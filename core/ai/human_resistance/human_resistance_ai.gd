class_name HumanResistanceAI
extends RefCounted
## HumanResistanceAI manages targeting behavior for Human Resistance units.
## Targets nearest robot faction units regardless of which faction they belong to.

signal target_acquired(unit_id: int, target_id: int, target_faction: int)
signal target_lost(unit_id: int, old_target_id: int)
signal attack_initiated(unit_id: int, target_id: int)
signal attack_completed(unit_id: int, target_id: int, damage: float)
signal ambush_attack(unit_id: int, target_id: int, bonus_damage: float)
signal unit_behavior_changed(unit_id: int, old_behavior: int, new_behavior: int)

## AI behavior states
enum Behavior {
	IDLE,
	PATROL,
	SEARCHING,
	ENGAGING,
	RETREATING,
	AMBUSH_WAITING
}

## Targeting configuration
const TARGET_UPDATE_INTERVAL := 0.5     ## Seconds between target updates
const MAX_TARGETS_PER_UPDATE := 20      ## Max targets to evaluate per update
const RETARGET_DISTANCE := 5.0          ## Distance change to force retarget

## AI performance
const AI_BUDGET_MS := 2.0               ## Max ms for AI updates per frame
const BATCH_SIZE := 50                  ## Units to update per batch

## References
var _faction: HumanResistanceAIFaction = null

## Unit AI states
var _unit_states: Dictionary = {}       ## unit_id -> AIState
var _update_queue: Array[int] = []
var _update_index := 0
var _update_timer := 0.0


func _init() -> void:
	pass


## Set faction reference.
func set_faction(faction: HumanResistanceAIFaction) -> void:
	_faction = faction


## Register unit for AI control.
func register_unit(unit_id: int, unit_type: String, position: Vector3) -> void:
	var state := AIState.new()
	state.unit_id = unit_id
	state.unit_type = unit_type
	state.position = position
	state.current_behavior = Behavior.PATROL
	state.target_id = -1
	state.target_update_timer = 0.0

	_unit_states[unit_id] = state
	_update_queue.append(unit_id)


## Unregister unit from AI control.
func unregister_unit(unit_id: int) -> void:
	_unit_states.erase(unit_id)
	var idx := _update_queue.find(unit_id)
	if idx >= 0:
		_update_queue.remove_at(idx)


## Update AI for all units.
func update(delta: float, robot_unit_positions: Dictionary) -> void:
	_update_timer += delta

	if _update_timer < TARGET_UPDATE_INTERVAL:
		return

	_update_timer = 0.0

	var start_time := Time.get_ticks_usec()
	var units_updated := 0

	# Process units in batches
	while units_updated < BATCH_SIZE and _update_index < _update_queue.size():
		var elapsed_ms := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed_ms > AI_BUDGET_MS:
			break

		var unit_id: int = _update_queue[_update_index]
		_update_index += 1

		if _unit_states.has(unit_id):
			_update_unit_ai(unit_id, robot_unit_positions)
			units_updated += 1

	# Reset queue if completed
	if _update_index >= _update_queue.size():
		_update_index = 0


## Update AI for single unit.
func _update_unit_ai(unit_id: int, robot_unit_positions: Dictionary) -> void:
	var state: AIState = _unit_states[unit_id]

	# Find nearest target
	var best_target := _find_nearest_target(state.position, robot_unit_positions)

	if best_target.target_id >= 0:
		var old_target := state.target_id
		if old_target != best_target.target_id:
			if old_target >= 0:
				target_lost.emit(unit_id, old_target)

			state.target_id = best_target.target_id
			state.target_position = best_target.position
			state.target_faction = best_target.faction_id
			state.target_distance = best_target.distance

			target_acquired.emit(unit_id, best_target.target_id, best_target.faction_id)
			_set_behavior(unit_id, Behavior.ENGAGING)
		else:
			# Update distance to existing target
			state.target_position = best_target.position
			state.target_distance = best_target.distance
	else:
		# No valid target
		if state.target_id >= 0:
			target_lost.emit(unit_id, state.target_id)
			state.target_id = -1

		if state.current_behavior == Behavior.ENGAGING:
			_set_behavior(unit_id, Behavior.SEARCHING)


## Find nearest valid target from robot factions.
func _find_nearest_target(from_position: Vector3, robot_positions: Dictionary) -> TargetResult:
	var result := TargetResult.new()
	result.target_id = -1
	result.distance = INF

	var targets_checked := 0

	for unit_id in robot_positions:
		if targets_checked >= MAX_TARGETS_PER_UPDATE:
			break

		targets_checked += 1
		var data: Dictionary = robot_positions[unit_id]
		var pos: Vector3 = data.get("position", Vector3.ZERO)
		var faction_id: int = data.get("faction_id", 0)

		# Only target robot factions
		if faction_id == HumanResistanceAIFaction.FACTION_ID:
			continue

		var distance := from_position.distance_to(pos)
		if distance < result.distance:
			result.target_id = unit_id
			result.position = pos
			result.faction_id = faction_id
			result.distance = distance

	return result


## Set unit behavior.
func _set_behavior(unit_id: int, new_behavior: Behavior) -> void:
	if not _unit_states.has(unit_id):
		return

	var state: AIState = _unit_states[unit_id]
	var old_behavior := state.current_behavior

	if old_behavior != new_behavior:
		state.current_behavior = new_behavior
		unit_behavior_changed.emit(unit_id, old_behavior, new_behavior)


## Execute attack for unit.
func execute_attack(unit_id: int, base_damage: float) -> Dictionary:
	if not _unit_states.has(unit_id):
		return {"success": false}

	var state: AIState = _unit_states[unit_id]
	if state.target_id < 0:
		return {"success": false}

	var damage := base_damage

	# Apply threat multiplier from faction
	if _faction != null:
		damage *= _faction.get_unit_threat_multiplier(unit_id)

		# Check for ambush bonus
		if _faction.is_in_ambush(unit_id):
			var bonus: float = damage * _faction.get_ambush_damage_bonus(unit_id)
			damage += bonus
			_faction.complete_ambush(unit_id)
			ambush_attack.emit(unit_id, state.target_id, bonus)

	attack_initiated.emit(unit_id, state.target_id)
	attack_completed.emit(unit_id, state.target_id, damage)

	return {
		"success": true,
		"target_id": state.target_id,
		"damage": damage,
		"target_position": state.target_position
	}


## Update unit position.
func update_unit_position(unit_id: int, position: Vector3) -> void:
	if _unit_states.has(unit_id):
		_unit_states[unit_id].position = position


## Get unit target.
func get_unit_target(unit_id: int) -> int:
	if _unit_states.has(unit_id):
		return _unit_states[unit_id].target_id
	return -1


## Get unit behavior.
func get_unit_behavior(unit_id: int) -> Behavior:
	if _unit_states.has(unit_id):
		return _unit_states[unit_id].current_behavior
	return Behavior.IDLE


## Get target position for unit.
func get_target_position(unit_id: int) -> Vector3:
	if _unit_states.has(unit_id):
		return _unit_states[unit_id].target_position
	return Vector3.ZERO


## Get distance to target.
func get_target_distance(unit_id: int) -> float:
	if _unit_states.has(unit_id):
		return _unit_states[unit_id].target_distance
	return INF


## Check if unit has valid target.
func has_target(unit_id: int) -> bool:
	if _unit_states.has(unit_id):
		return _unit_states[unit_id].target_id >= 0
	return false


## Set unit to ambush behavior.
func set_ambush_mode(unit_id: int, position: Vector3) -> bool:
	if not _unit_states.has(unit_id):
		return false

	if _faction != null and not _faction.can_use_ambush(unit_id):
		return false

	var state: AIState = _unit_states[unit_id]
	state.position = position
	_set_behavior(unit_id, Behavior.AMBUSH_WAITING)

	if _faction != null:
		_faction.activate_ambush(unit_id, position)

	return true


## Get behavior name.
static func get_behavior_name(behavior: Behavior) -> String:
	match behavior:
		Behavior.IDLE: return "Idle"
		Behavior.PATROL: return "Patrol"
		Behavior.SEARCHING: return "Searching"
		Behavior.ENGAGING: return "Engaging"
		Behavior.RETREATING: return "Retreating"
		Behavior.AMBUSH_WAITING: return "Ambush"
	return "Unknown"


## Get controlled unit count.
func get_unit_count() -> int:
	return _unit_states.size()


## Get statistics.
func get_statistics() -> Dictionary:
	var behavior_counts := {}
	for behavior in Behavior.values():
		behavior_counts[get_behavior_name(behavior)] = 0

	var units_with_targets := 0

	for unit_id in _unit_states:
		var state: AIState = _unit_states[unit_id]
		var behavior_name := get_behavior_name(state.current_behavior)
		behavior_counts[behavior_name] += 1
		if state.target_id >= 0:
			units_with_targets += 1

	return {
		"controlled_units": _unit_states.size(),
		"units_with_targets": units_with_targets,
		"behavior_distribution": behavior_counts,
		"update_queue_size": _update_queue.size(),
		"update_index": _update_index
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var states := {}
	for unit_id in _unit_states:
		var state: AIState = _unit_states[unit_id]
		states[str(unit_id)] = state.to_dict()

	return {
		"unit_states": states,
		"update_queue": _update_queue.duplicate(),
		"update_index": _update_index,
		"update_timer": _update_timer
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_states.clear()
	_update_queue.clear()

	var states: Dictionary = data.get("unit_states", {})
	for key in states:
		var state := AIState.new()
		state.from_dict(states[key])
		_unit_states[int(key)] = state

	var queue: Array = data.get("update_queue", [])
	for unit_id in queue:
		_update_queue.append(unit_id)

	_update_index = data.get("update_index", 0)
	_update_timer = data.get("update_timer", 0.0)


## AIState inner class.
class AIState:
	var unit_id: int = -1
	var unit_type: String = "soldier"
	var position: Vector3 = Vector3.ZERO
	var current_behavior: Behavior = Behavior.IDLE
	var target_id: int = -1
	var target_position: Vector3 = Vector3.ZERO
	var target_faction: int = -1
	var target_distance: float = INF
	var target_update_timer: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"unit_id": unit_id,
			"unit_type": unit_type,
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"current_behavior": current_behavior,
			"target_id": target_id,
			"target_position": {"x": target_position.x, "y": target_position.y, "z": target_position.z},
			"target_faction": target_faction,
			"target_distance": target_distance,
			"target_update_timer": target_update_timer
		}

	func from_dict(data: Dictionary) -> void:
		unit_id = data.get("unit_id", -1)
		unit_type = data.get("unit_type", "soldier")
		var pos: Dictionary = data.get("position", {})
		position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		current_behavior = data.get("current_behavior", Behavior.IDLE)
		target_id = data.get("target_id", -1)
		var target_pos: Dictionary = data.get("target_position", {})
		target_position = Vector3(target_pos.get("x", 0), target_pos.get("y", 0), target_pos.get("z", 0))
		target_faction = data.get("target_faction", -1)
		target_distance = data.get("target_distance", INF)
		target_update_timer = data.get("target_update_timer", 0.0)


## TargetResult helper class.
class TargetResult:
	var target_id: int = -1
	var position: Vector3 = Vector3.ZERO
	var faction_id: int = -1
	var distance: float = INF
