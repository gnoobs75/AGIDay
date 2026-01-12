class_name Component
extends Resource
## Base Component class for the ECS framework.
## Components store data only - behavior is handled by Systems.
## All components must be serializable for networking and persistence.
## Extends Resource for Godot's resource management and serialization.

## Component type identifier
@export var component_type: String = "Component"

## Component version for migration support
@export var version: int = 1

## ID of the entity this component belongs to (-1 if unattached)
var entity_id: int = -1

## Component data stored as dictionary for flexibility
var data: Dictionary = {}

## Types that are allowed in component data for serialization
const SERIALIZABLE_TYPES: Array = [
	TYPE_NIL,
	TYPE_BOOL,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_STRING,
	TYPE_VECTOR2,
	TYPE_VECTOR2I,
	TYPE_VECTOR3,
	TYPE_VECTOR3I,
	TYPE_COLOR,
	TYPE_ARRAY,
	TYPE_DICTIONARY,
	TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY,
	TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY,
]


func _init() -> void:
	pass


## Get the component type name for registration and queries.
## Override in subclasses to return a unique type identifier.
func get_component_type() -> String:
	return component_type


## Get the component version.
func get_version() -> int:
	return version


## Set a data value.
func set_value(key: String, value: Variant) -> void:
	data[key] = value


## Get a data value.
func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


## Check if a data key exists.
func has_value(key: String) -> bool:
	return data.has(key)


## Remove a data value.
func remove_value(key: String) -> bool:
	if data.has(key):
		data.erase(key)
		return true
	return false


# =============================================================================
# Lifecycle Hooks
# =============================================================================

## Called when component is attached to an entity.
## Override in subclasses to perform initialization.
func on_attach(entity: Node) -> void:
	pass


## Called when component is detached from an entity.
## Override in subclasses to perform cleanup.
func on_detach(entity: Node) -> void:
	pass


## Called when the entity is updated (per-frame or per-tick).
## Override in subclasses to handle data updates.
func on_update(entity: Node, delta: float) -> void:
	pass


## Called when the entity is spawned.
## Override in subclasses to handle spawn initialization.
func on_spawn(entity: Node) -> void:
	pass


## Called when the entity is despawned.
## Override in subclasses to handle despawn cleanup.
func on_despawn(entity: Node) -> void:
	pass


# =============================================================================
# Validation
# =============================================================================

## Validate that this component's data is serializable.
## Returns true if valid, false otherwise.
func validate() -> bool:
	return _validate_dict(data)


## Recursively validate a dictionary for serializable types.
func _validate_dict(dict_data: Dictionary, depth: int = 0) -> bool:
	if depth > 10:
		push_error("Component validation failed: circular reference or excessive nesting detected")
		return false

	for key in dict_data:
		if typeof(key) != TYPE_STRING:
			push_error("Component validation failed: dictionary keys must be strings")
			return false

		var value = dict_data[key]
		if not _validate_value(value, depth):
			push_error("Component validation failed for key: %s" % key)
			return false

	return true


## Validate a single value for serializability.
func _validate_value(value: Variant, depth: int = 0) -> bool:
	var value_type := typeof(value)

	if value_type == TYPE_DICTIONARY:
		return _validate_dict(value, depth + 1)

	if value_type == TYPE_ARRAY:
		for item in value:
			if not _validate_value(item, depth + 1):
				return false
		return true

	if value_type == TYPE_OBJECT:
		# Objects are not directly serializable unless they have _to_dict
		if value == null:
			return true
		if value.has_method("_to_dict"):
			return _validate_dict(value._to_dict(), depth + 1)
		push_error("Component validation failed: Object type must implement _to_dict()")
		return false

	return value_type in SERIALIZABLE_TYPES


# =============================================================================
# Serialization
# =============================================================================

## Serialize component data to dictionary.
## Override in subclasses to include component-specific data.
func _to_dict() -> Dictionary:
	return {
		"type": component_type,
		"version": version,
		"entity_id": entity_id,
		"data": data.duplicate(true)
	}


## Deserialize component data from dictionary.
## Override in subclasses to restore component-specific data.
func _from_dict(dict_data: Dictionary) -> void:
	component_type = dict_data.get("type", "Component")
	version = dict_data.get("version", 1)
	entity_id = dict_data.get("entity_id", -1)
	data = dict_data.get("data", {}).duplicate(true)


## Create a deep copy of this component.
func duplicate_component() -> Component:
	var dict_data := _to_dict()
	var new_component := Component.new()
	new_component._from_dict(dict_data)
	return new_component


## Reset component to default state for object pooling.
func reset() -> void:
	entity_id = -1
	data.clear()


## Get a string representation for debugging.
func _to_string() -> String:
	return "Component(%s v%d, entity=%d)" % [component_type, version, entity_id]
