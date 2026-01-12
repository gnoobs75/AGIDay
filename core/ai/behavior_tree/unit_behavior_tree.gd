class_name UnitBehaviorTree
extends RefCounted
## UnitBehaviorTree manages behavior tree execution for a unit.
## Provides context management, execution control, and debugging.

signal tree_executed(unit_id: int, status: int)
signal tree_completed(unit_id: int, success: bool)
signal tree_interrupted(unit_id: int)

## The unit this behavior tree controls
var unit_id: int = -1

## Root node of the behavior tree
var root: BTNode = null

## Execution context passed to all nodes
var context: Dictionary = {}

## Whether the tree is currently active
var is_active: bool = true

## Whether the tree is paused
var is_paused: bool = false

## Last execution status
var last_status: int = BTStatus.Status.FAILURE

## Execution statistics
var total_executions: int = 0
var total_successes: int = 0
var total_failures: int = 0

## Seed for deterministic execution
var tree_seed: int = 0


func _init(p_unit_id: int = -1, p_root: BTNode = null) -> void:
	unit_id = p_unit_id
	root = p_root


## Set the root node.
func set_root(p_root: BTNode) -> void:
	root = p_root


## Initialize the tree with a seed.
func initialize(seed: int = 0) -> void:
	tree_seed = seed
	if root != null:
		root.initialize(seed)


## Set context value.
func set_context_value(key: String, value: Variant) -> void:
	context[key] = value


## Get context value.
func get_context_value(key: String, default: Variant = null) -> Variant:
	return context.get(key, default)


## Clear context.
func clear_context() -> void:
	context.clear()


## Update context with unit data.
func update_unit_context(unit_data: Dictionary) -> void:
	context["unit"] = unit_data
	context["unit_id"] = unit_id


## Execute one tick of the behavior tree.
func execute() -> int:
	if not is_active or is_paused:
		return last_status

	if root == null:
		return BTStatus.Status.FAILURE

	total_executions += 1
	last_status = root.execute(context)

	match last_status:
		BTStatus.Status.SUCCESS:
			total_successes += 1
			tree_completed.emit(unit_id, true)
		BTStatus.Status.FAILURE:
			total_failures += 1
			tree_completed.emit(unit_id, false)

	tree_executed.emit(unit_id, last_status)
	return last_status


## Pause execution.
func pause() -> void:
	is_paused = true


## Resume execution.
func resume() -> void:
	is_paused = false


## Stop and deactivate the tree.
func stop() -> void:
	is_active = false
	if root != null:
		root.interrupt()
	tree_interrupted.emit(unit_id)


## Reset the tree to initial state.
func reset() -> void:
	is_active = true
	is_paused = false
	last_status = BTStatus.Status.FAILURE
	if root != null:
		root.reset()


## Interrupt the current execution.
func interrupt() -> void:
	if root != null:
		root.interrupt()
	tree_interrupted.emit(unit_id)


## Get current status name.
func get_status_name() -> String:
	return BTStatus.to_string_status(last_status)


## Get debug info.
func get_debug_info() -> Dictionary:
	var info := {
		"unit_id": unit_id,
		"is_active": is_active,
		"is_paused": is_paused,
		"last_status": get_status_name(),
		"total_executions": total_executions,
		"total_successes": total_successes,
		"total_failures": total_failures,
		"success_rate": 0.0
	}

	if total_executions > 0:
		info["success_rate"] = float(total_successes) / float(total_executions)

	if root != null:
		info["root"] = root.get_debug_info()

	return info


## Create a simple attack-or-idle tree.
static func create_attack_or_idle_tree(unit_id: int) -> UnitBehaviorTree:
	var tree := UnitBehaviorTree.new(unit_id)

	# Root selector: try to attack, else idle
	var root := BTSelector.new("AttackOrIdle")

	# Attack sequence: has target -> in range -> attack
	var attack_sequence := BTSequence.new("AttackSequence")
	attack_sequence.add_child(BTCondition.new("HasTarget", func(ctx: Dictionary) -> bool:
		return ctx.get("target_id", -1) >= 0
	))
	attack_sequence.add_child(BTCondition.new("InRange", func(ctx: Dictionary) -> bool:
		return ctx.get("target_distance", INF) <= ctx.get("attack_range", 0.0)
	))
	attack_sequence.add_child(BTAction.new("Attack", func(ctx: Dictionary) -> int:
		ctx["action"] = "attack"
		return BTStatus.Status.SUCCESS
	))

	# Idle action (fallback)
	var idle_action := BTAction.new("Idle", func(ctx: Dictionary) -> int:
		ctx["action"] = "idle"
		return BTStatus.Status.SUCCESS
	)

	root.add_child(attack_sequence)
	root.add_child(idle_action)

	tree.set_root(root)
	return tree


## Create a chase-attack tree.
static func create_chase_attack_tree(unit_id: int) -> UnitBehaviorTree:
	var tree := UnitBehaviorTree.new(unit_id)

	# Root selector: attack if in range, chase if has target, else idle
	var root := BTSelector.new("ChaseAttack")

	# Attack if in range
	var attack_sequence := BTSequence.new("AttackIfInRange")
	attack_sequence.add_child(BTCondition.new("HasTarget", func(ctx: Dictionary) -> bool:
		return ctx.get("target_id", -1) >= 0
	))
	attack_sequence.add_child(BTCondition.new("InAttackRange", func(ctx: Dictionary) -> bool:
		return ctx.get("target_distance", INF) <= ctx.get("attack_range", 0.0)
	))
	attack_sequence.add_child(BTAction.new("Attack", func(ctx: Dictionary) -> int:
		ctx["action"] = "attack"
		return BTStatus.Status.SUCCESS
	))

	# Chase if has target but not in range
	var chase_sequence := BTSequence.new("ChaseIfHasTarget")
	chase_sequence.add_child(BTCondition.new("HasTarget", func(ctx: Dictionary) -> bool:
		return ctx.get("target_id", -1) >= 0
	))
	chase_sequence.add_child(BTAction.new("Chase", func(ctx: Dictionary) -> int:
		ctx["action"] = "chase"
		return BTStatus.Status.RUNNING
	))

	# Idle fallback
	var idle_action := BTAction.new("Idle", func(ctx: Dictionary) -> int:
		ctx["action"] = "idle"
		return BTStatus.Status.SUCCESS
	)

	root.add_child(attack_sequence)
	root.add_child(chase_sequence)
	root.add_child(idle_action)

	tree.set_root(root)
	return tree
