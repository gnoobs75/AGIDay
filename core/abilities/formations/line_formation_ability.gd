class_name LineFormationAbility
extends RefCounted
## LineFormationAbility implements the Tank Faction's defensive line formation.
## W hotkey, 150 REE cost, 5s cooldown, 15s duration.

signal formation_started(formation_id: int, center: Vector3, unit_count: int)
signal formation_updated(formation_id: int, positions: Dictionary)
signal formation_ended(formation_id: int)
signal formation_cancelled(formation_id: int, reason: String)
signal unit_movement_requested(unit_id: int, target: Vector3, duration: float)

## Configuration
const ABILITY_ID := "line_formation"
const HOTKEY := "W"
const REE_COST := 150.0
const COOLDOWN := 5.0
const DURATION := 15.0
const TWEEN_DURATION := 1.0
const UNIT_SPACING := 3.0
const MAX_LINE_LENGTH := 50.0
const MAX_FORMATIONS := 50

## Active formations (formation_id -> formation_data)
var _formations: Dictionary = {}

## Formation ID counter
var _next_formation_id: int = 0

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## Unit position callback (unit_id) -> Vector3
var _unit_position_callback: Callable

## Units in faction callback (faction_id) -> Array[int]
var _faction_units_callback: Callable


func _init() -> void:
	pass


## Set unit position callback.
func set_unit_position_callback(callback: Callable) -> void:
	_unit_position_callback = callback


## Set faction units callback.
func set_faction_units_callback(callback: Callable) -> void:
	_faction_units_callback = callback


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
		result["reason"] = "Maximum formations reached"
		return result

	return result


## Activate line formation at target position.
func activate(
	target_position: Vector3,
	unit_ids: Array[int],
	facing_direction: Vector3 = Vector3.FORWARD
) -> int:
	var validation := can_activate()
	if not validation["can_activate"]:
		return -1

	if unit_ids.is_empty():
		return -1

	# Create formation
	var formation_id := _next_formation_id
	_next_formation_id += 1

	var formation := LineFormation.new(formation_id)
	formation.spacing = UNIT_SPACING
	formation.max_line_length = MAX_LINE_LENGTH

	# Calculate initial positions
	var positions := formation.calculate_positions(unit_ids, target_position, facing_direction)

	# Store formation data
	_formations[formation_id] = {
		"formation": formation,
		"remaining_duration": DURATION,
		"tween_progress": 0.0,
		"unit_start_positions": _get_unit_positions(unit_ids),
		"is_tweening": true
	}

	# Start cooldown
	_cooldown_remaining = COOLDOWN

	# Request unit movement
	for unit_id in positions:
		var target: Vector3 = positions[unit_id]
		unit_movement_requested.emit(unit_id, target, TWEEN_DURATION)

	formation_started.emit(formation_id, target_position, unit_ids.size())

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
		var formation: LineFormation = data["formation"]

		# Update duration
		data["remaining_duration"] -= delta

		if data["remaining_duration"] <= 0:
			to_remove.append(formation_id)
			continue

		# Update tween progress
		if data["is_tweening"]:
			data["tween_progress"] += delta / TWEEN_DURATION
			if data["tween_progress"] >= 1.0:
				data["tween_progress"] = 1.0
				data["is_tweening"] = false

		# Emit position update
		var positions: Dictionary = {}
		for unit_id in formation._unit_positions:
			positions[unit_id] = formation._unit_positions[unit_id]

		if not positions.is_empty():
			formation_updated.emit(formation_id, positions)

	# Remove ended formations
	for formation_id in to_remove:
		_end_formation(formation_id)


## End formation normally.
func _end_formation(formation_id: int) -> void:
	if _formations.has(formation_id):
		var formation: LineFormation = _formations[formation_id]["formation"]
		formation.deactivate()
		_formations.erase(formation_id)
		formation_ended.emit(formation_id)


## Cancel formation (unit moved, attacked, etc).
func cancel_formation(formation_id: int, reason: String = "manual") -> void:
	if _formations.has(formation_id):
		var formation: LineFormation = _formations[formation_id]["formation"]
		formation.deactivate()
		_formations.erase(formation_id)
		formation_cancelled.emit(formation_id, reason)


## Cancel formation for unit.
func cancel_unit_formation(unit_id: int) -> void:
	for formation_id in _formations:
		var formation: LineFormation = _formations[formation_id]["formation"]
		if formation.has_unit(unit_id):
			formation.remove_unit(unit_id)

			# Cancel formation if too few units remain
			if formation.get_unit_count() < 2:
				cancel_formation(formation_id, "insufficient_units")


## Get unit positions via callback.
func _get_unit_positions(unit_ids: Array[int]) -> Dictionary:
	var positions: Dictionary = {}

	if _unit_position_callback.is_valid():
		for unit_id in unit_ids:
			positions[unit_id] = _unit_position_callback.call(unit_id)

	return positions


## Get formation.
func get_formation(formation_id: int) -> LineFormation:
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


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"hotkey": HOTKEY,
		"ree_cost": REE_COST,
		"cooldown": COOLDOWN,
		"duration": DURATION,
		"tween_duration": TWEEN_DURATION,
		"unit_spacing": UNIT_SPACING,
		"max_line_length": MAX_LINE_LENGTH,
		"max_formations": MAX_FORMATIONS
	}


## Create AbilityConfig for registration.
func create_ability_config() -> AbilityConfig:
	var config := AbilityConfig.new()
	config.ability_id = ABILITY_ID
	config.faction_id = "glacius"  ## Tank faction
	config.display_name = "Line Formation"
	config.description = "Arrange units in defensive lines for coordinated assault"
	config.hotkey = HOTKEY
	config.ability_type = AbilityConfig.AbilityType.FORMATION
	config.target_type = AbilityConfig.TargetType.POSITION
	config.cooldown = COOLDOWN
	config.resource_cost = {"ree": REE_COST, "power": 0.0}
	config.execution_params = {
		"duration": DURATION,
		"spacing": UNIT_SPACING,
		"max_line_length": MAX_LINE_LENGTH
	}
	config.feedback = {
		"visual_effect": "line_formation",
		"sound_effect": "formation_activate",
		"ui_notification": "Line Formation activated!"
	}
	return config


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var formations_data: Dictionary = {}
	for formation_id in _formations:
		var data: Dictionary = _formations[formation_id]
		formations_data[str(formation_id)] = {
			"formation": data["formation"].to_dict(),
			"remaining_duration": data["remaining_duration"],
			"tween_progress": data["tween_progress"],
			"is_tweening": data["is_tweening"]
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
		_formations[int(formation_id_str)] = {
			"formation": LineFormation.from_dict(formation_data["formation"]),
			"remaining_duration": formation_data["remaining_duration"],
			"tween_progress": formation_data["tween_progress"],
			"is_tweening": formation_data.get("is_tweening", false),
			"unit_start_positions": {}
		}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var formation_summaries: Array[Dictionary] = []
	for formation_id in _formations:
		var data: Dictionary = _formations[formation_id]
		var formation: LineFormation = data["formation"]
		formation_summaries.append({
			"id": formation_id,
			"units": formation.get_unit_count(),
			"remaining": "%.1fs" % data["remaining_duration"]
		})

	return {
		"active_formations": _formations.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"formations": formation_summaries
	}
