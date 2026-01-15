class_name CloudSyncAPI
extends RefCounted
## CloudSyncAPI provides high-level cloud synchronization interface.
## Wraps PlayFab and CloudSyncManager for easy integration.

signal sync_started()
signal sync_completed(success: bool)
signal sync_failed(error: String)
signal sync_progress(percent: float)
signal leaderboard_submitted(leaderboard_name: String, success: bool)
signal achievement_unlocked(achievement_id: String)
signal leaderboard_received(leaderboard_name: String, entries: Array)
signal conflict_detected(key: String, local_data: Dictionary, cloud_data: Dictionary)

## Configuration
const SYNC_INTERVAL := 300.0         ## 5 minutes
const MAX_BANDWIDTH_BYTES := 1048576 ## 1MB per sync
const AVG_BANDWIDTH_BPS := 102400    ## 100KB/s average

## Sub-systems
var _playfab: PlayFabManager = null
var _cloud_sync: CloudSyncManager = null
var _achievement_manager: AchievementManager = null
var _leaderboard_manager: LeaderboardManager = null
var _conflict_resolver: ConflictResolver = null

## State
var _is_initialized := false
var _is_online := false
var _sync_timer := 0.0
var _last_sync_result := true
var _pending_operations: Array[Dictionary] = []

## Bandwidth tracking
var _bytes_sent_this_sync := 0
var _sync_start_time := 0.0


func _init() -> void:
	pass


## Initialize the CloudSync API.
func initialize(http_node: Node, title_id: String = "") -> void:
	# Create sub-systems
	_playfab = PlayFabManager.new()
	_playfab.initialize(title_id, http_node)

	_cloud_sync = CloudSyncManager.new()
	_cloud_sync.initialize(_playfab)

	_achievement_manager = AchievementManager.new()
	_achievement_manager.initialize(null)  ## No Steam for cloud-only

	_leaderboard_manager = LeaderboardManager.new()
	_leaderboard_manager.initialize(null)

	_conflict_resolver = ConflictResolver.new()

	# Connect signals
	_playfab.login_completed.connect(_on_login_completed)
	_playfab.login_failed.connect(_on_login_failed)
	_cloud_sync.sync_completed.connect(_on_sync_completed)
	_cloud_sync.conflict_detected.connect(_on_conflict_detected)

	_is_initialized = true


## Login to cloud services.
func login(device_id: String = "") -> void:
	if not _is_initialized or _playfab == null:
		sync_failed.emit("CloudSync not initialized")
		return

	if device_id.is_empty():
		device_id = _generate_device_id()

	_playfab.login_with_device_id(device_id)


## Update (call each frame).
func update(delta: float) -> void:
	if not _is_initialized:
		return

	_sync_timer += delta

	# Periodic sync
	if _sync_timer >= SYNC_INTERVAL and _is_online:
		sync_to_cloud()
		_sync_timer = 0.0

	# Update sub-systems
	if _playfab != null:
		_playfab.update(delta)
	if _cloud_sync != null:
		_cloud_sync.update(delta)


## Sync local data to cloud.
func sync_to_cloud() -> void:
	if not _is_online:
		sync_failed.emit("Not connected to cloud")
		return

	_bytes_sent_this_sync = 0
	_sync_start_time = Time.get_ticks_msec()
	sync_started.emit()

	_cloud_sync.sync()


## Sync data from cloud to local.
func sync_from_cloud() -> void:
	if not _is_online:
		sync_failed.emit("Not connected to cloud")
		return

	sync_started.emit()
	_cloud_sync.sync()


## Submit score to leaderboard.
func submit_leaderboard_score(leaderboard_name: String, score: int, game_data: Dictionary = {}) -> void:
	if not _is_online:
		# Queue for later
		_pending_operations.append({
			"type": "leaderboard",
			"leaderboard": leaderboard_name,
			"score": score,
			"game_data": game_data
		})
		return

	if _playfab != null:
		_playfab.submit_score(leaderboard_name, score, game_data)

	if _leaderboard_manager != null:
		_leaderboard_manager.upload_score(leaderboard_name, score)

	leaderboard_submitted.emit(leaderboard_name, true)


## Unlock an achievement.
func unlock_achievement(achievement_id: String) -> void:
	if _achievement_manager != null:
		# Achievement manager handles offline queueing
		_achievement_manager.check_progress(achievement_id, 1, true)

	achievement_unlocked.emit(achievement_id)


## Track achievement progress.
func track_achievement_progress(stat_key: String, value: int = 1) -> void:
	if _achievement_manager != null:
		_achievement_manager.check_progress(stat_key, value)


## Get leaderboard entries.
func get_leaderboard(leaderboard_name: String, start: int = 0, count: int = 10) -> void:
	if not _is_online:
		# Return cached data
		if _leaderboard_manager != null:
			var cached := _leaderboard_manager.get_cached_entries(leaderboard_name)
			leaderboard_received.emit(leaderboard_name, cached)
		return

	if _playfab != null:
		_playfab.leaderboard_fetched.connect(
			func(name, entries):
				if name == leaderboard_name:
					leaderboard_received.emit(name, entries),
			CONNECT_ONE_SHOT
		)
		_playfab.fetch_leaderboard(leaderboard_name, start, count)


## Set cloud data for a key.
func set_cloud_data(key: String, data: Dictionary) -> void:
	if _cloud_sync != null:
		_cloud_sync.set_data(key, data)


## Get cloud data for a key.
func get_cloud_data(key: String) -> Dictionary:
	if _cloud_sync != null:
		return _cloud_sync.get_data(key)
	return {}


## Force sync on game exit.
func sync_on_exit() -> void:
	if _is_online:
		_cloud_sync.force_sync()


## Resolve conflict - keep local.
func resolve_conflict_keep_local(key: String) -> void:
	if _cloud_sync != null:
		_cloud_sync.resolve_keep_local(key)
	if _conflict_resolver != null:
		_conflict_resolver.resolve_manual_keep_local(key)


## Resolve conflict - use cloud.
func resolve_conflict_use_cloud(key: String) -> void:
	if _cloud_sync != null:
		_cloud_sync.resolve_use_cloud(key)
	if _conflict_resolver != null:
		_conflict_resolver.resolve_manual_use_cloud(key)


## Handle login completed.
func _on_login_completed(success: bool, _player_id: String) -> void:
	_is_online = success

	if success:
		# Process pending operations
		_process_pending_operations()
		# Initial sync
		sync_from_cloud()


## Handle login failed.
func _on_login_failed(error: String) -> void:
	_is_online = false
	sync_failed.emit("Login failed: " + error)


## Handle sync completed.
func _on_sync_completed(success: bool, conflicts: Array) -> void:
	_last_sync_result = success

	var elapsed := Time.get_ticks_msec() - _sync_start_time
	var bandwidth := _bytes_sent_this_sync

	if bandwidth > MAX_BANDWIDTH_BYTES:
		push_warning("CloudSyncAPI: Sync exceeded bandwidth limit: %d bytes" % bandwidth)

	sync_completed.emit(success)


## Handle conflict detected.
func _on_conflict_detected(conflict_data: Dictionary) -> void:
	conflict_detected.emit(
		conflict_data.get("key", ""),
		conflict_data.get("local_data", {}),
		conflict_data.get("cloud_data", {})
	)


## Process pending operations.
func _process_pending_operations() -> void:
	for op in _pending_operations:
		match op["type"]:
			"leaderboard":
				submit_leaderboard_score(op["leaderboard"], op["score"], op.get("game_data", {}))
			"achievement":
				unlock_achievement(op["achievement_id"])

	_pending_operations.clear()


## Generate device ID.
func _generate_device_id() -> String:
	var id := ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 32:
		id += "%x" % rng.randi_range(0, 15)
	return id


## Is connected to cloud.
func is_online() -> bool:
	return _is_online


## Is sync in progress.
func is_syncing() -> bool:
	if _cloud_sync != null:
		return _cloud_sync.is_syncing()
	return false


## Has pending conflicts.
func has_conflicts() -> bool:
	if _cloud_sync != null:
		return _cloud_sync.has_conflicts()
	return false


## Get conflicts.
func get_conflicts() -> Array:
	if _cloud_sync != null:
		return _cloud_sync.get_conflicts()
	return []


## Get sync status.
func get_sync_status() -> Dictionary:
	return {
		"initialized": _is_initialized,
		"online": _is_online,
		"syncing": is_syncing(),
		"last_sync_success": _last_sync_result,
		"time_until_sync": maxf(0, SYNC_INTERVAL - _sync_timer),
		"pending_operations": _pending_operations.size(),
		"has_conflicts": has_conflicts()
	}


## Cleanup.
func cleanup() -> void:
	sync_on_exit()
	_is_initialized = false
	_is_online = false
