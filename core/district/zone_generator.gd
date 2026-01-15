class_name ZoneGenerator
extends RefCounted
## ZoneGenerator creates the macro zone layout for the city.
## Generates 16x16 zone grid with faction-specific areas and strategic chokepoints.

signal generation_started()
signal zone_placed(x: int, y: int, zone_type: int)
signal generation_completed()

## Grid dimensions
const ZONE_GRID_SIZE := 16
const VOXELS_PER_ZONE := 32
const TOTAL_VOXEL_SIZE := 512  ## 16 * 32

## Zone types
enum ZoneType {
	POWER_HUB,
	INDUSTRIAL,
	ZERG_ALLEY,
	TANK_BOULEVARD,
	RESIDENTIAL,
	COMMERCIAL,
	PARK,
	MIXED
}

## Faction affinity
enum FactionAffinity {
	NEUTRAL,
	ZERG,      ## Aether Swarm, OptiForge
	TANK,      ## Dynapods, LogiBots
	MIXED
}

## Zone distribution in center (percentages)
const CENTER_DISTRIBUTION := {
	ZoneType.ZERG_ALLEY: 0.30,
	ZoneType.TANK_BOULEVARD: 0.30,
	ZoneType.RESIDENTIAL: 0.20,
	ZoneType.COMMERCIAL: 0.20
}

## Density range
const MIN_DENSITY := 0.4
const MAX_DENSITY := 0.9

## RNG
var _rng: RandomNumberGenerator = null

## Generated data
var _zone_grid: Array = []        ## 2D array of ZoneType
var _density_grid: Array = []     ## 2D array of float
var _affinity_grid: Array = []    ## 2D array of FactionAffinity


func _init() -> void:
	_rng = RandomNumberGenerator.new()


## Generate zone layout.
func generate_zone_layout(seed: int = 0) -> Dictionary:
	_rng.seed = seed if seed != 0 else Time.get_ticks_msec()

	generation_started.emit()

	_initialize_grids()
	_place_power_hubs()
	_place_edge_zones()
	_place_center_zones()
	_assign_densities()
	_assign_faction_affinities()

	generation_completed.emit()

	return {
		"zones": _zone_grid,
		"densities": _density_grid,
		"affinities": _affinity_grid
	}


## Initialize empty grids.
func _initialize_grids() -> void:
	_zone_grid = []
	_density_grid = []
	_affinity_grid = []

	for x in ZONE_GRID_SIZE:
		var zone_row := []
		var density_row := []
		var affinity_row := []

		for y in ZONE_GRID_SIZE:
			zone_row.append(ZoneType.MIXED)
			density_row.append(0.5)
			affinity_row.append(FactionAffinity.NEUTRAL)

		_zone_grid.append(zone_row)
		_density_grid.append(density_row)
		_affinity_grid.append(affinity_row)


## Place power hubs at corners.
func _place_power_hubs() -> void:
	# Four corners (1 cell inward from edges)
	var corners := [
		Vector2i(1, 1),
		Vector2i(14, 1),
		Vector2i(1, 14),
		Vector2i(14, 14)
	]

	for corner in corners:
		_zone_grid[corner.x][corner.y] = ZoneType.POWER_HUB
		zone_placed.emit(corner.x, corner.y, ZoneType.POWER_HUB)


## Place edge zones (industrial).
func _place_edge_zones() -> void:
	for x in ZONE_GRID_SIZE:
		for y in ZONE_GRID_SIZE:
			# Skip corners (already placed)
			if _zone_grid[x][y] == ZoneType.POWER_HUB:
				continue

			# Edge cells become industrial
			if x == 0 or x == ZONE_GRID_SIZE - 1 or y == 0 or y == ZONE_GRID_SIZE - 1:
				_zone_grid[x][y] = ZoneType.INDUSTRIAL
				zone_placed.emit(x, y, ZoneType.INDUSTRIAL)

			# Second row from edge also has industrial tendency
			elif x == 1 or x == ZONE_GRID_SIZE - 2 or y == 1 or y == ZONE_GRID_SIZE - 2:
				if _rng.randf() < 0.6:  ## 60% chance industrial
					_zone_grid[x][y] = ZoneType.INDUSTRIAL
					zone_placed.emit(x, y, ZoneType.INDUSTRIAL)


## Place center zones with distribution.
func _place_center_zones() -> void:
	# Build list of center cells to assign
	var center_cells: Array[Vector2i] = []

	for x in range(2, ZONE_GRID_SIZE - 2):
		for y in range(2, ZONE_GRID_SIZE - 2):
			if _zone_grid[x][y] == ZoneType.MIXED:  ## Not yet assigned
				center_cells.append(Vector2i(x, y))

	# Shuffle cells
	center_cells.shuffle()

	# Calculate zone counts based on distribution
	var total_cells := center_cells.size()
	var zone_counts := {}
	var assigned := 0

	for zone_type in CENTER_DISTRIBUTION:
		var count := int(total_cells * CENTER_DISTRIBUTION[zone_type])
		zone_counts[zone_type] = count
		assigned += count

	# Assign remaining to mixed
	zone_counts[ZoneType.MIXED] = total_cells - assigned

	# Assign zones to cells
	var cell_idx := 0
	for zone_type in zone_counts:
		var count: int = zone_counts[zone_type]
		for i in count:
			if cell_idx >= center_cells.size():
				break
			var cell := center_cells[cell_idx]
			_zone_grid[cell.x][cell.y] = zone_type
			zone_placed.emit(cell.x, cell.y, zone_type)
			cell_idx += 1


## Assign densities to zones.
func _assign_densities() -> void:
	for x in ZONE_GRID_SIZE:
		for y in ZONE_GRID_SIZE:
			var zone_type: ZoneType = _zone_grid[x][y]

			# Base density by zone type
			var base_density := 0.6
			match zone_type:
				ZoneType.POWER_HUB:
					base_density = 0.9
				ZoneType.INDUSTRIAL:
					base_density = 0.7
				ZoneType.ZERG_ALLEY:
					base_density = 0.85  ## High density for swarms
				ZoneType.TANK_BOULEVARD:
					base_density = 0.5   ## Low density, wide streets
				ZoneType.RESIDENTIAL:
					base_density = 0.65
				ZoneType.COMMERCIAL:
					base_density = 0.7
				ZoneType.PARK:
					base_density = 0.3
				ZoneType.MIXED:
					base_density = 0.6

			# Add random variance
			var variance := _rng.randf_range(-0.15, 0.15)
			_density_grid[x][y] = clampf(base_density + variance, MIN_DENSITY, MAX_DENSITY)


## Assign faction affinities.
func _assign_faction_affinities() -> void:
	for x in ZONE_GRID_SIZE:
		for y in ZONE_GRID_SIZE:
			var zone_type: ZoneType = _zone_grid[x][y]

			match zone_type:
				ZoneType.ZERG_ALLEY:
					_affinity_grid[x][y] = FactionAffinity.ZERG
				ZoneType.TANK_BOULEVARD:
					_affinity_grid[x][y] = FactionAffinity.TANK
				ZoneType.MIXED, ZoneType.RESIDENTIAL, ZoneType.COMMERCIAL:
					_affinity_grid[x][y] = FactionAffinity.MIXED
				_:
					_affinity_grid[x][y] = FactionAffinity.NEUTRAL


## Get zone at grid position.
func get_zone_at(x: int, y: int) -> ZoneType:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return ZoneType.MIXED
	return _zone_grid[x][y]


## Get density at grid position.
func get_density_at(x: int, y: int) -> float:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return 0.5
	return _density_grid[x][y]


## Get affinity at grid position.
func get_affinity_at(x: int, y: int) -> FactionAffinity:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return FactionAffinity.NEUTRAL
	return _affinity_grid[x][y]


## Convert voxel coordinates to zone coordinates.
func voxel_to_zone(voxel_x: int, voxel_y: int) -> Vector2i:
	return Vector2i(
		clampi(voxel_x / VOXELS_PER_ZONE, 0, ZONE_GRID_SIZE - 1),
		clampi(voxel_y / VOXELS_PER_ZONE, 0, ZONE_GRID_SIZE - 1)
	)


## Convert zone coordinates to voxel coordinates (center of zone).
func zone_to_voxel(zone_x: int, zone_y: int) -> Vector2i:
	return Vector2i(
		zone_x * VOXELS_PER_ZONE + VOXELS_PER_ZONE / 2,
		zone_y * VOXELS_PER_ZONE + VOXELS_PER_ZONE / 2
	)


## Get zone type name.
static func get_zone_name(zone_type: ZoneType) -> String:
	match zone_type:
		ZoneType.POWER_HUB: return "Power Hub"
		ZoneType.INDUSTRIAL: return "Industrial"
		ZoneType.ZERG_ALLEY: return "Zerg Alley"
		ZoneType.TANK_BOULEVARD: return "Tank Boulevard"
		ZoneType.RESIDENTIAL: return "Residential"
		ZoneType.COMMERCIAL: return "Commercial"
		ZoneType.PARK: return "Park"
		ZoneType.MIXED: return "Mixed"
	return "Unknown"


## Get zones of specific type.
func get_zones_of_type(zone_type: ZoneType) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in ZONE_GRID_SIZE:
		for y in ZONE_GRID_SIZE:
			if _zone_grid[x][y] == zone_type:
				result.append(Vector2i(x, y))
	return result


## Get zone grid.
func get_zone_grid() -> Array:
	return _zone_grid


## Get density grid.
func get_density_grid() -> Array:
	return _density_grid


## Get statistics.
func get_statistics() -> Dictionary:
	var type_counts := {}
	for zt in ZoneType.values():
		type_counts[zt] = 0

	for x in ZONE_GRID_SIZE:
		for y in ZONE_GRID_SIZE:
			type_counts[_zone_grid[x][y]] += 1

	return {
		"grid_size": ZONE_GRID_SIZE,
		"total_zones": ZONE_GRID_SIZE * ZONE_GRID_SIZE,
		"zone_counts": type_counts
	}
