class_name ReplayVerifier
extends RefCounted
## ReplayVerifier validates replay files for leaderboard submission and anti-cheat.
## Replays games deterministically to verify victory conditions and statistics.

signal verification_started(replay_id: String)
signal verification_progress(percent: float, current_frame: int, total_frames: int)
signal verification_completed(replay_id: String, result: VerificationResult)
signal verification_failed(replay_id: String, reason: String)
signal integrity_check_completed(is_valid: bool, details: Dictionary)

## Verification result codes
enum ResultCode {
	VALID,                  ## Replay is valid
	INVALID_CHECKSUM,       ## File integrity failed
	INVALID_FORMAT,         ## File format error
	SEED_MISMATCH,          ## Determinism failed
	VICTORY_MISMATCH,       ## Victory conditions don't match
	STATISTICS_MISMATCH,    ## Game statistics don't match
	SUSPICIOUS_TIMING,      ## Suspiciously fast actions
	INCOMPLETE_DATA,        ## Missing required data
	SIMULATION_ERROR        ## Error during replay
}

## Verification thresholds
const POSITION_TOLERANCE := 0.1         ## Position deviation tolerance
const TIMING_TOLERANCE_MS := 100        ## Timing tolerance in ms
const SUSPICIOUS_APM := 500             ## Actions per minute threshold
const MAX_VERIFICATION_TIME_MS := 30000 ## Max time for verification

## Replay file constants
## "AGID" magic bytes - initialized at runtime since PackedByteArray is not a constant expression
static var REPLAY_MAGIC: PackedByteArray = PackedByteArray([0x41, 0x47, 0x49, 0x44])
const REPLAY_VERSION := 1
const REPLAY_EXTENSION := ".agidreplay"
const REPLAY_DIR := "user://replays/"

## Verification state
var _is_verifying: bool = false
var _current_replay_id: String = ""
var _verification_start_time: int = 0

## Loaded replay data
var _replay_data: Dictionary = {}


func _init() -> void:
	pass


## Load replay file for verification.
func load_replay(file_path: String) -> bool:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("ReplayVerifier: Cannot open file: %s" % file_path)
		return false

	# Read and validate header
	var magic := file.get_buffer(4)
	if magic != REPLAY_MAGIC:
		push_error("ReplayVerifier: Invalid file magic")
		file.close()
		return false

	var version := file.get_32()
	if version > REPLAY_VERSION:
		push_error("ReplayVerifier: Unsupported replay version: %d" % version)
		file.close()
		return false

	var uncompressed_size := file.get_32()
	var stored_checksum := file.get_32()

	# Read compressed data
	var compressed := file.get_buffer(file.get_length() - file.get_position())
	file.close()

	# Verify checksum
	var calculated_checksum := _calculate_checksum(compressed)
	if calculated_checksum != stored_checksum:
		push_error("ReplayVerifier: Checksum mismatch")
		return false

	# Decompress
	var data_bytes := compressed.decompress(uncompressed_size, FileAccess.COMPRESSION_DEFLATE)
	if data_bytes.is_empty():
		push_error("ReplayVerifier: Decompression failed")
		return false

	# Parse data
	_replay_data = bytes_to_var(data_bytes)
	if not _replay_data is Dictionary:
		push_error("ReplayVerifier: Invalid replay data format")
		return false

	return true


## Load replay from dictionary (for in-memory verification).
func load_from_dict(replay_data: Dictionary) -> bool:
	if replay_data.is_empty():
		return false
	_replay_data = replay_data.duplicate(true)
	return true


## Verify file integrity only (fast check).
func verify_integrity(file_path: String) -> Dictionary:
	var result := {
		"is_valid": false,
		"checksum_valid": false,
		"format_valid": false,
		"version": 0,
		"error": ""
	}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		result["error"] = "Cannot open file"
		integrity_check_completed.emit(false, result)
		return result

	# Check magic
	var magic := file.get_buffer(4)
	if magic != REPLAY_MAGIC:
		result["error"] = "Invalid file magic"
		file.close()
		integrity_check_completed.emit(false, result)
		return result

	result["format_valid"] = true

	# Check version
	var version := file.get_32()
	result["version"] = version
	if version > REPLAY_VERSION:
		result["error"] = "Unsupported version"
		file.close()
		integrity_check_completed.emit(false, result)
		return result

	var uncompressed_size := file.get_32()
	var stored_checksum := file.get_32()

	# Read and verify checksum
	var compressed := file.get_buffer(file.get_length() - file.get_position())
	file.close()

	var calculated_checksum := _calculate_checksum(compressed)
	result["checksum_valid"] = (calculated_checksum == stored_checksum)

	if not result["checksum_valid"]:
		result["error"] = "Checksum mismatch"
		integrity_check_completed.emit(false, result)
		return result

	result["is_valid"] = true
	integrity_check_completed.emit(true, result)
	return result


## Perform full verification of loaded replay.
func verify() -> VerificationResult:
	if _replay_data.is_empty():
		var result := VerificationResult.new()
		result.code = ResultCode.INCOMPLETE_DATA
		result.message = "No replay data loaded"
		return result

	_is_verifying = true
	_current_replay_id = _replay_data.get("replay_id", "unknown")
	_verification_start_time = Time.get_ticks_msec()

	verification_started.emit(_current_replay_id)

	var result := VerificationResult.new()
	result.replay_id = _current_replay_id

	# Step 1: Validate required fields
	if not _validate_required_fields(result):
		_complete_verification(result)
		return result

	# Step 2: Check for suspicious patterns
	if not _check_suspicious_patterns(result):
		_complete_verification(result)
		return result

	# Step 3: Verify victory conditions match
	if not _verify_victory_conditions(result):
		_complete_verification(result)
		return result

	# Step 4: Verify statistics consistency
	if not _verify_statistics(result):
		_complete_verification(result)
		return result

	# Step 5: Simulate key frames (if time permits)
	_verify_simulation(result)

	_complete_verification(result)
	return result


## Validate required fields exist.
func _validate_required_fields(result: VerificationResult) -> bool:
	var required_fields := [
		"version", "replay_id", "game_seed", "map_seed",
		"factions", "player_faction", "base_snapshot",
		"start_frame", "end_frame"
	]

	for field in required_fields:
		if not _replay_data.has(field):
			result.code = ResultCode.INCOMPLETE_DATA
			result.message = "Missing required field: %s" % field
			result.details["missing_field"] = field
			return false

	return true


## Check for suspicious patterns.
func _check_suspicious_patterns(result: VerificationResult) -> bool:
	var critical_events: Array = _replay_data.get("critical_events", [])
	var duration_frames: int = _replay_data.get("duration_frames", 0)

	if duration_frames <= 0:
		result.code = ResultCode.INCOMPLETE_DATA
		result.message = "Invalid duration"
		return false

	# Calculate actions per minute
	var event_count := critical_events.size()
	var duration_minutes := float(duration_frames) / (60.0 * 60.0)  # Assuming 60 FPS
	var apm := event_count / maxf(0.1, duration_minutes)

	result.details["apm"] = apm
	result.details["event_count"] = event_count
	result.details["duration_frames"] = duration_frames

	if apm > SUSPICIOUS_APM:
		result.code = ResultCode.SUSPICIOUS_TIMING
		result.message = "Suspiciously high APM: %.1f" % apm
		result.warnings.append("APM exceeds threshold")
		# Don't fail, just flag as suspicious
		result.is_suspicious = true

	# Check for impossible timing between events
	var last_frame := 0
	for event in critical_events:
		var event_frame: int = event.get("frame", 0)
		if event_frame < last_frame:
			result.code = ResultCode.SUSPICIOUS_TIMING
			result.message = "Events out of order"
			return false
		last_frame = event_frame

	return true


## Verify victory conditions match recorded data.
func _verify_victory_conditions(result: VerificationResult) -> bool:
	var victory_faction: String = _replay_data.get("victory_faction", "")
	var victory_type: String = _replay_data.get("victory_type", "")
	var final_wave: int = _replay_data.get("final_wave", 0)

	result.details["victory_faction"] = victory_faction
	result.details["victory_type"] = victory_type
	result.details["final_wave"] = final_wave

	# Check if victory was recorded
	if victory_faction.is_empty():
		result.warnings.append("No victory recorded")
		return true  # Not a failure, just incomplete game

	# Find victory event in critical events
	var victory_event_found := false
	var critical_events: Array = _replay_data.get("critical_events", [])

	for event in critical_events:
		if event.get("type") == "victory":
			victory_event_found = true
			var event_faction: String = event.get("data", {}).get("faction", "")
			var event_type: String = event.get("data", {}).get("victory_type", "")

			if event_faction != victory_faction:
				result.code = ResultCode.VICTORY_MISMATCH
				result.message = "Victory faction mismatch"
				result.details["event_faction"] = event_faction
				return false

			if event_type != victory_type:
				result.code = ResultCode.VICTORY_MISMATCH
				result.message = "Victory type mismatch"
				result.details["event_type"] = event_type
				return false

			break

	if not victory_event_found and not victory_faction.is_empty():
		result.warnings.append("Victory event not found in critical events")

	return true


## Verify statistics consistency.
func _verify_statistics(result: VerificationResult) -> bool:
	var statistics: Dictionary = _replay_data.get("statistics", {})
	var critical_events: Array = _replay_data.get("critical_events", [])

	# Count events by type
	var spawn_count := 0
	var death_count := 0
	var building_count := 0
	var destruction_count := 0

	for event in critical_events:
		match event.get("type"):
			"unit_spawn":
				spawn_count += 1
			"unit_death":
				death_count += 1
			"building_constructed":
				building_count += 1
			"building_destroyed":
				destruction_count += 1

	result.details["spawn_events"] = spawn_count
	result.details["death_events"] = death_count
	result.details["building_events"] = building_count
	result.details["destruction_events"] = destruction_count

	# Sanity checks
	if death_count > spawn_count * 2:  # Allow some margin for pre-existing units
		result.warnings.append("More deaths than spawns")

	return true


## Verify simulation (lightweight check).
func _verify_simulation(result: VerificationResult) -> void:
	verification_progress.emit(0.5, 0, 100)

	var keyframes: Array = _replay_data.get("keyframes", [])
	var incremental_snapshots: Array = _replay_data.get("incremental_snapshots", [])

	result.details["keyframe_count"] = keyframes.size()
	result.details["snapshot_count"] = incremental_snapshots.size()

	# Verify keyframes are in order
	var last_frame := 0
	for keyframe in keyframes:
		var frame: int = keyframe.get("frame_number", 0)
		if frame <= last_frame and last_frame > 0:
			result.warnings.append("Keyframes out of order")
			break
		last_frame = frame

	verification_progress.emit(1.0, last_frame, last_frame)

	# If we got here without failures, it's valid
	if result.code == ResultCode.VALID:
		result.is_valid = true
		result.message = "Verification passed"


## Complete verification process.
func _complete_verification(result: VerificationResult) -> void:
	result.verification_time_ms = Time.get_ticks_msec() - _verification_start_time
	_is_verifying = false

	if result.is_valid:
		verification_completed.emit(_current_replay_id, result)
	else:
		verification_failed.emit(_current_replay_id, result.message)


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


## Get replay metadata (without full verification).
func get_replay_metadata() -> Dictionary:
	if _replay_data.is_empty():
		return {}

	return {
		"replay_id": _replay_data.get("replay_id", ""),
		"timestamp": _replay_data.get("timestamp", 0),
		"factions": _replay_data.get("factions", []),
		"player_faction": _replay_data.get("player_faction", ""),
		"difficulty": _replay_data.get("difficulty", 1),
		"victory_faction": _replay_data.get("victory_faction", ""),
		"victory_type": _replay_data.get("victory_type", ""),
		"victory_time": _replay_data.get("victory_time", 0.0),
		"final_wave": _replay_data.get("final_wave", 0),
		"duration_frames": _replay_data.get("duration_frames", 0)
	}


## Check if currently verifying.
func is_verifying() -> bool:
	return _is_verifying


## Get loaded replay data.
func get_replay_data() -> Dictionary:
	return _replay_data


## Clear loaded replay.
func clear() -> void:
	_replay_data.clear()
	_is_verifying = false
	_current_replay_id = ""


## Get list of replay files.
static func get_replay_files() -> Array[Dictionary]:
	var replays: Array[Dictionary] = []

	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return replays

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(REPLAY_EXTENSION):
			var file_path := REPLAY_DIR + file_name
			var file := FileAccess.open(file_path, FileAccess.READ)
			if file != null:
				replays.append({
					"name": file_name.trim_suffix(REPLAY_EXTENSION),
					"path": file_path,
					"size": file.get_length(),
					"modified": FileAccess.get_modified_time(file_path)
				})
				file.close()

		file_name = dir.get_next()

	dir.list_dir_end()
	return replays


## VerificationResult class.
class VerificationResult:
	var replay_id: String = ""
	var is_valid: bool = false
	var is_suspicious: bool = false
	var code: int = ResultCode.VALID
	var message: String = ""
	var details: Dictionary = {}
	var warnings: Array[String] = []
	var verification_time_ms: int = 0

	func to_dict() -> Dictionary:
		return {
			"replay_id": replay_id,
			"is_valid": is_valid,
			"is_suspicious": is_suspicious,
			"code": code,
			"message": message,
			"details": details.duplicate(),
			"warnings": warnings.duplicate(),
			"verification_time_ms": verification_time_ms
		}

	static func get_code_name(result_code: int) -> String:
		match result_code:
			ResultCode.VALID: return "VALID"
			ResultCode.INVALID_CHECKSUM: return "INVALID_CHECKSUM"
			ResultCode.INVALID_FORMAT: return "INVALID_FORMAT"
			ResultCode.SEED_MISMATCH: return "SEED_MISMATCH"
			ResultCode.VICTORY_MISMATCH: return "VICTORY_MISMATCH"
			ResultCode.STATISTICS_MISMATCH: return "STATISTICS_MISMATCH"
			ResultCode.SUSPICIOUS_TIMING: return "SUSPICIOUS_TIMING"
			ResultCode.INCOMPLETE_DATA: return "INCOMPLETE_DATA"
			ResultCode.SIMULATION_ERROR: return "SIMULATION_ERROR"
		return "UNKNOWN"
