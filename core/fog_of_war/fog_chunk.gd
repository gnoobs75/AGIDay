class_name FogChunk
extends RefCounted
## FogChunk represents a 32x32 voxel chunk of fog of war data.

## Chunk dimensions
const CHUNK_SIZE := 32  ## Voxels per side
const CHUNK_AREA := CHUNK_SIZE * CHUNK_SIZE  ## 1024 cells

## Chunk coordinates
var chunk_x: int = 0
var chunk_z: int = 0

## Visibility data (flattened array for cache efficiency)
## Each entry is a VisibilityState.State value
var _visibility: PackedByteArray

## Last visible time for each cell (for gameplay features)
var _last_visible_times: PackedFloat32Array

## Dirty flag for optimization
var _is_dirty: bool = false

## Currently visible cell count (for quick queries)
var _visible_count: int = 0


func _init(cx: int = 0, cz: int = 0) -> void:
	chunk_x = cx
	chunk_z = cz
	_visibility = PackedByteArray()
	_visibility.resize(CHUNK_AREA)
	_last_visible_times = PackedFloat32Array()
	_last_visible_times.resize(CHUNK_AREA)

	# Initialize all cells to unexplored
	for i in CHUNK_AREA:
		_visibility[i] = VisibilityState.State.UNEXPLORED
		_last_visible_times[i] = 0.0


## Get cell index from local coordinates.
func _get_index(local_x: int, local_z: int) -> int:
	return local_z * CHUNK_SIZE + local_x


## Get visibility state for local coordinates.
func get_visibility(local_x: int, local_z: int) -> int:
	if local_x < 0 or local_x >= CHUNK_SIZE or local_z < 0 or local_z >= CHUNK_SIZE:
		return VisibilityState.State.UNEXPLORED
	return _visibility[_get_index(local_x, local_z)]


## Set visibility state for local coordinates.
func set_visibility(local_x: int, local_z: int, state: int, current_time: float = 0.0) -> bool:
	if local_x < 0 or local_x >= CHUNK_SIZE or local_z < 0 or local_z >= CHUNK_SIZE:
		return false

	var idx := _get_index(local_x, local_z)
	var old_state: int = _visibility[idx]

	if not VisibilityState.is_valid_transition(old_state, state):
		return false

	if old_state == state:
		# Update last visible time even if state unchanged
		if state == VisibilityState.State.VISIBLE:
			_last_visible_times[idx] = current_time
		return false

	# Update visible count
	if old_state == VisibilityState.State.VISIBLE:
		_visible_count -= 1
	if state == VisibilityState.State.VISIBLE:
		_visible_count += 1

	_visibility[idx] = state

	if state == VisibilityState.State.VISIBLE:
		_last_visible_times[idx] = current_time

	_is_dirty = true
	return true


## Get last visible time for local coordinates.
func get_last_visible_time(local_x: int, local_z: int) -> float:
	if local_x < 0 or local_x >= CHUNK_SIZE or local_z < 0 or local_z >= CHUNK_SIZE:
		return 0.0
	return _last_visible_times[_get_index(local_x, local_z)]


## Set entire chunk to explored (when unit leaves area).
func set_chunk_explored() -> void:
	for i in CHUNK_AREA:
		if _visibility[i] == VisibilityState.State.VISIBLE:
			_visibility[i] = VisibilityState.State.EXPLORED

	_visible_count = 0
	_is_dirty = true


## Check if any cell in chunk is visible.
func has_visible_cells() -> bool:
	return _visible_count > 0


## Get visible cell count.
func get_visible_count() -> int:
	return _visible_count


## Check if chunk is dirty (needs sync).
func is_dirty() -> bool:
	return _is_dirty


## Clear dirty flag.
func clear_dirty() -> void:
	_is_dirty = false


## Get world coordinates for chunk origin.
func get_world_origin() -> Vector2i:
	return Vector2i(chunk_x * CHUNK_SIZE, chunk_z * CHUNK_SIZE)


## Check if world voxel coordinates are in this chunk.
func contains_voxel(voxel_x: int, voxel_z: int) -> bool:
	var origin := get_world_origin()
	return (voxel_x >= origin.x and voxel_x < origin.x + CHUNK_SIZE and
			voxel_z >= origin.y and voxel_z < origin.y + CHUNK_SIZE)


## Convert world voxel coordinates to local.
func world_to_local(voxel_x: int, voxel_z: int) -> Vector2i:
	var origin := get_world_origin()
	return Vector2i(voxel_x - origin.x, voxel_z - origin.y)


## Serialization.
func to_dict() -> Dictionary:
	return {
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"visibility": _visibility.duplicate(),
		"last_visible_times": Array(_last_visible_times),
		"visible_count": _visible_count
	}


func from_dict(data: Dictionary) -> void:
	chunk_x = data.get("chunk_x", 0)
	chunk_z = data.get("chunk_z", 0)

	var vis_data = data.get("visibility", [])
	if vis_data is PackedByteArray:
		_visibility = vis_data.duplicate()
	else:
		_visibility = PackedByteArray(vis_data)

	var times_data: Array = data.get("last_visible_times", [])
	_last_visible_times = PackedFloat32Array(times_data)

	_visible_count = data.get("visible_count", 0)
	_is_dirty = false


## Get summary for debugging.
func get_summary() -> Dictionary:
	var explored_count := 0
	var unexplored_count := 0

	for i in CHUNK_AREA:
		match _visibility[i]:
			VisibilityState.State.UNEXPLORED:
				unexplored_count += 1
			VisibilityState.State.EXPLORED:
				explored_count += 1

	return {
		"chunk_coords": Vector2i(chunk_x, chunk_z),
		"unexplored": unexplored_count,
		"explored": explored_count,
		"visible": _visible_count,
		"is_dirty": _is_dirty
	}
