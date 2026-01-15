class_name CoordinatedBarrageAbility
extends RefCounted
## CoordinatedBarrageAbility marks a target for focus fire by LogiBots Colossus.
## V hotkey, 30 REE cost, 25s cooldown, 8s duration.
## All LogiBots units deal +75% damage to the marked target.
## Nearby LogiBots will automatically switch to the marked target.

signal barrage_started(target_id: int, duration: float)
signal barrage_ended(target_id: int)
signal target_marked(target_id: int)
signal damage_amplified(attacker_id: int, target_id: int, bonus_damage: float)

## Configuration
const ABILITY_ID := "coordinated_barrage"
const HOTKEY := "V"
const REE_COST := 30.0
const COOLDOWN := 25.0
const DURATION := 8.0
const DAMAGE_BONUS := 0.75  ## +75% damage to marked target
const TARGETING_RADIUS := 30.0  ## Units within this range auto-target

## Current barrage state
var _marked_target_id: int = -1
var _barrage_remaining: float = 0.0
var _cooldown_remaining: float = 0.0

## Registered units (unit_id -> unit_data)
var _unit_data: Dictionary = {}

## Stats tracking
var _total_barrages: int = 0
var _total_bonus_damage: float = 0.0
var _targets_killed_while_marked: int = 0

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _set_unit_target: Callable  ## (unit_id, target_id) -> void
var _is_target_alive: Callable  ## (target_id) -> bool


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_unit_target(callback: Callable) -> void:
	_set_unit_target = callback


func set_is_target_alive(callback: Callable) -> void:
	_is_target_alive = callback


## Register unit for coordinated barrage.
func register_unit(unit_id: int) -> void:
	_unit_data[unit_id] = {
		"bonus_damage_dealt": 0.0
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_data.erase(unit_id)


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

	if _barrage_remaining > 0:
		result["can_activate"] = false
		result["reason"] = "Barrage already active"
		return result

	return result


## Activate coordinated barrage on target.
func activate(target_id: int, target_position: Vector3) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	if target_id < 0:
		return false

	# Mark target
	_marked_target_id = target_id
	_barrage_remaining = DURATION
	_cooldown_remaining = COOLDOWN
	_total_barrages += 1

	target_marked.emit(target_id)
	barrage_started.emit(target_id, DURATION)

	# Direct nearby units to attack the marked target
	_redirect_units_to_target(target_id, target_position)

	return true


## Redirect nearby units to attack the marked target.
func _redirect_units_to_target(target_id: int, target_position: Vector3) -> void:
	if not _set_unit_target.is_valid():
		return

	for unit_id in _unit_data:
		if not _get_unit_position.is_valid():
			continue

		var unit_pos: Vector3 = _get_unit_position.call(unit_id)
		var dist := unit_pos.distance_to(target_position)

		if dist <= TARGETING_RADIUS:
			_set_unit_target.call(unit_id, target_id)


## Check if target is currently marked.
func is_target_marked(target_id: int) -> bool:
	return _barrage_remaining > 0 and _marked_target_id == target_id


## Get damage multiplier for attack against target.
## Returns 1.0 + DAMAGE_BONUS if target is marked and attacker is registered.
func get_damage_multiplier(attacker_id: int, target_id: int) -> float:
	if not _unit_data.has(attacker_id):
		return 1.0

	if not is_target_marked(target_id):
		return 1.0

	return 1.0 + DAMAGE_BONUS


## Calculate bonus damage for attack (for stats tracking).
func calculate_bonus_damage(attacker_id: int, target_id: int, base_damage: float) -> float:
	if not _unit_data.has(attacker_id):
		return 0.0

	if not is_target_marked(target_id):
		return 0.0

	var bonus := base_damage * DAMAGE_BONUS

	# Track stats
	if _unit_data.has(attacker_id):
		_unit_data[attacker_id]["bonus_damage_dealt"] += bonus
	_total_bonus_damage += bonus

	damage_amplified.emit(attacker_id, target_id, bonus)

	return bonus


## Update barrage duration.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update barrage duration
	if _barrage_remaining > 0:
		_barrage_remaining -= delta

		# Check if target died
		if _is_target_alive.is_valid():
			if not _is_target_alive.call(_marked_target_id):
				_targets_killed_while_marked += 1
				_end_barrage()
				return

		# Check if barrage expired
		if _barrage_remaining <= 0:
			_end_barrage()


## End the current barrage.
func _end_barrage() -> void:
	var old_target := _marked_target_id
	_marked_target_id = -1
	_barrage_remaining = 0.0
	barrage_ended.emit(old_target)


## Cancel active barrage.
func cancel() -> void:
	if _barrage_remaining > 0:
		_end_barrage()


## Get marked target ID (-1 if none).
func get_marked_target() -> int:
	if _barrage_remaining > 0:
		return _marked_target_id
	return -1


## Get remaining barrage duration.
func get_barrage_remaining() -> float:
	return maxf(0.0, _barrage_remaining)


## Get remaining cooldown.
func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_remaining)


## Is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0


## Is barrage active.
func is_barrage_active() -> bool:
	return _barrage_remaining > 0


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"hotkey": HOTKEY,
		"ree_cost": REE_COST,
		"cooldown": COOLDOWN,
		"duration": DURATION,
		"damage_bonus": DAMAGE_BONUS,
		"targeting_radius": TARGETING_RADIUS
	}


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"total_barrages": _total_barrages,
		"total_bonus_damage": _total_bonus_damage,
		"targets_killed_while_marked": _targets_killed_while_marked,
		"tracked_units": _unit_data.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var unit_data_export: Dictionary = {}
	for unit_id in _unit_data:
		unit_data_export[str(unit_id)] = _unit_data[unit_id].duplicate()

	return {
		"marked_target_id": _marked_target_id,
		"barrage_remaining": _barrage_remaining,
		"cooldown_remaining": _cooldown_remaining,
		"unit_data": unit_data_export,
		"total_barrages": _total_barrages,
		"total_bonus_damage": _total_bonus_damage,
		"targets_killed_while_marked": _targets_killed_while_marked
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_marked_target_id = data.get("marked_target_id", -1)
	_barrage_remaining = data.get("barrage_remaining", 0.0)
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)
	_total_barrages = data.get("total_barrages", 0)
	_total_bonus_damage = data.get("total_bonus_damage", 0.0)
	_targets_killed_while_marked = data.get("targets_killed_while_marked", 0)

	_unit_data.clear()
	for unit_id_str in data.get("unit_data", {}):
		_unit_data[int(unit_id_str)] = data["unit_data"][unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"tracked_units": _unit_data.size(),
		"barrage_active": "Yes (%.1fs)" % _barrage_remaining if _barrage_remaining > 0 else "No",
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"total_barrages": _total_barrages,
		"targets_killed": _targets_killed_while_marked
	}
