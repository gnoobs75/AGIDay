class_name GPUProjectileSystem
extends RefCounted
## GPUProjectileSystem provides GPU-accelerated projectile processing.
## Manages physics simulation with adaptive quality and MultiMesh rendering.

signal projectile_spawned(proj_id: int, position: Vector3)
signal projectile_despawned(proj_id: int, reason: String)
signal projectile_hit(proj_id: int, unit_id: int, damage: float)
signal quality_changed(new_level: int)

## Quality settings
var _quality: ProjectileQuality = null

## Projectile pool
var _pool: PhysicsProjectilePool = null

## Active projectiles by ID
var _active: Dictionary = {}

## By faction
var _by_faction: Dictionary = {}

## GPU data buffer (for MultiMesh)
var _gpu_transform_buffer: PackedFloat32Array
var _gpu_color_buffer: PackedFloat32Array

## Frame timing
var _accumulated_time: float = 0.0
var _update_interval: float = 1.0 / 60.0  ## 60Hz default

## Performance stats
var _stats: Dictionary = {
	"physics_time_ms": 0.0,
	"active_projectiles": 0,
	"spawned_this_frame": 0,
	"despawned_this_frame": 0
}

## Ground level for bounce
var ground_level: float = 0.0


func _init() -> void:
	_quality = ProjectileQuality.new()
	_pool = PhysicsProjectilePool.new(_quality.get_max_projectiles())
	_resize_gpu_buffers()


## Set quality level.
func set_quality(level: int) -> void:
	var old_level := _quality.current_level
	_quality.set_quality(level)

	if old_level != level:
		var config := _quality.get_config()
		_pool.resize(config.max_projectiles)
		_update_interval = 1.0 / config.update_rate
		_resize_gpu_buffers()
		quality_changed.emit(level)


## Set despawn distance.
func set_despawn_distance(distance: float) -> void:
	_quality.set_despawn_distance(distance)


## Spawn projectile.
func spawn_projectile(
	faction_id: String,
	type_id: String,
	position: Vector3,
	direction: Vector3,
	speed: float,
	damage: float,
	damage_type: int = 0
) -> int:
	var proj := _pool.acquire()
	if proj == null:
		return -1

	proj.initialize(proj.id, faction_id, type_id, position, direction, speed, damage, damage_type)

	# Apply quality settings
	var config := _quality.get_config()
	proj.gravity_enabled = config.gravity_enabled
	proj.bounce_enabled = config.bounce_enabled

	_active[proj.id] = proj

	if not _by_faction.has(faction_id):
		_by_faction[faction_id] = []
	_by_faction[faction_id].append(proj.id)

	_stats["spawned_this_frame"] += 1
	projectile_spawned.emit(proj.id, position)

	return proj.id


## Despawn projectile.
func despawn_projectile(proj_id: int, reason: String = "manual") -> void:
	var proj: PhysicsProjectile = _active.get(proj_id)
	if proj == null:
		return

	if _by_faction.has(proj.faction_id):
		_by_faction[proj.faction_id].erase(proj_id)

	_active.erase(proj_id)
	_pool.release(proj)

	_stats["despawned_this_frame"] += 1
	projectile_despawned.emit(proj_id, reason)


## Process physics update.
func process(delta: float) -> void:
	_stats["spawned_this_frame"] = 0
	_stats["despawned_this_frame"] = 0

	var start_time := Time.get_ticks_usec()

	_accumulated_time += delta

	# Fixed timestep updates
	while _accumulated_time >= _update_interval:
		_update_physics(_update_interval)
		_accumulated_time -= _update_interval

	# Update GPU buffers
	_update_gpu_buffers()

	var end_time := Time.get_ticks_usec()
	_stats["physics_time_ms"] = (end_time - start_time) / 1000.0
	_stats["active_projectiles"] = _active.size()


## Update physics for all projectiles.
func _update_physics(delta: float) -> void:
	var config := _quality.get_config()
	var to_despawn: Array[int] = []

	for proj_id in _active:
		var proj: PhysicsProjectile = _active[proj_id]

		# Update physics
		proj.update_physics(delta, config.gravity_enabled, config.bounce_enabled)

		# Handle ground collision
		if config.bounce_enabled:
			proj.handle_ground_collision(ground_level, true)

		# Check despawn conditions
		if proj.should_despawn(config.despawn_distance):
			to_despawn.append(proj_id)

	# Despawn projectiles
	for proj_id in to_despawn:
		despawn_projectile(proj_id, "expired")


## Resize GPU buffers.
func _resize_gpu_buffers() -> void:
	var max_proj := _quality.get_max_projectiles()
	# 16 floats per transform (4x4 matrix)
	_gpu_transform_buffer.resize(max_proj * 16)
	# 4 floats per color (RGBA)
	_gpu_color_buffer.resize(max_proj * 4)


## Update GPU buffers for rendering.
func _update_gpu_buffers() -> void:
	var index := 0
	for proj_id in _active:
		var proj: PhysicsProjectile = _active[proj_id]

		# Build transform (simplified - position only)
		var base := index * 16

		# Identity rotation with position
		_gpu_transform_buffer[base + 0] = 1.0  # m00
		_gpu_transform_buffer[base + 1] = 0.0
		_gpu_transform_buffer[base + 2] = 0.0
		_gpu_transform_buffer[base + 3] = 0.0

		_gpu_transform_buffer[base + 4] = 0.0
		_gpu_transform_buffer[base + 5] = 1.0  # m11
		_gpu_transform_buffer[base + 6] = 0.0
		_gpu_transform_buffer[base + 7] = 0.0

		_gpu_transform_buffer[base + 8] = 0.0
		_gpu_transform_buffer[base + 9] = 0.0
		_gpu_transform_buffer[base + 10] = 1.0  # m22
		_gpu_transform_buffer[base + 11] = 0.0

		_gpu_transform_buffer[base + 12] = proj.position.x
		_gpu_transform_buffer[base + 13] = proj.position.y
		_gpu_transform_buffer[base + 14] = proj.position.z
		_gpu_transform_buffer[base + 15] = 1.0

		# Color (based on faction/type - placeholder)
		var color_base := index * 4
		_gpu_color_buffer[color_base + 0] = 1.0  # R
		_gpu_color_buffer[color_base + 1] = 1.0  # G
		_gpu_color_buffer[color_base + 2] = 1.0  # B
		_gpu_color_buffer[color_base + 3] = 1.0  # A

		index += 1


## Get GPU transform buffer.
func get_transform_buffer() -> PackedFloat32Array:
	return _gpu_transform_buffer


## Get GPU color buffer.
func get_color_buffer() -> PackedFloat32Array:
	return _gpu_color_buffer


## Get active projectile count.
func get_active_count() -> int:
	return _active.size()


## Get projectile by ID.
func get_projectile(proj_id: int) -> PhysicsProjectile:
	return _active.get(proj_id)


## Get all active projectiles.
func get_all_active() -> Array[PhysicsProjectile]:
	var result: Array[PhysicsProjectile] = []
	for proj_id in _active:
		result.append(_active[proj_id])
	return result


## Get projectiles in radius.
func get_projectiles_in_radius(center: Vector3, radius: float) -> Array[PhysicsProjectile]:
	var result: Array[PhysicsProjectile] = []
	var radius_sq := radius * radius

	for proj_id in _active:
		var proj: PhysicsProjectile = _active[proj_id]
		if proj.position.distance_squared_to(center) <= radius_sq:
			result.append(proj)

	return result


## Get quality settings.
func get_quality() -> ProjectileQuality:
	return _quality


## Clear all projectiles.
func clear() -> void:
	for proj_id in _active.keys():
		despawn_projectile(proj_id, "cleared")


## Get stats.
func get_stats() -> Dictionary:
	return _stats.duplicate()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var projectiles: Array = []
	for proj_id in _active:
		projectiles.append(_active[proj_id].to_dict())

	return {
		"quality": _quality.to_dict(),
		"projectiles": projectiles
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	clear()

	_quality.from_dict(data.get("quality", {}))
	_pool.resize(_quality.get_max_projectiles())
	_resize_gpu_buffers()

	for proj_data in data.get("projectiles", []):
		var proj := _pool.acquire()
		if proj == null:
			break

		var loaded := PhysicsProjectile.from_dict(proj_data)
		proj.id = loaded.id if loaded.id >= 0 else proj.id
		proj.faction_id = loaded.faction_id
		proj.projectile_type = loaded.projectile_type
		proj.position = loaded.position
		proj.velocity = loaded.velocity
		proj.spawn_position = loaded.spawn_position
		proj.damage = loaded.damage
		proj.damage_type = loaded.damage_type
		proj.lifetime = loaded.lifetime
		proj.max_lifetime = loaded.max_lifetime
		proj.bounce_count = loaded.bounce_count
		proj.max_bounces = loaded.max_bounces
		proj.hit_radius = loaded.hit_radius
		proj.gravity_enabled = loaded.gravity_enabled
		proj.bounce_enabled = loaded.bounce_enabled
		proj.is_active = true

		_active[proj.id] = proj

		if not _by_faction.has(proj.faction_id):
			_by_faction[proj.faction_id] = []
		_by_faction[proj.faction_id].append(proj.id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"quality": _quality.get_summary(),
		"pool": _pool.get_summary(),
		"stats": _stats,
		"gpu_buffer_size": _gpu_transform_buffer.size()
	}
