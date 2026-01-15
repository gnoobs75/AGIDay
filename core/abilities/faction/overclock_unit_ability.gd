class_name OverclockUnitAbility
extends RefCounted
## OverclockUnitAbility gives OptiForge units temporary speed/damage boost with self-damage risk.
## Q hotkey, 60 REE cost, 12s cooldown, 5s duration.
## Boosted units deal +50% damage and move +30% faster but take 5 DPS self-damage.

signal overclock_started(unit_ids: Array[int], duration: float)
signal overclock_ended(unit_ids: Array[int])
signal unit_overheated(unit_id: int, damage: float)
signal buff_applied(unit_id: int, damage_boost: float, speed_boost: float)
signal buff_expired(unit_id: int)

## Configuration
const ABILITY_ID := "overclock_unit"
const HOTKEY := "Q"
const REE_COST := 60.0
const COOLDOWN := 12.0
const DURATION := 5.0
const DAMAGE_BOOST := 0.50  ## +50% damage while overclocked
const SPEED_BOOST := 0.30  ## +30% movement speed while overclocked
const SELF_DAMAGE_PER_SECOND := 5.0  ## DPS to self while overclocked
const OVERHEAT_VISUAL_INTENSITY := 2.0  ## Emission multiplier
const MAX_OVERCLOCKED_UNITS := 50

## Overclocked units (unit_id -> overclock_data)
var _overclocked_units: Dictionary = {}

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## Stats tracking
var _total_overclocks: int = 0
var _total_bonus_damage_dealt: float = 0.0
var _total_self_damage_taken: float = 0.0

## Callbacks
var _get_faction_units: Callable  ## (faction_id) -> Array[int]
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _apply_self_damage: Callable  ## (unit_id, damage) -> void
var _set_unit_emission: Callable  ## (unit_id, intensity: float) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_faction_units(callback: Callable) -> void:
	_get_faction_units = callback


func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_apply_self_damage(callback: Callable) -> void:
	_apply_self_damage = callback


func set_unit_emission(callback: Callable) -> void:
	_set_unit_emission = callback


## Check if ability can be used.
func can_activate() -> Dictionary:
	var result := {
		"can_activate": true,
		"reason": ""
	}

	if _cooldown_remaining > 0:
		result["can_activate"] = false
		result["reason"] = "On cooldown (%.1fs)" % _cooldown_remaining
		return result

	return result


## Activate overclock for all OptiForge units.
func activate(faction_id: String) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	# Get all faction units
	var unit_ids: Array[int] = []
	if _get_faction_units.is_valid():
		var result: Array = _get_faction_units.call(faction_id)
		for u in result:
			if unit_ids.size() < MAX_OVERCLOCKED_UNITS:
				unit_ids.append(u)

	if unit_ids.is_empty():
		return false

	# Apply overclock to all units
	for unit_id in unit_ids:
		_apply_overclock(unit_id)

	# Start cooldown
	_cooldown_remaining = COOLDOWN
	_total_overclocks += 1

	overclock_started.emit(unit_ids, DURATION)

	return true


## Activate overclock for specific units.
func activate_for_units(unit_ids: Array[int]) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	if unit_ids.is_empty():
		return false

	# Apply overclock to specified units
	for unit_id in unit_ids:
		if _overclocked_units.size() < MAX_OVERCLOCKED_UNITS:
			_apply_overclock(unit_id)

	# Start cooldown
	_cooldown_remaining = COOLDOWN
	_total_overclocks += 1

	overclock_started.emit(unit_ids, DURATION)

	return true


## Apply overclock effect to a unit.
func _apply_overclock(unit_id: int) -> void:
	if _overclocked_units.has(unit_id):
		# Refresh duration if already overclocked
		_overclocked_units[unit_id]["remaining"] = DURATION
		return

	_overclocked_units[unit_id] = {
		"remaining": DURATION,
		"damage_boost": DAMAGE_BOOST,
		"speed_boost": SPEED_BOOST,
		"self_damage_accumulated": 0.0
	}

	# Set visual effect (heat glow)
	if _set_unit_emission.is_valid():
		_set_unit_emission.call(unit_id, OVERHEAT_VISUAL_INTENSITY)

	buff_applied.emit(unit_id, DAMAGE_BOOST, SPEED_BOOST)


## Remove overclock effect from a unit.
func _remove_overclock(unit_id: int) -> void:
	if not _overclocked_units.has(unit_id):
		return

	_overclocked_units.erase(unit_id)

	# Reset visual effect
	if _set_unit_emission.is_valid():
		_set_unit_emission.call(unit_id, 0.4)  # Normal emission

	buff_expired.emit(unit_id)


## Check if unit is overclocked.
func is_overclocked(unit_id: int) -> bool:
	return _overclocked_units.has(unit_id)


## Get damage multiplier for unit (1.0 + boost if overclocked).
## Call this from damage calculation.
func get_damage_multiplier(unit_id: int) -> float:
	if not _overclocked_units.has(unit_id):
		return 1.0
	return 1.0 + _overclocked_units[unit_id]["damage_boost"]


## Get speed multiplier for unit (1.0 + boost if overclocked).
## Call this from movement calculation.
func get_speed_multiplier(unit_id: int) -> float:
	if not _overclocked_units.has(unit_id):
		return 1.0
	return 1.0 + _overclocked_units[unit_id]["speed_boost"]


## Apply overclock damage boost to outgoing damage.
## Returns modified damage amount.
func apply_to_damage(unit_id: int, base_damage: float) -> float:
	if not _overclocked_units.has(unit_id):
		return base_damage

	var multiplier := get_damage_multiplier(unit_id)
	var boosted_damage := base_damage * multiplier
	var bonus_damage := boosted_damage - base_damage

	_total_bonus_damage_dealt += bonus_damage

	return boosted_damage


## Update overclock effects.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update overclocked units
	var to_remove: Array[int] = []

	for unit_id in _overclocked_units:
		var data: Dictionary = _overclocked_units[unit_id]
		data["remaining"] -= delta

		# Apply self-damage (overheating)
		var self_damage := SELF_DAMAGE_PER_SECOND * delta
		data["self_damage_accumulated"] += self_damage
		_total_self_damage_taken += self_damage

		if _apply_self_damage.is_valid():
			_apply_self_damage.call(unit_id, self_damage)
			unit_overheated.emit(unit_id, self_damage)

		if data["remaining"] <= 0:
			to_remove.append(unit_id)

	# Remove expired overclocks
	for unit_id in to_remove:
		_remove_overclock(unit_id)

	if not to_remove.is_empty():
		overclock_ended.emit(to_remove)


## Cancel all overclock effects.
func cancel_all(reason: String = "manual") -> void:
	var unit_ids: Array[int] = []
	for unit_id in _overclocked_units:
		unit_ids.append(unit_id)

	for unit_id in unit_ids:
		_remove_overclock(unit_id)


## Get overclocked unit count.
func get_overclocked_count() -> int:
	return _overclocked_units.size()


## Get remaining cooldown.
func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_remaining)


## Is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0


## Get remaining overclock time for unit.
func get_overclock_remaining(unit_id: int) -> float:
	if not _overclocked_units.has(unit_id):
		return 0.0
	return maxf(0.0, _overclocked_units[unit_id]["remaining"])


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"hotkey": HOTKEY,
		"ree_cost": REE_COST,
		"cooldown": COOLDOWN,
		"duration": DURATION,
		"damage_boost": DAMAGE_BOOST,
		"speed_boost": SPEED_BOOST,
		"self_damage_per_second": SELF_DAMAGE_PER_SECOND,
		"max_overclocked_units": MAX_OVERCLOCKED_UNITS
	}


## Create AbilityConfig for registration.
func create_ability_config() -> AbilityConfig:
	var config := AbilityConfig.new()
	config.ability_id = ABILITY_ID
	config.faction_id = "glacius"  ## OptiForge uses "glacius" for armor mechanics
	config.display_name = "Overclock"
	config.description = "All OptiForge units gain +50% damage and +30% speed for 5s but take 5 DPS"
	config.hotkey = HOTKEY
	config.ability_type = AbilityConfig.AbilityType.GLOBAL
	config.target_type = AbilityConfig.TargetType.NONE
	config.cooldown = COOLDOWN
	config.resource_cost = {"ree": REE_COST, "power": 0.0}
	config.execution_params = {
		"duration": DURATION,
		"damage_boost": DAMAGE_BOOST,
		"speed_boost": SPEED_BOOST,
		"self_damage_per_second": SELF_DAMAGE_PER_SECOND
	}
	config.feedback = {
		"visual_effect": "overclock_heat",
		"sound_effect": "overclock_activate",
		"ui_notification": "OVERCLOCK! +50% damage, +30% speed"
	}
	return config


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"total_overclocks": _total_overclocks,
		"total_bonus_damage_dealt": _total_bonus_damage_dealt,
		"total_self_damage_taken": _total_self_damage_taken,
		"avg_bonus_per_use": _total_bonus_damage_dealt / maxf(1.0, _total_overclocks)
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var overclocked_data: Dictionary = {}
	for unit_id in _overclocked_units:
		overclocked_data[str(unit_id)] = _overclocked_units[unit_id].duplicate()

	return {
		"cooldown_remaining": _cooldown_remaining,
		"overclocked_units": overclocked_data,
		"total_overclocks": _total_overclocks,
		"total_bonus_damage_dealt": _total_bonus_damage_dealt,
		"total_self_damage_taken": _total_self_damage_taken
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)
	_total_overclocks = data.get("total_overclocks", 0)
	_total_bonus_damage_dealt = data.get("total_bonus_damage_dealt", 0.0)
	_total_self_damage_taken = data.get("total_self_damage_taken", 0.0)

	_overclocked_units.clear()
	for unit_id_str in data.get("overclocked_units", {}):
		_overclocked_units[int(unit_id_str)] = data["overclocked_units"][unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"overclocked_units": _overclocked_units.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"total_overclocks": _total_overclocks,
		"total_bonus_damage": "%.0f" % _total_bonus_damage_dealt,
		"total_self_damage": "%.0f" % _total_self_damage_taken
	}
