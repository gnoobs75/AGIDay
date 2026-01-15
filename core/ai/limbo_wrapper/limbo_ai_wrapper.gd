class_name LimboAIWrapper
extends RefCounted
## LimboAIWrapper provides a custom abstraction layer around LimboAI.
## Enables decoupling for testing and future AI backend swaps.

## Behavior tree execution status
enum BTStatus {
	SUCCESS = 0,
	FAILURE = 1,
	RUNNING = 2
}

## Node types for tree construction
enum NodeType {
	SELECTOR,
	SEQUENCE,
	PARALLEL,
	CONDITION,
	ACTION,
	DECORATOR_INVERTER,
	DECORATOR_REPEATER,
	DECORATOR_LIMITER
}

## Blackboard key prefixes
const KEY_UNIT := "unit_"
const KEY_FACTION := "faction_"
const KEY_COMBAT := "combat_"
const KEY_MOVEMENT := "movement_"


## Create a new behavior tree root.
static func create_tree(tree_name: String) -> LimboBTNode:
	return LimboBTNode.new(tree_name, NodeType.SELECTOR)


## Create selector node (OR logic - first success wins).
static func create_selector(name: String) -> LimboBTNode:
	return LimboBTNode.new(name, NodeType.SELECTOR)


## Create sequence node (AND logic - all must succeed).
static func create_sequence(name: String) -> LimboBTNode:
	return LimboBTNode.new(name, NodeType.SEQUENCE)


## Create parallel node (runs all children simultaneously).
static func create_parallel(name: String, success_threshold: int = 1) -> LimboBTNode:
	var node := LimboBTNode.new(name, NodeType.PARALLEL)
	node.set_bt_meta("success_threshold", success_threshold)
	return node


## Create condition node.
static func create_condition(name: String, condition_func: Callable) -> LimboBTNode:
	var node := LimboBTNode.new(name, NodeType.CONDITION)
	node.set_condition(condition_func)
	return node


## Create action node.
static func create_action(name: String, action_func: Callable) -> LimboBTNode:
	var node := LimboBTNode.new(name, NodeType.ACTION)
	node.set_action(action_func)
	return node


## Create inverter decorator.
static func create_inverter(name: String) -> LimboBTNode:
	return LimboBTNode.new(name, NodeType.DECORATOR_INVERTER)


## Create repeater decorator.
static func create_repeater(name: String, repeat_count: int = -1) -> LimboBTNode:
	var node := LimboBTNode.new(name, NodeType.DECORATOR_REPEATER)
	node.set_bt_meta("repeat_count", repeat_count)
	return node


## Create limiter decorator (limits execution frequency).
static func create_limiter(name: String, cooldown_seconds: float) -> LimboBTNode:
	var node := LimboBTNode.new(name, NodeType.DECORATOR_LIMITER)
	node.set_bt_meta("cooldown", cooldown_seconds)
	return node


## LimboBTNode class - wrapper for behavior tree nodes.
class LimboBTNode extends RefCounted:
	var node_name: String
	var node_type: int
	var children: Array[LimboBTNode] = []
	var _condition: Callable
	var _action: Callable
	var _metadata: Dictionary = {}
	var _last_execution_time := 0.0


	func _init(p_name: String, p_type: int) -> void:
		node_name = p_name
		node_type = p_type


	func add_child(child: LimboBTNode) -> LimboBTNode:
		children.append(child)
		return self


	func set_condition(callback: Callable) -> void:
		_condition = callback


	func set_action(callback: Callable) -> void:
		_action = callback


	func set_bt_meta(key: String, value: Variant) -> void:
		_metadata[key] = value


	func get_meta_value(key: String, default: Variant = null) -> Variant:
		return _metadata.get(key, default)


	## Execute the node with given blackboard.
	func execute(blackboard: Dictionary) -> int:
		match node_type:
			NodeType.SELECTOR:
				return _execute_selector(blackboard)
			NodeType.SEQUENCE:
				return _execute_sequence(blackboard)
			NodeType.PARALLEL:
				return _execute_parallel(blackboard)
			NodeType.CONDITION:
				return _execute_condition(blackboard)
			NodeType.ACTION:
				return _execute_action(blackboard)
			NodeType.DECORATOR_INVERTER:
				return _execute_inverter(blackboard)
			NodeType.DECORATOR_REPEATER:
				return _execute_repeater(blackboard)
			NodeType.DECORATOR_LIMITER:
				return _execute_limiter(blackboard)

		return BTStatus.FAILURE


	func _execute_selector(blackboard: Dictionary) -> int:
		for child in children:
			var result := child.execute(blackboard)
			if result == BTStatus.SUCCESS:
				return BTStatus.SUCCESS
			if result == BTStatus.RUNNING:
				return BTStatus.RUNNING
		return BTStatus.FAILURE


	func _execute_sequence(blackboard: Dictionary) -> int:
		for child in children:
			var result := child.execute(blackboard)
			if result == BTStatus.FAILURE:
				return BTStatus.FAILURE
			if result == BTStatus.RUNNING:
				return BTStatus.RUNNING
		return BTStatus.SUCCESS


	func _execute_parallel(blackboard: Dictionary) -> int:
		var success_count := 0
		var running_count := 0
		var threshold: int = get_meta_value("success_threshold", 1)

		for child in children:
			var result := child.execute(blackboard)
			if result == BTStatus.SUCCESS:
				success_count += 1
			elif result == BTStatus.RUNNING:
				running_count += 1

		if success_count >= threshold:
			return BTStatus.SUCCESS
		if running_count > 0:
			return BTStatus.RUNNING
		return BTStatus.FAILURE


	func _execute_condition(blackboard: Dictionary) -> int:
		if not _condition.is_valid():
			return BTStatus.FAILURE

		var result: bool = _condition.call(blackboard)
		return BTStatus.SUCCESS if result else BTStatus.FAILURE


	func _execute_action(blackboard: Dictionary) -> int:
		if not _action.is_valid():
			return BTStatus.FAILURE

		return _action.call(blackboard)


	func _execute_inverter(blackboard: Dictionary) -> int:
		if children.is_empty():
			return BTStatus.FAILURE

		var result := children[0].execute(blackboard)
		if result == BTStatus.SUCCESS:
			return BTStatus.FAILURE
		if result == BTStatus.FAILURE:
			return BTStatus.SUCCESS
		return BTStatus.RUNNING


	func _execute_repeater(blackboard: Dictionary) -> int:
		if children.is_empty():
			return BTStatus.FAILURE

		var repeat_count: int = get_meta_value("repeat_count", -1)
		var current_count: int = blackboard.get("_repeater_" + node_name, 0)

		if repeat_count > 0 and current_count >= repeat_count:
			return BTStatus.SUCCESS

		var result := children[0].execute(blackboard)

		if result == BTStatus.SUCCESS or result == BTStatus.FAILURE:
			blackboard["_repeater_" + node_name] = current_count + 1

		if repeat_count < 0:  ## Infinite
			return BTStatus.RUNNING

		return result


	func _execute_limiter(blackboard: Dictionary) -> int:
		if children.is_empty():
			return BTStatus.FAILURE

		var cooldown: float = get_meta_value("cooldown", 1.0)
		var current_time := Time.get_ticks_msec() / 1000.0

		if current_time - _last_execution_time < cooldown:
			return BTStatus.FAILURE

		_last_execution_time = current_time
		return children[0].execute(blackboard)


	## Serialize node to dictionary.
	func to_dict() -> Dictionary:
		var children_data: Array = []
		for child in children:
			children_data.append(child.to_dict())

		return {
			"name": node_name,
			"type": node_type,
			"metadata": _metadata.duplicate(),
			"children": children_data
		}
