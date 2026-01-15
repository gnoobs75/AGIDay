class_name MultiMeshRenderer
extends RefCounted
## MultiMeshRenderer manages large-scale unit rendering across all factions.
## Reduces draw calls from 5000+ to ~20 by batching units by faction/type.

signal rendering_updated(draw_calls: int, transform_updates: int)
signal pool_created(faction_id: int, unit_type: String)

## Faction IDs
const FACTION_AETHER := 0
const FACTION_OPTIFORGE := 1
const FACTION_DYNAPODS := 2
const FACTION_LOGIBOTS := 3
const FACTION_HUMAN := 4

## Configuration
const MAX_INSTANCES_PER_MESH := 5000
const BATCH_UPDATE_SIZE := 100
const DIRTY_CHECK_INTERVAL := 0.016  ## ~60fps

## Pool storage: faction_id -> unit_type -> MultiMeshPool
var _faction_pools: Dictionary = {}

## Unit tracking
var _unit_registry: Dictionary = {}  ## unit_id -> {faction_id, unit_type, instance_idx, transform, dirty}

## Dirty tracking for lazy updates
var _dirty_units: Dictionary = {}  ## unit_id -> true

## Dead unit batching
var _dead_units: Array[int] = []

## Scene root
var _scene_root: Node3D = null

## Mesh resources
var _mesh_library: Dictionary = {}  ## faction_id -> unit_type -> Mesh

## Statistics
var _draw_call_count := 0
var _transform_update_count := 0
var _last_update_time := 0.0


func _init() -> void:
	pass


## Initialize renderer with scene root.
func initialize(scene_root: Node3D) -> void:
	_scene_root = scene_root
	_setup_faction_pools()
	_load_mesh_library()


## Setup pools for each faction.
func _setup_faction_pools() -> void:
	for faction_id in [FACTION_AETHER, FACTION_OPTIFORGE, FACTION_DYNAPODS, FACTION_LOGIBOTS, FACTION_HUMAN]:
		_faction_pools[faction_id] = {}


## Load mesh library (placeholder meshes for now).
func _load_mesh_library() -> void:
	# Aether Swarm - small, numerous
	_register_faction_meshes(FACTION_AETHER, {
		"drone": _create_unit_mesh(0.3, Color(0.0, 0.8, 0.9)),
		"scout": _create_unit_mesh(0.4, Color(0.0, 0.7, 0.8)),
		"infiltrator": _create_unit_mesh(0.5, Color(0.0, 0.6, 0.7)),
		"phaser": _create_unit_mesh(0.6, Color(0.0, 0.9, 1.0))
	})

	# OptiForge Legion - medium humanoids
	_register_faction_meshes(FACTION_OPTIFORGE, {
		"grunt": _create_unit_mesh(0.5, Color(0.8, 0.4, 0.0)),
		"soldier": _create_unit_mesh(0.6, Color(0.9, 0.5, 0.1)),
		"heavy": _create_unit_mesh(0.8, Color(0.7, 0.3, 0.0)),
		"elite": _create_unit_mesh(0.7, Color(1.0, 0.6, 0.2))
	})

	# Dynapods Vanguard - agile quads
	_register_faction_meshes(FACTION_DYNAPODS, {
		"runner": _create_unit_mesh(0.5, Color(0.2, 0.8, 0.2)),
		"striker": _create_unit_mesh(0.6, Color(0.3, 0.9, 0.3)),
		"acrobat": _create_unit_mesh(0.55, Color(0.1, 0.7, 0.1)),
		"juggernaut": _create_unit_mesh(1.0, Color(0.0, 0.6, 0.0))
	})

	# LogiBots Colossus - heavy siege
	_register_faction_meshes(FACTION_LOGIBOTS, {
		"worker": _create_unit_mesh(0.6, Color(0.5, 0.5, 0.7)),
		"defender": _create_unit_mesh(0.8, Color(0.6, 0.6, 0.8)),
		"artillery": _create_unit_mesh(1.0, Color(0.4, 0.4, 0.6)),
		"titan": _create_unit_mesh(1.5, Color(0.7, 0.7, 0.9))
	})

	# Human Remnant - military
	_register_faction_meshes(FACTION_HUMAN, {
		"soldier": _create_unit_mesh(0.5, Color(0.4, 0.5, 0.3)),
		"heavy": _create_unit_mesh(0.7, Color(0.3, 0.4, 0.2)),
		"vehicle": _create_unit_mesh(1.2, Color(0.5, 0.5, 0.4))
	})


## Register meshes for a faction.
func _register_faction_meshes(faction_id: int, meshes: Dictionary) -> void:
	_mesh_library[faction_id] = meshes


## Create a simple unit mesh.
func _create_unit_mesh(size: float, color: Color) -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, size * 1.5, size)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material

	return mesh


## Get or create pool for faction/type.
func _get_or_create_pool(faction_id: int, unit_type: String) -> MultiMeshPool:
	if not _faction_pools.has(faction_id):
		_faction_pools[faction_id] = {}

	var faction_pools: Dictionary = _faction_pools[faction_id]

	if not faction_pools.has(unit_type):
		var pool := MultiMeshPool.new()
		pool.initialize(_scene_root)

		var mesh := _get_mesh(faction_id, unit_type)
		pool.create_pool("%d_%s" % [faction_id, unit_type], mesh, 500)

		faction_pools[unit_type] = pool
		_draw_call_count += 1
		pool_created.emit(faction_id, unit_type)

	return faction_pools[unit_type]


## Get mesh for faction/type.
func _get_mesh(faction_id: int, unit_type: String) -> Mesh:
	if _mesh_library.has(faction_id):
		var faction_meshes: Dictionary = _mesh_library[faction_id]
		if faction_meshes.has(unit_type):
			return faction_meshes[unit_type]

	# Return default mesh
	return _create_unit_mesh(0.5, Color.WHITE)


## Register unit for rendering.
func register_unit(unit_id: int, faction_id: int, unit_type: String, transform: Transform3D) -> void:
	var pool := _get_or_create_pool(faction_id, unit_type)
	var pool_key := "%d_%s" % [faction_id, unit_type]

	var instance_idx := pool.add_instance(pool_key, unit_id, transform)

	_unit_registry[unit_id] = {
		"faction_id": faction_id,
		"unit_type": unit_type,
		"instance_idx": instance_idx,
		"transform": transform,
		"dirty": false
	}


## Unregister unit from rendering.
func unregister_unit(unit_id: int) -> void:
	if not _unit_registry.has(unit_id):
		return

	var info: Dictionary = _unit_registry[unit_id]
	var pool := _get_or_create_pool(info["faction_id"], info["unit_type"])
	var pool_key := "%d_%s" % [info["faction_id"], info["unit_type"]]

	pool.remove_instance(pool_key, unit_id)
	_unit_registry.erase(unit_id)
	_dirty_units.erase(unit_id)


## Mark unit transform as dirty.
func mark_dirty(unit_id: int, new_transform: Transform3D) -> void:
	if not _unit_registry.has(unit_id):
		return

	var info: Dictionary = _unit_registry[unit_id]
	info["transform"] = new_transform
	info["dirty"] = true
	_dirty_units[unit_id] = true


## Queue dead unit for batch removal.
func queue_dead_unit(unit_id: int) -> void:
	if _unit_registry.has(unit_id):
		_dead_units.append(unit_id)


## Update MultiMesh rendering - call each frame.
func update_multimesh_rendering() -> void:
	var start_time := Time.get_ticks_usec()
	_transform_update_count = 0

	# Process dirty units in batches
	var processed := 0
	var dirty_ids := _dirty_units.keys()

	for unit_id in dirty_ids:
		if processed >= BATCH_UPDATE_SIZE:
			break

		if not _unit_registry.has(unit_id):
			_dirty_units.erase(unit_id)
			continue

		var info: Dictionary = _unit_registry[unit_id]
		if info["dirty"]:
			var pool := _get_or_create_pool(info["faction_id"], info["unit_type"])
			var pool_key := "%d_%s" % [info["faction_id"], info["unit_type"]]

			pool.update_transform(pool_key, unit_id, info["transform"])
			info["dirty"] = false
			_dirty_units.erase(unit_id)
			_transform_update_count += 1
			processed += 1

	# Batch process dead units
	_process_dead_units()

	# Process any pending pool updates
	for faction_id in _faction_pools:
		for unit_type in _faction_pools[faction_id]:
			var pool: MultiMeshPool = _faction_pools[faction_id][unit_type]
			pool.process_pending_updates()

	_last_update_time = (Time.get_ticks_usec() - start_time) / 1000.0
	rendering_updated.emit(_draw_call_count, _transform_update_count)


## Process dead units in batch.
func _process_dead_units() -> void:
	if _dead_units.is_empty():
		return

	# Process all dead units at once
	for unit_id in _dead_units:
		unregister_unit(unit_id)

	_dead_units.clear()


## Get unit count by faction.
func get_unit_count_by_faction(faction_id: int) -> int:
	var count := 0
	if _faction_pools.has(faction_id):
		for unit_type in _faction_pools[faction_id]:
			var pool: MultiMeshPool = _faction_pools[faction_id][unit_type]
			count += pool.get_total_instances()
	return count


## Get total unit count.
func get_total_unit_count() -> int:
	var count := 0
	for faction_id in _faction_pools:
		count += get_unit_count_by_faction(faction_id)
	return count


## Get draw call count.
func get_draw_call_count() -> int:
	return _draw_call_count


## Get statistics.
func get_statistics() -> Dictionary:
	var faction_stats: Dictionary = {}
	for faction_id in _faction_pools:
		faction_stats[faction_id] = {}
		for unit_type in _faction_pools[faction_id]:
			var pool: MultiMeshPool = _faction_pools[faction_id][unit_type]
			faction_stats[faction_id][unit_type] = pool.get_statistics()

	return {
		"draw_calls": _draw_call_count,
		"transform_updates": _transform_update_count,
		"dirty_units": _dirty_units.size(),
		"dead_queue": _dead_units.size(),
		"total_units": get_total_unit_count(),
		"update_time_ms": _last_update_time,
		"factions": faction_stats
	}


## Cleanup all rendering.
func cleanup() -> void:
	for faction_id in _faction_pools:
		for unit_type in _faction_pools[faction_id]:
			var pool: MultiMeshPool = _faction_pools[faction_id][unit_type]
			pool.cleanup()

	_faction_pools.clear()
	_unit_registry.clear()
	_dirty_units.clear()
	_dead_units.clear()
	_draw_call_count = 0
