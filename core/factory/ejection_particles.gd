class_name EjectionParticles
extends RefCounted
## EjectionParticles manages GPU particle effects for unit ejection animations.
## Provides faction-specific particle effects for different ejection styles.

signal particles_spawned(effect_type: String, position: Vector3)

## Particle effect types
const EFFECT_SWARM_BURST := "swarm_burst"
const EFFECT_SWARM_TRAIL := "swarm_trail"
const EFFECT_IMPACT := "impact"
const EFFECT_DUST_CLOUD := "dust_cloud"
const EFFECT_LEAP_LAUNCH := "leap_launch"
const EFFECT_GROUND_CRACK := "ground_crack"
const EFFECT_STEAM_VENT := "steam_vent"
const EFFECT_FOOTSTEP := "footstep"
const EFFECT_RAPPEL_LINE := "rappel_line"

## Pool settings
const MAX_POOLED_PARTICLES := 30
const DEFAULT_LIFETIME := 1.5

## Faction colors for effects
const FACTION_COLORS := {
	1: Color(0.6, 0.2, 1.0),    # Aether Swarm - Purple
	2: Color(1.0, 0.5, 0.2),    # OptiForge - Orange
	3: Color(0.2, 0.9, 0.4),    # Dynapods - Green
	4: Color(0.2, 0.4, 0.9),    # LogiBots - Blue
	5: Color(0.5, 0.5, 0.5)     # Human Remnant - Gray
}

## Active particles
var _active_particles: Array[GPUParticles3D] = []
var _particle_pool: Dictionary = {}  ## effect_type -> Array[GPUParticles3D]

## Parent node
var _parent_node: Node3D = null


func _init() -> void:
	# Initialize pools
	for effect_type in [EFFECT_SWARM_BURST, EFFECT_SWARM_TRAIL, EFFECT_IMPACT,
			EFFECT_DUST_CLOUD, EFFECT_LEAP_LAUNCH, EFFECT_GROUND_CRACK,
			EFFECT_STEAM_VENT, EFFECT_FOOTSTEP, EFFECT_RAPPEL_LINE]:
		_particle_pool[effect_type] = []


## Set parent node for particles.
func set_parent(parent: Node3D) -> void:
	_parent_node = parent


## Spawn swarm burst effect (Aether Swarm ejection).
func spawn_swarm_burst(position: Vector3) -> GPUParticles3D:
	var particles := _get_or_create_particles(EFFECT_SWARM_BURST)
	if particles == null:
		return null

	particles.position = position
	particles.emitting = true

	_active_particles.append(particles)
	particles_spawned.emit(EFFECT_SWARM_BURST, position)

	return particles


## Spawn swarm trail effect following a unit.
func spawn_swarm_trail(unit_node: Node3D) -> void:
	if unit_node == null or not is_instance_valid(unit_node):
		return

	var particles := _get_or_create_particles(EFFECT_SWARM_TRAIL)
	if particles == null:
		return

	particles.position = unit_node.position
	particles.emitting = true
	_active_particles.append(particles)


## Spawn impact effect (forge stamp landing).
func spawn_impact(position: Vector3, faction_id: int) -> GPUParticles3D:
	var particles := _get_or_create_particles(EFFECT_IMPACT)
	if particles == null:
		return null

	particles.position = position

	# Apply faction color
	var color: Color = FACTION_COLORS.get(faction_id, Color.ORANGE)
	_apply_color_to_particles(particles, color)

	particles.emitting = true
	_active_particles.append(particles)
	particles_spawned.emit(EFFECT_IMPACT, position)

	return particles


## Spawn dust cloud effect (landing).
func spawn_dust_cloud(position: Vector3, faction_id: int) -> GPUParticles3D:
	var particles := _get_or_create_particles(EFFECT_DUST_CLOUD)
	if particles == null:
		return null

	particles.position = position
	particles.emitting = true
	_active_particles.append(particles)
	particles_spawned.emit(EFFECT_DUST_CLOUD, position)

	return particles


## Spawn leap launch effect (Dynapods).
func spawn_leap_launch(position: Vector3) -> GPUParticles3D:
	var particles := _get_or_create_particles(EFFECT_LEAP_LAUNCH)
	if particles == null:
		return null

	particles.position = position
	particles.emitting = true
	_active_particles.append(particles)
	particles_spawned.emit(EFFECT_LEAP_LAUNCH, position)

	return particles


## Spawn ground crack effect (LogiBots emergence).
func spawn_ground_crack(position: Vector3) -> GPUParticles3D:
	var particles := _get_or_create_particles(EFFECT_GROUND_CRACK)
	if particles == null:
		return null

	particles.position = position
	particles.emitting = true
	_active_particles.append(particles)
	particles_spawned.emit(EFFECT_GROUND_CRACK, position)

	return particles


## Spawn steam vent effect (LogiBots emergence).
func spawn_steam_vent(position: Vector3) -> GPUParticles3D:
	var particles := _get_or_create_particles(EFFECT_STEAM_VENT)
	if particles == null:
		return null

	particles.position = position
	particles.emitting = true
	_active_particles.append(particles)
	particles_spawned.emit(EFFECT_STEAM_VENT, position)

	return particles


## Spawn footstep dust effect.
func spawn_footstep(position: Vector3) -> GPUParticles3D:
	var particles := _get_or_create_particles(EFFECT_FOOTSTEP)
	if particles == null:
		return null

	particles.position = position
	particles.emitting = true
	_active_particles.append(particles)

	return particles


## Spawn rappel line effect (Human Remnant).
func spawn_rappel_line(start_pos: Vector3, end_pos: Vector3) -> GPUParticles3D:
	var particles := _get_or_create_particles(EFFECT_RAPPEL_LINE)
	if particles == null:
		return null

	particles.position = (start_pos + end_pos) / 2.0
	particles.emitting = true
	_active_particles.append(particles)
	particles_spawned.emit(EFFECT_RAPPEL_LINE, particles.position)

	return particles


## Get or create particles from pool.
func _get_or_create_particles(effect_type: String) -> GPUParticles3D:
	if _parent_node == null:
		return null

	var pool: Array = _particle_pool.get(effect_type, [])

	# Try to reuse from pool
	for particles in pool:
		if is_instance_valid(particles) and not particles.emitting:
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


## Create particles for an effect type.
func _create_particles(effect_type: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.lifetime = DEFAULT_LIFETIME

	match effect_type:
		EFFECT_SWARM_BURST:
			_configure_swarm_burst(particles)
		EFFECT_SWARM_TRAIL:
			_configure_swarm_trail(particles)
		EFFECT_IMPACT:
			_configure_impact(particles)
		EFFECT_DUST_CLOUD:
			_configure_dust_cloud(particles)
		EFFECT_LEAP_LAUNCH:
			_configure_leap_launch(particles)
		EFFECT_GROUND_CRACK:
			_configure_ground_crack(particles)
		EFFECT_STEAM_VENT:
			_configure_steam_vent(particles)
		EFFECT_FOOTSTEP:
			_configure_footstep(particles)
		EFFECT_RAPPEL_LINE:
			_configure_rappel_line(particles)
		_:
			_configure_impact(particles)

	return particles


## Configure swarm burst particles.
func _configure_swarm_burst(particles: GPUParticles3D) -> void:
	particles.amount = 80
	particles.lifetime = 0.8
	particles.explosiveness = 1.0

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5

	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 8.0

	material.gravity = Vector3(0, -2, 0)
	material.damping_min = 2.0
	material.damping_max = 4.0

	material.scale_min = 0.05
	material.scale_max = 0.15

	# Purple swarm color
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.8, 0.3, 1.0, 1.0))
	gradient.set_color(1, Color(0.4, 0.1, 0.6, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material
	particles.draw_pass_1 = _create_glow_mesh(Color(0.6, 0.2, 1.0))


## Configure swarm trail particles.
func _configure_swarm_trail(particles: GPUParticles3D) -> void:
	particles.amount = 30
	particles.lifetime = 0.5
	particles.one_shot = false
	particles.explosiveness = 0.0

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.3

	material.direction = Vector3(0, 0, -1)
	material.spread = 30.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.5

	material.gravity = Vector3.ZERO
	material.damping_min = 3.0
	material.damping_max = 5.0

	material.scale_min = 0.03
	material.scale_max = 0.08

	material.color = Color(0.6, 0.3, 1.0, 0.7)

	particles.process_material = material
	particles.draw_pass_1 = _create_glow_mesh(Color(0.6, 0.2, 1.0))


## Configure impact particles (forge stamp).
func _configure_impact(particles: GPUParticles3D) -> void:
	particles.amount = 60
	particles.lifetime = 1.0
	particles.explosiveness = 1.0

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 1.0
	material.emission_ring_inner_radius = 0.0
	material.emission_ring_height = 0.1
	material.emission_ring_axis = Vector3(0, 1, 0)

	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 6.0

	material.gravity = Vector3(0, -8, 0)

	material.scale_min = 0.08
	material.scale_max = 0.2

	# Orange industrial sparks
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
	gradient.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material
	particles.draw_pass_1 = _create_spark_mesh()


## Configure dust cloud particles.
func _configure_dust_cloud(particles: GPUParticles3D) -> void:
	particles.amount = 40
	particles.lifetime = 1.5
	particles.explosiveness = 0.8

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 0.8
	material.emission_ring_inner_radius = 0.0
	material.emission_ring_height = 0.3
	material.emission_ring_axis = Vector3(0, 1, 0)

	material.direction = Vector3(0, 1, 0)
	material.spread = 60.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0

	material.gravity = Vector3(0, 1, 0)  # Rises slowly
	material.damping_min = 1.0
	material.damping_max = 2.0

	material.scale_min = 0.2
	material.scale_max = 0.5

	# Dusty brown color
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.6, 0.5, 0.4, 0.6))
	gradient.set_color(1, Color(0.5, 0.4, 0.3, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material
	particles.draw_pass_1 = _create_mist_mesh()


## Configure leap launch particles (Dynapods).
func _configure_leap_launch(particles: GPUParticles3D) -> void:
	particles.amount = 50
	particles.lifetime = 0.6
	particles.explosiveness = 1.0

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 0.5
	material.emission_ring_inner_radius = 0.2
	material.emission_ring_height = 0.1
	material.emission_ring_axis = Vector3(0, 1, 0)

	material.direction = Vector3(0, -1, 0)  # Downward from launch point
	material.spread = 45.0
	material.initial_velocity_min = 4.0
	material.initial_velocity_max = 8.0

	material.gravity = Vector3(0, -5, 0)

	material.scale_min = 0.05
	material.scale_max = 0.15

	# Green energy burst
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.3, 1.0, 0.5, 1.0))
	gradient.set_color(1, Color(0.1, 0.6, 0.2, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material
	particles.draw_pass_1 = _create_glow_mesh(Color(0.2, 0.9, 0.4))


## Configure ground crack particles (LogiBots).
func _configure_ground_crack(particles: GPUParticles3D) -> void:
	particles.amount = 35
	particles.lifetime = 0.8
	particles.explosiveness = 1.0

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(1.5, 0.1, 1.5)

	material.direction = Vector3(0, 1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0

	material.gravity = Vector3(0, -15, 0)

	material.scale_min = 0.1
	material.scale_max = 0.3

	# Rock/debris color
	material.color = Color(0.5, 0.4, 0.35, 1.0)

	particles.process_material = material
	particles.draw_pass_1 = _create_debris_mesh()


## Configure steam vent particles.
func _configure_steam_vent(particles: GPUParticles3D) -> void:
	particles.amount = 60
	particles.lifetime = 2.0
	particles.explosiveness = 0.3

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 0.8
	material.emission_ring_inner_radius = 0.3
	material.emission_ring_height = 0.2
	material.emission_ring_axis = Vector3(0, 1, 0)

	material.direction = Vector3(0, 1, 0)
	material.spread = 20.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0

	material.gravity = Vector3(0, 2, 0)  # Rises
	material.damping_min = 0.5
	material.damping_max = 1.0

	material.scale_min = 0.15
	material.scale_max = 0.4

	# White steam
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.9, 0.9, 0.95, 0.7))
	gradient.set_color(1, Color(0.8, 0.8, 0.85, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material
	particles.draw_pass_1 = _create_mist_mesh()


## Configure footstep particles.
func _configure_footstep(particles: GPUParticles3D) -> void:
	particles.amount = 15
	particles.lifetime = 0.8
	particles.explosiveness = 1.0

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 0.4
	material.emission_ring_inner_radius = 0.0
	material.emission_ring_height = 0.1
	material.emission_ring_axis = Vector3(0, 1, 0)

	material.direction = Vector3(0, 1, 0)
	material.spread = 60.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.5

	material.gravity = Vector3(0, 0.5, 0)

	material.scale_min = 0.1
	material.scale_max = 0.2

	# Dust color
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.55, 0.45, 0.35, 0.5))
	gradient.set_color(1, Color(0.45, 0.35, 0.25, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material
	particles.draw_pass_1 = _create_mist_mesh()


## Configure rappel line particles (Human Remnant).
func _configure_rappel_line(particles: GPUParticles3D) -> void:
	particles.amount = 25
	particles.lifetime = 1.0
	particles.explosiveness = 0.5

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(0.1, 5.0, 0.1)  # Vertical line

	material.direction = Vector3(0, -1, 0)
	material.spread = 10.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 2.0

	material.gravity = Vector3(0, -2, 0)

	material.scale_min = 0.02
	material.scale_max = 0.05

	# Gray military color
	material.color = Color(0.4, 0.4, 0.4, 0.8)

	particles.process_material = material
	particles.draw_pass_1 = _create_spark_mesh()


## Apply faction color to particles.
func _apply_color_to_particles(particles: GPUParticles3D, color: Color) -> void:
	if particles.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = particles.process_material
		mat.color = color


## Create glow mesh.
func _create_glow_mesh(color: Color = Color.WHITE) -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat

	return mesh


## Create spark mesh.
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


## Create mist mesh.
func _create_mist_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat

	return mesh


## Create debris mesh.
func _create_debris_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.1)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.4, 0.35)
	mesh.material = mat

	return mesh


## Update particles (remove finished).
func update(_delta: float) -> void:
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
	for particles in _active_particles:
		if is_instance_valid(particles):
			particles.emitting = false

	_active_particles.clear()

	for effect_type in _particle_pool:
		var pool: Array = _particle_pool[effect_type]
		for particles in pool:
			if is_instance_valid(particles):
				particles.queue_free()
		pool.clear()


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
