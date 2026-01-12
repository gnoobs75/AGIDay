class_name BTInAttackRange
extends BTCondition
## BTInAttackRange checks if the current target is within attack range.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "InAttackRange")


func _check_condition(context: Dictionary) -> bool:
	var target_id: int = context.get("target_id", -1)
	if target_id < 0:
		return false

	var target_distance: float = context.get("target_distance", INF)
	var attack_range: float = context.get("attack_range", 10.0)

	return target_distance <= attack_range
