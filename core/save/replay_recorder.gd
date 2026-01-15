class_name ReplayRecorder
extends RefCounted
## ReplayRecorder manages automatic game state capture for deterministic replay.
## Captures snapshots every 10 frames and integrates with victory/defeat events.

signal recording_started(replay_id: String)
signal snapshot_captured(frame: int, snapshot_count: int)
signal critical_event_recorded(event_type: String, frame: int)
signal recording_stopped(replay_id: String, statistics: Dictionary)
signal replay_saved(file_path: String, success: bool)
signal save_progress(percent: float)

## Capture configuration
const SNAPSHOT_INTERVAL := 10           ## Frames between snapshots
const MAX_SNAPSHOTS := 10000            ## Max snapshots to prevent memory issues
const CAPTURE_BUDGET_MS := 1.0          ## Max time for capture per frame
const KEYFRAME_INTERVAL := 100          ## Full snapshot every N frames

## Replay file format
const REPLAY_VERSION := 1
## "AGID" magic bytes - initialized at runtime since PackedByteArray is not a constant expression
static var REPLAY_MAGIC: PackedByteArray = PackedByteArray([0x41, 0x47, 0x49, 0x44])
const REPLAY_EXTENSION := ".agidreplay"
const REPLAY_DIR := "user://replays/"

## Recording state
var _is_recording: bool = false
var _replay_id: String = ""
var _current_frame: int = 0
var _start_frame: int = 0

## Deterministic seeds
var _game_seed: int = 0
var _map_seed: int = 0

## Game metadata
var _factions: Array[String] = []
var _player_faction: String = ""
var _game_start_time: int = 0
var _difficulty: int = 1

## Snapshot storage
var _base_snapshot: Snapshot = null
var _keyframes: Array[Snapshot] = []
var _incremental_snapshots: Array[Dictionary] = []  ## Minimal data between keyframes

## Critical events log
var _critical_events: Array[Dictionary] = []

## Victory data
var _victory_faction: String = ""
var _victory_time: float = 0.0
var _victory_type: String = ""
var _final_wave: int = 0

## Performance tracking
var _total_capture_time_ms: float = 0.0
var _captures_performed: int = 0
var _last_capture_time_ms: float = 0.0

## Async save state
var _is_saving: bool = false


func _init() -> void:
	pass


## Start recording a new replay.
func start_recording(game_seed: int, map_seed: int, factions: Array[String],
					  player_faction: String, difficulty: int = 1) -> void:
	if _is_recording:
		stop_recording()

	_is_recording = true
	_replay_id = _generate_replay_id()
	_current_frame = 0
	_start_frame = 0

	# Store seeds for determinism
	_game_seed = game_seed
	_map_seed = map_seed

	# Store metadata
	_factions = factions.duplicate()
	_player_faction = player_faction
	_difficulty = difficulty
	_game_start_time = int(Time.get_unix_time_from_system())

	# Clear storage
	_base_snapshot = null
	_keyframes.clear()
	_incremental_snapshots.clear()
	_critical_events.clear()

	# Clear victory data
	_victory_faction = ""
	_victory_time = 0.0
	_victory_type = ""
	_final_wave = 0

	# Reset performance counters
	_total_capture_time_ms = 0.0
	_captures_performed = 0

	recording_started.emit(_replay_id)


## Process frame (call every frame during gameplay).
func process_frame(frame: int, game_state_getter: Callable) -> void:
	if not _is_recording:
		return

	_current_frame = frame

	# Check if we need to capture
	if frame % SNAPSHOT_INTERVAL != 0:
		return

	var start_time := Time.get_ticks_usec()

	# Determine if this is a keyframe
	var is_keyframe := (frame % KEYFRAME_INTERVAL == 0)

	if _base_snapshot == null:
		# First snapshot is always the base
		_capture_base_snapshot(frame, game_state_getter)
	elif is_keyframe:
		_capture_keyframe(frame, game_state_getter)
	else:
		_capture_incremental(frame, game_state_getter)

	# Track performance
	_last_capture_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
	_total_capture_time_ms += _last_capture_time_ms
	_captures_performed += 1

	var total_snapshots := 1 + _keyframes.size() + _incremental_snapshots.size()
	snapshot_captured.emit(frame, total_snapshots)


## Capture base snapshot (first frame).
func _capture_base_snapshot(frame: int, game_state_getter: Callable) -> void:
	var game_state: Dictionary = game_state_getter.call()
	_base_snapshot = Snapshot.create_from_state(
		game_state,
		frame,
		game_state.get("wave_number", 0),
		game_state.get("game_time", 0.0),
		Snapshot.TriggerType.CHECKPOINT
	)
	_start_frame = frame


## Capture keyframe (full snapshot).
func _capture_keyframe(frame: int, game_state_getter: Callable) -> void:
	if _keyframes.size() >= MAX_SNAPSHOTS / 10:
		return  ## Prevent memory issues

	var game_state: Dictionary = game_state_getter.call()
	var snapshot := Snapshot.create_from_state(
		game_state,
		frame,
		game_state.get("wave_number", 0),
		game_state.get("game_time", 0.0),
		Snapshot.TriggerType.CHECKPOINT
	)
	_keyframes.append(snapshot)


## Capture incremental snapshot (minimal data).
func _capture_incremental(frame: int, game_state_getter: Callable) -> void:
	if _incremental_snapshots.size() >= MAX_SNAPSHOTS:
		return  ## Prevent memory issues

	var game_state: Dictionary = game_state_getter.call()

	# Store minimal data needed for replay
	var incremental := {
		"frame": frame,
		"game_time": game_state.get("game_time", 0.0),
		"wave": game_state.get("wave_number", 0),
		# Store only positions and critical state changes
		"unit_positions": _extract_unit_positions(game_state),
		"resource_levels": game_state.get("resources", {}).duplicate(),
		"district_control": game_state.get("district_control", {}).duplicate()
	}

	_incremental_snapshots.append(incremental)


## Extract unit positions from game state.
func _extract_unit_positions(game_state: Dictionary) -> Dictionary:
	var positions := {}
	var entities: Dictionary = game_state.get("entities", {})

	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if entity.has("position"):
			positions[entity_id] = {
				"x": entity["position"].get("x", 0.0),
				"y": entity["position"].get("y", 0.0),
				"z": entity["position"].get("z", 0.0)
			}

	return positions


## Record a critical event.
func record_critical_event(event_type: String, data: Dictionary) -> void:
	if not _is_recording:
		return

	var event := {
		"type": event_type,
		"frame": _current_frame,
		"timestamp": Time.get_ticks_msec(),
		"data": data.duplicate()
	}

	_critical_events.append(event)
	critical_event_recorded.emit(event_type, _current_frame)


## Record unit spawn.
func record_unit_spawn(unit_id: int, unit_type: String, faction: String, position: Vector3) -> void:
	record_critical_event("unit_spawn", {
		"unit_id": unit_id,
		"unit_type": unit_type,
		"faction": faction,
		"position": {"x": position.x, "y": position.y, "z": position.z}
	})


## Record unit death.
func record_unit_death(unit_id: int, killer_id: int, position: Vector3) -> void:
	record_critical_event("unit_death", {
		"unit_id": unit_id,
		"killer_id": killer_id,
		"position": {"x": position.x, "y": position.y, "z": position.z}
	})


## Record building construction.
func record_building_constructed(building_id: int, building_type: String, faction: String, position: Vector3) -> void:
	record_critical_event("building_constructed", {
		"building_id": building_id,
		"building_type": building_type,
		"faction": faction,
		"position": {"x": position.x, "y": position.y, "z": position.z}
	})


## Record building destruction.
func record_building_destroyed(building_id: int, destroyer_faction: String) -> void:
	record_critical_event("building_destroyed", {
		"building_id": building_id,
		"destroyer_faction": destroyer_faction
	})


## Record research completion.
func record_research_completed(faction: String, research_id: String) -> void:
	record_critical_event("research_completed", {
		"faction": faction,
		"research_id": research_id
	})


## Record victory.
func record_victory(faction: String, victory_type: String, game_time: float, wave: int) -> void:
	_victory_faction = faction
	_victory_type = victory_type
	_victory_time = game_time
	_final_wave = wave

	record_critical_event("victory", {
		"faction": faction,
		"victory_type": victory_type,
		"game_time": game_time,
		"wave": wave
	})


## Record defeat.
func record_defeat(faction: String, defeat_reason: String, game_time: float, wave: int) -> void:
	if faction == _player_faction:
		_final_wave = wave

	record_critical_event("defeat", {
		"faction": faction,
		"defeat_reason": defeat_reason,
		"game_time": game_time,
		"wave": wave
	})


## Stop recording.
func stop_recording() -> Dictionary:
	if not _is_recording:
		return {"success": false, "error": "Not recording"}

	_is_recording = false

	var statistics := get_statistics()
	recording_stopped.emit(_replay_id, statistics)

	return statistics


## Save replay to file (async-friendly).
func save_replay(custom_name: String = "") -> bool:
	if _is_saving:
		return false

	if _base_snapshot == null:
		push_error("ReplayRecorder: No replay data to save")
		return false

	_is_saving = true

	# Build replay data structure
	var replay_data := _build_replay_data()

	# Generate filename
	var file_name := custom_name if not custom_name.is_empty() else _replay_id
	var file_path := REPLAY_DIR + file_name + REPLAY_EXTENSION

	# Ensure directory exists
	_ensure_replay_directory()

	# Serialize data
	save_progress.emit(0.1)
	var data_bytes := var_to_bytes(replay_data)

	# Compress
	save_progress.emit(0.3)
	var compressed := data_bytes.compress(FileAccess.COMPRESSION_DEFLATE)

	# Calculate checksum
	var checksum := _calculate_checksum(compressed)

	# Write file
	save_progress.emit(0.5)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("ReplayRecorder: Cannot create file: %s" % file_path)
		_is_saving = false
		replay_saved.emit(file_path, false)
		return false

	# Write header
	file.store_buffer(REPLAY_MAGIC)
	file.store_32(REPLAY_VERSION)
	file.store_32(data_bytes.size())  ## Uncompressed size
	file.store_32(checksum)
	file.store_buffer(compressed)
	file.close()

	save_progress.emit(1.0)
	_is_saving = false
	replay_saved.emit(file_path, true)

	return true


## Build complete replay data structure.
func _build_replay_data() -> Dictionary:
	# Convert keyframes to dicts
	var keyframes_data: Array = []
	for snapshot in _keyframes:
		keyframes_data.append(snapshot.to_dict())

	return {
		"version": REPLAY_VERSION,
		"replay_id": _replay_id,
		"timestamp": _game_start_time,

		# Deterministic seeds
		"game_seed": _game_seed,
		"map_seed": _map_seed,

		# Game configuration
		"factions": _factions.duplicate(),
		"player_faction": _player_faction,
		"difficulty": _difficulty,

		# Victory data
		"victory_faction": _victory_faction,
		"victory_type": _victory_type,
		"victory_time": _victory_time,
		"final_wave": _final_wave,

		# Frame data
		"start_frame": _start_frame,
		"end_frame": _current_frame,
		"duration_frames": _current_frame - _start_frame,

		# Snapshots
		"base_snapshot": _base_snapshot.to_dict() if _base_snapshot else {},
		"keyframes": keyframes_data,
		"incremental_snapshots": _incremental_snapshots.duplicate(),

		# Events
		"critical_events": _critical_events.duplicate(),

		# Metadata
		"statistics": get_statistics()
	}


## Calculate CRC32 checksum.
func _calculate_checksum(data: PackedByteArray) -> int:
	var crc: int = 0xFFFFFFFF
	for byte in data:
		crc = crc ^ byte
		for i in range(8):
			if crc & 1:
				crc = (crc >> 1) ^ 0xEDB88320
			else:
				crc = crc >> 1
	return crc ^ 0xFFFFFFFF


## Generate unique replay ID.
func _generate_replay_id() -> String:
	var timestamp := int(Time.get_unix_time_from_system())
	var random_suffix := randi() % 10000
	return "replay_%d_%04d" % [timestamp, random_suffix]


## Ensure replay directory exists.
func _ensure_replay_directory() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("replays"):
		dir.make_dir("replays")


## Check if currently recording.
func is_recording() -> bool:
	return _is_recording


## Check if currently saving.
func is_saving() -> bool:
	return _is_saving


## Get current replay ID.
func get_replay_id() -> String:
	return _replay_id


## Get current frame.
func get_current_frame() -> int:
	return _current_frame


## Get recording statistics.
func get_statistics() -> Dictionary:
	var total_snapshots := 1 + _keyframes.size() + _incremental_snapshots.size()
	var avg_capture_time := _total_capture_time_ms / maxf(1, _captures_performed)

	return {
		"replay_id": _replay_id,
		"is_recording": _is_recording,
		"start_frame": _start_frame,
		"current_frame": _current_frame,
		"duration_frames": _current_frame - _start_frame,
		"total_snapshots": total_snapshots,
		"keyframe_count": _keyframes.size(),
		"incremental_count": _incremental_snapshots.size(),
		"critical_events": _critical_events.size(),
		"captures_performed": _captures_performed,
		"avg_capture_time_ms": avg_capture_time,
		"last_capture_time_ms": _last_capture_time_ms,
		"victory_faction": _victory_faction,
		"victory_type": _victory_type,
		"final_wave": _final_wave
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return _build_replay_data()


## Clear all recording data.
func clear() -> void:
	_is_recording = false
	_replay_id = ""
	_current_frame = 0
	_start_frame = 0
	_game_seed = 0
	_map_seed = 0
	_factions.clear()
	_player_faction = ""
	_base_snapshot = null
	_keyframes.clear()
	_incremental_snapshots.clear()
	_critical_events.clear()
	_victory_faction = ""
	_victory_time = 0.0
	_victory_type = ""
	_final_wave = 0
