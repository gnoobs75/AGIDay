class_name HackingAbility
extends RefCounted
## HackingAbility handles hack execution with costs, cooldowns, and success rate.

signal hack_attempted(hacker_id: int, target_id: int)
signal hack_succeeded(hacker_id: int, target_id: int)
signal hack_failed(hacker_id: int, target_id: int, reason: String)
signal resources_consumed(faction_id: String, ree: float, power: float)

## Configuration
var success_rate: float = 0.90  ## 90% base success rate
var ree_cost: float = 50.0
var power_cost: float = 25.0
var range_limit: float = 10.0

## Managers
var _cooldown_manager: HackingCooldownManager = null
var _restrictions: HackingRestrictions = null
var _hacking_manager: HackingSystemManager = null

## Resource check callback
var _resource_check_callback: Callable

## Resource consume callback
var _resource_consume_callback: Callable

## Unit info callback (returns {faction, type, level, position, is_controlled})
var _unit_info_callback: Callable

## Statistics
var _stats: Dictionary = {
	"total_attempts": 0,
	"successful_hacks": 0,
	"failed_hacks": 0,
	"resources_spent_ree": 0.0,
	"resources_spent_power": 0.0
}


func _init() -> void:
	_cooldown_manager = HackingCooldownManager.new()
	_restrictions = HackingRestrictions.new()


## Set hacking system manager reference.
func set_hacking_manager(manager: HackingSystemManager) -> void:
	_hacking_manager = manager


## Set resource check callback (faction_id, ree, power) -> bool.
func set_resource_check_callback(callback: Callable) -> void:
	_resource_check_callback = callback


## Set resource consume callback (faction_id, ree, power) -> void.
func set_resource_consume_callback(callback: Callable) -> void:
	_resource_consume_callback = callback


## Set unit info callback (unit_id) -> Dictionary.
func set_unit_info_callback(callback: Callable) -> void:
	_unit_info_callback = callback


## Check if unit can be hacked.
func can_hack(hacker_id: int, hacker_faction: String, target_id: int) -> Dictionary:
	var result := {
		"can_hack": true,
		"reason": ""
	}

	# Get target info
	var target_info := _get_unit_info(target_id)
	if target_info.is_empty():
		result["can_hack"] = false
		result["reason"] = "Invalid target"
		return result

	# Check hacker position for range
	var hacker_info := _get_unit_info(hacker_id)
	if hacker_info.is_empty():
		result["can_hack"] = false
		result["reason"] = "Invalid hacker"
		return result

	# Check range
	var hacker_pos: Vector3 = hacker_info.get("position", Vector3.ZERO)
	var target_pos: Vector3 = target_info.get("position", Vector3.ZERO)
	var distance := hacker_pos.distance_to(target_pos)

	if distance > range_limit:
		result["can_hack"] = false
		result["reason"] = "Target out of range (%.1f > %.1f)" % [distance, range_limit]
		return result

	# Check cooldown
	if _cooldown_manager.is_on_cooldown(hacker_faction):
		var remaining := _cooldown_manager.get_remaining_cooldown(hacker_faction)
		result["can_hack"] = false
		result["reason"] = "On cooldown (%.1fs remaining)" % remaining
		return result

	# Check resources
	if not _has_resources(hacker_faction, ree_cost, power_cost):
		result["can_hack"] = false
		result["reason"] = "Insufficient resources"
		return result

	# Check restrictions
	var restriction_check := _restrictions.can_hack_unit(
		hacker_faction,
		target_info.get("faction", ""),
		target_info.get("type", ""),
		target_info.get("level", 1),
		target_info.get("is_controlled", false)
	)

	if not restriction_check["allowed"]:
		result["can_hack"] = false
		result["reason"] = restriction_check["reason"]
		return result

	return result


## Execute hack attempt.
func execute_hack(hacker_id: int, hacker_faction: String, target_id: int) -> bool:
	_stats["total_attempts"] += 1
	hack_attempted.emit(hacker_id, target_id)

	# Validate
	var can_hack_result := can_hack(hacker_id, hacker_faction, target_id)
	if not can_hack_result["can_hack"]:
		_stats["failed_hacks"] += 1
		hack_failed.emit(hacker_id, target_id, can_hack_result["reason"])
		return false

	# Roll for success
	var roll := randf()
	if roll > success_rate:
		_stats["failed_hacks"] += 1
		hack_failed.emit(hacker_id, target_id, "Hack attempt failed (%.0f%% chance)" % (success_rate * 100))
		# Start cooldown even on failure
		_cooldown_manager.start_cooldown(hacker_faction)
		return false

	# Consume resources
	_consume_resources(hacker_faction, ree_cost, power_cost)
	_stats["resources_spent_ree"] += ree_cost
	_stats["resources_spent_power"] += power_cost
	resources_consumed.emit(hacker_faction, ree_cost, power_cost)

	# Start cooldown
	_cooldown_manager.start_cooldown(hacker_faction)

	# Execute hack through manager
	if _hacking_manager != null:
		var success := _hacking_manager.hack_unit(target_id, hacker_faction)
		if success:
			_stats["successful_hacks"] += 1
			hack_succeeded.emit(hacker_id, target_id)
			return true
		else:
			_stats["failed_hacks"] += 1
			hack_failed.emit(hacker_id, target_id, "State transition failed")
			return false
	else:
		_stats["failed_hacks"] += 1
		hack_failed.emit(hacker_id, target_id, "Hacking manager not available")
		return false


## Update cooldowns.
func update(delta: float) -> void:
	_cooldown_manager.update(delta)


## Get unit info via callback.
func _get_unit_info(unit_id: int) -> Dictionary:
	if _unit_info_callback.is_valid():
		return _unit_info_callback.call(unit_id)
	return {}


## Check resources via callback.
func _has_resources(faction_id: String, ree: float, power: float) -> bool:
	if _resource_check_callback.is_valid():
		return _resource_check_callback.call(faction_id, ree, power)
	return true  # Default to allowing if no callback


## Consume resources via callback.
func _consume_resources(faction_id: String, ree: float, power: float) -> void:
	if _resource_consume_callback.is_valid():
		_resource_consume_callback.call(faction_id, ree, power)


## Get cooldown manager.
func get_cooldown_manager() -> HackingCooldownManager:
	return _cooldown_manager


## Get restrictions.
func get_restrictions() -> HackingRestrictions:
	return _restrictions


## Get statistics.
func get_stats() -> Dictionary:
	return _stats.duplicate()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"success_rate": success_rate,
		"ree_cost": ree_cost,
		"power_cost": power_cost,
		"range_limit": range_limit,
		"cooldown_manager": _cooldown_manager.to_dict(),
		"restrictions": _restrictions.to_dict(),
		"stats": _stats.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	success_rate = data.get("success_rate", 0.90)
	ree_cost = data.get("ree_cost", 50.0)
	power_cost = data.get("power_cost", 25.0)
	range_limit = data.get("range_limit", 10.0)
	_cooldown_manager.from_dict(data.get("cooldown_manager", {}))
	_restrictions.from_dict(data.get("restrictions", {}))
	_stats = data.get("stats", _stats).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"config": {
			"success_rate": success_rate,
			"ree_cost": ree_cost,
			"power_cost": power_cost,
			"range_limit": range_limit
		},
		"cooldowns": _cooldown_manager.get_summary(),
		"restrictions": _restrictions.get_summary(),
		"stats": _stats
	}
