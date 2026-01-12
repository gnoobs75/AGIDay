class_name BuildingTile
extends RefCounted
## BuildingTile represents a building placement on the city grid.
## Used by WFC algorithm for compatible tile placement.

## Unique building ID
var id: int = 0

## Building type
var type: int = BuildingType.Type.EMPTY

## Position on building grid
var position: Vector2i = Vector2i.ZERO

## Dimensions in grid cells
var dimensions: Vector2i = Vector2i(1, 1)

## Height in floors
var height: int = 0

## REE value (production or storage)
var ree_value: float = 0.0

## Power consumption
var power_consumption: float = 0.0

## Power production
var power_production: float = 0.0

## Compatible zone types
var compatible_zones: Array[int] = []

## Neighbor constraints (direction -> Array of compatible building types)
var neighbor_constraints: Dictionary = {}

## Whether building is connected to power grid
var has_power: bool = false

## Zone this building belongs to
var zone_id: int = -1

## Faction affinity overrides
var faction_affinity: Dictionary = {}

## Health points (for destructible buildings)
var health: float = 100.0
var max_health: float = 100.0

## Custom metadata
var metadata: Dictionary = {}


func _init(p_type: int = BuildingType.Type.EMPTY, p_position: Vector2i = Vector2i.ZERO) -> void:
	type = p_type
	position = p_position
	_initialize_from_type()


## Initialize properties from type.
func _initialize_from_type() -> void:
	dimensions = BuildingType.get_dimensions(type)
	height = BuildingType.get_height(type)
	power_consumption = BuildingType.get_power_consumption(type)
	power_production = BuildingType.get_power_production(type)
	ree_value = BuildingType.get_ree_production(type)

	compatible_zones.clear()
	for zone_type in BuildingType.get_compatible_zones(type):
		compatible_zones.append(zone_type)

	_setup_neighbor_constraints()


## Setup neighbor constraints for WFC.
func _setup_neighbor_constraints() -> void:
	neighbor_constraints.clear()

	# Default: all buildings can neighbor each other
	var all_types := BuildingType.get_all_types()

	for dir in [WFCTile.Direction.NORTH, WFCTile.Direction.EAST, WFCTile.Direction.SOUTH, WFCTile.Direction.WEST]:
		neighbor_constraints[dir] = all_types.duplicate()

	# Add specific constraints based on type
	match type:
		BuildingType.Type.ALLEY:
			# Alleys prefer alleys or small buildings
			for dir in neighbor_constraints:
				neighbor_constraints[dir] = [
					BuildingType.Type.ALLEY,
					BuildingType.Type.SMALL_RESIDENTIAL,
					BuildingType.Type.SMALL_COMMERCIAL,
					BuildingType.Type.ROAD,
					BuildingType.Type.EMPTY
				]
		BuildingType.Type.BOULEVARD:
			# Boulevards connect to roads and other boulevards
			for dir in neighbor_constraints:
				neighbor_constraints[dir] = [
					BuildingType.Type.BOULEVARD,
					BuildingType.Type.ROAD,
					BuildingType.Type.PLAZA,
					BuildingType.Type.LARGE_COMMERCIAL,
					BuildingType.Type.MEDIUM_COMMERCIAL
				]
		BuildingType.Type.POWER_STATION:
			# Power stations need buffer zones
			for dir in neighbor_constraints:
				neighbor_constraints[dir] = [
					BuildingType.Type.ROAD,
					BuildingType.Type.EMPTY,
					BuildingType.Type.POWER_SUBSTATION,
					BuildingType.Type.SMALL_INDUSTRIAL,
					BuildingType.Type.WAREHOUSE
				]


## Get bounding rect.
func get_bounds() -> Rect2i:
	return Rect2i(position, dimensions)


## Check if position overlaps.
func overlaps(other: BuildingTile) -> bool:
	return get_bounds().intersects(other.get_bounds())


## Check if contains grid position.
func contains(grid_pos: Vector2i) -> bool:
	return get_bounds().has_point(grid_pos)


## Get net power.
func get_net_power() -> float:
	return power_production - power_consumption


## Check if produces power.
func is_power_producer() -> bool:
	return power_production > 0


## Check if produces REE.
func is_ree_producer() -> bool:
	return ree_value > 0


## Check if walkable.
func is_walkable() -> bool:
	return BuildingType.is_walkable(type)


## Check if is actual building (not road/empty).
func is_building() -> bool:
	return BuildingType.is_building(type)


## Get type name.
func get_type_name() -> String:
	return BuildingType.get_name(type)


## Get faction affinity.
func get_affinity(faction: String) -> float:
	return faction_affinity.get(faction, 1.0)


## Set faction affinity.
func set_affinity(faction: String, value: float) -> void:
	faction_affinity[faction] = clampf(value, 0.0, 3.0)


## Can be placed in zone type.
func can_place_in_zone(zone_type: int) -> bool:
	return zone_type in compatible_zones


## Can neighbor another building type.
func can_neighbor(direction: int, other_type: int) -> bool:
	if not neighbor_constraints.has(direction):
		return true
	return other_type in neighbor_constraints[direction]


## Take damage.
func take_damage(amount: float) -> bool:
	health = maxf(0.0, health - amount)
	return health <= 0


## Repair building.
func repair(amount: float) -> void:
	health = minf(max_health, health + amount)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"position": {"x": position.x, "y": position.y},
		"dimensions": {"x": dimensions.x, "y": dimensions.y},
		"height": height,
		"ree_value": ree_value,
		"power_consumption": power_consumption,
		"power_production": power_production,
		"compatible_zones": compatible_zones.duplicate(),
		"has_power": has_power,
		"zone_id": zone_id,
		"faction_affinity": faction_affinity.duplicate(),
		"health": health,
		"max_health": max_health,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> BuildingTile:
	var pos_data: Dictionary = data.get("position", {})
	var tile := BuildingTile.new(
		data.get("type", BuildingType.Type.EMPTY),
		Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))
	)

	tile.id = data.get("id", 0)

	var dim_data: Dictionary = data.get("dimensions", {})
	tile.dimensions = Vector2i(dim_data.get("x", 1), dim_data.get("y", 1))

	tile.height = data.get("height", 0)
	tile.ree_value = data.get("ree_value", 0.0)
	tile.power_consumption = data.get("power_consumption", 0.0)
	tile.power_production = data.get("power_production", 0.0)

	tile.compatible_zones.clear()
	for zt in data.get("compatible_zones", []):
		tile.compatible_zones.append(int(zt))

	tile.has_power = data.get("has_power", false)
	tile.zone_id = data.get("zone_id", -1)
	tile.faction_affinity = data.get("faction_affinity", {}).duplicate()
	tile.health = data.get("health", 100.0)
	tile.max_health = data.get("max_health", 100.0)
	tile.metadata = data.get("metadata", {}).duplicate()

	return tile


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"type": get_type_name(),
		"position": "%d,%d" % [position.x, position.y],
		"size": "%dx%d" % [dimensions.x, dimensions.y],
		"height": height,
		"power": "%.1f" % get_net_power(),
		"health": "%.0f%%" % (health / max_health * 100)
	}
