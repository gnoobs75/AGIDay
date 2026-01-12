class_name BTMoveToAlly
extends BTAction
## BTMoveToAlly moves the unit toward the nearest ally.
## Returns RUNNING while moving, SUCCESS when close.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "MoveToAlly")


func _perform_action(context: Dictionary) -> int:
	var ally_position: Vector3 = context.get("nearest_ally_position", Vector3.ZERO)
	if ally_position == Vector3.ZERO:
		return BTStatus.Status.FAILURE

	var position: Vector3 = context.get("position", Vector3.ZERO)
	var distance := position.distance_to(ally_position)

	# Check if close enough to ally
	var safe_distance: float = context.get("ally_safe_distance", 10.0)
	if distance <= safe_distance:
		context["action"] = "at_ally"
		return BTStatus.Status.SUCCESS

	context["action"] = "move_to_ally"
	context["move_target"] = ally_position

	return BTStatus.Status.RUNNING
