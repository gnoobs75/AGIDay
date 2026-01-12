class_name VoxelEffects
extends RefCounted
## VoxelEffects handles visual effects for voxel destruction events.
## Manages particles, debris, dust, and camera effects.

signal effect_spawned(position: Vector3, effect_type: String)
signal debris_spawned(position: Vector3, count: int)
signal camera_shake_requested(intensity: float, duration: float)

## Effect pool sizes
const MAX_PARTICLE_SYSTEMS := 32
const MAX_DEBRIS_OBJECTS := 64
const DEBRIS_LIFETIME := 5.0

## Effect types
enum EffectType {
	CRACK,
	COLLAPSE,
	RUBBLE,
	CRATER,
	DUST_CLOUD,
	SPARKS
}

## Parent node for effects
var _effect_parent: Node3D = null

## Particle system pool
var _particle_pool: Array[GPUParticles3D] = []
var _active_particles: Dictionary = {}  ## instance_id -> expire_time

## Debris pool
var _debris_pool: Array[RigidBody3D] = []
var _active_debris: Dictionary = {}  ## instance_id -> expire_time

## Effect configurations
var _effect_configs: Dictionary = {}

## Debris mesh (shared)
var _debris_mesh: Mesh = null

## Current time tracking
var _current_time: float = 0.0


func _init() -> void:
	_setup_default_configs()
	_create_debris_mesh()


## Initialize with parent node for spawning effects.
func initialize(parent: Node3D) -> void:
	_effect_parent = parent
	_create_particle_pool()
	_create_debris_pool()


## Setup default effect configurations.
func _setup_default_configs() -> void:
	_effect_configs[EffectType.CRACK] = {
		"particle_amount": 8,
		"lifetime": 0.5,
		"scale": 0.5,
		"color": Color(0.6, 0.55, 0.5),
		"velocity_spread": 2.0,
		"debris_count": 2,
		"camera_shake": 0.1
	}

	_effect_configs[EffectType.COLLAPSE] = {
		"particle_amount": 24,
		"lifetime": 1.5,
		"scale": 1.0,
		"color": Color(0.5, 0.45, 0.4),
		"velocity_spread": 4.0,
		"debris_count": 6,
		"camera_shake": 0.3
	}

	_effect_configs[EffectType.RUBBLE] = {
		"particle_amount": 16,
		"lifetime": 2.0,
		"scale": 0.8,
		"color": Color(0.4, 0.35, 0.3),
		"velocity_spread": 3.0,
		"debris_count": 4,
		"camera_shake": 0.2
	}

	_effect_configs[EffectType.CRATER] = {
		"particle_amount": 32,
		"lifetime": 2.5,
		"scale": 1.5,
		"color": Color(0.3, 0.25, 0.2),
		"velocity_spread": 6.0,
		"debris_count": 8,
		"camera_shake": 0.5
	}

	_effect_configs[EffectType.DUST_CLOUD] = {
		"particle_amount": 48,
		"lifetime": 3.0,
		"scale": 2.0,
		"color": Color(0.6, 0.55, 0.5, 0.5),
		"velocity_spread": 1.0,
		"debris_count": 0,
		"camera_shake": 0.0
	}

	_effect_configs[EffectType.SPARKS] = {
		"particle_amount": 12,
		"lifetime": 0.3,
		"scale": 0.3,
		"color": Color(1.0, 0.8, 0.3),
		"velocity_spread": 5.0,
		"debris_count": 0,
		"camera_shake": 0.0
	}


## Create shared debris mesh.
func _create_debris_mesh() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.2, 0.25)
	_debris_mesh = box


## Create particle system pool.
func _create_particle_pool() -> void:
	for i in MAX_PARTICLE_SYSTEMS:
		var particles := _create_particle_system()
		if _effect_parent != null:
			_effect_parent.add_child(particles)
		particles.emitting = false
		particles.visible = false
		_particle_pool.append(particles)


## Create a single particle system.
func _create_particle_system() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 32
	particles.lifetime = 2.0
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.randomness = 0.3

	# Create process material
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 45.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3(0, -9.8, 0)
	material.damping_min = 1.0
	material.damping_max = 2.0
	material.scale_min = 0.5
	material.scale_max = 1.5

	particles.process_material = material

	# Create draw pass (simple quad)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	particles.draw_pass_1 = quad

	return particles


## Create debris object pool.
func _create_debris_pool() -> void:
	for i in MAX_DEBRIS_OBJECTS:
		var debris := _create_debris_object()
		if _effect_parent != null:
			_effect_parent.add_child(debris)
		debris.visible = false
		debris.freeze = true
		_debris_pool.append(debris)


## Create a single debris object.
func _create_debris_object() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = 0.5
	body.gravity_scale = 1.0

	# Add mesh
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _debris_mesh

	# Material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.35, 0.3)
	mat.roughness = 1.0
	mesh_instance.material_override = mat

	body.add_child(mesh_instance)

	# Collision shape
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 0.2, 0.25)
	collision.shape = shape
	body.add_child(collision)

	return body


## Spawn effect for voxel stage transition.
func spawn_stage_transition_effect(position: Vector3, old_stage: int, new_stage: int) -> void:
	var effect_type: int

	if new_stage == VoxelStage.Stage.CRACKED:
		effect_type = EffectType.CRACK
	elif new_stage == VoxelStage.Stage.RUBBLE:
		effect_type = EffectType.RUBBLE
	elif new_stage == VoxelStage.Stage.CRATER:
		effect_type = EffectType.CRATER
	else:
		return

	spawn_effect(position, effect_type)


## Spawn effect at position.
func spawn_effect(position: Vector3, effect_type: int) -> void:
	var config: Dictionary = _effect_configs.get(effect_type, _effect_configs[EffectType.CRACK])

	# Spawn particles
	_spawn_particles(position, config)

	# Spawn debris
	if config["debris_count"] > 0:
		_spawn_debris(position, config["debris_count"], config["velocity_spread"])

	# Request camera shake
	if config["camera_shake"] > 0:
		camera_shake_requested.emit(config["camera_shake"], config["lifetime"] * 0.5)

	effect_spawned.emit(position, _get_effect_name(effect_type))


## Spawn particles at position.
func _spawn_particles(position: Vector3, config: Dictionary) -> void:
	var particles := _get_available_particle_system()
	if particles == null:
		return

	# Configure
	particles.amount = config["particle_amount"]
	particles.lifetime = config["lifetime"]
	particles.global_position = position

	var mat: ParticleProcessMaterial = particles.process_material
	if mat != null:
		mat.initial_velocity_max = config["velocity_spread"]
		mat.initial_velocity_min = config["velocity_spread"] * 0.5
		mat.color = config["color"]

	# Start emitting
	particles.visible = true
	particles.emitting = true

	# Track expiration
	_active_particles[particles.get_instance_id()] = _current_time + config["lifetime"] + 0.5


## Get available particle system from pool.
func _get_available_particle_system() -> GPUParticles3D:
	for particles in _particle_pool:
		if not particles.emitting:
			return particles

	# Recycle oldest if all in use
	var oldest_id: int = -1
	var oldest_time: float = INF

	for id in _active_particles:
		if _active_particles[id] < oldest_time:
			oldest_time = _active_particles[id]
			oldest_id = id

	if oldest_id >= 0:
		for particles in _particle_pool:
			if particles.get_instance_id() == oldest_id:
				particles.emitting = false
				_active_particles.erase(oldest_id)
				return particles

	return null


## Spawn debris at position.
func _spawn_debris(position: Vector3, count: int, velocity_spread: float) -> void:
	var spawned := 0

	for debris in _debris_pool:
		if spawned >= count:
			break

		if debris.freeze and not debris.visible:
			# Position with slight randomization
			debris.global_position = position + Vector3(
				randf_range(-0.5, 0.5),
				randf_range(0.2, 0.5),
				randf_range(-0.5, 0.5)
			)

			# Random rotation
			debris.rotation = Vector3(
				randf() * TAU,
				randf() * TAU,
				randf() * TAU
			)

			# Initial velocity
			debris.linear_velocity = Vector3(
				randf_range(-velocity_spread, velocity_spread),
				randf_range(velocity_spread * 0.5, velocity_spread),
				randf_range(-velocity_spread, velocity_spread)
			)

			debris.angular_velocity = Vector3(
				randf_range(-5, 5),
				randf_range(-5, 5),
				randf_range(-5, 5)
			)

			debris.visible = true
			debris.freeze = false

			_active_debris[debris.get_instance_id()] = _current_time + DEBRIS_LIFETIME
			spawned += 1

	if spawned > 0:
		debris_spawned.emit(position, spawned)


## Process effects (call every frame).
func process(delta: float) -> void:
	_current_time += delta

	# Cleanup expired particles
	var expired_particles: Array = []
	for id in _active_particles:
		if _current_time >= _active_particles[id]:
			expired_particles.append(id)

	for id in expired_particles:
		_active_particles.erase(id)
		for particles in _particle_pool:
			if particles.get_instance_id() == id:
				particles.emitting = false
				particles.visible = false
				break

	# Cleanup expired debris
	var expired_debris: Array = []
	for id in _active_debris:
		if _current_time >= _active_debris[id]:
			expired_debris.append(id)

	for id in expired_debris:
		_active_debris.erase(id)
		for debris in _debris_pool:
			if debris.get_instance_id() == id:
				debris.freeze = true
				debris.visible = false
				debris.linear_velocity = Vector3.ZERO
				debris.angular_velocity = Vector3.ZERO
				break


## Spawn dust cloud at position.
func spawn_dust_cloud(position: Vector3, scale: float = 1.0) -> void:
	var config := _effect_configs[EffectType.DUST_CLOUD].duplicate()
	config["scale"] *= scale
	config["particle_amount"] = int(config["particle_amount"] * scale)
	_spawn_particles(position, config)


## Spawn sparks at position.
func spawn_sparks(position: Vector3) -> void:
	spawn_effect(position, EffectType.SPARKS)


## Spawn mass destruction effect (large area).
func spawn_mass_destruction(center: Vector3, radius: float) -> void:
	# Central crater effect
	spawn_effect(center, EffectType.CRATER)

	# Surrounding dust clouds
	var dust_count := int(radius / 4.0)
	for i in dust_count:
		var angle := randf() * TAU
		var dist := randf_range(radius * 0.3, radius * 0.8)
		var offset := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		spawn_dust_cloud(center + offset, 0.5)

	# Strong camera shake
	camera_shake_requested.emit(0.8, 1.0)


## Get effect name string.
func _get_effect_name(effect_type: int) -> String:
	match effect_type:
		EffectType.CRACK: return "crack"
		EffectType.COLLAPSE: return "collapse"
		EffectType.RUBBLE: return "rubble"
		EffectType.CRATER: return "crater"
		EffectType.DUST_CLOUD: return "dust_cloud"
		EffectType.SPARKS: return "sparks"
		_: return "unknown"


## Set custom effect configuration.
func set_effect_config(effect_type: int, config: Dictionary) -> void:
	_effect_configs[effect_type] = config


## Get active effect counts.
func get_statistics() -> Dictionary:
	return {
		"active_particles": _active_particles.size(),
		"active_debris": _active_debris.size(),
		"particle_pool_size": _particle_pool.size(),
		"debris_pool_size": _debris_pool.size()
	}


## Cleanup all effects.
func cleanup() -> void:
	for particles in _particle_pool:
		particles.queue_free()
	_particle_pool.clear()

	for debris in _debris_pool:
		debris.queue_free()
	_debris_pool.clear()

	_active_particles.clear()
	_active_debris.clear()
