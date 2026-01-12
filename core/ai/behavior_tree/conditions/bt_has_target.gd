class_name BTHasTarget
extends BTCondition
## BTHasTarget checks if the unit has a valid target.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "HasTarget")


func _check_condition(context: Dictionary) -> bool:
	var target_id: int = context.get("target_id", -1)
	return target_id >= 0
