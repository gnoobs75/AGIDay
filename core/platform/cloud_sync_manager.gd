class_name CloudSyncManager
extends RefCounted
## CloudSyncManager handles periodic cloud synchronization with PlayFab.
## Implements offline-first approach with conflict detection and resolution.

signal sync_started()
signal sync_completed(success: bool, conflicts: Array)
signal sync_failed(error: String)
signal conflict_detected(conflict_data: Dictionary)
signal data_uploaded(key: String)
signal data_downloaded(key: String, data: Dictionary)

## Configuration
const SYNC_INTERVAL := 300.0         ## 5 minutes
const MAX_SYNC_TIME := 500           ## 500ms target
const MAX_BANDWIDTH := 1048576       ## 1MB per sync
const MAX_LATENCY := 2000            ## 2 second max latency

## State
var _playfab: PlayFabManager = null
var _is_syncing := false
var _last_sync_time := 0.0
var _sync_timer := 0.0
var _is_online := true

## Local data cache
var _local_data: Dictionary = {}
var _local_timestamps: Dictionary = {}  ## key -> last modified time
var _cloud_timestamps: Dictionary = {}  ## key -> cloud timestamp

## Pending changes
var _pending_uploads: Dictionary = {}
var _pending_downloads: Array[String] = []

## Conflict tracking
var _conflicts: Array[SyncConflict] = []
var _rejected_versions: Dictionary = {}  ## For recovery

## Sync keys
const SYNC_KEYS := [
	"player_profile",
	"achievements",
	"statistics",
	"settings",
	"progression"
]

## Local storage path
const CACHE_PATH := "user://cloud_sync_cache.json"


func _init() -> void:
	_load_local_cache()


## Initialize with PlayFab manager.
func initialize(playfab: PlayFabManager) -> void:
	_playfab = playfab

	if _playfab != null:
		_playfab.profile_fetched.connect(_on_profile_fetched)
		_playfab.profile_updated.connect(_on_profile_updated)


## Update (call each frame).
func update(delta: float) -> void:
	_sync_timer += delta

	# Periodic sync
	if _sync_timer >= SYNC_INTERVAL and not _is_syncing:
		sync()
		_sync_timer = 0.0


## Start synchronization.
func sync() -> void:
	if _is_syncing:
		return

	if _playfab == null or not _playfab.is_logged_in():
		sync_failed.emit("Not logged in to PlayFab")
		return

	_is_syncing = true
	sync_started.emit()

	# Download cloud data first
	_download_cloud_data()


## Force sync (call on game exit).
func force_sync() -> void:
	_sync_timer = 0.0
	sync()


## Set local data.
func set_data(key: String, data: Dictionary) -> void:
	_local_data[key] = data.duplicate(true)
	_local_timestamps[key] = Time.get_ticks_msec()
	_pending_uploads[key] = data.duplicate(true)

	_save_local_cache()


## Get local data.
func get_data(key: String) -> Dictionary:
	return _local_data.get(key, {}).duplicate(true)


## Download cloud data.
func _download_cloud_data() -> void:
	if _playfab == null:
		_on_sync_complete(false)
		return

	_playfab.fetch_profile()


## Handle profile fetched.
func _on_profile_fetched(profile: Dictionary) -> void:
	var start_time := Time.get_ticks_msec()

	# Check each key for conflicts
	_conflicts.clear()

	for key in profile:
		if not key.begins_with("sync_"):
			continue

		var clean_key := key.substr(5)  ## Remove "sync_" prefix
		var cloud_data := _parse_cloud_value(profile[key])
		var cloud_timestamp: int = cloud_data.get("timestamp", 0)

		# Update cloud timestamps
		_cloud_timestamps[clean_key] = cloud_timestamp

		# Check for conflict
		if _pending_uploads.has(clean_key):
			var local_timestamp: int = _local_timestamps.get(clean_key, 0)

			if cloud_timestamp > local_timestamp:
				# Cloud is newer - conflict
				var conflict := SyncConflict.new()
				conflict.key = clean_key
				conflict.local_data = _local_data.get(clean_key, {})
				conflict.cloud_data = cloud_data.get("data", {})
				conflict.local_timestamp = local_timestamp
				conflict.cloud_timestamp = cloud_timestamp
				_conflicts.append(conflict)
			else:
				# Local is newer - upload
				pass
		else:
			# No local changes - accept cloud data
			_local_data[clean_key] = cloud_data.get("data", {})
			_local_timestamps[clean_key] = cloud_timestamp
			data_downloaded.emit(clean_key, cloud_data.get("data", {}))

	# If no conflicts, upload pending changes
	if _conflicts.is_empty():
		_upload_pending_changes()
	else:
		# Report conflicts for resolution
		for conflict in _conflicts:
			conflict_detected.emit(conflict.to_dict())

		_on_sync_complete(true)

	var elapsed := Time.get_ticks_msec() - start_time
	if elapsed > MAX_SYNC_TIME:
		push_warning("CloudSyncManager: Sync took %dms (target: %dms)" % [elapsed, MAX_SYNC_TIME])


## Upload pending changes.
func _upload_pending_changes() -> void:
	if _playfab == null or _pending_uploads.is_empty():
		_on_sync_complete(true)
		return

	var upload_data := {}
	for key in _pending_uploads:
		var sync_key := "sync_" + key
		upload_data[sync_key] = JSON.stringify({
			"data": _pending_uploads[key],
			"timestamp": _local_timestamps.get(key, Time.get_ticks_msec())
		})

	_playfab.update_profile(upload_data)


## Handle profile updated.
func _on_profile_updated(success: bool) -> void:
	if success:
		# Clear pending uploads
		for key in _pending_uploads:
			data_uploaded.emit(key)
		_pending_uploads.clear()

	_on_sync_complete(success)


## Parse cloud value (JSON string to Dictionary).
func _parse_cloud_value(value: String) -> Dictionary:
	var parsed = JSON.parse_string(value)
	if parsed is Dictionary:
		return parsed
	return {"data": {}, "timestamp": 0}


## Handle sync completion.
func _on_sync_complete(success: bool) -> void:
	_is_syncing = false
	_last_sync_time = Time.get_ticks_msec()
	_save_local_cache()

	var conflict_data: Array = []
	for conflict in _conflicts:
		conflict_data.append(conflict.to_dict())

	sync_completed.emit(success, conflict_data)


## Resolve conflict - keep local.
func resolve_keep_local(key: String) -> void:
	for i in _conflicts.size():
		if _conflicts[i].key == key:
			# Store rejected cloud version for recovery
			_rejected_versions[key] = {
				"data": _conflicts[i].cloud_data,
				"timestamp": _conflicts[i].cloud_timestamp,
				"rejected_at": Time.get_ticks_msec()
			}

			# Keep local data and force upload
			_pending_uploads[key] = _local_data.get(key, {})
			_conflicts.remove_at(i)
			break

	_save_local_cache()

	# Upload the local version
	if _conflicts.is_empty():
		_upload_pending_changes()


## Resolve conflict - use cloud.
func resolve_use_cloud(key: String) -> void:
	for i in _conflicts.size():
		if _conflicts[i].key == key:
			# Store rejected local version for recovery
			_rejected_versions[key] = {
				"data": _conflicts[i].local_data,
				"timestamp": _conflicts[i].local_timestamp,
				"rejected_at": Time.get_ticks_msec()
			}

			# Use cloud data
			_local_data[key] = _conflicts[i].cloud_data.duplicate(true)
			_local_timestamps[key] = _conflicts[i].cloud_timestamp
			_pending_uploads.erase(key)
			_conflicts.remove_at(i)

			data_downloaded.emit(key, _local_data[key])
			break

	_save_local_cache()

	if _conflicts.is_empty():
		_on_sync_complete(true)


## Recover rejected version.
func recover_rejected(key: String) -> Dictionary:
	if _rejected_versions.has(key):
		var recovered: Dictionary = _rejected_versions[key]
		_rejected_versions.erase(key)
		return recovered.get("data", {})
	return {}


## Merge non-conflicting changes.
func merge_non_conflicting(key: String, local_data: Dictionary, cloud_data: Dictionary) -> Dictionary:
	var merged := cloud_data.duplicate(true)

	# For each local key, if not in cloud or cloud is older, use local
	for local_key in local_data:
		if not cloud_data.has(local_key):
			merged[local_key] = local_data[local_key]

	return merged


## Get pending conflicts.
func get_conflicts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for conflict in _conflicts:
		result.append(conflict.to_dict())
	return result


## Has pending conflicts.
func has_conflicts() -> bool:
	return not _conflicts.is_empty()


## Is currently syncing.
func is_syncing() -> bool:
	return _is_syncing


## Get time until next sync.
func get_time_until_sync() -> float:
	return maxf(0, SYNC_INTERVAL - _sync_timer)


## Get last sync time.
func get_last_sync_time() -> float:
	return _last_sync_time


## Set online status.
func set_online(online: bool) -> void:
	_is_online = online


## Save local cache.
func _save_local_cache() -> void:
	var cache := {
		"local_data": _local_data,
		"local_timestamps": _local_timestamps,
		"cloud_timestamps": _cloud_timestamps,
		"pending_uploads": _pending_uploads,
		"rejected_versions": _rejected_versions,
		"last_sync": _last_sync_time
	}

	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(cache))
		file.close()


## Load local cache.
func _load_local_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return

	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return

	var json_string := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_string)
	if parsed is Dictionary:
		_local_data = parsed.get("local_data", {})
		_local_timestamps = parsed.get("local_timestamps", {})
		_cloud_timestamps = parsed.get("cloud_timestamps", {})
		_pending_uploads = parsed.get("pending_uploads", {})
		_rejected_versions = parsed.get("rejected_versions", {})
		_last_sync_time = parsed.get("last_sync", 0.0)


## Get status.
func get_status() -> Dictionary:
	return {
		"is_syncing": _is_syncing,
		"is_online": _is_online,
		"last_sync": _last_sync_time,
		"pending_uploads": _pending_uploads.size(),
		"conflicts": _conflicts.size(),
		"rejected_versions": _rejected_versions.size(),
		"time_until_sync": get_time_until_sync()
	}


## SyncConflict helper class.
class SyncConflict:
	var key: String = ""
	var local_data: Dictionary = {}
	var cloud_data: Dictionary = {}
	var local_timestamp: int = 0
	var cloud_timestamp: int = 0

	func to_dict() -> Dictionary:
		return {
			"key": key,
			"local_data": local_data,
			"cloud_data": cloud_data,
			"local_timestamp": local_timestamp,
			"cloud_timestamp": cloud_timestamp,
			"local_newer": local_timestamp > cloud_timestamp
		}
