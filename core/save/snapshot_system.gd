class_name SnapshotSystemClass
extends Node
## SnapshotSystem provides the high-level API for snapshot and delta operations.
## Integrates SnapshotManager with SaveManager for persistent storage.

signal snapshot_saved(snapshot_id: int, save_name: String)
signal snapshot_loaded(snapshot_id: int)
signal delta_applied(delta_id: int, target_frame: int)
signal state_reconstructed(frame_number: int)

## Reference to the internal snapshot manager
var _snapshot_manager: SnapshotManagerClass = null

## Reference to backup manager for corruption recovery
var _backup_manager: BackupManagerClass = null

## Cached snapshot data to avoid duplication
var _snapshot_cache: Dictionary = {}

## Maximum cache size in entries
const MAX_CACHE_SIZE: int = 5


func _ready() -> void:
	_snapshot_manager = SnapshotManager
	_backup_manager = BackupManagerClass.new()
	print("SnapshotSystem: Initialized")


## Create a new snapshot of the current game state
func create_snapshot(
	game_state: Dictionary,
	trigger: Snapshot.TriggerType = Snapshot.TriggerType.MANUAL
) -> Snapshot:
	# Create snapshot via manager
	var snapshot := _snapshot_manager.create_snapshot(game_state, trigger)

	# Cache the snapshot for efficient access
	_add_to_cache(snapshot)

	return snapshot


## Create wave completion snapshot
func create_wave_snapshot(game_state: Dictionary) -> Snapshot:
	return create_snapshot(game_state, Snapshot.TriggerType.WAVE_COMPLETE)


## Create timed snapshot (called every 5 minutes)
func create_timed_snapshot(game_state: Dictionary) -> Snapshot:
	return create_snapshot(game_state, Snapshot.TriggerType.TIMED)


## Load a snapshot by ID
func load_snapshot(snapshot_id: int) -> Snapshot:
	# Check cache first
	if _snapshot_cache.has(snapshot_id):
		return _snapshot_cache[snapshot_id]

	# Get from manager
	var snapshot := _snapshot_manager.get_snapshot(snapshot_id)
	if snapshot != null:
		_add_to_cache(snapshot)

	return snapshot


## Create a delta between two snapshots
func create_delta(old_snapshot: Snapshot, new_snapshot: Snapshot) -> Delta:
	return Delta.create_from_snapshots(old_snapshot, new_snapshot)


## Create a delta for the current frame
func create_frame_delta() -> Delta:
	return _snapshot_manager.begin_delta()


## Apply a delta to a snapshot
func apply_delta(snapshot: Snapshot, delta: Delta) -> Snapshot:
	var new_snapshot := delta.apply_to_snapshot(snapshot)
	delta_applied.emit(delta.delta_id, new_snapshot.frame_number)
	return new_snapshot


## Revert a delta from a snapshot
func revert_delta(snapshot: Snapshot, delta: Delta) -> Snapshot:
	return delta.revert_from_snapshot(snapshot)


## Get all available snapshots
func get_snapshots() -> Array[Snapshot]:
	return _snapshot_manager.get_all_snapshots()


## Get the latest snapshot
func get_latest_snapshot() -> Snapshot:
	return _snapshot_manager.get_latest_snapshot()


## Get snapshot count
func get_snapshot_count() -> int:
	return _snapshot_manager.get_snapshot_count()


## Reconstruct game state at a specific frame
func get_state_at_frame(frame_number: int) -> Dictionary:
	var state := _snapshot_manager.get_state_at_frame(frame_number)
	if not state.is_empty():
		state_reconstructed.emit(frame_number)
	return state


## Save current snapshots and deltas to a save file
func save_to_file(save_name: String, game_metadata: Dictionary = {}) -> SaveManagerClass.SaveResult:
	var export_data := _snapshot_manager.export_for_save()

	# Build complete game state for SaveManager
	var game_state := {
		"player_faction": game_metadata.get("player_faction", 0),
		"current_wave": _snapshot_manager.get_wave_number(),
		"difficulty": game_metadata.get("difficulty", 0),
		"game_time": _snapshot_manager.get_game_time(),
		"play_time": game_metadata.get("play_time", 0.0),
		"entity_count": 0,
		"entities": {},
		"systems": {},
		"world_state": {},
		"deltas": export_data.get("deltas", [])
	}

	# Get entity data from latest snapshot
	var latest := _snapshot_manager.get_latest_snapshot()
	if latest != null:
		game_state["entities"] = latest.entities
		game_state["entity_count"] = latest.get_entity_count()
		game_state["world_state"] = {
			"snapshot": export_data.get("snapshot", {}),
			"resources": latest.resources,
			"district_control": latest.district_control
		}

	# Save via SaveManager
	var result := SaveManager.save_game(save_name, game_state)

	if result.success:
		# Create backup
		_backup_manager.create_backup(save_name)
		snapshot_saved.emit(latest.snapshot_id if latest else 0, save_name)

	return result


## Load snapshots and deltas from a save file
func load_from_file(save_name: String) -> bool:
	# Validate and recover if needed
	var recovery := _backup_manager.validate_and_recover(save_name)
	if not recovery.get("original_valid", false) and not recovery.get("recovered", false):
		push_error("SnapshotSystem: Cannot load '%s' - file corrupted and no valid backup" % save_name)
		return false

	# Load via SaveManager
	var result := SaveManager.load_game(save_name)
	if not result.success:
		return false

	# Extract snapshot and delta data
	var world_state: Dictionary = result.snapshot.get("world_state", {})
	var snapshot_data: Dictionary = world_state.get("snapshot", {})

	# If no embedded snapshot, reconstruct from entities
	if snapshot_data.is_empty() and not result.snapshot.get("entities", {}).is_empty():
		snapshot_data = {
			"snapshot_id": 1,
			"frame_number": 0,
			"wave_number": result.metadata.current_wave if result.metadata else 0,
			"game_time": result.metadata.game_time_seconds if result.metadata else 0.0,
			"timestamp": result.metadata.modified_timestamp if result.metadata else 0,
			"trigger": Snapshot.TriggerType.MANUAL,
			"entities": result.snapshot.get("entities", {}),
			"resources": world_state.get("resources", {}),
			"district_control": world_state.get("district_control", {}),
			"system_states": result.snapshot.get("systems", {}),
			"world_state": {},
			"metadata": {}
		}

	# Load into snapshot manager
	_snapshot_manager.load_from_save_data(snapshot_data, result.deltas)

	var loaded_snapshot := _snapshot_manager.get_latest_snapshot()
	if loaded_snapshot != null:
		snapshot_loaded.emit(loaded_snapshot.snapshot_id)
		_add_to_cache(loaded_snapshot)

	return true


## Record entity added for delta tracking
func record_entity_added(entity_id: String, entity_data: Dictionary) -> void:
	_snapshot_manager.record_entity_added(entity_id, entity_data)


## Record entity removed for delta tracking
func record_entity_removed(entity_id: String, entity_data: Dictionary) -> void:
	_snapshot_manager.record_entity_removed(entity_id, entity_data)


## Record component change for delta tracking
func record_component_change(
	entity_id: String,
	component_type: String,
	field: String,
	old_value: Variant,
	new_value: Variant
) -> void:
	_snapshot_manager.record_component_changed(entity_id, component_type, field, old_value, new_value)


## Record resource change for delta tracking
func record_resource_change(resource_type: String, old_amount: float, new_amount: float) -> void:
	_snapshot_manager.record_resource_changed(resource_type, old_amount, new_amount)


## Record district control change for delta tracking
func record_district_change(district_id: String, old_faction: int, new_faction: int) -> void:
	_snapshot_manager.record_district_changed(district_id, old_faction, new_faction)


## Finalize current frame's delta
func finalize_frame_delta() -> void:
	_snapshot_manager.finalize_delta()


## Start tracking game state changes
func start_tracking() -> void:
	_snapshot_manager.start_tracking()


## Stop tracking game state changes
func stop_tracking() -> void:
	_snapshot_manager.stop_tracking()


## Set current wave number
func set_wave_number(wave: int) -> void:
	_snapshot_manager.set_wave_number(wave)


## Get current frame number
func get_frame_number() -> int:
	return _snapshot_manager.get_frame_number()


## Get current wave number
func get_wave_number() -> int:
	return _snapshot_manager.get_wave_number()


## Get current game time
func get_game_time() -> float:
	return _snapshot_manager.get_game_time()


## Check if should create timed snapshot
func should_create_timed_snapshot() -> bool:
	return _snapshot_manager.should_create_timed_snapshot()


## Get memory usage in MB
func get_memory_usage_mb() -> float:
	return _snapshot_manager.get_memory_usage_mb()


## Clear all snapshot and delta data
func clear() -> void:
	_snapshot_manager.clear()
	_snapshot_cache.clear()


## Add snapshot to cache with LRU eviction
func _add_to_cache(snapshot: Snapshot) -> void:
	# Evict oldest if at capacity
	while _snapshot_cache.size() >= MAX_CACHE_SIZE:
		var oldest_key = _snapshot_cache.keys()[0]
		_snapshot_cache.erase(oldest_key)

	_snapshot_cache[snapshot.snapshot_id] = snapshot


## Get all deltas since last snapshot
func get_pending_deltas() -> Array[Delta]:
	return _snapshot_manager.get_deltas_since_snapshot()


## Get delta by ID
func get_delta(delta_id: int) -> Delta:
	return _snapshot_manager.get_delta(delta_id)


## Get delta count
func get_delta_count() -> int:
	return _snapshot_manager.get_delta_count()


## Compact deltas by merging consecutive small deltas
func compact_deltas() -> int:
	var deltas := get_pending_deltas()
	if deltas.size() < 2:
		return 0

	var compacted := 0
	var merged_changes: Array[Delta.Change] = []
	var base_delta := deltas[0]

	for i in range(1, deltas.size()):
		var delta := deltas[i]

		# Merge small deltas
		if delta.get_change_count() < 10:
			for change in delta.changes:
				merged_changes.append(change)
			compacted += 1
		else:
			# Apply merged changes to base and reset
			if not merged_changes.is_empty():
				for change in merged_changes:
					base_delta.changes.append(change)
				merged_changes.clear()
			base_delta = delta

	return compacted


## Validate snapshot integrity
func validate_snapshot(snapshot: Snapshot) -> Dictionary:
	var result := {
		"valid": true,
		"entity_count": snapshot.get_entity_count(),
		"memory_size": snapshot.get_memory_size(),
		"issues": []
	}

	# Check for null entities
	for entity_id in snapshot.entities:
		var entity_data = snapshot.entities[entity_id]
		if entity_data == null:
			result["issues"].append("Null entity data for %s" % entity_id)
			result["valid"] = false

	# Check memory size
	if result["memory_size"] > SnapshotManagerClass.MAX_MEMORY_MB * 1024 * 1024:
		result["issues"].append("Snapshot exceeds memory limit")
		result["valid"] = false

	return result
