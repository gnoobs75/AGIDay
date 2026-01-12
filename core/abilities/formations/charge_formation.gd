class_name ChargeFormation
extends RefCounted
## ChargeFormation calculates positions for aggressive wedge/charge formations.

## Formation ID
var formation_id: int = -1

## Charge target position
var target: Vector3 = Vector3.ZERO

## Formation origin
var origin: Vector3 = Vector3.ZERO

## Unit spacing
var spacing: float = 2.5

## Wedge angle in radians
var wedge_angle: float = PI / 6.0  ## 30 degrees

## Unit positions (unit_id -> target_position)
var _unit_positions: Dictionary = {}

## Units in formation
var _unit_ids: Array[int] = []

## Active flag
var is_active: bool = false


func _init(id: int = -1) -> void:
	formation_id = id


## Calculate wedge positions for charging units.
func calculate_positions(
	unit_ids: Array[int],
	charge_target: Vector3,
	charge_origin: Vector3
) -> Dictionary:
	target = charge_target
	origin = charge_origin
	_unit_ids = unit_ids.duplicate()
	_unit_positions.clear()

	var unit_count := unit_ids.size()
	if unit_count == 0:
		return {}

	# Calculate charge direction
	var charge_dir := (target - origin).normalized()
	if charge_dir.length_squared() < 0.01:
		charge_dir = Vector3.FORWARD

	# Calculate perpendicular direction for wedge spread
	var perpendicular := charge_dir.cross(Vector3.UP).normalized()
	if perpendicular.length_squared() < 0.01:
		perpendicular = Vector3.RIGHT

	# Position units in wedge formation
	# First unit is at the tip, others spread behind in V-shape
	var tip_position := origin + charge_dir * spacing

	for i in unit_count:
		var unit_id: int = unit_ids[i]

		if i == 0:
			# Leader at tip of wedge
			_unit_positions[unit_id] = tip_position
		else:
			# Calculate position behind and to the side
			var row := (i + 1) / 2  ## Row number (1, 1, 2, 2, 3, 3, ...)
			var side := 1 if i % 2 == 1 else -1  ## Alternate sides

			var back_offset := charge_dir * (-spacing * row)
			var side_offset := perpendicular * (spacing * row * tan(wedge_angle) * side)

			_unit_positions[unit_id] = tip_position + back_offset + side_offset

	is_active = true
	return _unit_positions.duplicate()


## Update formation positions during charge.
func update_charge(delta: float, charge_speed: float) -> Dictionary:
	if not is_active or _unit_positions.is_empty():
		return {}

	# Calculate charge direction
	var charge_dir := (target - origin).normalized()

	# Move all positions forward
	var movement := charge_dir * charge_speed * delta
	origin += movement

	for unit_id in _unit_positions:
		_unit_positions[unit_id] += movement

	# Check if reached target
	if origin.distance_to(target) < spacing:
		is_active = false

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


## Get charge progress (0.0 to 1.0).
func get_charge_progress() -> float:
	var total_distance := origin.distance_to(target)
	if total_distance < 0.1:
		return 1.0

	var leader_pos := Vector3.ZERO
	if not _unit_positions.is_empty():
		for unit_id in _unit_positions:
			leader_pos = _unit_positions[unit_id]
			break

	var remaining := leader_pos.distance_to(target)
	return 1.0 - clampf(remaining / total_distance, 0.0, 1.0)


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
		"target": {"x": target.x, "y": target.y, "z": target.z},
		"origin": {"x": origin.x, "y": origin.y, "z": origin.z},
		"spacing": spacing,
		"wedge_angle": wedge_angle,
		"is_active": is_active,
		"unit_positions": positions_data,
		"unit_ids": _unit_ids.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> ChargeFormation:
	var formation := ChargeFormation.new(data.get("formation_id", -1))

	var target_data: Dictionary = data.get("target", {})
	formation.target = Vector3(
		target_data.get("x", 0),
		target_data.get("y", 0),
		target_data.get("z", 0)
	)

	var origin_data: Dictionary = data.get("origin", {})
	formation.origin = Vector3(
		origin_data.get("x", 0),
		origin_data.get("y", 0),
		origin_data.get("z", 0)
	)

	formation.spacing = data.get("spacing", 2.5)
	formation.wedge_angle = data.get("wedge_angle", PI / 6.0)
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
