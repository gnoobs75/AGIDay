class_name BehaviorTreeNode
extends RefCounted
## BehaviorTreeNode is the base class for all behavior tree nodes.

## Status values
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Node name
var node_name: String = ""

## Children nodes
var children: Array[BehaviorTreeNode] = []

## Parent node
var parent: BehaviorTreeNode = null


func _init(name: String = "") -> void:
	node_name = name


## Execute the node.
func execute(context: Dictionary) -> int:
	return Status.FAILURE


## Add child node.
func add_child(child: BehaviorTreeNode) -> void:
	child.parent = self
	children.append(child)


## Get debug string.
func get_debug_string() -> String:
	return node_name


## Selector node - runs children until one succeeds.
class Selector extends BehaviorTreeNode:
	var _current_child: int = 0

	func execute(context: Dictionary) -> int:
		while _current_child < children.size():
			var result := children[_current_child].execute(context)

			if result == Status.SUCCESS:
				_current_child = 0
				return Status.SUCCESS
			elif result == Status.RUNNING:
				return Status.RUNNING
			else:
				_current_child += 1

		_current_child = 0
		return Status.FAILURE


## Sequence node - runs children until one fails.
class Sequence extends BehaviorTreeNode:
	var _current_child: int = 0

	func execute(context: Dictionary) -> int:
		while _current_child < children.size():
			var result := children[_current_child].execute(context)

			if result == Status.FAILURE:
				_current_child = 0
				return Status.FAILURE
			elif result == Status.RUNNING:
				return Status.RUNNING
			else:
				_current_child += 1

		_current_child = 0
		return Status.SUCCESS


## Condition node - evaluates a condition.
class Condition extends BehaviorTreeNode:
	var condition_func: Callable

	func _init(name: String = "", condition: Callable = Callable()) -> void:
		super._init(name)
		condition_func = condition

	func execute(context: Dictionary) -> int:
		if condition_func.is_valid():
			if condition_func.call(context):
				return Status.SUCCESS
		return Status.FAILURE


## Action node - performs an action.
class Action extends BehaviorTreeNode:
	var action_func: Callable

	func _init(name: String = "", action: Callable = Callable()) -> void:
		super._init(name)
		action_func = action

	func execute(context: Dictionary) -> int:
		if action_func.is_valid():
			return action_func.call(context)
		return Status.FAILURE


## Decorator node - modifies child behavior.
class Decorator extends BehaviorTreeNode:
	func execute(context: Dictionary) -> int:
		if children.is_empty():
			return Status.FAILURE
		return children[0].execute(context)


## Inverter decorator - inverts child result.
class Inverter extends Decorator:
	func execute(context: Dictionary) -> int:
		var result := super.execute(context)
		if result == Status.SUCCESS:
			return Status.FAILURE
		elif result == Status.FAILURE:
			return Status.SUCCESS
		return result


## Repeater decorator - repeats child N times.
class Repeater extends Decorator:
	var repeat_count: int = 1
	var _current_count: int = 0

	func _init(name: String = "", count: int = 1) -> void:
		super._init(name)
		repeat_count = count

	func execute(context: Dictionary) -> int:
		while _current_count < repeat_count:
			var result := super.execute(context)

			if result == Status.RUNNING:
				return Status.RUNNING
			elif result == Status.FAILURE:
				_current_count = 0
				return Status.FAILURE

			_current_count += 1

		_current_count = 0
		return Status.SUCCESS
