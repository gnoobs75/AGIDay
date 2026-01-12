class_name ChargeFormationAbility
extends RefCounted
## ChargeFormationAbility implements the Ferron Horde's aggressive charge formation.
## Q hotkey, 100 REE cost, 8s cooldown, charges to target position.

signal charge_started(formation_id: int, origin: Vector3, target: Vector3, unit_count: int)
signal charge_updated(formation_id: int, positions: Dictionary, progress: float)
signal charge_completed(formation_id: int)
signal charge_cancelled(formation_id: int, reason: String)
signal unit_movement_requested(unit_id: int, target: Vector3, speed: float)

## Configuration
const ABILITY_ID := "charge_formation"
const HOTKEY := "Q"
const REE_COST := 100.0
const COOLDOWN := 8.0
const CHARGE_SPEED := 15.0  ## Units per second
const IMPACT_DAMAGE_BONUS := 1.5  ## 50% damage bonus on impact
const MAX_CHARGE_DISTANCE := 100.0
const MAX_FORMATIONS := 20

## Active formations (formation_id -> formation_data)
var _formations: Dictionary = {}

## Formation ID counter
var _next_formation_id: int = 0

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## Unit position callback (unit_id) -> Vector3
var _unit_position_callback: Callable

## Calculate center callback (unit_ids) -> Vector3
var _calculate_center_callback: Callable


func _init() -> void:
	pass


## Set unit position callback.
func set_unit_position_callback(callback: Callable) -> void:
	_unit_position_callback = callback


## Set calculate center callback.
func set_calculate_center_callback(callback: Callable) -> void:
	_calculate_center_callback = callback


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
		result["reason"] = "Maximum charges active"
		return result

	return result


## Activate charge formation toward target position.
func activate(
	target_position: Vector3,
	unit_ids: Array[int]
) -> int:
	var validation := can_activate()
	if not validation["can_activate"]:
		return -1

	if unit_ids.is_empty():
		return -1

	# Calculate formation origin (center of units)
	var origin := _calculate_formation_center(unit_ids)

	# Validate charge distance
	var distance := origin.distance_to(target_position)
	if distance > MAX_CHARGE_DISTANCE:
		# Clamp to max distance
		var direction := (target_position - origin).normalized()
		target_position = origin + direction * MAX_CHARGE_DISTANCE

	# Create formation
	var formation_id := _next_formation_id
	_next_formation_id += 1

	var formation := ChargeFormation.new(formation_id)
	formation.spacing = 2.5

	# Calculate initial positions
	var positions := formation.calculate_positions(unit_ids, target_position, origin)

	# Store formation data
	_formations[formation_id] = {
		"formation": formation,
		"target": target_position,
		"is_charging": true
	}

	# Start cooldown
	_cooldown_remaining = COOLDOWN

	# Request unit movement
	for unit_id in positions:
		var target: Vector3 = positions[unit_id]
		unit_movement_requested.emit(unit_id, target, CHARGE_SPEED)

	charge_started.emit(formation_id, origin, target_position, unit_ids.size())

	return formation_id


## Update all formations.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update formations
	var to_remove: Array[int] = []

	for formation_id in _formations:
		var data: Dictionary = _formations[formation_id]
		var formation: ChargeFormation = data["formation"]

		if not formation.is_active:
			to_remove.append(formation_id)
			continue

		# Update charge positions
		var positions := formation.update_charge(delta, CHARGE_SPEED)
		var progress := formation.get_charge_progress()

		# Emit position update
		if not positions.is_empty():
			charge_updated.emit(formation_id, positions, progress)

		# Request updated unit movement
		for unit_id in positions:
			var target: Vector3 = positions[unit_id]
			unit_movement_requested.emit(unit_id, target, CHARGE_SPEED)

		# Check if charge completed
		if progress >= 1.0 or not formation.is_active:
			to_remove.append(formation_id)

	# Remove completed formations
	for formation_id in to_remove:
		_complete_charge(formation_id)


## Complete charge normally.
func _complete_charge(formation_id: int) -> void:
	if _formations.has(formation_id):
		var formation: ChargeFormation = _formations[formation_id]["formation"]
		formation.deactivate()
		_formations.erase(formation_id)
		charge_completed.emit(formation_id)


## Cancel charge.
func cancel_formation(formation_id: int, reason: String = "manual") -> void:
	if _formations.has(formation_id):
		var formation: ChargeFormation = _formations[formation_id]["formation"]
		formation.deactivate()
		_formations.erase(formation_id)
		charge_cancelled.emit(formation_id, reason)


## Cancel charge for unit.
func cancel_unit_charge(unit_id: int) -> void:
	for formation_id in _formations:
		var formation: ChargeFormation = _formations[formation_id]["formation"]
		if formation.has_unit(unit_id):
			formation.remove_unit(unit_id)

			# Cancel formation if too few units remain
			if formation.get_unit_count() < 2:
				cancel_formation(formation_id, "insufficient_units")


## Calculate formation center from unit positions.
func _calculate_formation_center(unit_ids: Array[int]) -> Vector3:
	if _calculate_center_callback.is_valid():
		return _calculate_center_callback.call(unit_ids)

	if not _unit_position_callback.is_valid():
		return Vector3.ZERO

	var sum := Vector3.ZERO
	var count := 0

	for unit_id in unit_ids:
		var pos: Vector3 = _unit_position_callback.call(unit_id)
		if pos != Vector3.INF:
			sum += pos
			count += 1

	if count == 0:
		return Vector3.ZERO

	return sum / float(count)


## Get formation.
func get_formation(formation_id: int) -> ChargeFormation:
	var data: Dictionary = _formations.get(formation_id, {})
	return data.get("formation")


## Get active formation count.
func get_active_formation_count() -> int:
	return _formations.size()


## Get remaining cooldown.
func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_remaining)


## Is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0


## Get impact damage bonus.
func get_impact_damage_bonus() -> float:
	return IMPACT_DAMAGE_BONUS


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"hotkey": HOTKEY,
		"ree_cost": REE_COST,
		"cooldown": COOLDOWN,
		"charge_speed": CHARGE_SPEED,
		"impact_damage_bonus": IMPACT_DAMAGE_BONUS,
		"max_charge_distance": MAX_CHARGE_DISTANCE,
		"max_formations": MAX_FORMATIONS
	}


## Create AbilityConfig for registration.
func create_ability_config() -> AbilityConfig:
	var config := AbilityConfig.new()
	config.ability_id = ABILITY_ID
	config.faction_id = "ferron_horde"  ## Aggressive faction
	config.display_name = "Charge Formation"
	config.description = "Units form wedge and charge toward target with damage bonus"
	config.hotkey = HOTKEY
	config.ability_type = AbilityConfig.AbilityType.FORMATION
	config.target_type = AbilityConfig.TargetType.POSITION
	config.cooldown = COOLDOWN
	config.resource_cost = {"ree": REE_COST, "power": 0.0}
	config.execution_params = {
		"charge_speed": CHARGE_SPEED,
		"impact_damage_bonus": IMPACT_DAMAGE_BONUS,
		"max_charge_distance": MAX_CHARGE_DISTANCE
	}
	config.feedback = {
		"visual_effect": "charge_formation",
		"sound_effect": "charge_horn",
		"ui_notification": "Charge!"
	}
	return config


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var formations_data: Dictionary = {}
	for formation_id in _formations:
		var data: Dictionary = _formations[formation_id]
		var target: Vector3 = data["target"]
		formations_data[str(formation_id)] = {
			"formation": data["formation"].to_dict(),
			"target": {"x": target.x, "y": target.y, "z": target.z},
			"is_charging": data["is_charging"]
		}

	return {
		"next_formation_id": _next_formation_id,
		"cooldown_remaining": _cooldown_remaining,
		"formations": formations_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_next_formation_id = data.get("next_formation_id", 0)
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)

	_formations.clear()
	for formation_id_str in data.get("formations", {}):
		var formation_data: Dictionary = data["formations"][formation_id_str]
		var target_data: Dictionary = formation_data.get("target", {})
		_formations[int(formation_id_str)] = {
			"formation": ChargeFormation.from_dict(formation_data["formation"]),
			"target": Vector3(
				target_data.get("x", 0),
				target_data.get("y", 0),
				target_data.get("z", 0)
			),
			"is_charging": formation_data.get("is_charging", false)
		}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var formation_summaries: Array[Dictionary] = []
	for formation_id in _formations:
		var data: Dictionary = _formations[formation_id]
		var formation: ChargeFormation = data["formation"]
		formation_summaries.append({
			"id": formation_id,
			"units": formation.get_unit_count(),
			"progress": "%.0f%%" % (formation.get_charge_progress() * 100)
		})

	return {
		"active_charges": _formations.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"formations": formation_summaries
	}
