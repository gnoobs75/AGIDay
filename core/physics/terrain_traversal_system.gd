class_name TerrainTraversalSystem
extends RefCounted
## TerrainTraversalSystem enables vaulting and leaping over terrain obstacles.

signal vault_started(unit_id: int, obstacle_height: float)
signal vault_completed(unit_id: int)
signal leap_started(unit_id: int, distance: float)
signal leap_completed(unit_id: int)
signal traversal_failed(unit_id: int, reason: String)

## Configuration
const MAX_VAULT_HEIGHT := 5.0  ## meters
const MAX_VAULT_DISTANCE := 8.0  ## meters
const VAULT_SPEED := 10.0
const LEAP_HEIGHT := 3.0
const LEAP_SPEED := 12.0
const OBSTACLE_DETECTION_RANGE := 3.0
const AUTO_VAULT_ENABLED := true

## Traversal states
enum TraversalState {
	NONE,
	VAULTING,
	LEAPING
}

## Unit traversal data (unit_id -> traversal_data)
var _unit_traversals: Dictionary = {}

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _raycast_obstacle: Callable  ## (from, direction, distance) -> Dictionary
var _set_unit_position: Callable  ## (unit_id, position) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_raycast_obstacle(callback: Callable) -> void:
	_raycast_obstacle = callback


func set_unit_position(callback: Callable) -> void:
	_set_unit_position = callback


## Check for obstacles and auto-vault if needed.
func check_auto_vault(unit_id: int, movement_direction: Vector3) -> bool:
	if not AUTO_VAULT_ENABLED:
		return false

	if is_traversing(unit_id):
		return false

	var obstacle := _detect_obstacle(unit_id, movement_direction)
	if obstacle.is_empty():
		return false

	var height: float = obstacle.get("height", 0.0)
	if height > 0 and height <= MAX_VAULT_HEIGHT:
		return start_vault(unit_id, obstacle)

	return false


## Detect obstacle in movement direction.
func _detect_obstacle(unit_id: int, direction: Vector3) -> Dictionary:
	if not _get_unit_position.is_valid() or not _raycast_obstacle.is_valid():
		return {}

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	if unit_pos == Vector3.INF:
		return {}

	# Cast ray forward
	var hit: Dictionary = _raycast_obstacle.call(
		unit_pos + Vector3.UP * 0.5,
		direction.normalized(),
		OBSTACLE_DETECTION_RANGE
	)

	if hit.is_empty():
		return {}

	# Check if we can vault over
	var obstacle_top: Vector3 = hit.get("position", Vector3.ZERO)

	# Cast ray up to find top of obstacle
	var up_hit: Dictionary = _raycast_obstacle.call(
		obstacle_top,
		Vector3.UP,
		MAX_VAULT_HEIGHT
	)

	var height := MAX_VAULT_HEIGHT
	if not up_hit.is_empty():
		height = up_hit.get("distance", MAX_VAULT_HEIGHT)

	return {
		"position": hit.get("position", Vector3.ZERO),
		"height": height,
		"normal": hit.get("normal", Vector3.UP),
		"direction": direction
	}


## Start vault over obstacle.
func start_vault(unit_id: int, obstacle: Dictionary) -> bool:
	if is_traversing(unit_id):
		return false

	var height: float = obstacle.get("height", 0.0)
	if height <= 0 or height > MAX_VAULT_HEIGHT:
		traversal_failed.emit(unit_id, "obstacle_too_high")
		return false

	var direction: Vector3 = obstacle.get("direction", Vector3.FORWARD)

	_unit_traversals[unit_id] = {
		"state": TraversalState.VAULTING,
		"progress": 0.0,
		"start_position": Vector3.ZERO,
		"end_position": Vector3.ZERO,
		"peak_position": Vector3.ZERO,
		"height": height,
		"direction": direction,
		"duration": 0.0
	}

	# Calculate positions
	if _get_unit_position.is_valid():
		var start: Vector3 = _get_unit_position.call(unit_id)
		var data: Dictionary = _unit_traversals[unit_id]

		data["start_position"] = start
		data["peak_position"] = start + Vector3.UP * (height + 0.5) + direction * 0.5
		data["end_position"] = start + direction * minf(MAX_VAULT_DISTANCE, height * 2.0)
		data["duration"] = height / VAULT_SPEED + 0.3

	vault_started.emit(unit_id, height)
	return true


## Start leap action.
func start_leap(unit_id: int, target_position: Vector3) -> bool:
	if is_traversing(unit_id):
		return false

	if not _get_unit_position.is_valid():
		return false

	var start: Vector3 = _get_unit_position.call(unit_id)
	if start == Vector3.INF:
		return false

	var distance := start.distance_to(target_position)

	_unit_traversals[unit_id] = {
		"state": TraversalState.LEAPING,
		"progress": 0.0,
		"start_position": start,
		"end_position": target_position,
		"peak_position": (start + target_position) / 2.0 + Vector3.UP * LEAP_HEIGHT,
		"height": LEAP_HEIGHT,
		"direction": (target_position - start).normalized(),
		"duration": distance / LEAP_SPEED
	}

	leap_started.emit(unit_id, distance)
	return true


## Update all traversals.
func update(delta: float) -> void:
	var completed: Array[int] = []

	for unit_id in _unit_traversals:
		var data: Dictionary = _unit_traversals[unit_id]

		# Update progress
		if data["duration"] > 0:
			data["progress"] += delta / data["duration"]
		else:
			data["progress"] = 1.0

		# Calculate current position using bezier curve
		var position := _calculate_traversal_position(data)

		# Apply position
		if _set_unit_position.is_valid():
			_set_unit_position.call(unit_id, position)

		# Check completion
		if data["progress"] >= 1.0:
			completed.append(unit_id)

	# Handle completed traversals
	for unit_id in completed:
		_complete_traversal(unit_id)


## Calculate position along traversal arc.
func _calculate_traversal_position(data: Dictionary) -> Vector3:
	var t: float = clampf(data["progress"], 0.0, 1.0)
	var start: Vector3 = data["start_position"]
	var peak: Vector3 = data["peak_position"]
	var end_pos: Vector3 = data["end_position"]

	# Quadratic bezier curve
	var q0 := start.lerp(peak, t)
	var q1 := peak.lerp(end_pos, t)

	return q0.lerp(q1, t)


## Complete traversal.
func _complete_traversal(unit_id: int) -> void:
	if not _unit_traversals.has(unit_id):
		return

	var data: Dictionary = _unit_traversals[unit_id]
	var state: int = data["state"]

	# Set final position
	if _set_unit_position.is_valid():
		_set_unit_position.call(unit_id, data["end_position"])

	_unit_traversals.erase(unit_id)

	match state:
		TraversalState.VAULTING:
			vault_completed.emit(unit_id)
		TraversalState.LEAPING:
			leap_completed.emit(unit_id)


## Cancel traversal.
func cancel_traversal(unit_id: int) -> void:
	if _unit_traversals.has(unit_id):
		_unit_traversals.erase(unit_id)


## Check if unit is traversing.
func is_traversing(unit_id: int) -> bool:
	return _unit_traversals.has(unit_id)


## Get traversal state for unit.
func get_traversal_state(unit_id: int) -> int:
	if not _unit_traversals.has(unit_id):
		return TraversalState.NONE
	return _unit_traversals[unit_id]["state"]


## Get traversal progress (0.0 to 1.0).
func get_traversal_progress(unit_id: int) -> float:
	if not _unit_traversals.has(unit_id):
		return 0.0
	return _unit_traversals[unit_id]["progress"]


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var traversals_data: Dictionary = {}
	for unit_id in _unit_traversals:
		var data: Dictionary = _unit_traversals[unit_id]
		traversals_data[str(unit_id)] = {
			"state": data["state"],
			"progress": data["progress"],
			"start_position": _vec3_to_dict(data["start_position"]),
			"end_position": _vec3_to_dict(data["end_position"]),
			"peak_position": _vec3_to_dict(data["peak_position"]),
			"height": data["height"],
			"direction": _vec3_to_dict(data["direction"]),
			"duration": data["duration"]
		}

	return {"unit_traversals": traversals_data}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_traversals.clear()
	for unit_id_str in data.get("unit_traversals", {}):
		var tdata: Dictionary = data["unit_traversals"][unit_id_str]
		_unit_traversals[int(unit_id_str)] = {
			"state": tdata.get("state", TraversalState.NONE),
			"progress": tdata.get("progress", 0.0),
			"start_position": _dict_to_vec3(tdata.get("start_position", {})),
			"end_position": _dict_to_vec3(tdata.get("end_position", {})),
			"peak_position": _dict_to_vec3(tdata.get("peak_position", {})),
			"height": tdata.get("height", 0.0),
			"direction": _dict_to_vec3(tdata.get("direction", {})),
			"duration": tdata.get("duration", 0.0)
		}


func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func _dict_to_vec3(d: Dictionary) -> Vector3:
	return Vector3(d.get("x", 0), d.get("y", 0), d.get("z", 0))


## Get summary for debugging.
func get_summary() -> Dictionary:
	var vaulting := 0
	var leaping := 0

	for unit_id in _unit_traversals:
		match _unit_traversals[unit_id]["state"]:
			TraversalState.VAULTING:
				vaulting += 1
			TraversalState.LEAPING:
				leaping += 1

	return {
		"active_traversals": _unit_traversals.size(),
		"vaulting": vaulting,
		"leaping": leaping,
		"max_vault_height": MAX_VAULT_HEIGHT,
		"max_vault_distance": MAX_VAULT_DISTANCE
	}
