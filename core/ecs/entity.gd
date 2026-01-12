class_name Entity
extends Node
## Base Entity class for the ECS framework.
## Entities are Node-based containers for components, identified by unique IDs.
## Entity references should be stored as IDs, not direct references.
## Format: TYPE_XXXXXXXX (e.g., UNIT_00012345)

## Signal emitted when entity is spawned
signal spawned()

## Signal emitted when entity is despawned
signal despawned()

## Signal emitted when a component is added
signal component_added(component_type: String)

## Signal emitted when a component is removed
signal component_removed(component_type: String)

## Unique numeric identifier for this entity
var id: int = -1

## Formatted entity ID string (e.g., UNIT_00012345)
var id_string: String = ""

## Dictionary mapping component type names to component instances
var _components: Dictionary = {}

## Whether this entity is active (inactive entities are skipped by systems)
var is_active: bool = true

## Entity type identifier for serialization and querying (PascalCase)
var entity_type: String = "Entity"

## Entity type enum value
var type_enum: EntityTypes.Type = EntityTypes.Type.CUSTOM

## Timestamp when entity was spawned (msec)
var spawn_time: int = 0

## Timestamp when entity was despawned (msec, 0 if still active)
var despawn_time: int = 0

## Whether entity has been spawned
var is_spawned: bool = false


func _init() -> void:
	pass


## Initialize entity with ID and type.
func initialize(entity_id: int, type: EntityTypes.Type = EntityTypes.Type.CUSTOM) -> void:
	id = entity_id
	type_enum = type
	entity_type = EntityTypes.get_type_name(type)
	id_string = EntityTypes.generate_id_string(type, entity_id)
	name = id_string  # Set node name for scene tree visibility


## Spawn the entity (activate and start lifecycle).
func spawn() -> void:
	if is_spawned:
		push_warning("Entity %s already spawned" % id_string)
		return

	is_spawned = true
	is_active = true
	spawn_time = Time.get_ticks_msec()
	despawn_time = 0

	# Call on_spawn for all components
	for component in _components.values():
		if component.has_method("on_spawn"):
			component.on_spawn(self)

	spawned.emit()


## Despawn the entity (deactivate and end lifecycle).
func despawn() -> void:
	if not is_spawned:
		return

	despawn_time = Time.get_ticks_msec()
	is_active = false
	is_spawned = false

	# Call on_despawn for all components
	for component in _components.values():
		if component.has_method("on_despawn"):
			component.on_despawn(self)

	despawned.emit()


## Get entity lifetime in milliseconds.
func get_lifetime_msec() -> int:
	if not is_spawned and despawn_time > 0:
		return despawn_time - spawn_time
	elif is_spawned:
		return Time.get_ticks_msec() - spawn_time
	return 0


## Add a component to this entity.
## Returns true if added successfully, false if component type already exists.
func add_component(component: Component) -> bool:
	var type_name: String = component.get_component_type()

	if _components.has(type_name):
		push_warning("Entity %s already has component: %s" % [id_string, type_name])
		return false

	if not component.validate():
		push_error("Component validation failed for: %s" % type_name)
		return false

	_components[type_name] = component
	component.entity_id = id

	# Call lifecycle hook
	component.on_attach(self)

	component_added.emit(type_name)
	return true


## Remove a component from this entity by type name.
## Returns the removed component, or null if not found.
func remove_component(type_name: String) -> Component:
	if not _components.has(type_name):
		return null

	var component: Component = _components[type_name]

	# Call lifecycle hook before removal
	component.on_detach(self)

	_components.erase(type_name)
	component.entity_id = -1

	component_removed.emit(type_name)
	return component


## Get a component by type name.
## Returns null if component not found.
func get_component(type_name: String) -> Component:
	return _components.get(type_name)


## Check if entity has a component of the given type.
func has_component(type_name: String) -> bool:
	return _components.has(type_name)


## Check if entity has all of the specified component types.
func has_components(type_names: Array[String]) -> bool:
	for type_name in type_names:
		if not _components.has(type_name):
			return false
	return true


## Get all component type names on this entity.
func get_component_types() -> Array[String]:
	var types: Array[String] = []
	for key in _components.keys():
		types.append(key)
	return types


## Get all components as an array.
func get_all_components() -> Array[Component]:
	var components: Array[Component] = []
	for component in _components.values():
		components.append(component)
	return components


## Get component count.
func get_component_count() -> int:
	return _components.size()


## Notify all components of an update (call on_update lifecycle hook).
func notify_components_update(delta: float) -> void:
	for component in _components.values():
		component.on_update(self, delta)


## Serialize entity to dictionary for saving/networking.
func to_dict() -> Dictionary:
	var components_data: Dictionary = {}
	for type_name in _components:
		var component: Component = _components[type_name]
		components_data[type_name] = component._to_dict()

	return {
		"id": id,
		"id_string": id_string,
		"entity_type": entity_type,
		"type_enum": type_enum,
		"is_active": is_active,
		"is_spawned": is_spawned,
		"spawn_time": spawn_time,
		"despawn_time": despawn_time,
		"components": components_data
	}


## Deserialize entity from dictionary.
## Note: Components must be reconstructed by EntityManager using ComponentRegistry.
static func from_dict(data: Dictionary) -> Entity:
	var entity := Entity.new()
	entity.id = data.get("id", -1)
	entity.id_string = data.get("id_string", "")
	entity.entity_type = data.get("entity_type", "Entity")
	entity.type_enum = data.get("type_enum", EntityTypes.Type.CUSTOM)
	entity.is_active = data.get("is_active", true)
	entity.is_spawned = data.get("is_spawned", false)
	entity.spawn_time = data.get("spawn_time", 0)
	entity.despawn_time = data.get("despawn_time", 0)
	entity.name = entity.id_string
	# Components are reconstructed by EntityManager
	return entity


## Clear all components from this entity.
func clear_components() -> void:
	for type_name in _components.keys():
		var component: Component = _components[type_name]
		component.on_detach(self)
		component.entity_id = -1
	_components.clear()


## Reset entity for reuse in object pool.
func reset() -> void:
	clear_components()
	id = -1
	id_string = ""
	entity_type = "Entity"
	type_enum = EntityTypes.Type.CUSTOM
	is_active = true
	is_spawned = false
	spawn_time = 0
	despawn_time = 0
	name = ""
