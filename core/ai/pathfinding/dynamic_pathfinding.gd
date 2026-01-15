class_name DynamicPathfinding
extends RefCounted
## DynamicPathfinding manages navigation mesh updates for evolving terrain.
## Handles path calculation, obstacle avoidance, and mesh rebuilding.

signal navmesh_updated(region_id: int, time_ms: float)
signal navmesh_rebuild_started()
signal navmesh_rebuild_completed(total_time_ms: float)
signal path_calculated(unit_id: int, path_length: int)
signal path_blocked(unit_id: int, blocked_position: Vector3)

## Configuration
const MAX_UPDATE_TIME_MS := 100.0     ## Target <100ms updates
const PARTIAL_UPDATE_RADIUS := 50.0   ## Radius for partial updates
const PATH_CACHE_TIME_MS := 500       ## Cache path results
const GRID_CELL_SIZE := 2.0           ## 2D grid cell size

## Terrain cost multipliers
const COST_SMOOTH := 1.0
const COST_RUBBLE := 1.5
const COST_CRATER := 2.0
const COST_BLOCKED := INF

## Navigation regions
var _regions: Dictionary = {}         ## region_id -> NavigationRegionData
var _next_region_id := 0

## Path cache
var _path_cache: Dictionary = {}      ## cache_key -> {path, timestamp}

## 2D cost grid (backup pathfinding)
var _cost_grid: Array = []
var _grid_size := Vector2i(512, 512)

## Pending updates
var _dirty_regions: Array[int] = []
var _pending_terrain_changes: Array = []

## Thread safety
var _update_mutex: Mutex = null
var _is_rebuilding := false


func _init() -> void:
	_update_mutex = Mutex.new()


## Initialize pathfinding system.
func initialize(world_size: Vector2i = Vector2i(512, 512)) -> void:
	_grid_size = world_size
	_initialize_cost_grid()


## Initialize 2D cost grid.
func _initialize_cost_grid() -> void:
	_cost_grid = []
	for x in _grid_size.x:
		var row := []
		for z in _grid_size.y:
			row.append(COST_SMOOTH)
		_cost_grid.append(row)


## Register navigation region.
func register_region(bounds: AABB) -> int:
	var region := NavigationRegionData.new()
	region.id = _next_region_id
	region.bounds = bounds
	region.is_dirty = true

	_regions[_next_region_id] = region
	_dirty_regions.append(_next_region_id)

	_next_region_id += 1
	return region.id


## Notify terrain change at position.
func on_terrain_changed(position: Vector3, old_state: int, new_state: int) -> void:
	_pending_terrain_changes.append({
		"position": position,
		"old_state": old_state,
		"new_state": new_state
	})

	# Update cost grid
	var grid_x := int(position.x / GRID_CELL_SIZE)
	var grid_z := int(position.z / GRID_CELL_SIZE)

	if grid_x >= 0 and grid_x < _grid_size.x and grid_z >= 0 and grid_z < _grid_size.y:
		_cost_grid[grid_x][grid_z] = _state_to_cost(new_state)

	# Mark affected regions dirty
	_mark_affected_regions_dirty(position)

	# Invalidate cached paths near position
	_invalidate_cache_near(position)


## Convert voxel state to movement cost.
func _state_to_cost(state: int) -> float:
	match state:
		0:  # INTACT
			return COST_BLOCKED
		1:  # CRACKED
			return COST_BLOCKED
		2:  # RUBBLE
			return COST_RUBBLE
		3:  # CRATER
			return COST_CRATER
	return COST_SMOOTH


## Mark regions affected by position change.
func _mark_affected_regions_dirty(position: Vector3) -> void:
	for region_id in _regions:
		var region: NavigationRegionData = _regions[region_id]

		if region.bounds.has_point(position):
			if not region.is_dirty:
				region.is_dirty = true
				if region_id not in _dirty_regions:
					_dirty_regions.append(region_id)


## Update navigation (call each frame).
func update(delta: float) -> void:
	# Process pending terrain changes
	_process_terrain_changes()

	# Update dirty regions
	_update_dirty_regions()


## Process pending terrain changes.
func _process_terrain_changes() -> void:
	if _pending_terrain_changes.is_empty():
		return

	_update_mutex.lock()
	var changes := _pending_terrain_changes.duplicate()
	_pending_terrain_changes.clear()
	_update_mutex.unlock()

	# Batch process changes
	for change in changes:
		# Changes already applied in on_terrain_changed
		pass


## Update dirty navigation regions.
func _update_dirty_regions() -> void:
	if _dirty_regions.is_empty() or _is_rebuilding:
		return

	var start_time := Time.get_ticks_msec()
	var regions_updated := 0

	while not _dirty_regions.is_empty():
		var elapsed := Time.get_ticks_msec() - start_time
		if elapsed > MAX_UPDATE_TIME_MS:
			break

		var region_id: int = _dirty_regions.pop_front()
		if _regions.has(region_id):
			_update_region(region_id)
			regions_updated += 1


## Update single navigation region.
func _update_region(region_id: int) -> void:
	if not _regions.has(region_id):
		return

	var region: NavigationRegionData = _regions[region_id]
	var update_start := Time.get_ticks_msec()

	# Recalculate region navmesh (placeholder - actual implementation
	# would use Godot's NavigationServer3D)
	region.navmesh_data = _generate_region_navmesh(region)
	region.is_dirty = false
	region.last_update_time = Time.get_ticks_msec()

	var update_time := float(Time.get_ticks_msec() - update_start)
	navmesh_updated.emit(region_id, update_time)


## Generate navmesh for region.
func _generate_region_navmesh(region: NavigationRegionData) -> Dictionary:
	# Generate walkable area data based on cost grid
	var walkable_cells := []

	var min_x := int(region.bounds.position.x / GRID_CELL_SIZE)
	var max_x := int((region.bounds.position.x + region.bounds.size.x) / GRID_CELL_SIZE)
	var min_z := int(region.bounds.position.z / GRID_CELL_SIZE)
	var max_z := int((region.bounds.position.z + region.bounds.size.z) / GRID_CELL_SIZE)

	for x in range(maxi(0, min_x), mini(_grid_size.x, max_x)):
		for z in range(maxi(0, min_z), mini(_grid_size.y, max_z)):
			if _cost_grid[x][z] < COST_BLOCKED:
				walkable_cells.append(Vector2i(x, z))

	return {
		"walkable_cells": walkable_cells,
		"bounds": region.bounds
	}


## Calculate path between points.
func calculate_path(start: Vector3, end: Vector3, unit_size: int = 0) -> Array[Vector3]:
	# Check cache first
	var cache_key := _make_cache_key(start, end, unit_size)
	var cached := _get_cached_path(cache_key)
	if not cached.is_empty():
		return cached

	# Calculate using 2D grid (A* algorithm)
	var path := _calculate_grid_path(start, end, unit_size)

	# Cache result
	_cache_path(cache_key, path)

	return path


## Calculate path using 2D grid.
func _calculate_grid_path(start: Vector3, end: Vector3, unit_size: int) -> Array[Vector3]:
	var start_cell := Vector2i(int(start.x / GRID_CELL_SIZE), int(start.z / GRID_CELL_SIZE))
	var end_cell := Vector2i(int(end.x / GRID_CELL_SIZE), int(end.z / GRID_CELL_SIZE))

	# Clamp to grid bounds
	start_cell = start_cell.clamp(Vector2i.ZERO, _grid_size - Vector2i.ONE)
	end_cell = end_cell.clamp(Vector2i.ZERO, _grid_size - Vector2i.ONE)

	# A* pathfinding
	var path_cells := _astar_pathfind(start_cell, end_cell, unit_size)

	# Convert to world coordinates
	var path: Array[Vector3] = []
	for cell in path_cells:
		var world_pos := Vector3(
			cell.x * GRID_CELL_SIZE + GRID_CELL_SIZE / 2,
			0,
			cell.y * GRID_CELL_SIZE + GRID_CELL_SIZE / 2
		)
		path.append(world_pos)

	# Smooth path
	if path.size() > 2:
		path = _smooth_path(path)

	return path


## A* pathfinding on 2D grid.
func _astar_pathfind(start: Vector2i, end: Vector2i, unit_size: int) -> Array[Vector2i]:
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}

	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: _heuristic(start, end)}

	var directions := [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]

	while not open_set.is_empty():
		# Find node with lowest f_score
		var current := open_set[0]
		var lowest_f: float = f_score.get(current, INF)
		for node in open_set:
			var node_f: float = f_score.get(node, INF)
			if node_f < lowest_f:
				lowest_f = node_f
				current = node

		if current == end:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		for dir in directions:
			var neighbor: Vector2i = current + dir
			if neighbor.x < 0 or neighbor.x >= _grid_size.x:
				continue
			if neighbor.y < 0 or neighbor.y >= _grid_size.y:
				continue

			var cell_cost: float = _cost_grid[neighbor.x][neighbor.y]

			# Apply unit size penalties
			if unit_size == 0:  # Small units blocked by rubble
				if cell_cost == COST_RUBBLE:
					cell_cost = COST_BLOCKED

			if cell_cost >= COST_BLOCKED:
				continue

			var move_cost := 1.0 if dir.x == 0 or dir.y == 0 else 1.414
			var tentative_g: float = g_score.get(current, INF) + move_cost * cell_cost

			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, end)

				if neighbor not in open_set:
					open_set.append(neighbor)

	return []  # No path found


## Heuristic for A*.
func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()


## Reconstruct path from came_from map.
func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]

	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)

	return path


## Smooth path to remove sharp turns.
func _smooth_path(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() <= 2:
		return path

	var smoothed: Array[Vector3] = [path[0]]

	for i in range(1, path.size() - 1):
		var prev: Vector3 = path[i - 1]
		var curr: Vector3 = path[i]
		var next: Vector3 = path[i + 1]

		# Check if we can skip this point (line of sight)
		if not _has_line_of_sight(prev, next):
			smoothed.append(curr)

	smoothed.append(path[path.size() - 1])
	return smoothed


## Check line of sight between points.
func _has_line_of_sight(start: Vector3, end: Vector3) -> bool:
	var dir := (end - start).normalized()
	var dist := start.distance_to(end)
	var steps := int(dist / GRID_CELL_SIZE) + 1

	for i in steps:
		var pos := start + dir * (float(i) / float(steps)) * dist
		var grid_x := int(pos.x / GRID_CELL_SIZE)
		var grid_z := int(pos.z / GRID_CELL_SIZE)

		if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
			return false

		if _cost_grid[grid_x][grid_z] >= COST_BLOCKED:
			return false

	return true


## Check if position is walkable.
func is_walkable(position: Vector3, unit_size: int = 0) -> bool:
	var grid_x := int(position.x / GRID_CELL_SIZE)
	var grid_z := int(position.z / GRID_CELL_SIZE)

	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return false

	var cost: float = _cost_grid[grid_x][grid_z]

	if unit_size == 0 and cost == COST_RUBBLE:
		return false

	return cost < COST_BLOCKED


## Get movement cost at position.
func get_cost_at(position: Vector3) -> float:
	var grid_x := int(position.x / GRID_CELL_SIZE)
	var grid_z := int(position.z / GRID_CELL_SIZE)

	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return COST_BLOCKED

	return _cost_grid[grid_x][grid_z]


## Set cost at position.
func set_cost_at(position: Vector3, cost: float) -> void:
	var grid_x := int(position.x / GRID_CELL_SIZE)
	var grid_z := int(position.z / GRID_CELL_SIZE)

	if grid_x >= 0 and grid_x < _grid_size.x and grid_z >= 0 and grid_z < _grid_size.y:
		_cost_grid[grid_x][grid_z] = cost


## Cache management.
func _make_cache_key(start: Vector3, end: Vector3, unit_size: int) -> String:
	return "%d,%d_%d,%d_%d" % [int(start.x), int(start.z), int(end.x), int(end.z), unit_size]


func _get_cached_path(key: String) -> Array[Vector3]:
	if not _path_cache.has(key):
		return []

	var cached: Dictionary = _path_cache[key]
	if Time.get_ticks_msec() - cached["timestamp"] > PATH_CACHE_TIME_MS:
		_path_cache.erase(key)
		return []

	return cached["path"]


func _cache_path(key: String, path: Array[Vector3]) -> void:
	_path_cache[key] = {
		"path": path,
		"timestamp": Time.get_ticks_msec()
	}


func _invalidate_cache_near(position: Vector3) -> void:
	var keys_to_remove := []

	for key in _path_cache:
		var cached: Dictionary = _path_cache[key]
		var path: Array[Vector3] = cached["path"]

		for point in path:
			if position.distance_to(point) < PARTIAL_UPDATE_RADIUS:
				keys_to_remove.append(key)
				break

	for key in keys_to_remove:
		_path_cache.erase(key)


## Force rebuild all navmesh.
func rebuild_all() -> void:
	_is_rebuilding = true
	navmesh_rebuild_started.emit()

	var start_time := Time.get_ticks_msec()

	for region_id in _regions:
		_update_region(region_id)

	var total_time := float(Time.get_ticks_msec() - start_time)
	_is_rebuilding = false

	navmesh_rebuild_completed.emit(total_time)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"region_count": _regions.size(),
		"dirty_regions": _dirty_regions.size(),
		"cache_size": _path_cache.size(),
		"grid_size": _grid_size,
		"is_rebuilding": _is_rebuilding
	}


## NavigationRegionData class.
class NavigationRegionData:
	var id: int = 0
	var bounds: AABB = AABB()
	var navmesh_data: Dictionary = {}
	var is_dirty: bool = true
	var last_update_time: int = 0
