class_name BTSequence
extends BTComposite
## BTSequence executes children in order, requiring all to succeed.
## Returns SUCCESS only if all children succeed.
## Returns FAILURE if any child fails.
## Returns RUNNING if a child returns RUNNING.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "Sequence")


## Execute sequence logic.
func _execute(context: Dictionary) -> int:
	# Continue from where we left off if a child was RUNNING
	while current_child_index < children.size():
		var child := children[current_child_index]
		var status := child.execute(context)

		match status:
			BTStatus.Status.SUCCESS:
				# Child succeeded, continue to next
				current_child_index += 1
			BTStatus.Status.RUNNING:
				# Child still running, keep current index
				return BTStatus.Status.RUNNING
			BTStatus.Status.FAILURE:
				# Child failed, sequence fails
				current_child_index = 0
				return BTStatus.Status.FAILURE

	# All children succeeded
	current_child_index = 0
	return BTStatus.Status.SUCCESS
