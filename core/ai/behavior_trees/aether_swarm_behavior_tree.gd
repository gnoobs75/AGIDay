class_name AetherSwarmBehaviorTree
extends RefCounted
## AetherSwarmBehaviorTree implements swarm tactics with coordinated group attacks.

## Behavior tree status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Configuration
const SWARM_JOIN_RADIUS := 15.0
const MIN_SWARM_SIZE := 3
const ATTACK_COORDINATION_DELAY := 0.2

## Root node (cached)
var _root: BehaviorTreeNode = null

## Callbacks
var _get_unit_position: Callable
var _get_nearby_allies: Callable  ## (position, radius, faction) -> Array[int]
var _get_ally_target: Callable  ## (unit_id) -> int
var _set_attack_target: Callable  ## (unit_id, target_id) -> void
var _request_movement: Callable  ## (unit_id, position) -> void
var _get_enemies_in_range: Callable  ## (position, range, faction) -> Array[int]
var _get_unit_health_percent: Callable  ## (unit_id) -> float


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


## Build the behavior tree structure.
func _build_behavior_tree() -> void:
	_root = BehaviorTreeNode.Selector.new("swarm_root")

	# Priority 1: Flee when low health
	var flee_sequence := BehaviorTreeNode.Sequence.new("flee_sequence")
	flee_sequence.add_child(BehaviorTreeNode.Condition.new("is_low_health", _check_low_health))
	flee_sequence.add_child(BehaviorTreeNode.Action.new("flee_to_allies", _action_flee_to_allies))
	_root.add_child(flee_sequence)

	# Priority 2: Join nearby swarm attack
	var join_swarm := BehaviorTreeNode.Sequence.new("join_swarm_sequence")
	join_swarm.add_child(BehaviorTreeNode.Condition.new("allies_attacking", _check_allies_attacking_same_target))
	join_swarm.add_child(BehaviorTreeNode.Action.new("join_attack", _action_join_swarm_attack))
	_root.add_child(join_swarm)

	# Priority 3: Initiate swarm attack
	var initiate_swarm := BehaviorTreeNode.Sequence.new("initiate_swarm_sequence")
	initiate_swarm.add_child(BehaviorTreeNode.Condition.new("has_swarm", _check_has_swarm_nearby))
	initiate_swarm.add_child(BehaviorTreeNode.Condition.new("has_enemy", _check_has_enemy_in_range))
	initiate_swarm.add_child(BehaviorTreeNode.Action.new("initiate_attack", _action_initiate_swarm_attack))
	_root.add_child(initiate_swarm)

	# Priority 4: Move to join swarm
	var seek_swarm := BehaviorTreeNode.Sequence.new("seek_swarm_sequence")
	seek_swarm.add_child(BehaviorTreeNode.Inverter.new("not_in_swarm"))
	seek_swarm.children[0].add_child(BehaviorTreeNode.Condition.new("has_swarm", _check_has_swarm_nearby))
	seek_swarm.add_child(BehaviorTreeNode.Action.new("move_to_swarm", _action_move_to_swarm))
	_root.add_child(seek_swarm)

	# Priority 5: Idle patrol
	var idle := BehaviorTreeNode.Action.new("idle_patrol", _action_idle_patrol)
	_root.add_child(idle)


## Execute behavior tree for unit.
func execute(unit_id: int) -> int:
	var context := {
		"unit_id": unit_id,
		"faction_id": "aether_swarm"
	}

	return _root.execute(context)


## Condition: Check if unit is low health.
func _check_low_health(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if _get_unit_health_percent.is_valid():
		var health: float = _get_unit_health_percent.call(unit_id)
		return health < 0.3  ## Below 30%

	return false


## Condition: Check if nearby allies attacking same target.
func _check_allies_attacking_same_target(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_nearby_allies.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var allies: Array = _get_nearby_allies.call(pos, SWARM_JOIN_RADIUS, "aether_swarm")

	if allies.size() < MIN_SWARM_SIZE:
		return false

	# Find common target
	var target_counts: Dictionary = {}

	for ally_id in allies:
		if ally_id == unit_id:
			continue

		if _get_ally_target.is_valid():
			var target: int = _get_ally_target.call(ally_id)
			if target != -1:
				target_counts[target] = target_counts.get(target, 0) + 1

	# Check if any target has enough attackers
	for target_id in target_counts:
		if target_counts[target_id] >= MIN_SWARM_SIZE - 1:
			context["swarm_target"] = target_id
			return true

	return false


## Condition: Check if swarm nearby.
func _check_has_swarm_nearby(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_nearby_allies.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var allies: Array = _get_nearby_allies.call(pos, SWARM_JOIN_RADIUS, "aether_swarm")

	return allies.size() >= MIN_SWARM_SIZE


## Condition: Check if enemy in range.
func _check_has_enemy_in_range(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 20.0, "aether_swarm")

	if not enemies.is_empty():
		context["nearest_enemy"] = enemies[0]
		return true

	return false


## Action: Flee to allies.
func _action_flee_to_allies(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_nearby_allies.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var allies: Array = _get_nearby_allies.call(pos, 50.0, "aether_swarm")

	if allies.is_empty():
		return Status.FAILURE

	# Calculate center of allies
	var center := Vector3.ZERO
	var count := 0

	for ally_id in allies:
		if ally_id == unit_id:
			continue
		var ally_pos: Vector3 = _get_unit_position.call(ally_id)
		if ally_pos != Vector3.INF:
			center += ally_pos
			count += 1

	if count == 0:
		return Status.FAILURE

	center /= float(count)

	if _request_movement.is_valid():
		_request_movement.call(unit_id, center)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Join swarm attack.
func _action_join_swarm_attack(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var target_id: int = context.get("swarm_target", -1)

	if target_id == -1:
		return Status.FAILURE

	if _set_attack_target.is_valid():
		_set_attack_target.call(unit_id, target_id)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Initiate swarm attack.
func _action_initiate_swarm_attack(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var enemy_id: int = context.get("nearest_enemy", -1)

	if enemy_id == -1:
		return Status.FAILURE

	if _set_attack_target.is_valid():
		_set_attack_target.call(unit_id, enemy_id)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Move to join swarm.
func _action_move_to_swarm(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_nearby_allies.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var allies: Array = _get_nearby_allies.call(pos, 100.0, "aether_swarm")

	if allies.is_empty():
		return Status.FAILURE

	# Find nearest ally
	var nearest_pos := Vector3.INF
	var nearest_dist := INF

	for ally_id in allies:
		if ally_id == unit_id:
			continue
		var ally_pos: Vector3 = _get_unit_position.call(ally_id)
		var dist := pos.distance_to(ally_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = ally_pos

	if nearest_pos == Vector3.INF:
		return Status.FAILURE

	if _request_movement.is_valid():
		_request_movement.call(unit_id, nearest_pos)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Idle patrol.
func _action_idle_patrol(context: Dictionary) -> int:
	# Idle behavior - success to complete tree
	return Status.SUCCESS


## Get tree name.
func get_name() -> String:
	return "AetherSwarmBehaviorTree"
