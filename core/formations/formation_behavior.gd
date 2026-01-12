class_name FormationBehavior
extends RefCounted
## FormationBehavior tracks and calculates squad formation properties.

signal tightness_changed(old_value: float, new_value: float)
signal radius_changed(old_value: float, new_value: float)
signal center_moved(old_center: Vector3, new_center: Vector3)

## Formation types
enum FormationType {
	LOOSE_SWARM,     ## Spread out, mobile
	BALANCED_WEDGE,  ## Balanced offense/defense
	MOBILE_CIRCLE,   ## High mobility focus
	TIGHT_LINE       ## Maximum cohesion
}

## Priority types
enum FormationPriority {
	SPREAD_OUT,  ## Maximize distance between units
	BALANCED,    ## Balance spread and cohesion
	MOBILITY,    ## Prioritize movement speed
	COHESION     ## Minimize distance between units
}

## Squad center (average position)
var squad_center: Vector3 = Vector3.ZERO

## Squad radius (meters)
var squad_radius: float = 5.0

## Formation type
var formation_type: FormationType = FormationType.BALANCED_WEDGE

## Formation priority
var priority: FormationPriority = FormationPriority.BALANCED

## Formation tightness (0.0 = loose, 1.0 = tight)
var tightness: float = 0.5

## Target tightness for smooth transitions
var _target_tightness: float = 0.5

## Tightness transition speed
var _tightness_lerp_speed: float = 2.0

## Unit positions in formation
var _unit_positions: Dictionary = {}  ## unit_id -> Vector3

## Unit offsets from center
var _unit_offsets: Dictionary = {}  ## unit_id -> Vector3


func _init() -> void:
	pass


## Configure formation from faction settings.
func configure_for_faction(faction_id: String) -> void:
	match faction_id:
		"aether_swarm":
			formation_type = FormationType.LOOSE_SWARM
			squad_radius = 8.0
			priority = FormationPriority.SPREAD_OUT
			_target_tightness = 0.3
		"optiforge_legion", "glacius":
			formation_type = FormationType.BALANCED_WEDGE
			squad_radius = 6.0
			priority = FormationPriority.BALANCED
			_target_tightness = 0.5
		"dynapods", "dynapods_vanguard":
			formation_type = FormationType.MOBILE_CIRCLE
			squad_radius = 5.0
			priority = FormationPriority.MOBILITY
			_target_tightness = 0.4
		"logibots_colossus", "ferron_horde":
			formation_type = FormationType.TIGHT_LINE
			squad_radius = 4.0
			priority = FormationPriority.COHESION
			_target_tightness = 0.7
		_:
			formation_type = FormationType.BALANCED_WEDGE
			squad_radius = 5.0
			priority = FormationPriority.BALANCED
			_target_tightness = 0.5

	tightness = _target_tightness


## Update squad center from unit positions.
func update_center(positions: Dictionary) -> void:
	_unit_positions = positions.duplicate()

	if positions.is_empty():
		return

	var old_center := squad_center
	var sum := Vector3.ZERO

	for unit_id in positions:
		sum += positions[unit_id]

	squad_center = sum / float(positions.size())

	# Update offsets
	_unit_offsets.clear()
	for unit_id in positions:
		_unit_offsets[unit_id] = positions[unit_id] - squad_center

	if old_center.distance_to(squad_center) > 0.1:
		center_moved.emit(old_center, squad_center)


## Set formation tightness with smooth transition.
func set_tightness(value: float, immediate: bool = false) -> void:
	_target_tightness = clampf(value, 0.0, 1.0)

	if immediate:
		var old := tightness
		tightness = _target_tightness
		if absf(old - tightness) > 0.01:
			tightness_changed.emit(old, tightness)


## Update tightness based on threat level.
func update_tightness_from_threat(threat_level: float) -> void:
	if threat_level > 0.7:
		set_tightness(0.8)
	elif threat_level > 0.4:
		set_tightness(0.6)
	else:
		set_tightness(0.3)


## Update tightness based on casualty rate.
func update_tightness_from_casualties(casualty_rate: float) -> void:
	if casualty_rate > 0.3:
		set_tightness(0.8)
	elif casualty_rate > 0.15:
		set_tightness(0.6)
	else:
		set_tightness(0.3)


## Update formation (called each frame).
func update(delta: float) -> void:
	# Smooth tightness transition
	if absf(tightness - _target_tightness) > 0.001:
		var old := tightness
		tightness = lerpf(tightness, _target_tightness, _tightness_lerp_speed * delta)
		if absf(old - tightness) > 0.01:
			tightness_changed.emit(old, tightness)


## Calculate desired position for unit.
func get_desired_position(unit_id: int) -> Vector3:
	if not _unit_offsets.has(unit_id):
		return Vector3.INF

	var offset: Vector3 = _unit_offsets[unit_id]
	var normalized_offset := offset.normalized() if offset.length() > 0.1 else Vector3.ZERO

	# Apply tightness: high tightness = closer to center
	var effective_radius := squad_radius * (1.0 - tightness)
	var desired_offset := normalized_offset * effective_radius

	return squad_center + desired_offset


## Get all desired positions.
func get_all_desired_positions() -> Dictionary:
	var positions: Dictionary = {}

	for unit_id in _unit_offsets:
		positions[unit_id] = get_desired_position(unit_id)

	return positions


## Set squad radius.
func set_radius(value: float) -> void:
	var old := squad_radius
	squad_radius = maxf(1.0, value)
	if absf(old - squad_radius) > 0.1:
		radius_changed.emit(old, squad_radius)


## Get unit count.
func get_unit_count() -> int:
	return _unit_positions.size()


## Check if unit is in formation.
func has_unit(unit_id: int) -> bool:
	return _unit_positions.has(unit_id)


## Add unit to formation.
func add_unit(unit_id: int, position: Vector3) -> void:
	_unit_positions[unit_id] = position
	_unit_offsets[unit_id] = position - squad_center


## Remove unit from formation.
func remove_unit(unit_id: int) -> void:
	_unit_positions.erase(unit_id)
	_unit_offsets.erase(unit_id)


## Get formation bounds.
func get_bounds() -> Dictionary:
	if _unit_positions.is_empty():
		return {"min": squad_center, "max": squad_center, "size": Vector3.ZERO}

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
		"center": squad_center,
		"size": max_pos - min_pos
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var positions_data: Dictionary = {}
	for unit_id in _unit_positions:
		var pos: Vector3 = _unit_positions[unit_id]
		positions_data[str(unit_id)] = {"x": pos.x, "y": pos.y, "z": pos.z}

	return {
		"squad_center": {"x": squad_center.x, "y": squad_center.y, "z": squad_center.z},
		"squad_radius": squad_radius,
		"formation_type": formation_type,
		"priority": priority,
		"tightness": tightness,
		"target_tightness": _target_tightness,
		"unit_positions": positions_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	var center_data: Dictionary = data.get("squad_center", {})
	squad_center = Vector3(
		center_data.get("x", 0),
		center_data.get("y", 0),
		center_data.get("z", 0)
	)

	squad_radius = data.get("squad_radius", 5.0)
	formation_type = data.get("formation_type", FormationType.BALANCED_WEDGE)
	priority = data.get("priority", FormationPriority.BALANCED)
	tightness = data.get("tightness", 0.5)
	_target_tightness = data.get("target_tightness", 0.5)

	_unit_positions.clear()
	_unit_offsets.clear()
	for unit_id_str in data.get("unit_positions", {}):
		var pos_data: Dictionary = data["unit_positions"][unit_id_str]
		var pos := Vector3(pos_data.get("x", 0), pos_data.get("y", 0), pos_data.get("z", 0))
		_unit_positions[int(unit_id_str)] = pos
		_unit_offsets[int(unit_id_str)] = pos - squad_center


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"center": "%.1f, %.1f, %.1f" % [squad_center.x, squad_center.y, squad_center.z],
		"radius": "%.1fm" % squad_radius,
		"type": FormationType.keys()[formation_type],
		"tightness": "%.0f%%" % (tightness * 100),
		"units": _unit_positions.size()
	}
