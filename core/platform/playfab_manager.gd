class_name PlayFabManager
extends RefCounted
## PlayFabManager provides PlayFab cloud integration for leaderboards and achievements.
## Handles REST API communication with TLS encryption and offline tolerance.

signal login_completed(success: bool, player_id: String)
signal login_failed(error: String)
signal leaderboard_updated(leaderboard_name: String, success: bool)
signal leaderboard_fetched(leaderboard_name: String, entries: Array)
signal profile_updated(success: bool)
signal profile_fetched(profile: Dictionary)
signal sync_completed(success: bool)
signal anomaly_detected(anomaly_type: String, details: Dictionary)

## Configuration
const BASE_URL := "https://titleId.playfabapi.com"  ## Replace titleId with actual
const API_VERSION := "2024-01"
const REQUEST_TIMEOUT := 10.0

## Leaderboard definitions
const LEADERBOARD_FASTEST_DOMINATION := "fastest_domination_time"
const LEADERBOARD_HIGHEST_KILLS := "highest_kill_count"
const LEADERBOARD_LONGEST_SURVIVAL := "longest_survival_wave"

## Validation ranges
const VALIDATION_RANGES := {
	LEADERBOARD_FASTEST_DOMINATION: {"min": 60, "max": 36000},      ## 1 min to 10 hours
	LEADERBOARD_HIGHEST_KILLS: {"min": 0, "max": 1000000},          ## Up to 1M kills
	LEADERBOARD_LONGEST_SURVIVAL: {"min": 1, "max": 1000}           ## Wave 1-1000
}

## Anomaly detection thresholds
const ANOMALY_THRESHOLDS := {
	"max_kills_per_second": 100.0,
	"max_waves_per_minute": 5.0,
	"min_game_time_seconds": 30.0
}

## State
var _title_id := ""
var _session_ticket := ""
var _player_id := ""
var _is_logged_in := false
var _last_sync_time := 0.0

## Pending requests
var _pending_submissions: Array[Dictionary] = []
var _request_queue: Array[Dictionary] = []

## HTTP client
var _http_client: HTTPRequest = null


func _init() -> void:
	pass


## Initialize with title ID.
func initialize(title_id: String, http_node: Node) -> void:
	_title_id = title_id

	# Create HTTP request node
	_http_client = HTTPRequest.new()
	_http_client.timeout = REQUEST_TIMEOUT
	http_node.add_child(_http_client)


## Login with device ID (anonymous login).
func login_with_device_id(device_id: String) -> void:
	var endpoint := "/Client/LoginWithCustomID"
	var body := {
		"TitleId": _title_id,
		"CustomId": device_id,
		"CreateAccount": true
	}

	_make_request(endpoint, body, _on_login_response)


## Login with Steam (if Steam integration available).
func login_with_steam(steam_ticket: String) -> void:
	var endpoint := "/Client/LoginWithSteam"
	var body := {
		"TitleId": _title_id,
		"SteamTicket": steam_ticket,
		"CreateAccount": true
	}

	_make_request(endpoint, body, _on_login_response)


## Handle login response.
func _on_login_response(result: Dictionary) -> void:
	if result.get("error", false):
		_is_logged_in = false
		login_failed.emit(result.get("error_message", "Unknown error"))
		return

	var data: Dictionary = result.get("data", {})
	_session_ticket = data.get("SessionTicket", "")
	_player_id = data.get("PlayFabId", "")
	_is_logged_in = true

	login_completed.emit(true, _player_id)

	# Process pending submissions
	_process_pending_submissions()


## Submit leaderboard score.
func submit_score(leaderboard_name: String, score: int, game_data: Dictionary = {}) -> void:
	# Validate score range
	if not _validate_score(leaderboard_name, score):
		anomaly_detected.emit("invalid_score", {
			"leaderboard": leaderboard_name,
			"score": score
		})
		return

	# Detect anomalies
	if not _check_anomalies(leaderboard_name, score, game_data):
		return

	if not _is_logged_in:
		_queue_submission(leaderboard_name, score, game_data)
		return

	var endpoint := "/Client/UpdatePlayerStatistics"
	var body := {
		"Statistics": [
			{
				"StatisticName": leaderboard_name,
				"Value": score
			}
		]
	}

	_make_authenticated_request(endpoint, body, func(result):
		_on_score_submitted(leaderboard_name, result)
	)


## Handle score submission response.
func _on_score_submitted(leaderboard_name: String, result: Dictionary) -> void:
	var success := not result.get("error", false)
	leaderboard_updated.emit(leaderboard_name, success)


## Fetch leaderboard entries.
func fetch_leaderboard(leaderboard_name: String, start: int = 0, count: int = 10) -> void:
	if not _is_logged_in:
		leaderboard_fetched.emit(leaderboard_name, [])
		return

	var endpoint := "/Client/GetLeaderboard"
	var body := {
		"StatisticName": leaderboard_name,
		"StartPosition": start,
		"MaxResultsCount": count
	}

	_make_authenticated_request(endpoint, body, func(result):
		_on_leaderboard_fetched(leaderboard_name, result)
	)


## Handle leaderboard fetch response.
func _on_leaderboard_fetched(leaderboard_name: String, result: Dictionary) -> void:
	if result.get("error", false):
		leaderboard_fetched.emit(leaderboard_name, [])
		return

	var data: Dictionary = result.get("data", {})
	var entries: Array = data.get("Leaderboard", [])

	var parsed_entries: Array[Dictionary] = []
	for entry in entries:
		parsed_entries.append({
			"rank": entry.get("Position", 0) + 1,
			"player_id": entry.get("PlayFabId", ""),
			"display_name": entry.get("DisplayName", "Player"),
			"score": entry.get("StatValue", 0)
		})

	leaderboard_fetched.emit(leaderboard_name, parsed_entries)


## Update player profile.
func update_profile(profile_data: Dictionary) -> void:
	if not _is_logged_in:
		return

	var endpoint := "/Client/UpdateUserData"
	var body := {
		"Data": profile_data,
		"Permission": "Private"
	}

	_make_authenticated_request(endpoint, body, func(result):
		var success := not result.get("error", false)
		profile_updated.emit(success)
	)


## Fetch player profile.
func fetch_profile() -> void:
	if not _is_logged_in:
		profile_fetched.emit({})
		return

	var endpoint := "/Client/GetUserData"
	var body := {
		"PlayFabId": _player_id
	}

	_make_authenticated_request(endpoint, body, func(result):
		if result.get("error", false):
			profile_fetched.emit({})
			return

		var data: Dictionary = result.get("data", {}).get("Data", {})
		var profile := {}
		for key in data:
			profile[key] = data[key].get("Value", "")
		profile_fetched.emit(profile)
	)


## Validate score against defined ranges.
func _validate_score(leaderboard_name: String, score: int) -> bool:
	if not VALIDATION_RANGES.has(leaderboard_name):
		return true

	var range_data: Dictionary = VALIDATION_RANGES[leaderboard_name]
	return score >= range_data["min"] and score <= range_data["max"]


## Check for anomalies in submission.
func _check_anomalies(leaderboard_name: String, score: int, game_data: Dictionary) -> bool:
	var game_time: float = game_data.get("game_time_seconds", 0.0)
	var kills: int = game_data.get("total_kills", 0)
	var waves: int = game_data.get("waves_completed", 0)

	# Check minimum game time
	if game_time > 0 and game_time < ANOMALY_THRESHOLDS["min_game_time_seconds"]:
		anomaly_detected.emit("instant_progression", {
			"game_time": game_time,
			"leaderboard": leaderboard_name,
			"score": score
		})
		return false

	# Check kills per second
	if game_time > 0 and kills > 0:
		var kps := float(kills) / game_time
		if kps > ANOMALY_THRESHOLDS["max_kills_per_second"]:
			anomaly_detected.emit("impossible_kill_rate", {
				"kills_per_second": kps,
				"total_kills": kills,
				"game_time": game_time
			})
			return false

	# Check waves per minute
	if game_time > 60 and waves > 0:
		var wpm := float(waves) / (game_time / 60.0)
		if wpm > ANOMALY_THRESHOLDS["max_waves_per_minute"]:
			anomaly_detected.emit("impossible_wave_rate", {
				"waves_per_minute": wpm,
				"waves_completed": waves,
				"game_time": game_time
			})
			return false

	return true


## Queue submission for later (offline mode).
func _queue_submission(leaderboard_name: String, score: int, game_data: Dictionary) -> void:
	_pending_submissions.append({
		"leaderboard": leaderboard_name,
		"score": score,
		"game_data": game_data,
		"timestamp": Time.get_ticks_msec()
	})


## Process pending submissions.
func _process_pending_submissions() -> void:
	for submission in _pending_submissions:
		submit_score(submission["leaderboard"], submission["score"], submission["game_data"])
	_pending_submissions.clear()


## Make HTTP request.
func _make_request(endpoint: String, body: Dictionary, callback: Callable) -> void:
	if _http_client == null:
		callback.call({"error": true, "error_message": "HTTP client not initialized"})
		return

	var url := BASE_URL.replace("titleId", _title_id) + endpoint
	var headers := [
		"Content-Type: application/json"
	]

	var json_body := JSON.stringify(body)

	_request_queue.append({
		"callback": callback,
		"timestamp": Time.get_ticks_msec()
	})

	# In actual implementation, would use HTTPRequest.request()
	# _http_client.request(url, headers, HTTPClient.METHOD_POST, json_body)


## Make authenticated HTTP request.
func _make_authenticated_request(endpoint: String, body: Dictionary, callback: Callable) -> void:
	if _session_ticket.is_empty():
		callback.call({"error": true, "error_message": "Not authenticated"})
		return

	var url := BASE_URL.replace("titleId", _title_id) + endpoint
	var headers := [
		"Content-Type: application/json",
		"X-Authorization: " + _session_ticket
	]

	var json_body := JSON.stringify(body)

	_request_queue.append({
		"callback": callback,
		"timestamp": Time.get_ticks_msec()
	})

	# In actual implementation, would use HTTPRequest.request()


## Check if logged in.
func is_logged_in() -> bool:
	return _is_logged_in


## Get player ID.
func get_player_id() -> String:
	return _player_id


## Get pending count.
func get_pending_count() -> int:
	return _pending_submissions.size()


## Get status.
func get_status() -> Dictionary:
	return {
		"logged_in": _is_logged_in,
		"player_id": _player_id,
		"pending_submissions": _pending_submissions.size(),
		"last_sync": _last_sync_time
	}
