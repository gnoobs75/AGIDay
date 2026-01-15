class_name WFCBuildingPlacer
extends RefCounted
## WFCBuildingPlacer uses Wave Function Collapse to generate building layouts.
## Respects zone constraints and neighbor compatibility rules.

signal generation_started()
signal cell_collapsed(x: int, y: int, building_type: int)
signal generation_completed()
signal generation_failed(reason: String)

## Grid size
const GRID_SIZE := 512

## Building types
enum BuildingType {
	EMPTY,
	SMALL_RESIDENTIAL,
	MEDIUM_RESIDENTIAL,
	LARGE_RESIDENTIAL,
	SMALL_COMMERCIAL,
	MEDIUM_COMMERCIAL,
	LARGE_COMMERCIAL,
	SMALL_INDUSTRIAL,
	MEDIUM_INDUSTRIAL,
	LARGE_INDUSTRIAL,
	SKYSCRAPER,
	WAREHOUSE,
	FACTORY,
	PARK,
	ROAD
}

## Zone types
enum ZoneType {
	ZERG_ALLEY,      ## Small buildings, high density
	TANK_BOULEVARD,  ## Large buildings, wide streets
	MIXED_USE,       ## Various building sizes
	INDUSTRIAL,      ## Factories and warehouses
	PARK             ## Open spaces
}

## Building sizes (in grid cells)
const BUILDING_SIZES := {
	BuildingType.EMPTY: Vector2i(1, 1),
	BuildingType.SMALL_RESIDENTIAL: Vector2i(1, 1),
	BuildingType.MEDIUM_RESIDENTIAL: Vector2i(2, 2),
	BuildingType.LARGE_RESIDENTIAL: Vector2i(2, 3),
	BuildingType.SMALL_COMMERCIAL: Vector2i(1, 1),
	BuildingType.MEDIUM_COMMERCIAL: Vector2i(2, 2),
	BuildingType.LARGE_COMMERCIAL: Vector2i(3, 3),
	BuildingType.SMALL_INDUSTRIAL: Vector2i(2, 2),
	BuildingType.MEDIUM_INDUSTRIAL: Vector2i(3, 3),
	BuildingType.LARGE_INDUSTRIAL: Vector2i(4, 4),
	BuildingType.SKYSCRAPER: Vector2i(2, 2),
	BuildingType.WAREHOUSE: Vector2i(4, 3),
	BuildingType.FACTORY: Vector2i(4, 4),
	BuildingType.PARK: Vector2i(3, 3),
	BuildingType.ROAD: Vector2i(1, 1)
}

## Zone to valid building types mapping
const ZONE_BUILDINGS := {
	ZoneType.ZERG_ALLEY: [
		BuildingType.SMALL_RESIDENTIAL,
		BuildingType.SMALL_COMMERCIAL,
		BuildingType.ROAD
	],
	ZoneType.TANK_BOULEVARD: [
		BuildingType.LARGE_RESIDENTIAL,
		BuildingType.LARGE_COMMERCIAL,
		BuildingType.SKYSCRAPER,
		BuildingType.ROAD
	],
	ZoneType.MIXED_USE: [
		BuildingType.SMALL_RESIDENTIAL,
		BuildingType.MEDIUM_RESIDENTIAL,
		BuildingType.SMALL_COMMERCIAL,
		BuildingType.MEDIUM_COMMERCIAL,
		BuildingType.PARK,
		BuildingType.ROAD
	],
	ZoneType.INDUSTRIAL: [
		BuildingType.SMALL_INDUSTRIAL,
		BuildingType.MEDIUM_INDUSTRIAL,
		BuildingType.LARGE_INDUSTRIAL,
		BuildingType.WAREHOUSE,
		BuildingType.FACTORY,
		BuildingType.ROAD
	],
	ZoneType.PARK: [
		BuildingType.PARK,
		BuildingType.ROAD,
		BuildingType.EMPTY
	]
}

## Neighbor compatibility (which buildings can be adjacent)
var _neighbor_rules: Dictionary = {}

## WFC state
var _grid: Array = []              ## 2D array of collapsed BuildingType
var _possibilities: Array = []     ## 2D array of Array[BuildingType] (superpositions)
var _zone_grid: Array = []         ## 2D array of ZoneType

## RNG
var _rng: RandomNumberGenerator = null

## Statistics
var _cells_collapsed := 0
var _propagation_count := 0


func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_setup_neighbor_rules()


## Setup neighbor compatibility rules.
func _setup_neighbor_rules() -> void:
	# Define which buildings can be adjacent
	# Roads can be next to anything
	for bt in BuildingType.values():
		if not _neighbor_rules.has(bt):
			_neighbor_rules[bt] = []

		# Roads are compatible with everything
		_neighbor_rules[bt].append(BuildingType.ROAD)

		# Same type is compatible with itself
		_neighbor_rules[bt].append(bt)

	# Specific compatibility rules
	_add_neighbor_rule(BuildingType.SMALL_RESIDENTIAL, BuildingType.MEDIUM_RESIDENTIAL)
	_add_neighbor_rule(BuildingType.SMALL_RESIDENTIAL, BuildingType.SMALL_COMMERCIAL)
	_add_neighbor_rule(BuildingType.MEDIUM_RESIDENTIAL, BuildingType.LARGE_RESIDENTIAL)
	_add_neighbor_rule(BuildingType.MEDIUM_RESIDENTIAL, BuildingType.PARK)

	_add_neighbor_rule(BuildingType.SMALL_COMMERCIAL, BuildingType.MEDIUM_COMMERCIAL)
	_add_neighbor_rule(BuildingType.MEDIUM_COMMERCIAL, BuildingType.LARGE_COMMERCIAL)
	_add_neighbor_rule(BuildingType.LARGE_COMMERCIAL, BuildingType.SKYSCRAPER)

	_add_neighbor_rule(BuildingType.SMALL_INDUSTRIAL, BuildingType.MEDIUM_INDUSTRIAL)
	_add_neighbor_rule(BuildingType.MEDIUM_INDUSTRIAL, BuildingType.LARGE_INDUSTRIAL)
	_add_neighbor_rule(BuildingType.LARGE_INDUSTRIAL, BuildingType.WAREHOUSE)
	_add_neighbor_rule(BuildingType.WAREHOUSE, BuildingType.FACTORY)

	_add_neighbor_rule(BuildingType.PARK, BuildingType.SMALL_RESIDENTIAL)
	_add_neighbor_rule(BuildingType.PARK, BuildingType.MEDIUM_RESIDENTIAL)
	_add_neighbor_rule(BuildingType.PARK, BuildingType.EMPTY)


## Add bidirectional neighbor rule.
func _add_neighbor_rule(a: int, b: int) -> void:
	if not _neighbor_rules.has(a):
		_neighbor_rules[a] = []
	if not _neighbor_rules.has(b):
		_neighbor_rules[b] = []

	if b not in _neighbor_rules[a]:
		_neighbor_rules[a].append(b)
	if a not in _neighbor_rules[b]:
		_neighbor_rules[b].append(a)


## Generate building layout.
func generate_building_layout(zone_grid: Array, seed: int = 0) -> Array:
	_rng.seed = seed if seed != 0 else Time.get_ticks_msec()
	_zone_grid = zone_grid
	_cells_collapsed = 0
	_propagation_count = 0

	generation_started.emit()

	# Initialize grids
	_initialize_grids()

	# WFC main loop
	while true:
		# Find cell with minimum entropy
		var min_cell := _find_minimum_entropy_cell()

		if min_cell.x < 0:
			# All cells collapsed
			break

		# Collapse the cell
		if not _collapse_cell(min_cell.x, min_cell.y):
			generation_failed.emit("Failed to collapse cell at (%d, %d)" % [min_cell.x, min_cell.y])
			return []

		# Propagate constraints
		_propagate_constraints(min_cell.x, min_cell.y)

		_cells_collapsed += 1

	generation_completed.emit()
	return _grid


## Initialize grids with possibilities.
func _initialize_grids() -> void:
	_grid = []
	_possibilities = []

	for x in GRID_SIZE:
		var grid_row := []
		var poss_row := []

		for y in GRID_SIZE:
			grid_row.append(BuildingType.EMPTY)

			# Get zone for this cell
			var zone: int = _get_zone_at(x, y)
			var valid_types: Array = ZONE_BUILDINGS.get(zone, [BuildingType.EMPTY]).duplicate()
			poss_row.append(valid_types)

		_grid.append(grid_row)
		_possibilities.append(poss_row)


## Get zone at grid position.
func _get_zone_at(x: int, y: int) -> int:
	if _zone_grid.is_empty():
		return ZoneType.MIXED_USE

	if x < 0 or x >= _zone_grid.size():
		return ZoneType.MIXED_USE

	if y < 0 or y >= _zone_grid[x].size():
		return ZoneType.MIXED_USE

	return _zone_grid[x][y]


## Find cell with minimum entropy (fewest possibilities).
func _find_minimum_entropy_cell() -> Vector2i:
	var min_entropy := 999999
	var min_cell := Vector2i(-1, -1)
	var candidates: Array[Vector2i] = []

	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var poss: Array = _possibilities[x][y]

			# Skip already collapsed cells
			if poss.size() <= 1:
				continue

			if poss.size() < min_entropy:
				min_entropy = poss.size()
				candidates.clear()
				candidates.append(Vector2i(x, y))
			elif poss.size() == min_entropy:
				candidates.append(Vector2i(x, y))

	# Randomly select from candidates (for variety)
	if not candidates.is_empty():
		min_cell = candidates[_rng.randi() % candidates.size()]

	return min_cell


## Collapse a cell to a single possibility.
func _collapse_cell(x: int, y: int) -> bool:
	var poss: Array = _possibilities[x][y]

	if poss.is_empty():
		return false

	# Weight selection by building size (prefer smaller for variety)
	var total_weight := 0.0
	var weights: Array[float] = []

	for bt in poss:
		var size: Vector2i = BUILDING_SIZES.get(bt, Vector2i(1, 1))
		var weight := 1.0 / (size.x * size.y)  ## Smaller = higher weight
		weights.append(weight)
		total_weight += weight

	# Random selection based on weights
	var roll := _rng.randf() * total_weight
	var cumulative := 0.0
	var selected: int = poss[0]

	for i in poss.size():
		cumulative += weights[i]
		if roll <= cumulative:
			selected = poss[i]
			break

	# Collapse to selected type
	_grid[x][y] = selected
	_possibilities[x][y] = [selected]

	# Handle multi-cell buildings
	var size: Vector2i = BUILDING_SIZES.get(selected, Vector2i(1, 1))
	if size.x > 1 or size.y > 1:
		_reserve_building_cells(x, y, size)

	cell_collapsed.emit(x, y, selected)
	return true


## Reserve cells for multi-cell building.
func _reserve_building_cells(start_x: int, start_y: int, size: Vector2i) -> void:
	for dx in size.x:
		for dy in size.y:
			if dx == 0 and dy == 0:
				continue  ## Skip origin cell

			var nx := start_x + dx
			var ny := start_y + dy

			if nx >= 0 and nx < GRID_SIZE and ny >= 0 and ny < GRID_SIZE:
				_grid[nx][ny] = BuildingType.EMPTY  ## Mark as part of building
				_possibilities[nx][ny] = [BuildingType.EMPTY]


## Propagate constraints to neighbors.
func _propagate_constraints(x: int, y: int) -> void:
	var stack: Array[Vector2i] = [Vector2i(x, y)]

	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		var current_poss: Array = _possibilities[cell.x][cell.y]

		if current_poss.is_empty():
			continue

		# Check all 4 neighbors
		for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var nx: int = cell.x + dir.x
			var ny: int = cell.y + dir.y

			if nx < 0 or nx >= GRID_SIZE or ny < 0 or ny >= GRID_SIZE:
				continue

			var neighbor_poss: Array = _possibilities[nx][ny]
			if neighbor_poss.size() <= 1:
				continue  ## Already collapsed

			# Filter neighbor possibilities based on compatibility
			var new_poss := _filter_possibilities(neighbor_poss, current_poss)

			if new_poss.size() < neighbor_poss.size():
				_possibilities[nx][ny] = new_poss
				stack.append(Vector2i(nx, ny))
				_propagation_count += 1


## Filter possibilities based on neighbor compatibility.
func _filter_possibilities(neighbor_poss: Array, current_poss: Array) -> Array:
	var valid: Array = []

	for np in neighbor_poss:
		var is_valid := false

		for cp in current_poss:
			var compatible: Array = _neighbor_rules.get(cp, [])
			if np in compatible:
				is_valid = true
				break

		if is_valid:
			valid.append(np)

	return valid


## Get the generated grid.
func get_grid() -> Array:
	return _grid


## Get building at position.
func get_building_at(x: int, y: int) -> int:
	if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE:
		return BuildingType.EMPTY
	return _grid[x][y]


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"cells_collapsed": _cells_collapsed,
		"propagation_count": _propagation_count,
		"grid_size": GRID_SIZE
	}


## Create default zone grid (for testing).
static func create_default_zone_grid() -> Array:
	var zones := []
	for x in GRID_SIZE:
		var row := []
		for y in GRID_SIZE:
			# Simple pattern: corners are different zones
			var zone: int = ZoneType.MIXED_USE
			if x < GRID_SIZE / 4:
				if y < GRID_SIZE / 4:
					zone = ZoneType.ZERG_ALLEY
				else:
					zone = ZoneType.INDUSTRIAL
			elif x > GRID_SIZE * 3 / 4:
				if y > GRID_SIZE * 3 / 4:
					zone = ZoneType.TANK_BOULEVARD
				else:
					zone = ZoneType.INDUSTRIAL
			else:
				zone = ZoneType.MIXED_USE
			row.append(zone)
		zones.append(row)
	return zones
