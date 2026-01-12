class_name CityDistrict
extends RefCounted
## CityDistrict represents a 64x64 voxel district in the 8x8 city grid.
## Contains buildings and tracks ownership, type, and resources.

## District types based on position
enum DistrictType {
	POWER_PLANT = 0,   ## Corner districts (4)
	RESOURCE_NODE = 1, ## Edge districts excluding corners (24)
	MIXED = 2          ## Interior districts (36)
}

## District size in voxels
const DISTRICT_SIZE := 64

## Unique district ID
var id: int = 0

## Grid position (0-7, 0-7)
var grid_position: Vector2i = Vector2i.ZERO

## District type
var type: int = DistrictType.MIXED

## Voxel bounds
var position: Vector3i = Vector3i.ZERO
var size: Vector3i = Vector3i(DISTRICT_SIZE, 32, DISTRICT_SIZE)

## Buildings in this district
var buildings: Array[int] = []

## Controlling faction
var owner_faction: String = ""

## Capture progress (0.0 to 1.0)
var capture_progress: float = 0.0

## Whether district is contested
var is_contested: bool = false

## Resource production rate
var resource_rate: float = 0.0

## Power production rate
var power_rate: float = 0.0

## Custom metadata
var metadata: Dictionary = {}


func _init(p_grid_pos: Vector2i = Vector2i.ZERO) -> void:
	grid_position = p_grid_pos
	id = p_grid_pos.y * 8 + p_grid_pos.x
	_calculate_position()
	_determine_type()


## Calculate voxel position from grid position.
func _calculate_position() -> void:
	position = Vector3i(
		grid_position.x * DISTRICT_SIZE,
		0,
		grid_position.y * DISTRICT_SIZE
	)


## Determine district type from grid position.
func _determine_type() -> void:
	var is_corner := _is_corner_district()
	var is_edge := _is_edge_district()

	if is_corner:
		type = DistrictType.POWER_PLANT
		power_rate = 100.0  # Power plants produce power
	elif is_edge:
		type = DistrictType.RESOURCE_NODE
		resource_rate = 10.0  # Resource nodes produce REE
	else:
		type = DistrictType.MIXED
		resource_rate = 2.0  # Mixed districts produce some resources


## Check if district is a corner.
func _is_corner_district() -> bool:
	return ((grid_position.x == 0 or grid_position.x == 7) and
			(grid_position.y == 0 or grid_position.y == 7))


## Check if district is an edge (excluding corners).
func _is_edge_district() -> bool:
	if _is_corner_district():
		return false
	return (grid_position.x == 0 or grid_position.x == 7 or
			grid_position.y == 0 or grid_position.y == 7)


## Get 3D bounding box.
func get_bounds() -> AABB:
	return AABB(Vector3(position), Vector3(size))


## Get 2D bounds (XZ plane).
func get_bounds_2d() -> Rect2i:
	return Rect2i(
		grid_position.x * DISTRICT_SIZE,
		grid_position.y * DISTRICT_SIZE,
		DISTRICT_SIZE,
		DISTRICT_SIZE
	)


## Check if 3D position is in district.
func contains(pos: Vector3i) -> bool:
	return (pos.x >= position.x and pos.x < position.x + size.x and
			pos.y >= position.y and pos.y < position.y + size.y and
			pos.z >= position.z and pos.z < position.z + size.z)


## Check if 2D position (XZ) is in district.
func contains_2d(x: int, z: int) -> bool:
	return (x >= position.x and x < position.x + size.x and
			z >= position.z and z < position.z + size.z)


## Add building to district.
func add_building(building_id: int) -> void:
	if building_id not in buildings:
		buildings.append(building_id)


## Remove building from district.
func remove_building(building_id: int) -> void:
	var idx := buildings.find(building_id)
	if idx >= 0:
		buildings.remove_at(idx)


## Get building count.
func get_building_count() -> int:
	return buildings.size()


## Set owner faction.
func set_owner(faction: String) -> void:
	owner_faction = faction
	capture_progress = 1.0 if not faction.is_empty() else 0.0


## Check if controlled.
func is_controlled() -> bool:
	return not owner_faction.is_empty()


## Get type name.
func get_type_name() -> String:
	match type:
		DistrictType.POWER_PLANT: return "Power Plant"
		DistrictType.RESOURCE_NODE: return "Resource Node"
		DistrictType.MIXED: return "Mixed"
	return "Unknown"


## Get center position (voxels).
func get_center() -> Vector3i:
	return Vector3i(
		position.x + size.x / 2,
		position.y + size.y / 2,
		position.z + size.z / 2
	)


## Get center position 2D (XZ).
func get_center_2d() -> Vector2i:
	return Vector2i(
		position.x + size.x / 2,
		position.z + size.z / 2
	)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"grid_position": {"x": grid_position.x, "y": grid_position.y},
		"type": type,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"size": {"x": size.x, "y": size.y, "z": size.z},
		"buildings": buildings.duplicate(),
		"owner_faction": owner_faction,
		"capture_progress": capture_progress,
		"is_contested": is_contested,
		"resource_rate": resource_rate,
		"power_rate": power_rate,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> CityDistrict:
	var grid_data: Dictionary = data.get("grid_position", {})
	var district := CityDistrict.new(Vector2i(
		grid_data.get("x", 0),
		grid_data.get("y", 0)
	))

	district.id = data.get("id", district.id)
	district.type = data.get("type", district.type)

	var pos_data: Dictionary = data.get("position", {})
	district.position = Vector3i(
		pos_data.get("x", 0),
		pos_data.get("y", 0),
		pos_data.get("z", 0)
	)

	var size_data: Dictionary = data.get("size", {})
	district.size = Vector3i(
		size_data.get("x", DISTRICT_SIZE),
		size_data.get("y", 32),
		size_data.get("z", DISTRICT_SIZE)
	)

	district.buildings.clear()
	for bid in data.get("buildings", []):
		district.buildings.append(int(bid))

	district.owner_faction = data.get("owner_faction", "")
	district.capture_progress = data.get("capture_progress", 0.0)
	district.is_contested = data.get("is_contested", false)
	district.resource_rate = data.get("resource_rate", 0.0)
	district.power_rate = data.get("power_rate", 0.0)
	district.metadata = data.get("metadata", {}).duplicate()

	return district


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"grid": "%d,%d" % [grid_position.x, grid_position.y],
		"type": get_type_name(),
		"buildings": buildings.size(),
		"owner": owner_faction if not owner_faction.is_empty() else "none",
		"resources": "%.1f/s" % resource_rate,
		"power": "%.0f" % power_rate
	}
