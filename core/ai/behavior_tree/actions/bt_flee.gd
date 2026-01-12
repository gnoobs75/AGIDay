class_name BTFlee
extends BTAction
## BTFlee makes the unit flee from threats toward safety.
## Returns RUNNING while fleeing.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "Flee")


func _perform_action(context: Dictionary) -> int:
	var position: Vector3 = context.get("position", Vector3.ZERO)
	var nearest_ally_position: Vector3 = context.get("nearest_ally_position", Vector3.ZERO)
	var threat_position: Vector3 = context.get("threat_position", Vector3.ZERO)

	var flee_target: Vector3

	# Prefer fleeing toward allies
	if nearest_ally_position != Vector3.ZERO:
		flee_target = nearest_ally_position
	else:
		# Flee away from threat
		var flee_direction := (position - threat_position).normalized()
		flee_target = position + flee_direction * 30.0

	context["action"] = "flee"
	context["move_target"] = flee_target

	return BTStatus.Status.RUNNING
