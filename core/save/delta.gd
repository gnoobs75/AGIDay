class_name Delta
extends RefCounted
## Delta tracks incremental changes between frames or snapshots.
## Used for deterministic replay and efficient save file storage.

## Change operation types
enum ChangeType {
	ADD = 0,      # Entity/component added
	REMOVE = 1,   # Entity/component removed
	MODIFY = 2,   # Value changed
	BATCH = 3     # Multiple changes grouped
}

## A single change record
class Change:
	var change_type: int = ChangeType.MODIFY
	var target_type: String = ""  # "entity", "component", "resource", "district"
	var target_id: String = ""
	var field_path: String = ""   # Dot-separated path (e.g., "health.current")
	var old_value: Variant = null
	var new_value: Variant = null

	func to_dict() -> Dictionary:
		return {
			"type": change_type,
			"target_type": target_type,
			"target_id": target_id,
			"field_path": field_path,
			"old_value": old_value,
			"new_value": new_value
		}

	static func from_dict(data: Dictionary) -> Change:
		var change := Change.new()
		change.change_type = data.get("type", ChangeType.MODIFY)
		change.target_type = data.get("target_type", "")
		change.target_id = data.get("target_id", "")
		change.field_path = data.get("field_path", "")
		change.old_value = data.get("old_value")
		change.new_value = data.get("new_value")
		return change


## Unique delta ID
var delta_id: int = 0

## Frame number this delta represents
var frame_number: int = 0

## Base snapshot ID this delta is relative to
var base_snapshot_id: int = 0

## Previous delta ID (for chain)
var previous_delta_id: int = -1

## Timestamp when delta was created
var timestamp: int = 0

## All changes in this delta
var changes: Array[Change] = []

## Compressed change data (for serialization)
var _compressed_changes: PackedByteArray = PackedByteArray()


func _init() -> void:
	timestamp = int(Time.get_unix_time_from_system())


## Add a change to this delta
func add_change(
	p_change_type: ChangeType,
	p_target_type: String,
	p_target_id: String,
	p_field_path: String = "",
	p_old_value: Variant = null,
	p_new_value: Variant = null
) -> void:
	var change := Change.new()
	change.change_type = p_change_type
	change.target_type = p_target_type
	change.target_id = p_target_id
	change.field_path = p_field_path
	change.old_value = p_old_value
	change.new_value = p_new_value
	changes.append(change)


## Record entity creation
func record_entity_added(entity_id: String, entity_data: Dictionary) -> void:
	add_change(ChangeType.ADD, "entity", entity_id, "", null, entity_data)


## Record entity destruction
func record_entity_removed(entity_id: String, entity_data: Dictionary) -> void:
	add_change(ChangeType.REMOVE, "entity", entity_id, "", entity_data, null)


## Record component change
func record_component_changed(
	entity_id: String,
	component_type: String,
	field: String,
	old_value: Variant,
	new_value: Variant
) -> void:
	add_change(ChangeType.MODIFY, "component", entity_id, "%s.%s" % [component_type, field], old_value, new_value)


## Record resource change
func record_resource_changed(resource_type: String, old_amount: float, new_amount: float) -> void:
	add_change(ChangeType.MODIFY, "resource", resource_type, "amount", old_amount, new_amount)


## Record district control change
func record_district_changed(district_id: String, old_faction: int, new_faction: int) -> void:
	add_change(ChangeType.MODIFY, "district", district_id, "faction", old_faction, new_faction)


## Get number of changes
func get_change_count() -> int:
	return changes.size()


## Check if delta is empty
func is_empty() -> bool:
	return changes.is_empty()


## Convert delta to dictionary for serialization
func to_dict() -> Dictionary:
	var changes_data: Array[Dictionary] = []
	for change in changes:
		changes_data.append(change.to_dict())

	return {
		"delta_id": delta_id,
		"frame_number": frame_number,
		"base_snapshot_id": base_snapshot_id,
		"previous_delta_id": previous_delta_id,
		"timestamp": timestamp,
		"changes": changes_data
	}


## Restore delta from dictionary
static func from_dict(data: Dictionary) -> Delta:
	var delta := Delta.new()
	delta.delta_id = data.get("delta_id", 0)
	delta.frame_number = data.get("frame_number", 0)
	delta.base_snapshot_id = data.get("base_snapshot_id", 0)
	delta.previous_delta_id = data.get("previous_delta_id", -1)
	delta.timestamp = data.get("timestamp", 0)

	var changes_data: Array = data.get("changes", [])
	for change_dict in changes_data:
		delta.changes.append(Change.from_dict(change_dict))

	return delta


## Apply this delta to a snapshot (forward)
func apply_to_snapshot(snapshot: Snapshot) -> Snapshot:
	var new_snapshot := snapshot.duplicate()

	for change in changes:
		_apply_change(new_snapshot, change)

	new_snapshot.frame_number = frame_number
	return new_snapshot


## Revert this delta from a snapshot (backward)
func revert_from_snapshot(snapshot: Snapshot) -> Snapshot:
	var new_snapshot := snapshot.duplicate()

	# Apply changes in reverse order using old values
	for i in range(changes.size() - 1, -1, -1):
		_revert_change(new_snapshot, changes[i])

	return new_snapshot


func _apply_change(snapshot: Snapshot, change: Change) -> void:
	match change.target_type:
		"entity":
			match change.change_type:
				ChangeType.ADD:
					snapshot.entities[change.target_id] = change.new_value
				ChangeType.REMOVE:
					snapshot.entities.erase(change.target_id)
				ChangeType.MODIFY:
					if snapshot.entities.has(change.target_id):
						_set_nested_value(snapshot.entities[change.target_id], change.field_path, change.new_value)

		"component":
			if snapshot.entities.has(change.target_id):
				_set_nested_value(snapshot.entities[change.target_id], change.field_path, change.new_value)

		"resource":
			snapshot.resources[change.target_id] = change.new_value

		"district":
			snapshot.district_control[change.target_id] = change.new_value


func _revert_change(snapshot: Snapshot, change: Change) -> void:
	match change.target_type:
		"entity":
			match change.change_type:
				ChangeType.ADD:
					snapshot.entities.erase(change.target_id)
				ChangeType.REMOVE:
					snapshot.entities[change.target_id] = change.old_value
				ChangeType.MODIFY:
					if snapshot.entities.has(change.target_id):
						_set_nested_value(snapshot.entities[change.target_id], change.field_path, change.old_value)

		"component":
			if snapshot.entities.has(change.target_id):
				_set_nested_value(snapshot.entities[change.target_id], change.field_path, change.old_value)

		"resource":
			snapshot.resources[change.target_id] = change.old_value

		"district":
			snapshot.district_control[change.target_id] = change.old_value


func _set_nested_value(dict: Dictionary, path: String, value: Variant) -> void:
	if path.is_empty():
		return

	var parts := path.split(".")
	var current := dict

	for i in range(parts.size() - 1):
		var key := parts[i]
		if not current.has(key):
			current[key] = {}
		current = current[key]

	if current is Dictionary:
		current[parts[-1]] = value


## Compare two snapshots and create a delta
static func create_from_snapshots(old_snapshot: Snapshot, new_snapshot: Snapshot) -> Delta:
	var delta := Delta.new()
	delta.base_snapshot_id = old_snapshot.snapshot_id
	delta.frame_number = new_snapshot.frame_number

	# Compare entities
	_compare_dictionaries(
		delta,
		"entity",
		old_snapshot.entities,
		new_snapshot.entities
	)

	# Compare resources
	for key in new_snapshot.resources:
		if not old_snapshot.resources.has(key):
			delta.add_change(ChangeType.ADD, "resource", key, "", null, new_snapshot.resources[key])
		elif old_snapshot.resources[key] != new_snapshot.resources[key]:
			delta.add_change(ChangeType.MODIFY, "resource", key, "amount", old_snapshot.resources[key], new_snapshot.resources[key])

	for key in old_snapshot.resources:
		if not new_snapshot.resources.has(key):
			delta.add_change(ChangeType.REMOVE, "resource", key, "", old_snapshot.resources[key], null)

	# Compare district control
	for key in new_snapshot.district_control:
		if not old_snapshot.district_control.has(key):
			delta.add_change(ChangeType.ADD, "district", key, "", null, new_snapshot.district_control[key])
		elif old_snapshot.district_control[key] != new_snapshot.district_control[key]:
			delta.add_change(ChangeType.MODIFY, "district", key, "faction", old_snapshot.district_control[key], new_snapshot.district_control[key])

	for key in old_snapshot.district_control:
		if not new_snapshot.district_control.has(key):
			delta.add_change(ChangeType.REMOVE, "district", key, "", old_snapshot.district_control[key], null)

	return delta


static func _compare_dictionaries(
	delta: Delta,
	target_type: String,
	old_dict: Dictionary,
	new_dict: Dictionary
) -> void:
	# Check for added/modified entries
	for key in new_dict:
		if not old_dict.has(key):
			delta.add_change(ChangeType.ADD, target_type, str(key), "", null, new_dict[key])
		elif old_dict[key] != new_dict[key]:
			# For entities, record the full new state
			delta.add_change(ChangeType.MODIFY, target_type, str(key), "", old_dict[key], new_dict[key])

	# Check for removed entries
	for key in old_dict:
		if not new_dict.has(key):
			delta.add_change(ChangeType.REMOVE, target_type, str(key), "", old_dict[key], null)


## Get approximate size in bytes
func get_size() -> int:
	var bytes := var_to_bytes(to_dict())
	return bytes.size()
