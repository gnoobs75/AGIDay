class_name UnhackingMechanic
extends RefCounted
## UnhackingMechanic handles damage-based unhacking attempts.
## 10% chance per hit with minimum damage threshold.

signal unhacking_attempted(unit_id: int, attacker_faction: String, success: bool)
signal unit_unhacked(unit_id: int, by_damage: bool)

## Unhacking chance per valid hit (0-1)
var unhacking_chance: float = 0.10  ## 10%

## Minimum damage to trigger unhacking check
var damage_threshold: float = 10.0

## Unit info callback (unit_id) -> {original_faction, current_owner, is_hacked}
var _unit_info_callback: Callable

## Unhacking callback (unit_id) -> void
var _unhack_callback: Callable

## Statistics
var _stats: Dictionary = {
	"total_attempts": 0,
	"successful_unhacks": 0,
	"failed_unhacks": 0,
	"damage_blocked": 0
}


func _init() -> void:
	pass


## Set unit info callback.
func set_unit_info_callback(callback: Callable) -> void:
	_unit_info_callback = callback


## Set unhack callback.
func set_unhack_callback(callback: Callable) -> void:
	_unhack_callback = callback


## Process damage event for potential unhacking.
## Returns true if unhacking succeeded.
func process_damage(
	unit_id: int,
	attacker_faction: String,
	damage: float
) -> bool:
	# Get unit info
	var info := _get_unit_info(unit_id)
	if info.is_empty():
		return false

	# Only process hacked units
	if not info.get("is_hacked", false):
		return false

	# Only original faction can unhack
	var original: String = info.get("original_faction", "")
	if attacker_faction != original:
		return false

	# Check damage threshold
	if damage < damage_threshold:
		_stats["damage_blocked"] += 1
		return false

	# Roll for unhacking
	_stats["total_attempts"] += 1
	var roll := randf()
	var success := roll < unhacking_chance

	unhacking_attempted.emit(unit_id, attacker_faction, success)

	if success:
		_stats["successful_unhacks"] += 1

		# Execute unhacking
		if _unhack_callback.is_valid():
			_unhack_callback.call(unit_id)

		unit_unhacked.emit(unit_id, true)
		return true
	else:
		_stats["failed_unhacks"] += 1
		return false


## Get unit info via callback.
func _get_unit_info(unit_id: int) -> Dictionary:
	if _unit_info_callback.is_valid():
		return _unit_info_callback.call(unit_id)
	return {}


## Get statistics.
func get_stats() -> Dictionary:
	return _stats.duplicate()


## Get success rate.
func get_actual_success_rate() -> float:
	if _stats["total_attempts"] == 0:
		return 0.0
	return float(_stats["successful_unhacks"]) / float(_stats["total_attempts"])


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"unhacking_chance": unhacking_chance,
		"damage_threshold": damage_threshold,
		"stats": _stats.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	unhacking_chance = data.get("unhacking_chance", 0.10)
	damage_threshold = data.get("damage_threshold", 10.0)
	_stats = data.get("stats", _stats).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"config": {
			"chance": "%.0f%%" % (unhacking_chance * 100),
			"threshold": damage_threshold
		},
		"stats": _stats,
		"actual_rate": "%.1f%%" % (get_actual_success_rate() * 100)
	}
