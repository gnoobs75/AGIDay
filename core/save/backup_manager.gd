class_name BackupManagerClass
extends RefCounted
## BackupManager handles automatic backup creation and rotation.
## Maintains 3 backup copies of each save file for corruption recovery.

signal backup_created(save_name: String, backup_number: int)
signal backup_restored(save_name: String, backup_number: int)
signal corruption_detected(save_name: String)
signal recovery_started(save_name: String)
signal recovery_completed(save_name: String, success: bool, backup_used: int)
signal recovery_failed(save_name: String, reason: String)
signal disk_space_warning(available_mb: float, required_mb: float)
signal backup_rotation_completed(save_name: String, backups_rotated: int)
signal old_backups_deleted(save_name: String, count: int)

## Number of backup copies to maintain
const MAX_BACKUPS: int = 3

## Minimum required disk space in MB
const MIN_DISK_SPACE_MB: float = 100.0

## Backup file suffix format
const BACKUP_SUFFIX: String = ".backup"

## Backup directory name
const BACKUP_DIR: String = "backups"


## Get backup directory path
func get_backup_directory() -> String:
	return "user://saves/" + BACKUP_DIR + "/"


## Ensure backup directory exists
func _ensure_backup_directory() -> bool:
	var base_dir := DirAccess.open("user://saves/")
	if base_dir == null:
		var user_dir := DirAccess.open("user://")
		if user_dir != null:
			user_dir.make_dir("saves")
			base_dir = DirAccess.open("user://saves/")

	if base_dir == null:
		push_error("BackupManager: Cannot access saves directory")
		return false

	if not base_dir.dir_exists(BACKUP_DIR):
		var err := base_dir.make_dir(BACKUP_DIR)
		if err != OK:
			push_error("BackupManager: Cannot create backup directory")
			return false

	return true


## Get backup file path for a save
func get_backup_path(save_name: String, backup_number: int) -> String:
	var backup_dir := get_backup_directory()
	return backup_dir + save_name + BACKUP_SUFFIX + str(backup_number)


## Create a backup of a save file with rotation
func create_backup(save_name: String) -> bool:
	if not _ensure_backup_directory():
		return false

	var source_path := SaveFormat.get_save_path(save_name)
	if not FileAccess.file_exists(source_path):
		push_error("BackupManager: Source file does not exist: %s" % source_path)
		return false

	# Rotate existing backups (3 -> delete, 2 -> 3, 1 -> 2)
	_rotate_backups(save_name)

	# Create new backup as backup1
	var backup_path := get_backup_path(save_name, 1)
	var success := _copy_file(source_path, backup_path)

	if success:
		backup_created.emit(save_name, 1)
		print("BackupManager: Created backup for '%s'" % save_name)

	return success


## Rotate existing backups (oldest gets deleted)
func _rotate_backups(save_name: String) -> void:
	# Delete oldest backup if exists
	var oldest_path := get_backup_path(save_name, MAX_BACKUPS)
	if FileAccess.file_exists(oldest_path):
		_delete_file(oldest_path)

	# Shift remaining backups
	for i in range(MAX_BACKUPS - 1, 0, -1):
		var current_path := get_backup_path(save_name, i)
		var next_path := get_backup_path(save_name, i + 1)
		if FileAccess.file_exists(current_path):
			_rename_file(current_path, next_path)


## Restore from backup
func restore_backup(save_name: String, backup_number: int = 1) -> bool:
	var backup_path := get_backup_path(save_name, backup_number)
	var target_path := SaveFormat.get_save_path(save_name)

	if not FileAccess.file_exists(backup_path):
		push_error("BackupManager: Backup file does not exist: %s" % backup_path)
		return false

	# Validate backup before restoring
	if not validate_backup(save_name, backup_number):
		push_error("BackupManager: Backup validation failed")
		return false

	# Copy backup to main save location
	var success := _copy_file(backup_path, target_path)

	if success:
		backup_restored.emit(save_name, backup_number)
		print("BackupManager: Restored '%s' from backup %d" % [save_name, backup_number])

	return success


## Find and restore from most recent valid backup
func restore_from_valid_backup(save_name: String) -> bool:
	for i in range(1, MAX_BACKUPS + 1):
		if has_backup(save_name, i) and validate_backup(save_name, i):
			return restore_backup(save_name, i)

	push_error("BackupManager: No valid backups found for '%s'" % save_name)
	return false


## Check if a backup exists
func has_backup(save_name: String, backup_number: int = 1) -> bool:
	var backup_path := get_backup_path(save_name, backup_number)
	return FileAccess.file_exists(backup_path)


## Check if any backup exists for a save
func has_any_backup(save_name: String) -> bool:
	for i in range(1, MAX_BACKUPS + 1):
		if has_backup(save_name, i):
			return true
	return false


## Get list of available backups for a save
func get_available_backups(save_name: String) -> Array[int]:
	var backups: Array[int] = []
	for i in range(1, MAX_BACKUPS + 1):
		if has_backup(save_name, i):
			backups.append(i)
	return backups


## Validate a backup file
func validate_backup(save_name: String, backup_number: int) -> bool:
	var backup_path := get_backup_path(save_name, backup_number)

	if not FileAccess.file_exists(backup_path):
		return false

	var binary_file := BinarySaveFile.new()
	var info := binary_file.read_save_info(backup_path)

	return info.get("success", false)


## Validate main save and restore from backup if corrupted
func validate_and_recover(save_name: String) -> Dictionary:
	var result := {
		"original_valid": false,
		"recovered": false,
		"backup_used": 0,
		"error": ""
	}

	var save_path := SaveFormat.get_save_path(save_name)

	if not FileAccess.file_exists(save_path):
		result["error"] = "Save file does not exist"
		return result

	# Validate main save
	var binary_file := BinarySaveFile.new()
	var info := binary_file.read_save_info(save_path)

	if info.get("success", false):
		result["original_valid"] = true
		return result

	# Main save is corrupted
	corruption_detected.emit(save_name)
	push_warning("BackupManager: Corruption detected in '%s', attempting recovery" % save_name)

	# Try to recover from backups
	for i in range(1, MAX_BACKUPS + 1):
		if has_backup(save_name, i) and validate_backup(save_name, i):
			if restore_backup(save_name, i):
				result["recovered"] = true
				result["backup_used"] = i
				return result

	result["error"] = "No valid backups available for recovery"
	return result


## Delete all backups for a save
func delete_all_backups(save_name: String) -> void:
	for i in range(1, MAX_BACKUPS + 1):
		var backup_path := get_backup_path(save_name, i)
		if FileAccess.file_exists(backup_path):
			_delete_file(backup_path)

	print("BackupManager: Deleted all backups for '%s'" % save_name)


## Get backup info
func get_backup_info(save_name: String, backup_number: int) -> Dictionary:
	var result := {
		"exists": false,
		"valid": false,
		"size": 0,
		"timestamp": 0
	}

	var backup_path := get_backup_path(save_name, backup_number)

	if not FileAccess.file_exists(backup_path):
		return result

	result["exists"] = true
	result["valid"] = validate_backup(save_name, backup_number)

	var file := FileAccess.open(backup_path, FileAccess.READ)
	if file != null:
		result["size"] = file.get_length()
		file.close()

	# Try to get timestamp from file metadata
	var binary_file := BinarySaveFile.new()
	var info := binary_file.read_save_info(backup_path)
	if info.get("success", false):
		var header: SaveFormat.SaveHeader = info.get("header")
		if header != null:
			result["timestamp"] = header.timestamp

	return result


## Copy file from source to destination
func _copy_file(source: String, destination: String) -> bool:
	var source_file := FileAccess.open(source, FileAccess.READ)
	if source_file == null:
		push_error("BackupManager: Cannot open source file: %s" % source)
		return false

	var data := source_file.get_buffer(source_file.get_length())
	source_file.close()

	var dest_file := FileAccess.open(destination, FileAccess.WRITE)
	if dest_file == null:
		push_error("BackupManager: Cannot create destination file: %s" % destination)
		return false

	dest_file.store_buffer(data)
	dest_file.close()

	return true


## Delete a file
func _delete_file(path: String) -> bool:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false

	return dir.remove(path.get_file()) == OK


## Rename/move a file
func _rename_file(old_path: String, new_path: String) -> bool:
	var dir := DirAccess.open(old_path.get_base_dir())
	if dir == null:
		return false

	# If different directories, need to copy then delete
	if old_path.get_base_dir() != new_path.get_base_dir():
		if _copy_file(old_path, new_path):
			return _delete_file(old_path)
		return false

	return dir.rename(old_path.get_file(), new_path.get_file()) == OK


## Get total backup size for a save in bytes
func get_total_backup_size(save_name: String) -> int:
	var total := 0

	for i in range(1, MAX_BACKUPS + 1):
		var backup_path := get_backup_path(save_name, i)
		if FileAccess.file_exists(backup_path):
			var file := FileAccess.open(backup_path, FileAccess.READ)
			if file != null:
				total += file.get_length()
				file.close()

	return total


## Clean up orphaned backups (backups without main save)
func cleanup_orphaned_backups() -> int:
	if not _ensure_backup_directory():
		return 0

	var cleaned := 0
	var backup_dir := DirAccess.open(get_backup_directory())
	if backup_dir == null:
		return 0

	backup_dir.list_dir_begin()
	var file_name := backup_dir.get_next()

	while file_name != "":
		if not backup_dir.current_is_dir() and file_name.contains(BACKUP_SUFFIX):
			# Extract save name from backup file name
			var parts := file_name.split(BACKUP_SUFFIX)
			if parts.size() > 0:
				var save_name := parts[0]
				var save_path := SaveFormat.get_save_path(save_name)

				if not FileAccess.file_exists(save_path):
					# Main save doesn't exist, delete backup
					var backup_path := get_backup_directory() + file_name
					if _delete_file(backup_path):
						cleaned += 1
						print("BackupManager: Cleaned orphaned backup: %s" % file_name)

		file_name = backup_dir.get_next()

	backup_dir.list_dir_end()
	return cleaned


## Get all backups for a save with full info
func get_backups(save_name: String) -> Array[Dictionary]:
	var backups: Array[Dictionary] = []

	for i in range(1, MAX_BACKUPS + 1):
		var info := get_backup_info(save_name, i)
		if info.get("exists", false):
			info["backup_number"] = i
			info["save_name"] = save_name
			info["formatted_date"] = SaveFormat.format_timestamp(info.get("timestamp", 0))
			backups.append(info)

	return backups


## Delete old backups beyond a certain age (in seconds)
func delete_old_backups(save_name: String, max_age_seconds: int) -> int:
	var deleted := 0
	var current_time := int(Time.get_unix_time_from_system())

	for i in range(1, MAX_BACKUPS + 1):
		var info := get_backup_info(save_name, i)
		if info.get("exists", false):
			var backup_time: int = info.get("timestamp", 0)
			var age := current_time - backup_time

			if age > max_age_seconds:
				var backup_path := get_backup_path(save_name, i)
				if _delete_file(backup_path):
					deleted += 1
					print("BackupManager: Deleted old backup %d for '%s' (age: %ds)" % [i, save_name, age])

	if deleted > 0:
		old_backups_deleted.emit(save_name, deleted)

	return deleted


## Check available disk space
func check_disk_space() -> Dictionary:
	var result := {
		"available_mb": -1.0,  # -1 means unable to determine
		"sufficient": true,
		"warning": false
	}

	# Godot doesn't provide direct disk space API, so we estimate
	# based on ability to write a test file
	var test_path := "user://saves/.disk_test"

	var test_file := FileAccess.open(test_path, FileAccess.WRITE)
	if test_file == null:
		result["sufficient"] = false
		result["warning"] = true
		return result

	test_file.close()
	_delete_file(test_path)

	# Estimate based on total backup sizes
	var total_backup_size := get_all_backups_size()
	var estimated_available := 1000.0 - (float(total_backup_size) / (1024 * 1024))  # Rough estimate

	result["available_mb"] = max(0.0, estimated_available)
	result["warning"] = estimated_available < MIN_DISK_SPACE_MB * 2
	result["sufficient"] = estimated_available > MIN_DISK_SPACE_MB

	if result["warning"]:
		disk_space_warning.emit(result["available_mb"], MIN_DISK_SPACE_MB)

	return result


## Get total size of all backups in bytes
func get_all_backups_size() -> int:
	if not _ensure_backup_directory():
		return 0

	var total := 0
	var backup_dir := DirAccess.open(get_backup_directory())
	if backup_dir == null:
		return 0

	backup_dir.list_dir_begin()
	var file_name := backup_dir.get_next()

	while file_name != "":
		if not backup_dir.current_is_dir():
			var file_path := get_backup_directory() + file_name
			var file := FileAccess.open(file_path, FileAccess.READ)
			if file != null:
				total += file.get_length()
				file.close()
		file_name = backup_dir.get_next()

	backup_dir.list_dir_end()
	return total


## Automatic recovery with user notifications
func auto_recover(save_name: String) -> Dictionary:
	recovery_started.emit(save_name)

	var result := validate_and_recover(save_name)

	if result.get("original_valid", false):
		# No recovery needed
		return result

	if result.get("recovered", false):
		recovery_completed.emit(save_name, true, result.get("backup_used", 0))
		print("BackupManager: Auto-recovery successful for '%s' using backup %d" % [
			save_name, result.get("backup_used", 0)
		])
	else:
		var error_msg: String = result.get("error", "Unknown error")
		recovery_failed.emit(save_name, error_msg)
		push_error("BackupManager: Auto-recovery failed for '%s': %s" % [save_name, error_msg])

	return result


## Get backup statistics
func get_backup_stats() -> Dictionary:
	var stats := {
		"total_backups": 0,
		"total_size_bytes": 0,
		"total_size_mb": 0.0,
		"valid_backups": 0,
		"invalid_backups": 0,
		"saves_with_backups": []
	}

	if not _ensure_backup_directory():
		return stats

	var backup_dir := DirAccess.open(get_backup_directory())
	if backup_dir == null:
		return stats

	var save_names: Dictionary = {}

	backup_dir.list_dir_begin()
	var file_name := backup_dir.get_next()

	while file_name != "":
		if not backup_dir.current_is_dir() and file_name.contains(BACKUP_SUFFIX):
			stats["total_backups"] += 1

			var file_path := get_backup_directory() + file_name
			var file := FileAccess.open(file_path, FileAccess.READ)
			if file != null:
				stats["total_size_bytes"] += file.get_length()
				file.close()

			# Extract save name
			var parts := file_name.split(BACKUP_SUFFIX)
			if parts.size() > 0:
				save_names[parts[0]] = true

		file_name = backup_dir.get_next()

	backup_dir.list_dir_end()

	stats["total_size_mb"] = float(stats["total_size_bytes"]) / (1024 * 1024)
	stats["saves_with_backups"] = save_names.keys()

	# Count valid vs invalid
	for save_name in save_names.keys():
		for i in range(1, MAX_BACKUPS + 1):
			if has_backup(save_name, i):
				if validate_backup(save_name, i):
					stats["valid_backups"] += 1
				else:
					stats["invalid_backups"] += 1

	return stats


## Create backup with disk space check
func create_backup_safe(save_name: String) -> Dictionary:
	var result := {
		"success": false,
		"error": "",
		"backup_number": 0
	}

	# Check disk space first
	var space := check_disk_space()
	if not space.get("sufficient", false):
		result["error"] = "Insufficient disk space"
		disk_space_warning.emit(space.get("available_mb", 0), MIN_DISK_SPACE_MB)
		return result

	# Create backup
	if create_backup(save_name):
		result["success"] = true
		result["backup_number"] = 1
	else:
		result["error"] = "Failed to create backup"

	return result
