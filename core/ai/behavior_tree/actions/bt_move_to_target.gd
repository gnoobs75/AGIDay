class_name BTMoveToTarget
extends BTAction
## BTMoveToTarget moves the unit toward its current target.
## Returns RUNNING while moving, SUCCESS when in range, FAILURE if no target.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "MoveToTarget")


func _perform_action(context: Dictionary) -> int:
	var target_id: int = context.get("target_id", -1)
	if target_id < 0:
		return BTStatus.Status.FAILURE

	var target_distance: float = context.get("target_distance", INF)
	var attack_range: float = context.get("attack_range", 10.0)

	# Check if already in range
	if target_distance <= attack_range:
		context["action"] = "in_range"
		return BTStatus.Status.SUCCESS

	# Set move action
	context["action"] = "move_to_target"
	context["move_target"] = context.get("target_position", Vector3.ZERO)

	return BTStatus.Status.RUNNING
