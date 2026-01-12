class_name BTShouldDodge
extends BTCondition
## BTShouldDodge checks if the unit should perform a dodge maneuver.
## Considers incoming projectiles, nearby threats, and dodge cooldown.


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "ShouldDodge")


func _check_condition(context: Dictionary) -> bool:
	# Check if dodge is on cooldown
	var dodge_cooldown: float = context.get("dodge_cooldown", 0.0)
	if dodge_cooldown > 0:
		return false

	# Check for incoming projectiles
	var incoming_projectiles: Array = context.get("incoming_projectiles", [])
	if not incoming_projectiles.is_empty():
		# Store threat position for dodge direction calculation
		var nearest_projectile: Dictionary = incoming_projectiles[0]
		context["dodge_threat_position"] = nearest_projectile.get("position", Vector3.ZERO)
		return true

	# Check threat level (high threat might warrant dodge)
	var threat_level: float = context.get("threat_level", 0.0)
	if threat_level > 0.7:
		var target_position: Vector3 = context.get("target_position", Vector3.ZERO)
		context["dodge_threat_position"] = target_position
		return true

	return false
