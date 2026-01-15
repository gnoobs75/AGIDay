class_name AcrobaticStrikeAbility
extends RefCounted
## AcrobaticStrikeAbility allows Dynapods Vanguard units to perform leap attacks.
## B hotkey, 40 REE cost, 15s cooldown.
## Units leap to target location dealing bonus damage on landing.

signal leap_started(unit_id: int, target_pos: Vector3)
signal leap_landed(unit_id: int, damage_dealt: float, units_hit: int)
signal unit_leaping(unit_id: int, progress: float)

## Configuration
const ABILITY_ID := "acrobatic_strike"
const HOTKEY := "B"
const REE_COST := 40.0
const COOLDOWN := 15.0
const LEAP_DURATION := 0.8  ## Seconds in the air
const LEAP_HEIGHT := 8.0  ## Peak height of leap arc
const LEAP_RANGE := 20.0  ## Maximum leap distance
const LANDING_DAMAGE := 75.0  ## Base damage on landing
const LANDING_RADIUS := 5.0  ## AoE radius on landing
const DAMAGE_FALLOFF := 0.5  ## Damage at edge = base * falloff

## Leaping units (unit_id -> leap_data)
var _leaping_units: Dictionary = {}

## Registered units
var _registered_units: Dictionary = {}

## Cooldown state
var _cooldown_remaining: float = 0.0

## Stats tracking
var _total_leaps: int = 0
var _total_damage_dealt: float = 0.0
var _total_units_hit: int = 0

## Callbacks
var _get_enemies_in_radius: Callable  ## (position, radius) -> Array[Dictionary]
var _apply_damage: Callable  ## (target_id, damage) -> void
var _set_unit_position: Callable  ## (unit_id, position) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_enemies_in_radius(callback: Callable) -> void:
	_get_enemies_in_radius = callback


func set_apply_damage(callback: Callable) -> void:
	_apply_damage = callback


func set_unit_position(callback: Callable) -> void:
	_set_unit_position = callback


## Register unit for acrobatic strikes.
func register_unit(unit_id: int) -> void:
	_registered_units[unit_id] = {
		"leaps_performed": 0,
		"damage_dealt": 0.0
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_registered_units.erase(unit_id)
	_leaping_units.erase(unit_id)


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


## Activate leap for a unit to target position.
func activate_leap(unit_id: int, start_pos: Vector3, target_pos: Vector3) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	if not _registered_units.has(unit_id):
		return false

	# Check range
	var distance: float = start_pos.distance_to(target_pos)
	if distance > LEAP_RANGE:
		# Clamp to max range
		var direction: Vector3 = (target_pos - start_pos).normalized()
		target_pos = start_pos + direction * LEAP_RANGE

	# Start leap
	_leaping_units[unit_id] = {
		"start_pos": start_pos,
		"target_pos": target_pos,
		"elapsed": 0.0,
		"landed": false
	}

	_cooldown_remaining = COOLDOWN
	_total_leaps += 1

	leap_started.emit(unit_id, target_pos)

	return true


## Activate leap for multiple units.
func activate_for_units(unit_ids: Array[int], target_pos: Vector3, positions: Dictionary) -> int:
	var validation := can_activate()
	if not validation["can_activate"]:
		return 0

	var leaps_started: int = 0

	for unit_id in unit_ids:
		if not _registered_units.has(unit_id):
			continue
		if not positions.has(unit_id):
			continue

		var start_pos: Vector3 = positions[unit_id]
		if activate_leap(unit_id, start_pos, target_pos):
			leaps_started += 1
			# Only apply cooldown once for group activation
			if leaps_started == 1:
				_cooldown_remaining = COOLDOWN

	return leaps_started


## Update leaping units.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update leaping units
	var to_remove: Array[int] = []

	for unit_id in _leaping_units:
		var data: Dictionary = _leaping_units[unit_id]
		data["elapsed"] += delta

		var progress: float = data["elapsed"] / LEAP_DURATION

		if progress >= 1.0:
			# Leap complete - land and deal damage
			_land_unit(unit_id, data)
			to_remove.append(unit_id)
		else:
			# Update unit position along arc
			_update_leap_position(unit_id, data, progress)
			unit_leaping.emit(unit_id, progress)

	for unit_id in to_remove:
		_leaping_units.erase(unit_id)


## Update unit position during leap.
func _update_leap_position(unit_id: int, data: Dictionary, progress: float) -> void:
	var start: Vector3 = data["start_pos"]
	var target: Vector3 = data["target_pos"]

	# Lerp horizontal position
	var pos: Vector3 = start.lerp(target, progress)

	# Add arc height (parabola)
	var height: float = LEAP_HEIGHT * 4.0 * progress * (1.0 - progress)
	pos.y = start.y + height

	if _set_unit_position.is_valid():
		_set_unit_position.call(unit_id, pos)


## Handle unit landing.
func _land_unit(unit_id: int, data: Dictionary) -> void:
	var landing_pos: Vector3 = data["target_pos"]

	# Set final position
	if _set_unit_position.is_valid():
		_set_unit_position.call(unit_id, landing_pos)

	# Deal AoE damage
	var damage_dealt: float = 0.0
	var units_hit: int = 0

	if _get_enemies_in_radius.is_valid() and _apply_damage.is_valid():
		var enemies: Array = _get_enemies_in_radius.call(landing_pos, LANDING_RADIUS)

		for enemy in enemies:
			var enemy_pos: Vector3 = enemy.get("position", landing_pos)
			var dist: float = landing_pos.distance_to(enemy_pos)

			# Calculate damage with falloff
			var falloff_mult: float = 1.0 - (dist / LANDING_RADIUS) * (1.0 - DAMAGE_FALLOFF)
			var damage: float = LANDING_DAMAGE * falloff_mult

			var enemy_id: int = enemy.get("id", -1)
			if enemy_id >= 0:
				_apply_damage.call(enemy_id, damage)
				damage_dealt += damage
				units_hit += 1

	# Update stats
	_total_damage_dealt += damage_dealt
	_total_units_hit += units_hit

	if _registered_units.has(unit_id):
		_registered_units[unit_id]["leaps_performed"] += 1
		_registered_units[unit_id]["damage_dealt"] += damage_dealt

	data["landed"] = true
	leap_landed.emit(unit_id, damage_dealt, units_hit)


## Check if unit is currently leaping.
func is_leaping(unit_id: int) -> bool:
	return _leaping_units.has(unit_id)


## Get leap progress (0.0 to 1.0).
func get_leap_progress(unit_id: int) -> float:
	if not _leaping_units.has(unit_id):
		return 0.0
	return minf(1.0, _leaping_units[unit_id]["elapsed"] / LEAP_DURATION)


## Get number of units currently leaping.
func get_leaping_count() -> int:
	return _leaping_units.size()


## Get remaining cooldown.
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
		"cooldown": COOLDOWN,
		"leap_duration": LEAP_DURATION,
		"leap_height": LEAP_HEIGHT,
		"leap_range": LEAP_RANGE,
		"landing_damage": LANDING_DAMAGE,
		"landing_radius": LANDING_RADIUS
	}


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"total_leaps": _total_leaps,
		"total_damage_dealt": _total_damage_dealt,
		"total_units_hit": _total_units_hit,
		"avg_damage_per_leap": _total_damage_dealt / maxf(1.0, _total_leaps),
		"avg_hits_per_leap": float(_total_units_hit) / maxf(1.0, _total_leaps),
		"registered_units": _registered_units.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var registered_export: Dictionary = {}
	for unit_id in _registered_units:
		registered_export[str(unit_id)] = _registered_units[unit_id].duplicate()

	var leaping_export: Dictionary = {}
	for unit_id in _leaping_units:
		var data: Dictionary = _leaping_units[unit_id].duplicate()
		data["start_pos"] = [data["start_pos"].x, data["start_pos"].y, data["start_pos"].z]
		data["target_pos"] = [data["target_pos"].x, data["target_pos"].y, data["target_pos"].z]
		leaping_export[str(unit_id)] = data

	return {
		"registered_units": registered_export,
		"leaping_units": leaping_export,
		"cooldown_remaining": _cooldown_remaining,
		"total_leaps": _total_leaps,
		"total_damage_dealt": _total_damage_dealt,
		"total_units_hit": _total_units_hit
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)
	_total_leaps = data.get("total_leaps", 0)
	_total_damage_dealt = data.get("total_damage_dealt", 0.0)
	_total_units_hit = data.get("total_units_hit", 0)

	_registered_units.clear()
	for unit_id_str in data.get("registered_units", {}):
		_registered_units[int(unit_id_str)] = data["registered_units"][unit_id_str].duplicate()

	_leaping_units.clear()
	for unit_id_str in data.get("leaping_units", {}):
		var leap_data: Dictionary = data["leaping_units"][unit_id_str].duplicate()
		var start: Array = leap_data.get("start_pos", [0, 0, 0])
		leap_data["start_pos"] = Vector3(start[0], start[1], start[2])
		var target: Array = leap_data.get("target_pos", [0, 0, 0])
		leap_data["target_pos"] = Vector3(target[0], target[1], target[2])
		_leaping_units[int(unit_id_str)] = leap_data


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"registered_units": _registered_units.size(),
		"currently_leaping": _leaping_units.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"total_leaps": _total_leaps,
		"total_damage": "%.0f" % _total_damage_dealt
	}
