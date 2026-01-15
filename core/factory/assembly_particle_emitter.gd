class_name AssemblyParticleEmitter
extends RefCounted
## AssemblyParticleEmitter creates and manages GPUParticles3D for assembly effects.

signal emission_started(particle_type: String)
signal emission_completed(particle_type: String)

## Particle type constants
const TYPE_WELDING := "welding"
const TYPE_SPARKS := "sparks"
const TYPE_ENERGY := "energy"

## Default particle counts
const WELDING_PARTICLES := 50
const SPARK_PARTICLES := 100
const ENERGY_PARTICLES := 30

## Default lifetimes
const WELDING_LIFETIME := 0.5
const SPARK_LIFETIME := 1.0
const ENERGY_LIFETIME := 0.8

## Emitter state
var _particles: GPUParticles3D = null
var _particle_type: String = ""
var _is_emitting: bool = false
var _intensity: float = 1.0

## Faction theme colors
var _primary_color: Color = Color(1.0, 0.7, 0.2)  # Default welding orange
var _secondary_color: Color = Color.WHITE
var _intensity_multiplier: float = 1.0


func _init() -> void:
	pass


## Create emitter for a specific particle type.
func create_emitter(particle_type: String, parent: Node3D = null) -> GPUParticles3D:
	_particle_type = particle_type
	_particles = GPUParticles3D.new()
	_particles.one_shot = true
	_particles.emitting = false

	# Configure based on type
	match particle_type:
		TYPE_WELDING:
			_configure_welding()
		TYPE_SPARKS:
			_configure_sparks()
		TYPE_ENERGY:
			_configure_energy()
		_:
			_configure_welding()

	if parent != null:
		parent.add_child(_particles)

	return _particles


## Configure welding particles (50 particles, 0.5s lifetime).
func _configure_welding() -> void:
	_particles.amount = WELDING_PARTICLES
	_particles.lifetime = WELDING_LIFETIME
	_particles.explosiveness = 0.9
	_particles.randomness = 0.2

	var material := create_welding_material()
	_particles.process_material = material
	_particles.draw_pass_1 = _create_welding_mesh()


## Configure spark particles (100 particles, 1.0s lifetime).
func _configure_sparks() -> void:
	_particles.amount = SPARK_PARTICLES
	_particles.lifetime = SPARK_LIFETIME
	_particles.explosiveness = 0.8
	_particles.randomness = 0.3

	var material := create_spark_material()
	_particles.process_material = material
	_particles.draw_pass_1 = _create_spark_mesh()


## Configure energy particles (30 particles, 0.8s lifetime).
func _configure_energy() -> void:
	_particles.amount = ENERGY_PARTICLES
	_particles.lifetime = ENERGY_LIFETIME
	_particles.explosiveness = 0.5
	_particles.randomness = 0.4

	var material := create_energy_material()
	_particles.process_material = material
	_particles.draw_pass_1 = _create_energy_mesh()


## Create welding particle material.
func create_welding_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()

	# Emission shape - point source
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.05

	# Direction and velocity
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0

	# Physics
	material.gravity = Vector3(0, -12.0, 0)
	material.damping_min = 0.5
	material.damping_max = 1.5

	# Scale
	material.scale_min = 0.02
	material.scale_max = 0.04

	# Color with faction influence
	var color := _primary_color
	color.a = 1.0
	material.color = color

	# Color gradient (fade out)
	var gradient := Gradient.new()
	gradient.add_point(0.0, color)
	gradient.add_point(0.7, Color(color.r, color.g * 0.8, color.b * 0.5, 0.8))
	gradient.add_point(1.0, Color(color.r * 0.5, 0.1, 0.0, 0.0))

	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	return material


## Create spark particle material.
func create_spark_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()

	# Emission shape - sphere burst
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.1

	# Direction and velocity
	material.direction = Vector3(0, 1, 0)
	material.spread = 90.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 8.0

	# Physics
	material.gravity = Vector3(0, -9.8, 0)
	material.damping_min = 1.0
	material.damping_max = 3.0

	# Scale
	material.scale_min = 0.01
	material.scale_max = 0.025

	# Bright spark color
	var spark_color := Color(1.0, 0.9, 0.6)
	material.color = spark_color

	# Gradient for spark trail
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.2, spark_color)
	gradient.add_point(0.6, Color(1.0, 0.5, 0.1, 0.6))
	gradient.add_point(1.0, Color(0.3, 0.1, 0.0, 0.0))

	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	return material


## Create energy particle material.
func create_energy_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()

	# Emission shape - ring
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 0.3
	material.emission_ring_inner_radius = 0.1
	material.emission_ring_height = 0.1
	material.emission_ring_axis = Vector3(0, 1, 0)

	# Direction - outward radial
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.5
	material.radial_velocity_min = 0.5
	material.radial_velocity_max = 1.0

	# No gravity - floats
	material.gravity = Vector3.ZERO

	# Scale oscillation
	material.scale_min = 0.05
	material.scale_max = 0.15

	# Energy color with faction influence
	var energy_color := _secondary_color
	if energy_color == Color.WHITE:
		energy_color = Color(0.4, 0.7, 1.0)
	material.color = energy_color

	# Gradient for energy fade
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(energy_color.r, energy_color.g, energy_color.b, 0.0))
	gradient.add_point(0.2, Color(energy_color.r, energy_color.g, energy_color.b, 0.8))
	gradient.add_point(0.8, energy_color)
	gradient.add_point(1.0, Color(energy_color.r, energy_color.g, energy_color.b, 0.0))

	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	return material


## Create welding mesh (elongated spark).
func _create_welding_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, 0.08)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = _primary_color
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat

	return mesh


## Create spark mesh (tiny point).
func _create_spark_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.01
	mesh.height = 0.02
	mesh.radial_segments = 4
	mesh.rings = 2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_energy_multiplier = 5.0
	mesh.material = mat

	return mesh


## Create energy mesh (glowing sphere).
func _create_energy_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 8
	mesh.rings = 4

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.8)
	mat.emission_enabled = true
	mat.emission = _secondary_color if _secondary_color != Color.WHITE else Color(0.4, 0.7, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat

	return mesh


## Set faction theme colors.
func set_faction_colors(primary: Color, secondary: Color, intensity_mult: float = 1.0) -> void:
	_primary_color = primary
	_secondary_color = secondary
	_intensity_multiplier = intensity_mult

	# Rebuild materials with new colors if emitter exists
	if _particles != null and _particles.process_material != null:
		match _particle_type:
			TYPE_WELDING:
				_particles.process_material = create_welding_material()
			TYPE_SPARKS:
				_particles.process_material = create_spark_material()
			TYPE_ENERGY:
				_particles.process_material = create_energy_material()


## Apply faction theme directly.
func apply_theme(theme: FactionAssemblyTheme) -> void:
	if theme == null:
		return

	set_faction_colors(
		theme.particle_color,
		theme.glow_color,
		theme.particle_intensity_multiplier
	)


## Emit particles at position.
func emit(position: Vector3, intensity: float = 1.0) -> void:
	if _particles == null:
		return

	_intensity = clampf(intensity * _intensity_multiplier, 0.0, 2.0)
	_particles.position = position
	_particles.amount = int(_particles.amount * _intensity)
	_particles.emitting = true
	_is_emitting = true

	emission_started.emit(_particle_type)


## Stop emission.
func stop() -> void:
	if _particles != null:
		_particles.emitting = false
	_is_emitting = false


## Check if currently emitting.
func is_emitting() -> bool:
	if _particles != null:
		return _particles.emitting
	return false


## Get particles node.
func get_particles() -> GPUParticles3D:
	return _particles


## Get particle type.
func get_type() -> String:
	return _particle_type


## Reset emitter for reuse.
func reset() -> void:
	stop()
	if _particles != null:
		var amount: int = WELDING_PARTICLES
		match _particle_type:
			TYPE_WELDING:
				amount = WELDING_PARTICLES
			TYPE_SPARKS:
				amount = SPARK_PARTICLES
			TYPE_ENERGY:
				amount = ENERGY_PARTICLES
		_particles.amount = amount


## Cleanup.
func cleanup() -> void:
	stop()
	if _particles != null and is_instance_valid(_particles):
		_particles.queue_free()
	_particles = null


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"particle_type": _particle_type,
		"is_emitting": is_emitting(),
		"intensity": _intensity,
		"has_particles": _particles != null,
		"primary_color": _primary_color,
		"intensity_multiplier": _intensity_multiplier
	}
