class_name CityLayout
extends RefCounted
## CityLayout stores all generated city data for game systems.
## Supports serialization for persistence and multiplayer synchronization.

## Grid dimensions
const ZONE_GRID_SIZE := 16
const BUILDING_GRID_SIZE := 512

## Zone data (from ZoneGenerator)
var zone_grid: Array = []           ## 16x16 zone types
var density_grid: Array = []        ## 16x16 density values
var affinity_grid: Array = []       ## 16x16 faction affinities

## Power data (from PowerGridGenerator)
var power_grid: Array = []          ## 16x16 power types
var power_output: Array = []        ## 16x16 power output values
var power_connections: Array = []   ## Connection paths
var reactor_positions: Array = []
var substation_positions: Array = []
var solar_positions: Array = []

## Building data (from WFCBuildingPlacer)
var building_grid: Array = []       ## 512x512 building types

## Resource data (reserved for resource placement phase)
var resource_positions: Array = []  ## Array of {position, type, amount}

## Generation metadata
var generation_seed: int = 0
var generation_time_ms: float = 0.0
var generation_version: String = "1.0"


func _init() -> void:
	pass


## Check if layout is valid.
func is_valid() -> bool:
	return not zone_grid.is_empty() and not building_grid.is_empty()


## Get zone at grid position.
func get_zone_at(x: int, y: int) -> int:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return 0
	if zone_grid.is_empty() or x >= zone_grid.size():
		return 0
	if y >= zone_grid[x].size():
		return 0
	return zone_grid[x][y]


## Get building at position.
func get_building_at(x: int, y: int) -> int:
	if x < 0 or x >= BUILDING_GRID_SIZE or y < 0 or y >= BUILDING_GRID_SIZE:
		return 0
	if building_grid.is_empty() or x >= building_grid.size():
		return 0
	if y >= building_grid[x].size():
		return 0
	return building_grid[x][y]


## Get power type at zone position.
func get_power_at(x: int, y: int) -> int:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return 0
	if power_grid.is_empty() or x >= power_grid.size():
		return 0
	if y >= power_grid[x].size():
		return 0
	return power_grid[x][y]


## Serialize building grid using run-length encoding.
func serialize_building_grid() -> PackedByteArray:
	if building_grid.is_empty():
		return PackedByteArray()

	var encoded := PackedByteArray()

	# Flatten grid for RLE
	var flat: Array[int] = []
	for x in BUILDING_GRID_SIZE:
		if x >= building_grid.size():
			for y in BUILDING_GRID_SIZE:
				flat.append(0)
		else:
			for y in BUILDING_GRID_SIZE:
				if y >= building_grid[x].size():
					flat.append(0)
				else:
					flat.append(building_grid[x][y])

	# Run-length encode
	var i := 0
	while i < flat.size():
		var value: int = flat[i]
		var run_length := 1

		# Count consecutive same values (max 255)
		while i + run_length < flat.size() and flat[i + run_length] == value and run_length < 255:
			run_length += 1

		# Store: [value, run_length]
		encoded.append(value)
		encoded.append(run_length)

		i += run_length

	return encoded


## Deserialize building grid from run-length encoded data.
func deserialize_building_grid(data: PackedByteArray) -> void:
	if data.is_empty():
		return

	# Decode RLE
	var flat: Array[int] = []
	var i := 0

	while i + 1 < data.size():
		var value: int = data[i]
		var run_length: int = data[i + 1]

		for j in run_length:
			flat.append(value)

		i += 2

	# Reconstruct 2D grid
	building_grid = []
	var flat_idx := 0

	for x in BUILDING_GRID_SIZE:
		var row := []
		for y in BUILDING_GRID_SIZE:
			if flat_idx < flat.size():
				row.append(flat[flat_idx])
				flat_idx += 1
			else:
				row.append(0)
		building_grid.append(row)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"version": generation_version,
		"seed": generation_seed,
		"generation_time_ms": generation_time_ms,
		"zone_grid": zone_grid.duplicate(true),
		"density_grid": density_grid.duplicate(true),
		"affinity_grid": affinity_grid.duplicate(true),
		"power_grid": power_grid.duplicate(true),
		"power_output": power_output.duplicate(true),
		"power_connections": power_connections.duplicate(true),
		"reactor_positions": _serialize_vector_array(reactor_positions),
		"substation_positions": _serialize_vector_array(substation_positions),
		"solar_positions": _serialize_vector_array(solar_positions),
		"building_grid_rle": Marshalls.raw_to_base64(serialize_building_grid()),
		"resource_positions": resource_positions.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	generation_version = data.get("version", "1.0")
	generation_seed = data.get("seed", 0)
	generation_time_ms = data.get("generation_time_ms", 0.0)

	zone_grid = data.get("zone_grid", []).duplicate(true)
	density_grid = data.get("density_grid", []).duplicate(true)
	affinity_grid = data.get("affinity_grid", []).duplicate(true)

	power_grid = data.get("power_grid", []).duplicate(true)
	power_output = data.get("power_output", []).duplicate(true)
	power_connections = data.get("power_connections", []).duplicate(true)

	reactor_positions = _deserialize_vector_array(data.get("reactor_positions", []))
	substation_positions = _deserialize_vector_array(data.get("substation_positions", []))
	solar_positions = _deserialize_vector_array(data.get("solar_positions", []))

	# Decode building grid from RLE
	var rle_data: String = data.get("building_grid_rle", "")
	if not rle_data.is_empty():
		deserialize_building_grid(Marshalls.base64_to_raw(rle_data))
	else:
		building_grid = data.get("building_grid", []).duplicate(true)

	resource_positions = data.get("resource_positions", []).duplicate(true)


## Serialize Vector2i array to plain arrays.
func _serialize_vector_array(vectors: Array) -> Array:
	var result := []
	for v in vectors:
		if v is Vector2i:
			result.append({"x": v.x, "y": v.y})
		elif v is Dictionary:
			result.append(v)
	return result


## Deserialize Vector2i array from plain arrays.
func _deserialize_vector_array(data: Array) -> Array:
	var result := []
	for item in data:
		if item is Dictionary:
			result.append(Vector2i(item.get("x", 0), item.get("y", 0)))
	return result


## Get statistics.
func get_statistics() -> Dictionary:
	var zone_counts := {}
	for x in zone_grid.size():
		for y in zone_grid[x].size():
			var zone_type: int = zone_grid[x][y]
			zone_counts[zone_type] = zone_counts.get(zone_type, 0) + 1

	var building_counts := {}
	for x in building_grid.size():
		for y in building_grid[x].size():
			var building_type: int = building_grid[x][y]
			building_counts[building_type] = building_counts.get(building_type, 0) + 1

	return {
		"seed": generation_seed,
		"generation_time_ms": generation_time_ms,
		"zone_grid_size": zone_grid.size(),
		"building_grid_size": building_grid.size(),
		"zone_counts": zone_counts,
		"building_counts": building_counts,
		"reactor_count": reactor_positions.size(),
		"substation_count": substation_positions.size(),
		"solar_count": solar_positions.size(),
		"resource_count": resource_positions.size()
	}


## Create from generation results.
static func create_from_generation(zone_result: Dictionary, power_result: Dictionary,
								   building_result: Array, seed_value: int,
								   time_ms: float) -> CityLayout:
	var layout := CityLayout.new()

	layout.generation_seed = seed_value
	layout.generation_time_ms = time_ms

	# Zone data
	layout.zone_grid = zone_result.get("zones", []).duplicate(true)
	layout.density_grid = zone_result.get("densities", []).duplicate(true)
	layout.affinity_grid = zone_result.get("affinities", []).duplicate(true)

	# Power data
	layout.power_grid = power_result.get("power_grid", []).duplicate(true)
	layout.power_output = power_result.get("power_output", []).duplicate(true)
	layout.power_connections = power_result.get("connections", []).duplicate(true)
	layout.reactor_positions = power_result.get("reactors", []).duplicate()
	layout.substation_positions = power_result.get("substations", []).duplicate()
	layout.solar_positions = power_result.get("solar_panels", []).duplicate()

	# Building data
	layout.building_grid = building_result.duplicate(true)

	return layout
