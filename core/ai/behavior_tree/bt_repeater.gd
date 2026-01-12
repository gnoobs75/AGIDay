class_name BTRepeater
extends BTDecorator
## BTRepeater repeats its child a specified number of times.
## Returns SUCCESS after completing all repetitions.
## Returns FAILURE immediately if child fails (unless ignore_failure is true).
## Returns RUNNING if child is still running.

## Number of times to repeat (-1 for infinite)
var repeat_count: int = -1

## Whether to ignore child failures
var ignore_failure: bool = false

## Current repetition count
var current_repetition: int = 0


func _init(p_name: String = "", p_child: BTNode = null, p_repeat_count: int = -1, p_ignore_failure: bool = false) -> void:
	super._init(p_name if not p_name.is_empty() else "Repeater", p_child)
	repeat_count = p_repeat_count
	ignore_failure = p_ignore_failure


## Execute repeater logic.
func _execute(context: Dictionary) -> int:
	if child == null:
		return BTStatus.Status.FAILURE

	var status := child.execute(context)

	match status:
		BTStatus.Status.RUNNING:
			return BTStatus.Status.RUNNING
		BTStatus.Status.FAILURE:
			if not ignore_failure:
				current_repetition = 0
				return BTStatus.Status.FAILURE
		BTStatus.Status.SUCCESS:
			pass

	# Completed one iteration
	current_repetition += 1
	child.reset()

	# Check if we should continue
	if repeat_count < 0:
		# Infinite repeat
		return BTStatus.Status.RUNNING

	if current_repetition >= repeat_count:
		current_repetition = 0
		return BTStatus.Status.SUCCESS

	return BTStatus.Status.RUNNING


## Override reset to also reset repetition count.
func _on_reset() -> void:
	super._on_reset()
	current_repetition = 0


## Get debug info.
func get_debug_info() -> Dictionary:
	var info := super.get_debug_info()
	info["repeat_count"] = repeat_count
	info["current_repetition"] = current_repetition
	info["ignore_failure"] = ignore_failure
	return info
