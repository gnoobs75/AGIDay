class_name BTFindTarget
extends BTAction
## BTFindTarget searches for a valid target and stores it in the blackboard.
## Returns SUCCESS if target found, FAILURE otherwise.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "FindTarget")


func _perform_action(context: Dictionary) -> int:
	# Check if we already have a valid target
	var current_target_id: int = context.get("target_id", -1)
	if current_target_id >= 0:
		var target_health: float = context.get("target_health_ratio", 0.0)
		if target_health > 0:
			return BTStatus.Status.SUCCESS

	# Look for potential targets in context
	var potential_targets: Array = context.get("potential_targets", [])
	if potential_targets.is_empty():
		context["action"] = "find_target"
		return BTStatus.Status.FAILURE

	# Find best target (first one for now, AIComponent handles priority)
	var best_target: Dictionary = potential_targets[0]
	for target in potential_targets:
		var priority: float = target.get("priority", 0.0)
		if priority > best_target.get("priority", 0.0):
			best_target = target

	# Store target in context
	context["target_id"] = best_target.get("target_id", -1)
	context["target_position"] = best_target.get("position", Vector3.ZERO)
	context["target_distance"] = best_target.get("distance", INF)
	context["action"] = "target_acquired"

	return BTStatus.Status.SUCCESS
