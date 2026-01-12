class_name WaveConfiguration
extends RefCounted
## WaveConfiguration defines all parameters for a wave spawn.
## Supports deterministic spawning through seeded RNG.

## Wave number (1-based)
var wave_number: int = 1

## Faction that spawns this wave
var faction: String = ""

## Base unit count before difficulty scaling
var base_unit_count: int = 10

## Calculated unit count after difficulty
var unit_count: int = 10

## Unit composition (unit_type -> percentage 0.0-1.0)
var unit_composition: Dictionary = {}

## Spawn locations (Array of Vector3)
var spawn_locations: Array[Vector3] = []

## Spawn timing configuration
var spawn_timing: WaveSpawnTiming = null

## Difficulty multiplier
var difficulty_multiplier: float = 1.0

## Seed for deterministic spawning
var seed: int = 0

## Wave-specific modifiers
var modifiers: Dictionary = {}

## Whether this is a boss wave
var is_boss_wave: bool = false

## Boss unit type (if boss wave)
var boss_unit_type: String = ""

## Growth rate per wave (1.15 = 15% more units per wave)
const GROWTH_RATE := 1.15


func _init() -> void:
	spawn_timing = WaveSpawnTiming.new()


## Initialize wave with parameters.
func initialize(p_wave_number: int, p_faction: String, p_base_count: int, p_seed: int = 0) -> void:
	wave_number = p_wave_number
	faction = p_faction
	base_unit_count = p_base_count
	seed = p_seed if p_seed != 0 else _generate_seed()

	# Calculate unit count with exponential growth
	unit_count = int(base_unit_count * pow(GROWTH_RATE, wave_number - 1) * difficulty_multiplier)

	# Set boss wave every 10 waves
	is_boss_wave = (wave_number % 10) == 0


## Generate deterministic seed.
func _generate_seed() -> int:
	return hash(str(wave_number) + faction)


## Set unit composition.
func set_composition(composition: Dictionary) -> void:
	unit_composition = composition.duplicate()
	_validate_composition()


## Validate composition percentages sum to 1.0.
func _validate_composition() -> void:
	var total := 0.0
	for unit_type in unit_composition:
		total += unit_composition[unit_type]

	if absf(total - 1.0) > 0.01:
		# Normalize
		for unit_type in unit_composition:
			unit_composition[unit_type] /= total


## Add spawn location.
func add_spawn_location(location: Vector3) -> void:
	spawn_locations.append(location)


## Set spawn locations.
func set_spawn_locations(locations: Array[Vector3]) -> void:
	spawn_locations = locations.duplicate()


## Get units to spawn by type.
func get_units_by_type() -> Dictionary:
	var result := {}
	var remaining := unit_count

	for unit_type in unit_composition:
		var count := int(unit_count * unit_composition[unit_type])
		result[unit_type] = count
		remaining -= count

	# Distribute remaining units
	if remaining > 0 and not result.is_empty():
		var first_type: String = result.keys()[0]
		result[first_type] += remaining

	return result


## Set modifier.
func set_modifier(key: String, value: float) -> void:
	modifiers[key] = value


## Get modifier.
func get_modifier(key: String, default: float = 1.0) -> float:
	return modifiers.get(key, default)


## Validate configuration.
func validate() -> bool:
	if wave_number < 1:
		return false
	if faction.is_empty():
		return false
	if base_unit_count <= 0:
		return false
	if unit_composition.is_empty():
		return false
	if spawn_locations.is_empty():
		return false
	return true


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var locations_data: Array = []
	for loc in spawn_locations:
		locations_data.append({"x": loc.x, "y": loc.y, "z": loc.z})

	return {
		"wave_number": wave_number,
		"faction": faction,
		"base_unit_count": base_unit_count,
		"unit_count": unit_count,
		"unit_composition": unit_composition.duplicate(),
		"spawn_locations": locations_data,
		"spawn_timing": spawn_timing.to_dict() if spawn_timing != null else {},
		"difficulty_multiplier": difficulty_multiplier,
		"seed": seed,
		"modifiers": modifiers.duplicate(),
		"is_boss_wave": is_boss_wave,
		"boss_unit_type": boss_unit_type
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> WaveConfiguration:
	var config := WaveConfiguration.new()
	config.wave_number = data.get("wave_number", 1)
	config.faction = data.get("faction", "")
	config.base_unit_count = data.get("base_unit_count", 10)
	config.unit_count = data.get("unit_count", 10)
	config.unit_composition = data.get("unit_composition", {}).duplicate()
	config.difficulty_multiplier = data.get("difficulty_multiplier", 1.0)
	config.seed = data.get("seed", 0)
	config.modifiers = data.get("modifiers", {}).duplicate()
	config.is_boss_wave = data.get("is_boss_wave", false)
	config.boss_unit_type = data.get("boss_unit_type", "")

	var locations_data: Array = data.get("spawn_locations", [])
	config.spawn_locations.clear()
	for loc_data in locations_data:
		config.spawn_locations.append(Vector3(
			loc_data.get("x", 0.0),
			loc_data.get("y", 0.0),
			loc_data.get("z", 0.0)
		))

	var timing_data: Dictionary = data.get("spawn_timing", {})
	if not timing_data.is_empty():
		config.spawn_timing = WaveSpawnTiming.from_dict(timing_data)

	return config


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"wave": wave_number,
		"faction": faction,
		"units": unit_count,
		"base_units": base_unit_count,
		"difficulty": difficulty_multiplier,
		"boss": is_boss_wave,
		"spawn_points": spawn_locations.size()
	}
