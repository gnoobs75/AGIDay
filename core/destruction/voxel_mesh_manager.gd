class_name VoxelMeshManager
extends RefCounted
## VoxelMeshManager handles mesh generation and updates for voxel chunks.
## Provides async mesh rebuilding with LOD support for large voxel grids.

signal mesh_updated(chunk_id: int)
signal mesh_rebuild_started(chunk_id: int)
signal mesh_rebuild_completed(chunk_id: int)
signal all_meshes_updated()

## LOD distances (squared for efficient comparison)
const LOD_DISTANCE_HIGH := 64 * 64           ## Full detail
const LOD_DISTANCE_MEDIUM := 128 * 128       ## Medium detail
const LOD_DISTANCE_LOW := 256 * 256          ## Low detail
const LOD_DISTANCE_CULL := 512 * 512         ## Don't render

## Mesh update queue priority
const PRIORITY_IMMEDIATE := 0
const PRIORITY_HIGH := 1
const PRIORITY_MEDIUM := 2
const PRIORITY_LOW := 3

## Max mesh updates per frame
const MAX_UPDATES_PER_FRAME := 4

## Chunk mesh data
class ChunkMesh:
	var chunk_id: int = 0
	var mesh_instance: MeshInstance3D = null
	var current_lod: int = 0
	var last_update_version: int = 0
	var is_visible: bool = true
	var world_position: Vector3 = Vector3.ZERO
	var needs_rebuild: bool = false


## Chunk manager reference
var _chunk_manager: VoxelChunkManager = null

## Mesh instances per chunk
var _chunk_meshes: Dictionary = {}  ## chunk_id -> ChunkMesh

## Parent node for mesh instances
var _mesh_parent: Node3D = null

## Update queue (priority -> Array[chunk_id])
var _update_queue: Dictionary = {
	PRIORITY_IMMEDIATE: [],
	PRIORITY_HIGH: [],
	PRIORITY_MEDIUM: [],
	PRIORITY_LOW: []
}

## Camera position for LOD/culling
var _camera_position: Vector3 = Vector3.ZERO

## Materials for each destruction state
var _materials: Dictionary = {}  ## stage -> Material

## Thread for async mesh building
var _worker_thread: Thread = null
var _thread_mutex: Mutex = null
var _pending_builds: Array[int] = []
var _completed_builds: Dictionary = {}  ## chunk_id -> mesh_data


func _init() -> void:
	_thread_mutex = Mutex.new()


## Initialize with chunk manager and parent node.
func initialize(chunk_manager: VoxelChunkManager, parent: Node3D) -> void:
	_chunk_manager = chunk_manager
	_mesh_parent = parent

	# Create default materials
	_create_default_materials()

	# Connect to chunk manager signals
	if _chunk_manager != null:
		_chunk_manager.chunk_modified.connect(_on_chunk_modified)
		_chunk_manager.voxel_stage_changed.connect(_on_voxel_stage_changed)

	# Initialize mesh instances for all chunks
	for i in VoxelChunkManager.TOTAL_CHUNKS:
		_create_chunk_mesh(i)


## Create default materials for destruction stages.
func _create_default_materials() -> void:
	# Intact - solid building material
	var intact_mat := StandardMaterial3D.new()
	intact_mat.albedo_color = Color(0.7, 0.7, 0.75)
	intact_mat.roughness = 0.8
	_materials[VoxelStage.Stage.INTACT] = intact_mat

	# Cracked - damaged material with darker tint
	var cracked_mat := StandardMaterial3D.new()
	cracked_mat.albedo_color = Color(0.5, 0.45, 0.4)
	cracked_mat.roughness = 0.9
	_materials[VoxelStage.Stage.CRACKED] = cracked_mat

	# Rubble - debris material
	var rubble_mat := StandardMaterial3D.new()
	rubble_mat.albedo_color = Color(0.4, 0.35, 0.3)
	rubble_mat.roughness = 1.0
	_materials[VoxelStage.Stage.RUBBLE] = rubble_mat

	# Crater - dark empty material
	var crater_mat := StandardMaterial3D.new()
	crater_mat.albedo_color = Color(0.2, 0.18, 0.15)
	crater_mat.roughness = 1.0
	_materials[VoxelStage.Stage.CRATER] = crater_mat


## Set custom material for stage.
func set_stage_material(stage: int, material: Material) -> void:
	_materials[stage] = material


## Create mesh instance for chunk.
func _create_chunk_mesh(chunk_id: int) -> void:
	var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
	if chunk == null:
		return

	var chunk_mesh := ChunkMesh.new()
	chunk_mesh.chunk_id = chunk_id
	chunk_mesh.world_position = Vector3(
		chunk.world_offset.x + VoxelChunk.CHUNK_SIZE / 2.0,
		0,
		chunk.world_offset.z + VoxelChunk.CHUNK_SIZE / 2.0
	)

	# Create mesh instance
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ChunkMesh_%d" % chunk_id
	mesh_instance.position = Vector3(chunk.world_offset.x, 0, chunk.world_offset.z)

	if _mesh_parent != null:
		_mesh_parent.add_child(mesh_instance)

	chunk_mesh.mesh_instance = mesh_instance
	chunk_mesh.needs_rebuild = true
	_chunk_meshes[chunk_id] = chunk_mesh

	# Queue initial build
	queue_mesh_update(chunk_id, PRIORITY_LOW)


## Queue mesh update with priority.
func queue_mesh_update(chunk_id: int, priority: int = PRIORITY_MEDIUM) -> void:
	# Remove from other priority queues
	for p in _update_queue:
		var idx: int = _update_queue[p].find(chunk_id)
		if idx >= 0:
			_update_queue[p].remove_at(idx)

	# Add to requested priority
	if not _update_queue[priority].has(chunk_id):
		_update_queue[priority].append(chunk_id)

	if _chunk_meshes.has(chunk_id):
		_chunk_meshes[chunk_id].needs_rebuild = true


## Process mesh update queue (call every frame).
func process(delta: float) -> void:
	# Update camera position for LOD
	_update_lod_visibility()

	# Process async build completions
	_apply_completed_builds()

	# Process update queue
	var updates_processed := 0

	for priority in [PRIORITY_IMMEDIATE, PRIORITY_HIGH, PRIORITY_MEDIUM, PRIORITY_LOW]:
		while not _update_queue[priority].is_empty() and updates_processed < MAX_UPDATES_PER_FRAME:
			var chunk_id: int = _update_queue[priority].pop_front()
			_rebuild_chunk_mesh(chunk_id)
			updates_processed += 1


## Update camera position for LOD calculations.
func set_camera_position(position: Vector3) -> void:
	_camera_position = position


## Update LOD and visibility for all chunks.
func _update_lod_visibility() -> void:
	for chunk_id in _chunk_meshes:
		var chunk_mesh: ChunkMesh = _chunk_meshes[chunk_id]
		if chunk_mesh.mesh_instance == null:
			continue

		var dist_sq := _camera_position.distance_squared_to(chunk_mesh.world_position)

		# Determine LOD level
		var new_lod := 0
		if dist_sq < LOD_DISTANCE_HIGH:
			new_lod = 0  # High detail
		elif dist_sq < LOD_DISTANCE_MEDIUM:
			new_lod = 1  # Medium
		elif dist_sq < LOD_DISTANCE_LOW:
			new_lod = 2  # Low
		else:
			new_lod = 3  # Cull

		# Update visibility
		var should_visible := new_lod < 3
		if chunk_mesh.is_visible != should_visible:
			chunk_mesh.is_visible = should_visible
			chunk_mesh.mesh_instance.visible = should_visible

		# Queue rebuild if LOD changed significantly
		if chunk_mesh.current_lod != new_lod and absi(chunk_mesh.current_lod - new_lod) > 0:
			chunk_mesh.current_lod = new_lod
			if should_visible and chunk_mesh.needs_rebuild:
				var priority := PRIORITY_LOW if new_lod > 1 else PRIORITY_MEDIUM
				queue_mesh_update(chunk_id, priority)


## Rebuild mesh for chunk.
func _rebuild_chunk_mesh(chunk_id: int) -> void:
	var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
	if chunk == null or not chunk.is_loaded:
		return

	var chunk_mesh: ChunkMesh = _chunk_meshes.get(chunk_id)
	if chunk_mesh == null or chunk_mesh.mesh_instance == null:
		return

	mesh_rebuild_started.emit(chunk_id)

	# Generate mesh based on LOD
	var mesh := _generate_chunk_mesh(chunk, chunk_mesh.current_lod)

	chunk_mesh.mesh_instance.mesh = mesh
	chunk_mesh.last_update_version = chunk.version
	chunk_mesh.needs_rebuild = false

	mesh_rebuild_completed.emit(chunk_id)
	mesh_updated.emit(chunk_id)


## Generate mesh for chunk at given LOD.
func _generate_chunk_mesh(chunk: VoxelChunk, lod: int) -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# LOD determines voxel sampling step
	var step := 1 << lod  # 1, 2, 4, 8
	var voxel_size := float(step)

	for z in range(0, VoxelChunk.CHUNK_SIZE, step):
		for x in range(0, VoxelChunk.CHUNK_SIZE, step):
			var voxel := chunk.get_voxel(x, z)
			if voxel == null:
				continue

			# Skip empty craters at high LOD
			if voxel.stage == VoxelStage.Stage.CRATER and lod < 2:
				continue

			# Generate cube for this voxel
			_add_voxel_cube(surface_tool, x, z, voxel_size, voxel.stage)

	# Apply material
	var primary_stage := _get_dominant_stage(chunk)
	if _materials.has(primary_stage):
		surface_tool.set_material(_materials[primary_stage])

	return surface_tool.commit()


## Add cube geometry for a voxel.
func _add_voxel_cube(st: SurfaceTool, x: int, z: int, size: float, stage: int) -> void:
	var height := _get_stage_height(stage)
	var offset := Vector3(x, 0, z)

	# Set color based on stage
	var color := _get_stage_color(stage)
	st.set_color(color)

	# Top face (always visible)
	st.set_normal(Vector3.UP)
	st.add_vertex(offset + Vector3(0, height, 0))
	st.add_vertex(offset + Vector3(size, height, 0))
	st.add_vertex(offset + Vector3(size, height, size))

	st.add_vertex(offset + Vector3(0, height, 0))
	st.add_vertex(offset + Vector3(size, height, size))
	st.add_vertex(offset + Vector3(0, height, size))

	# Side faces (simplified for performance)
	if height > 0.1:
		# Front face
		st.set_normal(Vector3.FORWARD)
		st.add_vertex(offset + Vector3(0, 0, size))
		st.add_vertex(offset + Vector3(size, 0, size))
		st.add_vertex(offset + Vector3(size, height, size))

		st.add_vertex(offset + Vector3(0, 0, size))
		st.add_vertex(offset + Vector3(size, height, size))
		st.add_vertex(offset + Vector3(0, height, size))

		# Right face
		st.set_normal(Vector3.RIGHT)
		st.add_vertex(offset + Vector3(size, 0, 0))
		st.add_vertex(offset + Vector3(size, 0, size))
		st.add_vertex(offset + Vector3(size, height, size))

		st.add_vertex(offset + Vector3(size, 0, 0))
		st.add_vertex(offset + Vector3(size, height, size))
		st.add_vertex(offset + Vector3(size, height, 0))


## Get height for voxel stage.
func _get_stage_height(stage: int) -> float:
	match stage:
		VoxelStage.Stage.INTACT: return 2.0
		VoxelStage.Stage.CRACKED: return 1.5
		VoxelStage.Stage.RUBBLE: return 0.5
		VoxelStage.Stage.CRATER: return -0.2
		_: return 1.0


## Get color for voxel stage.
func _get_stage_color(stage: int) -> Color:
	match stage:
		VoxelStage.Stage.INTACT: return Color(0.7, 0.7, 0.75)
		VoxelStage.Stage.CRACKED: return Color(0.5, 0.45, 0.4)
		VoxelStage.Stage.RUBBLE: return Color(0.4, 0.35, 0.3)
		VoxelStage.Stage.CRATER: return Color(0.2, 0.18, 0.15)
		_: return Color.WHITE


## Get dominant stage in chunk for material selection.
func _get_dominant_stage(chunk: VoxelChunk) -> int:
	var counts := {
		VoxelStage.Stage.INTACT: 0,
		VoxelStage.Stage.CRACKED: 0,
		VoxelStage.Stage.RUBBLE: 0,
		VoxelStage.Stage.CRATER: 0
	}

	for z in VoxelChunk.CHUNK_SIZE:
		for x in VoxelChunk.CHUNK_SIZE:
			var voxel := chunk.get_voxel(x, z)
			if voxel != null:
				counts[voxel.stage] = counts.get(voxel.stage, 0) + 1

	var max_count := 0
	var dominant := VoxelStage.Stage.INTACT

	for stage in counts:
		if counts[stage] > max_count:
			max_count = counts[stage]
			dominant = stage

	return dominant


## Apply completed async builds.
func _apply_completed_builds() -> void:
	_thread_mutex.lock()
	var completed := _completed_builds.duplicate()
	_completed_builds.clear()
	_thread_mutex.unlock()

	for chunk_id in completed:
		var chunk_mesh: ChunkMesh = _chunk_meshes.get(chunk_id)
		if chunk_mesh != null and chunk_mesh.mesh_instance != null:
			chunk_mesh.mesh_instance.mesh = completed[chunk_id]
			chunk_mesh.needs_rebuild = false
			mesh_updated.emit(chunk_id)


## Handle chunk modification.
func _on_chunk_modified(chunk_id: int) -> void:
	var chunk_mesh: ChunkMesh = _chunk_meshes.get(chunk_id)
	if chunk_mesh == null:
		return

	# Prioritize based on visibility and distance
	var priority := PRIORITY_MEDIUM
	if chunk_mesh.is_visible:
		var dist_sq := _camera_position.distance_squared_to(chunk_mesh.world_position)
		if dist_sq < LOD_DISTANCE_HIGH:
			priority = PRIORITY_HIGH

	queue_mesh_update(chunk_id, priority)


## Handle voxel stage change.
func _on_voxel_stage_changed(position: Vector3i, old_stage: int, new_stage: int) -> void:
	# Stage changes are already handled by chunk_modified
	pass


## Force immediate rebuild of all chunks.
func rebuild_all_meshes() -> void:
	for chunk_id in _chunk_meshes:
		queue_mesh_update(chunk_id, PRIORITY_IMMEDIATE)


## Get mesh instance for chunk.
func get_chunk_mesh_instance(chunk_id: int) -> MeshInstance3D:
	var chunk_mesh: ChunkMesh = _chunk_meshes.get(chunk_id)
	if chunk_mesh != null:
		return chunk_mesh.mesh_instance
	return null


## Clean up all mesh instances.
func cleanup() -> void:
	for chunk_id in _chunk_meshes:
		var chunk_mesh: ChunkMesh = _chunk_meshes[chunk_id]
		if chunk_mesh.mesh_instance != null:
			chunk_mesh.mesh_instance.queue_free()

	_chunk_meshes.clear()
	_update_queue = {
		PRIORITY_IMMEDIATE: [],
		PRIORITY_HIGH: [],
		PRIORITY_MEDIUM: [],
		PRIORITY_LOW: []
	}


## Get statistics.
func get_statistics() -> Dictionary:
	var visible_count := 0
	var pending_count := 0

	for chunk_id in _chunk_meshes:
		var cm: ChunkMesh = _chunk_meshes[chunk_id]
		if cm.is_visible:
			visible_count += 1
		if cm.needs_rebuild:
			pending_count += 1

	var queue_total := 0
	for p in _update_queue:
		queue_total += _update_queue[p].size()

	return {
		"total_chunks": _chunk_meshes.size(),
		"visible_chunks": visible_count,
		"pending_rebuilds": pending_count,
		"queue_size": queue_total,
		"camera_position": _camera_position
	}
