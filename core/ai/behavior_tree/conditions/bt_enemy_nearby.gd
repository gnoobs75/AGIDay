class_name BTEnemyNearby
extends BTCondition
## BTEnemyNearby checks if there are enemies within detection range.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "EnemyNearby")


func _check_condition(context: Dictionary) -> bool:
	var potential_targets: Array = context.get("potential_targets", [])
	return not potential_targets.is_empty()
