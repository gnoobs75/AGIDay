class_name CombatBehavior
extends RefCounted
## CombatBehavior handles targeting, attacking, and combat tactics.

signal attack_requested(unit_id: int, target_id: int, ability: String)
signal target_acquired(unit_id: int, target_id: int)
signal target_lost(unit_id: int, old_target: int)

## Combat states
enum CombatState {
	IDLE,
	ENGAGING,
	ATTACKING,
	COOLDOWN
}

## Configuration
const DEFAULT_ATTACK_RANGE := 10.0
const ATTACK_COOLDOWN := 1.0

## Unit combat states (unit_id -> state)
var _combat_states: Dictionary = {}

## Callbacks
var _get_unit_position: Callable
var _get_target_position: Callable
var _get_attack_range: Callable
var _is_target_valid: Callable
var _get_attack_ability: Callable


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_target_position(callback: Callable) -> void:
	_get_target_position = callback


func set_get_attack_range(callback: Callable) -> void:
	_get_attack_range = callback


func set_is_target_valid(callback: Callable) -> void:
	_is_target_valid = callback


func set_get_attack_ability(callback: Callable) -> void:
	_get_attack_ability = callback


## Acquire target.
func acquire_target(unit_id: int, target_id: int) -> Dictionary:
	# Validate target
	if _is_target_valid.is_valid():
		if not _is_target_valid.call(target_id):
			return {"action": "none", "reason": "invalid_target"}

	var old_target := -1
	if _combat_states.has(unit_id):
		old_target = _combat_states[unit_id].get("target_id", -1)

	_combat_states[unit_id] = {
		"state": CombatState.ENGAGING,
		"target_id": target_id,
		"cooldown": 0.0
	}

	if old_target != -1 and old_target != target_id:
		target_lost.emit(unit_id, old_target)

	target_acquired.emit(unit_id, target_id)

	return {
		"action": "acquire_target",
		"target_id": target_id
	}


## Execute attack on current target.
func attack(unit_id: int) -> Dictionary:
	if not _combat_states.has(unit_id):
		return {"action": "none", "reason": "no_target"}

	var state: Dictionary = _combat_states[unit_id]

	# Check cooldown
	if state["cooldown"] > 0:
		return {"action": "none", "reason": "cooldown"}

	var target_id: int = state["target_id"]

	# Check range
	if not _is_in_range(unit_id, target_id):
		return {
			"action": "move_to_target",
			"target_id": target_id
		}

	# Get attack ability
	var ability := "basic_attack"
	if _get_attack_ability.is_valid():
		ability = _get_attack_ability.call(unit_id)

	state["state"] = CombatState.ATTACKING
	state["cooldown"] = ATTACK_COOLDOWN

	attack_requested.emit(unit_id, target_id, ability)

	return {
		"action": "attack",
		"target_id": target_id,
		"ability": ability
	}


## Check if target is in attack range.
func _is_in_range(unit_id: int, target_id: int) -> bool:
	if not _get_unit_position.is_valid() or not _get_target_position.is_valid():
		return true  ## Assume in range if can't check

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	var target_pos: Vector3 = _get_target_position.call(target_id)

	var attack_range := DEFAULT_ATTACK_RANGE
	if _get_attack_range.is_valid():
		attack_range = _get_attack_range.call(unit_id)

	return unit_pos.distance_to(target_pos) <= attack_range


## Update cooldowns.
func update(delta: float) -> void:
	for unit_id in _combat_states:
		var state: Dictionary = _combat_states[unit_id]
		if state["cooldown"] > 0:
			state["cooldown"] -= delta
			if state["cooldown"] <= 0:
				state["state"] = CombatState.ENGAGING


## Disengage from combat.
func disengage(unit_id: int) -> Dictionary:
	if _combat_states.has(unit_id):
		var old_target: int = _combat_states[unit_id].get("target_id", -1)
		_combat_states.erase(unit_id)

		if old_target != -1:
			target_lost.emit(unit_id, old_target)

	return {"action": "disengage"}


## Get current target.
func get_target(unit_id: int) -> int:
	if not _combat_states.has(unit_id):
		return -1
	return _combat_states[unit_id].get("target_id", -1)


## Get combat state.
func get_state(unit_id: int) -> int:
	if not _combat_states.has(unit_id):
		return CombatState.IDLE
	return _combat_states[unit_id]["state"]


## Clear unit state.
func clear_unit(unit_id: int) -> void:
	_combat_states.erase(unit_id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var state_counts: Dictionary = {}
	for combat_state in CombatState.values():
		state_counts[CombatState.keys()[combat_state]] = 0

	for unit_id in _combat_states:
		var state_name: String = CombatState.keys()[_combat_states[unit_id]["state"]]
		state_counts[state_name] += 1

	return {
		"active_combatants": _combat_states.size(),
		"state_distribution": state_counts
	}
