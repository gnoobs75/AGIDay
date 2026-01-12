class_name OverclockAbility
extends RefCounted
## OverclockAbility boosts production facility speed with meltdown risk.
## R hotkey, 200 REE + 100 power cost, 60s cooldown, 30s duration, 15% meltdown risk.

signal overclock_started(building_id: int, duration: float)
signal overclock_ended(building_id: int)
signal overclock_meltdown(building_id: int)
signal production_boosted(building_id: int, multiplier: float)

## Configuration
const ABILITY_ID := "overclock"
const HOTKEY := "R"
const REE_COST := 200.0
const POWER_COST := 100.0
const COOLDOWN := 60.0
const DURATION := 30.0
const SPEED_MULTIPLIER := 2.0
const MELTDOWN_CHANCE := 0.15
const MELTDOWN_CHECK_INTERVAL := 5.0  ## Check every 5 seconds
const MAX_OVERCLOCKS := 10

## Active overclocks (building_id -> overclock_data)
var _active_overclocks: Dictionary = {}

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## RNG for meltdown checks
var _rng := RandomNumberGenerator.new()

## Callbacks
var _get_building_type: Callable  ## (building_id) -> String
var _set_production_multiplier: Callable  ## (building_id, multiplier) -> void
var _trigger_meltdown: Callable  ## (building_id) -> void
var _is_production_building: Callable  ## (building_id) -> bool


func _init() -> void:
	_rng.randomize()


## Set callbacks.
func set_get_building_type(callback: Callable) -> void:
	_get_building_type = callback


func set_production_multiplier(callback: Callable) -> void:
	_set_production_multiplier = callback


func set_trigger_meltdown(callback: Callable) -> void:
	_trigger_meltdown = callback


func set_is_production_building(callback: Callable) -> void:
	_is_production_building = callback


## Check if ability can be activated.
func can_activate() -> Dictionary:
	var result := {
		"can_activate": true,
		"reason": ""
	}

	if _cooldown_remaining > 0:
		result["can_activate"] = false
		result["reason"] = "On cooldown (%.1fs)" % _cooldown_remaining
		return result

	if _active_overclocks.size() >= MAX_OVERCLOCKS:
		result["can_activate"] = false
		result["reason"] = "Maximum overclocks active"
		return result

	return result


## Activate overclock on building.
func activate(building_id: int) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	# Check if already overclocked
	if _active_overclocks.has(building_id):
		return false

	# Verify it's a production building
	if _is_production_building.is_valid():
		if not _is_production_building.call(building_id):
			return false

	# Start overclock
	_active_overclocks[building_id] = {
		"remaining_duration": DURATION,
		"meltdown_timer": MELTDOWN_CHECK_INTERVAL,
		"total_meltdown_checks": 0
	}

	# Apply production multiplier
	if _set_production_multiplier.is_valid():
		_set_production_multiplier.call(building_id, SPEED_MULTIPLIER)
		production_boosted.emit(building_id, SPEED_MULTIPLIER)

	# Start cooldown
	_cooldown_remaining = COOLDOWN

	overclock_started.emit(building_id, DURATION)
	return true


## Activate on multiple buildings.
func activate_multiple(building_ids: Array[int]) -> int:
	var activated := 0
	for building_id in building_ids:
		if activate(building_id):
			activated += 1
			# Only one overclock per activation
			break
	return activated


## Update all overclocks.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update active overclocks
	var to_remove: Array[int] = []

	for building_id in _active_overclocks:
		var data: Dictionary = _active_overclocks[building_id]

		# Update duration
		data["remaining_duration"] -= delta

		if data["remaining_duration"] <= 0:
			to_remove.append(building_id)
			continue

		# Update meltdown timer
		data["meltdown_timer"] -= delta

		if data["meltdown_timer"] <= 0:
			data["meltdown_timer"] = MELTDOWN_CHECK_INTERVAL
			data["total_meltdown_checks"] += 1

			# Check for meltdown
			if _check_meltdown(building_id, data["total_meltdown_checks"]):
				_trigger_building_meltdown(building_id)
				to_remove.append(building_id)

	# Remove ended overclocks
	for building_id in to_remove:
		_end_overclock(building_id)


## Check for meltdown based on accumulated risk.
func _check_meltdown(building_id: int, check_count: int) -> bool:
	# Risk increases slightly with each check
	var accumulated_risk := MELTDOWN_CHANCE * (1.0 + check_count * 0.1)
	var roll := _rng.randf()
	return roll < accumulated_risk


## Trigger meltdown on building.
func _trigger_building_meltdown(building_id: int) -> void:
	# Reset production multiplier
	if _set_production_multiplier.is_valid():
		_set_production_multiplier.call(building_id, 1.0)

	# Trigger meltdown effect
	if _trigger_meltdown.is_valid():
		_trigger_meltdown.call(building_id)

	overclock_meltdown.emit(building_id)


## End overclock normally.
func _end_overclock(building_id: int) -> void:
	if _active_overclocks.has(building_id):
		# Reset production multiplier
		if _set_production_multiplier.is_valid():
			_set_production_multiplier.call(building_id, 1.0)

		_active_overclocks.erase(building_id)
		overclock_ended.emit(building_id)


## Cancel overclock early.
func cancel_overclock(building_id: int) -> void:
	_end_overclock(building_id)


## Check if building is overclocked.
func is_overclocked(building_id: int) -> bool:
	return _active_overclocks.has(building_id)


## Get remaining duration for overclock.
func get_remaining_duration(building_id: int) -> float:
	var data: Dictionary = _active_overclocks.get(building_id, {})
	return data.get("remaining_duration", 0.0)


## Get active overclock count.
func get_active_count() -> int:
	return _active_overclocks.size()


## Get cooldown remaining.
func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_remaining)


## Is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"hotkey": HOTKEY,
		"ree_cost": REE_COST,
		"power_cost": POWER_COST,
		"cooldown": COOLDOWN,
		"duration": DURATION,
		"speed_multiplier": SPEED_MULTIPLIER,
		"meltdown_chance": MELTDOWN_CHANCE,
		"max_overclocks": MAX_OVERCLOCKS
	}


## Create AbilityConfig for registration.
func create_ability_config() -> AbilityConfig:
	var config := AbilityConfig.new()
	config.ability_id = ABILITY_ID
	config.faction_id = "ferron_horde"  ## Industrial faction
	config.display_name = "Overclock"
	config.description = "Boost production speed by 2x for 30s with meltdown risk"
	config.hotkey = HOTKEY
	config.ability_type = AbilityConfig.AbilityType.TARGETED
	config.target_type = AbilityConfig.TargetType.UNIT  ## Target building
	config.cooldown = COOLDOWN
	config.resource_cost = {"ree": REE_COST, "power": POWER_COST}
	config.execution_params = {
		"duration": DURATION,
		"speed_multiplier": SPEED_MULTIPLIER,
		"meltdown_chance": MELTDOWN_CHANCE
	}
	config.feedback = {
		"visual_effect": "overclock_sparks",
		"sound_effect": "overclock_activate",
		"ui_notification": "Overclock activated! Watch for meltdown risk!"
	}
	return config


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var overclocks_data: Dictionary = {}
	for building_id in _active_overclocks:
		var data: Dictionary = _active_overclocks[building_id]
		overclocks_data[str(building_id)] = {
			"remaining_duration": data["remaining_duration"],
			"meltdown_timer": data["meltdown_timer"],
			"total_meltdown_checks": data["total_meltdown_checks"]
		}

	return {
		"cooldown_remaining": _cooldown_remaining,
		"active_overclocks": overclocks_data,
		"rng_state": _rng.state
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)

	if data.has("rng_state"):
		_rng.state = data["rng_state"]

	_active_overclocks.clear()
	for building_id_str in data.get("active_overclocks", {}):
		var overclock_data: Dictionary = data["active_overclocks"][building_id_str]
		_active_overclocks[int(building_id_str)] = {
			"remaining_duration": overclock_data["remaining_duration"],
			"meltdown_timer": overclock_data["meltdown_timer"],
			"total_meltdown_checks": overclock_data.get("total_meltdown_checks", 0)
		}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var overclock_summaries: Array[Dictionary] = []
	for building_id in _active_overclocks:
		var data: Dictionary = _active_overclocks[building_id]
		overclock_summaries.append({
			"building": building_id,
			"remaining": "%.1fs" % data["remaining_duration"],
			"checks": data["total_meltdown_checks"]
		})

	return {
		"active_overclocks": _active_overclocks.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"overclocks": overclock_summaries
	}
