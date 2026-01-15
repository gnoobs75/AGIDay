class_name SiegeFormationAbility
extends RefCounted
## SiegeFormationAbility gives LogiBots units increased range when stationary.
## F hotkey, 40 REE cost, 15s cooldown, lasts until units move.
## Deployed units gain +50% attack range but cannot move.

signal siege_started(unit_ids: Array[int])
signal siege_ended(unit_ids: Array[int])
signal unit_deployed(unit_id: int, range_boost: float)
signal unit_mobilized(unit_id: int)

## Configuration
const ABILITY_ID := "siege_formation"
const HOTKEY := "F"
const REE_COST := 40.0
const COOLDOWN := 15.0
const RANGE_BOOST := 0.50  ## +50% attack range while deployed
const DEPLOY_TIME := 1.0  ## Time to deploy/undeploy
const MOVE_THRESHOLD := 0.5  ## Movement distance that cancels siege
const MAX_DEPLOYED_UNITS := 30

## Deployed units (unit_id -> deploy_data)
var _deployed_units: Dictionary = {}

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## Stats tracking
var _total_deployments: int = 0
var _total_shots_while_deployed: int = 0

## Callbacks
var _get_faction_units: Callable  ## (faction_id) -> Array[int]
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _set_unit_can_move: Callable  ## (unit_id, can_move: bool) -> void
var _set_unit_deployed_visual: Callable  ## (unit_id, deployed: bool) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_faction_units(callback: Callable) -> void:
	_get_faction_units = callback


func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_unit_can_move(callback: Callable) -> void:
	_set_unit_can_move = callback


func set_unit_deployed_visual(callback: Callable) -> void:
	_set_unit_deployed_visual = callback


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


## Activate siege formation for all LogiBots units.
func activate(faction_id: String) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	# Get all faction units
	var unit_ids: Array[int] = []
	if _get_faction_units.is_valid():
		var result: Array = _get_faction_units.call(faction_id)
		for u in result:
			if unit_ids.size() < MAX_DEPLOYED_UNITS:
				unit_ids.append(u)

	if unit_ids.is_empty():
		return false

	# Deploy all units
	for unit_id in unit_ids:
		_deploy_unit(unit_id)

	# Start cooldown
	_cooldown_remaining = COOLDOWN
	_total_deployments += 1

	siege_started.emit(unit_ids)

	return true


## Toggle siege mode - if any are deployed, undeploy all; otherwise deploy all.
func toggle(faction_id: String) -> bool:
	# Check if any units are deployed
	if _deployed_units.size() > 0:
		# Undeploy all
		var unit_ids: Array[int] = []
		for unit_id in _deployed_units:
			unit_ids.append(unit_id)
		for unit_id in unit_ids:
			_mobilize_unit(unit_id)
		return true
	else:
		# Deploy
		return activate(faction_id)


## Activate siege for specific units.
func activate_for_units(unit_ids: Array[int]) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	if unit_ids.is_empty():
		return false

	# Deploy specified units
	for unit_id in unit_ids:
		if _deployed_units.size() < MAX_DEPLOYED_UNITS:
			_deploy_unit(unit_id)

	# Start cooldown
	_cooldown_remaining = COOLDOWN
	_total_deployments += 1

	siege_started.emit(unit_ids)

	return true


## Deploy a unit into siege mode.
func _deploy_unit(unit_id: int) -> void:
	if _deployed_units.has(unit_id):
		return

	# Get current position for tracking movement
	var position := Vector3.ZERO
	if _get_unit_position.is_valid():
		position = _get_unit_position.call(unit_id)

	_deployed_units[unit_id] = {
		"range_boost": RANGE_BOOST,
		"deploy_position": position,
		"deploying": true,
		"deploy_timer": DEPLOY_TIME
	}

	# Lock movement
	if _set_unit_can_move.is_valid():
		_set_unit_can_move.call(unit_id, false)

	# Set visual effect
	if _set_unit_deployed_visual.is_valid():
		_set_unit_deployed_visual.call(unit_id, true)

	unit_deployed.emit(unit_id, RANGE_BOOST)


## Mobilize a unit (exit siege mode).
func _mobilize_unit(unit_id: int) -> void:
	if not _deployed_units.has(unit_id):
		return

	_deployed_units.erase(unit_id)

	# Unlock movement
	if _set_unit_can_move.is_valid():
		_set_unit_can_move.call(unit_id, true)

	# Remove visual effect
	if _set_unit_deployed_visual.is_valid():
		_set_unit_deployed_visual.call(unit_id, false)

	unit_mobilized.emit(unit_id)


## Check if unit is deployed.
func is_deployed(unit_id: int) -> bool:
	return _deployed_units.has(unit_id)


## Check if unit is fully deployed (not in deploy animation).
func is_fully_deployed(unit_id: int) -> bool:
	if not _deployed_units.has(unit_id):
		return false
	return not _deployed_units[unit_id]["deploying"]


## Get range multiplier for unit (1.0 + boost if deployed).
## Call this from attack range calculation.
func get_range_multiplier(unit_id: int) -> float:
	if not _deployed_units.has(unit_id):
		return 1.0
	if _deployed_units[unit_id]["deploying"]:
		return 1.0  # No bonus while deploying
	return 1.0 + _deployed_units[unit_id]["range_boost"]


## Apply siege formation range boost.
## Returns modified range.
func apply_to_range(unit_id: int, base_range: float) -> float:
	if not _deployed_units.has(unit_id):
		return base_range

	if _deployed_units[unit_id]["deploying"]:
		return base_range  # No bonus while deploying

	_total_shots_while_deployed += 1
	return base_range * get_range_multiplier(unit_id)


## Update siege formation.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update deployed units
	var to_mobilize: Array[int] = []

	for unit_id in _deployed_units:
		var data: Dictionary = _deployed_units[unit_id]

		# Update deploy timer
		if data["deploying"]:
			data["deploy_timer"] -= delta
			if data["deploy_timer"] <= 0:
				data["deploying"] = false

		# Check for forced movement (unit was moved externally)
		if _get_unit_position.is_valid():
			var current_pos: Vector3 = _get_unit_position.call(unit_id)
			var deploy_pos: Vector3 = data["deploy_position"]
			var dist := current_pos.distance_to(deploy_pos)
			if dist > MOVE_THRESHOLD:
				to_mobilize.append(unit_id)

	# Mobilize units that moved
	for unit_id in to_mobilize:
		_mobilize_unit(unit_id)

	if not to_mobilize.is_empty():
		siege_ended.emit(to_mobilize)


## Cancel all siege formations.
func cancel_all(reason: String = "manual") -> void:
	var unit_ids: Array[int] = []
	for unit_id in _deployed_units:
		unit_ids.append(unit_id)

	for unit_id in unit_ids:
		_mobilize_unit(unit_id)


## Get deployed unit count.
func get_deployed_count() -> int:
	return _deployed_units.size()


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
		"range_boost": RANGE_BOOST,
		"deploy_time": DEPLOY_TIME,
		"max_deployed_units": MAX_DEPLOYED_UNITS
	}


## Create AbilityConfig for registration.
func create_ability_config() -> AbilityConfig:
	var config := AbilityConfig.new()
	config.ability_id = ABILITY_ID
	config.faction_id = "logibots"
	config.display_name = "Siege Formation"
	config.description = "Deploy LogiBots units for +50% attack range (cannot move while deployed)"
	config.hotkey = HOTKEY
	config.ability_type = AbilityConfig.AbilityType.GLOBAL
	config.target_type = AbilityConfig.TargetType.NONE
	config.cooldown = COOLDOWN
	config.resource_cost = {"ree": REE_COST, "power": 0.0}
	config.execution_params = {
		"range_boost": RANGE_BOOST,
		"deploy_time": DEPLOY_TIME
	}
	config.feedback = {
		"visual_effect": "siege_deploy",
		"sound_effect": "siege_lockdown",
		"ui_notification": "SIEGE MODE! +50% range, cannot move"
	}
	return config


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"total_deployments": _total_deployments,
		"total_shots_while_deployed": _total_shots_while_deployed,
		"avg_shots_per_deployment": float(_total_shots_while_deployed) / maxf(1.0, _total_deployments)
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var deployed_data: Dictionary = {}
	for unit_id in _deployed_units:
		var data: Dictionary = _deployed_units[unit_id]
		deployed_data[str(unit_id)] = {
			"range_boost": data["range_boost"],
			"deploy_position": {
				"x": data["deploy_position"].x,
				"y": data["deploy_position"].y,
				"z": data["deploy_position"].z
			},
			"deploying": data["deploying"],
			"deploy_timer": data["deploy_timer"]
		}

	return {
		"cooldown_remaining": _cooldown_remaining,
		"deployed_units": deployed_data,
		"total_deployments": _total_deployments,
		"total_shots_while_deployed": _total_shots_while_deployed
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)
	_total_deployments = data.get("total_deployments", 0)
	_total_shots_while_deployed = data.get("total_shots_while_deployed", 0)

	_deployed_units.clear()
	for unit_id_str in data.get("deployed_units", {}):
		var unit_data: Dictionary = data["deployed_units"][unit_id_str]
		var pos_data: Dictionary = unit_data.get("deploy_position", {})
		_deployed_units[int(unit_id_str)] = {
			"range_boost": unit_data.get("range_boost", RANGE_BOOST),
			"deploy_position": Vector3(
				pos_data.get("x", 0.0),
				pos_data.get("y", 0.0),
				pos_data.get("z", 0.0)
			),
			"deploying": unit_data.get("deploying", false),
			"deploy_timer": unit_data.get("deploy_timer", 0.0)
		}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var fully_deployed := 0
	for unit_id in _deployed_units:
		if not _deployed_units[unit_id]["deploying"]:
			fully_deployed += 1

	return {
		"deployed_units": _deployed_units.size(),
		"fully_deployed": fully_deployed,
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"total_deployments": _total_deployments
	}
