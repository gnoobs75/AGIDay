class_name DynapodsPhysicsSystem
extends RefCounted
## DynapodsPhysicsSystem manages momentum physics for Dynapods faction units.
## Optimized for 400+ units at 60fps with <4ms frame budget.

signal physics_updated(unit_count: int, elapsed_ms: float)
signal unit_physics_frozen(unit_id: int)
signal unit_physics_unfrozen(unit_id: int)

## Performance settings
const MAX_FRAME_TIME_MS := 4.0
const TARGET_FPS := 60.0
const FREEZE_DISTANCE := 100.0  ## Distance from camera to freeze physics
const BATCH_SIZE := 50  ## Units processed per batch
const UPDATE_PRIORITY_THRESHOLD := 30.0  ## Distance for priority updates

## Sub-systems
var momentum_controller: MomentumPhysicsController = null
var terrain_traversal: TerrainTraversalSystem = null

## Unit registration (unit_id -> unit_data)
var _units: Dictionary = {}

## Frozen units (unit_id -> true)
var _frozen_units: Dictionary = {}

## Camera position for distance calculations
var _camera_position: Vector3 = Vector3.ZERO

## Update batch tracking
var _current_batch_start: int = 0

## Frame timing
var _last_frame_time_ms: float = 0.0

## Callbacks
var _get_unit_position: Callable
var _set_unit_position: Callable
var _raycast_obstacle: Callable


func _init() -> void:
	momentum_controller = MomentumPhysicsController.new()
	terrain_traversal = TerrainTraversalSystem.new()


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback
	terrain_traversal.set_get_unit_position(callback)


func set_unit_position(callback: Callable) -> void:
	_set_unit_position = callback
	terrain_traversal.set_unit_position(callback)


func set_raycast_obstacle(callback: Callable) -> void:
	_raycast_obstacle = callback
	terrain_traversal.set_raycast_obstacle(callback)


## Set camera position for distance-based optimization.
func set_camera_position(position: Vector3) -> void:
	_camera_position = position


## Register unit with physics system.
func register_unit(unit_id: int, unit_type: String = "default") -> void:
	_units[unit_id] = {
		"type": unit_type,
		"last_update_frame": 0,
		"priority": false
	}

	momentum_controller.register_unit(unit_id, unit_type)


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_units.erase(unit_id)
	_frozen_units.erase(unit_id)
	momentum_controller.unregister_unit(unit_id)
	terrain_traversal.cancel_traversal(unit_id)


## Update physics system.
func update(delta: float, frame_number: int) -> void:
	var start_time := Time.get_ticks_usec()

	# Update frozen states based on camera distance
	_update_frozen_states()

	# Get list of active (non-frozen) units
	var active_units := _get_active_units()

	# Process in batches to respect frame budget
	var processed := 0
	var batch_start := _current_batch_start

	while processed < active_units.size():
		# Check frame budget
		var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed >= MAX_FRAME_TIME_MS:
			break

		var unit_id: int = active_units[processed]

		# Skip if frozen
		if _frozen_units.has(unit_id):
			processed += 1
			continue

		# Update momentum physics
		var velocity := momentum_controller.update_unit(unit_id, delta)

		# Apply velocity to position
		_apply_velocity(unit_id, velocity, delta)

		# Check for terrain traversal (auto-vault)
		if velocity.length() > 0.1:
			terrain_traversal.check_auto_vault(unit_id, velocity.normalized())

		# Mark as updated
		_units[unit_id]["last_update_frame"] = frame_number

		processed += 1

	# Update terrain traversal (always runs for active traversals)
	terrain_traversal.update(delta)

	# Track for next frame
	_current_batch_start = (batch_start + processed) % maxi(1, active_units.size())

	_last_frame_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
	physics_updated.emit(_units.size(), _last_frame_time_ms)


## Update frozen states based on camera distance.
func _update_frozen_states() -> void:
	if not _get_unit_position.is_valid():
		return

	for unit_id in _units:
		var pos: Vector3 = _get_unit_position.call(unit_id)
		if pos == Vector3.INF:
			continue

		var distance := _camera_position.distance_to(pos)
		var was_frozen := _frozen_units.has(unit_id)

		if distance > FREEZE_DISTANCE:
			if not was_frozen:
				_frozen_units[unit_id] = true
				unit_physics_frozen.emit(unit_id)
		else:
			if was_frozen:
				_frozen_units.erase(unit_id)
				unit_physics_unfrozen.emit(unit_id)

		# Update priority
		_units[unit_id]["priority"] = distance < UPDATE_PRIORITY_THRESHOLD


## Get active (non-frozen) units sorted by priority.
func _get_active_units() -> Array[int]:
	var priority_units: Array[int] = []
	var normal_units: Array[int] = []

	for unit_id in _units:
		if _frozen_units.has(unit_id):
			continue

		if _units[unit_id]["priority"]:
			priority_units.append(unit_id)
		else:
			normal_units.append(unit_id)

	# Priority units first
	var result: Array[int] = priority_units
	for uid in normal_units:
		result.append(uid)

	return result


## Apply velocity to unit position.
func _apply_velocity(unit_id: int, velocity: Vector3, delta: float) -> void:
	if velocity.length() < 0.01:
		return

	if not _get_unit_position.is_valid() or not _set_unit_position.is_valid():
		return

	# Don't apply velocity if traversing
	if terrain_traversal.is_traversing(unit_id):
		return

	var current_pos: Vector3 = _get_unit_position.call(unit_id)
	if current_pos == Vector3.INF:
		return

	var new_pos := current_pos + velocity * delta
	_set_unit_position.call(unit_id, new_pos)


## Apply acceleration to unit.
func apply_acceleration(unit_id: int, direction: Vector3) -> void:
	momentum_controller.apply_acceleration(unit_id, direction)


## Apply impulse to unit.
func apply_impulse(unit_id: int, impulse: Vector3) -> void:
	momentum_controller.apply_impulse(unit_id, impulse)


## Start leap for unit.
func start_leap(unit_id: int, target_position: Vector3) -> bool:
	return terrain_traversal.start_leap(unit_id, target_position)


## Get velocity for unit.
func get_velocity(unit_id: int) -> Vector3:
	return momentum_controller.get_velocity(unit_id)


## Check if unit is moving.
func is_moving(unit_id: int) -> bool:
	return momentum_controller.is_moving(unit_id)


## Check if unit is frozen.
func is_frozen(unit_id: int) -> bool:
	return _frozen_units.has(unit_id)


## Check if unit is traversing.
func is_traversing(unit_id: int) -> bool:
	return terrain_traversal.is_traversing(unit_id)


## Get last frame time.
func get_last_frame_time_ms() -> float:
	return _last_frame_time_ms


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var units_data: Dictionary = {}
	for unit_id in _units:
		units_data[str(unit_id)] = _units[unit_id].duplicate()

	var frozen_data: Array[int] = []
	for unit_id in _frozen_units:
		frozen_data.append(unit_id)

	return {
		"units": units_data,
		"frozen_units": frozen_data,
		"camera_position": {"x": _camera_position.x, "y": _camera_position.y, "z": _camera_position.z},
		"momentum_controller": momentum_controller.to_dict(),
		"terrain_traversal": terrain_traversal.to_dict()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_units.clear()
	for unit_id_str in data.get("units", {}):
		_units[int(unit_id_str)] = data["units"][unit_id_str].duplicate()

	_frozen_units.clear()
	for unit_id in data.get("frozen_units", []):
		_frozen_units[unit_id] = true

	var cam_data: Dictionary = data.get("camera_position", {})
	_camera_position = Vector3(cam_data.get("x", 0), cam_data.get("y", 0), cam_data.get("z", 0))

	momentum_controller.from_dict(data.get("momentum_controller", {}))
	terrain_traversal.from_dict(data.get("terrain_traversal", {}))


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"total_units": _units.size(),
		"frozen_units": _frozen_units.size(),
		"active_units": _units.size() - _frozen_units.size(),
		"last_frame_ms": "%.2fms" % _last_frame_time_ms,
		"momentum": momentum_controller.get_summary(),
		"traversal": terrain_traversal.get_summary()
	}
