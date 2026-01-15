class_name VoxelChunkStreamer
extends RefCounted
## VoxelChunkStreamer manages dynamic chunk loading/unloading based on camera.
## Provides frustum culling and LOD management for efficient rendering.

signal chunk_stream_in(chunk_id: int)
signal chunk_stream_out(chunk_id: int)
signal lod_changed(chunk_id: int, old_lod: int, new_lod: int)

## Streaming distances (in world units)
const STREAM_DISTANCE := 192.0         ## Load chunks within this distance
const UNLOAD_DISTANCE := 256.0         ## Unload chunks beyond this distance
const HYSTERESIS := 32.0               ## Buffer to prevent thrashing

## LOD levels and their distances
const LOD_LEVELS := 4
const LOD_DISTANCES := [64.0, 128.0, 192.0, 256.0]

## Update intervals
const STREAM_CHECK_INTERVAL := 0.25    ## Check every 250ms
const LOD_CHECK_INTERVAL := 0.1        ## Check every 100ms

## Chunk manager reference
var _chunk_manager: VoxelChunkManager = null

## Mesh manager reference
var _mesh_manager: VoxelMeshManager = null

## Persistence reference
var _persistence: VoxelPersistence = null

## Camera state
var _camera_position: Vector3 = Vector3.ZERO
var _camera_forward: Vector3 = Vector3.FORWARD
var _frustum_planes: Array = []

## Chunk streaming state
var _streamed_chunks: Dictionary = {}  ## chunk_id -> StreamState
var _stream_queue_in: Array[int] = []
var _stream_queue_out: Array[int] = []

## Timing
var _stream_timer: float = 0.0
var _lod_timer: float = 0.0


## Chunk streaming state
class StreamState:
	var chunk_id: int = 0
	var is_loaded: bool = false
	var current_lod: int = 0
	var distance: float = 0.0
	var in_frustum: bool = true
	var last_visible_time: float = 0.0


func _init() -> void:
	pass


## Initialize streamer with references.
func initialize(
	chunk_manager: VoxelChunkManager,
	mesh_manager: VoxelMeshManager,
	persistence: VoxelPersistence = null
) -> void:
	_chunk_manager = chunk_manager
	_mesh_manager = mesh_manager
	_persistence = persistence

	# Initialize streaming state for all chunks
	for i in VoxelChunkManager.TOTAL_CHUNKS:
		var state := StreamState.new()
		state.chunk_id = i
		state.is_loaded = true  # Start with all loaded
		_streamed_chunks[i] = state


## Update camera position and orientation.
func set_camera_transform(position: Vector3, forward: Vector3) -> void:
	_camera_position = position
	_camera_forward = forward.normalized()


## Set frustum planes for culling (from Camera3D.get_frustum()).
func set_frustum_planes(planes: Array) -> void:
	_frustum_planes = planes


## Process streaming (call every frame).
func process(delta: float) -> void:
	_stream_timer += delta
	_lod_timer += delta

	# Check LOD more frequently
	if _lod_timer >= LOD_CHECK_INTERVAL:
		_lod_timer = 0.0
		_update_chunk_lods()

	# Check streaming less frequently
	if _stream_timer >= STREAM_CHECK_INTERVAL:
		_stream_timer = 0.0
		_update_chunk_streaming()

	# Process stream queues
	_process_stream_queues()


## Update chunk LOD levels.
func _update_chunk_lods() -> void:
	for chunk_id in _streamed_chunks:
		var state: StreamState = _streamed_chunks[chunk_id]
		if not state.is_loaded:
			continue

		var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
		if chunk == null:
			continue

		# Calculate distance to camera
		var chunk_center := Vector3(
			chunk.world_offset.x + VoxelChunk.CHUNK_SIZE / 2.0,
			0,
			chunk.world_offset.z + VoxelChunk.CHUNK_SIZE / 2.0
		)
		state.distance = _camera_position.distance_to(chunk_center)

		# Determine LOD level
		var new_lod := LOD_LEVELS - 1
		for i in LOD_LEVELS:
			if state.distance < LOD_DISTANCES[i]:
				new_lod = i
				break

		# Update LOD if changed
		if new_lod != state.current_lod:
			var old_lod := state.current_lod
			state.current_lod = new_lod
			lod_changed.emit(chunk_id, old_lod, new_lod)

			# Queue mesh rebuild at new LOD
			if _mesh_manager != null:
				var priority := VoxelMeshManager.PRIORITY_LOW
				if new_lod < old_lod:
					priority = VoxelMeshManager.PRIORITY_MEDIUM
				_mesh_manager.queue_mesh_update(chunk_id, priority)


## Update chunk streaming (load/unload).
func _update_chunk_streaming() -> void:
	for chunk_id in _streamed_chunks:
		var state: StreamState = _streamed_chunks[chunk_id]

		var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
		if chunk == null:
			continue

		# Calculate distance
		var chunk_center := Vector3(
			chunk.world_offset.x + VoxelChunk.CHUNK_SIZE / 2.0,
			0,
			chunk.world_offset.z + VoxelChunk.CHUNK_SIZE / 2.0
		)
		var distance := _camera_position.distance_to(chunk_center)

		# Check frustum visibility
		var in_frustum := _is_chunk_in_frustum(chunk_center, VoxelChunk.CHUNK_SIZE)
		state.in_frustum = in_frustum

		if in_frustum:
			state.last_visible_time = Time.get_ticks_msec() / 1000.0

		# Determine if should be loaded
		var should_load := distance < STREAM_DISTANCE
		var should_unload := distance > UNLOAD_DISTANCE + HYSTERESIS

		# Also keep visible chunks loaded
		if in_frustum and distance < UNLOAD_DISTANCE:
			should_load = true
			should_unload = false

		# Queue streaming operations
		if should_load and not state.is_loaded:
			if not _stream_queue_in.has(chunk_id):
				_stream_queue_in.append(chunk_id)
		elif should_unload and state.is_loaded:
			if not _stream_queue_out.has(chunk_id):
				_stream_queue_out.append(chunk_id)


## Check if chunk is in camera frustum.
func _is_chunk_in_frustum(center: Vector3, size: float) -> bool:
	if _frustum_planes.is_empty():
		return true  # No frustum data, assume visible

	# Simple sphere check against frustum planes
	var radius := size * 0.707  # Approximate bounding sphere

	for plane in _frustum_planes:
		if plane is Plane:
			var distance: float = plane.distance_to(center)
			if distance < -radius:
				return false

	return true


## Process stream queues.
func _process_stream_queues() -> void:
	# Process one stream-in per frame
	if not _stream_queue_in.is_empty():
		var chunk_id: int = _stream_queue_in.pop_front()
		_stream_in_chunk(chunk_id)

	# Process one stream-out per frame
	if not _stream_queue_out.is_empty():
		var chunk_id: int = _stream_queue_out.pop_front()
		_stream_out_chunk(chunk_id)


## Stream in a chunk.
func _stream_in_chunk(chunk_id: int) -> void:
	var state: StreamState = _streamed_chunks.get(chunk_id)
	if state == null or state.is_loaded:
		return

	var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
	if chunk == null:
		return

	# Reload chunk data
	if _persistence != null:
		_persistence.ensure_chunk_loaded(chunk_id)
	else:
		chunk.reload()

	state.is_loaded = true

	# Queue mesh generation
	if _mesh_manager != null:
		_mesh_manager.queue_mesh_update(chunk_id, VoxelMeshManager.PRIORITY_HIGH)

	chunk_stream_in.emit(chunk_id)


## Stream out a chunk.
func _stream_out_chunk(chunk_id: int) -> void:
	var state: StreamState = _streamed_chunks.get(chunk_id)
	if state == null or not state.is_loaded:
		return

	var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
	if chunk == null:
		return

	# Don't unload dirty chunks
	if chunk.is_dirty:
		return

	# Unload chunk data
	chunk.unload()
	state.is_loaded = false

	# Hide mesh
	if _mesh_manager != null:
		var mesh := _mesh_manager.get_chunk_mesh_instance(chunk_id)
		if mesh != null:
			mesh.visible = false

	chunk_stream_out.emit(chunk_id)


## Force load chunks in radius.
func preload_radius(center: Vector3, radius: float) -> int:
	var loaded_count := 0

	for chunk_id in _streamed_chunks:
		var state: StreamState = _streamed_chunks[chunk_id]
		if state.is_loaded:
			continue

		var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
		if chunk == null:
			continue

		var chunk_center := Vector3(
			chunk.world_offset.x + VoxelChunk.CHUNK_SIZE / 2.0,
			0,
			chunk.world_offset.z + VoxelChunk.CHUNK_SIZE / 2.0
		)

		if center.distance_to(chunk_center) < radius:
			_stream_in_chunk(chunk_id)
			loaded_count += 1

	return loaded_count


## Get chunk at world position.
func get_chunk_at_position(position: Vector3) -> int:
	var chunk_x := int(position.x) / VoxelChunk.CHUNK_SIZE
	var chunk_z := int(position.z) / VoxelChunk.CHUNK_SIZE

	if chunk_x < 0 or chunk_x >= VoxelChunkManager.GRID_SIZE:
		return -1
	if chunk_z < 0 or chunk_z >= VoxelChunkManager.GRID_SIZE:
		return -1

	return chunk_z * VoxelChunkManager.GRID_SIZE + chunk_x


## Ensure chunk at position is loaded.
func ensure_loaded_at_position(position: Vector3) -> void:
	var chunk_id := get_chunk_at_position(position)
	if chunk_id >= 0:
		var state: StreamState = _streamed_chunks.get(chunk_id)
		if state != null and not state.is_loaded:
			_stream_in_chunk(chunk_id)


## Get loaded chunk count.
func get_loaded_count() -> int:
	var count := 0
	for chunk_id in _streamed_chunks:
		var state: StreamState = _streamed_chunks[chunk_id]
		if state.is_loaded:
			count += 1
	return count


## Get visible chunk count.
func get_visible_count() -> int:
	var count := 0
	for chunk_id in _streamed_chunks:
		var state: StreamState = _streamed_chunks[chunk_id]
		if state.is_loaded and state.in_frustum:
			count += 1
	return count


## Get chunks by LOD level.
func get_chunks_by_lod() -> Dictionary:
	var result := {}
	for i in LOD_LEVELS:
		result[i] = 0

	for chunk_id in _streamed_chunks:
		var state: StreamState = _streamed_chunks[chunk_id]
		if state.is_loaded:
			result[state.current_lod] = result.get(state.current_lod, 0) + 1

	return result


## Get streaming statistics.
func get_statistics() -> Dictionary:
	return {
		"total_chunks": _streamed_chunks.size(),
		"loaded_chunks": get_loaded_count(),
		"visible_chunks": get_visible_count(),
		"stream_queue_in": _stream_queue_in.size(),
		"stream_queue_out": _stream_queue_out.size(),
		"chunks_by_lod": get_chunks_by_lod(),
		"camera_position": _camera_position
	}
