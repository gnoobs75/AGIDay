class_name WaveDifficultyCalculator
extends RefCounted
## WaveDifficultyCalculator computes difficulty parameters for waves.
## Considers wave number, faction performance, and player strength.

signal difficulty_calculated(wave_number: int, params: Dictionary)

## Difficulty scaling modes
enum ScalingMode {
	LINEAR = 0,      ## Linear difficulty increase
	EXPONENTIAL = 1, ## Exponential difficulty curve
	ADAPTIVE = 2     ## Adapts based on player performance
}

## Base units for wave 1
const BASE_UNITS := 50

## Growth rate per wave (exponential mode)
const EXPONENTIAL_GROWTH := 1.15

## Linear growth per wave
const LINEAR_GROWTH := 10

## Adaptive adjustment range
const ADAPTIVE_MIN_MULT := 0.5
const ADAPTIVE_MAX_MULT := 2.0

## Current scaling mode
var scaling_mode: int = ScalingMode.EXPONENTIAL

## Global difficulty multiplier
var difficulty_multiplier: float = 1.0

## Player performance history for adaptive scaling
var _performance_history: Array[float] = []

## Maximum performance history entries
var _max_history := 10

## Target success rate for adaptive mode
var _target_success_rate := 0.7


func _init() -> void:
	pass


## Calculate difficulty parameters for a wave.
func calculate(wave_number: int, faction_performance: Dictionary = {}) -> Dictionary:
	var params := {
		"wave_number": wave_number,
		"unit_count": _calculate_unit_count(wave_number),
		"health_multiplier": _calculate_health_multiplier(wave_number),
		"damage_multiplier": _calculate_damage_multiplier(wave_number),
		"speed_multiplier": _calculate_speed_multiplier(wave_number),
		"composition": _calculate_composition(wave_number),
		"spawn_duration": _calculate_spawn_duration(wave_number),
		"is_boss_wave": (wave_number % 10) == 0
	}

	# Apply adaptive adjustments if enabled
	if scaling_mode == ScalingMode.ADAPTIVE and not faction_performance.is_empty():
		params = _apply_adaptive_adjustment(params, faction_performance)

	# Apply global multiplier
	params["unit_count"] = int(params["unit_count"] * difficulty_multiplier)

	difficulty_calculated.emit(wave_number, params)
	return params


## Calculate unit count for wave.
func _calculate_unit_count(wave_number: int) -> int:
	match scaling_mode:
		ScalingMode.LINEAR:
			return BASE_UNITS + (wave_number - 1) * LINEAR_GROWTH
		ScalingMode.EXPONENTIAL, ScalingMode.ADAPTIVE:
			return int(BASE_UNITS * pow(EXPONENTIAL_GROWTH, wave_number - 1))

	return BASE_UNITS


## Calculate health multiplier for wave.
func _calculate_health_multiplier(wave_number: int) -> float:
	# Gradual health increase
	return 1.0 + (wave_number - 1) * 0.05


## Calculate damage multiplier for wave.
func _calculate_damage_multiplier(wave_number: int) -> float:
	# Slower damage scaling
	return 1.0 + (wave_number - 1) * 0.03


## Calculate speed multiplier for wave.
func _calculate_speed_multiplier(wave_number: int) -> float:
	# Cap speed increases
	return minf(1.0 + (wave_number - 1) * 0.02, 1.5)


## Calculate unit composition for wave.
func _calculate_composition(wave_number: int) -> Dictionary:
	var basic_ratio := maxf(0.3, 0.6 - wave_number * 0.02)
	var ranged_ratio := minf(0.4, 0.25 + wave_number * 0.01)
	var heavy_ratio := 1.0 - basic_ratio - ranged_ratio

	return {
		"basic": basic_ratio,
		"ranged": ranged_ratio,
		"heavy": heavy_ratio
	}


## Calculate spawn duration for wave.
func _calculate_spawn_duration(wave_number: int) -> float:
	# Longer spawn duration for later waves
	return 10.0 + wave_number * 0.5


## Apply adaptive difficulty adjustment.
func _apply_adaptive_adjustment(params: Dictionary, faction_performance: Dictionary) -> Dictionary:
	var adjusted := params.duplicate()

	# Calculate recent success rate
	var success_rate := _calculate_success_rate(faction_performance)
	_performance_history.append(success_rate)

	# Keep history limited
	while _performance_history.size() > _max_history:
		_performance_history.pop_front()

	# Calculate average performance
	var avg_performance := 0.0
	for perf in _performance_history:
		avg_performance += perf
	avg_performance /= _performance_history.size()

	# Adjust difficulty based on performance vs target
	var adjustment := 1.0
	if avg_performance > _target_success_rate + 0.1:
		# Player doing too well, increase difficulty
		adjustment = lerpf(1.0, ADAPTIVE_MAX_MULT, (avg_performance - _target_success_rate) / 0.3)
	elif avg_performance < _target_success_rate - 0.1:
		# Player struggling, decrease difficulty
		adjustment = lerpf(ADAPTIVE_MIN_MULT, 1.0, avg_performance / _target_success_rate)

	# Apply adjustment to unit count
	adjusted["unit_count"] = int(adjusted["unit_count"] * clampf(adjustment, ADAPTIVE_MIN_MULT, ADAPTIVE_MAX_MULT))
	adjusted["adaptive_multiplier"] = adjustment

	return adjusted


## Calculate success rate from faction performance.
func _calculate_success_rate(faction_performance: Dictionary) -> float:
	var total_damage := 0.0
	var player_damage := 0.0

	for faction_id in faction_performance:
		var damage: float = faction_performance[faction_id].get("damage_dealt", 0.0)
		total_damage += damage

		# Assume player factions are not "enemy"
		if faction_id != "enemy":
			player_damage += damage

	if total_damage <= 0:
		return 0.5

	return player_damage / total_damage


## Set scaling mode.
func set_scaling_mode(mode: int) -> void:
	scaling_mode = mode


## Set difficulty multiplier.
func set_difficulty_multiplier(mult: float) -> void:
	difficulty_multiplier = clampf(mult, 0.1, 10.0)


## Set target success rate for adaptive mode.
func set_target_success_rate(rate: float) -> void:
	_target_success_rate = clampf(rate, 0.3, 0.9)


## Clear performance history.
func clear_history() -> void:
	_performance_history.clear()


## Get current adaptive multiplier.
func get_adaptive_multiplier() -> float:
	if _performance_history.is_empty():
		return 1.0

	var avg_performance := 0.0
	for perf in _performance_history:
		avg_performance += perf
	avg_performance /= _performance_history.size()

	if avg_performance > _target_success_rate + 0.1:
		return lerpf(1.0, ADAPTIVE_MAX_MULT, (avg_performance - _target_success_rate) / 0.3)
	elif avg_performance < _target_success_rate - 0.1:
		return lerpf(ADAPTIVE_MIN_MULT, 1.0, avg_performance / _target_success_rate)

	return 1.0


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"scaling_mode": scaling_mode,
		"difficulty_multiplier": difficulty_multiplier,
		"performance_history": _performance_history.duplicate(),
		"target_success_rate": _target_success_rate
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	scaling_mode = data.get("scaling_mode", ScalingMode.EXPONENTIAL)
	difficulty_multiplier = data.get("difficulty_multiplier", 1.0)
	_target_success_rate = data.get("target_success_rate", 0.7)

	_performance_history.clear()
	for val in data.get("performance_history", []):
		_performance_history.append(float(val))


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"mode": _get_mode_name(),
		"multiplier": difficulty_multiplier,
		"adaptive_mult": get_adaptive_multiplier(),
		"history_size": _performance_history.size()
	}


## Get mode name.
func _get_mode_name() -> String:
	match scaling_mode:
		ScalingMode.LINEAR: return "LINEAR"
		ScalingMode.EXPONENTIAL: return "EXPONENTIAL"
		ScalingMode.ADAPTIVE: return "ADAPTIVE"
	return "UNKNOWN"
