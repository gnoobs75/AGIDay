class_name BTAction
extends BTNode
## BTAction is a leaf node that executes specific actions.
## Override _perform_action() in subclasses to implement custom behavior.

## Action callback function (optional, for simple actions)
var action_callback: Callable = Callable()


func _init(p_name: String = "", callback: Callable = Callable()) -> void:
	super._init(p_name if not p_name.is_empty() else "Action")
	action_callback = callback


## Execute the action.
func _execute(context: Dictionary) -> int:
	if action_callback.is_valid():
		return action_callback.call(context)
	return _perform_action(context)


## Override in subclasses for custom action logic.
## Should return BTStatus.Status value.
func _perform_action(_context: Dictionary) -> int:
	return BTStatus.Status.SUCCESS
