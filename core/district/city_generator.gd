class_name ProceduralCityGenerator
extends RefCounted
## ProceduralCityGenerator orchestrates all city generation phases.
## Coordinates zone layout, power grid, building placement, and resource placement.

signal generation_started(seed_value: int)
signal phase_started(phase_name: String)
signal phase_completed(phase_name: String, time_ms: float)
signal generation_completed(layout: CityLayout)
signal generation_failed(reason: String)

## Generation phases
enum GenerationPhase {
	IDLE,
	ZONE_LAYOUT,
	POWER_GRID,
	BUILDING_PLACEMENT,
	RESOURCE_PLACEMENT,
	VOXEL_CONVERSION,
	COMPLETE,
	FAILED
}

## Phase names
const PHASE_NAMES := {
	GenerationPhase.ZONE_LAYOUT: "Zone Layout",
	GenerationPhase.POWER_GRID: "Power Grid",
	GenerationPhase.BUILDING_PLACEMENT: "Building Placement",
	GenerationPhase.RESOURCE_PLACEMENT: "Resource Placement",
	GenerationPhase.VOXEL_CONVERSION: "Voxel Conversion"
}

## Seed derivation constants
const ZONE_SEED_OFFSET := 1000
const POWER_SEED_OFFSET := 2000
const BUILDING_SEED_OFFSET := 3000
const RESOURCE_SEED_OFFSET := 4000
const VOXEL_SEED_OFFSET := 5000

## Sub-generators
var _zone_generator: ZoneGenerator = null
var _power_generator: PowerGridGenerator = null
var _building_placer: WFCBuildingPlacer = null

## State
var _current_phase: GenerationPhase = GenerationPhase.IDLE
var _master_seed: int = 0
var _start_time: int = 0

## Results
var _zone_result: Dictionary = {}
var _power_result: Dictionary = {}
var _building_result: Array = []
var _resource_result: Array = []


func _init() -> void:
	_zone_generator = ZoneGenerator.new()
	_power_generator = PowerGridGenerator.new()
	_building_placer = WFCBuildingPlacer.new()


## Generate complete city with given seed.
func generate_city(seed_value: int = 0) -> CityLayout:
	_master_seed = seed_value if seed_value != 0 else Time.get_ticks_msec()
	_start_time = Time.get_ticks_msec()

	generation_started.emit(_master_seed)

	# Phase 1: Zone Layout
	_current_phase = GenerationPhase.ZONE_LAYOUT
	phase_started.emit(PHASE_NAMES[_current_phase])

	var zone_start := Time.get_ticks_msec()
	var zone_seed := _derive_seed(ZONE_SEED_OFFSET)
	_zone_result = _zone_generator.generate_zone_layout(zone_seed)

	if _zone_result.is_empty():
		_fail_generation("Zone layout generation failed")
		return null

	phase_completed.emit(PHASE_NAMES[_current_phase], Time.get_ticks_msec() - zone_start)

	# Phase 2: Power Grid
	_current_phase = GenerationPhase.POWER_GRID
	phase_started.emit(PHASE_NAMES[_current_phase])

	var power_start := Time.get_ticks_msec()
	var power_seed := _derive_seed(POWER_SEED_OFFSET)
	_power_result = _power_generator.generate_power_grid(_zone_result["zones"], power_seed)

	if _power_result.is_empty():
		_fail_generation("Power grid generation failed")
		return null

	phase_completed.emit(PHASE_NAMES[_current_phase], Time.get_ticks_msec() - power_start)

	# Phase 3: Building Placement
	_current_phase = GenerationPhase.BUILDING_PLACEMENT
	phase_started.emit(PHASE_NAMES[_current_phase])

	var building_start := Time.get_ticks_msec()
	var building_seed := _derive_seed(BUILDING_SEED_OFFSET)
	var wfc_zone_grid := _convert_zones_for_wfc(_zone_result["zones"])
	_building_result = _building_placer.generate_building_layout(wfc_zone_grid, building_seed)

	if _building_result.is_empty():
		_fail_generation("Building placement failed")
		return null

	phase_completed.emit(PHASE_NAMES[_current_phase], Time.get_ticks_msec() - building_start)

	# Phase 4: Resource Placement
	_current_phase = GenerationPhase.RESOURCE_PLACEMENT
	phase_started.emit(PHASE_NAMES[_current_phase])

	var resource_start := Time.get_ticks_msec()
	var resource_seed := _derive_seed(RESOURCE_SEED_OFFSET)
	_resource_result = _generate_resources(resource_seed)

	phase_completed.emit(PHASE_NAMES[_current_phase], Time.get_ticks_msec() - resource_start)

	# Phase 5: Voxel Conversion (placeholder - actual voxel conversion done by VoxelConverter)
	_current_phase = GenerationPhase.VOXEL_CONVERSION
	phase_started.emit(PHASE_NAMES[_current_phase])

	var voxel_start := Time.get_ticks_msec()
	# Voxel conversion is handled separately by the voxel system
	# This phase prepares the data structure

	phase_completed.emit(PHASE_NAMES[_current_phase], Time.get_ticks_msec() - voxel_start)

	# Create final layout
	_current_phase = GenerationPhase.COMPLETE
	var total_time := float(Time.get_ticks_msec() - _start_time)

	var layout := CityLayout.create_from_generation(
		_zone_result,
		_power_result,
		_building_result,
		_master_seed,
		total_time
	)

	layout.resource_positions = _resource_result.duplicate(true)

	generation_completed.emit(layout)
	return layout


## Derive sub-seed for deterministic phase generation.
func _derive_seed(offset: int) -> int:
	# Use hash combining for better distribution
	var combined := _master_seed ^ (offset * 2654435761)  # Golden ratio hash
	return combined & 0x7FFFFFFF  # Keep positive


## Convert zone grid to WFC format.
func _convert_zones_for_wfc(zones: Array) -> Array:
	# Map ZoneGenerator types to WFCBuildingPlacer types
	const ZONE_MAPPING := {
		0: 4,  # POWER_HUB -> PARK (special handling)
		1: 3,  # INDUSTRIAL -> INDUSTRIAL
		2: 0,  # ZERG_ALLEY -> ZERG_ALLEY
		3: 1,  # TANK_BOULEVARD -> TANK_BOULEVARD
		4: 2,  # RESIDENTIAL -> MIXED_USE
		5: 2,  # COMMERCIAL -> MIXED_USE
		6: 4,  # PARK -> PARK
		7: 2   # MIXED -> MIXED_USE
	}

	# Expand zone grid (16x16) to building grid scale (512x512)
	var wfc_zones := []
	var voxels_per_zone := 32  # 512 / 16

	for x in 512:
		var row := []
		var zone_x := mini(x / voxels_per_zone, zones.size() - 1)

		for y in 512:
			var zone_y := 0
			if zone_x < zones.size():
				zone_y = mini(y / voxels_per_zone, zones[zone_x].size() - 1)

			var zone_type := 0
			if zone_x < zones.size() and zone_y < zones[zone_x].size():
				zone_type = zones[zone_x][zone_y]

			row.append(ZONE_MAPPING.get(zone_type, 2))

		wfc_zones.append(row)

	return wfc_zones


## Generate resource placement.
func _generate_resources(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var resources := []

	# Place resources based on zone types and building types
	for x in range(0, 512, 32):  # Check every 32 cells
		for y in range(0, 512, 32):
			var zone_x := x / 32
			var zone_y := y / 32

			if zone_x >= _zone_result["zones"].size():
				continue
			if zone_y >= _zone_result["zones"][zone_x].size():
				continue

			var zone_type: int = _zone_result["zones"][zone_x][zone_y]
			var density: float = _zone_result["densities"][zone_x][zone_y] if _zone_result.has("densities") else 0.5

			# More resources in industrial and commercial zones
			var resource_chance := 0.1
			match zone_type:
				1:  # INDUSTRIAL
					resource_chance = 0.4
				5:  # COMMERCIAL
					resource_chance = 0.3
				4:  # RESIDENTIAL
					resource_chance = 0.15

			if rng.randf() < resource_chance * density:
				var resource := {
					"position": Vector3(x + rng.randi() % 32, 0, y + rng.randi() % 32),
					"type": _select_resource_type(rng, zone_type),
					"amount": rng.randi_range(10, 100)
				}
				resources.append(resource)

	return resources


## Select resource type based on zone.
func _select_resource_type(rng: RandomNumberGenerator, zone_type: int) -> String:
	var types := ["ree_common", "ree_rare", "scrap_metal", "electronics"]

	match zone_type:
		1:  # INDUSTRIAL
			types = ["scrap_metal", "scrap_metal", "electronics", "ree_common"]
		5:  # COMMERCIAL
			types = ["electronics", "ree_common", "ree_rare", "scrap_metal"]
		_:
			types = ["ree_common", "scrap_metal", "electronics", "ree_rare"]

	return types[rng.randi() % types.size()]


## Fail generation with reason.
func _fail_generation(reason: String) -> void:
	_current_phase = GenerationPhase.FAILED
	generation_failed.emit(reason)


## Get current phase.
func get_current_phase() -> GenerationPhase:
	return _current_phase


## Get current phase name.
func get_current_phase_name() -> String:
	return PHASE_NAMES.get(_current_phase, "Unknown")


## Get zone generator for direct access.
func get_zone_generator() -> ZoneGenerator:
	return _zone_generator


## Get power generator for direct access.
func get_power_generator() -> PowerGridGenerator:
	return _power_generator


## Get building placer for direct access.
func get_building_placer() -> WFCBuildingPlacer:
	return _building_placer


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"master_seed": _master_seed,
		"current_phase": _current_phase,
		"zone_stats": _zone_generator.get_statistics() if _zone_generator else {},
		"power_stats": _power_generator.get_statistics() if _power_generator else {},
		"building_stats": _building_placer.get_statistics() if _building_placer else {}
	}


## CityGenerationSeed helper class for seed management.
class CityGenerationSeed:
	var master_seed: int = 0

	func _init(seed_value: int = 0) -> void:
		master_seed = seed_value if seed_value != 0 else Time.get_ticks_msec()

	func get_zone_seed() -> int:
		return _derive(ZONE_SEED_OFFSET)

	func get_power_seed() -> int:
		return _derive(POWER_SEED_OFFSET)

	func get_building_seed() -> int:
		return _derive(BUILDING_SEED_OFFSET)

	func get_resource_seed() -> int:
		return _derive(RESOURCE_SEED_OFFSET)

	func get_voxel_seed() -> int:
		return _derive(VOXEL_SEED_OFFSET)

	func _derive(offset: int) -> int:
		var combined := master_seed ^ (offset * 2654435761)
		return combined & 0x7FFFFFFF

	func to_dict() -> Dictionary:
		return {"master_seed": master_seed}

	static func from_dict(data: Dictionary) -> CityGenerationSeed:
		var seed_obj := CityGenerationSeed.new(data.get("master_seed", 0))
		return seed_obj
