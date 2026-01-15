class_name DifficultyScaler
extends RefCounted
## DifficultyScaler handles time-based difficulty escalation.
## Increases enemy production rates over match duration.

signal difficulty_scaled(new_multiplier: float)
signal escalation_milestone(minutes: int, multiplier: float)

## Configuration
const DEFAULT_ESCALATION_RATE := 0.01  ## 1% per minute
const DEFAULT_BASE_MULTIPLIER := 1.0

## Escalation settings
var escalation_rate: float = DEFAULT_ESCALATION_RATE
var base_multiplier: float = DEFAULT_BASE_MULTIPLIER

## Match tracking
var _match_duration: float = 0.0       ## Seconds
var _is_paused: bool = false
var _last_milestone_minute: int = 0

## Current production multiplier
var _production_multiplier: float = DEFAULT_BASE_MULTIPLIER

## Faction tracking
var _player_faction_id: int = -1       ## Player faction (not scaled)
var _enemy_faction_ids: Array[int] = []


func _init() -> void:
	pass


## Configure scaling parameters.
func configure(rate: float = DEFAULT_ESCALATION_RATE,
			   base: float = DEFAULT_BASE_MULTIPLIER) -> void:
	escalation_rate = rate
	base_multiplier = base
	_production_multiplier = base


## Set player faction (exempt from scaling).
func set_player_faction(faction_id: int) -> void:
	_player_faction_id = faction_id


## Set enemy factions (affected by scaling).
func set_enemy_factions(faction_ids: Array[int]) -> void:
	_enemy_faction_ids = faction_ids.duplicate()


## Add enemy faction.
func add_enemy_faction(faction_id: int) -> void:
	if faction_id not in _enemy_faction_ids:
		_enemy_faction_ids.append(faction_id)


## Update scaling (call each frame).
func update(delta: float) -> void:
	if _is_paused:
		return

	_match_duration += delta

	# Calculate new multiplier
	var minutes := _match_duration / 60.0
	var new_multiplier := base_multiplier + (escalation_rate * minutes)

	if new_multiplier != _production_multiplier:
		_production_multiplier = new_multiplier
		difficulty_scaled.emit(_production_multiplier)

		# Check for milestone
		var current_minute := int(minutes)
		if current_minute > _last_milestone_minute:
			_last_milestone_minute = current_minute
			escalation_milestone.emit(current_minute, _production_multiplier)


## Get current production multiplier.
func get_production_multiplier() -> float:
	return _production_multiplier


## Get production multiplier for specific faction.
func get_faction_multiplier(faction_id: int) -> float:
	# Player faction is not affected by scaling
	if faction_id == _player_faction_id:
		return base_multiplier

	# Enemy factions get scaled multiplier
	if faction_id in _enemy_faction_ids:
		return _production_multiplier

	# Unknown faction - default to base
	return base_multiplier


## Check if faction is affected by scaling.
func is_faction_scaled(faction_id: int) -> bool:
	return faction_id in _enemy_faction_ids


## Get match duration in seconds.
func get_match_duration() -> float:
	return _match_duration


## Get match duration in minutes.
func get_match_minutes() -> float:
	return _match_duration / 60.0


## Pause scaling.
func pause() -> void:
	_is_paused = true


## Resume scaling.
func resume() -> void:
	_is_paused = false


## Check if paused.
func is_paused() -> bool:
	return _is_paused


## Reset scaling.
func reset() -> void:
	_match_duration = 0.0
	_production_multiplier = base_multiplier
	_last_milestone_minute = 0
	_is_paused = false


## Set match duration directly (for loading saves).
func set_match_duration(duration: float) -> void:
	_match_duration = duration
	_recalculate_multiplier()


## Recalculate multiplier from duration.
func _recalculate_multiplier() -> void:
	var minutes := _match_duration / 60.0
	_production_multiplier = base_multiplier + (escalation_rate * minutes)
	_last_milestone_minute = int(minutes)


## Get production time with scaling applied.
func get_scaled_production_time(base_time: float, faction_id: int) -> float:
	var multiplier := get_faction_multiplier(faction_id)
	if multiplier <= 0:
		return base_time

	# Higher multiplier = faster production = lower time
	return base_time / multiplier


## Get production rate with scaling applied.
func get_scaled_production_rate(base_rate: float, faction_id: int) -> float:
	var multiplier := get_faction_multiplier(faction_id)
	return base_rate * multiplier


## Calculate effective difficulty level (0-100 scale).
func get_difficulty_level() -> int:
	# Convert multiplier to difficulty level
	# 1.0 = 0, 2.0 = 100 (roughly 100 minutes of gameplay)
	var level := int((_production_multiplier - base_multiplier) * 100.0)
	return clampi(level, 0, 100)


## Get difficulty description.
func get_difficulty_description() -> String:
	var level := get_difficulty_level()
	if level < 10:
		return "Normal"
	elif level < 25:
		return "Escalating"
	elif level < 50:
		return "Challenging"
	elif level < 75:
		return "Intense"
	else:
		return "Extreme"


## Get time until next milestone.
func get_time_until_milestone() -> float:
	var current_minutes := _match_duration / 60.0
	var next_minute := float(_last_milestone_minute + 1)
	return maxf(0.0, (next_minute * 60.0) - _match_duration)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"match_duration_seconds": _match_duration,
		"match_duration_minutes": get_match_minutes(),
		"production_multiplier": _production_multiplier,
		"escalation_rate": escalation_rate,
		"base_multiplier": base_multiplier,
		"difficulty_level": get_difficulty_level(),
		"difficulty_description": get_difficulty_description(),
		"player_faction": _player_faction_id,
		"enemy_factions": _enemy_faction_ids.duplicate(),
		"is_paused": _is_paused
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"match_duration": _match_duration,
		"escalation_rate": escalation_rate,
		"base_multiplier": base_multiplier,
		"production_multiplier": _production_multiplier,
		"player_faction_id": _player_faction_id,
		"enemy_faction_ids": _enemy_faction_ids.duplicate(),
		"is_paused": _is_paused,
		"last_milestone_minute": _last_milestone_minute
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_match_duration = data.get("match_duration", 0.0)
	escalation_rate = data.get("escalation_rate", DEFAULT_ESCALATION_RATE)
	base_multiplier = data.get("base_multiplier", DEFAULT_BASE_MULTIPLIER)
	_production_multiplier = data.get("production_multiplier", DEFAULT_BASE_MULTIPLIER)
	_player_faction_id = data.get("player_faction_id", -1)
	_is_paused = data.get("is_paused", false)
	_last_milestone_minute = data.get("last_milestone_minute", 0)

	_enemy_faction_ids.clear()
	for id in data.get("enemy_faction_ids", []):
		_enemy_faction_ids.append(id)
