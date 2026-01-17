class_name VoxelChunk
extends RefCounted
## VoxelChunk manages a 64x64 grid of voxels with version tracking.
## Provides efficient local coordinate access and dirty flag tracking.

signal chunk_modified(chunk_id: int)
signal voxel_stage_changed(local_pos: Vector3i, old_stage: int, new_stage: int)

## Chunk dimensions
const CHUNK_SIZE := 64
const CHUNK_AREA := CHUNK_SIZE * CHUNK_SIZE  ## 4096 voxels per chunk

## Unique chunk identifier
var chunk_id: int = 0

## Chunk position in chunk grid (0-7, 0-7)
var chunk_position: Vector2i = Vector2i.ZERO

## World offset for converting local to world coordinates
var world_offset: Vector3i = Vector3i.ZERO

## Version for tracking changes (incremented on each modification)
var version: int = 0

## Dirty flag for persistence and rendering updates
var is_dirty: bool = false

## Voxel storage (flat array, accessed via local coordinates)
var _voxels: Array[VoxelStateData] = []

## Quick lookup for damaged voxels
var _damaged_voxels: Dictionary = {}  ## local_key -> true

## Quick lookup for power nodes
var _power_nodes: Dictionary = {}  ## local_key -> true

## Destruction count for statistics
var destruction_count: int = 0

## Last modified frame number for delta tracking
var last_modified_frame: int = 0

## Total resource drops from this chunk
var resource_drops: float = 0.0

## Changed voxel indices for delta compression
var _changed_indices: Dictionary = {}  ## index -> true

## Whether chunk is loaded in memory (for streaming)
var is_loaded: bool = true


## Get string ID in CHUNK_X_Y format.
static func make_chunk_id_string(pos: Vector2i) -> String:
	return "CHUNK_%d_%d" % [pos.x, pos.y]


func _init(id: int = 0, pos: Vector2i = Vector2i.ZERO) -> void:
	chunk_id = id
	chunk_position = pos
	world_offset = Vector3i(pos.x * CHUNK_SIZE, 0, pos.y * CHUNK_SIZE)
	_initialize_storage()


## Initialize voxel storage.
func _initialize_storage() -> void:
	_voxels.resize(CHUNK_AREA)
	for i in CHUNK_AREA:
		var local_x := i % CHUNK_SIZE
		var local_z := i / CHUNK_SIZE
		var world_pos := Vector3i(
			world_offset.x + local_x,
			0,
			world_offset.z + local_z
		)
		_voxels[i] = VoxelStateData.new(world_pos, 100)


## Get voxel at local coordinates.
func get_voxel(local_x: int, local_z: int) -> VoxelStateData:
	if not is_loaded or _voxels.is_empty():
		return null
	if not _is_valid_local(local_x, local_z):
		return null
	var idx := _get_index(local_x, local_z)
	if idx < 0 or idx >= _voxels.size():
		return null
	return _voxels[idx]


## Get voxel at local position vector.
func get_voxel_v(local_pos: Vector2i) -> VoxelStateData:
	return get_voxel(local_pos.x, local_pos.y)


## Set voxel at local coordinates.
func set_voxel(local_x: int, local_z: int, voxel: VoxelStateData) -> void:
	if not _is_valid_local(local_x, local_z):
		return
	var idx := _get_index(local_x, local_z)
	_voxels[idx] = voxel
	_mark_dirty(idx)


## Apply damage to voxel at local coordinates.ww
func damage_voxel(local_x: int, local_z: int, damage: int, current_time: float = 0.0) -> int:
	var voxel := get_voxel(local_x, local_z)
	if voxel == null:
		return -1

	var old_stage := voxel.stage
	var new_stage := voxel.apply_damage(damage, current_time)

	if new_stage >= 0:
		var idx := _get_index(local_x, local_z)
		_handle_stage_change(local_x, local_z, voxel, old_stage, new_stage)
		_mark_dirty(idx)

	return new_stage


## Repair voxel at local coordinates.
func repair_voxel(local_x: int, local_z: int, heal: int, current_time: float = 0.0) -> int:
	var voxel := get_voxel(local_x, local_z)
	if voxel == null:
		return -1

	var old_stage := voxel.stage
	var new_stage := voxel.apply_repair(heal, current_time)

	if new_stage >= 0:
		var idx := _get_index(local_x, local_z)
		_handle_stage_change(local_x, local_z, voxel, old_stage, new_stage)
		_mark_dirty(idx)

	return new_stage


## Handle voxel stage change.
func _handle_stage_change(local_x: int, local_z: int, voxel: VoxelStateData, old_stage: int, new_stage: int) -> void:
	var key := _get_local_key(local_x, local_z)
	var local_pos := Vector3i(local_x, 0, local_z)

	# Track damaged voxels
	if new_stage > VoxelStage.Stage.INTACT:
		_damaged_voxels[key] = true
	elif _damaged_voxels.has(key):
		_damaged_voxels.erase(key)

	# Track destruction and resource drops
	if new_stage == VoxelStage.Stage.RUBBLE and old_stage != VoxelStage.Stage.RUBBLE:
		# Resources drop when transitioning to rubble
		resource_drops += _calculate_resource_drop(voxel.voxel_type)

	if new_stage == VoxelStage.Stage.CRATER and old_stage != VoxelStage.Stage.CRATER:
		destruction_count += 1

	voxel_stage_changed.emit(local_pos, old_stage, new_stage)


## Calculate resource drop for voxel type.
func _calculate_resource_drop(voxel_type: String) -> float:
	match voxel_type:
		"industrial": return 75.0
		"power_node", "power_hub": return 100.0
		"ree_node", "resource": return 150.0
		_: return 50.0


## Convert local to world position.
func local_to_world(local_x: int, local_z: int) -> Vector3i:
	return Vector3i(
		world_offset.x + local_x,
		0,
		world_offset.z + local_z
	)


## Convert world to local position (returns null if outside chunk).
func world_to_local(world_pos: Vector3i) -> Vector2i:
	var local_x := world_pos.x - world_offset.x
	var local_z := world_pos.z - world_offset.z

	if _is_valid_local(local_x, local_z):
		return Vector2i(local_x, local_z)
	return Vector2i(-1, -1)  # Invalid


## Check if world position is in this chunk.
func contains_world_position(world_pos: Vector3i) -> bool:
	var local_x := world_pos.x - world_offset.x
	var local_z := world_pos.z - world_offset.z
	return _is_valid_local(local_x, local_z)


## Get all damaged voxels in chunk.
func get_damaged_voxels() -> Array[VoxelStateData]:
	var result: Array[VoxelStateData] = []
	for key in _damaged_voxels:
		var idx := int(key)
		if idx >= 0 and idx < _voxels.size():
			result.append(_voxels[idx])
	return result


## Get all power nodes in chunk.
func get_power_nodes() -> Array[VoxelStateData]:
	var result: Array[VoxelStateData] = []
	for key in _power_nodes:
		var idx := int(key)
		if idx >= 0 and idx < _voxels.size():
			result.append(_voxels[idx])
	return result


## Register a power node.
func register_power_node(local_x: int, local_z: int) -> void:
	var voxel := get_voxel(local_x, local_z)
	if voxel != null:
		voxel.set_flag(VoxelStateData.FLAG_POWER_NODE, true)
		_power_nodes[_get_index(local_x, local_z)] = true
		_mark_dirty()


## Mark chunk as dirty with voxel index.
func _mark_dirty(voxel_index: int = -1) -> void:
	is_dirty = true
	version += 1
	last_modified_frame = Engine.get_process_frames()
	if voxel_index >= 0:
		_changed_indices[voxel_index] = true
	chunk_modified.emit(chunk_id)


## Clear dirty flag and changed indices.
func clear_dirty() -> void:
	is_dirty = false
	_changed_indices.clear()


## Get array index from local coordinates.
func _get_index(local_x: int, local_z: int) -> int:
	return local_z * CHUNK_SIZE + local_x


## Get local key string from coordinates.
func _get_local_key(local_x: int, local_z: int) -> int:
	return _get_index(local_x, local_z)


## Validate local coordinates.
func _is_valid_local(local_x: int, local_z: int) -> bool:
	return local_x >= 0 and local_x < CHUNK_SIZE and local_z >= 0 and local_z < CHUNK_SIZE


## Serialize chunk to binary format (3 bytes per voxel).
## Header: chunk_id(4) + version(4) + destruction_count(4) + last_modified_frame(4) + resource_drops(4) = 20 bytes
func to_binary() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(20 + CHUNK_AREA * 3)

	# Write header
	data.encode_s32(0, chunk_id)
	data.encode_s32(4, version)
	data.encode_s32(8, destruction_count)
	data.encode_s32(12, last_modified_frame)
	data.encode_float(16, resource_drops)

	# Write voxel data (3 bytes each)
	var offset := 20
	for voxel in _voxels:
		data[offset] = voxel.stage
		data[offset + 1] = voxel.current_hp
		data[offset + 2] = voxel.type_flags & 0xFF
		offset += 3

	return data


## Deserialize chunk from binary format.
func from_binary(data: PackedByteArray) -> bool:
	if data.size() < 20 + CHUNK_AREA * 3:
		return false

	# Read header
	chunk_id = data.decode_s32(0)
	version = data.decode_s32(4)
	destruction_count = data.decode_s32(8)
	last_modified_frame = data.decode_s32(12)
	resource_drops = data.decode_float(16)

	# Read voxel data
	var offset := 20
	for i in CHUNK_AREA:
		var voxel := _voxels[i]
		voxel.stage = data[offset]
		voxel.current_hp = data[offset + 1]
		voxel.type_flags = data[offset + 2]
		offset += 3

		# Rebuild lookup tables
		if voxel.stage > VoxelStage.Stage.INTACT:
			_damaged_voxels[i] = true
		if voxel.is_power_node():
			_power_nodes[i] = true

	is_dirty = false
	_changed_indices.clear()
	return true


## Get delta (changed voxels only) since last clear.
## Format: chunk_id(4) + count(4) + [index(2) + stage(1) + hp(1) + flags(1)] per changed voxel
func get_delta() -> PackedByteArray:
	if not is_dirty or _changed_indices.is_empty():
		return PackedByteArray()

	var count := _changed_indices.size()
	var data := PackedByteArray()
	# Header: chunk_id (4) + count (4) = 8 bytes
	# Per voxel: index (2) + stage (1) + hp (1) + flags (1) = 5 bytes
	data.resize(8 + count * 5)

	data.encode_s32(0, chunk_id)
	data.encode_s32(4, count)

	var offset := 8
	for idx in _changed_indices:
		var voxel := _voxels[idx]
		data.encode_u16(offset, idx)
		data[offset + 2] = voxel.stage
		data[offset + 3] = voxel.current_hp
		data[offset + 4] = voxel.type_flags & 0xFF
		offset += 5

	return data


## Apply delta update from packed data.
func apply_delta(data: PackedByteArray) -> bool:
	if data.size() < 8:
		return false

	var data_chunk_id := data.decode_s32(0)
	if data_chunk_id != chunk_id:
		return false

	var count := data.decode_s32(4)
	if data.size() < 8 + count * 5:
		return false

	var offset := 8
	for i in count:
		var idx := data.decode_u16(offset)
		if idx < CHUNK_AREA:
			var voxel := _voxels[idx]
			voxel.stage = data[offset + 2]
			voxel.current_hp = data[offset + 3]
			voxel.type_flags = data[offset + 4]

			# Rebuild lookups
			if voxel.stage > VoxelStage.Stage.INTACT:
				_damaged_voxels[idx] = true
			elif _damaged_voxels.has(idx):
				_damaged_voxels.erase(idx)
			if voxel.is_power_node():
				_power_nodes[idx] = true
		offset += 5

	return true


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var voxel_data: Array = []
	for voxel in _voxels:
		voxel_data.append(voxel.to_dict())

	return {
		"chunk_id": chunk_id,
		"chunk_id_string": VoxelChunk.make_chunk_id_string(chunk_position),
		"chunk_position": [chunk_position.x, chunk_position.y],
		"version": version,
		"destruction_count": destruction_count,
		"last_modified_frame": last_modified_frame,
		"resource_drops": resource_drops,
		"voxels": voxel_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	chunk_id = data.get("chunk_id", 0)
	var pos_arr: Array = data.get("chunk_position", [0, 0])
	chunk_position = Vector2i(pos_arr[0], pos_arr[1])
	world_offset = Vector3i(chunk_position.x * CHUNK_SIZE, 0, chunk_position.y * CHUNK_SIZE)
	version = data.get("version", 0)
	destruction_count = data.get("destruction_count", 0)
	last_modified_frame = data.get("last_modified_frame", 0)
	resource_drops = data.get("resource_drops", 0.0)

	var voxel_data: Array = data.get("voxels", [])
	_damaged_voxels.clear()
	_power_nodes.clear()
	_changed_indices.clear()

	for i in mini(voxel_data.size(), CHUNK_AREA):
		_voxels[i].from_dict(voxel_data[i])
		if _voxels[i].stage > VoxelStage.Stage.INTACT:
			_damaged_voxels[i] = true
		if _voxels[i].is_power_node():
			_power_nodes[i] = true


## Unload chunk data to free memory. Keeps metadata.
func unload() -> void:
	_voxels.clear()
	_damaged_voxels.clear()
	_power_nodes.clear()
	_changed_indices.clear()
	is_loaded = false


## Reload chunk data (reinitialize storage).
func reload() -> void:
	if not is_loaded:
		_initialize_storage()
		is_loaded = true


## Get memory usage estimate in bytes.
func get_memory_usage() -> int:
	if not is_loaded:
		return 64  # Just metadata
	# ~40 bytes per VoxelState + overhead
	return CHUNK_AREA * 48 + 256


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"chunk_id": chunk_id,
		"chunk_id_string": VoxelChunk.make_chunk_id_string(chunk_position),
		"chunk_position": chunk_position,
		"version": version,
		"is_dirty": is_dirty,
		"is_loaded": is_loaded,
		"total_voxels": CHUNK_AREA,
		"damaged_count": _damaged_voxels.size(),
		"power_node_count": _power_nodes.size(),
		"destruction_count": destruction_count,
		"last_modified_frame": last_modified_frame,
		"resource_drops": resource_drops,
		"changed_voxels": _changed_indices.size(),
		"memory_usage": get_memory_usage()
	}
