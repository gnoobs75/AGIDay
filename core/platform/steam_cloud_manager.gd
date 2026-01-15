class_name SteamCloudManager
extends RefCounted
## SteamCloudManager handles Steam Cloud save file backup and synchronization.
## Provides automatic backup on exit and periodic sync during gameplay.

signal upload_started(file_name: String)
signal upload_completed(file_name: String, success: bool)
signal upload_progress(file_name: String, percent: float)
signal download_started(file_name: String)
signal download_completed(file_name: String, success: bool)
signal download_progress(file_name: String, percent: float)
signal conflict_detected(file_name: String, local_time: int, cloud_time: int)
signal cloud_unavailable(reason: String)
signal quota_exceeded(used: int, total: int)

## Configuration
const SYNC_INTERVAL := 300.0           ## 5 minutes
const MAX_SYNC_TIME := 2000            ## 2 seconds target
const SAVE_EXTENSION := ".agi"
const BACKUP_EXTENSIONS := [".agi.backup1", ".agi.backup2", ".agi.backup3"]

## Steam Cloud paths
const CLOUD_SAVE_PATH := "saves/"
const CLOUD_BACKUP_PATH := "backups/"

## State
var _steam_manager: SteamManager = null
var _is_available := false
var _is_syncing := false
var _sync_timer := 0.0

## File tracking
var _local_files: Dictionary = {}      ## file_name -> {path, modified_time, size}
var _cloud_files: Dictionary = {}      ## file_name -> {size, modified_time}
var _pending_uploads: Array[String] = []
var _pending_downloads: Array[String] = []

## Conflict tracking
var _conflicts: Dictionary = {}        ## file_name -> {local_time, cloud_time}

## Quota tracking
var _quota_used := 0
var _quota_total := 0


func _init() -> void:
	pass


## Initialize with Steam manager.
func initialize(steam_manager: SteamManager) -> void:
	_steam_manager = steam_manager

	if _steam_manager == null or not _steam_manager.is_initialized():
		_is_available = false
		cloud_unavailable.emit("Steam not initialized")
		return

	# Check if cloud is enabled
	_is_available = _check_cloud_available()

	if _is_available:
		_update_quota()
		_refresh_cloud_file_list()


## Check if Steam Cloud is available.
func _check_cloud_available() -> bool:
	if not Engine.has_singleton("Steam"):
		return false

	# Actual call would be: Steam.isCloudEnabled() and Steam.isCloudEnabledForApp()
	return true


## Update (call each frame).
func update(delta: float) -> void:
	if not _is_available:
		return

	_sync_timer += delta

	# Periodic sync
	if _sync_timer >= SYNC_INTERVAL and not _is_syncing:
		sync_all()
		_sync_timer = 0.0


## Sync all save files.
func sync_all() -> void:
	if not _is_available or _is_syncing:
		return

	_is_syncing = true

	# Refresh cloud file list
	_refresh_cloud_file_list()

	# Check for conflicts
	_detect_conflicts()

	# Upload local files newer than cloud
	for file_name in _local_files:
		if _should_upload(file_name):
			_pending_uploads.append(file_name)

	# Download cloud files newer than local
	for file_name in _cloud_files:
		if _should_download(file_name):
			_pending_downloads.append(file_name)

	# Process queues
	_process_uploads()
	_process_downloads()

	_is_syncing = false


## Upload save file to Steam Cloud.
func upload_file(local_path: String, cloud_name: String = "") -> bool:
	if not _is_available:
		return false

	if cloud_name.is_empty():
		cloud_name = local_path.get_file()

	# Check quota
	var file_size := _get_file_size(local_path)
	if _quota_used + file_size > _quota_total:
		quota_exceeded.emit(_quota_used, _quota_total)
		return false

	upload_started.emit(cloud_name)

	# Read file content
	var file := FileAccess.open(local_path, FileAccess.READ)
	if file == null:
		upload_completed.emit(cloud_name, false)
		return false

	var content := file.get_buffer(file.get_length())
	file.close()

	# Upload to Steam Cloud
	var success := _steam_file_write(CLOUD_SAVE_PATH + cloud_name, content)

	if success:
		_cloud_files[cloud_name] = {
			"size": content.size(),
			"modified_time": Time.get_unix_time_from_system()
		}
		_quota_used += content.size()

	upload_completed.emit(cloud_name, success)
	return success


## Download save file from Steam Cloud.
func download_file(cloud_name: String, local_path: String = "") -> bool:
	if not _is_available:
		return false

	if local_path.is_empty():
		local_path = "user://saves/" + cloud_name

	download_started.emit(cloud_name)

	# Download from Steam Cloud
	var content := _steam_file_read(CLOUD_SAVE_PATH + cloud_name)

	if content.is_empty():
		download_completed.emit(cloud_name, false)
		return false

	# Ensure directory exists
	var dir := local_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	# Write to local file
	var file := FileAccess.open(local_path, FileAccess.WRITE)
	if file == null:
		download_completed.emit(cloud_name, false)
		return false

	file.store_buffer(content)
	file.close()

	_local_files[cloud_name] = {
		"path": local_path,
		"modified_time": Time.get_unix_time_from_system(),
		"size": content.size()
	}

	download_completed.emit(cloud_name, true)
	return true


## Upload on game exit.
func upload_on_exit() -> void:
	if not _is_available:
		return

	# Force upload all local saves
	for file_name in _local_files:
		var file_data: Dictionary = _local_files[file_name]
		upload_file(file_data["path"], file_name)


## Register local file for tracking.
func register_local_file(file_name: String, local_path: String) -> void:
	var modified_time := _get_file_modified_time(local_path)
	var file_size := _get_file_size(local_path)

	_local_files[file_name] = {
		"path": local_path,
		"modified_time": modified_time,
		"size": file_size
	}


## Refresh cloud file list.
func _refresh_cloud_file_list() -> void:
	_cloud_files.clear()

	# Get file count
	var file_count := _steam_get_file_count()

	for i in file_count:
		var file_info := _steam_get_file_info(i)
		if file_info.get("name", "").begins_with(CLOUD_SAVE_PATH):
			var cloud_name := file_info["name"].substr(CLOUD_SAVE_PATH.length())
			_cloud_files[cloud_name] = {
				"size": file_info.get("size", 0),
				"modified_time": file_info.get("timestamp", 0)
			}


## Detect conflicts between local and cloud.
func _detect_conflicts() -> void:
	_conflicts.clear()

	for file_name in _local_files:
		if not _cloud_files.has(file_name):
			continue

		var local_time: int = _local_files[file_name]["modified_time"]
		var cloud_time: int = _cloud_files[file_name]["modified_time"]

		# If times are different and neither is clearly newer
		var time_diff := absi(local_time - cloud_time)
		if time_diff > 60:  ## More than 1 minute difference
			_conflicts[file_name] = {
				"local_time": local_time,
				"cloud_time": cloud_time
			}
			conflict_detected.emit(file_name, local_time, cloud_time)


## Check if file should be uploaded.
func _should_upload(file_name: String) -> bool:
	if _conflicts.has(file_name):
		return false  ## Needs conflict resolution

	if not _cloud_files.has(file_name):
		return true  ## New file

	var local_time: int = _local_files[file_name]["modified_time"]
	var cloud_time: int = _cloud_files[file_name]["modified_time"]

	return local_time > cloud_time


## Check if file should be downloaded.
func _should_download(file_name: String) -> bool:
	if _conflicts.has(file_name):
		return false  ## Needs conflict resolution

	if not _local_files.has(file_name):
		return true  ## New file from cloud

	var local_time: int = _local_files[file_name]["modified_time"]
	var cloud_time: int = _cloud_files[file_name]["modified_time"]

	return cloud_time > local_time


## Process pending uploads.
func _process_uploads() -> void:
	for file_name in _pending_uploads:
		if _local_files.has(file_name):
			upload_file(_local_files[file_name]["path"], file_name)
	_pending_uploads.clear()


## Process pending downloads.
func _process_downloads() -> void:
	for file_name in _pending_downloads:
		var local_path := "user://saves/" + file_name
		if _local_files.has(file_name):
			local_path = _local_files[file_name]["path"]
		download_file(file_name, local_path)
	_pending_downloads.clear()


## Resolve conflict - keep local.
func resolve_keep_local(file_name: String) -> void:
	if not _conflicts.has(file_name):
		return

	_conflicts.erase(file_name)

	# Upload local version
	if _local_files.has(file_name):
		upload_file(_local_files[file_name]["path"], file_name)


## Resolve conflict - use cloud.
func resolve_use_cloud(file_name: String) -> void:
	if not _conflicts.has(file_name):
		return

	_conflicts.erase(file_name)

	# Download cloud version
	var local_path := "user://saves/" + file_name
	if _local_files.has(file_name):
		local_path = _local_files[file_name]["path"]
	download_file(file_name, local_path)


## Update quota information.
func _update_quota() -> void:
	var quota := _steam_get_quota()
	_quota_used = quota.get("used", 0)
	_quota_total = quota.get("total", 0)


## Steam API wrappers (would use actual Steam calls)
func _steam_file_write(path: String, content: PackedByteArray) -> bool:
	# Actual: Steam.fileWrite(path, content)
	return true


func _steam_file_read(path: String) -> PackedByteArray:
	# Actual: Steam.fileRead(path)
	return PackedByteArray()


func _steam_get_file_count() -> int:
	# Actual: Steam.getFileCount()
	return 0


func _steam_get_file_info(index: int) -> Dictionary:
	# Actual: Steam.getFileNameAndSize(index)
	return {}


func _steam_get_quota() -> Dictionary:
	# Actual: Steam.getQuota()
	return {"used": 0, "total": 1073741824}  ## 1GB default


## Helper functions
func _get_file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size


func _get_file_modified_time(path: String) -> int:
	return FileAccess.get_modified_time(path)


## Getters
func is_available() -> bool:
	return _is_available


func is_syncing() -> bool:
	return _is_syncing


func has_conflicts() -> bool:
	return not _conflicts.is_empty()


func get_conflicts() -> Dictionary:
	return _conflicts.duplicate()


func get_quota_used() -> int:
	return _quota_used


func get_quota_total() -> int:
	return _quota_total


func get_quota_percent() -> float:
	if _quota_total <= 0:
		return 0.0
	return float(_quota_used) / float(_quota_total) * 100.0


func get_status() -> Dictionary:
	return {
		"available": _is_available,
		"syncing": _is_syncing,
		"local_files": _local_files.size(),
		"cloud_files": _cloud_files.size(),
		"conflicts": _conflicts.size(),
		"pending_uploads": _pending_uploads.size(),
		"pending_downloads": _pending_downloads.size(),
		"quota_used": _quota_used,
		"quota_total": _quota_total,
		"quota_percent": get_quota_percent()
	}


## Cleanup.
func cleanup() -> void:
	upload_on_exit()
