class_name BTAttack
extends BTAction
## BTAttack executes an attack on the current target.
## Returns SUCCESS after attack, FAILURE if no target or not in range.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "Attack")


func _perform_action(context: Dictionary) -> int:
	var target_id: int = context.get("target_id", -1)
	if target_id < 0:
		return BTStatus.Status.FAILURE

	var target_distance: float = context.get("target_distance", INF)
	var attack_range: float = context.get("attack_range", 10.0)

	# Check if in range
	if target_distance > attack_range:
		return BTStatus.Status.FAILURE

	# Execute attack
	context["action"] = "attack"
	context["attack_target_id"] = target_id

	return BTStatus.Status.SUCCESS
