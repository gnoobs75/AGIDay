class_name LineFormation
extends RefCounted
## LineFormation calculates positions for defensive line formations.

## Formation ID
var formation_id: int = -1

## Center position
var center: Vector3 = Vector3.ZERO

## Formation direction (facing direction)
var direction: Vector3 = Vector3.FORWARD

## Unit spacing
var spacing: float = 3.0

## Maximum line length
var max_line_length: float = 50.0

## Unit positions (unit_id -> target_position)
var _unit_positions: Dictionary = {}

## Units in formation
var _unit_ids: Array[int] = []

## Active flag
var is_active: bool = false


func _init(id: int = -1) -> void:
	formation_id = id


## Calculate line positions for units.
func calculate_positions(
	unit_ids: Array[int],
	target_center: Vector3,
	facing_direction: Vector3 = Vector3.FORWARD
) -> Dictionary:
	center = target_center
	direction = facing_direction.normalized() if facing_direction.length() > 0 else Vector3.FORWARD
	_unit_ids = unit_ids.duplicate()
	_unit_positions.clear()

	var unit_count := unit_ids.size()
	if unit_count == 0:
		return {}

	# Calculate perpendicular direction for line spread
	var perpendicular := direction.cross(Vector3.UP).normalized()
	if perpendicular.length_squared() < 0.01:
		perpendicular = Vector3.RIGHT

	# Calculate how many units per row based on max line length
	var units_per_row := int(max_line_length / spacing)
	units_per_row = maxi(1, units_per_row)

	# Calculate number of rows needed
	var row_count := ceili(float(unit_count) / float(units_per_row))

	var unit_index := 0
	for row in row_count:
		# Calculate units in this row
		var units_in_row := mini(units_per_row, unit_count - unit_index)

		# Calculate row width
		var row_width := (units_in_row - 1) * spacing

		# Calculate row offset (back rows behind front)
		var row_offset := direction * (-spacing * row)

		# Position units in row
		for i in units_in_row:
			var lateral_offset := (i - (units_in_row - 1) / 2.0) * spacing
			var position := center + row_offset + perpendicular * lateral_offset

			var unit_id: int = unit_ids[unit_index]
			_unit_positions[unit_id] = position
			unit_index += 1

	is_active = true
	return _unit_positions.duplicate()


## Get target position for unit.
func get_unit_position(unit_id: int) -> Vector3:
	return _unit_positions.get(unit_id, Vector3.INF)


## Check if unit is in formation.
func has_unit(unit_id: int) -> bool:
	return _unit_positions.has(unit_id)


## Remove unit from formation.
func remove_unit(unit_id: int) -> void:
	_unit_positions.erase(unit_id)
	_unit_ids.erase(unit_id)


## Get unit count.
func get_unit_count() -> int:
	return _unit_positions.size()


## Get all unit IDs.
func get_unit_ids() -> Array[int]:
	return _unit_ids.duplicate()


## Deactivate formation.
func deactivate() -> void:
	is_active = false
	_unit_positions.clear()
	_unit_ids.clear()


## Get formation bounds.
func get_bounds() -> Dictionary:
	if _unit_positions.is_empty():
		return {}

	var min_pos := Vector3.INF
	var max_pos := -Vector3.INF

	for unit_id in _unit_positions:
		var pos: Vector3 = _unit_positions[unit_id]
		min_pos.x = minf(min_pos.x, pos.x)
		min_pos.y = minf(min_pos.y, pos.y)
		min_pos.z = minf(min_pos.z, pos.z)
		max_pos.x = maxf(max_pos.x, pos.x)
		max_pos.y = maxf(max_pos.y, pos.y)
		max_pos.z = maxf(max_pos.z, pos.z)

	return {
		"min": min_pos,
		"max": max_pos,
		"center": (min_pos + max_pos) / 2.0,
		"size": max_pos - min_pos
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var positions_data: Dictionary = {}
	for unit_id in _unit_positions:
		var pos: Vector3 = _unit_positions[unit_id]
		positions_data[str(unit_id)] = {"x": pos.x, "y": pos.y, "z": pos.z}

	return {
		"formation_id": formation_id,
		"center": {"x": center.x, "y": center.y, "z": center.z},
		"direction": {"x": direction.x, "y": direction.y, "z": direction.z},
		"spacing": spacing,
		"max_line_length": max_line_length,
		"is_active": is_active,
		"unit_positions": positions_data,
		"unit_ids": _unit_ids.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> LineFormation:
	var formation := LineFormation.new(data.get("formation_id", -1))

	var center_data: Dictionary = data.get("center", {})
	formation.center = Vector3(
		center_data.get("x", 0),
		center_data.get("y", 0),
		center_data.get("z", 0)
	)

	var dir_data: Dictionary = data.get("direction", {})
	formation.direction = Vector3(
		dir_data.get("x", 0),
		dir_data.get("y", 0),
		dir_data.get("z", 1)
	)

	formation.spacing = data.get("spacing", 3.0)
	formation.max_line_length = data.get("max_line_length", 50.0)
	formation.is_active = data.get("is_active", false)

	formation._unit_ids.clear()
	for unit_id in data.get("unit_ids", []):
		formation._unit_ids.append(unit_id)

	formation._unit_positions.clear()
	for unit_id_str in data.get("unit_positions", {}):
		var pos_data: Dictionary = data["unit_positions"][unit_id_str]
		formation._unit_positions[int(unit_id_str)] = Vector3(
			pos_data.get("x", 0),
			pos_data.get("y", 0),
			pos_data.get("z", 0)
		)

	return formation
