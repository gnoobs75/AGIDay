class_name StateSnapshot
extends RefCounted
## StateSnapshot handles state serialization, delta compression, and snapshot management.
## Sends full snapshots to new clients and delta-compressed updates to existing clients.

signal snapshot_created(snapshot_id: int)
signal snapshot_applied(snapshot_id: int)

## Configuration
const MAX_SNAPSHOT_HISTORY := 64    ## Keep last N snapshots for delta calculation
const COMPRESSION_LEVEL := 6        ## zlib compression level (0-9)

## Snapshot metadata
var _snapshot_counter := 0
var _snapshot_history: Array[Dictionary] = []
var _last_acked_snapshot: Dictionary = {}  ## peer_id -> last_acked_snapshot_id

## Entity state tracking
var _entity_states: Dictionary = {}     ## entity_id -> state_dict
var _previous_states: Dictionary = {}   ## entity_id -> previous_state_dict

## Critical fields that must always be synced
const CRITICAL_FIELDS := ["health", "position", "alive", "faction_id"]


func _init() -> void:
	pass


## Register an entity for state tracking.
func register_entity(entity_id: int, initial_state: Dictionary) -> void:
	_entity_states[entity_id] = initial_state.duplicate(true)
	_previous_states[entity_id] = initial_state.duplicate(true)


## Unregister an entity.
func unregister_entity(entity_id: int) -> void:
	_entity_states.erase(entity_id)
	_previous_states.erase(entity_id)


## Update entity state.
func update_entity_state(entity_id: int, state: Dictionary) -> void:
	if not _entity_states.has(entity_id):
		register_entity(entity_id, state)
		return

	_previous_states[entity_id] = _entity_states[entity_id].duplicate(true)
	_entity_states[entity_id] = state.duplicate(true)


## Create a full snapshot (for new clients).
func create_full_snapshot() -> PackedByteArray:
	var snapshot := {
		"id": _snapshot_counter,
		"timestamp": Time.get_ticks_msec(),
		"type": "full",
		"entities": _entity_states.duplicate(true),
		"global_state": _get_global_state()
	}

	_snapshot_counter += 1
	_add_to_history(snapshot)
	snapshot_created.emit(snapshot["id"])

	return _compress_snapshot(snapshot)


## Create a delta snapshot (for existing clients).
func create_snapshot() -> Dictionary:
	var snapshot := {
		"id": _snapshot_counter,
		"timestamp": Time.get_ticks_msec(),
		"type": "delta",
		"changes": _calculate_delta(),
		"removed": _get_removed_entities()
	}

	_snapshot_counter += 1
	_add_to_history(snapshot)
	snapshot_created.emit(snapshot["id"])

	return snapshot


## Compress delta snapshot for transmission.
func compress_delta(snapshot: Dictionary) -> PackedByteArray:
	return _compress_snapshot(snapshot)


## Calculate delta between current and previous states.
func _calculate_delta() -> Dictionary:
	var delta := {}

	for entity_id in _entity_states:
		if not _previous_states.has(entity_id):
			# New entity - send full state
			delta[entity_id] = _entity_states[entity_id].duplicate(true)
			continue

		var current: Dictionary = _entity_states[entity_id]
		var previous: Dictionary = _previous_states[entity_id]
		var entity_delta := _calculate_entity_delta(current, previous)

		if not entity_delta.is_empty():
			delta[entity_id] = entity_delta

	return delta


## Calculate delta for a single entity.
func _calculate_entity_delta(current: Dictionary, previous: Dictionary) -> Dictionary:
	var delta := {}

	for key in current:
		# Always include critical fields
		if key in CRITICAL_FIELDS:
			if not previous.has(key) or current[key] != previous[key]:
				delta[key] = current[key]
			continue

		# Check for changes in non-critical fields
		if not previous.has(key):
			delta[key] = current[key]
		elif _values_differ(current[key], previous[key]):
			delta[key] = current[key]

	return delta


## Check if two values differ (handles nested structures).
func _values_differ(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return true

	if a is Dictionary:
		if a.size() != b.size():
			return true
		for key in a:
			if not b.has(key) or _values_differ(a[key], b[key]):
				return true
		return false

	if a is Array:
		if a.size() != b.size():
			return true
		for i in a.size():
			if _values_differ(a[i], b[i]):
				return true
		return false

	if a is Vector3:
		return not a.is_equal_approx(b)

	if a is Vector2:
		return not a.is_equal_approx(b)

	if a is float:
		return not is_equal_approx(a, b)

	return a != b


## Get removed entities since last snapshot.
func _get_removed_entities() -> Array[int]:
	var removed: Array[int] = []

	for entity_id in _previous_states:
		if not _entity_states.has(entity_id):
			removed.append(entity_id)

	return removed


## Get global game state.
func _get_global_state() -> Dictionary:
	# Override in subclass to include game-specific global state
	return {
		"network_time": Time.get_ticks_msec()
	}


## Compress snapshot to bytes.
func _compress_snapshot(snapshot: Dictionary) -> PackedByteArray:
	var json_string := JSON.stringify(snapshot)
	var raw_bytes := json_string.to_utf8_buffer()
	return raw_bytes.compress(FileAccess.COMPRESSION_ZSTD)


## Decompress snapshot from bytes.
func decompress_snapshot(data: PackedByteArray) -> Dictionary:
	var decompressed := data.decompress_dynamic(-1, FileAccess.COMPRESSION_ZSTD)
	var json_string := decompressed.get_string_from_utf8()
	var parsed := JSON.parse_string(json_string)

	if parsed is Dictionary:
		return parsed
	return {}


## Apply received snapshot.
func apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.get("type") == "full":
		_apply_full_snapshot(snapshot)
	else:
		_apply_delta_snapshot(snapshot)

	snapshot_applied.emit(snapshot.get("id", 0))


## Apply full snapshot.
func _apply_full_snapshot(snapshot: Dictionary) -> void:
	_entity_states.clear()
	_previous_states.clear()

	var entities: Dictionary = snapshot.get("entities", {})
	for entity_id_str in entities:
		var entity_id := int(entity_id_str)
		_entity_states[entity_id] = entities[entity_id_str]
		_previous_states[entity_id] = entities[entity_id_str].duplicate(true)


## Apply delta snapshot.
func _apply_delta_snapshot(snapshot: Dictionary) -> void:
	# Apply changes
	var changes: Dictionary = snapshot.get("changes", {})
	for entity_id_str in changes:
		var entity_id := int(entity_id_str)
		var entity_changes: Dictionary = changes[entity_id_str]

		if _entity_states.has(entity_id):
			# Merge changes into existing state
			_previous_states[entity_id] = _entity_states[entity_id].duplicate(true)
			for key in entity_changes:
				_entity_states[entity_id][key] = entity_changes[key]
		else:
			# New entity
			_entity_states[entity_id] = entity_changes
			_previous_states[entity_id] = entity_changes.duplicate(true)

	# Remove entities
	var removed: Array = snapshot.get("removed", [])
	for entity_id in removed:
		_entity_states.erase(entity_id)
		_previous_states.erase(entity_id)


## Add snapshot to history.
func _add_to_history(snapshot: Dictionary) -> void:
	_snapshot_history.append(snapshot)

	# Limit history size
	while _snapshot_history.size() > MAX_SNAPSHOT_HISTORY:
		_snapshot_history.pop_front()


## Get snapshot from history by ID.
func get_snapshot_from_history(snapshot_id: int) -> Dictionary:
	for snapshot in _snapshot_history:
		if snapshot.get("id") == snapshot_id:
			return snapshot
	return {}


## Record acknowledged snapshot for a peer.
func record_ack(peer_id: int, snapshot_id: int) -> void:
	_last_acked_snapshot[peer_id] = snapshot_id


## Get last acknowledged snapshot for a peer.
func get_last_acked(peer_id: int) -> int:
	return _last_acked_snapshot.get(peer_id, 0)


## Get entity state.
func get_entity_state(entity_id: int) -> Dictionary:
	return _entity_states.get(entity_id, {})


## Get all entity states.
func get_all_states() -> Dictionary:
	return _entity_states.duplicate(true)


## Get snapshot statistics.
func get_stats() -> Dictionary:
	var total_entities := _entity_states.size()
	var history_size := _snapshot_history.size()
	var avg_delta_size := 0

	if history_size > 0:
		var total_changes := 0
		for snapshot in _snapshot_history:
			if snapshot.get("type") == "delta":
				total_changes += snapshot.get("changes", {}).size()
		avg_delta_size = total_changes / history_size

	return {
		"total_entities": total_entities,
		"snapshot_counter": _snapshot_counter,
		"history_size": history_size,
		"avg_delta_size": avg_delta_size
	}


## Clear all state.
func clear() -> void:
	_entity_states.clear()
	_previous_states.clear()
	_snapshot_history.clear()
	_last_acked_snapshot.clear()
	_snapshot_counter = 0
