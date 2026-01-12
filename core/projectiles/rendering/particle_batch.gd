class_name ParticleBatch
extends RefCounted
## ParticleBatch manages a single GPUParticles3D for one projectile type.
## Enables batch rendering of thousands of projectiles in a single draw call.

## Maximum particles per batch
const MAX_PARTICLES_PER_BATCH := 2048

## Projectile type this batch renders
var type_id: String = ""

## Visual configuration
var visual_config: ParticleVisualConfig = null

## Particle data buffer (position, velocity, color, size per particle)
var _particle_data: PackedFloat32Array

## Active particle indices (projectile_id -> particle_index)
var _projectile_to_particle: Dictionary = {}

## Free particle indices
var _free_indices: Array[int] = []

## Active count
var _active_count: int = 0

## Capacity
var _capacity: int = MAX_PARTICLES_PER_BATCH


func _init(proj_type_id: String = "", config: ParticleVisualConfig = null) -> void:
	type_id = proj_type_id
	visual_config = config
	_initialize_buffers()


## Initialize particle data buffers.
func _initialize_buffers() -> void:
	# 12 floats per particle: position(3), velocity(3), color(4), size(1), rotation(1)
	_particle_data.resize(_capacity * 12)
	_particle_data.fill(0.0)

	_free_indices.clear()
	for i in range(_capacity - 1, -1, -1):  # Reverse order for efficient pop_back
		_free_indices.append(i)

	_projectile_to_particle.clear()
	_active_count = 0


## Allocate particle slot for projectile.
func allocate_particle(projectile_id: int) -> int:
	if _free_indices.is_empty():
		return -1

	var particle_index: int = _free_indices.pop_back()
	_projectile_to_particle[projectile_id] = particle_index
	_active_count += 1

	return particle_index


## Release particle slot.
func release_particle(projectile_id: int) -> void:
	if not _projectile_to_particle.has(projectile_id):
		return

	var particle_index: int = _projectile_to_particle[projectile_id]

	# Clear particle data
	var base_idx := particle_index * 12
	for i in 12:
		_particle_data[base_idx + i] = 0.0

	_free_indices.append(particle_index)
	_projectile_to_particle.erase(projectile_id)
	_active_count -= 1


## Update particle transform.
func update_particle(
	projectile_id: int,
	position: Vector3,
	velocity: Vector3,
	rotation: float = 0.0
) -> void:
	if not _projectile_to_particle.has(projectile_id):
		return

	var particle_index: int = _projectile_to_particle[projectile_id]
	var base_idx := particle_index * 12

	# Position
	_particle_data[base_idx + 0] = position.x
	_particle_data[base_idx + 1] = position.y
	_particle_data[base_idx + 2] = position.z

	# Velocity (for motion blur/trails)
	_particle_data[base_idx + 3] = velocity.x
	_particle_data[base_idx + 4] = velocity.y
	_particle_data[base_idx + 5] = velocity.z

	# Color (from visual config)
	if visual_config != null:
		_particle_data[base_idx + 6] = visual_config.color.r
		_particle_data[base_idx + 7] = visual_config.color.g
		_particle_data[base_idx + 8] = visual_config.color.b
		_particle_data[base_idx + 9] = visual_config.color.a
	else:
		_particle_data[base_idx + 6] = 1.0
		_particle_data[base_idx + 7] = 1.0
		_particle_data[base_idx + 8] = 1.0
		_particle_data[base_idx + 9] = 1.0

	# Size
	_particle_data[base_idx + 10] = visual_config.size if visual_config != null else 0.2

	# Rotation
	_particle_data[base_idx + 11] = rotation


## Get particle data buffer.
func get_particle_data() -> PackedFloat32Array:
	return _particle_data


## Check if batch has capacity.
func has_capacity() -> bool:
	return not _free_indices.is_empty()


## Get active count.
func get_active_count() -> int:
	return _active_count


## Get capacity.
func get_capacity() -> int:
	return _capacity


## Check if projectile is in this batch.
func has_projectile(projectile_id: int) -> bool:
	return _projectile_to_particle.has(projectile_id)


## Get particle index for projectile.
func get_particle_index(projectile_id: int) -> int:
	return _projectile_to_particle.get(projectile_id, -1)


## Clear all particles.
func clear() -> void:
	_initialize_buffers()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"type_id": type_id,
		"active": _active_count,
		"capacity": _capacity,
		"free": _free_indices.size()
	}
