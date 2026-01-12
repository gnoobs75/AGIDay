class_name DistrictCityGenerator
extends RefCounted
## DistrictCityGenerator creates a 512x512 voxel city with 64 districts.
## Uses deterministic seeded generation for reproducible maps.

signal generation_started(seed: int)
signal generation_progress(progress: float, phase: String)
signal generation_complete(success: bool, duration_ms: int)
signal district_generated(district: CityDistrict)
signal building_placed(building: CityBuilding, district_id: int)

## City dimensions
const GRID_SIZE := 512         ## Total city size in voxels
const DISTRICT_GRID := 8       ## 8x8 district grid
const DISTRICT_SIZE := 64      ## Each district is 64x64 voxels
const TOTAL_DISTRICTS := 64    ## 8 * 8 = 64 districts

## Building placement settings
const MIN_BUILDINGS_PER_DISTRICT := 5
const MAX_BUILDINGS_PER_DISTRICT := 15
const BUILDING_SPACING := 2    ## Minimum gap between buildings

## Generation state
enum State {
	IDLE = 0,
	GENERATING = 1,
	COMPLETE = 2,
	FAILED = 3
}

## Current state
var state: int = State.IDLE

## Generation seed
var seed: int = 0

## Random number generator
var _rng: RandomNumberGenerator = null

## Generated districts (grid_y * 8 + grid_x -> CityDistrict)
var districts: Dictionary = {}

## Generated buildings (id -> CityBuilding)
var buildings: Dictionary = {}

## Next building ID
var _next_building_id: int = 1

## Generation timing
var _generation_start_time: int = 0
var _generation_duration_ms: int = 0


func _init() -> void:
	_rng = RandomNumberGenerator.new()


## Generate city with seed.
func generate(p_seed: int = 0) -> bool:
	if state == State.GENERATING:
		return false

	state = State.GENERATING
	seed = p_seed if p_seed != 0 else randi()
	_rng.seed = seed

	_generation_start_time = Time.get_ticks_msec()

	generation_started.emit(seed)

	# Clear existing data
	districts.clear()
	buildings.clear()
	_next_building_id = 1

	# Phase 1: Generate districts
	generation_progress.emit(0.1, "Creating districts")
	if not _generate_districts():
		_fail_generation("District generation failed")
		return false

	# Phase 2: Place buildings
	generation_progress.emit(0.3, "Placing buildings")
	if not _place_buildings():
		_fail_generation("Building placement failed")
		return false

	# Complete
	_generation_duration_ms = Time.get_ticks_msec() - _generation_start_time
	state = State.COMPLETE

	generation_progress.emit(1.0, "Complete")
	generation_complete.emit(true, _generation_duration_ms)

	return true


## Generate all districts.
func _generate_districts() -> bool:
	for y in DISTRICT_GRID:
		for x in DISTRICT_GRID:
			var district := CityDistrict.new(Vector2i(x, y))
			districts[district.id] = district
			district_generated.emit(district)

	return districts.size() == TOTAL_DISTRICTS


## Place buildings in all districts.
func _place_buildings() -> bool:
	var district_count := 0

	for district_id in districts:
		var district: CityDistrict = districts[district_id]

		var num_buildings := _rng.randi_range(MIN_BUILDINGS_PER_DISTRICT, MAX_BUILDINGS_PER_DISTRICT)

		for i in num_buildings:
			var building := _create_building_for_district(district)
			if building != null:
				building.id = _next_building_id
				_next_building_id += 1
				building.district_id = district.id

				buildings[building.id] = building
				district.add_building(building.id)

				building_placed.emit(building, district.id)

		district_count += 1

		# Report progress
		var progress := 0.3 + 0.7 * (float(district_count) / float(TOTAL_DISTRICTS))
		generation_progress.emit(progress, "Placing buildings in district %d" % district_id)

	return true


## Create a building for a district.
func _create_building_for_district(district: CityDistrict) -> CityBuilding:
	# Choose building size based on district type
	var size_category := _choose_building_size(district.type)

	# Choose building category
	var category := _choose_building_category(district.type)

	var building := CityBuilding.new(category, size_category)

	# Find valid position in district
	var position := _find_building_position(district, building)
	if position.x < 0:
		return null  # No valid position found

	building.position = position
	return building


## Choose building size based on district type.
func _choose_building_size(district_type: int) -> int:
	var roll := _rng.randf()

	match district_type:
		CityDistrict.DistrictType.POWER_PLANT:
			# Power plants have more large buildings
			if roll < 0.4:
				return CityBuilding.SizeCategory.LARGE
			elif roll < 0.7:
				return CityBuilding.SizeCategory.MEDIUM
			else:
				return CityBuilding.SizeCategory.SMALL

		CityDistrict.DistrictType.RESOURCE_NODE:
			# Resource districts have medium buildings
			if roll < 0.3:
				return CityBuilding.SizeCategory.LARGE
			elif roll < 0.7:
				return CityBuilding.SizeCategory.MEDIUM
			else:
				return CityBuilding.SizeCategory.SMALL

		_:  # MIXED
			# Mixed districts have varied sizes
			if roll < 0.2:
				return CityBuilding.SizeCategory.LARGE
			elif roll < 0.5:
				return CityBuilding.SizeCategory.MEDIUM
			else:
				return CityBuilding.SizeCategory.SMALL

	return CityBuilding.SizeCategory.SMALL


## Choose building category based on district type.
func _choose_building_category(district_type: int) -> int:
	var roll := _rng.randf()

	match district_type:
		CityDistrict.DistrictType.POWER_PLANT:
			return CityBuilding.BuildingCategory.INFRASTRUCTURE

		CityDistrict.DistrictType.RESOURCE_NODE:
			if roll < 0.6:
				return CityBuilding.BuildingCategory.INDUSTRIAL
			else:
				return CityBuilding.BuildingCategory.INFRASTRUCTURE

		_:  # MIXED
			if roll < 0.4:
				return CityBuilding.BuildingCategory.RESIDENTIAL
			elif roll < 0.7:
				return CityBuilding.BuildingCategory.COMMERCIAL
			else:
				return CityBuilding.BuildingCategory.INDUSTRIAL

	return CityBuilding.BuildingCategory.RESIDENTIAL


## Find valid position for building in district.
func _find_building_position(district: CityDistrict, building: CityBuilding) -> Vector3i:
	var max_attempts := 50

	var min_x := district.position.x + BUILDING_SPACING
	var max_x := district.position.x + district.size.x - building.size.x - BUILDING_SPACING
	var min_z := district.position.z + BUILDING_SPACING
	var max_z := district.position.z + district.size.z - building.size.z - BUILDING_SPACING

	if max_x <= min_x or max_z <= min_z:
		return Vector3i(-1, -1, -1)  # Building too large for district

	for attempt in max_attempts:
		var x := _rng.randi_range(min_x, max_x)
		var z := _rng.randi_range(min_z, max_z)
		var pos := Vector3i(x, 0, z)

		# Check for overlaps with existing buildings
		var test_building := CityBuilding.new(building.category, building.size_category)
		test_building.position = pos

		if _is_position_valid(district, test_building):
			return pos

	return Vector3i(-1, -1, -1)


## Check if building position is valid.
func _is_position_valid(district: CityDistrict, building: CityBuilding) -> bool:
	# Check bounds
	var min_pos := district.position
	var max_pos := district.position + district.size

	if not building.fits_within(min_pos, max_pos):
		return false

	# Check overlaps with existing buildings in district
	for existing_id in district.buildings:
		var existing: CityBuilding = buildings.get(existing_id)
		if existing != null:
			# Add spacing check
			var expanded_bounds := AABB(
				Vector3(building.position) - Vector3(BUILDING_SPACING, 0, BUILDING_SPACING),
				Vector3(building.size) + Vector3(BUILDING_SPACING * 2, 0, BUILDING_SPACING * 2)
			)

			if expanded_bounds.intersects(existing.get_bounds()):
				return false

	return true


## Fail generation.
func _fail_generation(reason: String) -> void:
	state = State.FAILED
	_generation_duration_ms = Time.get_ticks_msec() - _generation_start_time
	generation_complete.emit(false, _generation_duration_ms)
	push_error("City generation failed: " + reason)


## Get district at grid position.
func get_district(grid_x: int, grid_y: int) -> CityDistrict:
	var id := grid_y * DISTRICT_GRID + grid_x
	return districts.get(id)


## Get district at voxel position.
func get_district_at(voxel_x: int, voxel_z: int) -> CityDistrict:
	var grid_x := voxel_x / DISTRICT_SIZE
	var grid_z := voxel_z / DISTRICT_SIZE
	return get_district(grid_x, grid_z)


## Get building by ID.
func get_building(id: int) -> CityBuilding:
	return buildings.get(id)


## Get building at voxel position.
func get_building_at(pos: Vector3i) -> CityBuilding:
	for building in buildings.values():
		if building.contains(pos):
			return building
	return null


## Get buildings in district.
func get_buildings_in_district(district_id: int) -> Array[CityBuilding]:
	var result: Array[CityBuilding] = []
	var district: CityDistrict = districts.get(district_id)

	if district != null:
		for building_id in district.buildings:
			var building: CityBuilding = buildings.get(building_id)
			if building != null:
				result.append(building)

	return result


## Get districts by type.
func get_districts_by_type(district_type: int) -> Array[CityDistrict]:
	var result: Array[CityDistrict] = []
	for district in districts.values():
		if district.type == district_type:
			result.append(district)
	return result


## Get memory usage estimate (bytes).
func get_memory_usage() -> int:
	var size := 0

	# Districts
	size += districts.size() * 500

	# Buildings
	size += buildings.size() * 300

	return size


## Check if generation is complete.
func is_complete() -> bool:
	return state == State.COMPLETE


## Check if generation failed.
func is_failed() -> bool:
	return state == State.FAILED


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var districts_data: Dictionary = {}
	for id in districts:
		districts_data[str(id)] = districts[id].to_dict()

	var buildings_data: Dictionary = {}
	for id in buildings:
		buildings_data[str(id)] = buildings[id].to_dict()

	return {
		"seed": seed,
		"state": state,
		"districts": districts_data,
		"buildings": buildings_data,
		"next_building_id": _next_building_id,
		"generation_duration_ms": _generation_duration_ms
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> DistrictCityGenerator:
	var generator := DistrictCityGenerator.new()
	generator.seed = data.get("seed", 0)
	generator.state = data.get("state", State.IDLE)
	generator._next_building_id = data.get("next_building_id", 1)
	generator._generation_duration_ms = data.get("generation_duration_ms", 0)

	generator._rng.seed = generator.seed

	# Restore districts
	generator.districts.clear()
	for id_str in data.get("districts", {}):
		var district := CityDistrict.from_dict(data["districts"][id_str])
		generator.districts[int(id_str)] = district

	# Restore buildings
	generator.buildings.clear()
	for id_str in data.get("buildings", {}):
		var building := CityBuilding.from_dict(data["buildings"][id_str])
		generator.buildings[int(id_str)] = building

	return generator


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_counts: Dictionary = {}
	for district in districts.values():
		var type_name := district.get_type_name()
		type_counts[type_name] = type_counts.get(type_name, 0) + 1

	var building_counts: Dictionary = {}
	for building in buildings.values():
		var category := building.get_category_name()
		building_counts[category] = building_counts.get(category, 0) + 1

	return {
		"seed": seed,
		"state": ["IDLE", "GENERATING", "COMPLETE", "FAILED"][state],
		"grid_size": "%dx%d" % [GRID_SIZE, GRID_SIZE],
		"districts": districts.size(),
		"district_types": type_counts,
		"buildings": buildings.size(),
		"building_types": building_counts,
		"memory_kb": "%.1f KB" % (get_memory_usage() / 1024.0),
		"duration_ms": _generation_duration_ms
	}
