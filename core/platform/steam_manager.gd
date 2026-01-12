class_name SteamManager
extends RefCounted
## SteamManager provides Steam API integration using GodotSteam.
## Handles initialization, achievement unlocking, and leaderboard management.

signal steam_initialized(success: bool)
signal steam_error(error: String)
signal overlay_toggled(active: bool)
signal stats_received()
signal stats_stored()

## Steam state
var _initialized := false
var _steam_id := 0
var _persona_name := ""
var _stats_received := false

## Pending operations for offline mode
var _pending_achievements: Array[String] = []
var _pending_stats: Dictionary = {}
var _pending_leaderboard_scores: Array[Dictionary] = []

## Error handling
var _last_error := ""
var _retry_timer := 0.0
const RETRY_INTERVAL := 30.0


func _init() -> void:
	pass


## Initialize Steam API.
func initialize() -> bool:
	# Check if Steam is available (GodotSteam check)
	if not _is_steam_available():
		push_warning("SteamManager: Steam API not available (running without Steam)")
		_initialized = false
		steam_initialized.emit(false)
		return false

	# Initialize Steam
	var init_result: Dictionary = _steam_init()

	if init_result.get("status") != 1:
		_last_error = init_result.get("verbal", "Unknown Steam error")
		push_error("SteamManager: Failed to initialize: " + _last_error)
		steam_error.emit(_last_error)
		steam_initialized.emit(false)
		return false

	_initialized = true
	_steam_id = _get_steam_id()
	_persona_name = _get_persona_name()

	# Request user stats
	_request_current_stats()

	steam_initialized.emit(true)
	return true


## Check if Steam is available.
func _is_steam_available() -> bool:
	# Check if Steam singleton exists (GodotSteam)
	# In actual implementation, this would check for the Steam class
	return Engine.has_singleton("Steam")


## Initialize Steam (wrapper for actual Steam call).
func _steam_init() -> Dictionary:
	if not _is_steam_available():
		return {"status": 0, "verbal": "Steam not available"}

	# Actual Steam call would be: Steam.steamInit()
	# For now, return mock success
	return {"status": 1, "verbal": "OK"}


## Get Steam ID.
func _get_steam_id() -> int:
	if not _is_steam_available():
		return 0
	# Actual call: return Steam.getSteamID()
	return 0


## Get persona name.
func _get_persona_name() -> String:
	if not _is_steam_available():
		return "Player"
	# Actual call: return Steam.getPersonaName()
	return "Player"


## Request current stats from Steam.
func _request_current_stats() -> void:
	if not _initialized or not _is_steam_available():
		return
	# Actual call: Steam.requestCurrentStats()
	# Steam will emit current_stats_received signal when done
	_stats_received = true
	stats_received.emit()


## Update (call periodically to process Steam callbacks).
func update(delta: float) -> void:
	if not _initialized:
		_retry_timer += delta
		if _retry_timer >= RETRY_INTERVAL:
			_retry_timer = 0.0
			initialize()  ## Retry initialization
		return

	# Run Steam callbacks
	if _is_steam_available():
		# Actual call: Steam.run_callbacks()
		pass

	# Process pending operations if online
	_process_pending_operations()


## Set achievement.
func set_achievement(achievement_id: String) -> bool:
	if not _initialized:
		_pending_achievements.append(achievement_id)
		return false

	if not _is_steam_available():
		return false

	# Actual call: Steam.setAchievement(achievement_id)
	# Then: Steam.storeStats()
	return true


## Clear achievement (for testing).
func clear_achievement(achievement_id: String) -> bool:
	if not _initialized or not _is_steam_available():
		return false

	# Actual call: Steam.clearAchievement(achievement_id)
	return true


## Get achievement status.
func get_achievement(achievement_id: String) -> Dictionary:
	if not _initialized or not _is_steam_available():
		return {"achieved": false, "name": achievement_id}

	# Actual call: return Steam.getAchievement(achievement_id)
	return {"achieved": false, "name": achievement_id}


## Set stat value (integer).
func set_stat_int(stat_name: String, value: int) -> bool:
	if not _initialized:
		_pending_stats[stat_name] = {"type": "int", "value": value}
		return false

	if not _is_steam_available():
		return false

	# Actual call: Steam.setStatInt(stat_name, value)
	return true


## Set stat value (float).
func set_stat_float(stat_name: String, value: float) -> bool:
	if not _initialized:
		_pending_stats[stat_name] = {"type": "float", "value": value}
		return false

	if not _is_steam_available():
		return false

	# Actual call: Steam.setStatFloat(stat_name, value)
	return true


## Get stat value (integer).
func get_stat_int(stat_name: String) -> int:
	if not _initialized or not _is_steam_available():
		return 0

	# Actual call: return Steam.getStatInt(stat_name)
	return 0


## Get stat value (float).
func get_stat_float(stat_name: String) -> float:
	if not _initialized or not _is_steam_available():
		return 0.0

	# Actual call: return Steam.getStatFloat(stat_name)
	return 0.0


## Store stats to Steam.
func store_stats() -> bool:
	if not _initialized or not _is_steam_available():
		return false

	# Actual call: Steam.storeStats()
	stats_stored.emit()
	return true


## Find or create leaderboard.
func find_leaderboard(leaderboard_name: String) -> void:
	if not _initialized or not _is_steam_available():
		return

	# Actual call: Steam.findLeaderboard(leaderboard_name)
	# Steam will emit leaderboard_find_result signal


## Upload leaderboard score.
func upload_score(leaderboard_id: int, score: int, keep_best: bool = true) -> void:
	if not _initialized:
		_pending_leaderboard_scores.append({
			"leaderboard_id": leaderboard_id,
			"score": score,
			"keep_best": keep_best
		})
		return

	if not _is_steam_available():
		return

	var upload_type := 1 if keep_best else 2  ## ELeaderboardUploadScoreMethod
	# Actual call: Steam.uploadLeaderboardScore(score, keep_best, [], leaderboard_id)


## Download leaderboard entries.
func download_leaderboard_entries(leaderboard_id: int, start: int, end: int,
								   type: int = 0) -> void:  ## 0 = Global, 1 = Friends, 2 = Around User
	if not _initialized or not _is_steam_available():
		return

	# Actual call: Steam.downloadLeaderboardEntries(start, end, type, leaderboard_id)
	# Steam will emit leaderboard_scores_downloaded signal


## Process pending operations (when reconnected).
func _process_pending_operations() -> void:
	if not _initialized or not _is_steam_available():
		return

	# Process pending achievements
	for achievement_id in _pending_achievements:
		set_achievement(achievement_id)
	_pending_achievements.clear()

	# Process pending stats
	for stat_name in _pending_stats:
		var stat_data: Dictionary = _pending_stats[stat_name]
		if stat_data["type"] == "int":
			set_stat_int(stat_name, stat_data["value"])
		else:
			set_stat_float(stat_name, stat_data["value"])
	_pending_stats.clear()

	# Process pending leaderboard scores
	for score_data in _pending_leaderboard_scores:
		upload_score(score_data["leaderboard_id"], score_data["score"], score_data["keep_best"])
	_pending_leaderboard_scores.clear()

	if not _pending_achievements.is_empty() or not _pending_stats.is_empty():
		store_stats()


## Activate Steam overlay.
func activate_overlay(dialog: String = "") -> void:
	if not _initialized or not _is_steam_available():
		return

	# Actual call: Steam.activateGameOverlay(dialog)
	# dialog can be: "Friends", "Community", "Players", "Settings", "OfficialGameGroup", "Stats", "Achievements"


## Is Steam overlay enabled.
func is_overlay_enabled() -> bool:
	if not _initialized or not _is_steam_available():
		return false

	# Actual call: return Steam.isOverlayEnabled()
	return false


## Get Steam ID.
func get_steam_id() -> int:
	return _steam_id


## Get player name.
func get_player_name() -> String:
	return _persona_name


## Is initialized.
func is_initialized() -> bool:
	return _initialized


## Has pending operations.
func has_pending_operations() -> bool:
	return not _pending_achievements.is_empty() or \
		   not _pending_stats.is_empty() or \
		   not _pending_leaderboard_scores.is_empty()


## Get last error.
func get_last_error() -> String:
	return _last_error


## Get status.
func get_status() -> Dictionary:
	return {
		"initialized": _initialized,
		"steam_id": _steam_id,
		"persona_name": _persona_name,
		"stats_received": _stats_received,
		"pending_achievements": _pending_achievements.size(),
		"pending_stats": _pending_stats.size(),
		"pending_scores": _pending_leaderboard_scores.size(),
		"last_error": _last_error
	}


## Shutdown Steam.
func shutdown() -> void:
	if _initialized and _is_steam_available():
		store_stats()  ## Save any pending stats
		# Actual call: Steam.steamShutdown()
	_initialized = false
