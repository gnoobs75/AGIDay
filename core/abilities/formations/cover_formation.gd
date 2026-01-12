class_name CoverFormation
extends RefCounted
## CoverFormation calculates positions for defensive cover formations.

## Formation ID
var formation_id: int = -1

## Center position
var center: Vector3 = Vector3.ZERO

## Formation direction (facing threat)
var direction: Vector3 = Vector3.FORWARD

## Unit spacing
var spacing: float = 2.0

## Formation depth (rows)
var depth: int = 2

## Unit positions (unit_id -> target_position)
var _unit_positions: Dictionary = {}

## Units in formation
var _unit_ids: Array[int] = []

## Cover points (optional cover positions)
var _cover_points: Array[Vector3] = []

## Active flag
var is_active: bool = false


func _init(id: int = -1) -> void:
	formation_id = id


## Set available cover points.
func set_cover_points(points: Array[Vector3]) -> void:
	_cover_points = points.duplicate()


## Calculate cover positions for units.
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

	# If cover points available, use them
	if not _cover_points.is_empty():
		return _calculate_cover_point_positions(unit_ids)

	# Otherwise create staggered defensive formation
	return _calculate_staggered_positions(unit_ids)


## Calculate positions using cover points.
func _calculate_cover_point_positions(unit_ids: Array[int]) -> Dictionary:
	# Sort cover points by distance to center
	var sorted_points: Array[Dictionary] = []
	for point in _cover_points:
		sorted_points.append({
			"point": point,
			"distance": point.distance_to(center)
		})

	sorted_points.sort_custom(func(a, b): return a["distance"] < b["distance"])

	# Assign units to nearest cover points
	var unit_index := 0
	for point_data in sorted_points:
		if unit_index >= unit_ids.size():
			break

		var unit_id: int = unit_ids[unit_index]
		_unit_positions[unit_id] = point_data["point"]
		unit_index += 1

	# Remaining units use staggered positions
	if unit_index < unit_ids.size():
		var remaining: Array[int] = []
		for i in range(unit_index, unit_ids.size()):
			remaining.append(unit_ids[i])
		_add_staggered_positions(remaining, _unit_positions.size())

	is_active = true
	return _unit_positions.duplicate()


## Calculate staggered defensive positions.
func _calculate_staggered_positions(unit_ids: Array[int]) -> Dictionary:
	var unit_count := unit_ids.size()

	# Calculate perpendicular direction for spread
	var perpendicular := direction.cross(Vector3.UP).normalized()
	if perpendicular.length_squared() < 0.01:
		perpendicular = Vector3.RIGHT

	# Calculate units per row
	var units_per_row := ceili(float(unit_count) / float(depth))

	var unit_index := 0
	for row in depth:
		var units_in_row := mini(units_per_row, unit_count - unit_index)
		if units_in_row <= 0:
			break

		# Calculate row width
		var row_width := (units_in_row - 1) * spacing

		# Row offset (back rows behind front)
		var row_offset := direction * (-spacing * 1.5 * row)

		# Stagger offset for back rows
		var stagger_offset := perpendicular * (spacing * 0.5) if row % 2 == 1 else Vector3.ZERO

		# Position units in row
		for i in units_in_row:
			var lateral_offset := (i - (units_in_row - 1) / 2.0) * spacing
			var position := center + row_offset + perpendicular * lateral_offset + stagger_offset

			var unit_id: int = unit_ids[unit_index]
			_unit_positions[unit_id] = position
			unit_index += 1

	is_active = true
	return _unit_positions.duplicate()


## Add staggered positions for remaining units.
func _add_staggered_positions(unit_ids: Array[int], start_index: int) -> void:
	var perpendicular := direction.cross(Vector3.UP).normalized()
	if perpendicular.length_squared() < 0.01:
		perpendicular = Vector3.RIGHT

	for i in unit_ids.size():
		var row := (start_index + i) / 5
		var col := (start_index + i) % 5

		var row_offset := direction * (-spacing * 1.5 * (depth + row))
		var lateral_offset := (col - 2) * spacing
		var stagger_offset := perpendicular * (spacing * 0.5) if row % 2 == 1 else Vector3.ZERO

		var position := center + row_offset + perpendicular * lateral_offset + stagger_offset
		_unit_positions[unit_ids[i]] = position


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


## Get defensive bonus based on formation integrity.
func get_defensive_bonus() -> float:
	if not is_active:
		return 1.0

	# Bonus scales with number of units in formation
	var unit_count := _unit_positions.size()
	if unit_count < 3:
		return 1.0

	# 10% bonus per 5 units, up to 50%
	var bonus := minf(0.5, (unit_count / 5) * 0.1)
	return 1.0 + bonus


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

	var cover_data: Array[Dictionary] = []
	for point in _cover_points:
		cover_data.append({"x": point.x, "y": point.y, "z": point.z})

	return {
		"formation_id": formation_id,
		"center": {"x": center.x, "y": center.y, "z": center.z},
		"direction": {"x": direction.x, "y": direction.y, "z": direction.z},
		"spacing": spacing,
		"depth": depth,
		"is_active": is_active,
		"unit_positions": positions_data,
		"unit_ids": _unit_ids.duplicate(),
		"cover_points": cover_data
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> CoverFormation:
	var formation := CoverFormation.new(data.get("formation_id", -1))

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

	formation.spacing = data.get("spacing", 2.0)
	formation.depth = data.get("depth", 2)
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

	formation._cover_points.clear()
	for point_data in data.get("cover_points", []):
		formation._cover_points.append(Vector3(
			point_data.get("x", 0),
			point_data.get("y", 0),
			point_data.get("z", 0)
		))

	return formation
