class_name CityBuilding
extends RefCounted
## CityBuilding represents a 3D building in the city grid.
## Has position, size, type, and destructibility properties.

## Building size categories
enum SizeCategory {
	SMALL = 0,   ## 4x4x4 voxels
	MEDIUM = 1,  ## 8x6x8 voxels
	LARGE = 2    ## 12x8x12 voxels
}

## Building type categories
enum BuildingCategory {
	RESIDENTIAL = 0,
	INDUSTRIAL = 1,
	COMMERCIAL = 2,
	INFRASTRUCTURE = 3
}

## Unique building ID
var id: int = 0

## Building type category
var category: int = BuildingCategory.RESIDENTIAL

## Size category
var size_category: int = SizeCategory.SMALL

## 3D position (voxel coordinates)
var position: Vector3i = Vector3i.ZERO

## 3D size (voxels)
var size: Vector3i = Vector3i(4, 4, 4)

## District ID this building belongs to
var district_id: int = -1

## Current health
var health: float = 100.0

## Maximum health
var max_health: float = 100.0

## Whether building is destroyed
var is_destroyed: bool = false

## Custom metadata
var metadata: Dictionary = {}


func _init(p_category: int = BuildingCategory.RESIDENTIAL, p_size: int = SizeCategory.SMALL) -> void:
	category = p_category
	size_category = p_size
	_set_size_from_category()
	_set_health_from_size()


## Set size based on category.
func _set_size_from_category() -> void:
	match size_category:
		SizeCategory.SMALL:
			size = Vector3i(4, 4, 4)
		SizeCategory.MEDIUM:
			size = Vector3i(8, 6, 8)
		SizeCategory.LARGE:
			size = Vector3i(12, 8, 12)


## Set health based on size.
func _set_health_from_size() -> void:
	match size_category:
		SizeCategory.SMALL:
			max_health = 100.0
		SizeCategory.MEDIUM:
			max_health = 250.0
		SizeCategory.LARGE:
			max_health = 500.0
	health = max_health


## Get 3D bounding box.
func get_bounds() -> AABB:
	return AABB(Vector3(position), Vector3(size))


## Check if position is inside building.
func contains(pos: Vector3i) -> bool:
	return (pos.x >= position.x and pos.x < position.x + size.x and
			pos.y >= position.y and pos.y < position.y + size.y and
			pos.z >= position.z and pos.z < position.z + size.z)


## Check if overlaps with another building.
func overlaps(other: CityBuilding) -> bool:
	return get_bounds().intersects(other.get_bounds())


## Check if fits within bounds.
func fits_within(min_pos: Vector3i, max_pos: Vector3i) -> bool:
	return (position.x >= min_pos.x and position.x + size.x <= max_pos.x and
			position.y >= min_pos.y and position.y + size.y <= max_pos.y and
			position.z >= min_pos.z and position.z + size.z <= max_pos.z)


## Take damage.
func take_damage(amount: float) -> bool:
	if is_destroyed:
		return false

	health = maxf(0.0, health - amount)

	if health <= 0:
		is_destroyed = true
		return true

	return false


## Repair building.
func repair(amount: float) -> void:
	if is_destroyed:
		return

	health = minf(max_health, health + amount)


## Get health percentage.
func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return health / max_health


## Get category name.
func get_category_name() -> String:
	match category:
		BuildingCategory.RESIDENTIAL: return "Residential"
		BuildingCategory.INDUSTRIAL: return "Industrial"
		BuildingCategory.COMMERCIAL: return "Commercial"
		BuildingCategory.INFRASTRUCTURE: return "Infrastructure"
	return "Unknown"


## Get size name.
func get_size_name() -> String:
	match size_category:
		SizeCategory.SMALL: return "Small"
		SizeCategory.MEDIUM: return "Medium"
		SizeCategory.LARGE: return "Large"
	return "Unknown"


## Get footprint area.
func get_footprint() -> int:
	return size.x * size.z


## Get volume.
func get_volume() -> int:
	return size.x * size.y * size.z


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"category": category,
		"size_category": size_category,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"size": {"x": size.x, "y": size.y, "z": size.z},
		"district_id": district_id,
		"health": health,
		"max_health": max_health,
		"is_destroyed": is_destroyed,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> CityBuilding:
	var building := CityBuilding.new(
		data.get("category", BuildingCategory.RESIDENTIAL),
		data.get("size_category", SizeCategory.SMALL)
	)

	building.id = data.get("id", 0)

	var pos_data: Dictionary = data.get("position", {})
	building.position = Vector3i(
		pos_data.get("x", 0),
		pos_data.get("y", 0),
		pos_data.get("z", 0)
	)

	var size_data: Dictionary = data.get("size", {})
	building.size = Vector3i(
		size_data.get("x", 4),
		size_data.get("y", 4),
		size_data.get("z", 4)
	)

	building.district_id = data.get("district_id", -1)
	building.health = data.get("health", 100.0)
	building.max_health = data.get("max_health", 100.0)
	building.is_destroyed = data.get("is_destroyed", false)
	building.metadata = data.get("metadata", {}).duplicate()

	return building


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"type": get_category_name(),
		"size": get_size_name(),
		"position": "%d,%d,%d" % [position.x, position.y, position.z],
		"health": "%.0f%%" % (get_health_percent() * 100),
		"destroyed": is_destroyed
	}
