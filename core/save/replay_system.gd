class_name ReplaySystemClass
extends RefCounted
## ReplaySystem enables deterministic battle replay using snapshots and deltas.
## Records game state changes for later playback and analysis.

signal replay_started(start_frame: int, end_frame: int)
signal replay_frame_advanced(current_frame: int, progress: float)
signal replay_paused()
signal replay_resumed()
signal replay_ended()
signal replay_saved(file_path: String)
signal replay_loaded(file_path: String)

## Replay playback state
enum PlaybackState {
	STOPPED = 0,
	PLAYING = 1,
	PAUSED = 2,
	SEEKING = 3
}

## Replay file extension
const REPLAY_EXTENSION: String = ".agireplay"

## Replay directory
const REPLAY_DIR: String = "user://replays/"

## Starting snapshot for replay
var _base_snapshot: Snapshot = null

## All deltas in the replay
var _replay_deltas: Array[Delta] = []

## Current playback state
var _playback_state: PlaybackState = PlaybackState.STOPPED

## Current frame in playback
var _current_frame: int = 0

## Start frame of replay
var _start_frame: int = 0

## End frame of replay
var _end_frame: int = 0

## Playback speed multiplier
var _playback_speed: float = 1.0

## Current reconstructed state
var _current_state: Snapshot = null

## Replay metadata
var _metadata: Dictionary = {}


## Start recording a new replay
func start_recording(base_snapshot: Snapshot) -> void:
	_base_snapshot = base_snapshot.duplicate()
	_replay_deltas.clear()
	_start_frame = base_snapshot.frame_number
	_current_frame = _start_frame
	_metadata = {
		"start_time": int(Time.get_unix_time_from_system()),
		"wave_number": base_snapshot.wave_number,
		"entity_count": base_snapshot.get_entity_count()
	}
	print("ReplaySystem: Recording started at frame %d" % _start_frame)


## Add a delta to the recording
func record_delta(delta: Delta) -> void:
	if _base_snapshot == null:
		push_error("ReplaySystem: Cannot record delta - recording not started")
		return

	_replay_deltas.append(delta)
	_end_frame = delta.frame_number
	_current_frame = _end_frame


## Stop recording and finalize replay
func stop_recording() -> Dictionary:
	if _base_snapshot == null:
		return {"success": false, "error": "No recording in progress"}

	_metadata["end_time"] = int(Time.get_unix_time_from_system())
	_metadata["duration_frames"] = _end_frame - _start_frame
	_metadata["delta_count"] = _replay_deltas.size()

	print("ReplaySystem: Recording stopped. Duration: %d frames, %d deltas" % [
		_metadata["duration_frames"], _metadata["delta_count"]
	])

	return {
		"success": true,
		"start_frame": _start_frame,
		"end_frame": _end_frame,
		"delta_count": _replay_deltas.size()
	}


## Save replay to file
func save_replay(replay_name: String) -> bool:
	if _base_snapshot == null:
		push_error("ReplaySystem: No replay to save")
		return false

	_ensure_replay_directory()

	var replay_data := {
		"metadata": _metadata,
		"base_snapshot": _base_snapshot.to_dict(),
		"deltas": []
	}

	for delta in _replay_deltas:
		replay_data["deltas"].append(delta.to_dict())

	# Serialize and compress
	var data_bytes := var_to_bytes(replay_data)
	var compressed := data_bytes.compress(FileAccess.COMPRESSION_DEFLATE)

	var file_path := REPLAY_DIR + replay_name + REPLAY_EXTENSION
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("ReplaySystem: Cannot create replay file: %s" % file_path)
		return false

	# Write header
	file.store_buffer(PackedByteArray([0x41, 0x47, 0x49, 0x52]))  # "AGIR" magic
	file.store_32(1)  # Version
	file.store_32(data_bytes.size())  # Uncompressed size
	file.store_buffer(compressed)
	file.close()

	replay_saved.emit(file_path)
	print("ReplaySystem: Saved replay '%s' (%d bytes)" % [replay_name, compressed.size()])
	return true


## Load replay from file
func load_replay(replay_name: String) -> bool:
	var file_path := REPLAY_DIR + replay_name + REPLAY_EXTENSION
	if not FileAccess.file_exists(file_path):
		push_error("ReplaySystem: Replay file not found: %s" % file_path)
		return false

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("ReplaySystem: Cannot open replay file")
		return false

	# Read header
	var magic := file.get_buffer(4)
	if magic != PackedByteArray([0x41, 0x47, 0x49, 0x52]):
		push_error("ReplaySystem: Invalid replay file magic")
		file.close()
		return false

	var _version := file.get_32()
	var uncompressed_size := file.get_32()

	# Read compressed data
	var compressed := file.get_buffer(file.get_length() - file.get_position())
	file.close()

	# Decompress
	var data_bytes := compressed.decompress(uncompressed_size, FileAccess.COMPRESSION_DEFLATE)
	if data_bytes.is_empty():
		push_error("ReplaySystem: Failed to decompress replay")
		return false

	var replay_data = bytes_to_var(data_bytes)
	if not replay_data is Dictionary:
		push_error("ReplaySystem: Invalid replay data")
		return false

	# Load data
	_metadata = replay_data.get("metadata", {})
	_base_snapshot = Snapshot.from_dict(replay_data.get("base_snapshot", {}))
	_replay_deltas.clear()

	for delta_dict in replay_data.get("deltas", []):
		_replay_deltas.append(Delta.from_dict(delta_dict))

	_start_frame = _base_snapshot.frame_number
	_end_frame = _metadata.get("duration_frames", 0) + _start_frame
	_current_frame = _start_frame
	_current_state = _base_snapshot.duplicate()

	replay_loaded.emit(file_path)
	print("ReplaySystem: Loaded replay '%s' (%d frames, %d deltas)" % [
		replay_name, _end_frame - _start_frame, _replay_deltas.size()
	])
	return true


## Start replay playback
func start_playback() -> void:
	if _base_snapshot == null:
		push_error("ReplaySystem: No replay loaded")
		return

	_playback_state = PlaybackState.PLAYING
	_current_frame = _start_frame
	_current_state = _base_snapshot.duplicate()

	replay_started.emit(_start_frame, _end_frame)
	print("ReplaySystem: Playback started (frames %d - %d)" % [_start_frame, _end_frame])


## Pause playback
func pause_playback() -> void:
	if _playback_state == PlaybackState.PLAYING:
		_playback_state = PlaybackState.PAUSED
		replay_paused.emit()


## Resume playback
func resume_playback() -> void:
	if _playback_state == PlaybackState.PAUSED:
		_playback_state = PlaybackState.PLAYING
		replay_resumed.emit()


## Stop playback
func stop_playback() -> void:
	_playback_state = PlaybackState.STOPPED
	replay_ended.emit()


## Advance playback by one frame
func advance_frame() -> Snapshot:
	if _playback_state != PlaybackState.PLAYING and _playback_state != PlaybackState.SEEKING:
		return _current_state

	if _current_frame >= _end_frame:
		_playback_state = PlaybackState.STOPPED
		replay_ended.emit()
		return _current_state

	# Find and apply delta for this frame
	for delta in _replay_deltas:
		if delta.frame_number == _current_frame + 1:
			_current_state = delta.apply_to_snapshot(_current_state)
			break

	_current_frame += 1

	var progress := float(_current_frame - _start_frame) / float(_end_frame - _start_frame)
	replay_frame_advanced.emit(_current_frame, progress)

	return _current_state


## Seek to specific frame
func seek_to_frame(target_frame: int) -> Snapshot:
	if _base_snapshot == null:
		return null

	target_frame = clampi(target_frame, _start_frame, _end_frame)

	_playback_state = PlaybackState.SEEKING

	# Reset to base snapshot
	_current_state = _base_snapshot.duplicate()
	_current_frame = _start_frame

	# Apply deltas up to target frame
	for delta in _replay_deltas:
		if delta.frame_number <= target_frame:
			_current_state = delta.apply_to_snapshot(_current_state)
			_current_frame = delta.frame_number
		else:
			break

	_current_frame = target_frame

	var progress := float(_current_frame - _start_frame) / float(_end_frame - _start_frame)
	replay_frame_advanced.emit(_current_frame, progress)

	return _current_state


## Get state at specific frame
func get_state_at_frame(frame: int) -> Dictionary:
	var state := seek_to_frame(frame)
	if state == null:
		return {}
	return state.to_dict()


## Set playback speed
func set_playback_speed(speed: float) -> void:
	_playback_speed = clampf(speed, 0.1, 10.0)


## Get playback speed
func get_playback_speed() -> float:
	return _playback_speed


## Get current frame
func get_current_frame() -> int:
	return _current_frame


## Get total frames
func get_total_frames() -> int:
	return _end_frame - _start_frame


## Get playback progress (0.0 - 1.0)
func get_progress() -> float:
	if _end_frame <= _start_frame:
		return 0.0
	return float(_current_frame - _start_frame) / float(_end_frame - _start_frame)


## Get current state
func get_current_state() -> Snapshot:
	return _current_state


## Get playback state
func get_playback_state() -> PlaybackState:
	return _playback_state


## Get replay metadata
func get_metadata() -> Dictionary:
	return _metadata


## Get list of available replays
func get_replay_list() -> Array[Dictionary]:
	var replays: Array[Dictionary] = []
	_ensure_replay_directory()

	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return replays

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(REPLAY_EXTENSION):
			var replay_name := file_name.trim_suffix(REPLAY_EXTENSION)
			var file_path := REPLAY_DIR + file_name

			var file := FileAccess.open(file_path, FileAccess.READ)
			if file != null:
				replays.append({
					"name": replay_name,
					"path": file_path,
					"size": file.get_length()
				})
				file.close()

		file_name = dir.get_next()

	dir.list_dir_end()
	return replays


## Delete a replay file
func delete_replay(replay_name: String) -> bool:
	var file_path := REPLAY_DIR + replay_name + REPLAY_EXTENSION
	if not FileAccess.file_exists(file_path):
		return false

	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return false

	return dir.remove(replay_name + REPLAY_EXTENSION) == OK


## Ensure replay directory exists
func _ensure_replay_directory() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("replays"):
		dir.make_dir("replays")


## Check if currently recording
func is_recording() -> bool:
	return _base_snapshot != null and _playback_state == PlaybackState.STOPPED


## Check if replay is loaded
func is_replay_loaded() -> bool:
	return _base_snapshot != null


## Clear current replay
func clear() -> void:
	_base_snapshot = null
	_replay_deltas.clear()
	_current_state = null
	_playback_state = PlaybackState.STOPPED
	_current_frame = 0
	_start_frame = 0
	_end_frame = 0
	_metadata.clear()
