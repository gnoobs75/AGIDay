class_name BTDodge
extends BTAction
## BTDodge executes a dodge maneuver to avoid incoming attacks.
## Returns RUNNING while dodging, SUCCESS when complete.

## Dodge duration in seconds
var dodge_duration: float = 0.3

## Time spent dodging
var _dodge_time: float = 0.0


func _init(p_name: String = "", p_dodge_duration: float = 0.3) -> void:
	super._init(p_name if not p_name.is_empty() else "Dodge")
	dodge_duration = p_dodge_duration


func _perform_action(context: Dictionary) -> int:
	var delta: float = context.get("delta", 0.016)

	if _dodge_time <= 0:
		# Start dodge
		_dodge_time = dodge_duration
		_calculate_dodge_direction(context)

	_dodge_time -= delta

	if _dodge_time <= 0:
		# Dodge complete
		_dodge_time = 0.0
		context["action"] = "dodge_complete"
		return BTStatus.Status.SUCCESS

	context["action"] = "dodge"
	return BTStatus.Status.RUNNING


func _calculate_dodge_direction(context: Dictionary) -> void:
	var position: Vector3 = context.get("position", Vector3.ZERO)
	var threat_position: Vector3 = context.get("dodge_threat_position", Vector3.ZERO)

	# Calculate perpendicular dodge direction
	var to_threat := (threat_position - position).normalized()
	var dodge_direction := Vector3(-to_threat.z, 0, to_threat.x)  # Perpendicular

	# Randomly choose left or right
	if rand_float() < 0.5:
		dodge_direction = -dodge_direction

	context["dodge_direction"] = dodge_direction


func _on_reset() -> void:
	_dodge_time = 0.0
