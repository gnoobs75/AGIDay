class_name BTPatrol
extends BTAction
## BTPatrol makes the unit patrol between waypoints or in an area.
## Returns RUNNING while patrolling.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "Patrol")


func _perform_action(context: Dictionary) -> int:
	var patrol_waypoints: Array = context.get("patrol_waypoints", [])
	var current_waypoint_index: int = context.get("current_waypoint_index", 0)
	var position: Vector3 = context.get("position", Vector3.ZERO)

	if patrol_waypoints.is_empty():
		# No waypoints, just idle patrol in place
		context["action"] = "patrol_idle"
		return BTStatus.Status.RUNNING

	# Get current waypoint
	var target_waypoint: Vector3 = patrol_waypoints[current_waypoint_index]
	var distance := position.distance_to(target_waypoint)

	# Check if reached waypoint
	if distance < 2.0:
		# Move to next waypoint
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
		context["current_waypoint_index"] = current_waypoint_index
		target_waypoint = patrol_waypoints[current_waypoint_index]

	context["action"] = "patrol"
	context["move_target"] = target_waypoint

	return BTStatus.Status.RUNNING
