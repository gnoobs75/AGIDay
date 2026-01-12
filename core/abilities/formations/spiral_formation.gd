class_name SpiralFormation
extends RefCounted
## SpiralFormation calculates positions for spiral formation patterns.

## Formation ID
var formation_id: int = -1

## Center position
var center: Vector3 = Vector3.ZERO

## Base radius
var base_radius: float = 10.0

## Units per ring
var units_per_ring: int = 20

## Ring radius expansion
var ring_expansion: float = 2.0

## Rotation speed (radians per second)
var rotation_speed: float = 0.5

## Current rotation angle
var current_rotation: float = 0.0

## Active flag
var is_active: bool = false

## Unit positions (unit_id -> target_position)
var _unit_positions: Dictionary = {}

## Units in formation
var _unit_ids: Array[int] = []


func _init(id: int = -1) -> void:
	formation_id = id


## Calculate spiral positions for units.
func calculate_positions(unit_ids: Array[int], target_center: Vector3) -> Dictionary:
	center = target_center
	_unit_ids = unit_ids.duplicate()
	_unit_positions.clear()

	var unit_count := unit_ids.size()
	if unit_count == 0:
		return {}

	# Calculate how many rings needed
	var units_placed := 0
	var ring := 0

	while units_placed < unit_count:
		var ring_radius := base_radius + (ring * ring_expansion)
		var units_in_ring := mini(units_per_ring, unit_count - units_placed)

		# Place units in this ring
		for i in units_in_ring:
			var angle := (TAU / units_in_ring) * i + current_rotation
			var offset := Vector3(
				cos(angle) * ring_radius,
				0.0,
				sin(angle) * ring_radius
			)

			var unit_id: int = unit_ids[units_placed]
			_unit_positions[unit_id] = center + offset
			units_placed += 1

		ring += 1

	is_active = true
	return _unit_positions.duplicate()


## Update rotation (for spinning spiral).
func update_rotation(delta: float) -> Dictionary:
	if not is_active:
		return {}

	current_rotation += rotation_speed * delta

	# Recalculate positions with new rotation
	return calculate_positions(_unit_ids, center)


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


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var positions_data: Dictionary = {}
	for unit_id in _unit_positions:
		var pos: Vector3 = _unit_positions[unit_id]
		positions_data[str(unit_id)] = {"x": pos.x, "y": pos.y, "z": pos.z}

	return {
		"formation_id": formation_id,
		"center": {"x": center.x, "y": center.y, "z": center.z},
		"base_radius": base_radius,
		"units_per_ring": units_per_ring,
		"ring_expansion": ring_expansion,
		"rotation_speed": rotation_speed,
		"current_rotation": current_rotation,
		"is_active": is_active,
		"unit_positions": positions_data,
		"unit_ids": _unit_ids.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> SpiralFormation:
	var formation := SpiralFormation.new(data.get("formation_id", -1))

	var center_data: Dictionary = data.get("center", {})
	formation.center = Vector3(
		center_data.get("x", 0),
		center_data.get("y", 0),
		center_data.get("z", 0)
	)

	formation.base_radius = data.get("base_radius", 10.0)
	formation.units_per_ring = data.get("units_per_ring", 20)
	formation.ring_expansion = data.get("ring_expansion", 2.0)
	formation.rotation_speed = data.get("rotation_speed", 0.5)
	formation.current_rotation = data.get("current_rotation", 0.0)
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
