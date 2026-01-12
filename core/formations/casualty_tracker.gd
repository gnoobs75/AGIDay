class_name CasualtyTracker
extends RefCounted
## CasualtyTracker monitors unit losses over a time window.

signal casualty_rate_changed(old_rate: float, new_rate: float)
signal high_casualties_detected(rate: float)

## Time window for casualty calculation (seconds)
const CASUALTY_WINDOW := 10.0

## High casualty threshold
const HIGH_CASUALTY_THRESHOLD := 0.3

## History entries (timestamp, unit_count)
var _history: Array[Dictionary] = []

## Current unit count
var _current_count: int = 0

## Previous count (at window start)
var _previous_count: int = 0

## Current casualty rate
var _casualty_rate: float = 0.0

## Time accumulator
var _time_accumulated: float = 0.0


func _init() -> void:
	pass


## Update with current unit count.
func update(delta: float, unit_count: int) -> void:
	_time_accumulated += delta
	_current_count = unit_count

	# Add history entry every second
	if _time_accumulated >= 1.0:
		_time_accumulated -= 1.0
		_add_history_entry(unit_count)


## Add history entry.
func _add_history_entry(count: int) -> void:
	var timestamp := Time.get_ticks_msec() / 1000.0

	_history.append({
		"timestamp": timestamp,
		"count": count
	})

	# Remove entries outside window
	var cutoff := timestamp - CASUALTY_WINDOW
	while not _history.is_empty() and _history[0]["timestamp"] < cutoff:
		_history.pop_front()

	# Update casualty rate
	_calculate_casualty_rate()


## Calculate casualty rate.
func _calculate_casualty_rate() -> void:
	if _history.size() < 2:
		_casualty_rate = 0.0
		return

	var old_rate := _casualty_rate

	# Get count at start of window
	_previous_count = _history[0]["count"]
	_current_count = _history[_history.size() - 1]["count"]

	if _previous_count <= 0:
		_casualty_rate = 0.0
	else:
		var lost := _previous_count - _current_count
		_casualty_rate = maxf(0.0, float(lost) / float(_previous_count))

	if absf(old_rate - _casualty_rate) > 0.01:
		casualty_rate_changed.emit(old_rate, _casualty_rate)

		if _casualty_rate >= HIGH_CASUALTY_THRESHOLD:
			high_casualties_detected.emit(_casualty_rate)


## Record unit death.
func record_death() -> void:
	_current_count = maxi(0, _current_count - 1)


## Record multiple deaths.
func record_deaths(count: int) -> void:
	_current_count = maxi(0, _current_count - count)


## Get current casualty rate.
func get_casualty_rate() -> float:
	return _casualty_rate


## Get current unit count.
func get_current_count() -> int:
	return _current_count


## Get previous count (at window start).
func get_previous_count() -> int:
	return _previous_count


## Check if under heavy casualties.
func is_under_heavy_fire() -> bool:
	return _casualty_rate >= HIGH_CASUALTY_THRESHOLD


## Reset tracker.
func reset(initial_count: int = 0) -> void:
	_history.clear()
	_current_count = initial_count
	_previous_count = initial_count
	_casualty_rate = 0.0
	_time_accumulated = 0.0


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"history": _history.duplicate(),
		"current_count": _current_count,
		"previous_count": _previous_count,
		"casualty_rate": _casualty_rate,
		"time_accumulated": _time_accumulated
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_history.clear()
	for entry in data.get("history", []):
		_history.append(entry.duplicate())

	_current_count = data.get("current_count", 0)
	_previous_count = data.get("previous_count", 0)
	_casualty_rate = data.get("casualty_rate", 0.0)
	_time_accumulated = data.get("time_accumulated", 0.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"casualty_rate": "%.1f%%" % (_casualty_rate * 100),
		"current_count": _current_count,
		"previous_count": _previous_count,
		"window_entries": _history.size(),
		"under_heavy_fire": is_under_heavy_fire()
	}
