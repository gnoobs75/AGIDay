class_name PhaseShiftAbility
extends RefCounted
## PhaseShiftAbility enables Aether Swarm units to phase through defenses temporarily.
## E hotkey, 80 REE cost, 8s cooldown, 3s duration.
## Phased units take 90% reduced damage and ignore collision.

signal phase_started(unit_ids: Array[int], duration: float)
signal phase_ended(unit_ids: Array[int])
signal phase_cancelled(reason: String)
signal buff_applied(unit_id: int, damage_reduction: float)
signal buff_expired(unit_id: int)
signal damage_phased(unit_id: int, original_damage: float, reduced_damage: float)

## Configuration
const ABILITY_ID := "phase_shift"
const HOTKEY := "E"
const REE_COST := 80.0
const COOLDOWN := 8.0
const DURATION := 3.0
const DAMAGE_REDUCTION := 0.90  ## 90% damage reduction while phased
const PHASE_VISUAL_ALPHA := 0.3  ## Visual transparency while phased
const MAX_PHASED_UNITS := 100

## Phased units (unit_id -> phase_data)
var _phased_units: Dictionary = {}

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## Total damage phased (for stats)
var _total_damage_phased: float = 0.0
var _total_phase_activations: int = 0

## Callbacks
var _get_faction_units: Callable  ## (faction_id) -> Array[int]
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _set_unit_collision: Callable  ## (unit_id, enabled: bool) -> void
var _set_unit_visual_alpha: Callable  ## (unit_id, alpha: float) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_faction_units(callback: Callable) -> void:
	_get_faction_units = callback


func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_unit_collision(callback: Callable) -> void:
	_set_unit_collision = callback


func set_unit_visual_alpha(callback: Callable) -> void:
	_set_unit_visual_alpha = callback


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


## Activate phase shift for all Aether Swarm units.
func activate(faction_id: String) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	# Get all faction units
	var unit_ids: Array[int] = []
	if _get_faction_units.is_valid():
		var result: Array = _get_faction_units.call(faction_id)
		for u in result:
			if unit_ids.size() < MAX_PHASED_UNITS:
				unit_ids.append(u)

	if unit_ids.is_empty():
		return false

	# Apply phase to all units
	for unit_id in unit_ids:
		_apply_phase(unit_id)

	# Start cooldown
	_cooldown_remaining = COOLDOWN
	_total_phase_activations += 1

	phase_started.emit(unit_ids, DURATION)

	return true


## Activate phase shift for specific units.
func activate_for_units(unit_ids: Array[int]) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	if unit_ids.is_empty():
		return false

	# Apply phase to specified units
	for unit_id in unit_ids:
		if _phased_units.size() < MAX_PHASED_UNITS:
			_apply_phase(unit_id)

	# Start cooldown
	_cooldown_remaining = COOLDOWN
	_total_phase_activations += 1

	phase_started.emit(unit_ids, DURATION)

	return true


## Apply phase effect to a unit.
func _apply_phase(unit_id: int) -> void:
	if _phased_units.has(unit_id):
		# Refresh duration if already phased
		_phased_units[unit_id]["remaining"] = DURATION
		return

	_phased_units[unit_id] = {
		"remaining": DURATION,
		"damage_reduction": DAMAGE_REDUCTION
	}

	# Disable collision
	if _set_unit_collision.is_valid():
		_set_unit_collision.call(unit_id, false)

	# Set visual transparency
	if _set_unit_visual_alpha.is_valid():
		_set_unit_visual_alpha.call(unit_id, PHASE_VISUAL_ALPHA)

	buff_applied.emit(unit_id, DAMAGE_REDUCTION)


## Remove phase effect from a unit.
func _remove_phase(unit_id: int) -> void:
	if not _phased_units.has(unit_id):
		return

	_phased_units.erase(unit_id)

	# Re-enable collision
	if _set_unit_collision.is_valid():
		_set_unit_collision.call(unit_id, true)

	# Restore visual
	if _set_unit_visual_alpha.is_valid():
		_set_unit_visual_alpha.call(unit_id, 1.0)

	buff_expired.emit(unit_id)


## Check if unit is phased.
func is_phased(unit_id: int) -> bool:
	return _phased_units.has(unit_id)


## Get damage reduction for unit (call this from damage system).
func get_damage_reduction(unit_id: int) -> float:
	if not _phased_units.has(unit_id):
		return 0.0
	return _phased_units[unit_id]["damage_reduction"]


## Apply phase damage reduction to incoming damage.
## Returns modified damage amount.
func apply_to_damage(unit_id: int, incoming_damage: float) -> float:
	if not _phased_units.has(unit_id):
		return incoming_damage

	var reduction: float = _phased_units[unit_id]["damage_reduction"]
	var reduced_damage := incoming_damage * (1.0 - reduction)
	var damage_avoided := incoming_damage - reduced_damage

	_total_damage_phased += damage_avoided
	damage_phased.emit(unit_id, incoming_damage, reduced_damage)

	return reduced_damage


## Update phase effects.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update phased units
	var to_remove: Array[int] = []

	for unit_id in _phased_units:
		_phased_units[unit_id]["remaining"] -= delta

		if _phased_units[unit_id]["remaining"] <= 0:
			to_remove.append(unit_id)

	# Remove expired phases
	for unit_id in to_remove:
		_remove_phase(unit_id)

	if not to_remove.is_empty():
		phase_ended.emit(to_remove)


## Cancel all phase effects.
func cancel_all(reason: String = "manual") -> void:
	var unit_ids: Array[int] = []
	for unit_id in _phased_units:
		unit_ids.append(unit_id)

	for unit_id in unit_ids:
		_remove_phase(unit_id)

	if not unit_ids.is_empty():
		phase_cancelled.emit(reason)


## Get phased unit count.
func get_phased_count() -> int:
	return _phased_units.size()


## Get remaining cooldown.
func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_remaining)


## Is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0


## Get remaining phase time for unit.
func get_phase_remaining(unit_id: int) -> float:
	if not _phased_units.has(unit_id):
		return 0.0
	return maxf(0.0, _phased_units[unit_id]["remaining"])


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"hotkey": HOTKEY,
		"ree_cost": REE_COST,
		"cooldown": COOLDOWN,
		"duration": DURATION,
		"damage_reduction": DAMAGE_REDUCTION,
		"phase_visual_alpha": PHASE_VISUAL_ALPHA,
		"max_phased_units": MAX_PHASED_UNITS
	}


## Create AbilityConfig for registration.
func create_ability_config() -> AbilityConfig:
	var config := AbilityConfig.new()
	config.ability_id = ABILITY_ID
	config.faction_id = "aether_swarm"
	config.display_name = "Phase Shift"
	config.description = "All swarm units phase through matter, taking 90% reduced damage for 3s"
	config.hotkey = HOTKEY
	config.ability_type = AbilityConfig.AbilityType.GLOBAL
	config.target_type = AbilityConfig.TargetType.NONE
	config.cooldown = COOLDOWN
	config.resource_cost = {"ree": REE_COST, "power": 0.0}
	config.execution_params = {
		"duration": DURATION,
		"damage_reduction": DAMAGE_REDUCTION
	}
	config.feedback = {
		"visual_effect": "phase_shift",
		"sound_effect": "phase_whoosh",
		"ui_notification": "Phase Shift!"
	}
	return config


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"total_activations": _total_phase_activations,
		"total_damage_phased": _total_damage_phased,
		"avg_damage_per_activation": _total_damage_phased / maxf(1.0, _total_phase_activations)
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var phased_data: Dictionary = {}
	for unit_id in _phased_units:
		phased_data[str(unit_id)] = _phased_units[unit_id].duplicate()

	return {
		"cooldown_remaining": _cooldown_remaining,
		"phased_units": phased_data,
		"total_damage_phased": _total_damage_phased,
		"total_phase_activations": _total_phase_activations
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)
	_total_damage_phased = data.get("total_damage_phased", 0.0)
	_total_phase_activations = data.get("total_phase_activations", 0)

	_phased_units.clear()
	for unit_id_str in data.get("phased_units", {}):
		_phased_units[int(unit_id_str)] = data["phased_units"][unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"phased_units": _phased_units.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"total_activations": _total_phase_activations,
		"total_damage_phased": "%.0f" % _total_damage_phased
	}
