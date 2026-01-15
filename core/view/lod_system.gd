class_name LODSystem
extends RefCounted
## LODSystem manages level of detail for distant units to reduce rendering load.
## Dynamically adjusts unit detail based on distance from camera.

signal lod_level_changed(unit_id: int, new_level: int)
signal lod_update_completed(units_updated: int)

## LOD levels
enum LODLevel {
	HIGH,      ## Full detail - 0-50 units
	MEDIUM,    ## Reduced detail - 50-100 units
	LOW,       ## Minimal detail - 100-200 units
	BILLBOARD  ## 2D sprite - 200+ units
}

## Distance thresholds
const LOD_DISTANCES := {
	LODLevel.HIGH: 50.0,
	LODLevel.MEDIUM: 100.0,
	LODLevel.LOW: 200.0,
	LODLevel.BILLBOARD: INF
}

## Configuration
const UPDATE_INTERVAL := 0.1          ## Seconds between LOD updates
const MAX_UPDATES_PER_FRAME := 100    ## Limit updates to prevent hitches
const HYSTERESIS := 5.0               ## Distance buffer to prevent flickering

## Camera reference
var _camera_position: Vector3 = Vector3.ZERO

## Unit LOD state
var _unit_lod_levels: Dictionary = {}  ## unit_id -> LODLevel
var _unit_positions: Dictionary = {}   ## unit_id -> Vector3

## Update timing
var _update_timer := 0.0
var _pending_updates: Array[int] = []
var _update_index := 0

## Statistics
var _lod_counts: Dictionary = {
	LODLevel.HIGH: 0,
	LODLevel.MEDIUM: 0,
	LODLevel.LOW: 0,
	LODLevel.BILLBOARD: 0
}


func _init() -> void:
	pass


## Update camera position.
func set_camera_position(position: Vector3) -> void:
	_camera_position = position


## Register unit for LOD management.
func register_unit(unit_id: int, position: Vector3) -> void:
	_unit_positions[unit_id] = position
	_unit_lod_levels[unit_id] = _calculate_lod_level(position)
	_update_lod_counts()


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	if _unit_lod_levels.has(unit_id):
		var old_level: LODLevel = _unit_lod_levels[unit_id]
		_lod_counts[old_level] = maxi(0, _lod_counts[old_level] - 1)

	_unit_positions.erase(unit_id)
	_unit_lod_levels.erase(unit_id)


## Update unit position.
func update_unit_position(unit_id: int, position: Vector3) -> void:
	_unit_positions[unit_id] = position

	if unit_id not in _pending_updates:
		_pending_updates.append(unit_id)


## Update LOD system (call each frame).
func update(delta: float) -> void:
	_update_timer += delta

	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_process_lod_updates()


## Process pending LOD updates.
func _process_lod_updates() -> void:
	# Add all units to pending if we need a full update
	if _pending_updates.is_empty():
		_pending_updates = _unit_positions.keys().duplicate()
		_update_index = 0

	var updates_done := 0
	var lod_changes := 0

	while _update_index < _pending_updates.size() and updates_done < MAX_UPDATES_PER_FRAME:
		var unit_id: int = _pending_updates[_update_index]
		_update_index += 1
		updates_done += 1

		if _unit_positions.has(unit_id):
			var changed := _update_unit_lod(unit_id)
			if changed:
				lod_changes += 1

	# Reset if we've processed all
	if _update_index >= _pending_updates.size():
		_pending_updates.clear()
		_update_index = 0

	if lod_changes > 0:
		_update_lod_counts()
		lod_update_completed.emit(lod_changes)


## Update LOD for single unit.
func _update_unit_lod(unit_id: int) -> bool:
	if not _unit_positions.has(unit_id):
		return false

	var position: Vector3 = _unit_positions[unit_id]
	var new_level := _calculate_lod_level(position)
	var old_level: LODLevel = _unit_lod_levels.get(unit_id, LODLevel.HIGH)

	# Apply hysteresis to prevent flickering
	if new_level != old_level:
		var threshold: float = LOD_DISTANCES[new_level]
		var distance := _camera_position.distance_to(position)

		# Only change if clearly past threshold (with hysteresis)
		if new_level > old_level:  # Going to lower detail
			if distance < threshold - HYSTERESIS:
				return false
		else:  # Going to higher detail
			if distance > threshold + HYSTERESIS:
				return false

		_unit_lod_levels[unit_id] = new_level
		lod_level_changed.emit(unit_id, new_level)
		return true

	return false


## Calculate LOD level for position.
func _calculate_lod_level(position: Vector3) -> LODLevel:
	var distance := _camera_position.distance_to(position)

	if distance < LOD_DISTANCES[LODLevel.HIGH]:
		return LODLevel.HIGH
	elif distance < LOD_DISTANCES[LODLevel.MEDIUM]:
		return LODLevel.MEDIUM
	elif distance < LOD_DISTANCES[LODLevel.LOW]:
		return LODLevel.LOW
	else:
		return LODLevel.BILLBOARD


## Update LOD count statistics.
func _update_lod_counts() -> void:
	for level in LODLevel.values():
		_lod_counts[level] = 0

	for unit_id in _unit_lod_levels:
		var level: LODLevel = _unit_lod_levels[unit_id]
		_lod_counts[level] += 1


## Get LOD level for unit.
func get_unit_lod(unit_id: int) -> LODLevel:
	return _unit_lod_levels.get(unit_id, LODLevel.HIGH)


## Get units at LOD level.
func get_units_at_lod(level: LODLevel) -> Array[int]:
	var result: Array[int] = []
	for unit_id in _unit_lod_levels:
		if _unit_lod_levels[unit_id] == level:
			result.append(unit_id)
	return result


## Get count at LOD level.
func get_count_at_lod(level: LODLevel) -> int:
	return _lod_counts.get(level, 0)


## Check if unit is visible (not culled).
func is_unit_visible(unit_id: int) -> bool:
	# All LOD levels are visible, just at different detail
	return _unit_lod_levels.has(unit_id)


## Get LOD level name.
static func get_lod_name(level: LODLevel) -> String:
	match level:
		LODLevel.HIGH: return "High"
		LODLevel.MEDIUM: return "Medium"
		LODLevel.LOW: return "Low"
		LODLevel.BILLBOARD: return "Billboard"
	return "Unknown"


## Get statistics.
func get_statistics() -> Dictionary:
	var total_units := _unit_positions.size()

	return {
		"total_units": total_units,
		"high_detail": _lod_counts[LODLevel.HIGH],
		"medium_detail": _lod_counts[LODLevel.MEDIUM],
		"low_detail": _lod_counts[LODLevel.LOW],
		"billboard": _lod_counts[LODLevel.BILLBOARD],
		"camera_position": _camera_position,
		"pending_updates": _pending_updates.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var lod_data := {}
	for unit_id in _unit_lod_levels:
		lod_data[str(unit_id)] = _unit_lod_levels[unit_id]

	return {
		"unit_lod_levels": lod_data,
		"camera_position": {
			"x": _camera_position.x,
			"y": _camera_position.y,
			"z": _camera_position.z
		}
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_lod_levels.clear()

	var lod_data: Dictionary = data.get("unit_lod_levels", {})
	for key in lod_data:
		_unit_lod_levels[int(key)] = lod_data[key]

	var pos: Dictionary = data.get("camera_position", {})
	_camera_position = Vector3(
		pos.get("x", 0.0),
		pos.get("y", 0.0),
		pos.get("z", 0.0)
	)

	_update_lod_counts()
