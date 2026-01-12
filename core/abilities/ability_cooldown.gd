class_name AbilityCooldown
extends RefCounted
## AbilityCooldown tracks cooldowns for abilities.

## Active cooldowns (ability_id -> remaining_time)
var _cooldowns: Dictionary = {}

## Cooldown durations (ability_id -> duration)
var _durations: Dictionary = {}


func _init() -> void:
	pass


## Register ability cooldown duration.
func register_ability(ability_id: String, duration: float) -> void:
	_durations[ability_id] = duration


## Start cooldown for ability.
func start_cooldown(ability_id: String, duration: float = -1.0) -> void:
	var cd := duration if duration > 0 else _durations.get(ability_id, 10.0)
	_cooldowns[ability_id] = cd


## Update all cooldowns.
func update(delta: float) -> Array[String]:
	var ready: Array[String] = []

	var to_remove: Array[String] = []
	for ability_id in _cooldowns:
		_cooldowns[ability_id] -= delta

		if _cooldowns[ability_id] <= 0:
			to_remove.append(ability_id)
			ready.append(ability_id)

	for ability_id in to_remove:
		_cooldowns.erase(ability_id)

	return ready


## Check if ability is on cooldown.
func is_on_cooldown(ability_id: String) -> bool:
	return _cooldowns.has(ability_id) and _cooldowns[ability_id] > 0


## Get remaining cooldown.
func get_remaining(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)


## Get cooldown progress (0 = just started, 1 = ready).
func get_progress(ability_id: String) -> float:
	if not is_on_cooldown(ability_id):
		return 1.0

	var remaining := _cooldowns.get(ability_id, 0.0)
	var duration := _durations.get(ability_id, 10.0)

	return 1.0 - (remaining / duration) if duration > 0 else 1.0


## Reset cooldown.
func reset_cooldown(ability_id: String) -> void:
	_cooldowns.erase(ability_id)


## Clear all cooldowns.
func clear() -> void:
	_cooldowns.clear()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"cooldowns": _cooldowns.duplicate(),
		"durations": _durations.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldowns = data.get("cooldowns", {}).duplicate()
	_durations = data.get("durations", {}).duplicate()


## Get summary.
func get_summary() -> Dictionary:
	var on_cooldown: Array[String] = []
	for ability_id in _cooldowns:
		on_cooldown.append("%s (%.1fs)" % [ability_id, _cooldowns[ability_id]])

	return {
		"active_cooldowns": _cooldowns.size(),
		"registered": _durations.size(),
		"on_cooldown": on_cooldown
	}
