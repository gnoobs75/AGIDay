class_name TankPhysicsConfig
extends RefCounted
## TankPhysicsConfig stores physics parameters for Tank faction units.

## Unit type configurations
const UNIT_CONFIGS := {
	"titan": {
		"mass": 100.0,
		"friction": 0.5,
		"linear_damp": 0.5,
		"angular_damp": 1.0,
		"max_velocity": 12.0,
		"knockback_resistance": 0.2
	},
	"colossus": {
		"mass": 150.0,
		"friction": 0.8,
		"linear_damp": 0.6,
		"angular_damp": 1.2,
		"max_velocity": 8.0,
		"knockback_resistance": 0.4
	},
	"heavy_tank": {
		"mass": 120.0,
		"friction": 0.6,
		"linear_damp": 0.55,
		"angular_damp": 1.1,
		"max_velocity": 10.0,
		"knockback_resistance": 0.3
	},
	"assault_tank": {
		"mass": 80.0,
		"friction": 0.4,
		"linear_damp": 0.4,
		"angular_damp": 0.9,
		"max_velocity": 14.0,
		"knockback_resistance": 0.15
	},
	"artillery": {
		"mass": 90.0,
		"friction": 0.7,
		"linear_damp": 0.7,
		"angular_damp": 1.3,
		"max_velocity": 6.0,
		"knockback_resistance": 0.1
	},
	"default": {
		"mass": 100.0,
		"friction": 0.5,
		"linear_damp": 0.5,
		"angular_damp": 1.0,
		"max_velocity": 10.0,
		"knockback_resistance": 0.2
	}
}

## Collision shape sizes per unit type
const COLLISION_SHAPES := {
	"titan": Vector3(2.0, 1.5, 3.0),
	"colossus": Vector3(3.0, 2.0, 4.0),
	"heavy_tank": Vector3(2.5, 1.8, 3.5),
	"assault_tank": Vector3(1.8, 1.2, 2.5),
	"artillery": Vector3(2.0, 1.5, 4.0),
	"default": Vector3(2.0, 1.5, 3.0)
}


## Get config for unit type.
static func get_config(unit_type: String) -> Dictionary:
	return UNIT_CONFIGS.get(unit_type, UNIT_CONFIGS["default"]).duplicate()


## Get collision shape size for unit type.
static func get_collision_shape(unit_type: String) -> Vector3:
	return COLLISION_SHAPES.get(unit_type, COLLISION_SHAPES["default"])


## Get mass for unit type.
static func get_mass(unit_type: String) -> float:
	var config := get_config(unit_type)
	return config["mass"]


## Get max velocity for unit type.
static func get_max_velocity(unit_type: String) -> float:
	var config := get_config(unit_type)
	return config["max_velocity"]


## Get knockback resistance for unit type.
static func get_knockback_resistance(unit_type: String) -> float:
	var config := get_config(unit_type)
	return config["knockback_resistance"]


## Calculate knockback force accounting for resistance.
static func calculate_knockback(
	unit_type: String,
	base_force: float,
	direction: Vector3
) -> Vector3:
	var resistance := get_knockback_resistance(unit_type)
	var effective_force := base_force * (1.0 - resistance)
	return direction.normalized() * effective_force
