class_name TankFactionBehaviorTree
extends RefCounted
## TankFactionBehaviorTree implements defensive positioning and area control.

## Behavior tree status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Configuration
const DEFENSIVE_RADIUS := 10.0
const STRATEGIC_POINT_SEARCH_RADIUS := 30.0
const HOLD_POSITION_TIME := 5.0
const MIN_TANKS_FOR_LINE := 3

## Root node (cached)
var _root: BehaviorTreeNode = null

## Callbacks
var _get_unit_position: Callable
var _get_nearby_allies: Callable
var _get_ally_target: Callable
var _set_attack_target: Callable
var _request_movement: Callable
var _get_enemies_in_range: Callable
var _get_unit_health_percent: Callable
var _get_strategic_points: Callable  ## (position, radius) -> Array[Vector3]
var _is_position_held: Callable  ## (unit_id) -> bool


func _init() -> void:
	_build_behavior_tree()


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_nearby_allies(callback: Callable) -> void:
	_get_nearby_allies = callback


func set_get_ally_target(callback: Callable) -> void:
	_get_ally_target = callback


func set_attack_target(callback: Callable) -> void:
	_set_attack_target = callback


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback


func set_get_enemies_in_range(callback: Callable) -> void:
	_get_enemies_in_range = callback


func set_get_unit_health_percent(callback: Callable) -> void:
	_get_unit_health_percent = callback


func set_get_strategic_points(callback: Callable) -> void:
	_get_strategic_points = callback


func set_is_position_held(callback: Callable) -> void:
	_is_position_held = callback


## Build the behavior tree structure.
func _build_behavior_tree() -> void:
	_root = BehaviorTreeNode.Selector.new("tank_root")

	# Priority 1: Hold strategic position under attack
	var hold_sequence := BehaviorTreeNode.Sequence.new("hold_position_sequence")
	hold_sequence.add_child(BehaviorTreeNode.Condition.new("should_hold", _check_should_hold_position))
	hold_sequence.add_child(BehaviorTreeNode.Condition.new("enemies_nearby", _check_has_enemy_in_range))
	hold_sequence.add_child(BehaviorTreeNode.Action.new("defend_position", _action_defend_position))
	_root.add_child(hold_sequence)

	# Priority 2: Form defensive line
	var line_sequence := BehaviorTreeNode.Sequence.new("line_formation_sequence")
	line_sequence.add_child(BehaviorTreeNode.Condition.new("has_tanks", _check_has_tanks_nearby))
	line_sequence.add_child(BehaviorTreeNode.Condition.new("enemies_approaching", _check_enemies_approaching))
	line_sequence.add_child(BehaviorTreeNode.Action.new("form_line", _action_form_defensive_line))
	_root.add_child(line_sequence)

	# Priority 3: Move to strategic position
	var strategic_sequence := BehaviorTreeNode.Sequence.new("strategic_sequence")
	var not_holding := BehaviorTreeNode.Inverter.new("not_holding")
	not_holding.add_child(BehaviorTreeNode.Condition.new("should_hold", _check_should_hold_position))
	strategic_sequence.add_child(not_holding)
	strategic_sequence.add_child(BehaviorTreeNode.Action.new("move_strategic", _action_move_to_strategic_position))
	_root.add_child(strategic_sequence)

	# Priority 4: Engage nearby enemy
	var engage_sequence := BehaviorTreeNode.Sequence.new("engage_sequence")
	engage_sequence.add_child(BehaviorTreeNode.Condition.new("has_enemy", _check_has_enemy_in_range))
	engage_sequence.add_child(BehaviorTreeNode.Action.new("engage", _action_engage_enemy))
	_root.add_child(engage_sequence)

	# Priority 5: Patrol
	var patrol := BehaviorTreeNode.Action.new("patrol", _action_patrol)
	_root.add_child(patrol)


## Execute behavior tree for unit.
func execute(unit_id: int) -> int:
	var context := {
		"unit_id": unit_id,
		"faction_id": "glacius"
	}

	return _root.execute(context)


## Condition: Check if should hold position.
func _check_should_hold_position(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if _is_position_held.is_valid():
		return _is_position_held.call(unit_id)

	# Default: hold if at strategic point
	if not _get_unit_position.is_valid() or not _get_strategic_points.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var points: Array = _get_strategic_points.call(pos, 5.0)

	return not points.is_empty()


## Condition: Check if has tanks nearby.
func _check_has_tanks_nearby(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_nearby_allies.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var allies: Array = _get_nearby_allies.call(pos, DEFENSIVE_RADIUS, "glacius")

	return allies.size() >= MIN_TANKS_FOR_LINE


## Condition: Check if enemies approaching.
func _check_enemies_approaching(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 40.0, "glacius")

	if not enemies.is_empty():
		context["approaching_enemies"] = enemies
		return true

	return false


## Condition: Check if enemy in range.
func _check_has_enemy_in_range(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 25.0, "glacius")

	if not enemies.is_empty():
		context["nearest_enemy"] = enemies[0]
		return true

	return false


## Action: Defend position.
func _action_defend_position(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var enemy_id: int = context.get("nearest_enemy", -1)

	if enemy_id == -1:
		return Status.FAILURE

	# Attack enemy while holding position
	if _set_attack_target.is_valid():
		_set_attack_target.call(unit_id, enemy_id)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Form defensive line.
func _action_form_defensive_line(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_nearby_allies.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var allies: Array = _get_nearby_allies.call(pos, DEFENSIVE_RADIUS, "glacius")

	if allies.size() < MIN_TANKS_FOR_LINE:
		return Status.FAILURE

	# Calculate line position based on enemy direction
	var enemies: Array = context.get("approaching_enemies", [])
	if enemies.is_empty():
		return Status.FAILURE

	# Get enemy center
	var enemy_center := Vector3.ZERO
	for enemy_id in enemies:
		var enemy_pos: Vector3 = _get_unit_position.call(enemy_id)
		if enemy_pos != Vector3.INF:
			enemy_center += enemy_pos

	enemy_center /= float(enemies.size())

	# Calculate defensive position
	var defense_dir := (pos - enemy_center).normalized()
	var target_pos := pos + defense_dir * 2.0

	if _request_movement.is_valid():
		_request_movement.call(unit_id, target_pos)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Move to strategic position.
func _action_move_to_strategic_position(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_strategic_points.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var points: Array = _get_strategic_points.call(pos, STRATEGIC_POINT_SEARCH_RADIUS)

	if points.is_empty():
		return Status.FAILURE

	# Find nearest unoccupied strategic point
	var nearest_point: Vector3 = points[0]
	var nearest_dist := pos.distance_to(nearest_point)

	for point in points:
		var dist := pos.distance_to(point)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_point = point

	if _request_movement.is_valid():
		_request_movement.call(unit_id, nearest_point)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Engage enemy.
func _action_engage_enemy(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var enemy_id: int = context.get("nearest_enemy", -1)

	if enemy_id == -1:
		return Status.FAILURE

	if _set_attack_target.is_valid():
		_set_attack_target.call(unit_id, enemy_id)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Patrol.
func _action_patrol(context: Dictionary) -> int:
	# Default patrol behavior
	return Status.SUCCESS


## Get tree name.
func get_name() -> String:
	return "TankFactionBehaviorTree"
