class_name BTCondition
extends BTNode
## BTCondition is a leaf node that checks a condition.
## Returns SUCCESS if condition is true, FAILURE if false.

## Condition callback function (optional, for simple conditions)
var condition_callback: Callable = Callable()


func _init(p_name: String = "", callback: Callable = Callable()) -> void:
	super._init(p_name if not p_name.is_empty() else "Condition")
	condition_callback = callback


## Execute the condition check.
func _execute(context: Dictionary) -> int:
	var result: bool

	if condition_callback.is_valid():
		result = condition_callback.call(context)
	else:
		result = _check_condition(context)

	return BTStatus.Status.SUCCESS if result else BTStatus.Status.FAILURE


## Override in subclasses for custom condition logic.
## Should return true or false.
func _check_condition(_context: Dictionary) -> bool:
	return false
