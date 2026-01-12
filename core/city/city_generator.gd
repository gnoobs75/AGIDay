class_name CityGenerator
extends RefCounted
## CityGenerator creates procedural city layouts using Wave Function Collapse.
## Produces deterministic results from seeded RNG for replay support.

signal generation_started(seed: int, size: Vector2i)
signal generation_progress(progress: float, phase: String)
signal generation_complete(success: bool, elapsed_ms: int)
signal area_generated(area_type: String, bounds: Rect2i)

## Generation states
enum State {
	IDLE = 0,
	GENERATING = 1,
	COMPLETE = 2,
	FAILED = 3
}

## Default grid size
const DEFAULT_SIZE := 512

## Tile size in voxels
const TILE_SIZE := 4

## Maximum generation time (ms)
const MAX_GENERATION_TIME_MS := 5000

## Current state
var state: int = State.IDLE

## City seed
var city_seed: int = 0

## Grid size in tiles
var grid_width: int = 0
var grid_height: int = 0

## WFC solver
var solver: WFCSolver = null

## Tileset
var tileset: WFCTileset = null

## Generated city data
var city_data: CityData = null

## RNG for additional randomization
var _rng: RandomNumberGenerator = null


func _init() -> void:
	_rng = RandomNumberGenerator.new()
	tileset = WFCTileset.create_urban_tileset()


## Generate city with given parameters.
func generate(size: int = DEFAULT_SIZE, seed: int = 0) -> CityData:
	if state == State.GENERATING:
		return null

	state = State.GENERATING
	city_seed = seed if seed != 0 else randi()
	_rng.seed = city_seed

	# Convert voxel size to tile grid
	grid_width = size / TILE_SIZE
	grid_height = size / TILE_SIZE

	generation_started.emit(city_seed, Vector2i(size, size))

	var start_time := Time.get_ticks_msec()

	# Initialize solver
	solver = WFCSolver.new()
	solver.initialize(grid_width, grid_height, tileset, city_seed)

	# Connect progress signal
	solver.generation_progress.connect(_on_solver_progress)

	# Seed important locations
	_seed_key_locations()

	generation_progress.emit(0.1, "Seeding key locations")

	# Run WFC solver
	var success := solver.solve()

	var elapsed := Time.get_ticks_msec() - start_time

	if not success or elapsed > MAX_GENERATION_TIME_MS:
		state = State.FAILED
		generation_complete.emit(false, elapsed)
		return null

	generation_progress.emit(0.8, "Building city data")

	# Build city data from solved grid
	city_data = _build_city_data()

	generation_progress.emit(0.9, "Classifying areas")

	# Classify strategic areas
	_classify_areas()

	generation_progress.emit(1.0, "Complete")

	state = State.COMPLETE
	generation_complete.emit(true, elapsed)

	return city_data


## Seed key locations (roads, plazas) before solving.
func _seed_key_locations() -> void:
	var center_x := grid_width / 2
	var center_y := grid_height / 2

	# Main cross through center
	for i in range(0, grid_width, 8):
		solver.pre_collapse(i, center_y, "road_ew")

	for i in range(0, grid_height, 8):
		solver.pre_collapse(center_x, i, "road_ns")

	# Central plaza
	solver.pre_collapse(center_x, center_y, "road_cross")

	# Secondary roads
	var quarter_x := grid_width / 4
	var quarter_y := grid_height / 4

	for i in range(quarter_x, grid_width, grid_width / 2):
		for j in range(0, grid_height, 12):
			if absf(j - center_y) > 2:
				solver.pre_collapse(i, j, "road_ns")

	# Boulevard sections
	var blvd_y := center_y + grid_height / 4
	if blvd_y < grid_height:
		for i in range(quarter_x, 3 * quarter_x, 4):
			solver.pre_collapse(i, blvd_y, "boulevard_ew")

	# Alley sections
	var alley_y := center_y - grid_height / 4
	if alley_y > 0:
		for i in range(quarter_x, 3 * quarter_x, 6):
			solver.pre_collapse(i, alley_y, "alley_ew")


## Build city data from solved grid.
func _build_city_data() -> CityData:
	var data := CityData.new()
	data.initialize(grid_width * TILE_SIZE, grid_height * TILE_SIZE, city_seed)

	# Copy tile data
	for y in grid_height:
		for x in grid_width:
			var tile_id := solver.get_tile_at(x, y)
			var tile := tileset.get_tile(tile_id)

			if tile == null:
				continue

			# Set voxel data for tile area
			var voxel_x := x * TILE_SIZE
			var voxel_y := y * TILE_SIZE

			for dy in TILE_SIZE:
				for dx in TILE_SIZE:
					data.set_tile(voxel_x + dx, voxel_y + dy, tile_id)
					data.set_walkability(voxel_x + dx, voxel_y + dy, tile.walkability)
					data.set_height(voxel_x + dx, voxel_y + dy, tile.height)

			# Store area classification
			data.add_area_tile(tile.area_type, Vector2i(x, y))

	return data


## Classify strategic areas.
func _classify_areas() -> void:
	if city_data == null:
		return

	# Find contiguous areas of each type
	var visited: Dictionary = {}
	var areas: Dictionary = {}

	for y in grid_height:
		for x in grid_width:
			var key := str(x) + "," + str(y)
			if visited.has(key):
				continue

			var tile_id := solver.get_tile_at(x, y)
			var tile := tileset.get_tile(tile_id)

			if tile == null:
				continue

			# Flood fill to find contiguous area
			var bounds := _flood_fill_area(x, y, tile.area_type, visited)

			if bounds.size.x >= 2 and bounds.size.y >= 2:
				if not areas.has(tile.area_type):
					areas[tile.area_type] = []
				areas[tile.area_type].append(bounds)

				area_generated.emit(tile.area_type, bounds)

	# Store area classifications in city data
	for area_type in areas:
		for bounds in areas[area_type]:
			city_data.add_strategic_area(area_type, bounds)


## Flood fill to find contiguous area bounds.
func _flood_fill_area(start_x: int, start_y: int, area_type: String, visited: Dictionary) -> Rect2i:
	var min_x := start_x
	var min_y := start_y
	var max_x := start_x
	var max_y := start_y

	var stack: Array[Vector2i] = [Vector2i(start_x, start_y)]

	while not stack.is_empty():
		var pos := stack.pop_back()
		var key := str(pos.x) + "," + str(pos.y)

		if visited.has(key):
			continue

		if pos.x < 0 or pos.x >= grid_width or pos.y < 0 or pos.y >= grid_height:
			continue

		var tile_id := solver.get_tile_at(pos.x, pos.y)
		var tile := tileset.get_tile(tile_id)

		if tile == null or tile.area_type != area_type:
			continue

		visited[key] = true

		min_x = mini(min_x, pos.x)
		min_y = mini(min_y, pos.y)
		max_x = maxi(max_x, pos.x)
		max_y = maxi(max_y, pos.y)

		# Add neighbors
		stack.append(Vector2i(pos.x + 1, pos.y))
		stack.append(Vector2i(pos.x - 1, pos.y))
		stack.append(Vector2i(pos.x, pos.y + 1))
		stack.append(Vector2i(pos.x, pos.y - 1))

	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Handle solver progress.
func _on_solver_progress(progress: float) -> void:
	generation_progress.emit(0.1 + progress * 0.7, "Solving WFC")


## Get city data.
func get_city_data() -> CityData:
	return city_data


## Get tile at voxel position.
func get_tile_at_voxel(voxel_x: int, voxel_y: int) -> WFCTile:
	if city_data == null:
		return null

	var tile_id := city_data.get_tile(voxel_x, voxel_y)
	return tileset.get_tile(tile_id)


## Get walkability at voxel position.
func get_walkability_at(voxel_x: int, voxel_y: int) -> float:
	if city_data == null:
		return 0.0
	return city_data.get_walkability(voxel_x, voxel_y)


## Get strategic areas by type.
func get_areas_by_type(area_type: String) -> Array[Rect2i]:
	if city_data == null:
		return []
	return city_data.get_strategic_areas(area_type)


## Check if generation is complete.
func is_complete() -> bool:
	return state == State.COMPLETE


## Check if generation failed.
func is_failed() -> bool:
	return state == State.FAILED


## Get seed used for generation.
func get_seed() -> int:
	return city_seed


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"state": state,
		"city_seed": city_seed,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"city_data": city_data.to_dict() if city_data != null else {}
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	state = data.get("state", State.IDLE)
	city_seed = data.get("city_seed", 0)
	grid_width = data.get("grid_width", 0)
	grid_height = data.get("grid_height", 0)

	var city_data_dict: Dictionary = data.get("city_data", {})
	if not city_data_dict.is_empty():
		city_data = CityData.from_dict(city_data_dict)

	if city_seed != 0:
		_rng.seed = city_seed


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"state": _get_state_name(),
		"seed": city_seed,
		"grid_size": "%dx%d tiles" % [grid_width, grid_height],
		"voxel_size": "%dx%d" % [grid_width * TILE_SIZE, grid_height * TILE_SIZE],
		"has_data": city_data != null
	}


## Get state name.
func _get_state_name() -> String:
	match state:
		State.IDLE: return "IDLE"
		State.GENERATING: return "GENERATING"
		State.COMPLETE: return "COMPLETE"
		State.FAILED: return "FAILED"
	return "UNKNOWN"
