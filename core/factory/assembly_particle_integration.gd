class_name AssemblyParticleIntegration
extends RefCounted
## AssemblyParticleIntegration connects particle effects with assembly processes.

signal particles_emitted(assembly_id: int, particle_type: String, position: Vector3)
signal completion_particles_emitted(assembly_id: int)

## Particle pool
var _pool: ParticlePool = null

## Assembly tracking
var _assembly_particles: Dictionary = {}  ## assembly_id -> Array[AssemblyParticleEmitter]
var _assembly_themes: Dictionary = {}  ## assembly_id -> FactionAssemblyTheme

## Completion particle settings
const COMPLETION_PARTICLE_COUNT := 3
const COMPLETION_PARTICLE_DELAY := 0.1


func _init() -> void:
	_pool = ParticlePool.new()


## Initialize with parent node.
func initialize(parent: Node3D) -> void:
	_pool.set_parent(parent)
	_pool.prewarm_all(5)


## Register an assembly for particle effects.
func register_assembly(assembly_id: int, theme: FactionAssemblyTheme = null) -> void:
	_assembly_particles[assembly_id] = []
	if theme != null:
		_assembly_themes[assembly_id] = theme


## Emit particles for an assembly part.
func emit_assembly_particles(
	assembly_id: int,
	part: AssemblyPart,
	position: Vector3
) -> AssemblyParticleEmitter:
	if part == null:
		return null

	# Determine particle type
	var particle_type := part.particle_type
	if particle_type.is_empty():
		particle_type = AssemblyParticleEmitter.TYPE_WELDING

	# Map part particle types to emitter types
	particle_type = _map_particle_type(particle_type)

	# Get emitter from pool
	var emitter := _pool.get_particle_emitter(particle_type)
	if emitter == null:
		return null

	# Apply assembly theme if available
	if _assembly_themes.has(assembly_id):
		emitter.apply_theme(_assembly_themes[assembly_id])

	# Track emitter
	if _assembly_particles.has(assembly_id):
		_assembly_particles[assembly_id].append(emitter)

	# Emit particles
	emitter.emit(position, part.particle_intensity)

	particles_emitted.emit(assembly_id, particle_type, position)

	return emitter


## Emit particles at a position for a specific type.
func emit_at_position(
	assembly_id: int,
	particle_type: String,
	position: Vector3,
	intensity: float = 1.0
) -> AssemblyParticleEmitter:
	var mapped_type := _map_particle_type(particle_type)

	var emitter := _pool.get_particle_emitter(mapped_type)
	if emitter == null:
		return null

	if _assembly_themes.has(assembly_id):
		emitter.apply_theme(_assembly_themes[assembly_id])

	if _assembly_particles.has(assembly_id):
		_assembly_particles[assembly_id].append(emitter)

	emitter.emit(position, intensity)

	particles_emitted.emit(assembly_id, mapped_type, position)

	return emitter


## Emit completion particles.
func emit_completion_particles(assembly_id: int, position: Vector3) -> void:
	# Emit multiple energy particles around completion point
	for i in COMPLETION_PARTICLE_COUNT:
		var offset := Vector3(
			randf_range(-0.3, 0.3),
			randf_range(0.0, 0.5),
			randf_range(-0.3, 0.3)
		)

		var emitter := _pool.get_particle_emitter(AssemblyParticleEmitter.TYPE_ENERGY)
		if emitter != null:
			if _assembly_themes.has(assembly_id):
				emitter.apply_theme(_assembly_themes[assembly_id])

			if _assembly_particles.has(assembly_id):
				_assembly_particles[assembly_id].append(emitter)

			emitter.emit(position + offset, 1.5)

	completion_particles_emitted.emit(assembly_id)


## Map part particle type to emitter type.
func _map_particle_type(part_type: String) -> String:
	match part_type.to_lower():
		"weld_sparks", "welding":
			return AssemblyParticleEmitter.TYPE_WELDING
		"sparks", "metal_sparks":
			return AssemblyParticleEmitter.TYPE_SPARKS
		"energy_pulse", "energy", "power":
			return AssemblyParticleEmitter.TYPE_ENERGY
		"organic_mist", "organic":
			return AssemblyParticleEmitter.TYPE_ENERGY
		"circuit_sparks", "circuit":
			return AssemblyParticleEmitter.TYPE_SPARKS
		_:
			return AssemblyParticleEmitter.TYPE_WELDING


## Update integration (call each frame).
func update(delta: float) -> void:
	_pool.update(delta)


## Cleanup particles for an assembly.
func cleanup_assembly(assembly_id: int) -> void:
	if not _assembly_particles.has(assembly_id):
		return

	# Return all emitters to pool
	for emitter in _assembly_particles[assembly_id]:
		_pool.return_particle_emitter(emitter)

	_assembly_particles.erase(assembly_id)
	_assembly_themes.erase(assembly_id)


## Set theme for an assembly.
func set_assembly_theme(assembly_id: int, theme: FactionAssemblyTheme) -> void:
	_assembly_themes[assembly_id] = theme


## Get pool.
func get_pool() -> ParticlePool:
	return _pool


## Cleanup all.
func cleanup() -> void:
	for assembly_id in _assembly_particles.keys():
		cleanup_assembly(assembly_id)

	_pool.cleanup()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var assembly_counts: Dictionary = {}
	for assembly_id in _assembly_particles:
		assembly_counts[assembly_id] = _assembly_particles[assembly_id].size()

	return {
		"active_assemblies": _assembly_particles.size(),
		"assembly_emitters": assembly_counts,
		"pool": _pool.get_summary()
	}
