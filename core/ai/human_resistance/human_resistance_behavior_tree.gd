class_name HumanResistanceBehaviorTree
extends RefCounted
## HumanResistanceBehaviorTree implements patrol, combat, and special abilities for Human Resistance.

## Behavior tree status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Root node (cached)
var _root: BehaviorTreeNode = null

## Callbacks
var _get_unit_position: Callable
var _get_unit_type: Callable
var _get_enemies_in_range: Callable
var _get_allies_in_range: Callable
var _set_attack_target: Callable
var _request_movement: Callable
var _get_high_ground: Callable  ## (position, radius) -> Vector3
var _get_cover_position: Callable  ## (position, threat_dir) -> Vector3
var _get_patrol_point: Callable  ## (unit_id) -> Vector3
var _apply_buff: Callable  ## (unit_id, buff_type, value) -> void


func _init() -> void:
	_build_behavior_tree()


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_type(callback: Callable) -> void:
	_get_unit_type = callback


func set_get_enemies_in_range(callback: Callable) -> void:
	_get_enemies_in_range = callback


func set_get_allies_in_range(callback: Callable) -> void:
	_get_allies_in_range = callback


func set_attack_target(callback: Callable) -> void:
	_set_attack_target = callback


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback


func set_get_high_ground(callback: Callable) -> void:
	_get_high_ground = callback


func set_get_cover_position(callback: Callable) -> void:
	_get_cover_position = callback


func set_get_patrol_point(callback: Callable) -> void:
	_get_patrol_point = callback


func set_apply_buff(callback: Callable) -> void:
	_apply_buff = callback


## Build the behavior tree structure.
func _build_behavior_tree() -> void:
	_root = BehaviorTreeNode.Selector.new("human_root")

	# Priority 1: Special behaviors based on unit type
	var special_sequence := BehaviorTreeNode.Sequence.new("special_behavior")
	special_sequence.add_child(BehaviorTreeNode.Condition.new("has_special", _check_has_special_behavior))
	special_sequence.add_child(BehaviorTreeNode.Action.new("do_special", _action_execute_special))
	_root.add_child(special_sequence)

	# Priority 2: Combat when enemy detected
	var combat_sequence := BehaviorTreeNode.Sequence.new("combat_sequence")
	combat_sequence.add_child(BehaviorTreeNode.Condition.new("enemy_detected", _check_enemy_detected))
	combat_sequence.add_child(BehaviorTreeNode.Action.new("engage_enemy", _action_engage_enemy))
	_root.add_child(combat_sequence)

	# Priority 3: Move to tactical position
	var position_sequence := BehaviorTreeNode.Sequence.new("tactical_position")
	position_sequence.add_child(BehaviorTreeNode.Condition.new("needs_position", _check_needs_tactical_position))
	position_sequence.add_child(BehaviorTreeNode.Action.new("move_tactical", _action_move_to_tactical))
	_root.add_child(position_sequence)

	# Priority 4: Patrol
	var patrol := BehaviorTreeNode.Action.new("patrol", _action_patrol)
	_root.add_child(patrol)


## Execute behavior tree for unit.
func execute(unit_id: int) -> int:
	var context := {
		"unit_id": unit_id,
		"faction_id": "human_remnant"
	}

	# Get unit type for context
	if _get_unit_type.is_valid():
		context["unit_type"] = _get_unit_type.call(unit_id)
	else:
		context["unit_type"] = "soldier"

	return _root.execute(context)


## Condition: Check if unit has special behavior.
func _check_has_special_behavior(context: Dictionary) -> bool:
	var unit_type: String = context.get("unit_type", "soldier")
	var special := HumanResistanceConfig.get_special_behavior(unit_type)
	return special != "none"


## Condition: Check if enemy detected.
func _check_enemy_detected(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]
	var unit_type: String = context.get("unit_type", "soldier")

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var detection_range := HumanResistanceConfig.get_detection_range(unit_type)

	var enemies: Array = _get_enemies_in_range.call(pos, detection_range, "human_remnant")

	if not enemies.is_empty():
		context["detected_enemies"] = enemies
		context["primary_target"] = enemies[0]
		return true

	return false


## Condition: Check if needs tactical position.
func _check_needs_tactical_position(context: Dictionary) -> bool:
	var unit_type: String = context.get("unit_type", "soldier")
	var special := HumanResistanceConfig.get_special_behavior(unit_type)

	# Sniper and Heavy Gunner need tactical positions
	return special in ["prefer_high_ground", "prefer_cover"]


## Action: Execute special behavior.
func _action_execute_special(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var unit_type: String = context.get("unit_type", "soldier")
	var special := HumanResistanceConfig.get_special_behavior(unit_type)

	match special:
		"prefer_high_ground":
			return _execute_high_ground_behavior(unit_id, context)
		"prefer_cover":
			return _execute_cover_behavior(unit_id, context)
		"lead_from_back":
			return _execute_commander_behavior(unit_id, context)

	return Status.FAILURE


## Execute high ground preference (Sniper).
func _execute_high_ground_behavior(unit_id: int, context: Dictionary) -> int:
	if not _get_unit_position.is_valid() or not _get_high_ground.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var high_ground: Vector3 = _get_high_ground.call(pos, 20.0)

	if high_ground == Vector3.INF:
		return Status.FAILURE

	if pos.distance_to(high_ground) < 3.0:
		# Already at high ground, engage if enemies present
		if context.has("primary_target"):
			return _action_engage_enemy(context)
		return Status.SUCCESS

	# Move to high ground
	if _request_movement.is_valid():
		_request_movement.call(unit_id, high_ground)
		return Status.RUNNING

	return Status.FAILURE


## Execute cover preference (Heavy Gunner).
func _execute_cover_behavior(unit_id: int, context: Dictionary) -> int:
	if not _get_unit_position.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)

	# Determine threat direction
	var threat_dir := Vector3.FORWARD
	if context.has("detected_enemies") and _get_unit_position.is_valid():
		var enemies: Array = context["detected_enemies"]
		if not enemies.is_empty():
			var enemy_pos: Vector3 = _get_unit_position.call(enemies[0])
			if enemy_pos != Vector3.INF:
				threat_dir = (enemy_pos - pos).normalized()

	# Find cover
	if _get_cover_position.is_valid():
		var cover_pos: Vector3 = _get_cover_position.call(pos, threat_dir)
		if cover_pos != Vector3.INF and pos.distance_to(cover_pos) > 2.0:
			if _request_movement.is_valid():
				_request_movement.call(unit_id, cover_pos)
				return Status.RUNNING

	# In cover or no cover found, engage if enemies present
	if context.has("primary_target"):
		return _action_engage_enemy(context)

	return Status.SUCCESS


## Execute commander behavior (lead from back, buff allies).
func _execute_commander_behavior(unit_id: int, context: Dictionary) -> int:
	if not _get_unit_position.is_valid() or not _get_allies_in_range.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var buff_config := HumanResistanceConfig.get_commander_buff()

	# Apply buffs to nearby allies
	var allies: Array = _get_allies_in_range.call(pos, buff_config["radius"], "human_remnant")

	if _apply_buff.is_valid():
		for ally_id in allies:
			if ally_id == unit_id:
				continue
			_apply_buff.call(ally_id, "commander_damage", buff_config["damage_bonus"])
			_apply_buff.call(ally_id, "commander_speed", buff_config["speed_bonus"])
			_apply_buff.call(ally_id, "commander_armor", buff_config["armor_bonus"])

	# Stay behind allies
	if not allies.is_empty():
		var avg_ally_pos := Vector3.ZERO
		var count := 0

		for ally_id in allies:
			if ally_id == unit_id:
				continue
			var ally_pos: Vector3 = _get_unit_position.call(ally_id)
			if ally_pos != Vector3.INF:
				avg_ally_pos += ally_pos
				count += 1

		if count > 0:
			avg_ally_pos /= float(count)

			# Calculate position behind allies (away from enemies if present)
			var back_dir := Vector3.BACK
			if context.has("detected_enemies") and not context["detected_enemies"].is_empty():
				var enemy_pos: Vector3 = _get_unit_position.call(context["detected_enemies"][0])
				if enemy_pos != Vector3.INF:
					back_dir = (avg_ally_pos - enemy_pos).normalized()

			var target_pos := avg_ally_pos + back_dir * 10.0

			if pos.distance_to(target_pos) > 3.0:
				if _request_movement.is_valid():
					_request_movement.call(unit_id, target_pos)

	# Engage if enemies present
	if context.has("primary_target"):
		return _action_engage_enemy(context)

	return Status.SUCCESS


## Action: Engage enemy.
func _action_engage_enemy(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var target_id: int = context.get("primary_target", -1)
	var unit_type: String = context.get("unit_type", "soldier")

	if target_id == -1:
		return Status.FAILURE

	# Check aggression - may flee if low
	var aggression := HumanResistanceConfig.get_aggression(unit_type)
	# For now, always engage if above 0.3 aggression
	if aggression < 0.3:
		return Status.FAILURE

	# Check if in attack range
	if _get_unit_position.is_valid():
		var pos: Vector3 = _get_unit_position.call(unit_id)
		var target_pos: Vector3 = _get_unit_position.call(target_id)
		var attack_range := HumanResistanceConfig.get_attack_range(unit_type)

		if target_pos != Vector3.INF:
			var distance := pos.distance_to(target_pos)

			if distance > attack_range:
				# Move closer
				var approach_pos := target_pos + (pos - target_pos).normalized() * (attack_range * 0.8)
				if _request_movement.is_valid():
					_request_movement.call(unit_id, approach_pos)
					return Status.RUNNING

	# Attack target
	if _set_attack_target.is_valid():
		_set_attack_target.call(unit_id, target_id)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Move to tactical position.
func _action_move_to_tactical(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var unit_type: String = context.get("unit_type", "soldier")
	var special := HumanResistanceConfig.get_special_behavior(unit_type)

	if special == "prefer_high_ground":
		return _execute_high_ground_behavior(unit_id, context)
	elif special == "prefer_cover":
		return _execute_cover_behavior(unit_id, context)

	return Status.FAILURE


## Action: Patrol.
func _action_patrol(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]

	if not _get_patrol_point.is_valid() or not _request_movement.is_valid():
		return Status.SUCCESS

	var patrol_point: Vector3 = _get_patrol_point.call(unit_id)

	if patrol_point != Vector3.INF:
		_request_movement.call(unit_id, patrol_point)
		return Status.RUNNING

	return Status.SUCCESS


## Get tree name.
func get_name() -> String:
	return "HumanResistanceBehaviorTree"
