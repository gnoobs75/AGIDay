class_name WFCTile
extends RefCounted
## WFCTile represents a single tile type in Wave Function Collapse.
## Contains adjacency rules defining which tiles can connect on each side.

## Tile directions
enum Direction {
	NORTH = 0,
	EAST = 1,
	SOUTH = 2,
	WEST = 3
}

## Tile identifier
var id: String = ""

## Display name
var name: String = ""

## Tile weight (probability)
var weight: float = 1.0

## Area classification
var area_type: String = "neutral"

## Faction affinity (higher = more favorable)
var faction_affinity: Dictionary = {}

## Walkability (0.0 = blocked, 1.0 = open)
var walkability: float = 1.0

## Building height (0 = ground level)
var height: int = 0

## Edge sockets for adjacency (direction -> socket_id)
var sockets: Dictionary = {
	Direction.NORTH: "",
	Direction.EAST: "",
	Direction.SOUTH: "",
	Direction.WEST: ""
}

## Custom metadata
var metadata: Dictionary = {}


func _init(p_id: String = "", p_name: String = "") -> void:
	id = p_id
	name = p_name if not p_name.is_empty() else p_id


## Set socket for direction.
func set_socket(direction: int, socket_id: String) -> void:
	sockets[direction] = socket_id


## Get socket for direction.
func get_socket(direction: int) -> String:
	return sockets.get(direction, "")


## Set all sockets to same value.
func set_all_sockets(socket_id: String) -> void:
	for dir in sockets:
		sockets[dir] = socket_id


## Set faction affinity.
func set_affinity(faction: String, value: float) -> void:
	faction_affinity[faction] = clampf(value, 0.0, 2.0)


## Get faction affinity.
func get_affinity(faction: String) -> float:
	return faction_affinity.get(faction, 1.0)


## Check if can connect to another tile on given side.
func can_connect(direction: int, other_tile: WFCTile) -> bool:
	if other_tile == null:
		return false

	var opposite := get_opposite_direction(direction)
	return sockets[direction] == other_tile.sockets[opposite]


## Get opposite direction.
static func get_opposite_direction(direction: int) -> int:
	match direction:
		Direction.NORTH: return Direction.SOUTH
		Direction.SOUTH: return Direction.NORTH
		Direction.EAST: return Direction.WEST
		Direction.WEST: return Direction.EAST
	return direction


## Get direction name.
static func get_direction_name(direction: int) -> String:
	match direction:
		Direction.NORTH: return "NORTH"
		Direction.EAST: return "EAST"
		Direction.SOUTH: return "SOUTH"
		Direction.WEST: return "WEST"
	return "UNKNOWN"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"weight": weight,
		"area_type": area_type,
		"faction_affinity": faction_affinity.duplicate(),
		"walkability": walkability,
		"height": height,
		"sockets": sockets.duplicate(),
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> WFCTile:
	var tile := WFCTile.new()
	tile.id = data.get("id", "")
	tile.name = data.get("name", "")
	tile.weight = data.get("weight", 1.0)
	tile.area_type = data.get("area_type", "neutral")
	tile.faction_affinity = data.get("faction_affinity", {}).duplicate()
	tile.walkability = data.get("walkability", 1.0)
	tile.height = data.get("height", 0)
	tile.sockets = data.get("sockets", {}).duplicate()
	tile.metadata = data.get("metadata", {}).duplicate()
	return tile
