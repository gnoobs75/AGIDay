class_name ProceduralCity
extends RefCounted
## ProceduralCity is the main integration class for city generation.
## Coordinates all subsystems and provides the complete city for gameplay.

signal city_generation_started(seed_value: int)
signal city_generation_progress(phase: String, progress: float)
signal city_generation_completed(city_data: Dictionary)
signal city_generation_failed(reason: String)
signal district_setup_completed(district_count: int)
signal power_setup_completed(plant_count: int)

## Generation targets
const TARGET_GENERATION_TIME_MS := 5000.0  ## <5 seconds
const TARGET_MEMORY_MB := 100              ## <100MB
const GRID_SIZE := 512

## Sub-generators
var _city_generator: ProceduralCityGenerator = null
var _voxel_converter: VoxelConverter = null

## Runtime managers
var _district_manager: DistrictZoneManager = null
var _power_manager: PowerManager = null

## Generated data
var _city_layout: CityLayout = null
var _voxel_data: Dictionary = {}
var _is_generated := false

## Statistics
var _generation_time_ms := 0.0
var _memory_usage_mb := 0.0


func _init() -> void:
	_city_generator = ProceduralCityGenerator.new()
	_voxel_converter = VoxelConverter.new()
	_district_manager = DistrictZoneManager.new()
	_power_manager = PowerManager.new()

	# Connect generator signals
	_city_generator.phase_started.connect(_on_phase_started)
	_city_generator.phase_completed.connect(_on_phase_completed)


## Generate complete city with seed.
func generate(seed_value: int = 0) -> bool:
	var actual_seed := seed_value if seed_value != 0 else Time.get_ticks_msec()
	var start_time := Time.get_ticks_msec()

	city_generation_started.emit(actual_seed)

	# Phase 1: Generate city layout
	city_generation_progress.emit("City Layout", 0.0)
	_city_layout = _city_generator.generate_city(actual_seed)

	if _city_layout == null or not _city_layout.is_valid():
		city_generation_failed.emit("City layout generation failed")
		return false

	city_generation_progress.emit("City Layout", 1.0)

	# Phase 2: Convert to voxels
	city_generation_progress.emit("Voxel Conversion", 0.0)
	var power_positions := _city_layout.reactor_positions + _city_layout.substation_positions
	_voxel_data = _voxel_converter.convert_buildings_to_voxels(
		_city_layout.building_grid,
		power_positions,
		actual_seed + 10000
	)

	if _voxel_data.is_empty():
		city_generation_failed.emit("Voxel conversion failed")
		return false

	city_generation_progress.emit("Voxel Conversion", 1.0)

	# Phase 3: Setup districts
	city_generation_progress.emit("District Setup", 0.0)
	_setup_districts()
	city_generation_progress.emit("District Setup", 1.0)

	# Phase 4: Setup power grid
	city_generation_progress.emit("Power Grid Setup", 0.0)
	_setup_power_grid()
	city_generation_progress.emit("Power Grid Setup", 1.0)

	# Calculate statistics
	_generation_time_ms = Time.get_ticks_msec() - start_time
	_memory_usage_mb = _estimate_memory_usage()
	_is_generated = true

	# Emit completion
	var city_data := get_city_data()
	city_generation_completed.emit(city_data)

	return true


## Setup districts from generated layout.
func _setup_districts() -> void:
	_district_manager.initialize_from_zones(
		_city_layout.zone_grid,
		_city_layout.affinity_grid
	)

	district_setup_completed.emit(_district_manager.get_district_count())


## Setup power grid from generated layout.
func _setup_power_grid() -> void:
	var power_data := {
		"reactors": _city_layout.reactor_positions,
		"substations": _city_layout.substation_positions,
		"solar_panels": _city_layout.solar_positions,
		"connections": _city_layout.power_connections
	}

	_power_manager.initialize_from_power_grid(power_data)

	# Register districts for power tracking
	var districts: Dictionary = _district_manager.get_all_districts()
	for district_id in districts:
		var district: DistrictZone = districts[district_id]
		# Base consumption on zone type and size
		var consumption := float(district.zones.size()) * 10.0
		_power_manager.register_district(district_id, consumption)

	power_setup_completed.emit(_power_manager.get_statistics()["total_plants"])


## Estimate memory usage.
func _estimate_memory_usage() -> float:
	var bytes := 0

	# Zone grids (16x16 * 3 grids * 4 bytes)
	bytes += 16 * 16 * 3 * 4

	# Building grid (512x512 * 4 bytes)
	bytes += 512 * 512 * 4

	# Voxel data (estimate based on count)
	var voxel_count: int = _voxel_data.get("voxel_count", 0)
	bytes += voxel_count * 64  # ~64 bytes per voxel state

	# Convert to MB
	return float(bytes) / (1024.0 * 1024.0)


## Update city systems (call each frame).
func update(delta: float, unit_positions: Dictionary = {}) -> void:
	if not _is_generated:
		return

	_power_manager.update(delta)
	_district_manager.update_capture(delta, unit_positions)


## Get complete city data.
func get_city_data() -> Dictionary:
	return {
		"seed": _city_layout.generation_seed if _city_layout else 0,
		"layout": _city_layout.to_dict() if _city_layout else {},
		"voxel_count": _voxel_data.get("voxel_count", 0),
		"districts": _district_manager.to_dict(),
		"power": _power_manager.to_dict(),
		"statistics": get_statistics()
	}


## Get city layout.
func get_layout() -> CityLayout:
	return _city_layout


## Get voxel data.
func get_voxel_data() -> Dictionary:
	return _voxel_data


## Get voxel converter.
func get_voxel_converter() -> VoxelConverter:
	return _voxel_converter


## Get district manager.
func get_district_manager() -> DistrictZoneManager:
	return _district_manager


## Get power manager.
func get_power_manager() -> PowerManager:
	return _power_manager


## Get zone at position.
func get_zone_at(x: int, y: int) -> int:
	if _city_layout == null:
		return 0
	return _city_layout.get_zone_at(x, y)


## Get building at position.
func get_building_at(x: int, y: int) -> int:
	if _city_layout == null:
		return 0
	return _city_layout.get_building_at(x, y)


## Get voxel at 3D position.
func get_voxel_at(x: int, y: int, z: int) -> VoxelState:
	return _voxel_converter.get_voxel_at(x, y, z)


## Get district at position.
func get_district_at(position: Vector3) -> Variant:
	return _district_manager.get_district_at_position(position)


## Apply damage at position.
func apply_damage(position: Vector3, damage: float, radius: float) -> Dictionary:
	var result := {
		"voxels_destroyed": 0,
		"lines_damaged": 0
	}

	# Damage voxels
	result["voxels_destroyed"] = _voxel_converter.damage_voxels_in_radius(position, radius, damage)

	# Damage power lines
	result["lines_damaged"] = _power_manager.damage_line(position, damage, radius)

	return result


## Check if city is generated.
func is_generated() -> bool:
	return _is_generated


## Get generation statistics.
func get_statistics() -> Dictionary:
	return {
		"is_generated": _is_generated,
		"generation_time_ms": _generation_time_ms,
		"memory_usage_mb": _memory_usage_mb,
		"target_time_ms": TARGET_GENERATION_TIME_MS,
		"target_memory_mb": TARGET_MEMORY_MB,
		"meets_time_target": _generation_time_ms <= TARGET_GENERATION_TIME_MS,
		"meets_memory_target": _memory_usage_mb <= TARGET_MEMORY_MB,
		"grid_size": GRID_SIZE,
		"voxel_count": _voxel_data.get("voxel_count", 0),
		"building_count": _voxel_data.get("building_count", 0),
		"district_count": _district_manager.get_district_count() if _district_manager else 0,
		"power_generation": _power_manager.get_total_generation() if _power_manager else 0
	}


## Signal handlers.
func _on_phase_started(phase_name: String) -> void:
	city_generation_progress.emit(phase_name, 0.0)


func _on_phase_completed(phase_name: String, time_ms: float) -> void:
	city_generation_progress.emit(phase_name, 1.0)


## Serialize complete city state.
func to_dict() -> Dictionary:
	return {
		"layout": _city_layout.to_dict() if _city_layout else {},
		"voxels_damaged": _voxel_converter.serialize_damaged_voxels(),
		"districts": _district_manager.to_dict(),
		"power": _power_manager.to_dict(),
		"generation_time_ms": _generation_time_ms,
		"memory_usage_mb": _memory_usage_mb,
		"is_generated": _is_generated
	}


## Deserialize city state.
func from_dict(data: Dictionary) -> void:
	# Restore layout
	if data.has("layout"):
		_city_layout = CityLayout.new()
		_city_layout.from_dict(data["layout"])

		# Regenerate voxels from layout
		if _city_layout.is_valid():
			var power_positions := _city_layout.reactor_positions + _city_layout.substation_positions
			_voxel_data = _voxel_converter.convert_buildings_to_voxels(
				_city_layout.building_grid,
				power_positions,
				_city_layout.generation_seed + 10000
			)

			# Apply saved damage
			if data.has("voxels_damaged"):
				_voxel_converter.deserialize_damaged_voxels(data["voxels_damaged"])

	# Restore districts
	if data.has("districts"):
		_district_manager.from_dict(data["districts"])

	# Restore power
	if data.has("power"):
		_power_manager.from_dict(data["power"])

	_generation_time_ms = data.get("generation_time_ms", 0.0)
	_memory_usage_mb = data.get("memory_usage_mb", 0.0)
	_is_generated = data.get("is_generated", false)


## Clear city data.
func clear() -> void:
	_city_layout = null
	_voxel_data.clear()
	_voxel_converter.clear()
	_is_generated = false
	_generation_time_ms = 0.0
	_memory_usage_mb = 0.0
