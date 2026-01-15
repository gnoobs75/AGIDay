class_name CityLayout
extends RefCounted
## CityLayout stores the complete generated city structure.
## Contains zones, buildings, power grid, and provides serialization.

## City dimensions
const ZONE_GRID_SIZE := 16      ## 16x16 zone grid
const ZONE_VOXEL_SIZE := 32     ## Each zone is 32x32 voxels
const BUILDING_GRID_SIZE := 512 ## 512x512 base building grid
const VOXEL_SIZE := 512         ## 512x512 voxel map

## Seed manager
var seed_manager: CityGenerationSeed = null

## Zone grid (16x16)
var zones: Array = []  # 2D array of Zone objects

## Buildings (id -> BuildingTile)
var buildings: Dictionary = {}

## Power grid nodes (id -> PowerGridNode)
var power_nodes: Dictionary = {}

## Next available IDs
var _next_building_id: int = 1
var _next_power_node_id: int = 1

## Generation timestamp
var generated_at: int = 0

## Generation duration (ms)
var generation_duration_ms: int = 0

## Custom metadata
var metadata: Dictionary = {}


func _init() -> void:
	seed_manager = CityGenerationSeed.new()
	_initialize_zones()


## Initialize zone grid.
func _initialize_zones() -> void:
	zones.clear()
	for y in ZONE_GRID_SIZE:
		var row: Array = []
		for x in ZONE_GRID_SIZE:
			row.append(Zone.new(Vector2i(x, y), ZoneType.Type.MIXED_ZONE))
		zones.append(row)


## Set seed and regenerate seed manager.
func set_seed(seed: int) -> void:
	seed_manager.initialize(seed)


## Get zone at grid position.
func get_zone(x: int, y: int) -> Zone:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return null
	return zones[y][x]


## Get zone at voxel position.
func get_zone_at_voxel(voxel_x: int, voxel_y: int) -> Zone:
	var zone_x := voxel_x / ZONE_VOXEL_SIZE
	var zone_y := voxel_y / ZONE_VOXEL_SIZE
	return get_zone(zone_x, zone_y)


## Set zone at position.
func set_zone(x: int, y: int, zone: Zone) -> void:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return
	zones[y][x] = zone


## Add building.
func add_building(building: BuildingTile) -> int:
	building.id = _next_building_id
	_next_building_id += 1
	buildings[building.id] = building

	# Add to zone
	var zone := get_zone_at_voxel(building.position.x, building.position.y)
	if zone != null:
		zone.add_building(building.id)
		building.zone_id = zone.position.y * ZONE_GRID_SIZE + zone.position.x

	return building.id


## Get building by ID.
func get_building(id: int) -> BuildingTile:
	return buildings.get(id)


## Get building at position.
func get_building_at(x: int, y: int) -> BuildingTile:
	for building in buildings.values():
		if building.contains(Vector2i(x, y)):
			return building
	return null


## Remove building.
func remove_building(id: int) -> bool:
	var building: BuildingTile = buildings.get(id)
	if building == null:
		return false

	# Remove from zone
	var zone := get_zone_at_voxel(building.position.x, building.position.y)
	if zone != null:
		zone.remove_building(id)

	buildings.erase(id)
	return true


## Add power node.
func add_power_node(node: PowerGridNode) -> int:
	node.id = _next_power_node_id
	_next_power_node_id += 1
	power_nodes[node.id] = node
	return node.id


## Get power node by ID.
func get_power_node(id: int) -> PowerGridNode:
	return power_nodes.get(id)


## Connect two power nodes.
func connect_power_nodes(id1: int, id2: int) -> bool:
	var node1 := get_power_node(id1)
	var node2 := get_power_node(id2)

	if node1 == null or node2 == null:
		return false

	return node1.add_connection(id2) and node2.add_connection(id1)


## Get zones by type.
func get_zones_by_type(zone_type: int) -> Array[Zone]:
	var result: Array[Zone] = []
	for row in zones:
		for zone in row:
			if zone.type == zone_type:
				result.append(zone)
	return result


## Get buildings by type.
func get_buildings_by_type(building_type: int) -> Array[BuildingTile]:
	var result: Array[BuildingTile] = []
	for building in buildings.values():
		if building.type == building_type:
			result.append(building)
	return result


## Get power nodes by type.
func get_power_nodes_by_type(node_type: int) -> Array[PowerGridNode]:
	var result: Array[PowerGridNode] = []
	for node in power_nodes.values():
		if node.type == node_type:
			result.append(node)
	return result


## Calculate total power production.
func get_total_power_production() -> float:
	var total := 0.0
	for node in power_nodes.values():
		if node.type == PowerGridNode.NodeType.GENERATOR:
			total += node.power_output
	return total


## Calculate total power demand.
func get_total_power_demand() -> float:
	var total := 0.0
	for node in power_nodes.values():
		if node.type == PowerGridNode.NodeType.CONSUMER:
			total += node.power_demand
	return total


## Calculate total REE production.
func get_total_ree_production() -> float:
	var total := 0.0
	for building in buildings.values():
		if building.is_ree_producer():
			total += building.ree_value
	return total


## Get memory usage estimate.
func get_memory_usage() -> int:
	var size := 0

	# Zones
	size += ZONE_GRID_SIZE * ZONE_GRID_SIZE * 200

	# Buildings
	size += buildings.size() * 300

	# Power nodes
	size += power_nodes.size() * 150

	return size


## Serialize to dictionary.
func to_dict() -> Dictionary:
	# Serialize zones
	var zones_data: Array = []
	for row in zones:
		var row_data: Array = []
		for zone in row:
			row_data.append(zone.to_dict())
		zones_data.append(row_data)

	# Serialize buildings
	var buildings_data: Dictionary = {}
	for id in buildings:
		buildings_data[str(id)] = buildings[id].to_dict()

	# Serialize power nodes
	var power_data: Dictionary = {}
	for id in power_nodes:
		power_data[str(id)] = power_nodes[id].to_dict()

	return {
		"seed_manager": seed_manager.to_dict(),
		"zones": zones_data,
		"buildings": buildings_data,
		"power_nodes": power_data,
		"next_building_id": _next_building_id,
		"next_power_node_id": _next_power_node_id,
		"generated_at": generated_at,
		"generation_duration_ms": generation_duration_ms,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> CityLayout:
	var layout := CityLayout.new()

	# Restore seed manager
	var seed_data: Dictionary = data.get("seed_manager", {})
	if not seed_data.is_empty():
		layout.seed_manager = CityGenerationSeed.from_dict(seed_data)

	# Restore zones
	layout.zones.clear()
	for row_data in data.get("zones", []):
		var row: Array = []
		for zone_data in row_data:
			row.append(Zone.from_dict(zone_data))
		layout.zones.append(row)

	# Initialize zones if empty
	if layout.zones.is_empty():
		layout._initialize_zones()

	# Restore buildings
	layout.buildings.clear()
	for id_str in data.get("buildings", {}):
		var building := BuildingTile.from_dict(data["buildings"][id_str])
		layout.buildings[int(id_str)] = building

	# Restore power nodes
	layout.power_nodes.clear()
	for id_str in data.get("power_nodes", {}):
		var node := PowerGridNode.from_dict(data["power_nodes"][id_str])
		layout.power_nodes[int(id_str)] = node

	layout._next_building_id = data.get("next_building_id", 1)
	layout._next_power_node_id = data.get("next_power_node_id", 1)
	layout.generated_at = data.get("generated_at", 0)
	layout.generation_duration_ms = data.get("generation_duration_ms", 0)
	layout.metadata = data.get("metadata", {}).duplicate()

	return layout


## Get summary for debugging.
func get_summary() -> Dictionary:
	var zone_counts: Dictionary = {}
	for row in zones:
		for zone in row:
			var type_name: String = zone.get_type_name()
			zone_counts[type_name] = zone_counts.get(type_name, 0) + 1

	return {
		"seed": seed_manager.master_seed,
		"zones": "%dx%d" % [ZONE_GRID_SIZE, ZONE_GRID_SIZE],
		"buildings": buildings.size(),
		"power_nodes": power_nodes.size(),
		"power_production": "%.0f" % get_total_power_production(),
		"power_demand": "%.0f" % get_total_power_demand(),
		"ree_production": "%.1f/s" % get_total_ree_production(),
		"zone_types": zone_counts,
		"memory_kb": "%.1f KB" % (get_memory_usage() / 1024.0),
		"generated_at": generated_at,
		"duration_ms": generation_duration_ms
	}
