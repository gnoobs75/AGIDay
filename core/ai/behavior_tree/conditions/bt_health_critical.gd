class_name BTHealthCritical
extends BTCondition
## BTHealthCritical checks if the unit's health is critically low.

## Health threshold below which health is considered critical (0.0 to 1.0)
var critical_threshold: float = 0.25


func _init(p_name: String = "", p_threshold: float = 0.25) -> void:
	super._init(p_name if not p_name.is_empty() else "HealthCritical")
	critical_threshold = p_threshold


func _check_condition(context: Dictionary) -> bool:
	var health_ratio: float = context.get("health_ratio", 1.0)
	return health_ratio <= critical_threshold
