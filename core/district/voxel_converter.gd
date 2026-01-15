class_name VoxelConverter
extends RefCounted
## VoxelConverter converts 2D building grids into 3D voxel grids.
## Assigns heights based on building type and creates VoxelState for each cell.

signal conversion_started()
signal conversion_progress(progress: float)
signal conversion_completed(voxel_count: int)

## Grid dimensions
const GRID_SIZE := 512
const MAX_HEIGHT := 64

## Building height ranges (min, max)
const HEIGHT_RANGES := {
	0: Vector2i(0, 0),     ## EMPTY - no height
	1: Vector2i(3, 5),     ## SMALL_RESIDENTIAL
	2: Vector2i(5, 8),     ## MEDIUM_RESIDENTIAL
	3: Vector2i(8, 12),    ## LARGE_RESIDENTIAL
	4: Vector2i(3, 5),     ## SMALL_COMMERCIAL
	5: Vector2i(5, 8),     ## MEDIUM_COMMERCIAL
	6: Vector2i(8, 12),    ## LARGE_COMMERCIAL
	7: Vector2i(4, 6),     ## SMALL_INDUSTRIAL
	8: Vector2i(6, 8),     ## MEDIUM_INDUSTRIAL
	9: Vector2i(8, 10),    ## LARGE_INDUSTRIAL
	10: Vector2i(10, 15),  ## SKYSCRAPER
	11: Vector2i(4, 6),    ## WAREHOUSE
	12: Vector2i(6, 10),   ## FACTORY
	13: Vector2i(1, 2),    ## PARK
	14: Vector2i(0, 0)     ## ROAD - no height
}

## Building HP values
const HP_VALUES := {
	0: 0,        ## EMPTY
	1: 75,       ## SMALL_RESIDENTIAL
	2: 100,      ## MEDIUM_RESIDENTIAL
	3: 125,      ## LARGE_RESIDENTIAL
	4: 100,      ## SMALL_COMMERCIAL
	5: 125,      ## MEDIUM_COMMERCIAL
	6: 150,      ## LARGE_COMMERCIAL
	7: 150,      ## SMALL_INDUSTRIAL
	8: 175,      ## MEDIUM_INDUSTRIAL
	9: 200,      ## LARGE_INDUSTRIAL
	10: 200,     ## SKYSCRAPER
	11: 175,     ## WAREHOUSE
	12: 200,     ## FACTORY
	13: 50,      ## PARK
	14: 0        ## ROAD
}

## Industrial building types
const INDUSTRIAL_TYPES := [7, 8, 9, 11, 12]

## Power plant positions (from PowerGridGenerator)
var _power_positions: Array = []

## RNG
var _rng: RandomNumberGenerator = null

## Generated voxel grid (3D: x, z, y)
var _voxel_grid: Dictionary = {}  ## Vector3i -> VoxelState
var _height_map: Array = []        ## 2D array of heights

## Statistics
var _voxel_count := 0
var _building_count := 0


func _init() -> void:
	_rng = RandomNumberGenerator.new()


## Convert building grid to 3D voxel grid.
func convert_buildings_to_voxels(building_grid: Array, power_positions: Array = [],
								 seed_value: int = 0) -> Dictionary:
	_rng.seed = seed_value if seed_value != 0 else Time.get_ticks_msec()
	_power_positions = power_positions
	_voxel_grid.clear()
	_height_map.clear()
	_voxel_count = 0
	_building_count = 0

	conversion_started.emit()

	# Initialize height map
	for x in GRID_SIZE:
		var row := []
		for z in GRID_SIZE:
			row.append(0)
		_height_map.append(row)

	# Process building grid
	var total_cells := GRID_SIZE * GRID_SIZE
	var processed := 0

	for x in GRID_SIZE:
		if x >= building_grid.size():
			continue

		for z in GRID_SIZE:
			if z >= building_grid[x].size():
				continue

			var building_type: int = building_grid[x][z]
			_process_building_cell(x, z, building_type)

			processed += 1
			if processed % 10000 == 0:
				conversion_progress.emit(float(processed) / float(total_cells))

	conversion_completed.emit(_voxel_count)

	return {
		"voxel_grid": _voxel_grid,
		"height_map": _height_map,
		"voxel_count": _voxel_count,
		"building_count": _building_count
	}


## Process a single building cell.
func _process_building_cell(x: int, z: int, building_type: int) -> void:
	# Skip empty and road types
	if building_type == 0 or building_type == 14:
		return

	# Get height range for this building type
	var height_range: Vector2i = HEIGHT_RANGES.get(building_type, Vector2i(0, 0))
	if height_range.y <= 0:
		return

	# Determine height with variance
	var height := _rng.randi_range(height_range.x, height_range.y)
	_height_map[x][z] = height

	# Determine properties
	var hp: float = HP_VALUES.get(building_type, 100)
	var is_industrial := building_type in INDUSTRIAL_TYPES
	var is_power := _is_power_position(x, z)

	# Create voxels from ground to height
	for y in range(height):
		var voxel := VoxelState.create(x, y, z, hp, building_type, is_power, is_industrial)

		# Mark structural elements (bottom and corners)
		if y == 0 or y == height - 1:
			voxel.is_structural = true

		_voxel_grid[Vector3i(x, y, z)] = voxel
		_voxel_count += 1

	_building_count += 1


## Check if position is a power node.
func _is_power_position(x: int, z: int) -> bool:
	# Convert to zone coordinates (32 voxels per zone)
	var zone_x := x / 32
	var zone_z := z / 32

	for pos in _power_positions:
		if pos is Vector2i:
			if pos.x == zone_x and pos.y == zone_z:
				return true
		elif pos is Dictionary:
			if pos.get("x", -1) == zone_x and pos.get("y", -1) == zone_z:
				return true

	return false


## Get voxel at position.
func get_voxel_at(x: int, y: int, z: int) -> VoxelState:
	return _voxel_grid.get(Vector3i(x, y, z))


## Get voxel at Vector3i position.
func get_voxel(pos: Vector3i) -> VoxelState:
	return _voxel_grid.get(pos)


## Get height at position.
func get_height_at(x: int, z: int) -> int:
	if x < 0 or x >= GRID_SIZE or z < 0 or z >= GRID_SIZE:
		return 0
	if x >= _height_map.size() or z >= _height_map[x].size():
		return 0
	return _height_map[x][z]


## Get all voxels in column.
func get_column_voxels(x: int, z: int) -> Array[VoxelState]:
	var result: Array[VoxelState] = []
	var height := get_height_at(x, z)

	for y in range(height):
		var voxel := _voxel_grid.get(Vector3i(x, y, z))
		if voxel != null:
			result.append(voxel)

	return result


## Get voxels in radius (3D).
func get_voxels_in_radius(center: Vector3, radius: float) -> Array[VoxelState]:
	var result: Array[VoxelState] = []
	var radius_sq := radius * radius

	var min_x := maxi(0, int(center.x - radius))
	var max_x := mini(GRID_SIZE - 1, int(center.x + radius))
	var min_z := maxi(0, int(center.z - radius))
	var max_z := mini(GRID_SIZE - 1, int(center.z + radius))
	var min_y := maxi(0, int(center.y - radius))
	var max_y := mini(MAX_HEIGHT - 1, int(center.y + radius))

	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			for y in range(min_y, max_y + 1):
				var pos := Vector3i(x, y, z)
				var voxel := _voxel_grid.get(pos)
				if voxel != null:
					var dist_sq := (Vector3(x, y, z) - center).length_squared()
					if dist_sq <= radius_sq:
						result.append(voxel)

	return result


## Apply damage to voxels in radius.
func damage_voxels_in_radius(center: Vector3, radius: float, damage: float) -> int:
	var voxels := get_voxels_in_radius(center, radius)
	var destroyed := 0

	for voxel in voxels:
		var dist := Vector3(voxel.grid_x, voxel.grid_y, voxel.grid_z).distance_to(center)
		var falloff := 1.0 - (dist / radius)
		var actual_damage := damage * maxf(0.0, falloff)

		if voxel.apply_damage(actual_damage):
			destroyed += 1
			# Remove destroyed voxels
			_voxel_grid.erase(voxel.get_position())
			_voxel_count -= 1

	return destroyed


## Get height map.
func get_height_map() -> Array:
	return _height_map


## Get voxel grid.
func get_voxel_grid() -> Dictionary:
	return _voxel_grid


## Get statistics.
func get_statistics() -> Dictionary:
	var power_count := 0
	var industrial_count := 0
	var structural_count := 0

	for pos in _voxel_grid:
		var voxel: VoxelState = _voxel_grid[pos]
		if voxel.is_power_node:
			power_count += 1
		if voxel.is_industrial:
			industrial_count += 1
		if voxel.is_structural:
			structural_count += 1

	return {
		"grid_size": GRID_SIZE,
		"max_height": MAX_HEIGHT,
		"voxel_count": _voxel_count,
		"building_count": _building_count,
		"power_node_count": power_count,
		"industrial_count": industrial_count,
		"structural_count": structural_count
	}


## Serialize voxel grid (only damaged voxels for efficiency).
func serialize_damaged_voxels() -> Array:
	var result := []

	for pos in _voxel_grid:
		var voxel: VoxelState = _voxel_grid[pos]
		if voxel.is_damaged():
			result.append(voxel.to_dict())

	return result


## Deserialize and apply damaged voxel states.
func deserialize_damaged_voxels(data: Array) -> void:
	for voxel_data in data:
		var pos_data: Dictionary = voxel_data.get("position", {})
		var pos := Vector3i(
			pos_data.get("x", 0),
			pos_data.get("y", 0),
			pos_data.get("z", 0)
		)

		var voxel := _voxel_grid.get(pos)
		if voxel != null:
			voxel.from_dict(voxel_data)
		elif voxel_data.get("is_occupied", false):
			# Recreate destroyed voxel
			var new_voxel := VoxelState.new()
			new_voxel.from_dict(voxel_data)
			_voxel_grid[pos] = new_voxel


## Clear voxel grid.
func clear() -> void:
	_voxel_grid.clear()
	_height_map.clear()
	_voxel_count = 0
	_building_count = 0
