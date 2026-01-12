class_name LeaderboardManager
extends RefCounted
## LeaderboardManager handles Steam leaderboard submission and retrieval.
## Supports multiple leaderboard types and offline score caching.

signal leaderboard_found(leaderboard_name: String, leaderboard_id: int)
signal leaderboard_not_found(leaderboard_name: String)
signal score_uploaded(leaderboard_name: String, success: bool)
signal scores_downloaded(leaderboard_name: String, entries: Array)
signal upload_error(leaderboard_name: String, error: String)

## Steam reference
var _steam_manager: SteamManager = null

## Leaderboard data
var _leaderboards: Dictionary = {}      ## leaderboard_name -> leaderboard_id
var _pending_uploads: Array[Dictionary] = []
var _cached_entries: Dictionary = {}    ## leaderboard_name -> Array of entries

## Leaderboard names
const LEADERBOARD_FASTEST_DOMINATION := "fastest_domination"
const LEADERBOARD_HIGHEST_SCORE := "highest_score"
const LEADERBOARD_MOST_KILLS := "most_kills"
const LEADERBOARD_LONGEST_SURVIVAL := "longest_survival"
const LEADERBOARD_HIGHEST_WAVE := "highest_wave"

## Download types
enum DownloadType {
	GLOBAL,
	FRIENDS,
	AROUND_USER
}

## Local storage
const SAVE_PATH := "user://leaderboard_cache.json"


func _init() -> void:
	pass


## Initialize with Steam manager.
func initialize(steam_manager: SteamManager) -> void:
	_steam_manager = steam_manager

	# Load cached data
	_load_cache()

	# Find all leaderboards
	if _steam_manager != null and _steam_manager.is_initialized():
		_find_all_leaderboards()


## Find all game leaderboards.
func _find_all_leaderboards() -> void:
	find_leaderboard(LEADERBOARD_FASTEST_DOMINATION)
	find_leaderboard(LEADERBOARD_HIGHEST_SCORE)
	find_leaderboard(LEADERBOARD_MOST_KILLS)
	find_leaderboard(LEADERBOARD_LONGEST_SURVIVAL)
	find_leaderboard(LEADERBOARD_HIGHEST_WAVE)


## Find or create a leaderboard.
func find_leaderboard(leaderboard_name: String) -> void:
	if _steam_manager == null or not _steam_manager.is_initialized():
		return

	_steam_manager.find_leaderboard(leaderboard_name)
	# Result will come via callback


## Handle leaderboard found callback.
func on_leaderboard_found(leaderboard_name: String, leaderboard_id: int, found: bool) -> void:
	if found:
		_leaderboards[leaderboard_name] = leaderboard_id
		leaderboard_found.emit(leaderboard_name, leaderboard_id)

		# Process any pending uploads for this leaderboard
		_process_pending_uploads(leaderboard_name)
	else:
		leaderboard_not_found.emit(leaderboard_name)


## Upload score to leaderboard.
func upload_score(leaderboard_name: String, score: int, extra_data: Dictionary = {}) -> void:
	if _steam_manager == null or not _steam_manager.is_initialized():
		_queue_pending_upload(leaderboard_name, score, extra_data)
		return

	if not _leaderboards.has(leaderboard_name):
		_queue_pending_upload(leaderboard_name, score, extra_data)
		find_leaderboard(leaderboard_name)
		return

	var leaderboard_id: int = _leaderboards[leaderboard_name]
	_steam_manager.upload_score(leaderboard_id, score, true)


## Submit fastest domination time.
func submit_domination_time(time_seconds: int) -> void:
	# Lower is better for time-based leaderboards
	upload_score(LEADERBOARD_FASTEST_DOMINATION, time_seconds)


## Submit high score.
func submit_high_score(score: int) -> void:
	upload_score(LEADERBOARD_HIGHEST_SCORE, score)


## Submit kill count.
func submit_kill_count(kills: int) -> void:
	upload_score(LEADERBOARD_MOST_KILLS, kills)


## Submit survival time.
func submit_survival_time(time_seconds: int) -> void:
	upload_score(LEADERBOARD_LONGEST_SURVIVAL, time_seconds)


## Submit wave reached.
func submit_wave_reached(wave: int) -> void:
	upload_score(LEADERBOARD_HIGHEST_WAVE, wave)


## Download leaderboard entries.
func download_entries(leaderboard_name: String, start: int = 1, end: int = 10,
					   type: DownloadType = DownloadType.GLOBAL) -> void:
	if _steam_manager == null or not _steam_manager.is_initialized():
		# Return cached data if available
		if _cached_entries.has(leaderboard_name):
			scores_downloaded.emit(leaderboard_name, _cached_entries[leaderboard_name])
		return

	if not _leaderboards.has(leaderboard_name):
		find_leaderboard(leaderboard_name)
		return

	var leaderboard_id: int = _leaderboards[leaderboard_name]
	_steam_manager.download_leaderboard_entries(leaderboard_id, start, end, type)


## Get top entries for a leaderboard.
func get_top_entries(leaderboard_name: String, count: int = 10) -> void:
	download_entries(leaderboard_name, 1, count, DownloadType.GLOBAL)


## Get entries around current user.
func get_entries_around_user(leaderboard_name: String, range_size: int = 5) -> void:
	download_entries(leaderboard_name, -range_size, range_size, DownloadType.AROUND_USER)


## Get friend entries.
func get_friend_entries(leaderboard_name: String) -> void:
	download_entries(leaderboard_name, 1, 100, DownloadType.FRIENDS)


## Handle scores downloaded callback.
func on_scores_downloaded(leaderboard_name: String, entries: Array) -> void:
	# Parse entries into a cleaner format
	var parsed_entries: Array[Dictionary] = []

	for entry in entries:
		parsed_entries.append({
			"rank": entry.get("global_rank", 0),
			"steam_id": entry.get("steam_id", 0),
			"score": entry.get("score", 0),
			"details": entry.get("details", []),
			"ugc_handle": entry.get("ugc_handle", 0)
		})

	# Cache the results
	_cached_entries[leaderboard_name] = parsed_entries
	_save_cache()

	scores_downloaded.emit(leaderboard_name, parsed_entries)


## Handle score upload result.
func on_score_uploaded(leaderboard_name: String, success: bool,
					   score: int, changed: bool, rank: int) -> void:
	if success:
		score_uploaded.emit(leaderboard_name, true)
	else:
		upload_error.emit(leaderboard_name, "Upload failed")


## Queue pending upload for later.
func _queue_pending_upload(leaderboard_name: String, score: int, extra_data: Dictionary) -> void:
	_pending_uploads.append({
		"leaderboard_name": leaderboard_name,
		"score": score,
		"extra_data": extra_data,
		"timestamp": Time.get_ticks_msec()
	})
	_save_cache()


## Process pending uploads for a leaderboard.
func _process_pending_uploads(leaderboard_name: String) -> void:
	var remaining: Array[Dictionary] = []

	for upload in _pending_uploads:
		if upload["leaderboard_name"] == leaderboard_name:
			upload_score(leaderboard_name, upload["score"], upload["extra_data"])
		else:
			remaining.append(upload)

	_pending_uploads = remaining


## Get cached entries.
func get_cached_entries(leaderboard_name: String) -> Array:
	return _cached_entries.get(leaderboard_name, [])


## Check if leaderboard is available.
func is_leaderboard_available(leaderboard_name: String) -> bool:
	return _leaderboards.has(leaderboard_name)


## Get all available leaderboards.
func get_available_leaderboards() -> Array[String]:
	var result: Array[String] = []
	for name in _leaderboards:
		result.append(name)
	return result


## Get pending upload count.
func get_pending_count() -> int:
	return _pending_uploads.size()


## Save cache to file.
func _save_cache() -> void:
	var cache_data := {
		"cached_entries": _cached_entries,
		"pending_uploads": _pending_uploads
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(cache_data))
		file.close()


## Load cache from file.
func _load_cache() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var json_string := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_string)
	if parsed is Dictionary:
		_cached_entries = parsed.get("cached_entries", {})
		_pending_uploads.assign(parsed.get("pending_uploads", []))


## Clear cache.
func clear_cache() -> void:
	_cached_entries.clear()
	_save_cache()


## Format score for display (handles time-based vs point-based).
static func format_score(leaderboard_name: String, score: int) -> String:
	match leaderboard_name:
		LEADERBOARD_FASTEST_DOMINATION, LEADERBOARD_LONGEST_SURVIVAL:
			# Time format (MM:SS)
			var minutes := score / 60
			var seconds := score % 60
			return "%02d:%02d" % [minutes, seconds]
		_:
			# Point format with commas
			return _format_number(score)


## Format number with commas.
static func _format_number(number: int) -> String:
	var str_num := str(number)
	var result := ""
	var count := 0

	for i in range(str_num.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_num[i] + result
		count += 1

	return result


## Get leaderboard display name.
static func get_display_name(leaderboard_name: String) -> String:
	match leaderboard_name:
		LEADERBOARD_FASTEST_DOMINATION:
			return "Fastest Domination"
		LEADERBOARD_HIGHEST_SCORE:
			return "High Scores"
		LEADERBOARD_MOST_KILLS:
			return "Most Kills"
		LEADERBOARD_LONGEST_SURVIVAL:
			return "Longest Survival"
		LEADERBOARD_HIGHEST_WAVE:
			return "Highest Wave"
		_:
			return leaderboard_name.capitalize()


## Get status.
func get_status() -> Dictionary:
	return {
		"leaderboards_found": _leaderboards.size(),
		"pending_uploads": _pending_uploads.size(),
		"cached_entries": _cached_entries.size()
	}
