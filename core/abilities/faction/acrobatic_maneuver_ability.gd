class_name AcrobaticManeuverAbility
extends RefCounted
## AcrobaticManeuverAbility enables coordinated evasive maneuvers for Dynapods faction.
## Q hotkey, 120 REE cost, 4s cooldown, 2s duration.

signal maneuver_started(formation_id: int, unit_count: int)
signal maneuver_updated(formation_id: int, positions: Dictionary)
signal maneuver_ended(formation_id: int)
signal maneuver_cancelled(formation_id: int, reason: String)
signal buff_applied(unit_id: int, dodge_bonus: float, speed_multiplier: float)
signal buff_expired(unit_id: int)

## Configuration
const ABILITY_ID := "acrobatic_maneuver"
const HOTKEY := "Q"
const REE_COST := 120.0
const COOLDOWN := 4.0
const DURATION := 2.0
const DODGE_BONUS := 0.30  ## 30% dodge chance increase
const SPEED_MULTIPLIER := 1.3  ## 1.3x speed
const EVASION_DISTANCE := 5.0
const MAX_FORMATIONS := 30

## Active formations (formation_id -> formation_data)
var _formations: Dictionary = {}

## Formation ID counter
var _next_formation_id: int = 0

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## Unit buffs (unit_id -> buff_data)
var _unit_buffs: Dictionary = {}

## Callbacks
var _get_faction_units: Callable  ## (faction_id) -> Array[int]
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _apply_buff: Callable  ## (unit_id, dodge_bonus, speed_mult) -> void
var _remove_buff: Callable  ## (unit_id) -> void
var _request_movement: Callable  ## (unit_id, direction, distance) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_faction_units(callback: Callable) -> void:
	_get_faction_units = callback


func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_apply_buff(callback: Callable) -> void:
	_apply_buff = callback


func set_remove_buff(callback: Callable) -> void:
	_remove_buff = callback


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback


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

	if _formations.size() >= MAX_FORMATIONS:
		result["can_activate"] = false
		result["reason"] = "Maximum formations active"
		return result

	return result


## Activate acrobatic maneuver.
func activate(faction_id: String, evasion_target: Vector3 = Vector3.INF) -> int:
	var validation := can_activate()
	if not validation["can_activate"]:
		return -1

	# Get all faction units
	var unit_ids: Array[int] = []
	if _get_faction_units.is_valid():
		var result: Array = _get_faction_units.call(faction_id)
		for u in result:
			unit_ids.append(u)

	if unit_ids.is_empty():
		return -1

	# Create formation
	var formation_id := _next_formation_id
	_next_formation_id += 1

	_formations[formation_id] = {
		"faction_id": faction_id,
		"unit_ids": unit_ids.duplicate(),
		"remaining_duration": DURATION,
		"evasion_target": evasion_target
	}

	# Apply buffs and evasive movement to all units
	for unit_id in unit_ids:
		_apply_unit_buff(unit_id)
		_execute_evasive_movement(unit_id, evasion_target)

	# Start cooldown
	_cooldown_remaining = COOLDOWN

	maneuver_started.emit(formation_id, unit_ids.size())

	return formation_id


## Apply buff to unit.
func _apply_unit_buff(unit_id: int) -> void:
	_unit_buffs[unit_id] = {
		"dodge_bonus": DODGE_BONUS,
		"speed_multiplier": SPEED_MULTIPLIER,
		"remaining": DURATION
	}

	if _apply_buff.is_valid():
		_apply_buff.call(unit_id, DODGE_BONUS, SPEED_MULTIPLIER)

	buff_applied.emit(unit_id, DODGE_BONUS, SPEED_MULTIPLIER)


## Remove buff from unit.
func _remove_unit_buff(unit_id: int) -> void:
	if _unit_buffs.has(unit_id):
		_unit_buffs.erase(unit_id)

		if _remove_buff.is_valid():
			_remove_buff.call(unit_id)

		buff_expired.emit(unit_id)


## Execute evasive movement for unit.
func _execute_evasive_movement(unit_id: int, evasion_target: Vector3) -> void:
	if not _get_unit_position.is_valid() or not _request_movement.is_valid():
		return

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	if unit_pos == Vector3.INF:
		return

	var direction: Vector3

	if evasion_target != Vector3.INF:
		# Move away from target
		direction = (unit_pos - evasion_target).normalized()
	else:
		# Random evasive direction
		var angle := randf() * TAU
		direction = Vector3(cos(angle), 0, sin(angle))

	# Add some perpendicular component for acrobatic feel
	var perpendicular := Vector3(-direction.z, 0, direction.x)
	var final_direction := (direction + perpendicular * 0.5).normalized()

	_request_movement.call(unit_id, final_direction, EVASION_DISTANCE)


## Update all formations.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update formations
	var to_remove: Array[int] = []

	for formation_id in _formations:
		var data: Dictionary = _formations[formation_id]

		# Update duration
		data["remaining_duration"] -= delta

		if data["remaining_duration"] <= 0:
			to_remove.append(formation_id)

	# Remove ended formations
	for formation_id in to_remove:
		_end_formation(formation_id)

	# Update unit buffs
	var buffs_to_remove: Array[int] = []

	for unit_id in _unit_buffs:
		var buff_data: Dictionary = _unit_buffs[unit_id]
		buff_data["remaining"] -= delta

		if buff_data["remaining"] <= 0:
			buffs_to_remove.append(unit_id)

	for unit_id in buffs_to_remove:
		_remove_unit_buff(unit_id)


## End formation normally.
func _end_formation(formation_id: int) -> void:
	if _formations.has(formation_id):
		var data: Dictionary = _formations[formation_id]

		# Remove buffs from all units in formation
		for unit_id in data["unit_ids"]:
			_remove_unit_buff(unit_id)

		_formations.erase(formation_id)
		maneuver_ended.emit(formation_id)


## Cancel formation.
func cancel_formation(formation_id: int, reason: String = "manual") -> void:
	if _formations.has(formation_id):
		var data: Dictionary = _formations[formation_id]

		# Remove buffs from all units
		for unit_id in data["unit_ids"]:
			_remove_unit_buff(unit_id)

		_formations.erase(formation_id)
		maneuver_cancelled.emit(formation_id, reason)


## Check if unit has maneuver buff.
func has_buff(unit_id: int) -> bool:
	return _unit_buffs.has(unit_id)


## Get buff data for unit.
func get_buff_data(unit_id: int) -> Dictionary:
	return _unit_buffs.get(unit_id, {})


## Get active formation count.
func get_active_formation_count() -> int:
	return _formations.size()


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
		"duration": DURATION,
		"dodge_bonus": DODGE_BONUS,
		"speed_multiplier": SPEED_MULTIPLIER,
		"evasion_distance": EVASION_DISTANCE,
		"max_formations": MAX_FORMATIONS
	}


## Create AbilityConfig for registration.
func create_ability_config() -> AbilityConfig:
	var config := AbilityConfig.new()
	config.ability_id = ABILITY_ID
	config.faction_id = "dynapods"
	config.display_name = "Acrobatic Maneuver"
	config.description = "All units perform evasive maneuvers with +30% dodge and 1.3x speed"
	config.hotkey = HOTKEY
	config.ability_type = AbilityConfig.AbilityType.GLOBAL
	config.target_type = AbilityConfig.TargetType.NONE
	config.cooldown = COOLDOWN
	config.resource_cost = {"ree": REE_COST, "power": 0.0}
	config.execution_params = {
		"duration": DURATION,
		"dodge_bonus": DODGE_BONUS,
		"speed_multiplier": SPEED_MULTIPLIER,
		"evasion_distance": EVASION_DISTANCE
	}
	config.feedback = {
		"visual_effect": "acrobatic_maneuver",
		"sound_effect": "maneuver_whoosh",
		"ui_notification": "Acrobatic Maneuver!"
	}
	return config


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var formations_data: Dictionary = {}
	for formation_id in _formations:
		var data: Dictionary = _formations[formation_id]
		var target: Vector3 = data["evasion_target"]
		formations_data[str(formation_id)] = {
			"faction_id": data["faction_id"],
			"unit_ids": data["unit_ids"].duplicate(),
			"remaining_duration": data["remaining_duration"],
			"evasion_target": {"x": target.x, "y": target.y, "z": target.z}
		}

	var buffs_data: Dictionary = {}
	for unit_id in _unit_buffs:
		buffs_data[str(unit_id)] = _unit_buffs[unit_id].duplicate()

	return {
		"next_formation_id": _next_formation_id,
		"cooldown_remaining": _cooldown_remaining,
		"formations": formations_data,
		"unit_buffs": buffs_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_next_formation_id = data.get("next_formation_id", 0)
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)

	_formations.clear()
	for formation_id_str in data.get("formations", {}):
		var formation_data: Dictionary = data["formations"][formation_id_str]
		var target_data: Dictionary = formation_data.get("evasion_target", {})

		var unit_ids: Array[int] = []
		for u in formation_data.get("unit_ids", []):
			unit_ids.append(u)

		_formations[int(formation_id_str)] = {
			"faction_id": formation_data["faction_id"],
			"unit_ids": unit_ids,
			"remaining_duration": formation_data["remaining_duration"],
			"evasion_target": Vector3(
				target_data.get("x", 0),
				target_data.get("y", 0),
				target_data.get("z", 0)
			)
		}

	_unit_buffs.clear()
	for unit_id_str in data.get("unit_buffs", {}):
		_unit_buffs[int(unit_id_str)] = data["unit_buffs"][unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"active_formations": _formations.size(),
		"buffed_units": _unit_buffs.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready"
	}
