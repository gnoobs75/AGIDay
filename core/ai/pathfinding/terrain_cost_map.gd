class_name TerrainCostMap
extends RefCounted
## TerrainCostMap maintains movement costs for all terrain states.
## Integrates with destruction and flattening systems.

signal cost_changed(position: Vector3, old_cost: float, new_cost: float)
signal bulk_update_completed(cells_updated: int)

## Terrain types
enum TerrainType {
	SMOOTH,     ## Normal terrain, full speed
	GRASS,      ## Slight slowdown
	RUBBLE,     ## Moderate slowdown
	CRATER,     ## Heavy slowdown
	WATER,      ## Impassable for ground units
	BUILDING,   ## Impassable
	ROAD        ## Slight speed bonus
}

## Base movement costs by terrain type
const BASE_COSTS := {
	TerrainType.SMOOTH: 1.0,
	TerrainType.GRASS: 1.1,
	TerrainType.RUBBLE: 1.5,
	TerrainType.CRATER: 2.0,
	TerrainType.WATER: INF,
	TerrainType.BUILDING: INF,
	TerrainType.ROAD: 0.8
}

## Configuration
const CELL_SIZE := 2.0
const DEFAULT_COST := 1.0

## Cost grid
var _cost_grid: Array = []
var _terrain_grid: Array = []    ## Stores TerrainType
var _grid_size := Vector2i(512, 512)

## Height data for slope costs
var _height_grid: Array = []
const MAX_SLOPE_COST := 0.5      ## Additional cost per unit height difference


func _init() -> void:
	pass


## Initialize cost map.
func initialize(world_size: Vector2i = Vector2i(512, 512)) -> void:
	_grid_size = world_size
	_initialize_grids()


## Initialize all grids.
func _initialize_grids() -> void:
	_cost_grid = []
	_terrain_grid = []
	_height_grid = []

	for x in _grid_size.x:
		var cost_row := []
		var terrain_row := []
		var height_row := []

		for z in _grid_size.y:
			cost_row.append(DEFAULT_COST)
			terrain_row.append(TerrainType.SMOOTH)
			height_row.append(0.0)

		_cost_grid.append(cost_row)
		_terrain_grid.append(terrain_row)
		_height_grid.append(height_row)


## Set terrain type at position.
func set_terrain(position: Vector3, terrain_type: TerrainType) -> void:
	var grid_x := int(position.x / CELL_SIZE)
	var grid_z := int(position.z / CELL_SIZE)

	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return

	var old_terrain: TerrainType = _terrain_grid[grid_x][grid_z]
	if old_terrain == terrain_type:
		return

	_terrain_grid[grid_x][grid_z] = terrain_type

	# Update cost
	var old_cost: float = _cost_grid[grid_x][grid_z]
	var new_cost: float = _calculate_cell_cost(grid_x, grid_z)
	_cost_grid[grid_x][grid_z] = new_cost

	if old_cost != new_cost:
		cost_changed.emit(position, old_cost, new_cost)


## Set terrain type at grid coordinates.
func set_terrain_at_grid(grid_x: int, grid_z: int, terrain_type: TerrainType) -> void:
	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return

	_terrain_grid[grid_x][grid_z] = terrain_type
	_cost_grid[grid_x][grid_z] = _calculate_cell_cost(grid_x, grid_z)


## Set height at position.
func set_height(position: Vector3, height: float) -> void:
	var grid_x := int(position.x / CELL_SIZE)
	var grid_z := int(position.z / CELL_SIZE)

	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return

	_height_grid[grid_x][grid_z] = height

	# Recalculate costs for this cell and neighbors
	_update_slope_costs(grid_x, grid_z)


## Update slope costs for cell and neighbors.
func _update_slope_costs(grid_x: int, grid_z: int) -> void:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var nx := grid_x + dx
			var nz := grid_z + dz

			if nx >= 0 and nx < _grid_size.x and nz >= 0 and nz < _grid_size.y:
				_cost_grid[nx][nz] = _calculate_cell_cost(nx, nz)


## Calculate cost for cell.
func _calculate_cell_cost(grid_x: int, grid_z: int) -> float:
	var terrain: TerrainType = _terrain_grid[grid_x][grid_z]
	var base_cost: float = BASE_COSTS.get(terrain, DEFAULT_COST)

	if base_cost >= INF:
		return INF

	# Add slope cost
	var slope_cost := _calculate_slope_cost(grid_x, grid_z)
	return base_cost + slope_cost


## Calculate slope cost based on height differences.
func _calculate_slope_cost(grid_x: int, grid_z: int) -> float:
	var center_height: float = _height_grid[grid_x][grid_z]
	var max_diff := 0.0

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				continue

			var nx := grid_x + dx
			var nz := grid_z + dz

			if nx >= 0 and nx < _grid_size.x and nz >= 0 and nz < _grid_size.y:
				var neighbor_height: float = _height_grid[nx][nz]
				var diff := absf(neighbor_height - center_height)
				max_diff = maxf(max_diff, diff)

	return minf(max_diff * MAX_SLOPE_COST, MAX_SLOPE_COST * 10)


## Get cost at position.
func get_cost(position: Vector3) -> float:
	var grid_x := int(position.x / CELL_SIZE)
	var grid_z := int(position.z / CELL_SIZE)

	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return INF

	return _cost_grid[grid_x][grid_z]


## Get cost at grid coordinates.
func get_cost_at_grid(grid_x: int, grid_z: int) -> float:
	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return INF

	return _cost_grid[grid_x][grid_z]


## Get terrain type at position.
func get_terrain(position: Vector3) -> TerrainType:
	var grid_x := int(position.x / CELL_SIZE)
	var grid_z := int(position.z / CELL_SIZE)

	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return TerrainType.BUILDING

	return _terrain_grid[grid_x][grid_z]


## Get height at position.
func get_height(position: Vector3) -> float:
	var grid_x := int(position.x / CELL_SIZE)
	var grid_z := int(position.z / CELL_SIZE)

	if grid_x < 0 or grid_x >= _grid_size.x or grid_z < 0 or grid_z >= _grid_size.y:
		return 0.0

	return _height_grid[grid_x][grid_z]


## Check if position is passable.
func is_passable(position: Vector3) -> bool:
	return get_cost(position) < INF


## Apply destruction state to area.
func apply_destruction(center: Vector3, radius: float, destruction_level: int) -> int:
	var cells_updated := 0

	var min_x := int((center.x - radius) / CELL_SIZE)
	var max_x := int((center.x + radius) / CELL_SIZE)
	var min_z := int((center.z - radius) / CELL_SIZE)
	var max_z := int((center.z + radius) / CELL_SIZE)

	for grid_x in range(maxi(0, min_x), mini(_grid_size.x, max_x + 1)):
		for grid_z in range(maxi(0, min_z), mini(_grid_size.y, max_z + 1)):
			var cell_center := Vector3(
				grid_x * CELL_SIZE + CELL_SIZE / 2,
				0,
				grid_z * CELL_SIZE + CELL_SIZE / 2
			)

			var dist := center.distance_to(cell_center)
			if dist > radius:
				continue

			var terrain: TerrainType
			match destruction_level:
				0, 1:  # Intact, Cracked
					terrain = TerrainType.BUILDING
				2:  # Rubble
					terrain = TerrainType.RUBBLE
				3:  # Crater
					terrain = TerrainType.CRATER
				_:
					terrain = TerrainType.SMOOTH

			set_terrain_at_grid(grid_x, grid_z, terrain)
			cells_updated += 1

	if cells_updated > 0:
		bulk_update_completed.emit(cells_updated)

	return cells_updated


## Apply flattening to area.
func apply_flattening(center: Vector3, radius: float, target_height: float = 0.0) -> int:
	var cells_updated := 0

	var min_x := int((center.x - radius) / CELL_SIZE)
	var max_x := int((center.x + radius) / CELL_SIZE)
	var min_z := int((center.z - radius) / CELL_SIZE)
	var max_z := int((center.z + radius) / CELL_SIZE)

	for grid_x in range(maxi(0, min_x), mini(_grid_size.x, max_x + 1)):
		for grid_z in range(maxi(0, min_z), mini(_grid_size.y, max_z + 1)):
			var cell_center := Vector3(
				grid_x * CELL_SIZE + CELL_SIZE / 2,
				0,
				grid_z * CELL_SIZE + CELL_SIZE / 2
			)

			var dist := center.distance_to(cell_center)
			if dist > radius:
				continue

			# Flatten height
			_height_grid[grid_x][grid_z] = target_height

			# Set to smooth terrain
			_terrain_grid[grid_x][grid_z] = TerrainType.SMOOTH
			_cost_grid[grid_x][grid_z] = _calculate_cell_cost(grid_x, grid_z)
			cells_updated += 1

	if cells_updated > 0:
		bulk_update_completed.emit(cells_updated)

	return cells_updated


## Initialize from voxel data.
func initialize_from_voxels(voxel_heights: Array, building_positions: Array) -> void:
	# Set heights from voxel data
	for x in mini(voxel_heights.size(), _grid_size.x):
		for z in mini(voxel_heights[x].size(), _grid_size.y):
			_height_grid[x][z] = voxel_heights[x][z]

	# Mark building positions
	for pos in building_positions:
		if pos is Vector2i:
			if pos.x >= 0 and pos.x < _grid_size.x and pos.y >= 0 and pos.y < _grid_size.y:
				_terrain_grid[pos.x][pos.y] = TerrainType.BUILDING
		elif pos is Vector3:
			var grid_x := int(pos.x / CELL_SIZE)
			var grid_z := int(pos.z / CELL_SIZE)
			if grid_x >= 0 and grid_x < _grid_size.x and grid_z >= 0 and grid_z < _grid_size.y:
				_terrain_grid[grid_x][grid_z] = TerrainType.BUILDING

	# Recalculate all costs
	for x in _grid_size.x:
		for z in _grid_size.y:
			_cost_grid[x][z] = _calculate_cell_cost(x, z)


## Get cost grid (for pathfinding).
func get_cost_grid() -> Array:
	return _cost_grid


## Get terrain grid.
func get_terrain_grid() -> Array:
	return _terrain_grid


## Get grid size.
func get_grid_size() -> Vector2i:
	return _grid_size


## Get statistics.
func get_statistics() -> Dictionary:
	var terrain_counts := {}
	for t in TerrainType.values():
		terrain_counts[t] = 0

	var passable_count := 0

	for x in _grid_size.x:
		for z in _grid_size.y:
			terrain_counts[_terrain_grid[x][z]] += 1
			if _cost_grid[x][z] < INF:
				passable_count += 1

	var total_cells := _grid_size.x * _grid_size.y

	return {
		"grid_size": _grid_size,
		"cell_size": CELL_SIZE,
		"total_cells": total_cells,
		"passable_cells": passable_count,
		"impassable_cells": total_cells - passable_count,
		"terrain_counts": terrain_counts
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	# Use run-length encoding for terrain grid
	var terrain_rle := _rle_encode_terrain()

	return {
		"grid_size": {"x": _grid_size.x, "y": _grid_size.y},
		"terrain_rle": terrain_rle
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	var size: Dictionary = data.get("grid_size", {})
	_grid_size = Vector2i(size.get("x", 512), size.get("y", 512))

	_initialize_grids()

	# Decode terrain RLE
	var terrain_rle: Array = data.get("terrain_rle", [])
	_rle_decode_terrain(terrain_rle)

	# Recalculate costs
	for x in _grid_size.x:
		for z in _grid_size.y:
			_cost_grid[x][z] = _calculate_cell_cost(x, z)


## Run-length encode terrain grid.
func _rle_encode_terrain() -> Array:
	var encoded := []
	var flat := []

	for x in _grid_size.x:
		for z in _grid_size.y:
			flat.append(_terrain_grid[x][z])

	var i := 0
	while i < flat.size():
		var value: int = flat[i]
		var run := 1

		while i + run < flat.size() and flat[i + run] == value and run < 255:
			run += 1

		encoded.append(value)
		encoded.append(run)
		i += run

	return encoded


## Run-length decode terrain grid.
func _rle_decode_terrain(encoded: Array) -> void:
	var flat := []
	var i := 0

	while i + 1 < encoded.size():
		var value: int = encoded[i]
		var run: int = encoded[i + 1]

		for j in run:
			flat.append(value)

		i += 2

	var idx := 0
	for x in _grid_size.x:
		for z in _grid_size.y:
			if idx < flat.size():
				_terrain_grid[x][z] = flat[idx]
				idx += 1
