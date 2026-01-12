class_name PhysicsProjectile
extends RefCounted
## PhysicsProjectile extends projectile with physics simulation.
## Supports gravity, bounce, and collision physics.

## Gravity constant
const GRAVITY := Vector3(0.0, -9.8, 0.0)

## Projectile ID
var id: int = -1

## Faction
var faction_id: String = ""

## Projectile type
var projectile_type: String = ""

## Position
var position: Vector3 = Vector3.ZERO

## Velocity
var velocity: Vector3 = Vector3.ZERO

## Acceleration (for gravity and other forces)
var acceleration: Vector3 = Vector3.ZERO

## Spawn position (for despawn distance check)
var spawn_position: Vector3 = Vector3.ZERO

## Damage
var damage: float = 10.0

## Damage type (from DamageType enum)
var damage_type: int = 0  ## KINETIC

## Lifetime tracking
var lifetime: float = 0.0
var max_lifetime: float = 15.0

## Bounce properties
var bounce_count: int = 0
var max_bounces: int = 3
var bounce_dampening: float = 0.6  ## Velocity retained after bounce

## Hit radius
var hit_radius: float = 5.0

## Target for homing
var target_id: int = -1

## Active flag
var is_active: bool = false

## Physics flags
var gravity_enabled: bool = true
var bounce_enabled: bool = false

## Visual
var visual_effect: String = ""
var particle_index: int = -1


func _init() -> void:
	pass


## Initialize projectile.
func initialize(
	proj_id: int,
	faction: String,
	type_id: String,
	spawn_pos: Vector3,
	direction: Vector3,
	speed: float,
	proj_damage: float,
	proj_damage_type: int = 0
) -> void:
	id = proj_id
	faction_id = faction
	projectile_type = type_id
	position = spawn_pos
	spawn_position = spawn_pos
	velocity = direction.normalized() * speed
	acceleration = Vector3.ZERO
	damage = proj_damage
	damage_type = proj_damage_type
	lifetime = 0.0
	bounce_count = 0
	is_active = true


## Update physics.
func update_physics(delta: float, use_gravity: bool, use_bounce: bool) -> void:
	if not is_active:
		return

	# Apply gravity
	if use_gravity and gravity_enabled:
		acceleration = GRAVITY
	else:
		acceleration = Vector3.ZERO

	# Update velocity
	velocity += acceleration * delta

	# Update position
	position += velocity * delta

	# Update lifetime
	lifetime += delta


## Handle ground collision (bounce).
func handle_ground_collision(ground_y: float, use_bounce: bool) -> bool:
	if position.y <= ground_y:
		if use_bounce and bounce_enabled and bounce_count < max_bounces:
			# Bounce
			position.y = ground_y
			velocity.y = -velocity.y * bounce_dampening
			velocity.x *= bounce_dampening
			velocity.z *= bounce_dampening
			bounce_count += 1
			return true
		else:
			# Stop/despawn
			position.y = ground_y
			velocity = Vector3.ZERO
			return false

	return true


## Handle surface collision (bounce off surfaces).
func handle_surface_collision(normal: Vector3, use_bounce: bool) -> bool:
	if use_bounce and bounce_enabled and bounce_count < max_bounces:
		# Reflect velocity
		velocity = velocity.bounce(normal) * bounce_dampening
		bounce_count += 1
		return true
	return false


## Check if should despawn.
func should_despawn(despawn_distance: float) -> bool:
	# Check lifetime
	if lifetime >= max_lifetime:
		return true

	# Check distance from spawn
	var distance := position.distance_to(spawn_position)
	if distance >= despawn_distance:
		return true

	return false


## Check if expired.
func is_expired() -> bool:
	return lifetime >= max_lifetime or not is_active


## Reset for pooling.
func reset() -> void:
	id = -1
	faction_id = ""
	projectile_type = ""
	position = Vector3.ZERO
	velocity = Vector3.ZERO
	acceleration = Vector3.ZERO
	spawn_position = Vector3.ZERO
	damage = 0.0
	damage_type = 0
	lifetime = 0.0
	bounce_count = 0
	is_active = false
	target_id = -1
	visual_effect = ""
	particle_index = -1


## Get knockback (for KINETIC/EXPLOSIVE damage types).
func get_knockback_direction() -> Vector3:
	return velocity.normalized()


## Get knockback force based on damage type.
func get_knockback_force() -> float:
	# KINETIC = 0, EXPLOSIVE = 2 trigger knockback
	if damage_type == 0 or damage_type == 2:
		return damage * 0.5
	return 0.0


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"faction_id": faction_id,
		"projectile_type": projectile_type,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"spawn_position": {"x": spawn_position.x, "y": spawn_position.y, "z": spawn_position.z},
		"damage": damage,
		"damage_type": damage_type,
		"lifetime": lifetime,
		"max_lifetime": max_lifetime,
		"bounce_count": bounce_count,
		"max_bounces": max_bounces,
		"hit_radius": hit_radius,
		"gravity_enabled": gravity_enabled,
		"bounce_enabled": bounce_enabled
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> PhysicsProjectile:
	var proj := PhysicsProjectile.new()
	proj.id = data.get("id", -1)
	proj.faction_id = data.get("faction_id", "")
	proj.projectile_type = data.get("projectile_type", "")

	var pos: Dictionary = data.get("position", {})
	proj.position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	var vel: Dictionary = data.get("velocity", {})
	proj.velocity = Vector3(vel.get("x", 0), vel.get("y", 0), vel.get("z", 0))

	var spawn: Dictionary = data.get("spawn_position", {})
	proj.spawn_position = Vector3(spawn.get("x", 0), spawn.get("y", 0), spawn.get("z", 0))

	proj.damage = data.get("damage", 0.0)
	proj.damage_type = data.get("damage_type", 0)
	proj.lifetime = data.get("lifetime", 0.0)
	proj.max_lifetime = data.get("max_lifetime", 15.0)
	proj.bounce_count = data.get("bounce_count", 0)
	proj.max_bounces = data.get("max_bounces", 3)
	proj.hit_radius = data.get("hit_radius", 5.0)
	proj.gravity_enabled = data.get("gravity_enabled", true)
	proj.bounce_enabled = data.get("bounce_enabled", false)
	proj.is_active = true

	return proj
