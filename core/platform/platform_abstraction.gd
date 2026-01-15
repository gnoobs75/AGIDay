class_name PlatformAbstraction
extends RefCounted
## PlatformAbstraction provides a unified interface for platform-specific features.
## Abstracts Steam, PlayFab, and future platform integrations.

signal achievement_unlocked(achievement_id: String)
signal leaderboard_submitted(leaderboard_name: String, success: bool)
signal cloud_sync_completed(success: bool)
signal platform_initialized(platform_name: String)
signal user_logged_in(user_id: String, display_name: String)
signal user_logged_out()

## Platform types
enum Platform {
	NONE,
	STEAM,
	PLAYFAB,
	CUSTOM
}

## Current platform
var _current_platform := Platform.NONE
var _platform_name := "none"

## Sub-systems
var _steam_manager: SteamManager = null
var _achievement_manager: AchievementManager = null
var _leaderboard_manager: LeaderboardManager = null
var _cloud_sync_manager: CloudSyncManager = null
var _steam_cloud_manager: SteamCloudManager = null
var _playfab_manager: PlayFabManager = null
var _cloud_sync_api: CloudSyncAPI = null

## User info
var _user_id := ""
var _display_name := ""
var _is_logged_in := false

## State
var _is_initialized := false
var _http_node: Node = null


func _init() -> void:
	pass


## Initialize platform services.
func initialize(http_node: Node = null, force_platform: Platform = Platform.NONE) -> void:
	_http_node = http_node

	# Detect platform
	if force_platform != Platform.NONE:
		_current_platform = force_platform
	else:
		_current_platform = _detect_platform()

	_platform_name = _get_platform_name(_current_platform)

	# Initialize based on platform
	match _current_platform:
		Platform.STEAM:
			_initialize_steam()
		Platform.PLAYFAB:
			_initialize_playfab()
		Platform.CUSTOM:
			_initialize_custom()
		Platform.NONE:
			push_warning("PlatformAbstraction: No platform detected, using offline mode")

	_is_initialized = true
	platform_initialized.emit(_platform_name)


## Detect available platform.
func _detect_platform() -> Platform:
	# Check for Steam
	if Engine.has_singleton("Steam"):
		return Platform.STEAM

	# Check for PlayFab configuration
	if _http_node != null:
		return Platform.PLAYFAB

	return Platform.NONE


## Initialize Steam platform.
func _initialize_steam() -> void:
	_steam_manager = SteamManager.new()
	_steam_manager.initialize()

	if _steam_manager.is_initialized():
		_user_id = _steam_manager.get_steam_id()
		_display_name = _steam_manager.get_player_name()
		_is_logged_in = true

		# Initialize Steam sub-systems
		_achievement_manager = AchievementManager.new()
		_achievement_manager.initialize(_steam_manager)

		_leaderboard_manager = LeaderboardManager.new()
		_leaderboard_manager.initialize(_steam_manager)

		_steam_cloud_manager = SteamCloudManager.new()
		_steam_cloud_manager.initialize(_steam_manager)

		# Connect signals
		_steam_manager.achievement_unlocked.connect(_on_achievement_unlocked)

		user_logged_in.emit(_user_id, _display_name)


## Initialize PlayFab platform.
func _initialize_playfab() -> void:
	if _http_node == null:
		push_error("PlatformAbstraction: HTTP node required for PlayFab")
		return

	_playfab_manager = PlayFabManager.new()
	_playfab_manager.initialize("", _http_node)  ## Title ID from config

	_cloud_sync_manager = CloudSyncManager.new()
	_cloud_sync_manager.initialize(_playfab_manager)

	_cloud_sync_api = CloudSyncAPI.new()
	_cloud_sync_api.initialize(_http_node)

	# Connect signals
	_playfab_manager.login_completed.connect(_on_playfab_login)
	_cloud_sync_api.sync_completed.connect(_on_cloud_sync_completed)

	# Achievement manager (local-only without Steam)
	_achievement_manager = AchievementManager.new()
	_achievement_manager.initialize(null)


## Initialize custom platform (fallback).
func _initialize_custom() -> void:
	# Local-only achievements
	_achievement_manager = AchievementManager.new()
	_achievement_manager.initialize(null)


## Update (call each frame).
func update(delta: float) -> void:
	if not _is_initialized:
		return

	if _steam_manager != null:
		_steam_manager.update(delta)

	if _playfab_manager != null:
		_playfab_manager.update(delta)

	if _cloud_sync_manager != null:
		_cloud_sync_manager.update(delta)

	if _cloud_sync_api != null:
		_cloud_sync_api.update(delta)

	if _steam_cloud_manager != null:
		_steam_cloud_manager.update(delta)


## Unlock achievement (platform-agnostic).
func unlock_achievement(achievement_id: String) -> void:
	if _achievement_manager != null:
		_achievement_manager.check_progress(achievement_id, 1, true)

	if _cloud_sync_api != null:
		_cloud_sync_api.unlock_achievement(achievement_id)


## Track achievement progress.
func track_achievement_progress(stat_key: String, value: int = 1) -> void:
	if _achievement_manager != null:
		_achievement_manager.check_progress(stat_key, value)


## Submit leaderboard score.
func submit_leaderboard_score(leaderboard_name: String, score: int, extra_data: Dictionary = {}) -> void:
	if _leaderboard_manager != null:
		_leaderboard_manager.upload_score(leaderboard_name, score, extra_data)
		leaderboard_submitted.emit(leaderboard_name, true)

	if _cloud_sync_api != null:
		_cloud_sync_api.submit_leaderboard_score(leaderboard_name, score, extra_data)


## Get leaderboard entries.
func get_leaderboard_entries(leaderboard_name: String, start: int = 0, count: int = 10) -> void:
	if _leaderboard_manager != null:
		_leaderboard_manager.download_entries(leaderboard_name, start, start + count)
	elif _cloud_sync_api != null:
		_cloud_sync_api.get_leaderboard(leaderboard_name, start, count)


## Sync to cloud.
func sync_to_cloud() -> void:
	if _cloud_sync_api != null:
		_cloud_sync_api.sync_to_cloud()
	elif _steam_cloud_manager != null:
		_steam_cloud_manager.sync_all()


## Sync from cloud.
func sync_from_cloud() -> void:
	if _cloud_sync_api != null:
		_cloud_sync_api.sync_from_cloud()
	elif _steam_cloud_manager != null:
		_steam_cloud_manager.sync_all()


## Set cloud data.
func set_cloud_data(key: String, data: Dictionary) -> void:
	if _cloud_sync_api != null:
		_cloud_sync_api.set_cloud_data(key, data)
	elif _cloud_sync_manager != null:
		_cloud_sync_manager.set_data(key, data)


## Get cloud data.
func get_cloud_data(key: String) -> Dictionary:
	if _cloud_sync_api != null:
		return _cloud_sync_api.get_cloud_data(key)
	elif _cloud_sync_manager != null:
		return _cloud_sync_manager.get_data(key)
	return {}


## Register save file for cloud backup.
func register_save_file(file_name: String, local_path: String) -> void:
	if _steam_cloud_manager != null:
		_steam_cloud_manager.register_local_file(file_name, local_path)


## Upload save file to cloud.
func upload_save_file(local_path: String, cloud_name: String = "") -> bool:
	if _steam_cloud_manager != null:
		return _steam_cloud_manager.upload_file(local_path, cloud_name)
	return false


## Download save file from cloud.
func download_save_file(cloud_name: String, local_path: String = "") -> bool:
	if _steam_cloud_manager != null:
		return _steam_cloud_manager.download_file(cloud_name, local_path)
	return false


## Sync on game exit.
func sync_on_exit() -> void:
	if _cloud_sync_api != null:
		_cloud_sync_api.sync_on_exit()
	if _steam_cloud_manager != null:
		_steam_cloud_manager.upload_on_exit()


## Handle achievement unlocked.
func _on_achievement_unlocked(ach_id: String) -> void:
	achievement_unlocked.emit(ach_id)


## Handle PlayFab login.
func _on_playfab_login(success: bool, player_id: String) -> void:
	if success:
		_user_id = player_id
		_display_name = "Player"  ## PlayFab doesn't provide display name by default
		_is_logged_in = true
		user_logged_in.emit(_user_id, _display_name)


## Handle cloud sync completed.
func _on_cloud_sync_completed(success: bool) -> void:
	cloud_sync_completed.emit(success)


## Check if logged in.
func is_logged_in() -> bool:
	return _is_logged_in


## Get user ID.
func get_user_id() -> String:
	return _user_id


## Get display name.
func get_display_name() -> String:
	return _display_name


## Get current platform.
func get_platform() -> Platform:
	return _current_platform


## Get platform name.
func get_platform_name() -> String:
	return _platform_name


## Get platform name string.
func _get_platform_name(platform: Platform) -> String:
	match platform:
		Platform.STEAM: return "Steam"
		Platform.PLAYFAB: return "PlayFab"
		Platform.CUSTOM: return "Custom"
		Platform.NONE: return "Offline"
	return "Unknown"


## Check if online features available.
func is_online() -> bool:
	if _current_platform == Platform.STEAM:
		return _steam_manager != null and _steam_manager.is_initialized()
	elif _current_platform == Platform.PLAYFAB:
		return _cloud_sync_api != null and _cloud_sync_api.is_online()
	return false


## Check if cloud sync available.
func is_cloud_sync_available() -> bool:
	if _steam_cloud_manager != null:
		return _steam_cloud_manager.is_available()
	if _cloud_sync_api != null:
		return _cloud_sync_api.is_online()
	return false


## Has pending cloud conflicts.
func has_cloud_conflicts() -> bool:
	if _steam_cloud_manager != null:
		return _steam_cloud_manager.has_conflicts()
	if _cloud_sync_api != null:
		return _cloud_sync_api.has_conflicts()
	return false


## Get cloud conflicts.
func get_cloud_conflicts() -> Array:
	if _cloud_sync_api != null:
		return _cloud_sync_api.get_conflicts()
	if _steam_cloud_manager != null:
		return [_steam_cloud_manager.get_conflicts()]
	return []


## Resolve conflict - keep local.
func resolve_conflict_keep_local(key: String) -> void:
	if _cloud_sync_api != null:
		_cloud_sync_api.resolve_conflict_keep_local(key)
	if _steam_cloud_manager != null:
		_steam_cloud_manager.resolve_keep_local(key)


## Resolve conflict - use cloud.
func resolve_conflict_use_cloud(key: String) -> void:
	if _cloud_sync_api != null:
		_cloud_sync_api.resolve_conflict_use_cloud(key)
	if _steam_cloud_manager != null:
		_steam_cloud_manager.resolve_use_cloud(key)


## Get sync status for UI.
func get_sync_status() -> Dictionary:
	var status := {
		"platform": _platform_name,
		"online": is_online(),
		"syncing": false,
		"has_conflicts": has_cloud_conflicts(),
		"last_sync_success": true
	}

	if _cloud_sync_api != null:
		var api_status := _cloud_sync_api.get_sync_status()
		status["syncing"] = api_status.get("syncing", false)
		status["last_sync_success"] = api_status.get("last_sync_success", true)
		status["time_until_sync"] = api_status.get("time_until_sync", 0)
		status["pending_operations"] = api_status.get("pending_operations", 0)

	if _steam_cloud_manager != null:
		var steam_status := _steam_cloud_manager.get_status()
		status["syncing"] = steam_status.get("syncing", false)
		status["quota_percent"] = steam_status.get("quota_percent", 0)

	return status


## Get achievement progress.
func get_achievement_progress(achievement_id: String) -> Dictionary:
	if _achievement_manager != null:
		return _achievement_manager.get_achievement_progress(achievement_id)
	return {}


## Get all achievements.
func get_all_achievements() -> Array:
	if _achievement_manager != null:
		return _achievement_manager.get_all_achievements()
	return []


## Serialize state.
func to_dict() -> Dictionary:
	return {
		"platform": _current_platform,
		"user_id": _user_id,
		"display_name": _display_name
	}


## Cleanup.
func cleanup() -> void:
	sync_on_exit()

	if _steam_manager != null:
		_steam_manager.cleanup()
	if _cloud_sync_api != null:
		_cloud_sync_api.cleanup()
	if _steam_cloud_manager != null:
		_steam_cloud_manager.cleanup()
