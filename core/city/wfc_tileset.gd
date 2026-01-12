class_name WFCTileset
extends RefCounted
## WFCTileset contains all tile types and manages adjacency rules.
## Provides city-specific tile presets for urban generation.

## All registered tiles (id -> WFCTile)
var tiles: Dictionary = {}

## Socket compatibility cache (socket_id -> Array of tile_ids)
var _socket_cache: Dictionary = {}

## Total weight of all tiles
var _total_weight: float = 0.0


func _init() -> void:
	pass


## Register a tile.
func register_tile(tile: WFCTile) -> void:
	if tile == null or tile.id.is_empty():
		return

	tiles[tile.id] = tile
	_invalidate_cache()


## Get tile by ID.
func get_tile(id: String) -> WFCTile:
	return tiles.get(id)


## Get all tile IDs.
func get_tile_ids() -> Array:
	return tiles.keys()


## Get tiles compatible with socket on given direction.
func get_compatible_tiles(direction: int, socket_id: String) -> Array[String]:
	var opposite := WFCTile.get_opposite_direction(direction)
	var cache_key := str(opposite) + "_" + socket_id

	if _socket_cache.has(cache_key):
		return _socket_cache[cache_key]

	var compatible: Array[String] = []
	for tile_id in tiles:
		var tile: WFCTile = tiles[tile_id]
		if tile.get_socket(opposite) == socket_id:
			compatible.append(tile_id)

	_socket_cache[cache_key] = compatible
	return compatible


## Get total weight.
func get_total_weight() -> float:
	if _total_weight <= 0:
		_total_weight = 0.0
		for tile_id in tiles:
			_total_weight += tiles[tile_id].weight
	return _total_weight


## Invalidate cache.
func _invalidate_cache() -> void:
	_socket_cache.clear()
	_total_weight = 0.0


## Create default urban tileset.
static func create_urban_tileset() -> WFCTileset:
	var tileset := WFCTileset.new()

	# Road tiles
	var road_straight := WFCTile.new("road_ns", "Road N-S")
	road_straight.area_type = "road"
	road_straight.walkability = 1.0
	road_straight.weight = 3.0
	road_straight.set_socket(WFCTile.Direction.NORTH, "road")
	road_straight.set_socket(WFCTile.Direction.SOUTH, "road")
	road_straight.set_socket(WFCTile.Direction.EAST, "building")
	road_straight.set_socket(WFCTile.Direction.WEST, "building")
	road_straight.set_affinity("vehicles", 1.5)
	tileset.register_tile(road_straight)

	var road_ew := WFCTile.new("road_ew", "Road E-W")
	road_ew.area_type = "road"
	road_ew.walkability = 1.0
	road_ew.weight = 3.0
	road_ew.set_socket(WFCTile.Direction.NORTH, "building")
	road_ew.set_socket(WFCTile.Direction.SOUTH, "building")
	road_ew.set_socket(WFCTile.Direction.EAST, "road")
	road_ew.set_socket(WFCTile.Direction.WEST, "road")
	road_ew.set_affinity("vehicles", 1.5)
	tileset.register_tile(road_ew)

	var road_cross := WFCTile.new("road_cross", "Crossroad")
	road_cross.area_type = "road"
	road_cross.walkability = 1.0
	road_cross.weight = 1.0
	road_cross.set_all_sockets("road")
	road_cross.set_affinity("vehicles", 1.5)
	tileset.register_tile(road_cross)

	# T-junctions
	var road_t_north := WFCTile.new("road_t_n", "T-Junction North")
	road_t_north.area_type = "road"
	road_t_north.walkability = 1.0
	road_t_north.weight = 1.5
	road_t_north.set_socket(WFCTile.Direction.NORTH, "building")
	road_t_north.set_socket(WFCTile.Direction.SOUTH, "road")
	road_t_north.set_socket(WFCTile.Direction.EAST, "road")
	road_t_north.set_socket(WFCTile.Direction.WEST, "road")
	tileset.register_tile(road_t_north)

	var road_t_south := WFCTile.new("road_t_s", "T-Junction South")
	road_t_south.area_type = "road"
	road_t_south.walkability = 1.0
	road_t_south.weight = 1.5
	road_t_south.set_socket(WFCTile.Direction.NORTH, "road")
	road_t_south.set_socket(WFCTile.Direction.SOUTH, "building")
	road_t_south.set_socket(WFCTile.Direction.EAST, "road")
	road_t_south.set_socket(WFCTile.Direction.WEST, "road")
	tileset.register_tile(road_t_south)

	var road_t_east := WFCTile.new("road_t_e", "T-Junction East")
	road_t_east.area_type = "road"
	road_t_east.walkability = 1.0
	road_t_east.weight = 1.5
	road_t_east.set_socket(WFCTile.Direction.NORTH, "road")
	road_t_east.set_socket(WFCTile.Direction.SOUTH, "road")
	road_t_east.set_socket(WFCTile.Direction.EAST, "building")
	road_t_east.set_socket(WFCTile.Direction.WEST, "road")
	tileset.register_tile(road_t_east)

	var road_t_west := WFCTile.new("road_t_w", "T-Junction West")
	road_t_west.area_type = "road"
	road_t_west.walkability = 1.0
	road_t_west.weight = 1.5
	road_t_west.set_socket(WFCTile.Direction.NORTH, "road")
	road_t_west.set_socket(WFCTile.Direction.SOUTH, "road")
	road_t_west.set_socket(WFCTile.Direction.EAST, "road")
	road_t_west.set_socket(WFCTile.Direction.WEST, "building")
	tileset.register_tile(road_t_west)

	# Building tiles
	var building_small := WFCTile.new("building_small", "Small Building")
	building_small.area_type = "building"
	building_small.walkability = 0.0
	building_small.height = 2
	building_small.weight = 5.0
	building_small.set_all_sockets("building")
	tileset.register_tile(building_small)

	var building_medium := WFCTile.new("building_medium", "Medium Building")
	building_medium.area_type = "building"
	building_medium.walkability = 0.0
	building_medium.height = 4
	building_medium.weight = 3.0
	building_medium.set_all_sockets("building")
	tileset.register_tile(building_medium)

	var building_tall := WFCTile.new("building_tall", "Tall Building")
	building_tall.area_type = "building"
	building_tall.walkability = 0.0
	building_tall.height = 8
	building_tall.weight = 1.0
	building_tall.set_all_sockets("building")
	tileset.register_tile(building_tall)

	# Alley tiles (zerg-friendly)
	var alley_ns := WFCTile.new("alley_ns", "Alley N-S")
	alley_ns.area_type = "alley"
	alley_ns.walkability = 0.8
	alley_ns.weight = 2.0
	alley_ns.set_socket(WFCTile.Direction.NORTH, "alley")
	alley_ns.set_socket(WFCTile.Direction.SOUTH, "alley")
	alley_ns.set_socket(WFCTile.Direction.EAST, "building")
	alley_ns.set_socket(WFCTile.Direction.WEST, "building")
	alley_ns.set_affinity("swarm", 1.8)
	alley_ns.set_affinity("vehicles", 0.3)
	tileset.register_tile(alley_ns)

	var alley_ew := WFCTile.new("alley_ew", "Alley E-W")
	alley_ew.area_type = "alley"
	alley_ew.walkability = 0.8
	alley_ew.weight = 2.0
	alley_ew.set_socket(WFCTile.Direction.NORTH, "building")
	alley_ew.set_socket(WFCTile.Direction.SOUTH, "building")
	alley_ew.set_socket(WFCTile.Direction.EAST, "alley")
	alley_ew.set_socket(WFCTile.Direction.WEST, "alley")
	alley_ew.set_affinity("swarm", 1.8)
	alley_ew.set_affinity("vehicles", 0.3)
	tileset.register_tile(alley_ew)

	# Boulevard tiles (tank-friendly)
	var boulevard_ns := WFCTile.new("boulevard_ns", "Boulevard N-S")
	boulevard_ns.area_type = "boulevard"
	boulevard_ns.walkability = 1.0
	boulevard_ns.weight = 1.5
	boulevard_ns.set_socket(WFCTile.Direction.NORTH, "boulevard")
	boulevard_ns.set_socket(WFCTile.Direction.SOUTH, "boulevard")
	boulevard_ns.set_socket(WFCTile.Direction.EAST, "building")
	boulevard_ns.set_socket(WFCTile.Direction.WEST, "building")
	boulevard_ns.set_affinity("heavy", 2.0)
	boulevard_ns.set_affinity("swarm", 0.5)
	tileset.register_tile(boulevard_ns)

	var boulevard_ew := WFCTile.new("boulevard_ew", "Boulevard E-W")
	boulevard_ew.area_type = "boulevard"
	boulevard_ew.walkability = 1.0
	boulevard_ew.weight = 1.5
	boulevard_ew.set_socket(WFCTile.Direction.NORTH, "building")
	boulevard_ew.set_socket(WFCTile.Direction.SOUTH, "building")
	boulevard_ew.set_socket(WFCTile.Direction.EAST, "boulevard")
	boulevard_ew.set_socket(WFCTile.Direction.WEST, "boulevard")
	boulevard_ew.set_affinity("heavy", 2.0)
	boulevard_ew.set_affinity("swarm", 0.5)
	tileset.register_tile(boulevard_ew)

	# Open area / plaza
	var plaza := WFCTile.new("plaza", "Plaza")
	plaza.area_type = "open"
	plaza.walkability = 1.0
	plaza.weight = 1.0
	plaza.set_all_sockets("open")
	plaza.set_affinity("ranged", 1.5)
	tileset.register_tile(plaza)

	# REE node area
	var ree_area := WFCTile.new("ree_area", "REE Node Area")
	ree_area.area_type = "resource"
	ree_area.walkability = 0.9
	ree_area.weight = 0.5
	ree_area.set_all_sockets("open")
	ree_area.metadata["resource_type"] = "ree"
	tileset.register_tile(ree_area)

	# Transition tiles (road to alley)
	var road_alley_n := WFCTile.new("road_alley_n", "Road-Alley N")
	road_alley_n.area_type = "transition"
	road_alley_n.walkability = 0.9
	road_alley_n.weight = 1.0
	road_alley_n.set_socket(WFCTile.Direction.NORTH, "alley")
	road_alley_n.set_socket(WFCTile.Direction.SOUTH, "road")
	road_alley_n.set_socket(WFCTile.Direction.EAST, "building")
	road_alley_n.set_socket(WFCTile.Direction.WEST, "building")
	tileset.register_tile(road_alley_n)

	var road_alley_s := WFCTile.new("road_alley_s", "Road-Alley S")
	road_alley_s.area_type = "transition"
	road_alley_s.walkability = 0.9
	road_alley_s.weight = 1.0
	road_alley_s.set_socket(WFCTile.Direction.NORTH, "road")
	road_alley_s.set_socket(WFCTile.Direction.SOUTH, "alley")
	road_alley_s.set_socket(WFCTile.Direction.EAST, "building")
	road_alley_s.set_socket(WFCTile.Direction.WEST, "building")
	tileset.register_tile(road_alley_s)

	# Road-boulevard transitions
	var road_blvd_n := WFCTile.new("road_blvd_n", "Road-Boulevard N")
	road_blvd_n.area_type = "transition"
	road_blvd_n.walkability = 1.0
	road_blvd_n.weight = 0.8
	road_blvd_n.set_socket(WFCTile.Direction.NORTH, "boulevard")
	road_blvd_n.set_socket(WFCTile.Direction.SOUTH, "road")
	road_blvd_n.set_socket(WFCTile.Direction.EAST, "building")
	road_blvd_n.set_socket(WFCTile.Direction.WEST, "building")
	tileset.register_tile(road_blvd_n)

	var road_blvd_s := WFCTile.new("road_blvd_s", "Road-Boulevard S")
	road_blvd_s.area_type = "transition"
	road_blvd_s.walkability = 1.0
	road_blvd_s.weight = 0.8
	road_blvd_s.set_socket(WFCTile.Direction.NORTH, "road")
	road_blvd_s.set_socket(WFCTile.Direction.SOUTH, "boulevard")
	road_blvd_s.set_socket(WFCTile.Direction.EAST, "building")
	road_blvd_s.set_socket(WFCTile.Direction.WEST, "building")
	tileset.register_tile(road_blvd_s)

	return tileset


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var tiles_data := {}
	for tile_id in tiles:
		tiles_data[tile_id] = tiles[tile_id].to_dict()

	return {
		"tiles": tiles_data
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> WFCTileset:
	var tileset := WFCTileset.new()

	var tiles_data: Dictionary = data.get("tiles", {})
	for tile_id in tiles_data:
		var tile := WFCTile.from_dict(tiles_data[tile_id])
		tileset.register_tile(tile)

	return tileset
