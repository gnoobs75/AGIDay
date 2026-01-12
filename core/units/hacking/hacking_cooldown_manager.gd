class_name HackingCooldownManager
extends RefCounted
## HackingCooldownManager tracks per-faction hacking cooldowns.

## Default cooldown duration (seconds)
const DEFAULT_COOLDOWN := 3.0

## Active cooldowns (faction_id -> remaining_time)
var _cooldowns: Dictionary = {}

## Cooldown durations per faction (faction_id -> duration)
var _cooldown_durations: Dictionary = {}


func _init() -> void:
	pass


## Start cooldown for faction.
func start_cooldown(faction_id: String) -> void:
	var duration := get_cooldown_duration(faction_id)
	_cooldowns[faction_id] = duration


## Update all cooldowns.
func update(delta: float) -> void:
	var to_remove: Array[String] = []

	for faction_id in _cooldowns:
		_cooldowns[faction_id] -= delta
		if _cooldowns[faction_id] <= 0:
			to_remove.append(faction_id)

	for faction_id in to_remove:
		_cooldowns.erase(faction_id)


## Check if faction is on cooldown.
func is_on_cooldown(faction_id: String) -> bool:
	return _cooldowns.has(faction_id) and _cooldowns[faction_id] > 0


## Get remaining cooldown time.
func get_remaining_cooldown(faction_id: String) -> float:
	return _cooldowns.get(faction_id, 0.0)


## Get cooldown duration for faction.
func get_cooldown_duration(faction_id: String) -> float:
	return _cooldown_durations.get(faction_id, DEFAULT_COOLDOWN)


## Set cooldown duration for faction.
func set_cooldown_duration(faction_id: String, duration: float) -> void:
	_cooldown_durations[faction_id] = duration


## Reset cooldown for faction.
func reset_cooldown(faction_id: String) -> void:
	_cooldowns.erase(faction_id)


## Clear all cooldowns.
func clear_all() -> void:
	_cooldowns.clear()


## Get all active cooldowns.
func get_active_cooldowns() -> Dictionary:
	return _cooldowns.duplicate()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"cooldowns": _cooldowns.duplicate(),
		"cooldown_durations": _cooldown_durations.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldowns = data.get("cooldowns", {}).duplicate()
	_cooldown_durations = data.get("cooldown_durations", {}).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"active_cooldowns": _cooldowns.size(),
		"cooldowns": _cooldowns.duplicate()
	}
