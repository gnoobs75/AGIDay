class_name Zone
extends RefCounted
## Zone represents a city zone on the 16x16 zone grid.
## Each zone is 32x32 voxels.

## Zone dimensions in voxels
const ZONE_SIZE := 32

## Zone position (zone grid coordinates)
var position: Vector2i = Vector2i.ZERO

## Zone type
var type: int = ZoneType.Type.MIXED_ZONE

## Zone dimensions in voxels
var dimensions: Vector2i = Vector2i(ZONE_SIZE, ZONE_SIZE)

## Building density (0.0 to 1.0)
var density: float = 0.5

## Faction affinities (faction_id -> multiplier)
var faction_affinity: Dictionary = {}

## Power consumption
var power_consumption: float = 0.0

## Power production
var power_production: float = 0.0

## REE production rate
var ree_production: float = 0.0

## Buildings in this zone
var buildings: Array[int] = []  # Building IDs

## Controlling faction
var controlling_faction: String = ""

## Capture progress (0.0 to 1.0)
var capture_progress: float = 0.0

## Whether zone is contested
var is_contested: bool = false

## Custom metadata
var metadata: Dictionary = {}


func _init(p_position: Vector2i = Vector2i.ZERO, p_type: int = ZoneType.Type.MIXED_ZONE) -> void:
	position = p_position
	type = p_type
	density = ZoneType.get_default_density(type)
	faction_affinity = ZoneType.get_faction_affinities(type).duplicate()


## Get voxel bounds.
func get_voxel_bounds() -> Rect2i:
	return Rect2i(
		position.x * ZONE_SIZE,
		position.y * ZONE_SIZE,
		dimensions.x,
		dimensions.y
	)


## Get center in voxel coordinates.
func get_voxel_center() -> Vector2i:
	var bounds := get_voxel_bounds()
	return Vector2i(
		bounds.position.x + bounds.size.x / 2,
		bounds.position.y + bounds.size.y / 2
	)


## Check if voxel position is in zone.
func contains_voxel(voxel_pos: Vector2i) -> bool:
	var bounds := get_voxel_bounds()
	return bounds.has_point(voxel_pos)


## Get faction affinity.
func get_affinity(faction: String) -> float:
	return faction_affinity.get(faction, 1.0)


## Set faction affinity.
func set_affinity(faction: String, value: float) -> void:
	faction_affinity[faction] = clampf(value, 0.0, 3.0)


## Add building to zone.
func add_building(building_id: int) -> void:
	if building_id not in buildings:
		buildings.append(building_id)


## Remove building from zone.
func remove_building(building_id: int) -> void:
	var idx := buildings.find(building_id)
	if idx >= 0:
		buildings.remove_at(idx)


## Get net power (production - consumption).
func get_net_power() -> float:
	return power_production - power_consumption


## Check if zone is controlled.
func is_controlled() -> bool:
	return not controlling_faction.is_empty()


## Set controlling faction.
func set_controller(faction: String) -> void:
	controlling_faction = faction
	capture_progress = 1.0 if not faction.is_empty() else 0.0


## Get type name.
func get_type_name() -> String:
	return ZoneType.get_name(type)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"position": {"x": position.x, "y": position.y},
		"type": type,
		"dimensions": {"x": dimensions.x, "y": dimensions.y},
		"density": density,
		"faction_affinity": faction_affinity.duplicate(),
		"power_consumption": power_consumption,
		"power_production": power_production,
		"ree_production": ree_production,
		"buildings": buildings.duplicate(),
		"controlling_faction": controlling_faction,
		"capture_progress": capture_progress,
		"is_contested": is_contested,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> Zone:
	var pos_data: Dictionary = data.get("position", {})
	var zone := Zone.new(
		Vector2i(pos_data.get("x", 0), pos_data.get("y", 0)),
		data.get("type", ZoneType.Type.MIXED_ZONE)
	)

	var dim_data: Dictionary = data.get("dimensions", {})
	zone.dimensions = Vector2i(dim_data.get("x", ZONE_SIZE), dim_data.get("y", ZONE_SIZE))

	zone.density = data.get("density", 0.5)
	zone.faction_affinity = data.get("faction_affinity", {}).duplicate()
	zone.power_consumption = data.get("power_consumption", 0.0)
	zone.power_production = data.get("power_production", 0.0)
	zone.ree_production = data.get("ree_production", 0.0)

	zone.buildings.clear()
	for bid in data.get("buildings", []):
		zone.buildings.append(int(bid))

	zone.controlling_faction = data.get("controlling_faction", "")
	zone.capture_progress = data.get("capture_progress", 0.0)
	zone.is_contested = data.get("is_contested", false)
	zone.metadata = data.get("metadata", {}).duplicate()

	return zone


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"position": "%d,%d" % [position.x, position.y],
		"type": get_type_name(),
		"density": "%.0f%%" % (density * 100),
		"buildings": buildings.size(),
		"controller": controlling_faction if not controlling_faction.is_empty() else "none",
		"power": "%.1f" % get_net_power()
	}
