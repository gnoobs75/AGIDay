class_name BattleIntensityTracker
extends RefCounted
## BattleIntensityTracker calculates combat intensity for the music system.

signal intensity_spike(level: float)
signal combat_started()
signal combat_ended()

## Intensity calculation weights
const WEIGHT_UNIT_COUNT := 0.2
const WEIGHT_COMBAT_EVENTS := 0.3
const WEIGHT_DAMAGE_DEALT := 0.25
const WEIGHT_UNIT_DEATHS := 0.25

## Thresholds
const COMBAT_START_THRESHOLD := 0.15
const COMBAT_END_THRESHOLD := 0.05
const SPIKE_THRESHOLD := 0.3

## Decay rates (per second)
const COMBAT_EVENT_DECAY := 2.0
const DAMAGE_DECAY := 50.0
const DEATH_DECAY := 1.0

## Smoothing
const INTENSITY_SMOOTHING := 5.0  ## Higher = faster response

## Metrics
var _friendly_units := 0
var _enemy_units := 0
var _combat_events := 0.0        ## Decaying counter
var _damage_dealt := 0.0         ## Decaying counter
var _unit_deaths := 0.0          ## Decaying counter

## State
var _current_intensity := 0.0
var _raw_intensity := 0.0
var _in_combat := false
var _peak_intensity := 0.0
var _time_since_peak := 0.0

## Reference values for normalization
const MAX_UNIT_COUNT := 200
const MAX_COMBAT_EVENTS := 20.0
const MAX_DAMAGE := 1000.0
const MAX_DEATHS := 10.0


func _init() -> void:
	pass


## Update tracker each frame.
func update(delta: float) -> void:
	# Decay metrics
	_combat_events = maxf(_combat_events - COMBAT_EVENT_DECAY * delta, 0.0)
	_damage_dealt = maxf(_damage_dealt - DAMAGE_DECAY * delta, 0.0)
	_unit_deaths = maxf(_unit_deaths - DEATH_DECAY * delta, 0.0)

	# Calculate raw intensity
	_calculate_raw_intensity()

	# Smooth intensity
	var intensity_delta := (_raw_intensity - _current_intensity) * INTENSITY_SMOOTHING * delta
	_current_intensity = clampf(_current_intensity + intensity_delta, 0.0, 1.0)

	# Track peaks
	if _current_intensity > _peak_intensity:
		_peak_intensity = _current_intensity
		_time_since_peak = 0.0
		if _current_intensity >= SPIKE_THRESHOLD:
			intensity_spike.emit(_current_intensity)
	else:
		_time_since_peak += delta
		if _time_since_peak > 5.0:
			_peak_intensity = _current_intensity

	# Update combat state
	_update_combat_state()


## Calculate raw intensity from metrics.
func _calculate_raw_intensity() -> void:
	# Unit count contribution
	var total_units := _friendly_units + _enemy_units
	var unit_factor := clampf(float(total_units) / MAX_UNIT_COUNT, 0.0, 1.0)

	# Combat events contribution
	var event_factor := clampf(_combat_events / MAX_COMBAT_EVENTS, 0.0, 1.0)

	# Damage contribution
	var damage_factor := clampf(_damage_dealt / MAX_DAMAGE, 0.0, 1.0)

	# Death contribution
	var death_factor := clampf(_unit_deaths / MAX_DEATHS, 0.0, 1.0)

	# Weighted sum
	_raw_intensity = (
		unit_factor * WEIGHT_UNIT_COUNT +
		event_factor * WEIGHT_COMBAT_EVENTS +
		damage_factor * WEIGHT_DAMAGE_DEALT +
		death_factor * WEIGHT_UNIT_DEATHS
	)

	# Bonus for having enemies present
	if _enemy_units > 0:
		_raw_intensity += 0.05

	_raw_intensity = clampf(_raw_intensity, 0.0, 1.0)


## Update combat state.
func _update_combat_state() -> void:
	var was_in_combat := _in_combat

	if not _in_combat and _current_intensity >= COMBAT_START_THRESHOLD:
		_in_combat = true
		combat_started.emit()
	elif _in_combat and _current_intensity < COMBAT_END_THRESHOLD:
		_in_combat = false
		combat_ended.emit()


## Report unit counts.
func report_unit_counts(friendly: int, enemy: int) -> void:
	_friendly_units = friendly
	_enemy_units = enemy


## Report a combat event (attack, ability use, etc.).
func report_combat_event(weight: float = 1.0) -> void:
	_combat_events += weight


## Report damage dealt.
func report_damage(amount: float) -> void:
	_damage_dealt += amount


## Report a unit death.
func report_death(is_enemy: bool = true) -> void:
	_unit_deaths += 1.0
	if is_enemy:
		_combat_events += 0.5  ## Deaths also count as combat events


## Report an explosion or large event.
func report_explosion() -> void:
	_combat_events += 3.0
	_damage_dealt += 100.0


## Report a wave starting.
func report_wave_start() -> void:
	_combat_events += 2.0


## Report a wave ending.
func report_wave_end() -> void:
	# Quick decay of intensity after wave
	_combat_events *= 0.5
	_damage_dealt *= 0.5


## Get current intensity (0.0 to 1.0).
func get_intensity() -> float:
	return _current_intensity


## Get raw (unsmoothed) intensity.
func get_raw_intensity() -> float:
	return _raw_intensity


## Is currently in combat.
func is_in_combat() -> bool:
	return _in_combat


## Get intensity level as enum-like value.
func get_intensity_level() -> int:
	if _current_intensity >= 0.8:
		return 4  # Extreme
	elif _current_intensity >= 0.6:
		return 3  # Heavy
	elif _current_intensity >= 0.4:
		return 2  # Medium
	elif _current_intensity >= 0.2:
		return 1  # Light
	else:
		return 0  # Calm


## Get intensity level name.
func get_intensity_level_name() -> String:
	match get_intensity_level():
		4: return "extreme"
		3: return "heavy"
		2: return "medium"
		1: return "light"
		_: return "calm"


## Get analytics for debugging.
func get_analytics() -> Dictionary:
	return {
		"current_intensity": _current_intensity,
		"raw_intensity": _raw_intensity,
		"in_combat": _in_combat,
		"friendly_units": _friendly_units,
		"enemy_units": _enemy_units,
		"combat_events": _combat_events,
		"damage_dealt": _damage_dealt,
		"unit_deaths": _unit_deaths,
		"peak_intensity": _peak_intensity,
		"level": get_intensity_level_name()
	}


## Reset all metrics.
func reset() -> void:
	_friendly_units = 0
	_enemy_units = 0
	_combat_events = 0.0
	_damage_dealt = 0.0
	_unit_deaths = 0.0
	_current_intensity = 0.0
	_raw_intensity = 0.0
	_in_combat = false
	_peak_intensity = 0.0
	_time_since_peak = 0.0
