class_name LeaderboardEntry
extends RefCounted
## LeaderboardEntry represents a complete leaderboard submission with validation.
## Contains player data, performance metrics, and validation checksums.

## Leaderboard types
enum LeaderboardType {
	FASTEST_DOMINATION,     ## Time in seconds (lower is better)
	HIGHEST_KILLS,          ## Kill count (higher is better)
	LONGEST_SURVIVAL        ## Wave number reached (higher is better)
}

## Entry data
var player_name: String = ""
var player_id: String = ""
var faction_id: int = 0
var leaderboard_type: LeaderboardType = LeaderboardType.HIGHEST_KILLS
var score: int = 0
var timestamp: int = 0
var game_duration: int = 0           ## Seconds
var final_wave: int = 0
var performance_metrics: Dictionary = {}

## Validation data
var validation_checksum: String = ""
var session_token: String = ""
var submission_id: String = ""

## State
var is_validated := false
var validation_errors: Array[String] = []


func _init() -> void:
	timestamp = int(Time.get_unix_time_from_system())
	submission_id = _generate_submission_id()


## Create from victory event data.
static func from_victory_event(victory_data: Dictionary, lb_type: LeaderboardType) -> LeaderboardEntry:
	var entry := LeaderboardEntry.new()

	entry.player_name = _sanitize_text(victory_data.get("player_name", "Unknown"))
	entry.player_id = victory_data.get("player_id", "")
	entry.faction_id = victory_data.get("faction_id", 0)
	entry.leaderboard_type = lb_type
	entry.game_duration = victory_data.get("game_duration", 0)
	entry.final_wave = victory_data.get("final_wave", 0)

	# Calculate score based on leaderboard type
	entry.score = entry._calculate_score(victory_data)

	# Copy performance metrics
	entry.performance_metrics = {
		"total_kills": victory_data.get("total_kills", 0),
		"units_produced": victory_data.get("units_produced", 0),
		"resources_collected": victory_data.get("resources_collected", 0),
		"districts_captured": victory_data.get("districts_captured", 0),
		"factories_destroyed": victory_data.get("factories_destroyed", 0),
		"damage_dealt": victory_data.get("damage_dealt", 0),
		"damage_taken": victory_data.get("damage_taken", 0),
		"difficulty": victory_data.get("difficulty", 1.0)
	}

	# Generate validation checksum
	entry.validation_checksum = entry._generate_checksum()
	entry.session_token = victory_data.get("session_token", "")

	return entry


## Calculate score based on leaderboard type.
func _calculate_score(victory_data: Dictionary) -> int:
	match leaderboard_type:
		LeaderboardType.FASTEST_DOMINATION:
			# Score is time in seconds (lower is better)
			return victory_data.get("game_duration", 0)
		LeaderboardType.HIGHEST_KILLS:
			# Score is total kill count
			return victory_data.get("total_kills", 0)
		LeaderboardType.LONGEST_SURVIVAL:
			# Score is wave number reached
			return victory_data.get("final_wave", 0)
	return 0


## Validate entry data before submission.
func validate() -> bool:
	validation_errors.clear()

	# Basic data validation
	if player_name.is_empty():
		validation_errors.append("Player name is empty")
	if player_name.length() > 32:
		validation_errors.append("Player name too long")

	if score < 0:
		validation_errors.append("Score cannot be negative")

	if game_duration < 0:
		validation_errors.append("Game duration cannot be negative")

	if final_wave < 0:
		validation_errors.append("Wave number cannot be negative")

	# Type-specific validation
	match leaderboard_type:
		LeaderboardType.FASTEST_DOMINATION:
			if not _validate_domination_time():
				validation_errors.append("Domination time validation failed")
		LeaderboardType.HIGHEST_KILLS:
			if not _validate_kill_count():
				validation_errors.append("Kill count validation failed")
		LeaderboardType.LONGEST_SURVIVAL:
			if not _validate_wave_number():
				validation_errors.append("Wave number validation failed")

	# Checksum verification
	if validation_checksum != _generate_checksum():
		validation_errors.append("Checksum mismatch")

	is_validated = validation_errors.is_empty()
	return is_validated


## Validate domination time is reasonable.
func _validate_domination_time() -> bool:
	# Minimum time: 60 seconds (1 minute) - impossible to win faster
	# Maximum time: 86400 seconds (24 hours) - reasonable upper limit
	if score < 60:
		return false
	if score > 86400:
		return false

	# Duration should roughly match score for domination
	if abs(game_duration - score) > 60:  ## Allow 1 minute variance
		return false

	# Difficulty scaling - faster times require higher difficulty
	var difficulty: float = performance_metrics.get("difficulty", 1.0)
	var min_expected_time := int(300 * difficulty)  ## 5 minutes base scaled by difficulty
	if score < min_expected_time * 0.5:  ## Allow 50% faster than expected
		return false

	return true


## Validate kill count is reasonable.
func _validate_kill_count() -> bool:
	# Maximum kills per second: 50 (extremely generous)
	var max_kills := game_duration * 50
	if score > max_kills:
		return false

	# Minimum kills for a victory: at least some
	if score < 1:
		return false

	# Kills should match metrics
	var reported_kills: int = performance_metrics.get("total_kills", 0)
	if score != reported_kills:
		return false

	# Wave number should correlate with kill count
	# More waves = more enemies spawned = more potential kills
	var kills_per_wave := score / maxf(final_wave, 1)
	if kills_per_wave > 1000:  ## More than 1000 kills per wave is suspicious
		return false

	return true


## Validate wave number is reasonable.
func _validate_wave_number() -> bool:
	# Minimum wave time: 30 seconds per wave
	var min_duration := final_wave * 30
	if game_duration < min_duration:
		return false

	# Maximum wave: 1000 (reasonable upper limit)
	if score > 1000:
		return false

	# Score should match final_wave
	if score != final_wave:
		return false

	return true


## Generate validation checksum.
func _generate_checksum() -> String:
	var data := "%s|%d|%d|%d|%d|%d" % [
		player_id,
		faction_id,
		score,
		game_duration,
		final_wave,
		timestamp
	]

	# Add performance metrics hash
	var metrics_str := ""
	var sorted_keys := performance_metrics.keys()
	sorted_keys.sort()
	for key in sorted_keys:
		metrics_str += "%s:%s|" % [key, str(performance_metrics[key])]
	data += metrics_str

	# CRC32 checksum
	var crc := _crc32(data)
	return "%08x" % crc


## Generate unique submission ID.
func _generate_submission_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var id := ""
	for i in 16:
		id += "%x" % rng.randi_range(0, 15)
	return id


## Simple CRC32 implementation.
func _crc32(data: String) -> int:
	var crc := 0xFFFFFFFF
	var table: Array[int] = _get_crc_table()

	for c in data.to_utf8_buffer():
		crc = (crc >> 8) ^ table[(crc ^ c) & 0xFF]

	return crc ^ 0xFFFFFFFF


## Get CRC32 lookup table.
static func _get_crc_table() -> Array[int]:
	var table: Array[int] = []
	for i in 256:
		var crc := i
		for _j in 8:
			if crc & 1:
				crc = (crc >> 1) ^ 0xEDB88320
			else:
				crc = crc >> 1
		table.append(crc)
	return table


## Sanitize text input.
static func _sanitize_text(text: String) -> String:
	# Remove control characters
	var sanitized := ""
	for c in text:
		var code := c.unicode_at(0)
		if code >= 32 and code < 127:  ## Printable ASCII
			sanitized += c
		elif code >= 0x00A0:  ## Extended characters (excluding control)
			sanitized += c

	# Trim and limit length
	sanitized = sanitized.strip_edges()
	if sanitized.length() > 32:
		sanitized = sanitized.substr(0, 32)

	return sanitized


## Get leaderboard type as string.
func get_type_string() -> String:
	match leaderboard_type:
		LeaderboardType.FASTEST_DOMINATION:
			return "fastest_domination"
		LeaderboardType.HIGHEST_KILLS:
			return "highest_kills"
		LeaderboardType.LONGEST_SURVIVAL:
			return "longest_survival"
	return "unknown"


## Get leaderboard display name.
func get_type_display_name() -> String:
	match leaderboard_type:
		LeaderboardType.FASTEST_DOMINATION:
			return "Fastest Domination"
		LeaderboardType.HIGHEST_KILLS:
			return "Most Kills"
		LeaderboardType.LONGEST_SURVIVAL:
			return "Longest Survival"
	return "Unknown"


## Format score for display.
func format_score_display() -> String:
	match leaderboard_type:
		LeaderboardType.FASTEST_DOMINATION:
			# Time format (MM:SS)
			var minutes := score / 60
			var seconds := score % 60
			return "%02d:%02d" % [minutes, seconds]
		LeaderboardType.HIGHEST_KILLS:
			return _format_number(score)
		LeaderboardType.LONGEST_SURVIVAL:
			return "Wave %d" % score
	return str(score)


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


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"player_id": player_id,
		"faction_id": faction_id,
		"leaderboard_type": leaderboard_type,
		"score": score,
		"timestamp": timestamp,
		"game_duration": game_duration,
		"final_wave": final_wave,
		"performance_metrics": performance_metrics,
		"validation_checksum": validation_checksum,
		"session_token": session_token,
		"submission_id": submission_id,
		"is_validated": is_validated
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> LeaderboardEntry:
	var entry := LeaderboardEntry.new()
	entry.player_name = data.get("player_name", "")
	entry.player_id = data.get("player_id", "")
	entry.faction_id = data.get("faction_id", 0)
	entry.leaderboard_type = data.get("leaderboard_type", LeaderboardType.HIGHEST_KILLS)
	entry.score = data.get("score", 0)
	entry.timestamp = data.get("timestamp", 0)
	entry.game_duration = data.get("game_duration", 0)
	entry.final_wave = data.get("final_wave", 0)
	entry.performance_metrics = data.get("performance_metrics", {})
	entry.validation_checksum = data.get("validation_checksum", "")
	entry.session_token = data.get("session_token", "")
	entry.submission_id = data.get("submission_id", "")
	entry.is_validated = data.get("is_validated", false)
	return entry
