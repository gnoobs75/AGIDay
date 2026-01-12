class_name DistrictControlPoint
extends RefCounted
## DistrictControlPoint represents a capture point within a district.
## Multiple control points per district allow for more granular control.

signal captured(faction_id: String)
signal capture_progress_changed(progress: float)

## Control point ID
var id: int = -1

## District ID this point belongs to
var district_id: int = -1

## World position of control point
var position: Vector3 = Vector3.ZERO

## Capture radius
var capture_radius: float = 10.0

## Current controlling faction
var controlling_faction: String = ""

## Capture progress by faction (0-100)
var capture_progress: Dictionary = {}

## Points required to capture
var capture_points_required: float = 50.0


func _init(p_id: int = -1, p_district_id: int = -1, p_position: Vector3 = Vector3.ZERO) -> void:
	id = p_id
	district_id = p_district_id
	position = p_position


## Check if a position is within capture radius.
func is_in_range(pos: Vector3) -> bool:
	var dist := position.distance_to(pos)
	return dist <= capture_radius


## Add capture progress for a faction.
func add_progress(faction_id: String, amount: float) -> void:
	if not capture_progress.has(faction_id):
		capture_progress[faction_id] = 0.0

	capture_progress[faction_id] = minf(capture_progress[faction_id] + amount, capture_points_required)
	capture_progress_changed.emit(capture_progress[faction_id])

	if capture_progress[faction_id] >= capture_points_required:
		_complete_capture(faction_id)


## Complete capture.
func _complete_capture(faction_id: String) -> void:
	controlling_faction = faction_id
	capture_progress.clear()
	captured.emit(faction_id)


## Check if captured.
func is_captured() -> bool:
	return not controlling_faction.is_empty()


## Check if captured by faction.
func is_captured_by(faction_id: String) -> bool:
	return controlling_faction == faction_id


## Get capture progress for a faction.
func get_progress(faction_id: String) -> float:
	return capture_progress.get(faction_id, 0.0)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"district_id": district_id,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"capture_radius": capture_radius,
		"controlling_faction": controlling_faction,
		"capture_progress": capture_progress.duplicate(),
		"capture_points_required": capture_points_required
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> DistrictControlPoint:
	var point := DistrictControlPoint.new()
	point.id = data.get("id", -1)
	point.district_id = data.get("district_id", -1)
	point.capture_radius = data.get("capture_radius", 10.0)
	point.controlling_faction = data.get("controlling_faction", "")
	point.capture_progress = data.get("capture_progress", {}).duplicate()
	point.capture_points_required = data.get("capture_points_required", 50.0)

	var pos_data: Dictionary = data.get("position", {})
	point.position = Vector3(pos_data.get("x", 0.0), pos_data.get("y", 0.0), pos_data.get("z", 0.0))

	return point
