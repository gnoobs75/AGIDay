class_name TankPhysicsController
extends RefCounted
## TankPhysicsController manages RigidBody3D physics for Tank faction units.

signal velocity_changed(unit_id: int, velocity: Vector3)
signal knockback_applied(unit_id: int, force: Vector3)
signal collision_detected(unit_id: int, other_id: int, impact_velocity: float)
signal unit_frozen(unit_id: int)
signal unit_unfrozen(unit_id: int)

## Performance constants
const MAX_FRAME_TIME_MS := 5.0
const FREEZE_DISTANCE := 100.0
const MAX_KNOCKBACK_VELOCITY := 20.0
const COLLISION_LAYER := 1
const COLLISION_MASK := 1

## Unit physics data (unit_id -> physics_data)
var _unit_physics: Dictionary = {}

## Frozen units (unit_id -> true)
var _frozen_units: Dictionary = {}

## Pending forces (unit_id -> Array[force])
var _pending_forces: Dictionary = {}

## Camera position for optimization
var _camera_position: Vector3 = Vector3.ZERO


func _init() -> void:
	pass


## Register unit with physics.
func register_unit(unit_id: int, unit_type: String = "default", position: Vector3 = Vector3.ZERO) -> void:
	var config := TankPhysicsConfig.get_config(unit_type)

	_unit_physics[unit_id] = {
		"type": unit_type,
		"position": position,
		"velocity": Vector3.ZERO,
		"angular_velocity": Vector3.ZERO,
		"mass": config["mass"],
		"friction": config["friction"],
		"linear_damp": config["linear_damp"],
		"angular_damp": config["angular_damp"],
		"max_velocity": config["max_velocity"],
		"knockback_resistance": config["knockback_resistance"],
		"collision_shape": TankPhysicsConfig.get_collision_shape(unit_type)
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_physics.erase(unit_id)
	_frozen_units.erase(unit_id)
	_pending_forces.erase(unit_id)


## Apply force to unit.
func apply_force(unit_id: int, force: Vector3) -> void:
	if not _unit_physics.has(unit_id):
		return

	if not _pending_forces.has(unit_id):
		_pending_forces[unit_id] = []

	_pending_forces[unit_id].append(force)


## Apply knockback force to unit.
func apply_knockback(unit_id: int, direction: Vector3, force: float) -> void:
	if not _unit_physics.has(unit_id):
		return

	var data: Dictionary = _unit_physics[unit_id]
	var knockback := TankPhysicsConfig.calculate_knockback(
		data["type"],
		force,
		direction
	)

	apply_force(unit_id, knockback)
	knockback_applied.emit(unit_id, knockback)


## Apply AoE knockback to multiple units.
func apply_aoe_knockback(center: Vector3, radius: float, force: float) -> void:
	for unit_id in _unit_physics:
		var data: Dictionary = _unit_physics[unit_id]
		var unit_pos: Vector3 = data["position"]
		var distance := unit_pos.distance_to(center)

		if distance <= radius and distance > 0.1:
			var direction := (unit_pos - center).normalized()
			var falloff := 1.0 - (distance / radius)
			var effective_force := force * falloff

			apply_knockback(unit_id, direction, effective_force)


## Update physics for all units.
func update(delta: float) -> void:
	var start_time := Time.get_ticks_usec()

	# Update frozen states
	_update_frozen_states()

	# Process physics
	for unit_id in _unit_physics:
		# Check time budget
		var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed >= MAX_FRAME_TIME_MS:
			break

		# Skip frozen units
		if _frozen_units.has(unit_id):
			continue

		_update_unit_physics(unit_id, delta)

	# Clear processed forces
	_pending_forces.clear()


## Update physics for single unit.
func _update_unit_physics(unit_id: int, delta: float) -> void:
	var data: Dictionary = _unit_physics[unit_id]
	var old_velocity: Vector3 = data["velocity"]

	# Apply pending forces
	var total_force := Vector3.ZERO
	if _pending_forces.has(unit_id):
		for force in _pending_forces[unit_id]:
			total_force += force

	# Calculate acceleration (F = ma => a = F/m)
	var acceleration := total_force / data["mass"]

	# Update velocity
	data["velocity"] += acceleration * delta

	# Apply damping
	data["velocity"] *= pow(1.0 - data["linear_damp"], delta)

	# Clamp velocity
	_clamp_velocity(unit_id)

	# Update position
	data["position"] += data["velocity"] * delta

	# Emit if velocity changed significantly
	if old_velocity.distance_to(data["velocity"]) > 0.1:
		velocity_changed.emit(unit_id, data["velocity"])


## Clamp velocity to max.
func _clamp_velocity(unit_id: int) -> void:
	var data: Dictionary = _unit_physics[unit_id]
	var velocity: Vector3 = data["velocity"]
	var max_vel: float = minf(data["max_velocity"], MAX_KNOCKBACK_VELOCITY)

	if velocity.length() > max_vel:
		data["velocity"] = velocity.normalized() * max_vel


## Update frozen states based on camera distance.
func _update_frozen_states() -> void:
	for unit_id in _unit_physics:
		var data: Dictionary = _unit_physics[unit_id]
		var distance := _camera_position.distance_to(data["position"])
		var was_frozen := _frozen_units.has(unit_id)

		if distance > FREEZE_DISTANCE:
			if not was_frozen:
				_frozen_units[unit_id] = true
				unit_frozen.emit(unit_id)
		else:
			if was_frozen:
				_frozen_units.erase(unit_id)
				unit_unfrozen.emit(unit_id)


## Set camera position for optimization.
func set_camera_position(position: Vector3) -> void:
	_camera_position = position


## Set unit position directly.
func set_position(unit_id: int, position: Vector3) -> void:
	if _unit_physics.has(unit_id):
		_unit_physics[unit_id]["position"] = position


## Set unit velocity directly.
func set_velocity(unit_id: int, velocity: Vector3) -> void:
	if _unit_physics.has(unit_id):
		_unit_physics[unit_id]["velocity"] = velocity
		_clamp_velocity(unit_id)


## Get unit position.
func get_position(unit_id: int) -> Vector3:
	if not _unit_physics.has(unit_id):
		return Vector3.INF
	return _unit_physics[unit_id]["position"]


## Get unit velocity.
func get_velocity(unit_id: int) -> Vector3:
	if not _unit_physics.has(unit_id):
		return Vector3.ZERO
	return _unit_physics[unit_id]["velocity"]


## Get unit speed.
func get_speed(unit_id: int) -> float:
	return get_velocity(unit_id).length()


## Check if unit is moving.
func is_moving(unit_id: int) -> bool:
	return get_speed(unit_id) > 0.1


## Check if unit is frozen.
func is_frozen(unit_id: int) -> bool:
	return _frozen_units.has(unit_id)


## Get physics data for unit.
func get_physics_data(unit_id: int) -> Dictionary:
	return _unit_physics.get(unit_id, {}).duplicate()


## Check collision between two units.
func check_collision(unit_a: int, unit_b: int) -> bool:
	if not _unit_physics.has(unit_a) or not _unit_physics.has(unit_b):
		return false

	var data_a: Dictionary = _unit_physics[unit_a]
	var data_b: Dictionary = _unit_physics[unit_b]

	var pos_a: Vector3 = data_a["position"]
	var pos_b: Vector3 = data_b["position"]
	var shape_a: Vector3 = data_a["collision_shape"]
	var shape_b: Vector3 = data_b["collision_shape"]

	# Simple AABB collision
	var half_a := shape_a / 2.0
	var half_b := shape_b / 2.0

	var min_a := pos_a - half_a
	var max_a := pos_a + half_a
	var min_b := pos_b - half_b
	var max_b := pos_b + half_b

	return (min_a.x <= max_b.x and max_a.x >= min_b.x and
			min_a.y <= max_b.y and max_a.y >= min_b.y and
			min_a.z <= max_b.z and max_a.z >= min_b.z)


## Resolve collision between units.
func resolve_collision(unit_a: int, unit_b: int) -> void:
	if not check_collision(unit_a, unit_b):
		return

	var data_a: Dictionary = _unit_physics[unit_a]
	var data_b: Dictionary = _unit_physics[unit_b]

	var pos_a: Vector3 = data_a["position"]
	var pos_b: Vector3 = data_b["position"]

	# Calculate collision normal
	var collision_normal := (pos_a - pos_b).normalized()
	if collision_normal.length_squared() < 0.01:
		collision_normal = Vector3.RIGHT

	# Calculate relative velocity
	var rel_velocity: Vector3 = data_a["velocity"] - data_b["velocity"]
	var impact_velocity := absf(rel_velocity.dot(collision_normal))

	# Calculate impulse
	var total_mass := data_a["mass"] + data_b["mass"]
	var impulse := rel_velocity.dot(collision_normal) * 1.5  ## Elasticity

	# Apply impulse based on mass ratio
	var impulse_a := -impulse * (data_b["mass"] / total_mass)
	var impulse_b := impulse * (data_a["mass"] / total_mass)

	data_a["velocity"] += collision_normal * impulse_a
	data_b["velocity"] -= collision_normal * impulse_b

	# Separate units
	var overlap := _calculate_overlap(unit_a, unit_b)
	var separation := collision_normal * overlap * 0.5

	data_a["position"] += separation
	data_b["position"] -= separation

	collision_detected.emit(unit_a, unit_b, impact_velocity)


## Calculate overlap between units.
func _calculate_overlap(unit_a: int, unit_b: int) -> float:
	var data_a: Dictionary = _unit_physics[unit_a]
	var data_b: Dictionary = _unit_physics[unit_b]

	var pos_a: Vector3 = data_a["position"]
	var pos_b: Vector3 = data_b["position"]
	var shape_a: Vector3 = data_a["collision_shape"]
	var shape_b: Vector3 = data_b["collision_shape"]

	var combined_half := (shape_a + shape_b) / 2.0
	var distance := pos_a.distance_to(pos_b)
	var min_distance := combined_half.length()

	return maxf(0.0, min_distance - distance)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var physics_data: Dictionary = {}
	for unit_id in _unit_physics:
		var data: Dictionary = _unit_physics[unit_id]
		physics_data[str(unit_id)] = {
			"type": data["type"],
			"position": {"x": data["position"].x, "y": data["position"].y, "z": data["position"].z},
			"velocity": {"x": data["velocity"].x, "y": data["velocity"].y, "z": data["velocity"].z},
			"mass": data["mass"],
			"friction": data["friction"],
			"linear_damp": data["linear_damp"],
			"max_velocity": data["max_velocity"]
		}

	var frozen: Array[int] = []
	for unit_id in _frozen_units:
		frozen.append(unit_id)

	return {
		"unit_physics": physics_data,
		"frozen_units": frozen,
		"camera_position": {"x": _camera_position.x, "y": _camera_position.y, "z": _camera_position.z}
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_physics.clear()
	for unit_id_str in data.get("unit_physics", {}):
		var pdata: Dictionary = data["unit_physics"][unit_id_str]
		var pos_data: Dictionary = pdata.get("position", {})
		var vel_data: Dictionary = pdata.get("velocity", {})

		var config := TankPhysicsConfig.get_config(pdata.get("type", "default"))

		_unit_physics[int(unit_id_str)] = {
			"type": pdata.get("type", "default"),
			"position": Vector3(pos_data.get("x", 0), pos_data.get("y", 0), pos_data.get("z", 0)),
			"velocity": Vector3(vel_data.get("x", 0), vel_data.get("y", 0), vel_data.get("z", 0)),
			"angular_velocity": Vector3.ZERO,
			"mass": pdata.get("mass", config["mass"]),
			"friction": pdata.get("friction", config["friction"]),
			"linear_damp": pdata.get("linear_damp", config["linear_damp"]),
			"angular_damp": config["angular_damp"],
			"max_velocity": pdata.get("max_velocity", config["max_velocity"]),
			"knockback_resistance": config["knockback_resistance"],
			"collision_shape": TankPhysicsConfig.get_collision_shape(pdata.get("type", "default"))
		}

	_frozen_units.clear()
	for unit_id in data.get("frozen_units", []):
		_frozen_units[unit_id] = true

	var cam_data: Dictionary = data.get("camera_position", {})
	_camera_position = Vector3(cam_data.get("x", 0), cam_data.get("y", 0), cam_data.get("z", 0))


## Get summary for debugging.
func get_summary() -> Dictionary:
	var moving := 0
	for unit_id in _unit_physics:
		if is_moving(unit_id):
			moving += 1

	return {
		"total_units": _unit_physics.size(),
		"frozen_units": _frozen_units.size(),
		"moving_units": moving,
		"freeze_distance": FREEZE_DISTANCE
	}
