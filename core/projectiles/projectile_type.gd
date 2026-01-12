class_name ProjectileType
extends RefCounted
## ProjectileType defines configuration for a projectile variant.

## Movement types
enum MovementType {
	BALLISTIC = 0,  ## Constant velocity, straight line
	HOMING = 1      ## Tracks target with velocity interpolation
}

## Type identifier
var type_id: String = ""

## Display name
var display_name: String = ""

## Movement configuration
var movement_type: int = MovementType.BALLISTIC
var speed: float = 500.0
var homing_strength: float = 0.0  ## 0-1, how quickly it turns toward target
var max_turn_rate: float = 180.0  ## Degrees per second

## Combat properties
var damage: float = 10.0
var hit_radius: float = 5.0
var pierce_count: int = 0  ## 0 = destroyed on first hit

## Lifetime
var lifetime: float = 5.0  ## Seconds before auto-despawn

## Visual properties
var visual_effect: String = ""
var trail_enabled: bool = false
var scale: float = 1.0


func _init() -> void:
	pass


## Load from dictionary (JSON config).
static func from_dict(data: Dictionary) -> ProjectileType:
	var proj_type := ProjectileType.new()

	proj_type.type_id = data.get("type_id", "")
	proj_type.display_name = data.get("display_name", proj_type.type_id)

	# Movement
	var move_str: String = data.get("movement_type", "ballistic")
	proj_type.movement_type = MovementType.HOMING if move_str == "homing" else MovementType.BALLISTIC
	proj_type.speed = data.get("speed", 500.0)
	proj_type.homing_strength = data.get("homing_strength", 0.0)
	proj_type.max_turn_rate = data.get("max_turn_rate", 180.0)

	# Combat
	proj_type.damage = data.get("damage", 10.0)
	proj_type.hit_radius = data.get("hit_radius", 5.0)
	proj_type.pierce_count = data.get("pierce_count", 0)

	# Lifetime
	proj_type.lifetime = data.get("lifetime", 5.0)

	# Visual
	proj_type.visual_effect = data.get("visual_effect", "")
	proj_type.trail_enabled = data.get("trail_enabled", false)
	proj_type.scale = data.get("scale", 1.0)

	return proj_type


## Convert to dictionary.
func to_dict() -> Dictionary:
	return {
		"type_id": type_id,
		"display_name": display_name,
		"movement_type": "homing" if movement_type == MovementType.HOMING else "ballistic",
		"speed": speed,
		"homing_strength": homing_strength,
		"max_turn_rate": max_turn_rate,
		"damage": damage,
		"hit_radius": hit_radius,
		"pierce_count": pierce_count,
		"lifetime": lifetime,
		"visual_effect": visual_effect,
		"trail_enabled": trail_enabled,
		"scale": scale
	}


## Check if homing.
func is_homing() -> bool:
	return movement_type == MovementType.HOMING
