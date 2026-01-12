class_name SnapshotManagerClass
extends Node
## SnapshotManager handles snapshot and delta lifecycle.
## Creates snapshots at wave completion, timed intervals, and tracks frame deltas.

signal snapshot_created(snapshot: Snapshot)
signal delta_created(delta: Delta)
signal snapshot_cleaned(snapshot_id: int)
signal memory_warning(current_mb: float, max_mb: float)

## Maximum number of snapshots to retain
const MAX_SNAPSHOTS: int = 10

## Timed snapshot interval in seconds
const TIMED_SNAPSHOT_INTERVAL: float = 300.0  # 5 minutes

## Maximum memory for snapshots in MB
const MAX_MEMORY_MB: float = 500.0

## Target frame rate for delta tracking
const TARGET_FRAME_RATE: int = 60

## All stored snapshots (snapshot_id -> Snapshot)
var _snapshots: Dictionary = {}

## Snapshot order for cleanup (oldest first)
var _snapshot_order: Array[int] = []

## Current delta being built
var _current_delta: Delta = null

## All deltas since last snapshot (delta_id -> Delta)
var _deltas: Dictionary = {}

## Next snapshot ID
var _next_snapshot_id: int = 1

## Next delta ID
var _next_delta_id: int = 1

## Current frame number
var _frame_number: int = 0

## Current wave number
var _wave_number: int = 0

## Current game time
var _game_time: float = 0.0

## Time since last timed snapshot
var _time_since_snapshot: float = 0.0

## Is tracking enabled
var _tracking_enabled: bool = false

## Latest snapshot reference
var _latest_snapshot: Snapshot = null


func _ready() -> void:
	print("SnapshotManager: Initialized")


func _process(delta: float) -> void:
	if not _tracking_enabled:
		return

	_game_time += delta
	_time_since_snapshot += delta

	# Check for timed snapshot
	if _time_since_snapshot >= TIMED_SNAPSHOT_INTERVAL:
		_time_since_snapshot = 0.0
		# Note: Actual snapshot creation should be triggered by game code
		# with current state, this just tracks time


func _physics_process(_delta: float) -> void:
	if _tracking_enabled:
		_frame_number += 1


## Start tracking game state
func start_tracking() -> void:
	_tracking_enabled = true
	_frame_number = 0
	_game_time = 0.0
	_time_since_snapshot = 0.0
	print("SnapshotManager: Tracking started")


## Stop tracking game state
func stop_tracking() -> void:
	_tracking_enabled = false
	print("SnapshotManager: Tracking stopped")


## Set current wave number
func set_wave_number(wave: int) -> void:
	_wave_number = wave


## Get current frame number
func get_frame_number() -> int:
	return _frame_number


## Get current wave number
func get_wave_number() -> int:
	return _wave_number


## Get current game time
func get_game_time() -> float:
	return _game_time


## Check if should create timed snapshot
func should_create_timed_snapshot() -> bool:
	return _time_since_snapshot >= TIMED_SNAPSHOT_INTERVAL


## Reset timed snapshot timer
func reset_snapshot_timer() -> void:
	_time_since_snapshot = 0.0


## Create a new snapshot from game state
func create_snapshot(
	game_state: Dictionary,
	trigger: Snapshot.TriggerType = Snapshot.TriggerType.MANUAL
) -> Snapshot:
	var snapshot := Snapshot.create_from_state(
		game_state,
		_frame_number,
		_wave_number,
		_game_time,
		trigger
	)
	snapshot.snapshot_id = _next_snapshot_id
	_next_snapshot_id += 1

	# Store snapshot
	_snapshots[snapshot.snapshot_id] = snapshot
	_snapshot_order.append(snapshot.snapshot_id)
	_latest_snapshot = snapshot

	# Clear deltas for previous snapshot
	_deltas.clear()
	_current_delta = null

	# Cleanup old snapshots
	_cleanup_old_snapshots()

	# Check memory usage
	_check_memory_usage()

	snapshot_created.emit(snapshot)
	print("SnapshotManager: Created snapshot %d (frame %d, wave %d)" % [
		snapshot.snapshot_id, snapshot.frame_number, snapshot.wave_number
	])

	# Reset timed snapshot timer
	reset_snapshot_timer()

	return snapshot


## Create snapshot at wave completion
func create_wave_snapshot(game_state: Dictionary) -> Snapshot:
	return create_snapshot(game_state, Snapshot.TriggerType.WAVE_COMPLETE)


## Create timed snapshot
func create_timed_snapshot(game_state: Dictionary) -> Snapshot:
	return create_snapshot(game_state, Snapshot.TriggerType.TIMED)


## Start a new delta for the current frame
func begin_delta() -> Delta:
	if _current_delta != null and not _current_delta.is_empty():
		# Finalize previous delta
		finalize_delta()

	_current_delta = Delta.new()
	_current_delta.delta_id = _next_delta_id
	_current_delta.frame_number = _frame_number
	_current_delta.base_snapshot_id = _latest_snapshot.snapshot_id if _latest_snapshot else 0

	if _deltas.size() > 0:
		_current_delta.previous_delta_id = _next_delta_id - 1

	return _current_delta


## Get current delta (creates one if needed)
func get_current_delta() -> Delta:
	if _current_delta == null:
		begin_delta()
	return _current_delta


## Finalize current delta and store it
func finalize_delta() -> void:
	if _current_delta == null or _current_delta.is_empty():
		_current_delta = null
		return

	_deltas[_current_delta.delta_id] = _current_delta
	_next_delta_id += 1

	delta_created.emit(_current_delta)
	_current_delta = null


## Record entity added
func record_entity_added(entity_id: String, entity_data: Dictionary) -> void:
	get_current_delta().record_entity_added(entity_id, entity_data)


## Record entity removed
func record_entity_removed(entity_id: String, entity_data: Dictionary) -> void:
	get_current_delta().record_entity_removed(entity_id, entity_data)


## Record component changed
func record_component_changed(
	entity_id: String,
	component_type: String,
	field: String,
	old_value: Variant,
	new_value: Variant
) -> void:
	get_current_delta().record_component_changed(entity_id, component_type, field, old_value, new_value)


## Record resource changed
func record_resource_changed(resource_type: String, old_amount: float, new_amount: float) -> void:
	get_current_delta().record_resource_changed(resource_type, old_amount, new_amount)


## Record district changed
func record_district_changed(district_id: String, old_faction: int, new_faction: int) -> void:
	get_current_delta().record_district_changed(district_id, old_faction, new_faction)


## Get latest snapshot
func get_latest_snapshot() -> Snapshot:
	return _latest_snapshot


## Get snapshot by ID
func get_snapshot(snapshot_id: int) -> Snapshot:
	return _snapshots.get(snapshot_id)


## Get all snapshots
func get_all_snapshots() -> Array[Snapshot]:
	var result: Array[Snapshot] = []
	for id in _snapshot_order:
		if _snapshots.has(id):
			result.append(_snapshots[id])
	return result


## Get all deltas since last snapshot
func get_deltas_since_snapshot() -> Array[Delta]:
	var result: Array[Delta] = []
	for id in _deltas:
		result.append(_deltas[id])
	return result


## Get delta by ID
func get_delta(delta_id: int) -> Delta:
	return _deltas.get(delta_id)


## Get snapshot count
func get_snapshot_count() -> int:
	return _snapshots.size()


## Get delta count
func get_delta_count() -> int:
	return _deltas.size()


## Reconstruct game state at a specific frame
func get_state_at_frame(target_frame: int) -> Dictionary:
	if _latest_snapshot == null:
		return {}

	# Find the closest snapshot at or before target frame
	var base_snapshot: Snapshot = null
	for id in _snapshot_order:
		var snapshot: Snapshot = _snapshots.get(id)
		if snapshot and snapshot.frame_number <= target_frame:
			base_snapshot = snapshot
		else:
			break

	if base_snapshot == null:
		return {}

	# Start with base snapshot
	var result := base_snapshot.duplicate()

	# Apply deltas up to target frame
	var sorted_delta_ids := _deltas.keys()
	sorted_delta_ids.sort()

	for delta_id in sorted_delta_ids:
		var delta: Delta = _deltas[delta_id]
		if delta.base_snapshot_id == base_snapshot.snapshot_id:
			if delta.frame_number <= target_frame:
				result = delta.apply_to_snapshot(result)
			else:
				break

	return result.to_dict()


## Clear all snapshots and deltas
func clear() -> void:
	_snapshots.clear()
	_snapshot_order.clear()
	_deltas.clear()
	_current_delta = null
	_latest_snapshot = null
	_next_snapshot_id = 1
	_next_delta_id = 1
	_frame_number = 0
	_game_time = 0.0
	_time_since_snapshot = 0.0
	print("SnapshotManager: Cleared all data")


## Load snapshots and deltas from save data
func load_from_save_data(snapshot_data: Dictionary, delta_data: Array[Dictionary]) -> void:
	clear()

	if snapshot_data.has("snapshot_id"):
		var snapshot := Snapshot.from_dict(snapshot_data)
		_snapshots[snapshot.snapshot_id] = snapshot
		_snapshot_order.append(snapshot.snapshot_id)
		_latest_snapshot = snapshot
		_next_snapshot_id = snapshot.snapshot_id + 1
		_frame_number = snapshot.frame_number
		_wave_number = snapshot.wave_number
		_game_time = snapshot.game_time

	for delta_dict in delta_data:
		var delta := Delta.from_dict(delta_dict)
		_deltas[delta.delta_id] = delta
		_next_delta_id = maxi(_next_delta_id, delta.delta_id + 1)

	print("SnapshotManager: Loaded %d snapshots, %d deltas" % [_snapshots.size(), _deltas.size()])


## Export current state for saving
func export_for_save() -> Dictionary:
	var snapshot_data := {}
	if _latest_snapshot != null:
		snapshot_data = _latest_snapshot.to_dict()

	var delta_list: Array[Dictionary] = []
	for delta_id in _deltas:
		delta_list.append(_deltas[delta_id].to_dict())

	return {
		"snapshot": snapshot_data,
		"deltas": delta_list,
		"frame_number": _frame_number,
		"wave_number": _wave_number,
		"game_time": _game_time
	}


## Cleanup old snapshots beyond MAX_SNAPSHOTS
func _cleanup_old_snapshots() -> void:
	while _snapshot_order.size() > MAX_SNAPSHOTS:
		var oldest_id := _snapshot_order.pop_front()
		_snapshots.erase(oldest_id)
		snapshot_cleaned.emit(oldest_id)
		print("SnapshotManager: Cleaned up snapshot %d" % oldest_id)


## Check memory usage and warn if high
func _check_memory_usage() -> void:
	var total_size := 0

	for id in _snapshots:
		var snapshot: Snapshot = _snapshots[id]
		total_size += snapshot.get_memory_size()

	for id in _deltas:
		var delta: Delta = _deltas[id]
		total_size += delta.get_size()

	var size_mb := float(total_size) / (1024 * 1024)

	if size_mb > MAX_MEMORY_MB * 0.8:
		memory_warning.emit(size_mb, MAX_MEMORY_MB)
		push_warning("SnapshotManager: Memory usage at %.1f MB (%.0f%% of limit)" % [
			size_mb, (size_mb / MAX_MEMORY_MB) * 100
		])


## Get current memory usage in MB
func get_memory_usage_mb() -> float:
	var total_size := 0

	for id in _snapshots:
		var snapshot: Snapshot = _snapshots[id]
		total_size += snapshot.get_memory_size()

	for id in _deltas:
		var delta: Delta = _deltas[id]
		total_size += delta.get_size()

	return float(total_size) / (1024 * 1024)
