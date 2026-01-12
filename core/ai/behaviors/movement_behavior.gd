class_name MovementBehavior
extends RefCounted
## MovementBehavior handles unit movement including formation, retreat, and regrouping.

signal movement_requested(unit_id: int, target: Vector3, speed_mult: float)
signal formation_move_requested(unit_id: int, formation_position: Vector3)
signal retreat_started(unit_id: int, safe_position: Vector3)
signal regroup_started(unit_id: int, rally_point: Vector3)

## Movement types
enum MoveType {
	DIRECT,
	FORMATION,
	RETREAT,
	REGROUP,
	PATROL
}

## Configuration
const RETREAT_DISTANCE := 30.0
const REGROUP_RADIUS := 15.0
const ARRIVAL_THRESHOLD := 2.0

## Unit movement states (unit_id -> state)
var _movement_states: Dictionary = {}

## Callbacks
var _get_unit_position: Callable
var _get_nearest_ally_position: Callable
var _get_safe_position: Callable
var _pathfind: Callable  ## (from, to) -> Array[Vector3]


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_nearest_ally_position(callback: Callable) -> void:
	_get_nearest_ally_position = callback


func set_get_safe_position(callback: Callable) -> void:
	_get_safe_position = callback


func set_pathfind(callback: Callable) -> void:
	_pathfind = callback


## Execute movement to target.
func move_to(unit_id: int, target: Vector3, speed_mult: float = 1.0) -> Dictionary:
	_movement_states[unit_id] = {
		"type": MoveType.DIRECT,
		"target": target,
		"speed_mult": speed_mult
	}

	movement_requested.emit(unit_id, target, speed_mult)

	return {
		"action": "move",
		"target": target,
		"speed_mult": speed_mult
	}


## Execute formation movement.
func move_to_formation(unit_id: int, formation_position: Vector3) -> Dictionary:
	_movement_states[unit_id] = {
		"type": MoveType.FORMATION,
		"target": formation_position,
		"speed_mult": 1.0
	}

	formation_move_requested.emit(unit_id, formation_position)

	return {
		"action": "formation_move",
		"target": formation_position,
		"speed_mult": 1.0
	}


## Execute retreat.
func retreat(unit_id: int, threat_direction: Vector3) -> Dictionary:
	if not _get_unit_position.is_valid():
		return {"action": "none"}

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)

	# Calculate retreat direction (opposite of threat)
	var retreat_dir := -threat_direction.normalized()
	if retreat_dir.length_squared() < 0.01:
		retreat_dir = Vector3.BACK

	# Find safe position
	var safe_pos := unit_pos + retreat_dir * RETREAT_DISTANCE

	if _get_safe_position.is_valid():
		safe_pos = _get_safe_position.call(unit_pos, retreat_dir, RETREAT_DISTANCE)

	_movement_states[unit_id] = {
		"type": MoveType.RETREAT,
		"target": safe_pos,
		"speed_mult": 1.5  ## Faster when retreating
	}

	retreat_started.emit(unit_id, safe_pos)

	return {
		"action": "retreat",
		"target": safe_pos,
		"speed_mult": 1.5
	}


## Execute regroup to rally point.
func regroup(unit_id: int, rally_point: Vector3 = Vector3.INF) -> Dictionary:
	var target := rally_point

	# If no rally point, move to nearest ally
	if target == Vector3.INF and _get_nearest_ally_position.is_valid():
		target = _get_nearest_ally_position.call(unit_id)

	if target == Vector3.INF:
		return {"action": "none"}

	_movement_states[unit_id] = {
		"type": MoveType.REGROUP,
		"target": target,
		"speed_mult": 1.2
	}

	regroup_started.emit(unit_id, target)

	return {
		"action": "regroup",
		"target": target,
		"speed_mult": 1.2
	}


## Check if unit arrived at destination.
func has_arrived(unit_id: int) -> bool:
	if not _movement_states.has(unit_id):
		return true

	if not _get_unit_position.is_valid():
		return false

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	var target: Vector3 = _movement_states[unit_id]["target"]

	return unit_pos.distance_to(target) <= ARRIVAL_THRESHOLD


## Get current movement type.
func get_movement_type(unit_id: int) -> int:
	if not _movement_states.has(unit_id):
		return -1
	return _movement_states[unit_id]["type"]


## Stop movement.
func stop(unit_id: int) -> Dictionary:
	_movement_states.erase(unit_id)

	return {"action": "stop"}


## Clear unit state.
func clear_unit(unit_id: int) -> void:
	_movement_states.erase(unit_id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_counts: Dictionary = {}
	for move_type in MoveType.values():
		type_counts[MoveType.keys()[move_type]] = 0

	for unit_id in _movement_states:
		var type_name: String = MoveType.keys()[_movement_states[unit_id]["type"]]
		type_counts[type_name] += 1

	return {
		"active_movements": _movement_states.size(),
		"type_distribution": type_counts
	}
