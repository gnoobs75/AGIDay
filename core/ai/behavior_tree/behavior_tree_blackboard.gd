class_name BehaviorTreeBlackboard
extends RefCounted
## BehaviorTreeBlackboard manages state variables for behavior tree execution.
## Provides typed access to blackboard variables with change notifications.

signal variable_changed(key: String, old_value: Variant, new_value: Variant)
signal variable_added(key: String, value: Variant)
signal variable_removed(key: String)

## Internal storage
var _data: Dictionary = {}

## Variable metadata (type hints, descriptions)
var _metadata: Dictionary = {}

## Parent blackboard for hierarchical lookups
var parent_blackboard: BehaviorTreeBlackboard = null


func _init(p_parent: BehaviorTreeBlackboard = null) -> void:
	parent_blackboard = p_parent


## Set a variable value.
func set_var(key: String, value: Variant) -> void:
	var is_new := not _data.has(key)
	var old_value: Variant = _data.get(key)

	_data[key] = value

	if is_new:
		variable_added.emit(key, value)
	elif old_value != value:
		variable_changed.emit(key, old_value, value)


## Get a variable value.
func get_var(key: String, default: Variant = null) -> Variant:
	if _data.has(key):
		return _data[key]
	if parent_blackboard != null:
		return parent_blackboard.get_var(key, default)
	return default


## Check if a variable exists.
func has_var(key: String) -> bool:
	if _data.has(key):
		return true
	if parent_blackboard != null:
		return parent_blackboard.has_var(key)
	return false


## Remove a variable.
func remove_var(key: String) -> bool:
	if _data.has(key):
		_data.erase(key)
		_metadata.erase(key)
		variable_removed.emit(key)
		return true
	return false


## Clear all variables.
func clear() -> void:
	_data.clear()
	_metadata.clear()


## Set variable with metadata.
func set_var_with_meta(key: String, value: Variant, type_hint: int = TYPE_NIL, description: String = "") -> void:
	set_var(key, value)
	_metadata[key] = {
		"type_hint": type_hint,
		"description": description
	}


## Get variable metadata.
func get_var_meta(key: String) -> Dictionary:
	return _metadata.get(key, {})


## Get all variable keys.
func get_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in _data.keys():
		keys.append(str(key))
	return keys


## Get all data as dictionary.
func get_all_data() -> Dictionary:
	return _data.duplicate()


## Merge data from another blackboard.
func merge_from(other: BehaviorTreeBlackboard) -> void:
	for key in other._data:
		set_var(key, other._data[key])
		if other._metadata.has(key):
			_metadata[key] = other._metadata[key].duplicate()


## Create a child blackboard.
func create_child() -> BehaviorTreeBlackboard:
	return BehaviorTreeBlackboard.new(self)


# Common blackboard variable helpers

## Set unit ID.
func set_unit_id(id: int) -> void:
	set_var("unit_id", id)


## Get unit ID.
func get_unit_id() -> int:
	return get_var("unit_id", -1)


## Set faction ID.
func set_faction_id(id: int) -> void:
	set_var("faction_id", id)


## Get faction ID.
func get_faction_id() -> int:
	return get_var("faction_id", 0)


## Set target unit ID.
func set_target_id(id: int) -> void:
	set_var("target_id", id)


## Get target unit ID.
func get_target_id() -> int:
	return get_var("target_id", -1)


## Set target position.
func set_target_position(pos: Vector3) -> void:
	set_var("target_position", pos)


## Get target position.
func get_target_position() -> Vector3:
	return get_var("target_position", Vector3.ZERO)


## Set current action.
func set_current_action(action: String) -> void:
	set_var("current_action", action)


## Get current action.
func get_current_action() -> String:
	return get_var("current_action", "idle")


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var data_copy := {}
	for key in _data:
		var value = _data[key]
		# Handle Vector3 serialization
		if value is Vector3:
			data_copy[key] = {"_type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
		else:
			data_copy[key] = value

	return {
		"data": data_copy,
		"metadata": _metadata.duplicate(true)
	}


## Deserialize from dictionary.
static func from_dict(dict: Dictionary) -> BehaviorTreeBlackboard:
	var bb := BehaviorTreeBlackboard.new()

	var data: Dictionary = dict.get("data", {})
	for key in data:
		var value = data[key]
		# Handle Vector3 deserialization
		if value is Dictionary and value.get("_type") == "Vector3":
			bb._data[key] = Vector3(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0))
		else:
			bb._data[key] = value

	bb._metadata = dict.get("metadata", {}).duplicate(true)
	return bb
