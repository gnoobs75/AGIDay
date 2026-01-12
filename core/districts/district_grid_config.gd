class_name DistrictGridConfig
extends RefCounted
## DistrictGridConfig defines the grid layout for districts.
## Supports different configurations (8x8 with 64 districts, 16x16 with 256 districts, etc.)

## Preset configurations
enum Preset {
	STANDARD_8X8 = 0,   ## 64 districts, 64x64 voxels each
	DETAILED_16X16 = 1  ## 256 districts, 32x32 voxels each
}

## Map size in voxels
var map_size: int = 512

## Grid dimensions
var grid_size: int = 8

## District size in voxels
var district_size: int = 64

## Total number of districts
var total_districts: int = 64


func _init(preset: int = Preset.STANDARD_8X8) -> void:
	apply_preset(preset)


## Apply a preset configuration.
func apply_preset(preset: int) -> void:
	match preset:
		Preset.STANDARD_8X8:
			map_size = 512
			grid_size = 8
			district_size = 64
			total_districts = 64
		Preset.DETAILED_16X16:
			map_size = 512
			grid_size = 16
			district_size = 32
			total_districts = 256


## Create custom configuration.
func configure(p_map_size: int, p_grid_size: int) -> void:
	map_size = p_map_size
	grid_size = p_grid_size
	district_size = map_size / grid_size
	total_districts = grid_size * grid_size


## Get district ID from grid coordinates.
func get_id_from_grid(grid_x: int, grid_y: int) -> int:
	if grid_x < 0 or grid_x >= grid_size:
		return -1
	if grid_y < 0 or grid_y >= grid_size:
		return -1
	return grid_y * grid_size + grid_x


## Get grid coordinates from district ID.
func get_grid_from_id(id: int) -> Vector2i:
	if id < 0 or id >= total_districts:
		return Vector2i(-1, -1)
	return Vector2i(id % grid_size, id / grid_size)


## Get district ID from world position.
func get_id_from_position(pos: Vector3) -> int:
	var grid_x := int(pos.x / district_size)
	var grid_y := int(pos.z / district_size)
	return get_id_from_grid(grid_x, grid_y)


## Get world position (center) from district ID.
func get_position_from_id(id: int) -> Vector3:
	var grid := get_grid_from_id(id)
	if grid.x < 0:
		return Vector3.ZERO
	var half := district_size / 2.0
	return Vector3(grid.x * district_size + half, 0.0, grid.y * district_size + half)


## Get string ID in format "DISTRICT_X_Y".
func get_string_id(id: int) -> String:
	var grid := get_grid_from_id(id)
	return "DISTRICT_%d_%d" % [grid.x, grid.y]


## Parse string ID to get numeric ID.
func parse_string_id(string_id: String) -> int:
	if not string_id.begins_with("DISTRICT_"):
		return -1
	var parts := string_id.substr(9).split("_")
	if parts.size() != 2:
		return -1
	var x := parts[0].to_int()
	var y := parts[1].to_int()
	return get_id_from_grid(x, y)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"map_size": map_size,
		"grid_size": grid_size,
		"district_size": district_size,
		"total_districts": total_districts
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> DistrictGridConfig:
	var config := DistrictGridConfig.new()
	config.map_size = data.get("map_size", 512)
	config.grid_size = data.get("grid_size", 8)
	config.district_size = data.get("district_size", 64)
	config.total_districts = data.get("total_districts", 64)
	return config


## Create standard 8x8 config.
static func create_standard() -> DistrictGridConfig:
	return DistrictGridConfig.new(Preset.STANDARD_8X8)


## Create detailed 16x16 config.
static func create_detailed() -> DistrictGridConfig:
	return DistrictGridConfig.new(Preset.DETAILED_16X16)
