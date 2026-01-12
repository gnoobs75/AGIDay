class_name MomentumPhysicsController
extends RefCounted
## MomentumPhysicsController manages velocity and acceleration for momentum-based movement.

signal velocity_changed(unit_id: int, old_velocity: Vector3, new_velocity: Vector3)
signal max_velocity_reached(unit_id: int)
signal unit_stopped(unit_id: int)

## Default physics parameters
const DEFAULT_ACCELERATION := 20.0
const DEFAULT_MAX_VELOCITY := 15.0
const DEFAULT_FRICTION := 8.0
const MIN_VELOCITY := 0.1

## Unit physics data (unit_id -> physics_data)
var _unit_physics: Dictionary = {}

## Physics parameters per unit type (type -> params)
var _type_params: Dictionary = {}

## Gravity
var gravity: float = 9.8


func _init() -> void:
	_setup_default_params()


## Setup default parameters for unit types.
func _setup_default_params() -> void:
	_type_params["default"] = {
		"acceleration": DEFAULT_ACCELERATION,
		"max_velocity": DEFAULT_MAX_VELOCITY,
		"friction": DEFAULT_FRICTION
	}

	# Dynapods - high mobility
	_type_params["bouncer"] = {
		"acceleration": 25.0,
		"max_velocity": 18.0,
		"friction": 6.0
	}

	_type_params["tumbler"] = {
		"acceleration": 22.0,
		"max_velocity": 16.0,
		"friction": 7.0
	}

	_type_params["springer"] = {
		"acceleration": 30.0,
		"max_velocity": 20.0,
		"friction": 5.0
	}

	# Heavy units - lower mobility
	_type_params["heavy"] = {
		"acceleration": 12.0,
		"max_velocity": 10.0,
		"friction": 10.0
	}


## Register unit with physics system.
func register_unit(unit_id: int, unit_type: String = "default") -> void:
	var params: Dictionary = _type_params.get(unit_type, _type_params["default"])

	_unit_physics[unit_id] = {
		"velocity": Vector3.ZERO,
		"acceleration": Vector3.ZERO,
		"type": unit_type,
		"max_velocity": params["max_velocity"],
		"friction": params["friction"],
		"accel_rate": params["acceleration"],
		"is_grounded": true
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_physics.erase(unit_id)


## Apply acceleration to unit.
func apply_acceleration(unit_id: int, direction: Vector3) -> void:
	if not _unit_physics.has(unit_id):
		return

	var data: Dictionary = _unit_physics[unit_id]
	data["acceleration"] = direction.normalized() * data["accel_rate"]


## Apply impulse to unit (instant velocity change).
func apply_impulse(unit_id: int, impulse: Vector3) -> void:
	if not _unit_physics.has(unit_id):
		return

	var data: Dictionary = _unit_physics[unit_id]
	var old_velocity: Vector3 = data["velocity"]
	data["velocity"] += impulse
	_clamp_velocity(unit_id)

	velocity_changed.emit(unit_id, old_velocity, data["velocity"])


## Set velocity directly.
func set_velocity(unit_id: int, velocity: Vector3) -> void:
	if not _unit_physics.has(unit_id):
		return

	var data: Dictionary = _unit_physics[unit_id]
	var old_velocity: Vector3 = data["velocity"]
	data["velocity"] = velocity
	_clamp_velocity(unit_id)

	velocity_changed.emit(unit_id, old_velocity, data["velocity"])


## Update physics for single unit.
func update_unit(unit_id: int, delta: float) -> Vector3:
	if not _unit_physics.has(unit_id):
		return Vector3.ZERO

	var data: Dictionary = _unit_physics[unit_id]
	var old_velocity: Vector3 = data["velocity"]

	# Apply acceleration
	data["velocity"] += data["acceleration"] * delta

	# Apply friction
	_apply_friction(unit_id, delta)

	# Clamp velocity
	_clamp_velocity(unit_id)

	# Check for stopped state
	if data["velocity"].length() < MIN_VELOCITY:
		data["velocity"] = Vector3.ZERO
		if old_velocity.length() >= MIN_VELOCITY:
			unit_stopped.emit(unit_id)

	# Clear acceleration for next frame
	data["acceleration"] = Vector3.ZERO

	return data["velocity"]


## Update all units.
func update(delta: float) -> Dictionary:
	var velocities: Dictionary = {}

	for unit_id in _unit_physics:
		velocities[unit_id] = update_unit(unit_id, delta)

	return velocities


## Apply friction to unit.
func _apply_friction(unit_id: int, delta: float) -> void:
	var data: Dictionary = _unit_physics[unit_id]
	var velocity: Vector3 = data["velocity"]

	if velocity.length() < MIN_VELOCITY:
		return

	# Apply friction in opposite direction of velocity
	var friction_force := velocity.normalized() * data["friction"] * delta

	if friction_force.length() >= velocity.length():
		data["velocity"] = Vector3.ZERO
	else:
		data["velocity"] -= friction_force


## Clamp velocity to max.
func _clamp_velocity(unit_id: int) -> void:
	var data: Dictionary = _unit_physics[unit_id]
	var velocity: Vector3 = data["velocity"]
	var max_vel: float = data["max_velocity"]

	if velocity.length() > max_vel:
		data["velocity"] = velocity.normalized() * max_vel
		max_velocity_reached.emit(unit_id)


## Get velocity for unit.
func get_velocity(unit_id: int) -> Vector3:
	if not _unit_physics.has(unit_id):
		return Vector3.ZERO
	return _unit_physics[unit_id]["velocity"]


## Get speed (velocity magnitude) for unit.
func get_speed(unit_id: int) -> float:
	return get_velocity(unit_id).length()


## Check if unit is moving.
func is_moving(unit_id: int) -> bool:
	return get_speed(unit_id) >= MIN_VELOCITY


## Set unit grounded state.
func set_grounded(unit_id: int, grounded: bool) -> void:
	if _unit_physics.has(unit_id):
		_unit_physics[unit_id]["is_grounded"] = grounded


## Check if unit is grounded.
func is_grounded(unit_id: int) -> bool:
	if not _unit_physics.has(unit_id):
		return true
	return _unit_physics[unit_id]["is_grounded"]


## Get physics data for unit.
func get_physics_data(unit_id: int) -> Dictionary:
	return _unit_physics.get(unit_id, {}).duplicate()


## Set physics parameters for unit type.
func set_type_params(unit_type: String, acceleration: float, max_velocity: float, friction: float) -> void:
	_type_params[unit_type] = {
		"acceleration": acceleration,
		"max_velocity": max_velocity,
		"friction": friction
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var physics_data: Dictionary = {}
	for unit_id in _unit_physics:
		var data: Dictionary = _unit_physics[unit_id]
		var vel: Vector3 = data["velocity"]
		var accel: Vector3 = data["acceleration"]
		physics_data[str(unit_id)] = {
			"velocity": {"x": vel.x, "y": vel.y, "z": vel.z},
			"acceleration": {"x": accel.x, "y": accel.y, "z": accel.z},
			"type": data["type"],
			"max_velocity": data["max_velocity"],
			"friction": data["friction"],
			"accel_rate": data["accel_rate"],
			"is_grounded": data["is_grounded"]
		}

	return {
		"unit_physics": physics_data,
		"gravity": gravity
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	gravity = data.get("gravity", 9.8)

	_unit_physics.clear()
	for unit_id_str in data.get("unit_physics", {}):
		var pdata: Dictionary = data["unit_physics"][unit_id_str]
		var vel_data: Dictionary = pdata.get("velocity", {})
		var accel_data: Dictionary = pdata.get("acceleration", {})

		_unit_physics[int(unit_id_str)] = {
			"velocity": Vector3(vel_data.get("x", 0), vel_data.get("y", 0), vel_data.get("z", 0)),
			"acceleration": Vector3(accel_data.get("x", 0), accel_data.get("y", 0), accel_data.get("z", 0)),
			"type": pdata.get("type", "default"),
			"max_velocity": pdata.get("max_velocity", DEFAULT_MAX_VELOCITY),
			"friction": pdata.get("friction", DEFAULT_FRICTION),
			"accel_rate": pdata.get("accel_rate", DEFAULT_ACCELERATION),
			"is_grounded": pdata.get("is_grounded", true)
		}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var moving_count := 0
	var total_speed := 0.0

	for unit_id in _unit_physics:
		var speed := get_speed(unit_id)
		if speed >= MIN_VELOCITY:
			moving_count += 1
			total_speed += speed

	return {
		"registered_units": _unit_physics.size(),
		"moving_units": moving_count,
		"avg_speed": "%.1f" % (total_speed / maxf(1.0, moving_count)),
		"type_configs": _type_params.size()
	}
