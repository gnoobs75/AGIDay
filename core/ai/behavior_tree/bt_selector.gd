class_name BTSelector
extends BTComposite
## BTSelector tries children in order until one succeeds or returns RUNNING.
## Returns SUCCESS if any child succeeds.
## Returns FAILURE only if all children fail.
## Returns RUNNING if a child returns RUNNING.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "Selector")


## Execute selector logic.
func _execute(context: Dictionary) -> int:
	# Continue from where we left off if a child was RUNNING
	while current_child_index < children.size():
		var child := children[current_child_index]
		var status := child.execute(context)

		match status:
			BTStatus.Status.SUCCESS:
				# Child succeeded, selector succeeds
				current_child_index = 0
				return BTStatus.Status.SUCCESS
			BTStatus.Status.RUNNING:
				# Child still running, keep current index
				return BTStatus.Status.RUNNING
			BTStatus.Status.FAILURE:
				# Child failed, try next child
				current_child_index += 1

	# All children failed
	current_child_index = 0
	return BTStatus.Status.FAILURE
