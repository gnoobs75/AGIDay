class_name SaveManagerClass
extends Node
## SaveManager provides the high-level API for saving and loading game state.
## Use this singleton to manage all save/load operations.

signal save_started(save_name: String)
signal save_completed(save_name: String, success: bool)
signal save_progress(save_name: String, progress: float)
signal load_started(save_name: String)
signal load_completed(save_name: String, success: bool)
signal load_progress(save_name: String, progress: float)
signal save_deleted(save_name: String)
signal error_occurred(error_code: int, message: String)
signal backup_created_on_save(save_name: String)
signal recovery_needed(save_name: String)
signal recovered_from_backup(save_name: String, backup_number: int)

## Save operation result
class SaveResult:
	var success: bool = false
	var error_code: int = BinarySaveFile.SaveError.OK
	var error_message: String = ""
	var file_path: String = ""
	var file_size: int = 0
	var save_time_ms: int = 0


## Load operation result
class LoadResult:
	var success: bool = false
	var error_code: int = BinarySaveFile.SaveError.OK
	var error_message: String = ""
	var metadata: SaveFormat.SaveMetadata = null
	var snapshot: Dictionary = {}
	var deltas: Array[Dictionary] = []
	var voxel_chunks: Array[Dictionary] = []
	var load_time_ms: int = 0


## Save file info for listings
class SaveFileInfo:
	var file_name: String = ""
	var file_path: String = ""
	var file_size: int = 0
	var save_name: String = ""
	var timestamp: int = 0
	var formatted_date: String = ""
	var player_faction: int = 0
	var current_wave: int = 0
	var play_time: float = 0.0
	var formatted_play_time: String = ""
	var entity_count: int = 0


var _binary_file: BinarySaveFile
var _backup_manager: BackupManagerClass
var _is_saving: bool = false
var _is_loading: bool = false
var _current_operation: String = ""
var _auto_backup_enabled: bool = true


func _ready() -> void:
	_binary_file = BinarySaveFile.new()
	_binary_file.write_progress.connect(_on_write_progress)
	_binary_file.read_progress.connect(_on_read_progress)
	_backup_manager = BackupManagerClass.new()
	_ensure_save_directory()


func _ensure_save_directory() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("saves"):
		dir.make_dir("saves")


## Save the current game state
func save_game(
	save_name: String,
	game_state: Dictionary,
	voxel_data: Array[Dictionary] = []
) -> SaveResult:
	var result := SaveResult.new()
	var start_time := Time.get_ticks_msec()

	if _is_saving:
		result.error_code = BinarySaveFile.SaveError.UNKNOWN_ERROR
		result.error_message = "Save operation already in progress"
		error_occurred.emit(result.error_code, result.error_message)
		return result

	if not SaveFormat.is_valid_save_name(save_name):
		result.error_code = BinarySaveFile.SaveError.UNKNOWN_ERROR
		result.error_message = "Invalid save name"
		error_occurred.emit(result.error_code, result.error_message)
		return result

	_is_saving = true
	_current_operation = save_name
	save_started.emit(save_name)

	# Build metadata from game state
	var metadata := SaveFormat.SaveMetadata.new()
	metadata.save_name = save_name
	metadata.player_faction = game_state.get("player_faction", 0)
	metadata.current_wave = game_state.get("current_wave", 0)
	metadata.difficulty = game_state.get("difficulty", 0)
	metadata.game_time_seconds = game_state.get("game_time", 0.0)
	metadata.entity_count = game_state.get("entity_count", 0)
	metadata.play_time_seconds = game_state.get("play_time", 0.0)
	metadata.custom_data = game_state.get("custom_data", {})

	# Build snapshot from game state
	var snapshot := {
		"entities": game_state.get("entities", {}),
		"systems": game_state.get("systems", {}),
		"world_state": game_state.get("world_state", {}),
		"timestamp": int(Time.get_unix_time_from_system())
	}

	# Get deltas if available
	var deltas: Array[Dictionary] = []
	var raw_deltas = game_state.get("deltas", [])
	for d in raw_deltas:
		if d is Dictionary:
			deltas.append(d)

	# Save to file
	var file_path := SaveFormat.get_save_path(save_name)
	var success := _binary_file.write_save_file(file_path, metadata, snapshot, deltas, voxel_data)

	_is_saving = false
	_current_operation = ""

	result.success = success
	result.file_path = file_path
	result.save_time_ms = Time.get_ticks_msec() - start_time

	if success:
		result.file_size = _binary_file.get_file_size(file_path)
		print("SaveManager: Saved '%s' in %dms (%d bytes)" % [save_name, result.save_time_ms, result.file_size])

		# Auto-create backup on successful save
		if _auto_backup_enabled:
			if _backup_manager.create_backup(save_name):
				backup_created_on_save.emit(save_name)
	else:
		result.error_code = _binary_file.get_last_error()
		result.error_message = _binary_file.get_last_error_message()
		error_occurred.emit(result.error_code, result.error_message)

	save_completed.emit(save_name, success)
	return result


## Load a game state from file with automatic recovery
func load_game(save_name: String) -> LoadResult:
	var result := LoadResult.new()
	var start_time := Time.get_ticks_msec()

	if _is_loading:
		result.error_code = BinarySaveFile.SaveError.UNKNOWN_ERROR
		result.error_message = "Load operation already in progress"
		error_occurred.emit(result.error_code, result.error_message)
		return result

	_is_loading = true
	_current_operation = save_name
	load_started.emit(save_name)

	# Try to validate and recover if needed
	var recovery := _backup_manager.validate_and_recover(save_name)
	if not recovery.get("original_valid", false):
		if recovery.get("recovered", false):
			recovered_from_backup.emit(save_name, recovery.get("backup_used", 0))
		elif not recovery.get("error", "").is_empty():
			recovery_needed.emit(save_name)

	var file_path := SaveFormat.get_save_path(save_name)
	var data := _binary_file.read_save_file(file_path)

	_is_loading = false
	_current_operation = ""

	result.success = data.get("success", false)
	result.load_time_ms = Time.get_ticks_msec() - start_time

	if result.success:
		result.metadata = data.get("metadata")
		result.snapshot = data.get("snapshot", {})

		var raw_deltas = data.get("deltas", [])
		for d in raw_deltas:
			if d is Dictionary:
				result.deltas.append(d)

		var raw_voxels = data.get("voxel_chunks", [])
		for v in raw_voxels:
			if v is Dictionary:
				result.voxel_chunks.append(v)

		print("SaveManager: Loaded '%s' in %dms" % [save_name, result.load_time_ms])
	else:
		result.error_code = _binary_file.get_last_error()
		result.error_message = _binary_file.get_last_error_message()
		error_occurred.emit(result.error_code, result.error_message)

	load_completed.emit(save_name, result.success)
	return result


## Get list of all save files
func get_save_files() -> Array[SaveFileInfo]:
	var saves: Array[SaveFileInfo] = []
	var save_dir := SaveFormat.get_save_directory()

	var dir := DirAccess.open(save_dir)
	if dir == null:
		return saves

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(SaveFormat.FILE_EXTENSION):
			var info := get_save_info(file_name.trim_suffix(SaveFormat.FILE_EXTENSION))
			if info != null:
				saves.append(info)
		file_name = dir.get_next()

	dir.list_dir_end()

	# Sort by timestamp (newest first)
	saves.sort_custom(func(a: SaveFileInfo, b: SaveFileInfo) -> bool:
		return a.timestamp > b.timestamp
	)

	return saves


## Get info about a specific save file (without loading full data)
func get_save_info(save_name: String) -> SaveFileInfo:
	var file_path := SaveFormat.get_save_path(save_name)
	var data := _binary_file.read_save_info(file_path)

	if not data.get("success", false):
		return null

	var header: SaveFormat.SaveHeader = data.get("header")
	var metadata: SaveFormat.SaveMetadata = data.get("metadata")

	if header == null or metadata == null:
		return null

	var info := SaveFileInfo.new()
	info.file_name = save_name + SaveFormat.FILE_EXTENSION
	info.file_path = file_path
	info.file_size = _binary_file.get_file_size(file_path)
	info.save_name = metadata.save_name if not metadata.save_name.is_empty() else save_name
	info.timestamp = header.timestamp
	info.formatted_date = SaveFormat.format_timestamp(header.timestamp)
	info.player_faction = metadata.player_faction
	info.current_wave = metadata.current_wave
	info.play_time = metadata.play_time_seconds
	info.formatted_play_time = SaveFormat.format_play_time(metadata.play_time_seconds)
	info.entity_count = metadata.entity_count

	return info


## Delete a save file
func delete_save(save_name: String) -> bool:
	var file_path := SaveFormat.get_save_path(save_name)
	var success := _binary_file.delete_save_file(file_path)

	if success:
		save_deleted.emit(save_name)
		print("SaveManager: Deleted save '%s'" % save_name)
	else:
		error_occurred.emit(_binary_file.get_last_error(), _binary_file.get_last_error_message())

	return success


## Check if a save file exists
func save_exists(save_name: String) -> bool:
	var file_path := SaveFormat.get_save_path(save_name)
	return FileAccess.file_exists(file_path)


## Create a quicksave
func quicksave(game_state: Dictionary, voxel_data: Array[Dictionary] = []) -> SaveResult:
	return save_game(SaveFormat.QUICKSAVE_NAME, game_state, voxel_data)


## Load the quicksave
func quickload() -> LoadResult:
	return load_game(SaveFormat.QUICKSAVE_NAME)


## Check if quicksave exists
func has_quicksave() -> bool:
	return save_exists(SaveFormat.QUICKSAVE_NAME)


## Create an autosave with rotation
func autosave(game_state: Dictionary, voxel_data: Array[Dictionary] = [], max_autosaves: int = 3) -> SaveResult:
	# Rotate existing autosaves
	for i in range(max_autosaves - 1, 0, -1):
		var old_name := SaveFormat.AUTOSAVE_PREFIX + str(i)
		var new_name := SaveFormat.AUTOSAVE_PREFIX + str(i + 1)
		if save_exists(old_name):
			if i + 1 > max_autosaves:
				delete_save(old_name)
			else:
				_rename_save(old_name, new_name)

	# Rename current autosave_1 to autosave_2
	if save_exists(SaveFormat.AUTOSAVE_PREFIX + "1"):
		_rename_save(SaveFormat.AUTOSAVE_PREFIX + "1", SaveFormat.AUTOSAVE_PREFIX + "2")

	# Create new autosave
	return save_game(SaveFormat.AUTOSAVE_PREFIX + "1", game_state, voxel_data)


## Get list of autosaves
func get_autosaves() -> Array[SaveFileInfo]:
	var autosaves: Array[SaveFileInfo] = []

	for save_info in get_save_files():
		if save_info.file_name.begins_with(SaveFormat.AUTOSAVE_PREFIX):
			autosaves.append(save_info)

	return autosaves


## Check if any autosave exists
func has_autosave() -> bool:
	return save_exists(SaveFormat.AUTOSAVE_PREFIX + "1")


## Get the most recent autosave
func get_latest_autosave() -> SaveFileInfo:
	if save_exists(SaveFormat.AUTOSAVE_PREFIX + "1"):
		return get_save_info(SaveFormat.AUTOSAVE_PREFIX + "1")
	return null


## Rename a save file
func _rename_save(old_name: String, new_name: String) -> bool:
	var old_path := SaveFormat.get_save_path(old_name)
	var new_path := SaveFormat.get_save_path(new_name)

	if not FileAccess.file_exists(old_path):
		return false

	# Delete new file if exists
	if FileAccess.file_exists(new_path):
		_binary_file.delete_save_file(new_path)

	var dir := DirAccess.open(SaveFormat.get_save_directory())
	if dir == null:
		return false

	return dir.rename(old_path.get_file(), new_path.get_file()) == OK


## Check if a save/load operation is in progress
func is_busy() -> bool:
	return _is_saving or _is_loading


## Get the current operation name if busy
func get_current_operation() -> String:
	return _current_operation


## Validate a save file
func validate_save(save_name: String) -> Dictionary:
	var result := {
		"valid": false,
		"error": "",
		"header_valid": false,
		"metadata_valid": false,
		"checksum_valid": false,
		"version": 0
	}

	var file_path := SaveFormat.get_save_path(save_name)
	var data := _binary_file.read_save_file(file_path)

	if not data.get("success", false):
		result["error"] = _binary_file.get_last_error_message()
		return result

	result["header_valid"] = data.get("header") != null
	result["metadata_valid"] = data.get("metadata") != null
	result["checksum_valid"] = true  # If we got here, checksum passed

	var header: SaveFormat.SaveHeader = data.get("header")
	if header != null:
		result["version"] = header.version

	result["valid"] = result["header_valid"] and result["metadata_valid"]
	return result


func _on_write_progress(bytes_written: int, total_bytes: int) -> void:
	if _is_saving and total_bytes > 0:
		var progress := float(bytes_written) / float(total_bytes)
		save_progress.emit(_current_operation, progress)


func _on_read_progress(bytes_read: int, total_bytes: int) -> void:
	if _is_loading and total_bytes > 0:
		var progress := float(bytes_read) / float(total_bytes)
		load_progress.emit(_current_operation, progress)


## Enable or disable automatic backups on save
func set_auto_backup_enabled(enabled: bool) -> void:
	_auto_backup_enabled = enabled
	print("SaveManager: Auto-backup %s" % ("enabled" if enabled else "disabled"))


## Check if auto-backup is enabled
func is_auto_backup_enabled() -> bool:
	return _auto_backup_enabled


## Get the backup manager for direct access
func get_backup_manager() -> BackupManagerClass:
	return _backup_manager


## Manually create a backup for a save
func create_backup(save_name: String) -> bool:
	return _backup_manager.create_backup(save_name)


## Restore from a specific backup
func restore_from_backup(save_name: String, backup_number: int = 1) -> bool:
	return _backup_manager.restore_backup(save_name, backup_number)


## Get available backups for a save
func get_backups(save_name: String) -> Array[Dictionary]:
	return _backup_manager.get_backups(save_name)


## Delete a save and all its backups
func delete_save_with_backups(save_name: String) -> bool:
	var success := delete_save(save_name)
	if success:
		_backup_manager.delete_all_backups(save_name)
	return success


## Get backup statistics
func get_backup_stats() -> Dictionary:
	return _backup_manager.get_backup_stats()
