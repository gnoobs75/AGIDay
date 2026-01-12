class_name FogOfWarGrid
extends RefCounted
## FogOfWarGrid manages the complete fog of war system for one faction.
## Uses 16x16 chunks covering a 512x512 voxel map.

signal visibility_changed(voxel_x: int, voxel_z: int, new_state: int)
signal chunk_revealed(chunk_x: int, chunk_z: int)
signal chunk_hidden(chunk_x: int, chunk_z: int)

## Grid configuration
const GRID_SIZE := 16  ## Chunks per side
const MAP_SIZE := 512  ## Total voxels per side
const CHUNK_SIZE := FogChunk.CHUNK_SIZE  ## 32 voxels per chunk

## Faction identifier
var faction_id: String = ""

## Chunk storage (chunk_key -> FogChunk)
var _chunks: Dictionary = {}

## Performance tracking
var _last_update_time_ms := 0.0
var _dirty_chunks: Array[String] = []


func _init(p_faction_id: String = "") -> void:
	faction_id = p_faction_id
	_initialize_chunks()


## Initialize all chunks.
func _initialize_chunks() -> void:
	for cx in GRID_SIZE:
		for cz in GRID_SIZE:
			var key := _get_chunk_key(cx, cz)
			_chunks[key] = FogChunk.new(cx, cz)


## Get chunk key from chunk coordinates.
func _get_chunk_key(chunk_x: int, chunk_z: int) -> String:
	return str(chunk_x) + "_" + str(chunk_z)


## Get chunk coordinates from voxel coordinates.
func _voxel_to_chunk(voxel_x: int, voxel_z: int) -> Vector2i:
	return Vector2i(voxel_x / CHUNK_SIZE, voxel_z / CHUNK_SIZE)


## Get local coordinates within chunk.
func _voxel_to_local(voxel_x: int, voxel_z: int) -> Vector2i:
	return Vector2i(voxel_x % CHUNK_SIZE, voxel_z % CHUNK_SIZE)


## Get chunk at voxel coordinates.
func _get_chunk_at_voxel(voxel_x: int, voxel_z: int) -> FogChunk:
	var chunk_coords := _voxel_to_chunk(voxel_x, voxel_z)
	var key := _get_chunk_key(chunk_coords.x, chunk_coords.y)
	return _chunks.get(key)


## Get visibility at voxel coordinates.
func get_visibility(voxel_x: int, voxel_z: int) -> int:
	if voxel_x < 0 or voxel_x >= MAP_SIZE or voxel_z < 0 or voxel_z >= MAP_SIZE:
		return VisibilityState.State.UNEXPLORED

	var chunk := _get_chunk_at_voxel(voxel_x, voxel_z)
	if chunk == null:
		return VisibilityState.State.UNEXPLORED

	var local := _voxel_to_local(voxel_x, voxel_z)
	return chunk.get_visibility(local.x, local.y)


## Set visibility at voxel coordinates.
func set_visibility(voxel_x: int, voxel_z: int, state: int, current_time: float = 0.0) -> bool:
	if voxel_x < 0 or voxel_x >= MAP_SIZE or voxel_z < 0 or voxel_z >= MAP_SIZE:
		return false

	var chunk := _get_chunk_at_voxel(voxel_x, voxel_z)
	if chunk == null:
		return false

	var local := _voxel_to_local(voxel_x, voxel_z)
	var changed := chunk.set_visibility(local.x, local.y, state, current_time)

	if changed:
		visibility_changed.emit(voxel_x, voxel_z, state)

		var chunk_key := _get_chunk_key(chunk.chunk_x, chunk.chunk_z)
		if chunk_key not in _dirty_chunks:
			_dirty_chunks.append(chunk_key)

	return changed


## Reveal area around position (set to VISIBLE).
func reveal_area(center_x: int, center_z: int, radius: int, current_time: float = 0.0) -> int:
	var revealed := 0
	var radius_sq := radius * radius

	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius_sq:
				continue

			var vx := center_x + dx
			var vz := center_z + dz

			if set_visibility(vx, vz, VisibilityState.State.VISIBLE, current_time):
				revealed += 1

	return revealed


## Hide area (set VISIBLE to EXPLORED).
func hide_area(center_x: int, center_z: int, radius: int) -> int:
	var hidden := 0
	var radius_sq := radius * radius

	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius_sq:
				continue

			var vx := center_x + dx
			var vz := center_z + dz

			var current := get_visibility(vx, vz)
			if current == VisibilityState.State.VISIBLE:
				if set_visibility(vx, vz, VisibilityState.State.EXPLORED):
					hidden += 1

	return hidden


## Check if position is visible.
func is_visible(voxel_x: int, voxel_z: int) -> bool:
	return get_visibility(voxel_x, voxel_z) == VisibilityState.State.VISIBLE


## Check if position has been explored.
func is_explored(voxel_x: int, voxel_z: int) -> bool:
	return get_visibility(voxel_x, voxel_z) >= VisibilityState.State.EXPLORED


## Get last visible time at position.
func get_last_visible_time(voxel_x: int, voxel_z: int) -> float:
	var chunk := _get_chunk_at_voxel(voxel_x, voxel_z)
	if chunk == null:
		return 0.0

	var local := _voxel_to_local(voxel_x, voxel_z)
	return chunk.get_last_visible_time(local.x, local.y)


## Clear all visible cells to explored (end of turn/update).
func clear_all_visible() -> void:
	for key in _chunks:
		var chunk: FogChunk = _chunks[key]
		if chunk.has_visible_cells():
			chunk.set_chunk_explored()
			chunk_hidden.emit(chunk.chunk_x, chunk.chunk_z)

			if key not in _dirty_chunks:
				_dirty_chunks.append(key)


## Get all dirty chunks for synchronization.
func get_dirty_chunks() -> Array[FogChunk]:
	var result: Array[FogChunk] = []

	for key in _dirty_chunks:
		if _chunks.has(key):
			result.append(_chunks[key])

	return result


## Clear dirty flags.
func clear_dirty_flags() -> void:
	for key in _dirty_chunks:
		if _chunks.has(key):
			_chunks[key].clear_dirty()
	_dirty_chunks.clear()


## Get chunk at chunk coordinates.
func get_chunk(chunk_x: int, chunk_z: int) -> FogChunk:
	var key := _get_chunk_key(chunk_x, chunk_z)
	return _chunks.get(key)


## Serialization.
func to_dict() -> Dictionary:
	var chunks_data: Dictionary = {}

	for key in _chunks:
		var chunk: FogChunk = _chunks[key]
		chunks_data[key] = chunk.to_dict()

	return {
		"faction_id": faction_id,
		"chunks": chunks_data
	}


func from_dict(data: Dictionary) -> void:
	faction_id = data.get("faction_id", "")

	var chunks_data: Dictionary = data.get("chunks", {})
	for key in chunks_data:
		if _chunks.has(key):
			_chunks[key].from_dict(chunks_data[key])

	_dirty_chunks.clear()


## Get memory usage estimate in bytes.
func get_memory_usage() -> int:
	# Each chunk: 1024 bytes visibility + 4096 bytes times = ~5KB
	return _chunks.size() * 5120


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_visible := 0
	var total_explored := 0
	var total_unexplored := 0

	for key in _chunks:
		var summary: Dictionary = _chunks[key].get_summary()
		total_visible += summary["visible"]
		total_explored += summary["explored"]
		total_unexplored += summary["unexplored"]

	return {
		"faction_id": faction_id,
		"total_chunks": _chunks.size(),
		"dirty_chunks": _dirty_chunks.size(),
		"visibility": {
			"unexplored": total_unexplored,
			"explored": total_explored,
			"visible": total_visible
		},
		"memory_kb": get_memory_usage() / 1024
	}
