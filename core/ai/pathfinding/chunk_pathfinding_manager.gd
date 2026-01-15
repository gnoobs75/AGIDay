class_name ChunkPathfindingManager
extends RefCounted
## ChunkPathfindingManager handles asynchronous pathfinding updates at chunk granularity.
## Batches updates to minimize performance impact.

signal chunk_update_started(chunk_pos: Vector2i)
signal chunk_update_completed(chunk_pos: Vector2i, time_ms: float)
signal batch_update_completed(chunks_updated: int, total_time_ms: float)
signal pathfinding_ready()

## Configuration
const CHUNK_SIZE := 32
const MAX_CHUNKS_PER_UPDATE := 4
const UPDATE_INTERVAL := 0.1  ## Seconds between batch updates
const MAX_PATHFINDING_TIME_MS := 16.0  ## Stay under frame budget

## Chunk state
enum ChunkState {
	CLEAN,
	DIRTY,
	UPDATING,
	ERROR
}

## Chunk data
var _chunks: Dictionary = {}          ## Vector2i -> ChunkData
var _dirty_queue: Array[Vector2i] = []
var _update_queue: Array[Vector2i] = []

## Threading
var _update_thread: Thread = null
var _thread_mutex: Mutex = null
var _is_updating := false
var _pending_results: Array = []

## Timing
var _update_timer := 0.0
var _total_update_time := 0.0
var _update_count := 0

## Voxel pathfinding reference
var _voxel_pathfinding: VoxelPathfinding = null


func _init() -> void:
	_thread_mutex = Mutex.new()


## Initialize with voxel pathfinding.
func initialize(voxel_pathfinding: VoxelPathfinding) -> void:
	_voxel_pathfinding = voxel_pathfinding

	# Connect to pathfinding events
	_voxel_pathfinding.chunk_dirty.connect(_on_chunk_dirty)


## Register chunk for tracking.
func register_chunk(chunk_pos: Vector2i) -> void:
	if not _chunks.has(chunk_pos):
		var chunk := ChunkData.new()
		chunk.position = chunk_pos
		chunk.state = ChunkState.CLEAN
		_chunks[chunk_pos] = chunk


## Handle chunk marked dirty.
func _on_chunk_dirty(chunk_pos: Vector2i) -> void:
	if not _chunks.has(chunk_pos):
		register_chunk(chunk_pos)

	var chunk: ChunkData = _chunks[chunk_pos]

	if chunk.state != ChunkState.DIRTY and chunk.state != ChunkState.UPDATING:
		chunk.state = ChunkState.DIRTY
		if chunk_pos not in _dirty_queue:
			_dirty_queue.append(chunk_pos)


## Update manager (call each frame).
func update(delta: float) -> void:
	_update_timer += delta

	# Process pending thread results
	_process_pending_results()

	# Batch update dirty chunks periodically
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_process_dirty_chunks()


## Process dirty chunks synchronously.
func _process_dirty_chunks() -> void:
	if _dirty_queue.is_empty():
		return

	var start_time := Time.get_ticks_msec()
	var chunks_updated := 0

	while not _dirty_queue.is_empty() and chunks_updated < MAX_CHUNKS_PER_UPDATE:
		var elapsed := Time.get_ticks_msec() - start_time
		if elapsed > MAX_PATHFINDING_TIME_MS:
			break

		var chunk_pos: Vector2i = _dirty_queue.pop_front()
		_update_chunk_sync(chunk_pos)
		chunks_updated += 1

	var total_time := float(Time.get_ticks_msec() - start_time)
	_total_update_time += total_time
	_update_count += chunks_updated

	if chunks_updated > 0:
		batch_update_completed.emit(chunks_updated, total_time)


## Update chunk synchronously.
func _update_chunk_sync(chunk_pos: Vector2i) -> void:
	if not _chunks.has(chunk_pos):
		return

	var chunk: ChunkData = _chunks[chunk_pos]
	chunk.state = ChunkState.UPDATING

	chunk_update_started.emit(chunk_pos)

	var update_start := Time.get_ticks_usec()

	# Calculate new pathfinding costs for chunk
	var min_voxel := chunk_pos * CHUNK_SIZE
	var max_voxel := min_voxel + Vector2i(CHUNK_SIZE - 1, CHUNK_SIZE - 1)

	# Update cost grid for each unit size
	for size in VoxelPathfinding.UnitSize.values():
		chunk.cost_grids[size] = _voxel_pathfinding.get_cost_grid(min_voxel, max_voxel, size)

	chunk.last_update_time = Time.get_ticks_msec()
	chunk.state = ChunkState.CLEAN

	var update_time := (Time.get_ticks_usec() - update_start) / 1000.0
	chunk_update_completed.emit(chunk_pos, update_time)


## Queue chunk for async update.
func queue_chunk_update(chunk_pos: Vector2i) -> void:
	if chunk_pos not in _update_queue:
		_update_queue.append(chunk_pos)


## Start async batch update.
func start_async_update() -> void:
	if _is_updating or _update_queue.is_empty():
		return

	_thread_mutex.lock()
	_is_updating = true
	_thread_mutex.unlock()

	_update_thread = Thread.new()
	var chunks_to_update := _update_queue.duplicate()
	_update_queue.clear()

	var callable := Callable(self, "_async_update_chunks").bind(chunks_to_update)
	_update_thread.start(callable)


## Async chunk update thread function.
func _async_update_chunks(chunks: Array) -> void:
	var results := []

	for chunk_pos in chunks:
		if not _chunks.has(chunk_pos):
			continue

		var chunk: ChunkData = _chunks[chunk_pos]

		var min_voxel: Vector2i = chunk_pos * CHUNK_SIZE
		var max_voxel: Vector2i = min_voxel + Vector2i(CHUNK_SIZE - 1, CHUNK_SIZE - 1)

		var cost_grids := {}
		for size in VoxelPathfinding.UnitSize.values():
			cost_grids[size] = _voxel_pathfinding.get_cost_grid(min_voxel, max_voxel, size)

		results.append({
			"chunk_pos": chunk_pos,
			"cost_grids": cost_grids,
			"time": Time.get_ticks_msec()
		})

	_thread_mutex.lock()
	_pending_results.append_array(results)
	_is_updating = false
	_thread_mutex.unlock()


## Process results from async updates.
func _process_pending_results() -> void:
	_thread_mutex.lock()
	var results := _pending_results.duplicate()
	_pending_results.clear()
	_thread_mutex.unlock()

	if _update_thread != null and not _is_updating:
		if _update_thread.is_started():
			_update_thread.wait_to_finish()
		_update_thread = null

	for result in results:
		var chunk_pos: Vector2i = result["chunk_pos"]
		if _chunks.has(chunk_pos):
			var chunk: ChunkData = _chunks[chunk_pos]
			chunk.cost_grids = result["cost_grids"]
			chunk.last_update_time = result["time"]
			chunk.state = ChunkState.CLEAN

			chunk_update_completed.emit(chunk_pos, 0.0)


## Get chunk cost grid.
func get_chunk_cost_grid(chunk_pos: Vector2i, unit_size: int) -> Array:
	if not _chunks.has(chunk_pos):
		return []

	var chunk: ChunkData = _chunks[chunk_pos]
	return chunk.cost_grids.get(unit_size, [])


## Get traversal cost at world position.
func get_cost_at(world_x: int, world_z: int, unit_size: int) -> float:
	var chunk_pos := Vector2i(world_x / CHUNK_SIZE, world_z / CHUNK_SIZE)

	if not _chunks.has(chunk_pos):
		return INF

	var chunk: ChunkData = _chunks[chunk_pos]
	var grid: Array = chunk.cost_grids.get(unit_size, [])

	if grid.is_empty():
		return INF

	var local_x := world_x % CHUNK_SIZE
	var local_z := world_z % CHUNK_SIZE

	if local_x >= grid.size():
		return INF
	if local_z >= grid[local_x].size():
		return INF

	return grid[local_x][local_z]


## Get chunk state.
func get_chunk_state(chunk_pos: Vector2i) -> ChunkState:
	if _chunks.has(chunk_pos):
		return _chunks[chunk_pos].state
	return ChunkState.CLEAN


## Force update all dirty chunks.
func force_update_all() -> void:
	while not _dirty_queue.is_empty():
		var chunk_pos: Vector2i = _dirty_queue.pop_front()
		_update_chunk_sync(chunk_pos)


## Check if all chunks are clean.
func is_pathfinding_ready() -> bool:
	return _dirty_queue.is_empty() and not _is_updating


## Get dirty chunk count.
func get_dirty_count() -> int:
	return _dirty_queue.size()


## Get total chunk count.
func get_chunk_count() -> int:
	return _chunks.size()


## Get statistics.
func get_statistics() -> Dictionary:
	var dirty_count := 0
	var clean_count := 0
	var updating_count := 0

	for chunk_pos in _chunks:
		match _chunks[chunk_pos].state:
			ChunkState.DIRTY:
				dirty_count += 1
			ChunkState.CLEAN:
				clean_count += 1
			ChunkState.UPDATING:
				updating_count += 1

	var avg_time := 0.0
	if _update_count > 0:
		avg_time = _total_update_time / float(_update_count)

	return {
		"total_chunks": _chunks.size(),
		"dirty_chunks": dirty_count,
		"clean_chunks": clean_count,
		"updating_chunks": updating_count,
		"queue_size": _dirty_queue.size(),
		"is_updating": _is_updating,
		"total_updates": _update_count,
		"average_update_time_ms": avg_time
	}


## Cleanup.
func cleanup() -> void:
	if _update_thread != null:
		if _update_thread.is_started():
			_update_thread.wait_to_finish()
		_update_thread = null

	_chunks.clear()
	_dirty_queue.clear()
	_update_queue.clear()


## ChunkData class.
class ChunkData:
	var position: Vector2i = Vector2i.ZERO
	var state: ChunkState = ChunkState.CLEAN
	var cost_grids: Dictionary = {}  ## UnitSize -> Array[Array[float]]
	var last_update_time: int = 0
