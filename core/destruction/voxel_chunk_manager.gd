class_name VoxelChunkManager
extends RefCounted
## VoxelChunkManager coordinates 8x8 grid of chunks covering 512x512 voxels.
## Provides unified access to voxel data across all chunks with async updates.

signal voxel_damaged(position: Vector3i, damage: float, new_health: float)
signal voxel_stage_changed(position: Vector3i, old_stage: int, new_stage: int)
signal voxel_destroyed(position: Vector3i)
signal chunk_modified(chunk_id: int)
signal batch_complete(processed_count: int)

## Grid dimensions
const GRID_SIZE := 8                            ## 8x8 chunks
const TOTAL_CHUNKS := GRID_SIZE * GRID_SIZE     ## 64 chunks total
const WORLD_SIZE := 512                         ## 512x512 world
const TOTAL_VOXELS := WORLD_SIZE * WORLD_SIZE   ## 262,144 voxels

## Async processing limits
const MAX_UPDATES_PER_FRAME := 100

## Chunk storage
var _chunks: Array[VoxelChunk] = []

## Update queue for async processing
var _update_queue: Array[Dictionary] = []

## Metadata tracking
var _total_destruction_count: int = 0
var _special_nodes: Dictionary = {}  ## "type" -> Array[Vector3i]

## Processing statistics
var _updates_this_frame: int = 0


func _init() -> void:
	_initialize_chunks()


## Initialize all chunks in 8x8 grid.
func _initialize_chunks() -> void:
	_chunks.resize(TOTAL_CHUNKS)

	for z in GRID_SIZE:
		for x in GRID_SIZE:
			var idx := z * GRID_SIZE + x
			var chunk := VoxelChunk.new(idx, Vector2i(x, z))
			chunk.chunk_modified.connect(_on_chunk_modified)
			chunk.voxel_stage_changed.connect(_on_voxel_stage_changed.bind(chunk))
			_chunks[idx] = chunk


## Get voxel at world position.
func get_voxel(world_pos: Vector3i) -> VoxelStateData:
	var chunk := _get_chunk_for_world_pos(world_pos)
	if chunk == null:
		return null

	var local := _world_to_local(world_pos)
	return chunk.get_voxel(local.x, local.y)


## Set voxel at world position.
func set_voxel(world_pos: Vector3i, voxel: VoxelStateData) -> void:
	var chunk := _get_chunk_for_world_pos(world_pos)
	if chunk == null:
		return

	var local := _world_to_local(world_pos)
	chunk.set_voxel(local.x, local.y, voxel)


## Queue damage for async processing.
func queue_damage(world_pos: Vector3i, damage: int, source: String = "") -> void:
	_update_queue.append({
		"type": "damage",
		"position": world_pos,
		"damage": damage,
		"source": source,
		"time": Time.get_ticks_msec() / 1000.0
	})


## Queue repair for async processing.
func queue_repair(world_pos: Vector3i, heal: int) -> void:
	_update_queue.append({
		"type": "repair",
		"position": world_pos,
		"heal": heal,
		"time": Time.get_ticks_msec() / 1000.0
	})


## Apply damage immediately (bypasses queue).
func damage_voxel_immediate(world_pos: Vector3i, damage: int, current_time: float = 0.0) -> int:
	var chunk := _get_chunk_for_world_pos(world_pos)
	if chunk == null:
		return -1

	var local := _world_to_local(world_pos)
	var voxel_data: VoxelStateData = chunk.get_voxel(local.x, local.y)
	var old_hp: int = voxel_data.current_hp if voxel_data != null else 0
	var result := chunk.damage_voxel(local.x, local.y, damage, current_time)

	if result >= 0:
		var voxel: VoxelStateData = chunk.get_voxel(local.x, local.y)
		voxel_damaged.emit(world_pos, float(damage), float(voxel.current_hp))

	return result


## Apply repair immediately (bypasses queue).
func repair_voxel_immediate(world_pos: Vector3i, heal: int, current_time: float = 0.0) -> int:
	var chunk := _get_chunk_for_world_pos(world_pos)
	if chunk == null:
		return -1

	var local := _world_to_local(world_pos)
	return chunk.repair_voxel(local.x, local.y, heal, current_time)


## Process update queue (call every frame).
func process(delta: float) -> void:
	_updates_this_frame = 0
	var current_time := Time.get_ticks_msec() / 1000.0

	while not _update_queue.is_empty() and _updates_this_frame < MAX_UPDATES_PER_FRAME:
		var update: Dictionary = _update_queue.pop_front()
		_process_update(update, current_time)
		_updates_this_frame += 1

	if _updates_this_frame > 0:
		batch_complete.emit(_updates_this_frame)


## Process single update.
func _process_update(update: Dictionary, current_time: float) -> void:
	var pos: Vector3i = update["position"]

	match update["type"]:
		"damage":
			damage_voxel_immediate(pos, update["damage"], current_time)
		"repair":
			repair_voxel_immediate(pos, update["heal"], current_time)


## Get chunk for world position.
func _get_chunk_for_world_pos(world_pos: Vector3i) -> VoxelChunk:
	var chunk_x := world_pos.x / VoxelChunk.CHUNK_SIZE
	var chunk_z := world_pos.z / VoxelChunk.CHUNK_SIZE

	if chunk_x < 0 or chunk_x >= GRID_SIZE or chunk_z < 0 or chunk_z >= GRID_SIZE:
		return null

	return _chunks[chunk_z * GRID_SIZE + chunk_x]


## Get chunk by grid position.
func get_chunk(chunk_x: int, chunk_z: int) -> VoxelChunk:
	if chunk_x < 0 or chunk_x >= GRID_SIZE or chunk_z < 0 or chunk_z >= GRID_SIZE:
		return null

	return _chunks[chunk_z * GRID_SIZE + chunk_x]


## Get chunk by ID.
func get_chunk_by_id(chunk_id: int) -> VoxelChunk:
	if chunk_id < 0 or chunk_id >= TOTAL_CHUNKS:
		return null
	return _chunks[chunk_id]


## Convert world to local chunk coordinates.
func _world_to_local(world_pos: Vector3i) -> Vector2i:
	# Use posmod to handle negative coordinates correctly
	return Vector2i(
		posmod(world_pos.x, VoxelChunk.CHUNK_SIZE),
		posmod(world_pos.z, VoxelChunk.CHUNK_SIZE)
	)


## Get all damaged voxels across all chunks.
func get_all_damaged_voxels() -> Array[VoxelStateData]:
	var result: Array[VoxelStateData] = []
	for chunk in _chunks:
		result.append_array(chunk.get_damaged_voxels())
	return result


## Get all damaged voxels in radius.
func get_damaged_voxels_in_radius(center: Vector3i, radius: int) -> Array[VoxelStateData]:
	var result: Array[VoxelStateData] = []
	var radius_sq := radius * radius

	# Determine which chunks to check
	var min_chunk_x := maxi(0, (center.x - radius) / VoxelChunk.CHUNK_SIZE)
	var max_chunk_x := mini(GRID_SIZE - 1, (center.x + radius) / VoxelChunk.CHUNK_SIZE)
	var min_chunk_z := maxi(0, (center.z - radius) / VoxelChunk.CHUNK_SIZE)
	var max_chunk_z := mini(GRID_SIZE - 1, (center.z + radius) / VoxelChunk.CHUNK_SIZE)

	for cz in range(min_chunk_z, max_chunk_z + 1):
		for cx in range(min_chunk_x, max_chunk_x + 1):
			var chunk := _chunks[cz * GRID_SIZE + cx]
			for voxel in chunk.get_damaged_voxels():
				var dx := voxel.position.x - center.x
				var dz := voxel.position.z - center.z
				if dx * dx + dz * dz <= radius_sq:
					result.append(voxel)

	return result


## Get all power nodes across all chunks.
func get_all_power_nodes() -> Array[VoxelStateData]:
	var result: Array[VoxelStateData] = []
	for chunk in _chunks:
		result.append_array(chunk.get_power_nodes())
	return result


## Register special node location.
func register_special_node(world_pos: Vector3i, node_type: String) -> void:
	if not _special_nodes.has(node_type):
		_special_nodes[node_type] = []
	_special_nodes[node_type].append(world_pos)

	# Also update voxel flags
	var voxel := get_voxel(world_pos)
	if voxel != null:
		match node_type:
			"power_node":
				voxel.set_flag(VoxelStateData.FLAG_POWER_NODE, true)
			"power_hub":
				voxel.set_flag(VoxelStateData.FLAG_POWER_HUB, true)
			"resource":
				voxel.set_flag(VoxelStateData.FLAG_RESOURCE, true)
			"strategic":
				voxel.set_flag(VoxelStateData.FLAG_STRATEGIC, true)


## Get special nodes of type.
func get_special_nodes(node_type: String) -> Array:
	return _special_nodes.get(node_type, [])


## Check if position is valid.
func is_valid_position(world_pos: Vector3i) -> bool:
	return world_pos.x >= 0 and world_pos.x < WORLD_SIZE and \
		   world_pos.z >= 0 and world_pos.z < WORLD_SIZE


## Get dirty chunks for persistence.
func get_dirty_chunks() -> Array[VoxelChunk]:
	var dirty: Array[VoxelChunk] = []
	for chunk in _chunks:
		if chunk.is_dirty:
			dirty.append(chunk)
	return dirty


## Clear all dirty flags.
func clear_all_dirty() -> void:
	for chunk in _chunks:
		chunk.clear_dirty()


## Chunk modification handler.
func _on_chunk_modified(chunk_id: int) -> void:
	chunk_modified.emit(chunk_id)


## Voxel stage change handler.
func _on_voxel_stage_changed(local_pos: Vector3i, old_stage: int, new_stage: int, chunk: VoxelChunk) -> void:
	var world_pos := chunk.local_to_world(local_pos.x, local_pos.z)
	voxel_stage_changed.emit(world_pos, old_stage, new_stage)

	if new_stage == VoxelStage.Stage.CRATER:
		_total_destruction_count += 1
		voxel_destroyed.emit(world_pos)


## Serialize all chunks to binary.
func to_binary() -> PackedByteArray:
	var result := PackedByteArray()

	# Header: magic (4), version (4), total_chunks (4), destruction_count (4) = 16 bytes
	var header := PackedByteArray()
	header.resize(16)
	header.encode_u32(0, 0x564F5843)  # "VOXC"
	header.encode_u32(4, 1)            # Version 1
	header.encode_u32(8, TOTAL_CHUNKS)
	header.encode_s32(12, _total_destruction_count)
	result.append_array(header)

	# Serialize each chunk
	for chunk in _chunks:
		var chunk_data := chunk.to_binary()
		# Write chunk size then data
		var size_data := PackedByteArray()
		size_data.resize(4)
		size_data.encode_u32(0, chunk_data.size())
		result.append_array(size_data)
		result.append_array(chunk_data)

	return result


## Deserialize all chunks from binary.
func from_binary(data: PackedByteArray) -> bool:
	if data.size() < 16:
		return false

	# Validate header
	var magic := data.decode_u32(0)
	if magic != 0x564F5843:  # "VOXC"
		return false

	var version := data.decode_u32(4)
	if version != 1:
		return false

	var chunk_count := data.decode_u32(8)
	if chunk_count != TOTAL_CHUNKS:
		return false

	_total_destruction_count = data.decode_s32(12)

	# Read each chunk
	var offset := 16
	for i in TOTAL_CHUNKS:
		if offset + 4 > data.size():
			return false

		var chunk_size := data.decode_u32(offset)
		offset += 4

		if offset + chunk_size > data.size():
			return false

		var chunk_data := data.slice(offset, offset + chunk_size)
		if not _chunks[i].from_binary(chunk_data):
			return false

		offset += chunk_size

	return true


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var chunks_data: Array = []
	for chunk in _chunks:
		chunks_data.append(chunk.to_dict())

	return {
		"version": 1,
		"total_destruction_count": _total_destruction_count,
		"special_nodes": _special_nodes.duplicate(true),
		"chunks": chunks_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_total_destruction_count = data.get("total_destruction_count", 0)
	_special_nodes = data.get("special_nodes", {}).duplicate(true)

	var chunks_data: Array = data.get("chunks", [])
	for i in mini(chunks_data.size(), TOTAL_CHUNKS):
		_chunks[i].from_dict(chunks_data[i])


## Get total destruction count.
func get_total_destruction_count() -> int:
	return _total_destruction_count


## Get queue size.
func get_queue_size() -> int:
	return _update_queue.size()


## Clear all data and reinitialize.
func reset() -> void:
	_update_queue.clear()
	_total_destruction_count = 0
	_special_nodes.clear()
	_initialize_chunks()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var damaged_count := 0
	var power_count := 0
	var dirty_count := 0

	for chunk in _chunks:
		var summary := chunk.get_summary()
		damaged_count += summary["damaged_count"]
		power_count += summary["power_node_count"]
		if chunk.is_dirty:
			dirty_count += 1

	return {
		"grid_size": GRID_SIZE,
		"total_chunks": TOTAL_CHUNKS,
		"total_voxels": TOTAL_VOXELS,
		"total_destruction": _total_destruction_count,
		"damaged_voxels": damaged_count,
		"power_nodes": power_count,
		"dirty_chunks": dirty_count,
		"queue_size": _update_queue.size(),
		"special_node_types": _special_nodes.keys()
	}
