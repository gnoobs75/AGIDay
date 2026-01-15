class_name LeaderboardSubmission
extends RefCounted
## LeaderboardSubmission handles async leaderboard submissions with retry logic.
## Provides rank retrieval, validation, and offline support.

signal submission_started(entry: LeaderboardEntry)
signal submission_completed(entry: LeaderboardEntry, success: bool, rank: int)
signal submission_failed(entry: LeaderboardEntry, error: String)
signal submission_progress(entry: LeaderboardEntry, status: String)
signal rank_retrieved(leaderboard_type: int, rank: int, total_players: int)
signal rank_retrieval_failed(leaderboard_type: int, error: String)
signal all_submissions_complete()

## Configuration
const SUBMISSION_TIMEOUT_MS := 5000      ## 5 second timeout
const MAX_RETRY_ATTEMPTS := 3
const INITIAL_RETRY_DELAY := 1.0         ## 1 second
const MAX_RETRY_DELAY := 30.0            ## 30 seconds max
const RATE_LIMIT_DELAY := 1.0            ## 1 second between submissions
const RANK_CACHE_DURATION := 300.0       ## 5 minutes cache

## Dependencies
var _leaderboard_manager: LeaderboardManager = null
var _playfab_manager: PlayFabManager = null

## Submission queue
var _pending_submissions: Array[SubmissionTask] = []
var _active_submission: SubmissionTask = null
var _is_processing := false

## Rank cache
var _rank_cache: Dictionary = {}  ## leaderboard_type -> {rank, total, timestamp}

## Statistics
var _total_submissions := 0
var _successful_submissions := 0
var _failed_submissions := 0

## Local storage
const QUEUE_PATH := "user://leaderboard_queue.json"


func _init() -> void:
	_load_pending_queue()


## Initialize with managers.
func initialize(leaderboard_manager: LeaderboardManager, playfab_manager: PlayFabManager = null) -> void:
	_leaderboard_manager = leaderboard_manager
	_playfab_manager = playfab_manager

	if _leaderboard_manager != null:
		_leaderboard_manager.score_uploaded.connect(_on_steam_upload_complete)
		_leaderboard_manager.scores_downloaded.connect(_on_scores_downloaded)

	# Process any pending submissions from previous session
	_start_processing()


## Submit entry to all applicable leaderboards.
func submit_victory(victory_data: Dictionary) -> void:
	# Create entries for each leaderboard type
	for lb_type in [
		LeaderboardEntry.LeaderboardType.FASTEST_DOMINATION,
		LeaderboardEntry.LeaderboardType.HIGHEST_KILLS,
		LeaderboardEntry.LeaderboardType.LONGEST_SURVIVAL
	]:
		var entry := LeaderboardEntry.from_victory_event(victory_data, lb_type)

		# Validate before queueing
		if entry.validate():
			_queue_submission(entry)
		else:
			push_warning("LeaderboardSubmission: Entry validation failed: %s" % str(entry.validation_errors))


## Submit a single entry.
func submit_entry(entry: LeaderboardEntry) -> void:
	if not entry.is_validated:
		if not entry.validate():
			submission_failed.emit(entry, "Validation failed: " + ", ".join(entry.validation_errors))
			return

	_queue_submission(entry)


## Queue submission for processing.
func _queue_submission(entry: LeaderboardEntry) -> void:
	# Check for duplicate submission
	for pending in _pending_submissions:
		if pending.entry.submission_id == entry.submission_id:
			return  ## Already queued

	var task := SubmissionTask.new()
	task.entry = entry
	task.retry_count = 0
	task.next_retry_time = 0.0
	task.status = SubmissionTask.Status.PENDING

	_pending_submissions.append(task)
	_save_pending_queue()

	_start_processing()


## Start processing submission queue.
func _start_processing() -> void:
	if _is_processing:
		return

	_is_processing = true
	_process_next_submission()


## Process next submission in queue.
func _process_next_submission() -> void:
	if _pending_submissions.is_empty():
		_is_processing = false
		all_submissions_complete.emit()
		return

	# Find next ready submission
	var current_time := Time.get_ticks_msec() / 1000.0
	var next_task: SubmissionTask = null

	for task in _pending_submissions:
		if task.status == SubmissionTask.Status.PENDING:
			if task.next_retry_time <= current_time:
				next_task = task
				break

	if next_task == null:
		# All tasks are waiting for retry, schedule next check
		_is_processing = false
		return

	_active_submission = next_task
	_submit_entry_async(_active_submission)


## Submit entry asynchronously.
func _submit_entry_async(task: SubmissionTask) -> void:
	task.status = SubmissionTask.Status.SUBMITTING
	task.start_time = Time.get_ticks_msec()

	submission_started.emit(task.entry)
	submission_progress.emit(task.entry, "Submitting to leaderboard...")

	_total_submissions += 1

	# Submit to Steam leaderboard
	if _leaderboard_manager != null:
		var lb_name := task.entry.get_type_string()
		_leaderboard_manager.upload_score(lb_name, task.entry.score, task.entry.to_dict())

	# Also submit to PlayFab if available
	if _playfab_manager != null and _playfab_manager.is_logged_in():
		_submit_to_playfab(task)
	else:
		# Steam-only, wait for callback
		_start_timeout_check(task)


## Submit to PlayFab.
func _submit_to_playfab(task: SubmissionTask) -> void:
	if _playfab_manager == null:
		return

	var lb_name := task.entry.get_type_string()
	var game_data := {
		"faction_id": task.entry.faction_id,
		"game_duration": task.entry.game_duration,
		"final_wave": task.entry.final_wave,
		"checksum": task.entry.validation_checksum
	}

	_playfab_manager.submit_score(lb_name, task.entry.score, game_data)


## Start timeout check for submission.
func _start_timeout_check(task: SubmissionTask) -> void:
	# This would normally be a timer - for now, mark as needing timeout check
	task.timeout_check_needed = true


## Handle Steam upload complete.
func _on_steam_upload_complete(leaderboard_name: String, success: bool) -> void:
	if _active_submission == null:
		return

	if _active_submission.entry.get_type_string() != leaderboard_name:
		return

	if success:
		_on_submission_success(_active_submission)
	else:
		_on_submission_error(_active_submission, "Steam upload failed")


## Handle submission success.
func _on_submission_success(task: SubmissionTask) -> void:
	task.status = SubmissionTask.Status.COMPLETED
	_successful_submissions += 1

	# Remove from pending
	_pending_submissions.erase(task)
	_save_pending_queue()

	submission_progress.emit(task.entry, "Submission successful!")
	submission_completed.emit(task.entry, true, -1)  ## Rank unknown until retrieved

	# Fetch rank for this leaderboard
	_fetch_rank(task.entry.leaderboard_type)

	# Process next
	_active_submission = null
	_schedule_next_submission()


## Handle submission error.
func _on_submission_error(task: SubmissionTask, error: String) -> void:
	task.retry_count += 1

	if task.retry_count >= MAX_RETRY_ATTEMPTS:
		# Max retries reached, mark as failed
		task.status = SubmissionTask.Status.FAILED
		_failed_submissions += 1

		_pending_submissions.erase(task)
		_save_pending_queue()

		submission_failed.emit(task.entry, "Max retries exceeded: " + error)
	else:
		# Schedule retry with exponential backoff
		var delay := minf(INITIAL_RETRY_DELAY * pow(2, task.retry_count - 1), MAX_RETRY_DELAY)
		task.next_retry_time = Time.get_ticks_msec() / 1000.0 + delay
		task.status = SubmissionTask.Status.PENDING

		submission_progress.emit(task.entry, "Retry scheduled in %.1fs..." % delay)

	_active_submission = null
	_schedule_next_submission()


## Schedule next submission with rate limiting.
func _schedule_next_submission() -> void:
	# Rate limit between submissions
	await Engine.get_main_loop().create_timer(RATE_LIMIT_DELAY).timeout
	_process_next_submission()


## Fetch rank for a leaderboard.
func _fetch_rank(leaderboard_type: LeaderboardEntry.LeaderboardType) -> void:
	# Check cache first
	var current_time := Time.get_ticks_msec() / 1000.0
	if _rank_cache.has(leaderboard_type):
		var cached: Dictionary = _rank_cache[leaderboard_type]
		if current_time - cached.get("timestamp", 0) < RANK_CACHE_DURATION:
			rank_retrieved.emit(leaderboard_type, cached["rank"], cached["total"])
			return

	# Request from leaderboard manager
	if _leaderboard_manager != null:
		var lb_name := _get_leaderboard_name(leaderboard_type)
		_leaderboard_manager.get_entries_around_user(lb_name, 1)


## Handle scores downloaded (for rank retrieval).
func _on_scores_downloaded(leaderboard_name: String, entries: Array) -> void:
	var leaderboard_type := _get_leaderboard_type(leaderboard_name)
	if leaderboard_type < 0:
		return

	# Find our rank in the results
	var player_rank := -1
	var total_players := 0

	for entry_dict in entries:
		var rank: int = entry_dict.get("rank", 0)
		if rank > total_players:
			total_players = rank

		# Check if this is the current player (would need Steam ID comparison)
		# For now, assume the center entry is ours (from get_entries_around_user)
		if entries.size() > 0:
			player_rank = entries[0].get("rank", -1)

	# Cache the result
	_rank_cache[leaderboard_type] = {
		"rank": player_rank,
		"total": total_players,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}

	rank_retrieved.emit(leaderboard_type, player_rank, total_players)


## Get rank from cache.
func get_cached_rank(leaderboard_type: LeaderboardEntry.LeaderboardType) -> Dictionary:
	if _rank_cache.has(leaderboard_type):
		return _rank_cache[leaderboard_type].duplicate()
	return {"rank": -1, "total": 0}


## Format rank for display.
static func format_rank(rank: int, total: int) -> String:
	if rank < 0:
		return "Unranked"
	if total > 0:
		return "Rank %d of %s" % [rank, _format_number(total)]
	return "Rank %d" % rank


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


## Get leaderboard name from type.
func _get_leaderboard_name(leaderboard_type: LeaderboardEntry.LeaderboardType) -> String:
	match leaderboard_type:
		LeaderboardEntry.LeaderboardType.FASTEST_DOMINATION:
			return "fastest_domination"
		LeaderboardEntry.LeaderboardType.HIGHEST_KILLS:
			return "highest_kills"
		LeaderboardEntry.LeaderboardType.LONGEST_SURVIVAL:
			return "longest_survival"
	return ""


## Get leaderboard type from name.
func _get_leaderboard_type(leaderboard_name: String) -> int:
	match leaderboard_name:
		"fastest_domination":
			return LeaderboardEntry.LeaderboardType.FASTEST_DOMINATION
		"highest_kills":
			return LeaderboardEntry.LeaderboardType.HIGHEST_KILLS
		"longest_survival":
			return LeaderboardEntry.LeaderboardType.LONGEST_SURVIVAL
	return -1


## Get all ranks for display.
func get_all_ranks() -> Array[Dictionary]:
	var ranks: Array[Dictionary] = []
	for lb_type in [
		LeaderboardEntry.LeaderboardType.FASTEST_DOMINATION,
		LeaderboardEntry.LeaderboardType.HIGHEST_KILLS,
		LeaderboardEntry.LeaderboardType.LONGEST_SURVIVAL
	]:
		var cached := get_cached_rank(lb_type)
		ranks.append({
			"type": lb_type,
			"name": _get_leaderboard_name(lb_type),
			"rank": cached.get("rank", -1),
			"total": cached.get("total", 0)
		})
	return ranks


## Check if any submissions are pending.
func has_pending_submissions() -> bool:
	return not _pending_submissions.is_empty()


## Get pending submission count.
func get_pending_count() -> int:
	return _pending_submissions.size()


## Cancel all pending submissions.
func cancel_all() -> void:
	_pending_submissions.clear()
	_active_submission = null
	_is_processing = false
	_save_pending_queue()


## Save pending queue to file.
func _save_pending_queue() -> void:
	var queue_data: Array = []
	for task in _pending_submissions:
		queue_data.append({
			"entry": task.entry.to_dict(),
			"retry_count": task.retry_count,
			"status": task.status
		})

	var file := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(queue_data))
		file.close()


## Load pending queue from file.
func _load_pending_queue() -> void:
	if not FileAccess.file_exists(QUEUE_PATH):
		return

	var file := FileAccess.open(QUEUE_PATH, FileAccess.READ)
	if file == null:
		return

	var json_string := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_string)
	if parsed is Array:
		for item in parsed:
			if item is Dictionary:
				var task := SubmissionTask.new()
				task.entry = LeaderboardEntry.from_dict(item.get("entry", {}))
				task.retry_count = item.get("retry_count", 0)
				task.status = SubmissionTask.Status.PENDING  ## Reset to pending on load
				task.next_retry_time = 0.0
				_pending_submissions.append(task)


## Force retry all failed submissions.
func retry_failed() -> void:
	# This would reset failed submissions - but we remove them on failure
	# Instead, this forces processing of pending ones
	for task in _pending_submissions:
		task.next_retry_time = 0.0
		task.status = SubmissionTask.Status.PENDING

	_start_processing()


## Update (call each frame for timeout checks).
func update(_delta: float) -> void:
	if _active_submission == null:
		return

	if not _active_submission.timeout_check_needed:
		return

	var elapsed := Time.get_ticks_msec() - _active_submission.start_time
	if elapsed > SUBMISSION_TIMEOUT_MS:
		_active_submission.timeout_check_needed = false
		_on_submission_error(_active_submission, "Submission timed out")


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"total_submissions": _total_submissions,
		"successful_submissions": _successful_submissions,
		"failed_submissions": _failed_submissions,
		"pending_submissions": _pending_submissions.size(),
		"is_processing": _is_processing
	}


## Cleanup.
func cleanup() -> void:
	_save_pending_queue()


## SubmissionTask helper class.
class SubmissionTask:
	enum Status {
		PENDING,
		SUBMITTING,
		COMPLETED,
		FAILED
	}

	var entry: LeaderboardEntry = null
	var retry_count: int = 0
	var next_retry_time: float = 0.0
	var status: Status = Status.PENDING
	var start_time: int = 0
	var timeout_check_needed := false
