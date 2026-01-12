class_name DynapodsBehaviorTree
extends RefCounted
## DynapodsBehaviorTree implements acrobatic movement and leg-based attacks.

## Behavior tree status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Root node
var _root: BehaviorTreeNode = null

## Callbacks
var _get_unit_position: Callable
var _get_enemies_in_range: Callable
var _get_allies_in_range: Callable
var _set_attack_target: Callable
var _request_movement: Callable
var _get_momentum: Callable  ## (unit_id) -> float
var _apply_momentum: Callable  ## (unit_id, direction, force) -> void
var _can_vault: Callable  ## (unit_id, obstacle) -> bool
var _execute_vault: Callable  ## (unit_id, obstacle) -> void
var _execute_leg_sweep: Callable  ## (unit_id) -> void


func _init() -> void:
	_build_behavior_tree()


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_enemies_in_range(callback: Callable) -> void:
	_get_enemies_in_range = callback


func set_get_allies_in_range(callback: Callable) -> void:
	_get_allies_in_range = callback


func set_attack_target(callback: Callable) -> void:
	_set_attack_target = callback


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback


func set_get_momentum(callback: Callable) -> void:
	_get_momentum = callback


func set_apply_momentum(callback: Callable) -> void:
	_apply_momentum = callback


func set_can_vault(callback: Callable) -> void:
	_can_vault = callback


func set_execute_vault(callback: Callable) -> void:
	_execute_vault = callback


func set_execute_leg_sweep(callback: Callable) -> void:
	_execute_leg_sweep = callback


## Build the behavior tree structure.
func _build_behavior_tree() -> void:
	_root = BehaviorTreeNode.Selector.new("dynapods_root")

	# Priority 1: Acrobatic dodge when threatened
	var dodge_sequence := BehaviorTreeNode.Sequence.new("dodge_sequence")
	dodge_sequence.add_child(BehaviorTreeNode.Condition.new("threat_detected", _check_threat_detected))
	dodge_sequence.add_child(BehaviorTreeNode.Action.new("acrobatic_dodge", _action_acrobatic_dodge))
	_root.add_child(dodge_sequence)

	# Priority 2: Momentum charge when built up
	var charge_sequence := BehaviorTreeNode.Sequence.new("charge_sequence")
	charge_sequence.add_child(BehaviorTreeNode.Condition.new("has_momentum", _check_has_momentum))
	charge_sequence.add_child(BehaviorTreeNode.Condition.new("enemy_in_charge_range", _check_enemy_in_charge_range))
	charge_sequence.add_child(BehaviorTreeNode.Action.new("momentum_charge", _action_momentum_charge))
	_root.add_child(charge_sequence)

	# Priority 3: Vault over obstacles
	var vault_sequence := BehaviorTreeNode.Sequence.new("vault_sequence")
	vault_sequence.add_child(BehaviorTreeNode.Condition.new("obstacle_ahead", _check_obstacle_ahead))
	vault_sequence.add_child(BehaviorTreeNode.Action.new("vault_obstacle", _action_vault_obstacle))
	_root.add_child(vault_sequence)

	# Priority 4: Leg sweep in melee
	var sweep_sequence := BehaviorTreeNode.Sequence.new("sweep_sequence")
	sweep_sequence.add_child(BehaviorTreeNode.Condition.new("enemies_in_melee", _check_enemies_in_melee))
	sweep_sequence.add_child(BehaviorTreeNode.Action.new("leg_sweep", _action_leg_sweep))
	_root.add_child(sweep_sequence)

	# Priority 5: Engage enemy with bounce attacks
	var engage_sequence := BehaviorTreeNode.Sequence.new("engage_sequence")
	engage_sequence.add_child(BehaviorTreeNode.Condition.new("enemy_detected", _check_enemy_detected))
	engage_sequence.add_child(BehaviorTreeNode.Action.new("bounce_attack", _action_bounce_attack))
	_root.add_child(engage_sequence)

	# Priority 6: Build momentum through movement
	var build_momentum := BehaviorTreeNode.Action.new("build_momentum", _action_build_momentum)
	_root.add_child(build_momentum)


## Execute behavior tree.
func execute(unit_id: int) -> int:
	var context := {
		"unit_id": unit_id,
		"faction_id": "dynapods"
	}
	return _root.execute(context)


## Condition: Threat detected (incoming attack).
func _check_threat_detected(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 5.0, "dynapods")

	# Threat if enemy very close
	if not enemies.is_empty():
		context["threat_source"] = enemies[0]
		return true

	return false


## Condition: Has momentum built up.
func _check_has_momentum(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_momentum.is_valid():
		return false

	var momentum: float = _get_momentum.call(unit_id)
	return momentum >= 0.7  ## 70% momentum threshold


## Condition: Enemy in charge range.
func _check_enemy_in_charge_range(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 15.0, "dynapods")

	if not enemies.is_empty():
		context["charge_target"] = enemies[0]
		return true

	return false


## Condition: Obstacle ahead.
func _check_obstacle_ahead(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _can_vault.is_valid():
		return false

	# Check for vaultable obstacles in front
	var obstacle := context.get("current_obstacle", null)
	if obstacle != null:
		return _can_vault.call(unit_id, obstacle)

	return false


## Condition: Enemies in melee range.
func _check_enemies_in_melee(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 3.0, "dynapods")

	if enemies.size() >= 2:  ## Multiple enemies for sweep
		context["sweep_targets"] = enemies
		return true

	return false


## Condition: Enemy detected.
func _check_enemy_detected(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 20.0, "dynapods")

	if not enemies.is_empty():
		context["detected_enemies"] = enemies
		context["primary_target"] = enemies[0]
		return true

	return false


## Action: Acrobatic dodge.
func _action_acrobatic_dodge(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _apply_momentum.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var threat_source: int = context.get("threat_source", -1)

	if threat_source == -1:
		return Status.FAILURE

	var threat_pos: Vector3 = _get_unit_position.call(threat_source)
	if threat_pos == Vector3.INF:
		return Status.FAILURE

	# Dodge perpendicular to threat direction
	var threat_dir := (pos - threat_pos).normalized()
	var dodge_dir := Vector3(-threat_dir.z, 0, threat_dir.x)  ## Perpendicular

	_apply_momentum.call(unit_id, dodge_dir, 15.0)

	return Status.SUCCESS


## Action: Momentum charge.
func _action_momentum_charge(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var target_id: int = context.get("charge_target", -1)

	if target_id == -1:
		return Status.FAILURE

	if not _get_unit_position.is_valid() or not _apply_momentum.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var target_pos: Vector3 = _get_unit_position.call(target_id)

	if target_pos == Vector3.INF:
		return Status.FAILURE

	var charge_dir := (target_pos - pos).normalized()
	_apply_momentum.call(unit_id, charge_dir, 25.0)  ## Strong charge

	if _set_attack_target.is_valid():
		_set_attack_target.call(unit_id, target_id)

	return Status.SUCCESS


## Action: Vault obstacle.
func _action_vault_obstacle(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var obstacle := context.get("current_obstacle", null)

	if obstacle == null:
		return Status.FAILURE

	if _execute_vault.is_valid():
		_execute_vault.call(unit_id, obstacle)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Leg sweep.
func _action_leg_sweep(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]

	if _execute_leg_sweep.is_valid():
		_execute_leg_sweep.call(unit_id)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Bounce attack (hit multiple targets).
func _action_bounce_attack(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var enemies: Array = context.get("detected_enemies", [])

	if enemies.is_empty():
		return Status.FAILURE

	if not _get_unit_position.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var target_pos: Vector3 = _get_unit_position.call(enemies[0])

	if target_pos == Vector3.INF:
		return Status.FAILURE

	var distance := pos.distance_to(target_pos)

	# If in range, attack
	if distance <= 8.0:
		if _set_attack_target.is_valid():
			_set_attack_target.call(unit_id, enemies[0])
		return Status.SUCCESS

	# Move to engage
	if _request_movement.is_valid():
		_request_movement.call(unit_id, target_pos)
		return Status.RUNNING

	return Status.FAILURE


## Action: Build momentum through movement.
func _action_build_momentum(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]

	if not _apply_momentum.is_valid():
		return Status.FAILURE

	# Move forward to build momentum
	_apply_momentum.call(unit_id, Vector3.FORWARD, 5.0)

	return Status.RUNNING


## Get tree name.
func get_name() -> String:
	return "DynapodsBehaviorTree"
