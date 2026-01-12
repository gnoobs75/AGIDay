class_name FlankBehavior
extends RefCounted
## FlankBehavior calculates optimal flanking positions relative to targets.

signal flank_started(unit_id: int, target_id: int, flank_position: Vector3)
signal flank_reached(unit_id: int, target_id: int)
signal flank_cancelled(unit_id: int, reason: String)

## Behavior tree status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Flank side
enum FlankSide {
	LEFT,
	RIGHT,
	RANDOM
}

## Configuration
const FLANK_RANGE_MULTIPLIER := 1.5  ## Multiply attack range for flank distance
const MIN_FLANK_DISTANCE := 5.0
const MAX_FLANK_DISTANCE := 20.0
const FLANK_ARRIVAL_THRESHOLD := 2.0
const FLANK_TIMEOUT := 10.0  ## Seconds before flank attempt times out
const FLANK_SPEED_BONUS := 1.2  ## Movement speed bonus during flank

## Unit flank states (unit_id -> state_data)
var _flank_states: Dictionary = {}

## RNG for random flank side selection
var _rng := RandomNumberGenerator.new()

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _get_unit_attack_range: Callable  ## (unit_id) -> float
var _get_target_position: Callable  ## (target_id) -> Vector3
var _request_movement: Callable  ## (unit_id, target_position, speed_multiplier) -> bool
var _is_position_valid: Callable  ## (position) -> bool


func _init() -> void:
	_rng.randomize()


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_attack_range(callback: Callable) -> void:
	_get_unit_attack_range = callback


func set_get_target_position(callback: Callable) -> void:
	_get_target_position = callback


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback


func set_is_position_valid(callback: Callable) -> void:
	_is_position_valid = callback


## Execute flank behavior for unit.
func execute(unit_id: int, target_id: int, delta: float, preferred_side: int = FlankSide.RANDOM) -> int:
	# Ensure state exists
	if not _flank_states.has(unit_id):
		_flank_states[unit_id] = {
			"is_flanking": false,
			"target_id": -1,
			"flank_position": Vector3.ZERO,
			"flank_side": FlankSide.RANDOM,
			"elapsed_time": 0.0
		}

	var state: Dictionary = _flank_states[unit_id]

	# If not flanking or target changed, start new flank
	if not state["is_flanking"] or state["target_id"] != target_id:
		return _start_flank(unit_id, target_id, preferred_side)

	# Continue flanking
	return _continue_flank(unit_id, delta)


## Start flank action.
func _start_flank(unit_id: int, target_id: int, preferred_side: int) -> int:
	var flank_pos := calculate_flank_position(unit_id, target_id, preferred_side)
	if flank_pos == Vector3.INF:
		return Status.FAILURE

	var state: Dictionary = _flank_states[unit_id]
	state["is_flanking"] = true
	state["target_id"] = target_id
	state["flank_position"] = flank_pos
	state["flank_side"] = preferred_side
	state["elapsed_time"] = 0.0

	# Request movement to flank position
	if _request_movement.is_valid():
		_request_movement.call(unit_id, flank_pos, FLANK_SPEED_BONUS)

	flank_started.emit(unit_id, target_id, flank_pos)

	return Status.RUNNING


## Continue flank action.
func _continue_flank(unit_id: int, delta: float) -> int:
	var state: Dictionary = _flank_states[unit_id]

	# Update elapsed time
	state["elapsed_time"] += delta

	# Check for timeout
	if state["elapsed_time"] >= FLANK_TIMEOUT:
		_cancel_flank(unit_id, "timeout")
		return Status.FAILURE

	# Check if reached flank position
	if not _get_unit_position.is_valid():
		return Status.RUNNING

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	var flank_pos: Vector3 = state["flank_position"]

	var distance := unit_pos.distance_to(flank_pos)
	if distance <= FLANK_ARRIVAL_THRESHOLD:
		state["is_flanking"] = false
		flank_reached.emit(unit_id, state["target_id"])
		return Status.SUCCESS

	# Update flank position if target moved significantly
	if _get_target_position.is_valid():
		var target_pos: Vector3 = _get_target_position.call(state["target_id"])
		if target_pos != Vector3.INF:
			var expected_target := _estimate_target_from_flank(state["flank_position"], state["flank_side"])
			if target_pos.distance_to(expected_target) > 5.0:
				# Recalculate flank position
				var new_flank := calculate_flank_position(unit_id, state["target_id"], state["flank_side"])
				if new_flank != Vector3.INF:
					state["flank_position"] = new_flank
					if _request_movement.is_valid():
						_request_movement.call(unit_id, new_flank, FLANK_SPEED_BONUS)

	return Status.RUNNING


## Calculate optimal flank position.
func calculate_flank_position(unit_id: int, target_id: int, preferred_side: int = FlankSide.RANDOM) -> Vector3:
	if not _get_unit_position.is_valid() or not _get_target_position.is_valid():
		return Vector3.INF

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	var target_pos: Vector3 = _get_target_position.call(target_id)

	if unit_pos == Vector3.INF or target_pos == Vector3.INF:
		return Vector3.INF

	# Get attack range
	var attack_range := 10.0
	if _get_unit_attack_range.is_valid():
		attack_range = _get_unit_attack_range.call(unit_id)

	# Calculate flank distance
	var flank_distance := clampf(attack_range * FLANK_RANGE_MULTIPLIER, MIN_FLANK_DISTANCE, MAX_FLANK_DISTANCE)

	# Calculate direction from unit to target
	var to_target := (target_pos - unit_pos).normalized()

	# Calculate perpendicular direction (horizontal plane)
	var perpendicular := Vector3(-to_target.z, 0, to_target.x)

	# Choose side
	var side := preferred_side
	if side == FlankSide.RANDOM:
		side = FlankSide.LEFT if _rng.randf() < 0.5 else FlankSide.RIGHT

	if side == FlankSide.LEFT:
		perpendicular = -perpendicular

	# Calculate flank position
	var flank_pos := target_pos + perpendicular * flank_distance

	# Validate position
	if _is_position_valid.is_valid():
		if not _is_position_valid.call(flank_pos):
			# Try other side
			flank_pos = target_pos - perpendicular * flank_distance
			if not _is_position_valid.call(flank_pos):
				return Vector3.INF

	return flank_pos


## Estimate target position from flank position and side.
func _estimate_target_from_flank(flank_pos: Vector3, side: int) -> Vector3:
	# Rough estimation for target movement detection
	return flank_pos


## Cancel flank for unit.
func _cancel_flank(unit_id: int, reason: String) -> void:
	if _flank_states.has(unit_id):
		var state: Dictionary = _flank_states[unit_id]
		state["is_flanking"] = false
		flank_cancelled.emit(unit_id, reason)


## Cancel flank externally.
func cancel_flank(unit_id: int) -> void:
	_cancel_flank(unit_id, "cancelled")


## Check if unit is currently flanking.
func is_flanking(unit_id: int) -> bool:
	if not _flank_states.has(unit_id):
		return false
	return _flank_states[unit_id]["is_flanking"]


## Get flank target for unit.
func get_flank_target(unit_id: int) -> int:
	if not _flank_states.has(unit_id):
		return -1
	if not _flank_states[unit_id]["is_flanking"]:
		return -1
	return _flank_states[unit_id]["target_id"]


## Get flank position for unit.
func get_flank_position(unit_id: int) -> Vector3:
	if not _flank_states.has(unit_id):
		return Vector3.INF
	if not _flank_states[unit_id]["is_flanking"]:
		return Vector3.INF
	return _flank_states[unit_id]["flank_position"]


## Clear state for unit.
func clear_unit(unit_id: int) -> void:
	_flank_states.erase(unit_id)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var states_data: Dictionary = {}
	for unit_id in _flank_states:
		var state: Dictionary = _flank_states[unit_id]
		var flank_pos: Vector3 = state["flank_position"]
		states_data[str(unit_id)] = {
			"is_flanking": state["is_flanking"],
			"target_id": state["target_id"],
			"flank_position": {"x": flank_pos.x, "y": flank_pos.y, "z": flank_pos.z},
			"flank_side": state["flank_side"],
			"elapsed_time": state["elapsed_time"]
		}

	return {
		"flank_states": states_data,
		"rng_state": _rng.state
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_flank_states.clear()
	for unit_id_str in data.get("flank_states", {}):
		var state_data: Dictionary = data["flank_states"][unit_id_str]
		var pos_data: Dictionary = state_data.get("flank_position", {})
		_flank_states[int(unit_id_str)] = {
			"is_flanking": state_data.get("is_flanking", false),
			"target_id": state_data.get("target_id", -1),
			"flank_position": Vector3(
				pos_data.get("x", 0),
				pos_data.get("y", 0),
				pos_data.get("z", 0)
			),
			"flank_side": state_data.get("flank_side", FlankSide.RANDOM),
			"elapsed_time": state_data.get("elapsed_time", 0.0)
		}

	if data.has("rng_state"):
		_rng.state = data["rng_state"]


## Get summary for debugging.
func get_summary() -> Dictionary:
	var active_flanks := 0
	for unit_id in _flank_states:
		if _flank_states[unit_id]["is_flanking"]:
			active_flanks += 1

	return {
		"tracked_units": _flank_states.size(),
		"active_flanks": active_flanks,
		"flank_range_multiplier": FLANK_RANGE_MULTIPLIER,
		"flank_timeout": FLANK_TIMEOUT
	}
