class_name EntityManager
extends RefCounted
## EntityManager handles entity lifecycle, pooling, and querying.
## Pre-allocates entity pools to avoid runtime allocation.
## Provides deterministic entity ID generation for multiplayer consistency.
## Works with Node-based Entity instances.

## Signal emitted when an entity is created
signal entity_created(entity: Entity)

## Signal emitted when an entity is destroyed
signal entity_destroyed(entity_id: int)

## Signal emitted when a component is added to an entity
signal component_added(entity_id: int, component_type: String)

## Signal emitted when a component is removed from an entity
signal component_removed(entity_id: int, component_type: String)

## Default pool size for pre-allocation
const DEFAULT_POOL_SIZE: int = 10000

## Maximum entities allowed (safety limit)
const MAX_ENTITIES: int = 100000

## Active entities indexed by ID
var _entities: Dictionary = {}

## Pool of inactive entities available for reuse
var _entity_pool: Array[Entity] = []

## Next entity ID to assign (deterministic counter)
var _next_entity_id: int = 1

## Seed for deterministic ID generation
var _id_seed: int = 0

## Component type to entity ID index for fast queries
## Maps component type name -> Array of entity IDs
var _component_index: Dictionary = {}

## Entity type to entity ID index
## Maps entity type name -> Array of entity IDs
var _type_index: Dictionary = {}

## Total entities created (including destroyed) for statistics
var _total_created: int = 0

## Performance tracking
var _last_query_time_usec: int = 0


func _init(pool_size: int = DEFAULT_POOL_SIZE, seed_value: int = 0) -> void:
	_id_seed = seed_value
	_next_entity_id = seed_value + 1
	_preallocate_pool(pool_size)


## Pre-allocate entity pool to avoid runtime allocation.
func _preallocate_pool(count: int) -> void:
	for i in range(count):
		var entity := Entity.new()
		_entity_pool.append(entity)


## Generate the next deterministic entity ID.
func _generate_entity_id() -> int:
	var id := _next_entity_id
	_next_entity_id += 1
	return id


## Create a new entity, reusing from pool if available.
## Returns the created entity.
func create_entity(type_name: String = "Entity") -> Entity:
	if _entities.size() >= MAX_ENTITIES:
		push_error("EntityManager: Maximum entity limit reached (%d)" % MAX_ENTITIES)
		return null

	var entity: Entity

	# Try to get from pool
	if _entity_pool.size() > 0:
		entity = _entity_pool.pop_back()
		entity.reset()
	else:
		entity = Entity.new()

	# Assign ID and type using EntityTypes
	var entity_id := _generate_entity_id()
	var type_enum := EntityTypes.get_type_from_name(type_name)
	entity.initialize(entity_id, type_enum)

	# Register entity
	_entities[entity.id] = entity
	_total_created += 1

	# Add to type index
	if not _type_index.has(type_name):
		_type_index[type_name] = []
	_type_index[type_name].append(entity.id)

	entity_created.emit(entity)
	return entity


## Create a new entity with specific EntityTypes.Type.
func create_typed_entity(type: EntityTypes.Type) -> Entity:
	var type_name := EntityTypes.get_type_name(type)
	return create_entity(type_name)


## Spawn an entity (activate lifecycle).
func spawn_entity(entity_id: int) -> bool:
	var entity := get_entity(entity_id)
	if entity == null:
		return false

	entity.spawn()
	return true


## Despawn an entity (deactivate lifecycle without destroying).
func despawn_entity(entity_id: int) -> bool:
	var entity := get_entity(entity_id)
	if entity == null:
		return false

	entity.despawn()
	return true


## Destroy an entity by ID, returning it to the pool.
## Returns true if entity was found and destroyed.
func destroy_entity(entity_id: int) -> bool:
	if not _entities.has(entity_id):
		return false

	var entity: Entity = _entities[entity_id]

	# Despawn if spawned
	if entity.is_spawned:
		entity.despawn()

	# Remove from component indices
	for component_type in entity.get_component_types():
		_remove_from_component_index(entity_id, component_type)

	# Remove from type index
	var type_name := entity.entity_type
	if _type_index.has(type_name):
		_type_index[type_name].erase(entity_id)

	# Remove from active entities
	_entities.erase(entity_id)

	# Return to pool
	entity.reset()
	_entity_pool.append(entity)

	entity_destroyed.emit(entity_id)
	return true


## Get an entity by ID.
## Returns null if not found.
func get_entity(entity_id: int) -> Entity:
	return _entities.get(entity_id)


## Check if an entity exists.
func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


## Get all active entities.
func get_all_entities() -> Array[Entity]:
	var entities: Array[Entity] = []
	for entity in _entities.values():
		entities.append(entity)
	return entities


## Get all spawned entities.
func get_spawned_entities() -> Array[Entity]:
	var entities: Array[Entity] = []
	for entity in _entities.values():
		if entity.is_spawned:
			entities.append(entity)
	return entities


## Get entity count.
func get_entity_count() -> int:
	return _entities.size()


## Get spawned entity count.
func get_spawned_count() -> int:
	var count := 0
	for entity in _entities.values():
		if entity.is_spawned:
			count += 1
	return count


## Get pool size.
func get_pool_size() -> int:
	return _entity_pool.size()


## Add a component to an entity.
## Returns true if successful.
func add_component(entity_id: int, component: Component) -> bool:
	var entity := get_entity(entity_id)
	if entity == null:
		push_error("EntityManager: Cannot add component to non-existent entity %d" % entity_id)
		return false

	if not entity.add_component(component):
		return false

	# Update component index
	var type_name := component.get_component_type()
	_add_to_component_index(entity_id, type_name)

	component_added.emit(entity_id, type_name)
	return true


## Remove a component from an entity by type.
## Returns the removed component or null.
func remove_component(entity_id: int, component_type: String) -> Component:
	var entity := get_entity(entity_id)
	if entity == null:
		return null

	var component := entity.remove_component(component_type)
	if component != null:
		_remove_from_component_index(entity_id, component_type)
		component_removed.emit(entity_id, component_type)

	return component


## Add entity to component index.
func _add_to_component_index(entity_id: int, component_type: String) -> void:
	if not _component_index.has(component_type):
		_component_index[component_type] = []
	if entity_id not in _component_index[component_type]:
		_component_index[component_type].append(entity_id)


## Remove entity from component index.
func _remove_from_component_index(entity_id: int, component_type: String) -> void:
	if _component_index.has(component_type):
		_component_index[component_type].erase(entity_id)


## Query entities that have ALL of the specified component types.
## Returns array of matching entities.
func query_entities(component_types: Array[String]) -> Array[Entity]:
	var start_time := Time.get_ticks_usec()
	var result: Array[Entity] = []

	if component_types.is_empty():
		_last_query_time_usec = Time.get_ticks_usec() - start_time
		return get_all_entities()

	# Find the smallest component index to iterate
	var smallest_type := ""
	var smallest_count := MAX_ENTITIES + 1

	for type_name in component_types:
		if not _component_index.has(type_name):
			_last_query_time_usec = Time.get_ticks_usec() - start_time
			return result  # No entities have this component

		var count: int = _component_index[type_name].size()
		if count < smallest_count:
			smallest_count = count
			smallest_type = type_name

	# Iterate smallest set and check for all components
	for entity_id in _component_index[smallest_type]:
		var entity := get_entity(entity_id)
		if entity != null and entity.is_active and entity.has_components(component_types):
			result.append(entity)

	_last_query_time_usec = Time.get_ticks_usec() - start_time
	return result


## Query entities by entity type.
func query_by_type(entity_type: String) -> Array[Entity]:
	var result: Array[Entity] = []

	if not _type_index.has(entity_type):
		return result

	for entity_id in _type_index[entity_type]:
		var entity := get_entity(entity_id)
		if entity != null and entity.is_active:
			result.append(entity)

	return result


## Query entities that have ANY of the specified component types.
func query_entities_any(component_types: Array[String]) -> Array[Entity]:
	var result: Array[Entity] = []
	var seen_ids: Dictionary = {}

	for type_name in component_types:
		if _component_index.has(type_name):
			for entity_id in _component_index[type_name]:
				if not seen_ids.has(entity_id):
					var entity := get_entity(entity_id)
					if entity != null and entity.is_active:
						result.append(entity)
						seen_ids[entity_id] = true

	return result


## Get the last query execution time in microseconds.
func get_last_query_time_usec() -> int:
	return _last_query_time_usec


## Serialize all entities to dictionary.
func to_dict() -> Dictionary:
	var entities_data: Array = []
	for entity in _entities.values():
		entities_data.append(entity.to_dict())

	return {
		"next_entity_id": _next_entity_id,
		"id_seed": _id_seed,
		"entities": entities_data
	}


## Deserialize entities from dictionary.
## Note: Requires ComponentRegistry for component reconstruction.
func from_dict(data: Dictionary, component_registry: ComponentRegistry = null) -> void:
	clear()

	_next_entity_id = data.get("next_entity_id", 1)
	_id_seed = data.get("id_seed", 0)

	var entities_data: Array = data.get("entities", [])
	for entity_data in entities_data:
		var entity := Entity.from_dict(entity_data)

		# Register entity
		_entities[entity.id] = entity

		# Add to type index
		if not _type_index.has(entity.entity_type):
			_type_index[entity.entity_type] = []
		_type_index[entity.entity_type].append(entity.id)

		# Reconstruct components if registry provided
		if component_registry != null:
			var components_data: Dictionary = entity_data.get("components", {})
			for type_name in components_data:
				var component := component_registry.create_component(type_name)
				if component != null:
					component._from_dict(components_data[type_name])
					entity.add_component(component)
					_add_to_component_index(entity.id, type_name)


## Clear all entities and reset state.
func clear() -> void:
	for entity in _entities.values():
		if entity.is_spawned:
			entity.despawn()
		entity.reset()
		_entity_pool.append(entity)

	_entities.clear()
	_component_index.clear()
	_type_index.clear()


## Reset manager to initial state with new seed.
func reset(seed_value: int = 0) -> void:
	clear()
	_id_seed = seed_value
	_next_entity_id = seed_value + 1
	_total_created = 0


# =============================================================================
# Batch Operations
# =============================================================================

## Create multiple entities of the same type.
## Returns array of created entities.
func batch_create_entities(type_name: String, count: int) -> Array[Entity]:
	var entities: Array[Entity] = []
	entities.resize(count)

	for i in range(count):
		var entity := create_entity(type_name)
		if entity != null:
			entities[i] = entity
		else:
			# Trim array if we hit the limit
			entities.resize(i)
			break

	return entities


## Destroy multiple entities by ID.
## Returns number of entities successfully destroyed.
func batch_destroy_entities(entity_ids: Array[int]) -> int:
	var destroyed := 0
	for entity_id in entity_ids:
		if destroy_entity(entity_id):
			destroyed += 1
	return destroyed


## Spawn multiple entities.
## Returns number of entities successfully spawned.
func batch_spawn_entities(entity_ids: Array[int]) -> int:
	var spawned := 0
	for entity_id in entity_ids:
		if spawn_entity(entity_id):
			spawned += 1
	return spawned


## Despawn multiple entities.
## Returns number of entities successfully despawned.
func batch_despawn_entities(entity_ids: Array[int]) -> int:
	var despawned := 0
	for entity_id in entity_ids:
		if despawn_entity(entity_id):
			despawned += 1
	return despawned


## Add the same component type to multiple entities.
## Factory is called for each entity to create a new component instance.
## Returns number of components successfully added.
func batch_add_component(entity_ids: Array[int], factory: Callable) -> int:
	var added := 0
	for entity_id in entity_ids:
		var component = factory.call()
		if component is Component:
			if add_component(entity_id, component):
				added += 1
	return added


## Remove a component type from multiple entities.
## Returns number of components successfully removed.
func batch_remove_component(entity_ids: Array[int], component_type: String) -> int:
	var removed := 0
	for entity_id in entity_ids:
		if remove_component(entity_id, component_type) != null:
			removed += 1
	return removed


## Get statistics about EntityManager state.
func get_stats() -> Dictionary:
	return {
		"entity_count": _entities.size(),
		"pool_size": _entity_pool.size(),
		"total_created": _total_created,
		"next_entity_id": _next_entity_id,
		"component_types_indexed": _component_index.size(),
		"entity_types_indexed": _type_index.size(),
		"last_query_time_usec": _last_query_time_usec
	}
