class_name DifficultyCalculator
extends RefCounted
## DifficultyCalculator computes adaptive difficulty based on faction performance.
## Ensures balanced gameplay by adjusting enemy spawns based on player strength.

signal difficulty_calculated(faction_id: int, multiplier: float)
signal power_levels_updated(power_levels: Dictionary)

## Power level formula weights
const WEIGHT_UNITS := 0.4
const WEIGHT_RESOURCES := 0.3
const WEIGHT_DISTRICTS := 0.2
const WEIGHT_RESEARCH := 0.1

## Resource normalization
const RESOURCE_DIVISOR := 1000.0

## Base unit formula
const BASE_UNITS := 50.0
const GROWTH_RATE := 1.15  ## 15% increase per wave

## Difficulty multiplier ranges
const MIN_BELOW_AVERAGE_MULT := 0.8
const MAX_BELOW_AVERAGE_MULT := 0.95
const AVERAGE_MULT := 1.0
const MIN_ABOVE_AVERAGE_MULT := 1.05
const MAX_ABOVE_AVERAGE_MULT := 1.2

## Power level thresholds
const BELOW_AVERAGE_THRESHOLD := 0.8   ## Below 80% of average
const ABOVE_AVERAGE_THRESHOLD := 1.2   ## Above 120% of average

## Cache
var _cached_power_levels: Dictionary = {}
var _cached_multipliers: Dictionary = {}
var _cache_wave: int = -1

## Configuration
var _total_districts: int = 9
var _max_research_level: int = 10


func _init() -> void:
	pass


## Configure total districts and max research.
func configure(total_districts: int, max_research_level: int) -> void:
	_total_districts = total_districts
	_max_research_level = max_research_level


## Calculate faction power level.
## power = (units * 0.4) + (resources / 1000 * 0.3) + (districts / total * 0.2) + (research / max * 0.1)
func calculate_power_level(faction_data: Dictionary) -> float:
	var units: int = faction_data.get("unit_count", 0)
	var resources: float = faction_data.get("resources", 0.0)
	var districts: int = faction_data.get("district_count", 0)
	var research: int = faction_data.get("research_level", 0)

	var unit_score := float(units) * WEIGHT_UNITS
	var resource_score := (resources / RESOURCE_DIVISOR) * WEIGHT_RESOURCES
	var district_score := (float(districts) / float(maxi(1, _total_districts))) * WEIGHT_DISTRICTS
	var research_score := (float(research) / float(maxi(1, _max_research_level))) * WEIGHT_RESEARCH

	return unit_score + resource_score + district_score + research_score


## Calculate difficulty multiplier for faction.
func calculate_difficulty_multiplier(faction_power: float, average_power: float) -> float:
	if average_power <= 0:
		return AVERAGE_MULT

	var ratio := faction_power / average_power

	if ratio < BELOW_AVERAGE_THRESHOLD:
		# Below average - reduce difficulty (0.8 - 0.95)
		var t := ratio / BELOW_AVERAGE_THRESHOLD  # 0 to 1
		return lerpf(MIN_BELOW_AVERAGE_MULT, MAX_BELOW_AVERAGE_MULT, t)

	elif ratio > ABOVE_AVERAGE_THRESHOLD:
		# Above average - increase difficulty (1.05 - 1.2)
		var excess := (ratio - ABOVE_AVERAGE_THRESHOLD) / (2.0 - ABOVE_AVERAGE_THRESHOLD)
		var t := clampf(excess, 0.0, 1.0)
		return lerpf(MIN_ABOVE_AVERAGE_MULT, MAX_ABOVE_AVERAGE_MULT, t)

	else:
		# Near average - interpolate smoothly
		if ratio < 1.0:
			var t := (ratio - BELOW_AVERAGE_THRESHOLD) / (1.0 - BELOW_AVERAGE_THRESHOLD)
			return lerpf(MAX_BELOW_AVERAGE_MULT, AVERAGE_MULT, t)
		else:
			var t := (ratio - 1.0) / (ABOVE_AVERAGE_THRESHOLD - 1.0)
			return lerpf(AVERAGE_MULT, MIN_ABOVE_AVERAGE_MULT, t)


## Calculate base unit count for wave.
## base_units = 50 * (1.15 ^ wave_number)
func calculate_base_unit_count(wave_number: int) -> int:
	return int(BASE_UNITS * pow(GROWTH_RATE, wave_number))


## Calculate final unit count with difficulty multiplier.
func calculate_final_unit_count(wave_number: int, difficulty_multiplier: float) -> int:
	var base := calculate_base_unit_count(wave_number)
	return int(float(base) * difficulty_multiplier)


## Calculate difficulty for all factions.
func calculate_wave_difficulty(wave_number: int, faction_data: Dictionary) -> Dictionary:
	# Check cache
	if wave_number == _cache_wave and not _cached_multipliers.is_empty():
		return _cached_multipliers.duplicate()

	# Calculate power levels for all factions
	var power_levels: Dictionary = {}
	var total_power := 0.0

	for faction_id in faction_data:
		var data: Dictionary = faction_data[faction_id]
		var power := calculate_power_level(data)
		power_levels[faction_id] = power
		total_power += power

	# Calculate average power
	var faction_count := power_levels.size()
	var average_power := total_power / float(maxi(1, faction_count))

	# Calculate multipliers
	var multipliers: Dictionary = {}
	for faction_id in power_levels:
		var faction_power: float = power_levels[faction_id]
		var multiplier := calculate_difficulty_multiplier(faction_power, average_power)
		multipliers[faction_id] = multiplier
		difficulty_calculated.emit(faction_id, multiplier)

	# Cache results
	_cached_power_levels = power_levels.duplicate()
	_cached_multipliers = multipliers.duplicate()
	_cache_wave = wave_number

	power_levels_updated.emit(power_levels)

	return multipliers


## Calculate unit counts for wave.
func calculate_wave_units(wave_number: int, faction_data: Dictionary) -> Dictionary:
	var multipliers := calculate_wave_difficulty(wave_number, faction_data)
	var unit_counts: Dictionary = {}

	for faction_id in multipliers:
		var multiplier: float = multipliers[faction_id]
		unit_counts[faction_id] = calculate_final_unit_count(wave_number, multiplier)

	return unit_counts


## Get cached power level for faction.
func get_cached_power_level(faction_id: int) -> float:
	return _cached_power_levels.get(faction_id, 0.0)


## Get cached multiplier for faction.
func get_cached_multiplier(faction_id: int) -> float:
	return _cached_multipliers.get(faction_id, AVERAGE_MULT)


## Get all cached power levels.
func get_all_power_levels() -> Dictionary:
	return _cached_power_levels.duplicate()


## Get all cached multipliers.
func get_all_multipliers() -> Dictionary:
	return _cached_multipliers.duplicate()


## Invalidate cache (call when faction data changes significantly).
func invalidate_cache() -> void:
	_cached_power_levels.clear()
	_cached_multipliers.clear()
	_cache_wave = -1


## Calculate faction-specific difficulty adjustment.
## Some factions may need additional balancing.
func get_faction_weight(faction_id: int) -> float:
	# Faction-specific adjustments
	match faction_id:
		0:  # Aether Swarm - many weak units
			return 1.0
		1:  # OptiForge Legion - balanced
			return 1.0
		2:  # Dynapods Vanguard - agile
			return 1.05
		3:  # LogiBots Colossus - heavy
			return 0.95
		4:  # Human Remnant (NPC)
			return 1.0
	return 1.0


## Calculate adjusted power level with faction weight.
func calculate_adjusted_power_level(faction_id: int, faction_data: Dictionary) -> float:
	var base_power := calculate_power_level(faction_data)
	var faction_weight := get_faction_weight(faction_id)
	return base_power * faction_weight


## Predict difficulty for future wave.
func predict_wave_difficulty(current_wave: int, future_wave: int,
							 current_faction_data: Dictionary,
							 growth_estimate: float = 1.1) -> Dictionary:
	# Estimate future faction data based on growth
	var waves_ahead := future_wave - current_wave
	var growth_factor := pow(growth_estimate, waves_ahead)

	var estimated_data: Dictionary = {}
	for faction_id in current_faction_data:
		var current: Dictionary = current_faction_data[faction_id]
		estimated_data[faction_id] = {
			"unit_count": int(current.get("unit_count", 0) * growth_factor),
			"resources": current.get("resources", 0.0) * growth_factor,
			"district_count": current.get("district_count", 0),  # Districts don't grow predictably
			"research_level": mini(
				int(current.get("research_level", 0) + waves_ahead),
				_max_research_level
			)
		}

	return calculate_wave_difficulty(future_wave, estimated_data)


## Get difficulty description.
func get_difficulty_description(multiplier: float) -> String:
	if multiplier < 0.85:
		return "Very Easy"
	elif multiplier < 0.95:
		return "Easy"
	elif multiplier < 1.05:
		return "Normal"
	elif multiplier < 1.15:
		return "Hard"
	else:
		return "Very Hard"


## Get statistics.
func get_statistics() -> Dictionary:
	var avg_multiplier := 0.0
	var min_multiplier := INF
	var max_multiplier := 0.0

	for faction_id in _cached_multipliers:
		var mult: float = _cached_multipliers[faction_id]
		avg_multiplier += mult
		min_multiplier = minf(min_multiplier, mult)
		max_multiplier = maxf(max_multiplier, mult)

	if not _cached_multipliers.is_empty():
		avg_multiplier /= float(_cached_multipliers.size())

	return {
		"cached_wave": _cache_wave,
		"faction_count": _cached_power_levels.size(),
		"average_multiplier": avg_multiplier,
		"min_multiplier": min_multiplier if min_multiplier < INF else 0.0,
		"max_multiplier": max_multiplier,
		"power_levels": _cached_power_levels.duplicate(),
		"multipliers": _cached_multipliers.duplicate()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"total_districts": _total_districts,
		"max_research_level": _max_research_level,
		"cached_power_levels": _cached_power_levels.duplicate(),
		"cached_multipliers": _cached_multipliers.duplicate(),
		"cache_wave": _cache_wave
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_total_districts = data.get("total_districts", 9)
	_max_research_level = data.get("max_research_level", 10)
	_cached_power_levels = data.get("cached_power_levels", {}).duplicate()
	_cached_multipliers = data.get("cached_multipliers", {}).duplicate()
	_cache_wave = data.get("cache_wave", -1)
