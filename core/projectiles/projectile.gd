class_name Projectile
extends RefCounted
## Projectile represents a single projectile instance.
## Designed for high-performance pooling with 10,000+ simultaneous projectiles.

## Unique projectile ID
var id: int = -1

## Faction that fired this projectile
var faction_id: String = ""

## Projectile type reference
var projectile_type: String = ""

## Position in 3D space
var position: Vector3 = Vector3.ZERO

## Velocity vector
var velocity: Vector3 = Vector3.ZERO

## Rotation (for visual alignment)
var rotation: Vector3 = Vector3.ZERO

## Remaining lifetime (seconds)
var lifetime: float = 5.0

## Damage on hit
var damage: float = 10.0

## Collision radius
var hit_radius: float = 5.0

## Target unit ID for homing (-1 = no target)
var target_id: int = -1

## Homing turn speed (degrees/second)
var homing_speed: float = 0.0

## GPU particle system index
var particle_index: int = -1

## Visual effect identifier
var visual_effect: String = ""

## Active flag (for pooling)
var is_active: bool = false

## Remaining pierce count
var pierce_remaining: int = 0

## Frame spawned (for determinism)
var spawn_frame: int = 0

## Units already hit (for pierce tracking)
var hit_units: Array[int] = []


func _init() -> void:
	pass


## Initialize projectile with type configuration.
func initialize(
	proj_id: int,
	faction: String,
	proj_type: ProjectileType,
	spawn_position: Vector3,
	direction: Vector3,
	frame: int,
	target: int = -1
) -> void:
	id = proj_id
	faction_id = faction
	projectile_type = proj_type.type_id
	position = spawn_position
	velocity = direction.normalized() * proj_type.speed
	rotation = Vector3.ZERO
	lifetime = proj_type.lifetime
	damage = proj_type.damage
	hit_radius = proj_type.hit_radius
	target_id = target if proj_type.is_homing() else -1
	homing_speed = proj_type.max_turn_rate
	particle_index = -1
	visual_effect = proj_type.visual_effect
	is_active = true
	pierce_remaining = proj_type.pierce_count
	spawn_frame = frame
	hit_units.clear()

	# Calculate initial rotation from velocity
	if velocity.length_squared() > 0.001:
		rotation.y = atan2(velocity.x, velocity.z)
		rotation.x = asin(-velocity.normalized().y)


## Reset projectile for pooling.
func reset() -> void:
	id = -1
	faction_id = ""
	projectile_type = ""
	position = Vector3.ZERO
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	lifetime = 0.0
	damage = 0.0
	hit_radius = 0.0
	target_id = -1
	homing_speed = 0.0
	particle_index = -1
	visual_effect = ""
	is_active = false
	pierce_remaining = 0
	spawn_frame = 0
	hit_units.clear()


## Update projectile movement (ballistic).
func update_ballistic(delta: float) -> void:
	position += velocity * delta
	lifetime -= delta


## Update projectile movement (homing).
func update_homing(delta: float, target_position: Vector3, homing_strength: float) -> void:
	if target_id < 0:
		# No target, move ballistic
		update_ballistic(delta)
		return

	# Calculate direction to target
	var to_target := (target_position - position).normalized()
	var current_dir := velocity.normalized()

	# Interpolate direction based on homing strength
	var max_turn := deg_to_rad(homing_speed) * delta
	var angle_diff := current_dir.angle_to(to_target)

	if angle_diff > 0.001:
		var turn_amount := minf(angle_diff, max_turn * homing_strength)
		var turn_axis := current_dir.cross(to_target).normalized()

		if turn_axis.length_squared() > 0.001:
			var new_dir := current_dir.rotated(turn_axis, turn_amount)
			velocity = new_dir * velocity.length()

	# Update position
	position += velocity * delta
	lifetime -= delta

	# Update rotation to match velocity
	if velocity.length_squared() > 0.001:
		rotation.y = atan2(velocity.x, velocity.z)
		rotation.x = asin(-velocity.normalized().y)


## Check if projectile is expired.
func is_expired() -> bool:
	return lifetime <= 0.0 or not is_active


## Record hit on unit.
func record_hit(unit_id: int) -> bool:
	if unit_id in hit_units:
		return false  # Already hit this unit

	hit_units.append(unit_id)
	pierce_remaining -= 1

	return true


## Check if projectile should despawn after hit.
func should_despawn_on_hit() -> bool:
	return pierce_remaining < 0


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"faction_id": faction_id,
		"projectile_type": projectile_type,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"rotation": {"x": rotation.x, "y": rotation.y, "z": rotation.z},
		"lifetime": lifetime,
		"damage": damage,
		"hit_radius": hit_radius,
		"target_id": target_id,
		"homing_speed": homing_speed,
		"particle_index": particle_index,
		"visual_effect": visual_effect,
		"pierce_remaining": pierce_remaining,
		"spawn_frame": spawn_frame,
		"hit_units": hit_units.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> Projectile:
	var proj := Projectile.new()
	proj.id = data.get("id", -1)
	proj.faction_id = data.get("faction_id", "")
	proj.projectile_type = data.get("projectile_type", "")

	var pos_data: Dictionary = data.get("position", {})
	proj.position = Vector3(pos_data.get("x", 0), pos_data.get("y", 0), pos_data.get("z", 0))

	var vel_data: Dictionary = data.get("velocity", {})
	proj.velocity = Vector3(vel_data.get("x", 0), vel_data.get("y", 0), vel_data.get("z", 0))

	var rot_data: Dictionary = data.get("rotation", {})
	proj.rotation = Vector3(rot_data.get("x", 0), rot_data.get("y", 0), rot_data.get("z", 0))

	proj.lifetime = data.get("lifetime", 0.0)
	proj.damage = data.get("damage", 0.0)
	proj.hit_radius = data.get("hit_radius", 0.0)
	proj.target_id = data.get("target_id", -1)
	proj.homing_speed = data.get("homing_speed", 0.0)
	proj.particle_index = data.get("particle_index", -1)
	proj.visual_effect = data.get("visual_effect", "")
	proj.is_active = true
	proj.pierce_remaining = data.get("pierce_remaining", 0)
	proj.spawn_frame = data.get("spawn_frame", 0)

	proj.hit_units.clear()
	for unit_id in data.get("hit_units", []):
		proj.hit_units.append(unit_id)

	return proj
