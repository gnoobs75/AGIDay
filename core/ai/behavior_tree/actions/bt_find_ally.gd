class_name BTFindAlly
extends BTAction
## BTFindAlly searches for the nearest ally and stores it in the blackboard.
## Returns SUCCESS if ally found, FAILURE otherwise.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "FindNearestAlly")


func _perform_action(context: Dictionary) -> int:
	var nearby_allies: Array = context.get("nearby_allies", [])
	if nearby_allies.is_empty():
		context["action"] = "find_ally"
		return BTStatus.Status.FAILURE

	var position: Vector3 = context.get("position", Vector3.ZERO)
	var nearest_ally: Dictionary = {}
	var nearest_distance := INF

	for ally in nearby_allies:
		var ally_pos: Vector3 = ally.get("position", Vector3.ZERO)
		var distance := position.distance_to(ally_pos)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_ally = ally

	if nearest_ally.is_empty():
		return BTStatus.Status.FAILURE

	context["nearest_ally_id"] = nearest_ally.get("id", -1)
	context["nearest_ally_position"] = nearest_ally.get("position", Vector3.ZERO)
	context["nearest_ally_distance"] = nearest_distance
	context["action"] = "ally_found"

	return BTStatus.Status.SUCCESS
