class_name VoxelPersistence
extends RefCounted
## VoxelPersistence manages snapshot and delta storage for voxel chunks.
## Provides efficient save/load with compression and memory management.

signal snapshot_saved(snapshot_id: int)
signal snapshot_loaded(snapshot_id: int)
signal delta_saved(delta_id: int, chunk_count: int)
signal chunk_loaded(chunk_id: int)
signal chunk_unloaded(chunk_id: int)

## File format magic numbers
const SNAPSHOT_MAGIC := 0x56534E50  ## "VSNP"
const DELTA_MAGIC := 0x56444C54    ## "VDLT"
const FORMAT_VERSION := 1

## Memory management thresholds
const MAX_LOADED_CHUNKS := 48      ## Keep at most this many chunks loaded
const CHUNK_UNLOAD_DISTANCE := 256 ## Unload chunks farther than this from camera

## Reference to chunk manager
var _chunk_manager: VoxelChunkManager = null

## Snapshot tracking
var _last_snapshot_id: int = 0
var _last_snapshot_frame: int = 0

## Delta tracking
var _deltas: Array[PackedByteArray] = []
var _delta_frames: Array[int] = []

## Loaded chunk LRU tracking (chunk_id -> last_access_frame)
var _chunk_access: Dictionary = {}


func _init(chunk_manager: VoxelChunkManager = null) -> void:
	_chunk_manager = chunk_manager


## Set chunk manager reference.
func set_chunk_manager(manager: VoxelChunkManager) -> void:
	_chunk_manager = manager


## Create full snapshot of all chunks.
func create_snapshot() -> PackedByteArray:
	if _chunk_manager == null:
		return PackedByteArray()

	var snapshot := PackedByteArray()

	# Header: magic(4) + version(4) + snapshot_id(4) + frame(4) + chunk_count(4) = 20 bytes
	var header := PackedByteArray()
	header.resize(20)

	_last_snapshot_id += 1
	_last_snapshot_frame = Engine.get_process_frames()

	header.encode_u32(0, SNAPSHOT_MAGIC)
	header.encode_u32(4, FORMAT_VERSION)
	header.encode_s32(8, _last_snapshot_id)
	header.encode_s32(12, _last_snapshot_frame)
	header.encode_s32(16, VoxelChunkManager.TOTAL_CHUNKS)

	snapshot.append_array(header)

	# Only save dirty/changed chunks, mark others with placeholder
	for i in VoxelChunkManager.TOTAL_CHUNKS:
		var chunk := _chunk_manager.get_chunk_by_id(i)
		if chunk == null:
			continue

		var chunk_data := chunk.to_binary()

		# Write chunk size then data
		var size_bytes := PackedByteArray()
		size_bytes.resize(4)
		size_bytes.encode_u32(0, chunk_data.size())

		snapshot.append_array(size_bytes)
		snapshot.append_array(chunk_data)

		# Clear dirty after snapshot
		chunk.clear_dirty()

	# Clear delta history after full snapshot
	_deltas.clear()
	_delta_frames.clear()

	# Compress
	var compressed := snapshot.compress(FileAccess.COMPRESSION_ZSTD)

	snapshot_saved.emit(_last_snapshot_id)
	return compressed


## Load snapshot from compressed data.
func load_snapshot(compressed_data: PackedByteArray) -> bool:
	if _chunk_manager == null:
		return false

	var data := compressed_data.decompress_dynamic(-1, FileAccess.COMPRESSION_ZSTD)
	if data.size() < 20:
		return false

	# Validate header
	var magic := data.decode_u32(0)
	if magic != SNAPSHOT_MAGIC:
		return false

	var version := data.decode_u32(4)
	if version != FORMAT_VERSION:
		return false

	_last_snapshot_id = data.decode_s32(8)
	_last_snapshot_frame = data.decode_s32(12)
	var chunk_count := data.decode_s32(16)

	# Read chunks
	var offset := 20
	for i in chunk_count:
		if offset + 4 > data.size():
			return false

		var chunk_size := data.decode_u32(offset)
		offset += 4

		if offset + chunk_size > data.size():
			return false

		var chunk := _chunk_manager.get_chunk_by_id(i)
		if chunk != null:
			var chunk_data := data.slice(offset, offset + chunk_size)
			chunk.from_binary(chunk_data)

		offset += chunk_size

	# Clear deltas
	_deltas.clear()
	_delta_frames.clear()

	snapshot_loaded.emit(_last_snapshot_id)
	return true


## Create delta of changed chunks since last snapshot/delta.
func create_delta() -> PackedByteArray:
	if _chunk_manager == null:
		return PackedByteArray()

	var dirty_chunks := _chunk_manager.get_dirty_chunks()
	if dirty_chunks.is_empty():
		return PackedByteArray()

	var delta := PackedByteArray()

	# Header: magic(4) + version(4) + base_snapshot(4) + frame(4) + chunk_count(4) = 20 bytes
	var header := PackedByteArray()
	header.resize(20)

	var current_frame := Engine.get_process_frames()

	header.encode_u32(0, DELTA_MAGIC)
	header.encode_u32(4, FORMAT_VERSION)
	header.encode_s32(8, _last_snapshot_id)
	header.encode_s32(12, current_frame)
	header.encode_s32(16, dirty_chunks.size())

	delta.append_array(header)

	# Write each dirty chunk's delta
	for chunk in dirty_chunks:
		var chunk_delta := chunk.get_delta()
		if chunk_delta.is_empty():
			continue

		var size_bytes := PackedByteArray()
		size_bytes.resize(4)
		size_bytes.encode_u32(0, chunk_delta.size())

		delta.append_array(size_bytes)
		delta.append_array(chunk_delta)

		chunk.clear_dirty()

	# Store delta for reconstruction
	var compressed := delta.compress(FileAccess.COMPRESSION_ZSTD)
	_deltas.append(compressed)
	_delta_frames.append(current_frame)

	delta_saved.emit(_deltas.size(), dirty_chunks.size())
	return compressed


## Apply delta to current state.
func apply_delta(compressed_data: PackedByteArray) -> bool:
	if _chunk_manager == null:
		return false

	var data := compressed_data.decompress_dynamic(-1, FileAccess.COMPRESSION_ZSTD)
	if data.size() < 20:
		return false

	# Validate header
	var magic := data.decode_u32(0)
	if magic != DELTA_MAGIC:
		return false

	var base_snapshot := data.decode_s32(8)
	if base_snapshot != _last_snapshot_id:
		return false  # Delta doesn't match current snapshot

	var chunk_count := data.decode_s32(16)

	# Apply each chunk delta
	var offset := 20
	for i in chunk_count:
		if offset + 4 > data.size():
			return false

		var delta_size := data.decode_u32(offset)
		offset += 4

		if offset + delta_size > data.size():
			return false

		var chunk_data := data.slice(offset, offset + delta_size)

		# Extract chunk_id from delta data
		if chunk_data.size() >= 4:
			var chunk_id := chunk_data.decode_s32(0)
			var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
			if chunk != null:
				chunk.apply_delta(chunk_data)

		offset += delta_size

	return true


## Reconstruct full state from snapshot + deltas.
func reconstruct_from_deltas(snapshot_data: PackedByteArray, delta_list: Array[PackedByteArray]) -> bool:
	# Load base snapshot
	if not load_snapshot(snapshot_data):
		return false

	# Apply deltas in order
	for delta in delta_list:
		if not apply_delta(delta):
			return false

	return true


## Save to file.
func save_to_file(path: String) -> bool:
	var snapshot := create_snapshot()
	if snapshot.is_empty():
		return false

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_buffer(snapshot)
	file.close()
	return true


## Load from file.
func load_from_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var data := file.get_buffer(file.get_length())
	file.close()

	return load_snapshot(data)


## Memory management: unload distant chunks.
func manage_memory(camera_position: Vector3) -> int:
	if _chunk_manager == null:
		return 0

	var current_frame := Engine.get_process_frames()
	var unloaded_count := 0
	var loaded_chunks: Array[VoxelChunk] = []

	# Find loaded chunks and their distances
	for i in VoxelChunkManager.TOTAL_CHUNKS:
		var chunk := _chunk_manager.get_chunk_by_id(i)
		if chunk != null and chunk.is_loaded:
			loaded_chunks.append(chunk)

	# Check if we need to unload
	if loaded_chunks.size() <= MAX_LOADED_CHUNKS:
		return 0

	# Calculate distances and sort by distance (farthest first)
	var chunk_distances: Array = []
	for chunk in loaded_chunks:
		var chunk_center := Vector3(
			chunk.world_offset.x + VoxelChunk.CHUNK_SIZE / 2.0,
			0,
			chunk.world_offset.z + VoxelChunk.CHUNK_SIZE / 2.0
		)
		var dist := camera_position.distance_squared_to(chunk_center)
		var last_access: int = _chunk_access.get(chunk.chunk_id, 0)
		chunk_distances.append({
			"chunk": chunk,
			"distance": dist,
			"last_access": last_access
		})

	# Sort by distance (farthest first), then by last access (oldest first)
	chunk_distances.sort_custom(func(a, b):
		if a["distance"] != b["distance"]:
			return a["distance"] > b["distance"]
		return a["last_access"] < b["last_access"]
	)

	# Unload chunks exceeding limit
	var to_unload := loaded_chunks.size() - MAX_LOADED_CHUNKS
	for i in to_unload:
		var chunk_info: Dictionary = chunk_distances[i]
		var chunk: VoxelChunk = chunk_info["chunk"]

		# Don't unload dirty chunks
		if chunk.is_dirty:
			continue

		# Check distance threshold
		if chunk_info["distance"] < CHUNK_UNLOAD_DISTANCE * CHUNK_UNLOAD_DISTANCE:
			continue

		chunk.unload()
		_chunk_access.erase(chunk.chunk_id)
		chunk_unloaded.emit(chunk.chunk_id)
		unloaded_count += 1

	return unloaded_count


## Track chunk access for LRU.
func record_chunk_access(chunk_id: int) -> void:
	_chunk_access[chunk_id] = Engine.get_process_frames()


## Ensure chunk is loaded.
func ensure_chunk_loaded(chunk_id: int) -> VoxelChunk:
	if _chunk_manager == null:
		return null

	var chunk := _chunk_manager.get_chunk_by_id(chunk_id)
	if chunk == null:
		return null

	if not chunk.is_loaded:
		chunk.reload()
		chunk_loaded.emit(chunk_id)

	record_chunk_access(chunk_id)
	return chunk


## Get total memory usage across all chunks.
func get_total_memory_usage() -> int:
	if _chunk_manager == null:
		return 0

	var total := 0
	for i in VoxelChunkManager.TOTAL_CHUNKS:
		var chunk := _chunk_manager.get_chunk_by_id(i)
		if chunk != null:
			total += chunk.get_memory_usage()

	return total


## Get persistence statistics.
func get_statistics() -> Dictionary:
	var loaded_count := 0
	var dirty_count := 0

	if _chunk_manager != null:
		for i in VoxelChunkManager.TOTAL_CHUNKS:
			var chunk := _chunk_manager.get_chunk_by_id(i)
			if chunk != null:
				if chunk.is_loaded:
					loaded_count += 1
				if chunk.is_dirty:
					dirty_count += 1

	return {
		"last_snapshot_id": _last_snapshot_id,
		"last_snapshot_frame": _last_snapshot_frame,
		"delta_count": _deltas.size(),
		"loaded_chunks": loaded_count,
		"dirty_chunks": dirty_count,
		"total_memory": get_total_memory_usage(),
		"max_loaded_chunks": MAX_LOADED_CHUNKS
	}
