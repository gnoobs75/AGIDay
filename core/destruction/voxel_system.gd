class_name VoxelSystem
extends Node
## VoxelSystem is the main facade integrating all voxel subsystems.
## Provides unified API for destruction, repair, persistence, and visualization.

signal voxel_damaged(position: Vector3i, damage: float, new_hp: float)
signal voxel_destroyed(position: Vector3i)
signal voxel_repaired(position: Vector3i, new_stage: int)
signal pathfinding_update_needed(positions: Array[Vector3i])
signal power_node_state_changed(position: Vector3i, destroyed: bool)

## Subsystem references
var chunk_manager: VoxelChunkManager = null
var mesh_manager: VoxelMeshManager = null
var effects: VoxelEffects = null
var persistence: VoxelPersistence = null
var streamer: VoxelChunkStreamer = null
var repair_system: VoxelRepairSystem = null

## Pathfinding bridge callback
var _pathfinding_callback: Callable = Callable()

## Power grid bridge callback
var _power_grid_callback: Callable = Callable()

## Batched pathfinding updates
var _pending_nav_updates: Array[Vector3i] = []
var _nav_update_timer: float = 0.0
const NAV_UPDATE_INTERVAL := 0.1  ## Batch updates every 100ms

## Seeded RNG for procedural generation
var _rng: RandomNumberGenerator = null
var _world_seed: int = 0


func _ready() -> void:
	_initialize_subsystems()


func _process(delta: float) -> void:
	# Process subsystems
	if chunk_manager != null:
		chunk_manager.process(delta)

	if mesh_manager != null:
		mesh_manager.process(delta)

	if effects != null:
		effects.process(delta)

	if streamer != null:
		streamer.process(delta)

	# Batch pathfinding updates
	_nav_update_timer += delta
	if _nav_update_timer >= NAV_UPDATE_INTERVAL and not _pending_nav_updates.is_empty():
		_nav_update_timer = 0.0
		_flush_nav_updates()


## Initialize all subsystems.
func _initialize_subsystems() -> void:
	# Create chunk manager
	chunk_manager = VoxelChunkManager.new()
	chunk_manager.voxel_damaged.connect(_on_voxel_damaged)
	chunk_manager.voxel_stage_changed.connect(_on_voxel_stage_changed)
	chunk_manager.voxel_destroyed.connect(_on_voxel_destroyed)

	# Create persistence
	persistence = VoxelPersistence.new(chunk_manager)

	# Create effects
	effects = VoxelEffects.new()
	effects.initialize(self)

	# Create mesh manager
	mesh_manager = VoxelMeshManager.new()
	mesh_manager.initialize(chunk_manager, self)

	# Create streamer
	streamer = VoxelChunkStreamer.new()
	streamer.initialize(chunk_manager, mesh_manager, persistence)

	# Create repair system
	repair_system = VoxelRepairSystem.new()
	repair_system.set_chunk_manager(chunk_manager)
	repair_system.repair_completed.connect(_on_repair_completed)


## Initialize with world seed for procedural generation.
func initialize_world(seed_value: int) -> void:
	_world_seed = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


## Set camera position for LOD and streaming.
func set_camera_position(position: Vector3) -> void:
	if mesh_manager != null:
		mesh_manager.set_camera_position(position)
	if streamer != null:
		streamer.set_camera_transform(position, Vector3.FORWARD)
	if persistence != null:
		persistence.manage_memory(position)


## Set camera frustum for culling.
func set_camera_frustum(planes: Array) -> void:
	if streamer != null:
		streamer.set_frustum_planes(planes)


## Set pathfinding update callback.
## Callback signature: func(positions: Array[Vector3i]) -> void
func set_pathfinding_callback(callback: Callable) -> void:
	_pathfinding_callback = callback


## Set power grid callback.
## Callback signature: func(position: Vector3i, destroyed: bool) -> void
func set_power_grid_callback(callback: Callable) -> void:
	_power_grid_callback = callback


## Apply damage to voxel at position.
func damage_voxel(position: Vector3i, damage: int, source: String = "") -> void:
	if chunk_manager != null:
		chunk_manager.queue_damage(position, damage, source)


## Apply damage immediately (bypasses queue).
func damage_voxel_immediate(position: Vector3i, damage: int) -> void:
	if chunk_manager != null:
		chunk_manager.damage_voxel_immediate(position, damage)


## Apply area damage.
func damage_area(center: Vector3i, radius: int, damage: int, source: String = "") -> void:
	var radius_sq := radius * radius

	for z in range(center.z - radius, center.z + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var dx := x - center.x
			var dz := z - center.z
			if dx * dx + dz * dz <= radius_sq:
				var pos := Vector3i(x, 0, z)
				# Distance falloff
				var dist := sqrt(float(dx * dx + dz * dz))
				var falloff := 1.0 - (dist / float(radius))
				var effective_damage := int(damage * falloff)
				if effective_damage > 0:
					damage_voxel(pos, effective_damage, source)

	# Spawn mass destruction effect
	if effects != null and radius > 3:
		effects.spawn_mass_destruction(Vector3(center), float(radius))


## Repair voxel at position.
func repair_voxel(position: Vector3i, heal: int) -> void:
	if chunk_manager != null:
		chunk_manager.queue_repair(position, heal)


## Start builder repair process.
func start_repair(
	builder_id: int,
	voxel_position: Vector3i,
	builder_position: Vector3,
	repair_speed: float,
	faction_id: String
) -> bool:
	if repair_system != null:
		return repair_system.start_repair(
			builder_id, voxel_position, builder_position, repair_speed, faction_id
		)
	return false


## Update builder repair progress.
func update_repair(builder_id: int, delta: float) -> void:
	if repair_system != null:
		repair_system.update_repair(builder_id, delta)


## Cancel builder repair.
func cancel_repair(builder_id: int) -> void:
	if repair_system != null:
		repair_system.cancel_repair(builder_id)


## Get voxel at position.
func get_voxel(position: Vector3i) -> VoxelState:
	if chunk_manager != null:
		return chunk_manager.get_voxel(position)
	return null


## Check if position is valid.
func is_valid_position(position: Vector3i) -> bool:
	if chunk_manager != null:
		return chunk_manager.is_valid_position(position)
	return false


## Check if position is traversable.
func is_traversable(position: Vector3i) -> bool:
	var voxel := get_voxel(position)
	if voxel == null:
		return false
	return voxel.is_traversable()


## Register power node at position.
func register_power_node(position: Vector3i) -> void:
	if chunk_manager != null:
		chunk_manager.register_special_node(position, "power_node")


## Register strategic pathway at position.
func register_strategic_pathway(position: Vector3i) -> void:
	if chunk_manager != null:
		chunk_manager.register_special_node(position, "strategic")


## Get all damaged voxels.
func get_all_damaged_voxels() -> Array[VoxelState]:
	if chunk_manager != null:
		return chunk_manager.get_all_damaged_voxels()
	return []


## Get damaged voxels in radius.
func get_damaged_voxels_in_radius(center: Vector3i, radius: int) -> Array[VoxelState]:
	if chunk_manager != null:
		return chunk_manager.get_damaged_voxels_in_radius(center, radius)
	return []


## Save voxel state to file.
func save_to_file(path: String) -> bool:
	if persistence != null:
		return persistence.save_to_file(path)
	return false


## Load voxel state from file.
func load_from_file(path: String) -> bool:
	if persistence != null:
		var result := persistence.load_from_file(path)
		if result and mesh_manager != null:
			mesh_manager.rebuild_all_meshes()
		return result
	return false


## Create snapshot for save system.
func create_snapshot() -> PackedByteArray:
	if persistence != null:
		return persistence.create_snapshot()
	return PackedByteArray()


## Load snapshot.
func load_snapshot(data: PackedByteArray) -> bool:
	if persistence != null:
		var result := persistence.load_snapshot(data)
		if result and mesh_manager != null:
			mesh_manager.rebuild_all_meshes()
		return result
	return false


## Serialize to dictionary for ECS.
func to_dict() -> Dictionary:
	var data := {}
	if chunk_manager != null:
		data["chunks"] = chunk_manager.to_dict()
	data["seed"] = _world_seed
	return data


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_world_seed = data.get("seed", 0)
	if _world_seed != 0:
		_rng = RandomNumberGenerator.new()
		_rng.seed = _world_seed

	if chunk_manager != null and data.has("chunks"):
		chunk_manager.from_dict(data["chunks"])
		if mesh_manager != null:
			mesh_manager.rebuild_all_meshes()


## Generate procedural voxel data using seeded RNG.
func generate_procedural(generator_callback: Callable) -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = Time.get_ticks_msec()

	# Pass RNG to generator for deterministic generation
	generator_callback.call(_rng, chunk_manager)

	# Rebuild all meshes after generation
	if mesh_manager != null:
		mesh_manager.rebuild_all_meshes()


## Handle voxel damaged event.
func _on_voxel_damaged(position: Vector3i, damage: float, new_hp: float) -> void:
	voxel_damaged.emit(position, damage, new_hp)


## Handle voxel stage changed event.
func _on_voxel_stage_changed(position: Vector3i, old_stage: int, new_stage: int) -> void:
	# Spawn visual effect
	if effects != null:
		effects.spawn_stage_transition_effect(Vector3(position), old_stage, new_stage)

	# Queue pathfinding update if traversability changed
	var was_traversable := VoxelStage.is_traversable(old_stage)
	var is_trav := VoxelStage.is_traversable(new_stage)

	if was_traversable != is_trav:
		_pending_nav_updates.append(position)

	# Check power node
	var voxel := get_voxel(position)
	if voxel != null and voxel.is_power_node():
		var destroyed := new_stage >= VoxelStage.Stage.RUBBLE
		power_node_state_changed.emit(position, destroyed)
		if _power_grid_callback.is_valid():
			_power_grid_callback.call(position, destroyed)


## Handle voxel destroyed event.
func _on_voxel_destroyed(position: Vector3i) -> void:
	voxel_destroyed.emit(position)


## Handle repair completed event.
func _on_repair_completed(builder_id: int, position: Vector3i, new_stage: int) -> void:
	voxel_repaired.emit(position, new_stage)

	# May need nav update
	_pending_nav_updates.append(position)


## Flush batched navigation updates.
func _flush_nav_updates() -> void:
	if _pending_nav_updates.is_empty():
		return

	var updates := _pending_nav_updates.duplicate()
	_pending_nav_updates.clear()

	pathfinding_update_needed.emit(updates)

	if _pathfinding_callback.is_valid():
		_pathfinding_callback.call(updates)


## Get system statistics.
func get_statistics() -> Dictionary:
	var stats := {
		"world_seed": _world_seed
	}

	if chunk_manager != null:
		stats["chunks"] = chunk_manager.get_summary()

	if mesh_manager != null:
		stats["meshes"] = mesh_manager.get_statistics()

	if effects != null:
		stats["effects"] = effects.get_statistics()

	if persistence != null:
		stats["persistence"] = persistence.get_statistics()

	if streamer != null:
		stats["streaming"] = streamer.get_statistics()

	if repair_system != null:
		stats["repair"] = repair_system.get_summary()

	return stats


## Cleanup all subsystems.
func cleanup() -> void:
	if mesh_manager != null:
		mesh_manager.cleanup()

	if effects != null:
		effects.cleanup()

	chunk_manager = null
	mesh_manager = null
	effects = null
	persistence = null
	streamer = null
	repair_system = null
