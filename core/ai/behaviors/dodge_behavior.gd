class_name DodgeBehavior
extends RefCounted
## DodgeBehavior predicts projectile trajectories and moves units to avoid.

signal dodge_triggered(unit_id: int, dodge_direction: Vector3)
signal dodge_completed(unit_id: int)
signal dodge_failed(unit_id: int, reason: String)

## Behavior tree status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Configuration
const DODGE_RANGE := 15.0  ## Range to detect incoming projectiles
const DODGE_RADIUS := 2.0  ## How close projectile must be to trigger dodge
const DODGE_DISTANCE := 3.0  ## How far to dodge
const DODGE_SPEED := 12.0  ## Movement speed during dodge
const DODGE_COOLDOWN := 1.0  ## Seconds between dodges
const PREDICTION_TIME := 0.5  ## Seconds to predict ahead
const MAX_PROJECTILES_TO_CHECK := 10

## Unit dodge states (unit_id -> state_data)
var _dodge_states: Dictionary = {}

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _get_nearby_projectiles: Callable  ## (position, radius) -> Array[Dictionary]
var _request_movement: Callable  ## (unit_id, direction, distance, speed) -> bool


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_nearby_projectiles(callback: Callable) -> void:
	_get_nearby_projectiles = callback


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback


## Execute dodge behavior for unit.
func execute(unit_id: int, delta: float) -> int:
	# Ensure state exists
	if not _dodge_states.has(unit_id):
		_dodge_states[unit_id] = {
			"is_dodging": false,
			"cooldown": 0.0,
			"dodge_direction": Vector3.ZERO,
			"dodge_progress": 0.0
		}

	var state: Dictionary = _dodge_states[unit_id]

	# Update cooldown
	if state["cooldown"] > 0:
		state["cooldown"] -= delta

	# If currently dodging, continue
	if state["is_dodging"]:
		return _continue_dodge(unit_id, delta)

	# Check if we should dodge
	if state["cooldown"] > 0:
		return Status.FAILURE

	if should_dodge(unit_id):
		return _start_dodge(unit_id)

	return Status.FAILURE


## Check if unit should dodge.
func should_dodge(unit_id: int) -> bool:
	if not _get_unit_position.is_valid() or not _get_nearby_projectiles.is_valid():
		return false

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	if unit_pos == Vector3.INF:
		return false

	# Get nearby projectiles
	var projectiles: Array = _get_nearby_projectiles.call(unit_pos, DODGE_RANGE)
	if projectiles.is_empty():
		return false

	# Check each projectile for collision prediction
	var count := 0
	for projectile in projectiles:
		if count >= MAX_PROJECTILES_TO_CHECK:
			break

		if _predict_collision(unit_pos, projectile):
			return true

		count += 1

	return false


## Predict if projectile will collide with unit.
func _predict_collision(unit_pos: Vector3, projectile: Dictionary) -> bool:
	var proj_pos: Vector3 = projectile.get("position", Vector3.INF)
	var proj_vel: Vector3 = projectile.get("velocity", Vector3.ZERO)

	if proj_pos == Vector3.INF or proj_vel.length_squared() < 0.1:
		return false

	# Predict future position
	var future_pos := proj_pos + proj_vel * PREDICTION_TIME

	# Check if trajectory passes near unit
	# Find closest point on trajectory to unit
	var to_unit := unit_pos - proj_pos
	var trajectory_dir := proj_vel.normalized()
	var projection_length := to_unit.dot(trajectory_dir)

	# Only check projectiles coming toward us
	if projection_length < 0:
		return false

	var closest_point := proj_pos + trajectory_dir * projection_length
	var distance := unit_pos.distance_to(closest_point)

	return distance < DODGE_RADIUS


## Calculate combined dodge direction from multiple projectiles.
func calculate_dodge_direction(unit_id: int) -> Vector3:
	if not _get_unit_position.is_valid() or not _get_nearby_projectiles.is_valid():
		return Vector3.ZERO

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	if unit_pos == Vector3.INF:
		return Vector3.ZERO

	var projectiles: Array = _get_nearby_projectiles.call(unit_pos, DODGE_RANGE)
	if projectiles.is_empty():
		return Vector3.ZERO

	var combined_direction := Vector3.ZERO
	var count := 0

	for projectile in projectiles:
		if count >= MAX_PROJECTILES_TO_CHECK:
			break

		if _predict_collision(unit_pos, projectile):
			var dodge_dir := _calculate_perpendicular_dodge(unit_pos, projectile)
			combined_direction += dodge_dir
			count += 1

	if combined_direction.length_squared() < 0.01:
		return Vector3.ZERO

	return combined_direction.normalized()


## Calculate perpendicular dodge direction for single projectile.
func _calculate_perpendicular_dodge(unit_pos: Vector3, projectile: Dictionary) -> Vector3:
	var proj_vel: Vector3 = projectile.get("velocity", Vector3.ZERO)
	if proj_vel.length_squared() < 0.1:
		return Vector3.ZERO

	# Get perpendicular direction (horizontal plane)
	var trajectory_dir := proj_vel.normalized()
	var perpendicular := Vector3(-trajectory_dir.z, 0, trajectory_dir.x)

	# Choose side based on which is further from projectile trajectory
	var proj_pos: Vector3 = projectile.get("position", Vector3.ZERO)
	var to_unit := (unit_pos - proj_pos).normalized()

	# Pick the side the unit is already on
	if to_unit.dot(perpendicular) < 0:
		perpendicular = -perpendicular

	return perpendicular


## Start dodge action.
func _start_dodge(unit_id: int) -> int:
	var state: Dictionary = _dodge_states[unit_id]
	var direction := calculate_dodge_direction(unit_id)

	if direction.length_squared() < 0.01:
		return Status.FAILURE

	state["is_dodging"] = true
	state["dodge_direction"] = direction
	state["dodge_progress"] = 0.0
	state["cooldown"] = DODGE_COOLDOWN

	# Request movement
	if _request_movement.is_valid():
		_request_movement.call(unit_id, direction, DODGE_DISTANCE, DODGE_SPEED)

	dodge_triggered.emit(unit_id, direction)

	return Status.RUNNING


## Continue dodge action.
func _continue_dodge(unit_id: int, delta: float) -> int:
	var state: Dictionary = _dodge_states[unit_id]

	# Update progress
	state["dodge_progress"] += delta * DODGE_SPEED / DODGE_DISTANCE

	if state["dodge_progress"] >= 1.0:
		state["is_dodging"] = false
		state["dodge_progress"] = 0.0
		dodge_completed.emit(unit_id)
		return Status.SUCCESS

	return Status.RUNNING


## Cancel dodge for unit.
func cancel_dodge(unit_id: int) -> void:
	if _dodge_states.has(unit_id):
		var state: Dictionary = _dodge_states[unit_id]
		if state["is_dodging"]:
			state["is_dodging"] = false
			state["dodge_progress"] = 0.0


## Check if unit is currently dodging.
func is_dodging(unit_id: int) -> bool:
	if not _dodge_states.has(unit_id):
		return false
	return _dodge_states[unit_id]["is_dodging"]


## Get dodge cooldown remaining.
func get_cooldown(unit_id: int) -> float:
	if not _dodge_states.has(unit_id):
		return 0.0
	return maxf(0.0, _dodge_states[unit_id]["cooldown"])


## Clear state for unit.
func clear_unit(unit_id: int) -> void:
	_dodge_states.erase(unit_id)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var states_data: Dictionary = {}
	for unit_id in _dodge_states:
		var state: Dictionary = _dodge_states[unit_id]
		states_data[str(unit_id)] = {
			"is_dodging": state["is_dodging"],
			"cooldown": state["cooldown"],
			"dodge_direction": {
				"x": state["dodge_direction"].x,
				"y": state["dodge_direction"].y,
				"z": state["dodge_direction"].z
			},
			"dodge_progress": state["dodge_progress"]
		}

	return {"dodge_states": states_data}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_dodge_states.clear()
	for unit_id_str in data.get("dodge_states", {}):
		var state_data: Dictionary = data["dodge_states"][unit_id_str]
		var dir_data: Dictionary = state_data.get("dodge_direction", {})
		_dodge_states[int(unit_id_str)] = {
			"is_dodging": state_data.get("is_dodging", false),
			"cooldown": state_data.get("cooldown", 0.0),
			"dodge_direction": Vector3(
				dir_data.get("x", 0),
				dir_data.get("y", 0),
				dir_data.get("z", 0)
			),
			"dodge_progress": state_data.get("dodge_progress", 0.0)
		}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var active_dodges := 0
	for unit_id in _dodge_states:
		if _dodge_states[unit_id]["is_dodging"]:
			active_dodges += 1

	return {
		"tracked_units": _dodge_states.size(),
		"active_dodges": active_dodges,
		"dodge_range": DODGE_RANGE,
		"dodge_radius": DODGE_RADIUS
	}
