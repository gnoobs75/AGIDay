class_name TargetInfo
extends RefCounted
## TargetInfo stores information about a potential target for AI decision-making.
## Used for priority-based target selection.

## Target unit ID
var target_id: int = -1

## Target faction ID
var faction_id: int = 0

## Distance to target
var distance: float = INF

## Target's current health ratio (0.0 to 1.0)
var health_ratio: float = 1.0

## Target's damage output (threat indicator)
var damage: float = 0.0

## Calculated threat level
var threat: float = 0.0

## Calculated priority score
var priority: float = 0.0

## Target position
var position: Vector3 = Vector3.ZERO

## Whether target is currently attacking us
var is_attacking_us: bool = false

## Target unit type
var unit_type: String = ""


func _init(p_target_id: int = -1) -> void:
	target_id = p_target_id


## Calculate threat level.
## threat = damage * (1.0 - health_ratio) means damaged units are less threatening.
func calculate_threat() -> float:
	# Higher damage = more threatening
	# Lower health = less threatening (prioritize healthy targets)
	threat = damage * (1.0 - health_ratio * 0.5)  # Modified: healthy units are more threatening
	return threat


## Calculate priority score.
## priority = threat / (distance + 1.0) means closer, more dangerous units have higher priority.
func calculate_priority() -> float:
	# Ensure threat is calculated
	if threat <= 0:
		calculate_threat()

	# Priority formula: threat / (distance + 1.0)
	# Adding 1.0 prevents division by zero and reduces priority spike at very close range
	priority = threat / (distance + 1.0)

	# Bonus priority if target is attacking us
	if is_attacking_us:
		priority *= 1.5

	return priority


## Update from unit data.
func update_from_unit_data(data: Dictionary) -> void:
	target_id = data.get("id", target_id)
	faction_id = data.get("faction_id", faction_id)
	health_ratio = data.get("health_ratio", health_ratio)
	damage = data.get("damage", damage)
	position = data.get("position", position)
	unit_type = data.get("unit_type", unit_type)


## Check if target is valid.
func is_valid() -> bool:
	return target_id >= 0 and health_ratio > 0


## Clear target info.
func clear() -> void:
	target_id = -1
	faction_id = 0
	distance = INF
	health_ratio = 1.0
	damage = 0.0
	threat = 0.0
	priority = 0.0
	position = Vector3.ZERO
	is_attacking_us = false
	unit_type = ""


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"target_id": target_id,
		"faction_id": faction_id,
		"distance": distance,
		"health_ratio": health_ratio,
		"damage": damage,
		"threat": threat,
		"priority": priority,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"is_attacking_us": is_attacking_us,
		"unit_type": unit_type
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> TargetInfo:
	var info := TargetInfo.new()
	info.target_id = data.get("target_id", -1)
	info.faction_id = data.get("faction_id", 0)
	info.distance = data.get("distance", INF)
	info.health_ratio = data.get("health_ratio", 1.0)
	info.damage = data.get("damage", 0.0)
	info.threat = data.get("threat", 0.0)
	info.priority = data.get("priority", 0.0)
	info.is_attacking_us = data.get("is_attacking_us", false)
	info.unit_type = data.get("unit_type", "")

	var pos_data: Dictionary = data.get("position", {})
	info.position = Vector3(
		pos_data.get("x", 0.0),
		pos_data.get("y", 0.0),
		pos_data.get("z", 0.0)
	)

	return info


## Get summary for debugging.
func get_summary() -> String:
	return "Target(%d) dist=%.1f threat=%.2f priority=%.3f" % [target_id, distance, threat, priority]
