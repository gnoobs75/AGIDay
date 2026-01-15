class_name SpatialGrid
extends RefCounted
## SpatialGrid provides efficient spatial partitioning for unit queries.
## Uses dictionary-based cells to handle dynamic world expansion.

signal unit_added(unit_id: int, cell: Vector2i)
signal unit_removed(unit_id: int, cell: Vector2i)
signal unit_moved(unit_id: int, from_cell: Vector2i, to_cell: Vector2i)

## Configuration
const DEFAULT_CELL_SIZE := 10.0

## Grid storage
var _cell_size: float = DEFAULT_CELL_SIZE
var _cells: Dictionary = {}  ## Vector2i -> Array[int] (unit IDs)
var _unit_cells: Dictionary = {}  ## unit_id -> Vector2i (current cell)
var _unit_positions: Dictionary = {}  ## unit_id -> Vector3 (world position)

## Thread safety
var _mutex: Mutex = null
var _thread_safe: bool = false

## Statistics
var _total_units := 0
var _cell_count := 0
var _query_count := 0


func _init(cell_size: float = DEFAULT_CELL_SIZE, thread_safe: bool = false) -> void:
	_cell_size = maxf(cell_size, 1.0)
	_thread_safe = thread_safe
	if _thread_safe:
		_mutex = Mutex.new()


## Convert world position to cell coordinate.
func _world_to_cell(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / _cell_size),
		floori(position.z / _cell_size)  ## Using X-Z plane for top-down
	)


## Convert cell coordinate to world center.
func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		(cell.x + 0.5) * _cell_size,
		0.0,
		(cell.y + 0.5) * _cell_size
	)


## Add unit to grid.
func add_unit(unit_id: int, position: Vector3) -> void:
	if _thread_safe:
		_mutex.lock()

	var cell := _world_to_cell(position)

	# Remove from old cell if exists
	if _unit_cells.has(unit_id):
		_remove_from_cell(unit_id, _unit_cells[unit_id])

	# Add to new cell
	_add_to_cell(unit_id, cell)
	_unit_cells[unit_id] = cell
	_unit_positions[unit_id] = position

	_total_units += 1
	unit_added.emit(unit_id, cell)

	if _thread_safe:
		_mutex.unlock()


## Remove unit from grid.
func remove_unit(unit_id: int) -> void:
	if _thread_safe:
		_mutex.lock()

	if _unit_cells.has(unit_id):
		var cell: Vector2i = _unit_cells[unit_id]
		_remove_from_cell(unit_id, cell)
		_unit_cells.erase(unit_id)
		_unit_positions.erase(unit_id)
		_total_units -= 1
		unit_removed.emit(unit_id, cell)

	if _thread_safe:
		_mutex.unlock()


## Update unit position.
func update_unit_position(unit_id: int, new_position: Vector3) -> void:
	if _thread_safe:
		_mutex.lock()

	if not _unit_cells.has(unit_id):
		# Unit not in grid, add it
		if _thread_safe:
			_mutex.unlock()
		add_unit(unit_id, new_position)
		return

	var old_cell: Vector2i = _unit_cells[unit_id]
	var new_cell := _world_to_cell(new_position)

	_unit_positions[unit_id] = new_position

	# Only update cells if unit moved to different cell
	if old_cell != new_cell:
		_remove_from_cell(unit_id, old_cell)
		_add_to_cell(unit_id, new_cell)
		_unit_cells[unit_id] = new_cell
		unit_moved.emit(unit_id, old_cell, new_cell)

	if _thread_safe:
		_mutex.unlock()


## Add unit to cell.
func _add_to_cell(unit_id: int, cell: Vector2i) -> void:
	if not _cells.has(cell):
		_cells[cell] = []
		_cell_count += 1

	if unit_id not in _cells[cell]:
		_cells[cell].append(unit_id)


## Remove unit from cell.
func _remove_from_cell(unit_id: int, cell: Vector2i) -> void:
	if not _cells.has(cell):
		return

	var cell_units: Array = _cells[cell]
	var idx := cell_units.find(unit_id)
	if idx >= 0:
		cell_units.remove_at(idx)

	# Remove empty cells
	if cell_units.is_empty():
		_cells.erase(cell)
		_cell_count -= 1


## Get units in specific cell.
func get_units_in_cell(cell: Vector2i) -> Array[int]:
	if _thread_safe:
		_mutex.lock()

	var result: Array[int] = []
	if _cells.has(cell):
		result.assign(_cells[cell])

	if _thread_safe:
		_mutex.unlock()

	_query_count += 1
	return result


## Get units within radius of position.
func get_units_in_radius(position: Vector3, radius: float) -> Array[int]:
	if _thread_safe:
		_mutex.lock()

	var result: Array[int] = []
	var center_cell := _world_to_cell(position)
	var cell_radius := ceili(radius / _cell_size)
	var radius_sq := radius * radius

	# Check all cells that could contain units in radius
	for dx in range(-cell_radius, cell_radius + 1):
		for dz in range(-cell_radius, cell_radius + 1):
			var check_cell := Vector2i(center_cell.x + dx, center_cell.y + dz)

			if not _cells.has(check_cell):
				continue

			for unit_id in _cells[check_cell]:
				var unit_pos: Vector3 = _unit_positions.get(unit_id, Vector3.INF)
				var dist_sq := position.distance_squared_to(unit_pos)

				if dist_sq <= radius_sq:
					result.append(unit_id)

	if _thread_safe:
		_mutex.unlock()

	_query_count += 1
	return result


## Get nearest unit to position.
func get_nearest_unit(position: Vector3, max_radius: float = INF) -> int:
	if _thread_safe:
		_mutex.lock()

	var nearest_id := -1
	var nearest_dist_sq := max_radius * max_radius if max_radius != INF else INF

	# Search in expanding rings
	var center_cell := _world_to_cell(position)
	var max_ring := ceili(max_radius / _cell_size) if max_radius != INF else 10

	for ring in range(max_ring + 1):
		var found_in_ring := false

		# Check cells at distance 'ring' from center
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				# Only check cells on the ring edge (optimization)
				if absi(dx) != ring and absi(dz) != ring:
					continue

				var check_cell := Vector2i(center_cell.x + dx, center_cell.y + dz)

				if not _cells.has(check_cell):
					continue

				for unit_id in _cells[check_cell]:
					var unit_pos: Vector3 = _unit_positions.get(unit_id, Vector3.INF)
					var dist_sq := position.distance_squared_to(unit_pos)

					if dist_sq < nearest_dist_sq:
						nearest_dist_sq = dist_sq
						nearest_id = unit_id
						found_in_ring = true

		# If found in this ring and ring is beyond search radius, stop
		if found_in_ring and ring > 0:
			var ring_dist := ring * _cell_size
			if ring_dist > sqrt(nearest_dist_sq) + _cell_size:
				break

	if _thread_safe:
		_mutex.unlock()

	_query_count += 1
	return nearest_id


## Get K nearest units to position.
func get_k_nearest_units(position: Vector3, k: int, max_radius: float = INF) -> Array[int]:
	var units := get_units_in_radius(position, max_radius)

	# Sort by distance
	units.sort_custom(func(a: int, b: int) -> bool:
		var pos_a: Vector3 = _unit_positions.get(a, Vector3.INF)
		var pos_b: Vector3 = _unit_positions.get(b, Vector3.INF)
		return position.distance_squared_to(pos_a) < position.distance_squared_to(pos_b)
	)

	# Return first K
	if units.size() > k:
		units.resize(k)

	return units


## Get units in rectangular area.
func get_units_in_rect(min_pos: Vector3, max_pos: Vector3) -> Array[int]:
	if _thread_safe:
		_mutex.lock()

	var result: Array[int] = []
	var min_cell := _world_to_cell(min_pos)
	var max_cell := _world_to_cell(max_pos)

	for x in range(min_cell.x, max_cell.x + 1):
		for z in range(min_cell.y, max_cell.y + 1):
			var check_cell := Vector2i(x, z)

			if not _cells.has(check_cell):
				continue

			for unit_id in _cells[check_cell]:
				var unit_pos: Vector3 = _unit_positions.get(unit_id, Vector3.INF)

				if unit_pos.x >= min_pos.x and unit_pos.x <= max_pos.x and \
				   unit_pos.z >= min_pos.z and unit_pos.z <= max_pos.z:
					result.append(unit_id)

	if _thread_safe:
		_mutex.unlock()

	_query_count += 1
	return result


## Get unit position.
func get_unit_position(unit_id: int) -> Vector3:
	return _unit_positions.get(unit_id, Vector3.INF)


## Get unit cell.
func get_unit_cell(unit_id: int) -> Vector2i:
	return _unit_cells.get(unit_id, Vector2i(-999999, -999999))


## Check if unit is in grid.
func has_unit(unit_id: int) -> bool:
	return _unit_cells.has(unit_id)


## Get all cells.
func get_all_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _cells:
		result.append(cell)
	return result


## Get all unit IDs.
func get_all_units() -> Array[int]:
	var result: Array[int] = []
	for unit_id in _unit_cells:
		result.append(unit_id)
	return result


## Clear grid.
func clear() -> void:
	if _thread_safe:
		_mutex.lock()

	_cells.clear()
	_unit_cells.clear()
	_unit_positions.clear()
	_total_units = 0
	_cell_count = 0

	if _thread_safe:
		_mutex.unlock()


## Get cell size.
func get_cell_size() -> float:
	return _cell_size


## Get statistics.
func get_statistics() -> Dictionary:
	var avg_units_per_cell := 0.0
	var max_units_in_cell := 0

	for cell in _cells:
		var count: int = _cells[cell].size()
		if count > max_units_in_cell:
			max_units_in_cell = count

	if _cell_count > 0:
		avg_units_per_cell = float(_total_units) / float(_cell_count)

	return {
		"total_units": _total_units,
		"cell_count": _cell_count,
		"avg_units_per_cell": avg_units_per_cell,
		"max_units_in_cell": max_units_in_cell,
		"query_count": _query_count,
		"cell_size": _cell_size
	}


## Debug: Get cell boundaries for visualization.
func get_cell_bounds(cell: Vector2i) -> Dictionary:
	var min_pos := Vector3(cell.x * _cell_size, 0.0, cell.y * _cell_size)
	var max_pos := Vector3((cell.x + 1) * _cell_size, 0.0, (cell.y + 1) * _cell_size)
	return {
		"min": min_pos,
		"max": max_pos,
		"center": _cell_to_world(cell)
	}
