class_name BehaviorTreeWrapper
extends RefCounted
## BehaviorTreeWrapper wraps behavior tree execution with seeded RNG for determinism.
## Provides abstraction layer compatible with LimboAI if available.

signal tree_evaluated(unit_id: int, action: String, status: int)
signal evaluation_started(unit_id: int)
signal evaluation_completed(unit_id: int, duration_ms: float)

## The behavior tree being wrapped
var tree: UnitBehaviorTree = null

## Blackboard for state management
var blackboard: BehaviorTreeBlackboard = null

## Unit ID this wrapper is for
var unit_id: int = -1

## Faction ID for faction-specific behavior
var faction_id: int = 0

## Unit type for type-specific behavior
var unit_type: String = ""

## Seed for deterministic behavior
var rng_seed: int = 0

## Random number generator
var _rng: RandomNumberGenerator = null

## Last evaluation time in milliseconds
var last_evaluation_time_ms: float = 0.0

## Total evaluations performed
var total_evaluations: int = 0

## Template used to create this tree
var template_id: String = ""


func _init(p_unit_id: int = -1, p_faction_id: int = 0, p_unit_type: String = "") -> void:
	unit_id = p_unit_id
	faction_id = p_faction_id
	unit_type = p_unit_type
	blackboard = BehaviorTreeBlackboard.new()
	_rng = RandomNumberGenerator.new()

	# Initialize blackboard with basic info
	blackboard.set_unit_id(unit_id)
	blackboard.set_faction_id(faction_id)


## Initialize with a seed for deterministic behavior.
func initialize(seed: int) -> void:
	rng_seed = seed
	_rng.seed = seed
	if tree != null:
		tree.initialize(seed)


## Set the behavior tree.
func set_tree(p_tree: UnitBehaviorTree) -> void:
	tree = p_tree
	if tree != null and rng_seed != 0:
		tree.initialize(rng_seed)


## Set tree from a template.
func set_tree_from_template(template: BehaviorTreeTemplate) -> void:
	tree = template.create_tree(unit_id)
	template_id = template.template_id

	# Apply default blackboard vars
	for key in template.default_blackboard_vars:
		blackboard.set_var(key, template.default_blackboard_vars[key])

	if rng_seed != 0:
		tree.initialize(rng_seed)


## Evaluate the behavior tree and return the action to execute.
## Returns action string (e.g., "attack", "move", "idle").
func evaluate() -> String:
	if tree == null:
		return "idle"

	var start_time := Time.get_ticks_usec()
	evaluation_started.emit(unit_id)

	# Sync blackboard to tree context
	_sync_blackboard_to_context()

	# Execute tree
	var status := tree.execute()

	# Get action from context
	var action: String = tree.get_context_value("action", "idle")

	# Sync context back to blackboard
	_sync_context_to_blackboard()

	# Calculate evaluation time
	var end_time := Time.get_ticks_usec()
	last_evaluation_time_ms = (end_time - start_time) / 1000.0
	total_evaluations += 1

	evaluation_completed.emit(unit_id, last_evaluation_time_ms)
	tree_evaluated.emit(unit_id, action, status)

	return action


## Sync blackboard variables to tree context.
func _sync_blackboard_to_context() -> void:
	if tree == null:
		return

	for key in blackboard.get_keys():
		tree.set_context_value(key, blackboard.get_var(key))


## Sync tree context back to blackboard.
func _sync_context_to_blackboard() -> void:
	if tree == null:
		return

	# Only sync specific keys we care about
	var keys_to_sync := ["action", "target_id", "target_position"]
	for key in keys_to_sync:
		var value = tree.get_context_value(key)
		if value != null:
			blackboard.set_var(key, value)


## Set a blackboard variable.
func set_blackboard_var(key: String, value: Variant) -> void:
	blackboard.set_var(key, value)


## Get a blackboard variable.
func get_blackboard_var(key: String, default: Variant = null) -> Variant:
	return blackboard.get_var(key, default)


## Update unit data in blackboard.
func update_unit_data(data: Dictionary) -> void:
	for key in data:
		blackboard.set_var(key, data[key])


## Set target for the behavior tree.
func set_target(target_id: int, target_position: Vector3 = Vector3.ZERO, target_distance: float = INF) -> void:
	blackboard.set_target_id(target_id)
	blackboard.set_target_position(target_position)
	blackboard.set_var("target_distance", target_distance)


## Clear target.
func clear_target() -> void:
	blackboard.set_target_id(-1)
	blackboard.set_target_position(Vector3.ZERO)
	blackboard.set_var("target_distance", INF)


## Pause the behavior tree.
func pause() -> void:
	if tree != null:
		tree.pause()


## Resume the behavior tree.
func resume() -> void:
	if tree != null:
		tree.resume()


## Reset the behavior tree.
func reset() -> void:
	if tree != null:
		tree.reset()


## Interrupt the behavior tree.
func interrupt() -> void:
	if tree != null:
		tree.interrupt()


## Get a random float (deterministic).
func rand_float() -> float:
	return _rng.randf()


## Get a random int in range (deterministic).
func rand_int(min_val: int, max_val: int) -> int:
	return _rng.randi_range(min_val, max_val)


## Get the last action from evaluation.
func get_last_action() -> String:
	return blackboard.get_current_action()


## Get debug info.
func get_debug_info() -> Dictionary:
	var info := {
		"unit_id": unit_id,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"template_id": template_id,
		"rng_seed": rng_seed,
		"last_evaluation_time_ms": last_evaluation_time_ms,
		"total_evaluations": total_evaluations,
		"last_action": get_last_action(),
		"blackboard_vars": blackboard.get_all_data().size()
	}

	if tree != null:
		info["tree"] = tree.get_debug_info()

	return info


## Create a wrapper with attack-or-idle behavior.
static func create_attack_or_idle(unit_id: int, faction_id: int = 0, unit_type: String = "") -> BehaviorTreeWrapper:
	var wrapper := BehaviorTreeWrapper.new(unit_id, faction_id, unit_type)
	wrapper.set_tree(UnitBehaviorTree.create_attack_or_idle_tree(unit_id))
	wrapper.template_id = "attack_or_idle"
	return wrapper


## Create a wrapper with chase-attack behavior.
static func create_chase_attack(unit_id: int, faction_id: int = 0, unit_type: String = "") -> BehaviorTreeWrapper:
	var wrapper := BehaviorTreeWrapper.new(unit_id, faction_id, unit_type)
	wrapper.set_tree(UnitBehaviorTree.create_chase_attack_tree(unit_id))
	wrapper.template_id = "chase_attack"
	return wrapper
