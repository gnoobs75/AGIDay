class_name MovementComponent
extends Component
## MovementComponent handles entity position, velocity, and movement properties.

const COMPONENT_TYPE := "MovementComponent"


func _init() -> void:
	component_type = COMPONENT_TYPE
	version = 1
	data = {
		"position": Vector3.ZERO,
		"velocity": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"max_speed": 10.0,
		"acceleration": 50.0,
		"turn_rate": 5.0,
		"is_moving": false,
		"target_position": Vector3.ZERO,
		"has_target": false
	}


## Get the component schema for validation.
static func get_schema() -> ComponentSchema:
	var schema := ComponentSchema.new(COMPONENT_TYPE)

	schema.vector3_field("position").set_default(Vector3.ZERO)
	schema.vector3_field("velocity").set_default(Vector3.ZERO)
	schema.vector3_field("rotation").set_default(Vector3.ZERO)
	schema.float_field("max_speed").set_range(0.0, 1000.0).set_default(10.0)
	schema.float_field("acceleration").set_range(0.0, 500.0).set_default(50.0)
	schema.float_field("turn_rate").set_range(0.0, 20.0).set_default(5.0)
	schema.bool_field("is_moving").set_default(false)
	schema.vector3_field("target_position").set_default(Vector3.ZERO)
	schema.bool_field("has_target").set_default(false)

	return schema


## Get current position.
func get_position() -> Vector3:
	return data.get("position", Vector3.ZERO)


## Set current position.
func set_position(pos: Vector3) -> void:
	data["position"] = pos


## Get current velocity.
func get_velocity() -> Vector3:
	return data.get("velocity", Vector3.ZERO)


## Set current velocity.
func set_velocity(vel: Vector3) -> void:
	var max_speed: float = data.get("max_speed", 10.0)
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	data["velocity"] = vel
	data["is_moving"] = vel.length() > 0.01


## Get rotation.
func get_rotation() -> Vector3:
	return data.get("rotation", Vector3.ZERO)


## Set rotation.
func set_rotation(rot: Vector3) -> void:
	data["rotation"] = rot


## Get max speed.
func get_max_speed() -> float:
	return data.get("max_speed", 10.0)


## Set movement target.
func set_target(target: Vector3) -> void:
	data["target_position"] = target
	data["has_target"] = true


## Clear movement target.
func clear_target() -> void:
	data["has_target"] = false


## Check if has movement target.
func has_target() -> bool:
	return data.get("has_target", false)


## Get target position.
func get_target() -> Vector3:
	return data.get("target_position", Vector3.ZERO)


## Check if entity is moving.
func is_moving() -> bool:
	return data.get("is_moving", false)


## Get distance to target.
func get_distance_to_target() -> float:
	if not has_target():
		return 0.0
	return get_position().distance_to(get_target())


## Stop movement.
func stop() -> void:
	data["velocity"] = Vector3.ZERO
	data["is_moving"] = false
	data["has_target"] = false
