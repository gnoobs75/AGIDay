class_name BTInverter
extends BTDecorator
## BTInverter inverts the result of its child.
## SUCCESS becomes FAILURE, FAILURE becomes SUCCESS.
## RUNNING remains RUNNING.


func _init(p_name: String = "", p_child: BTNode = null) -> void:
	super._init(p_name if not p_name.is_empty() else "Inverter", p_child)


## Execute and invert the child result.
func _execute(context: Dictionary) -> int:
	if child == null:
		return BTStatus.Status.FAILURE

	var status := child.execute(context)

	match status:
		BTStatus.Status.SUCCESS:
			return BTStatus.Status.FAILURE
		BTStatus.Status.FAILURE:
			return BTStatus.Status.SUCCESS
		_:
			return status
