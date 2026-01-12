class_name AssemblyParticles
extends RefCounted
## AssemblyParticles manages GPUParticles3D effects for assembly operations.

signal particles_spawned(effect_type: String, position: Vector3)
signal particles_finished(effect_type: String)

## Particle effect types
const EFFECT_WELD_SPARKS := "weld_sparks"
const EFFECT_ENERGY_PULSE := "energy_pulse"
const EFFECT_ORGANIC_MIST := "organic_mist"
const EFFECT_CIRCUIT_SPARKS := "circuit_sparks"
const EFFECT_ASSEMBLY_GLOW := "assembly_glow"

## Pool settings
const MAX_POOLED_PARTICLES := 20
const PARTICLE_LIFETIME := 1.5

## Active particle systems
var _active_particles: Array[GPUParticles3D] = []
var _particle_pool: Dictionary = {}  ## effect_type -> Array[GPUParticles3D]

## Parent node for particles
var _parent_node: Node3D = null

## Theme colors for customization
var _primary_color: Color = Color.WHITE
var _glow_color: Color = Color.WHITE
var _particle_color: Color = Color.WHITE


func _init() -> void:
	# Initialize pools for each effect type
	_particle_pool[EFFECT_WELD_SPARKS] = []
	_particle_pool[EFFECT_ENERGY_PULSE] = []
	_particle_pool[EFFECT_ORGANIC_MIST] = []
	_particle_pool[EFFECT_CIRCUIT_SPARKS] = []
	_particle_pool[EFFECT_ASSEMBLY_GLOW] = []


## Set parent node for spawned particles.
func set_parent(parent: Node3D) -> void:
	_parent_node = parent


## Set theme colors for particle effects.
func set_theme_colors(primary: Color, glow: Color, particle: Color) -> void:
	_primary_color = primary
	_glow_color = glow
	_particle_color = particle


## Spawn particles at a position.
func spawn_particles(effect_type: String, position: Vector3, intensity: float = 1.0) -> GPUParticles3D:
	if _parent_node == null:
		push_warning("No parent node set for particles")
		return null

	var particles := _get_or_create_particles(effect_type)
	if particles == null:
		return null

	# Position and configure
	particles.position = position
	particles.amount = int(particles.amount * intensity)
	particles.emitting = true

	_active_particles.append(particles)
	particles_spawned.emit(effect_type, position)

	return particles


## Get or create particles from pool.
func _get_or_create_particles(effect_type: String) -> GPUParticles3D:
	var pool: Array = _particle_pool.get(effect_type, [])

	# Try to reuse from pool
	for particles in pool:
		if not particles.emitting:
			return particles

	# Create new if under limit
	if pool.size() < MAX_POOLED_PARTICLES:
		var particles := _create_particles(effect_type)
		if particles != null:
			pool.append(particles)
			_particle_pool[effect_type] = pool
			_parent_node.add_child(particles)
		return particles

	return null


## Create a new particle system for effect type.
func _create_particles(effect_type: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.lifetime = PARTICLE_LIFETIME

	# Configure based on effect type
	match effect_type:
		EFFECT_WELD_SPARKS:
			_configure_weld_sparks(particles)
		EFFECT_ENERGY_PULSE:
			_configure_energy_pulse(particles)
		EFFECT_ORGANIC_MIST:
			_configure_organic_mist(particles)
		EFFECT_CIRCUIT_SPARKS:
			_configure_circuit_sparks(particles)
		EFFECT_ASSEMBLY_GLOW:
			_configure_assembly_glow(particles)
		_:
			_configure_weld_sparks(particles)

	return particles


## Configure weld sparks effect (industrial).
func _configure_weld_sparks(particles: GPUParticles3D) -> void:
	particles.amount = 50
	particles.lifetime = 0.8
	particles.explosiveness = 0.9

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.1

	material.direction = Vector3(0, 1, 0)
	material.spread = 60.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0

	material.gravity = Vector3(0, -9.8, 0)
	material.damping_min = 1.0
	material.damping_max = 2.0

	material.scale_min = 0.02
	material.scale_max = 0.05

	material.color = _particle_color if _particle_color != Color.WHITE else Color(1.0, 0.7, 0.2)

	particles.process_material = material
	particles.draw_pass_1 = _create_spark_mesh()


## Configure energy pulse effect (tech).
func _configure_energy_pulse(particles: GPUParticles3D) -> void:
	particles.amount = 30
	particles.lifetime = 1.0
	particles.explosiveness = 0.5

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 0.5
	material.emission_ring_inner_radius = 0.3
	material.emission_ring_height = 0.1
	material.emission_ring_axis = Vector3(0, 1, 0)

	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.0

	material.gravity = Vector3.ZERO
	material.radial_velocity_min = 0.5
	material.radial_velocity_max = 1.0

	material.scale_min = 0.1
	material.scale_max = 0.2

	material.color = _glow_color if _glow_color != Color.WHITE else Color(0.4, 0.7, 1.0)

	particles.process_material = material
	particles.draw_pass_1 = _create_glow_mesh()


## Configure organic mist effect (swarm).
func _configure_organic_mist(particles: GPUParticles3D) -> void:
	particles.amount = 40
	particles.lifetime = 1.5
	particles.explosiveness = 0.3

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.3

	material.direction = Vector3(0, 1, 0)
	material.spread = 90.0
	material.initial_velocity_min = 0.3
	material.initial_velocity_max = 0.8

	material.gravity = Vector3(0, 0.5, 0)  # Float upward

	material.scale_min = 0.15
	material.scale_max = 0.3

	material.color = _particle_color if _particle_color != Color.WHITE else Color(0.6, 0.2, 0.8, 0.6)

	particles.process_material = material
	particles.draw_pass_1 = _create_mist_mesh()


## Configure circuit sparks effect (mechanical).
func _configure_circuit_sparks(particles: GPUParticles3D) -> void:
	particles.amount = 25
	particles.lifetime = 0.6
	particles.explosiveness = 1.0

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(0.2, 0.05, 0.2)

	material.direction = Vector3(0, 1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0

	material.gravity = Vector3(0, -5.0, 0)

	material.scale_min = 0.01
	material.scale_max = 0.03

	material.color = _particle_color if _particle_color != Color.WHITE else Color(0.2, 0.9, 0.3)

	particles.process_material = material
	particles.draw_pass_1 = _create_spark_mesh()


## Configure assembly glow effect (completion).
func _configure_assembly_glow(particles: GPUParticles3D) -> void:
	particles.amount = 60
	particles.lifetime = 2.0
	particles.explosiveness = 0.2

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5

	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 0.2
	material.initial_velocity_max = 0.5

	material.gravity = Vector3.ZERO
	material.radial_velocity_min = 0.3
	material.radial_velocity_max = 0.6

	material.scale_min = 0.05
	material.scale_max = 0.15

	var gradient := Gradient.new()
	gradient.add_point(0.0, _glow_color if _glow_color != Color.WHITE else Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(1.0, Color(_glow_color.r, _glow_color.g, _glow_color.b, 0.0))

	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material
	particles.draw_pass_1 = _create_glow_mesh()


## Create spark mesh (small box).
func _create_spark_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, 0.1)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 2.0
	mesh.material = mat

	return mesh


## Create glow mesh (sphere).
func _create_glow_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat

	return mesh


## Create mist mesh (larger sphere).
func _create_mist_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat

	return mesh


## Stop all active particles.
func stop_all() -> void:
	for particles in _active_particles:
		if is_instance_valid(particles):
			particles.emitting = false

	_active_particles.clear()


## Update particle states (call each frame).
func update(_delta: float) -> void:
	# Remove finished particles from active list
	var finished: Array[GPUParticles3D] = []

	for particles in _active_particles:
		if not is_instance_valid(particles):
			finished.append(particles)
			continue

		if not particles.emitting:
			finished.append(particles)

	for particles in finished:
		_active_particles.erase(particles)


## Cleanup all particles.
func cleanup() -> void:
	stop_all()

	for effect_type in _particle_pool:
		var pool: Array = _particle_pool[effect_type]
		for particles in pool:
			if is_instance_valid(particles):
				particles.queue_free()
		pool.clear()


## Get active particle count.
func get_active_count() -> int:
	return _active_particles.size()


## Check if any particles are active.
func has_active_particles() -> bool:
	return not _active_particles.is_empty()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var pool_sizes: Dictionary = {}
	for effect_type in _particle_pool:
		pool_sizes[effect_type] = _particle_pool[effect_type].size()

	return {
		"active_count": _active_particles.size(),
		"pool_sizes": pool_sizes,
		"has_parent": _parent_node != null
	}
