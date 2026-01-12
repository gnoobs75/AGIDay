class_name ProjectileRenderer
extends RefCounted
## ProjectileRenderer manages GPU particle rendering for all projectiles.
## Uses batch rendering to minimize draw calls while rendering 10,000+ projectiles.

signal batch_created(type_id: String)
signal hit_effect_requested(effect_type: String, position: Vector3, color: Color)

## Visual configs by type (type_id -> ParticleVisualConfig)
var _visual_configs: Dictionary = {}

## Particle batches by type (type_id -> Array[ParticleBatch])
var _batches: Dictionary = {}

## Projectile to batch mapping (projectile_id -> {type_id, batch_index})
var _projectile_batch_map: Dictionary = {}

## Effect queue for hit effects
var _effect_queue: Array[Dictionary] = []

## Statistics
var _stats: Dictionary = {
	"total_particles": 0,
	"total_batches": 0,
	"draw_calls": 0
}


func _init() -> void:
	_load_default_configs()


## Load default visual configurations.
func _load_default_configs() -> void:
	_visual_configs = ParticleVisualConfig.create_defaults()


## Register visual config for projectile type.
func register_visual_config(config: ParticleVisualConfig) -> void:
	_visual_configs[config.type_id] = config


## Get visual config for type.
func get_visual_config(type_id: String) -> ParticleVisualConfig:
	return _visual_configs.get(type_id)


## Allocate particle for projectile.
func allocate_particle(projectile_id: int, type_id: String) -> int:
	# Get or create batch for type
	var batch := _get_available_batch(type_id)
	if batch == null:
		batch = _create_batch(type_id)

	# Allocate particle slot
	var particle_index := batch.allocate_particle(projectile_id)
	if particle_index < 0:
		# Batch full, create new one
		batch = _create_batch(type_id)
		particle_index = batch.allocate_particle(projectile_id)

	if particle_index >= 0:
		var batch_index := _batches[type_id].find(batch)
		_projectile_batch_map[projectile_id] = {
			"type_id": type_id,
			"batch_index": batch_index
		}
		_stats["total_particles"] += 1

	return particle_index


## Release particle for projectile.
func release_particle(projectile_id: int, trigger_hit_effect: bool = false, position: Vector3 = Vector3.ZERO) -> void:
	if not _projectile_batch_map.has(projectile_id):
		return

	var mapping: Dictionary = _projectile_batch_map[projectile_id]
	var type_id: String = mapping["type_id"]
	var batch_index: int = mapping["batch_index"]

	if _batches.has(type_id) and batch_index < _batches[type_id].size():
		var batch: ParticleBatch = _batches[type_id][batch_index]
		batch.release_particle(projectile_id)

		# Trigger hit effect if requested
		if trigger_hit_effect:
			_queue_hit_effect(type_id, position)

	_projectile_batch_map.erase(projectile_id)
	_stats["total_particles"] -= 1


## Update particle transform.
func update_particle(
	projectile_id: int,
	position: Vector3,
	velocity: Vector3,
	rotation: float = 0.0
) -> void:
	if not _projectile_batch_map.has(projectile_id):
		return

	var mapping: Dictionary = _projectile_batch_map[projectile_id]
	var type_id: String = mapping["type_id"]
	var batch_index: int = mapping["batch_index"]

	if _batches.has(type_id) and batch_index < _batches[type_id].size():
		var batch: ParticleBatch = _batches[type_id][batch_index]
		batch.update_particle(projectile_id, position, velocity, rotation)


## Batch update multiple particles.
func update_particles_batch(updates: Array[Dictionary]) -> void:
	for update in updates:
		update_particle(
			update.get("id", -1),
			update.get("position", Vector3.ZERO),
			update.get("velocity", Vector3.ZERO),
			update.get("rotation", 0.0)
		)


## Get available batch with capacity.
func _get_available_batch(type_id: String) -> ParticleBatch:
	if not _batches.has(type_id):
		return null

	for batch in _batches[type_id]:
		if batch.has_capacity():
			return batch

	return null


## Create new batch for type.
func _create_batch(type_id: String) -> ParticleBatch:
	var config := _visual_configs.get(type_id)
	var batch := ParticleBatch.new(type_id, config)

	if not _batches.has(type_id):
		_batches[type_id] = []

	_batches[type_id].append(batch)
	_stats["total_batches"] += 1

	batch_created.emit(type_id)

	return batch


## Queue hit effect.
func _queue_hit_effect(type_id: String, position: Vector3) -> void:
	var config := _visual_configs.get(type_id)
	if config == null or config.hit_effect.is_empty():
		return

	_effect_queue.append({
		"effect_type": config.hit_effect,
		"position": position,
		"color": config.color
	})

	hit_effect_requested.emit(config.hit_effect, position, config.color)


## Process effect queue.
func process_effects() -> Array[Dictionary]:
	var effects := _effect_queue.duplicate()
	_effect_queue.clear()
	return effects


## Get all batch data for rendering.
func get_render_data() -> Dictionary:
	var render_data: Dictionary = {}

	for type_id in _batches:
		render_data[type_id] = []
		for batch in _batches[type_id]:
			if batch.get_active_count() > 0:
				render_data[type_id].append({
					"particle_data": batch.get_particle_data(),
					"active_count": batch.get_active_count(),
					"visual_config": batch.visual_config
				})

	return render_data


## Get batch count (equals draw calls).
func get_draw_call_count() -> int:
	var count := 0
	for type_id in _batches:
		for batch in _batches[type_id]:
			if batch.get_active_count() > 0:
				count += 1
	_stats["draw_calls"] = count
	return count


## Clear all particles.
func clear_all() -> void:
	for type_id in _batches:
		for batch in _batches[type_id]:
			batch.clear()

	_projectile_batch_map.clear()
	_effect_queue.clear()
	_stats["total_particles"] = 0


## Load configs from JSON.
func load_configs_from_json(json_path: String) -> bool:
	if not FileAccess.file_exists(json_path):
		return false

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return false

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		return false

	var data: Dictionary = json.data
	for config_data in data.get("visual_configs", []):
		var config := ParticleVisualConfig.from_dict(config_data)
		if not config.type_id.is_empty():
			register_visual_config(config)

	return true


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var configs_data: Array = []
	for type_id in _visual_configs:
		configs_data.append(_visual_configs[type_id].to_dict())

	return {
		"visual_configs": configs_data,
		"stats": _stats.duplicate()
	}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var batch_summaries: Dictionary = {}
	for type_id in _batches:
		batch_summaries[type_id] = []
		for batch in _batches[type_id]:
			batch_summaries[type_id].append(batch.get_summary())

	return {
		"total_particles": _stats["total_particles"],
		"total_batches": _stats["total_batches"],
		"draw_calls": get_draw_call_count(),
		"types": _visual_configs.size(),
		"batches": batch_summaries,
		"pending_effects": _effect_queue.size()
	}
