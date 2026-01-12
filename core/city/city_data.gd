class_name CityData
extends RefCounted
## CityData stores the generated city layout and metadata.
## Provides efficient access to tile data, walkability, and strategic areas.

## City dimensions (voxels)
var width: int = 0
var height: int = 0

## Seed used for generation
var seed: int = 0

## Tile grid (flattened 2D array of tile IDs)
var _tiles: PackedStringArray = PackedStringArray()

## Walkability grid (flattened 2D array)
var _walkability: PackedFloat32Array = PackedFloat32Array()

## Height grid (flattened 2D array)
var _heights: PackedByteArray = PackedByteArray()

## Area tiles (area_type -> Array of Vector2i)
var _area_tiles: Dictionary = {}

## Strategic areas (area_type -> Array of Rect2i)
var _strategic_areas: Dictionary = {}

## Faction affinities per area (area_key -> {faction -> value})
var _faction_affinities: Dictionary = {}

## Resource locations (Array of {type, position})
var resource_nodes: Array[Dictionary] = []

## Building data (position -> {type, height})
var buildings: Dictionary = {}


func _init() -> void:
	pass


## Initialize city data with dimensions.
func initialize(p_width: int, p_height: int, p_seed: int = 0) -> void:
	width = p_width
	height = p_height
	seed = p_seed

	var size := width * height
	_tiles.resize(size)
	_walkability.resize(size)
	_heights.resize(size)

	# Initialize with defaults
	for i in size:
		_tiles[i] = ""
		_walkability[i] = 1.0
		_heights[i] = 0


## Get index from coordinates.
func _get_index(x: int, y: int) -> int:
	if x < 0 or x >= width or y < 0 or y >= height:
		return -1
	return y * width + x


## Set tile at position.
func set_tile(x: int, y: int, tile_id: String) -> void:
	var idx := _get_index(x, y)
	if idx >= 0:
		_tiles[idx] = tile_id


## Get tile at position.
func get_tile(x: int, y: int) -> String:
	var idx := _get_index(x, y)
	if idx < 0:
		return ""
	return _tiles[idx]


## Set walkability at position.
func set_walkability(x: int, y: int, value: float) -> void:
	var idx := _get_index(x, y)
	if idx >= 0:
		_walkability[idx] = clampf(value, 0.0, 1.0)


## Get walkability at position.
func get_walkability(x: int, y: int) -> float:
	var idx := _get_index(x, y)
	if idx < 0:
		return 0.0
	return _walkability[idx]


## Set height at position.
func set_height(x: int, y: int, value: int) -> void:
	var idx := _get_index(x, y)
	if idx >= 0:
		_heights[idx] = clampi(value, 0, 255)


## Get height at position.
func get_height(x: int, y: int) -> int:
	var idx := _get_index(x, y)
	if idx < 0:
		return 0
	return _heights[idx]


## Add tile to area classification.
func add_area_tile(area_type: String, tile_pos: Vector2i) -> void:
	if not _area_tiles.has(area_type):
		_area_tiles[area_type] = []
	_area_tiles[area_type].append(tile_pos)


## Get tiles of specific area type.
func get_area_tiles(area_type: String) -> Array:
	return _area_tiles.get(area_type, [])


## Add strategic area.
func add_strategic_area(area_type: String, bounds: Rect2i) -> void:
	if not _strategic_areas.has(area_type):
		_strategic_areas[area_type] = []
	_strategic_areas[area_type].append(bounds)


## Get strategic areas by type.
func get_strategic_areas(area_type: String) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for bounds in _strategic_areas.get(area_type, []):
		result.append(bounds)
	return result


## Get all strategic area types.
func get_area_types() -> Array:
	return _strategic_areas.keys()


## Set faction affinity for area.
func set_faction_affinity(x: int, y: int, faction: String, value: float) -> void:
	var key := str(x) + "," + str(y)
	if not _faction_affinities.has(key):
		_faction_affinities[key] = {}
	_faction_affinities[key][faction] = clampf(value, 0.0, 2.0)


## Get faction affinity at position.
func get_faction_affinity(x: int, y: int, faction: String) -> float:
	var key := str(x) + "," + str(y)
	if not _faction_affinities.has(key):
		return 1.0
	return _faction_affinities[key].get(faction, 1.0)


## Add resource node.
func add_resource_node(resource_type: String, position: Vector2i) -> void:
	resource_nodes.append({
		"type": resource_type,
		"position": position
	})


## Get resource nodes by type.
func get_resource_nodes(resource_type: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in resource_nodes:
		if resource_type.is_empty() or node["type"] == resource_type:
			result.append(node)
	return result


## Add building.
func add_building(x: int, y: int, building_type: String, building_height: int) -> void:
	var key := str(x) + "," + str(y)
	buildings[key] = {
		"type": building_type,
		"height": building_height,
		"position": Vector2i(x, y)
	}


## Get building at position.
func get_building(x: int, y: int) -> Dictionary:
	var key := str(x) + "," + str(y)
	return buildings.get(key, {})


## Check if position is walkable.
func is_walkable(x: int, y: int) -> bool:
	return get_walkability(x, y) > 0.5


## Check if position is blocked.
func is_blocked(x: int, y: int) -> bool:
	return get_walkability(x, y) <= 0.0


## Find nearest walkable position.
func find_nearest_walkable(x: int, y: int, max_radius: int = 10) -> Vector2i:
	if is_walkable(x, y):
		return Vector2i(x, y)

	for radius in range(1, max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absf(dx) == radius or absf(dy) == radius:
					var nx := x + dx
					var ny := y + dy
					if is_walkable(nx, ny):
						return Vector2i(nx, ny)

	return Vector2i(-1, -1)


## Get memory usage estimate (bytes).
func get_memory_usage() -> int:
	var size := 0

	# Arrays
	size += _tiles.size() * 32  # Estimate for strings
	size += _walkability.size() * 4
	size += _heights.size()

	# Dictionaries (rough estimate)
	size += _area_tiles.size() * 100
	size += _strategic_areas.size() * 100
	size += _faction_affinities.size() * 50
	size += resource_nodes.size() * 50
	size += buildings.size() * 100

	return size


## Serialize to dictionary.
func to_dict() -> Dictionary:
	# Convert PackedArrays to regular arrays for serialization
	var tiles_arr: Array = []
	for tile in _tiles:
		tiles_arr.append(tile)

	var walk_arr: Array = []
	for w in _walkability:
		walk_arr.append(w)

	var height_arr: Array = []
	for h in _heights:
		height_arr.append(h)

	# Convert strategic areas
	var areas_data: Dictionary = {}
	for area_type in _strategic_areas:
		areas_data[area_type] = []
		for bounds in _strategic_areas[area_type]:
			areas_data[area_type].append({
				"x": bounds.position.x,
				"y": bounds.position.y,
				"w": bounds.size.x,
				"h": bounds.size.y
			})

	# Convert area tiles
	var area_tiles_data: Dictionary = {}
	for area_type in _area_tiles:
		area_tiles_data[area_type] = []
		for pos in _area_tiles[area_type]:
			area_tiles_data[area_type].append({"x": pos.x, "y": pos.y})

	# Convert resource nodes
	var nodes_data: Array = []
	for node in resource_nodes:
		nodes_data.append({
			"type": node["type"],
			"x": node["position"].x,
			"y": node["position"].y
		})

	return {
		"width": width,
		"height": height,
		"seed": seed,
		"tiles": tiles_arr,
		"walkability": walk_arr,
		"heights": height_arr,
		"area_tiles": area_tiles_data,
		"strategic_areas": areas_data,
		"faction_affinities": _faction_affinities.duplicate(true),
		"resource_nodes": nodes_data,
		"buildings": buildings.duplicate(true)
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> CityData:
	var city := CityData.new()
	city.width = data.get("width", 0)
	city.height = data.get("height", 0)
	city.seed = data.get("seed", 0)

	# Restore tiles
	city._tiles.clear()
	for tile in data.get("tiles", []):
		city._tiles.append(tile)

	# Restore walkability
	city._walkability.clear()
	for w in data.get("walkability", []):
		city._walkability.append(float(w))

	# Restore heights
	city._heights.clear()
	for h in data.get("heights", []):
		city._heights.append(int(h))

	# Restore area tiles
	city._area_tiles.clear()
	for area_type in data.get("area_tiles", {}):
		city._area_tiles[area_type] = []
		for pos_data in data["area_tiles"][area_type]:
			city._area_tiles[area_type].append(Vector2i(pos_data["x"], pos_data["y"]))

	# Restore strategic areas
	city._strategic_areas.clear()
	for area_type in data.get("strategic_areas", {}):
		city._strategic_areas[area_type] = []
		for bounds_data in data["strategic_areas"][area_type]:
			city._strategic_areas[area_type].append(Rect2i(
				bounds_data["x"],
				bounds_data["y"],
				bounds_data["w"],
				bounds_data["h"]
			))

	# Restore faction affinities
	city._faction_affinities = data.get("faction_affinities", {}).duplicate(true)

	# Restore resource nodes
	city.resource_nodes.clear()
	for node_data in data.get("resource_nodes", []):
		city.resource_nodes.append({
			"type": node_data["type"],
			"position": Vector2i(node_data["x"], node_data["y"])
		})

	# Restore buildings
	city.buildings = data.get("buildings", {}).duplicate(true)

	return city


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"size": "%dx%d" % [width, height],
		"seed": seed,
		"area_types": get_area_types(),
		"resource_nodes": resource_nodes.size(),
		"buildings": buildings.size(),
		"memory_kb": "%.1f KB" % (get_memory_usage() / 1024.0)
	}
