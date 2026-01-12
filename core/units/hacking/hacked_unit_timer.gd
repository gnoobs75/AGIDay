class_name HackedUnitTimer
extends RefCounted
## HackedUnitTimer tracks hacking duration and triggers auto-unhacking.

signal hack_progress_updated(unit_id: int, progress: float, remaining: float)
signal hack_expired(unit_id: int)
signal hack_extended(unit_id: int, new_duration: float)

## Default hack duration (seconds)
const DEFAULT_DURATION := 30.0

## Active timers (unit_id -> timer_data)
var _timers: Dictionary = {}


func _init() -> void:
	pass


## Start timer for hacked unit.
func start_timer(unit_id: int, duration: float = DEFAULT_DURATION) -> void:
	_timers[unit_id] = {
		"total_duration": duration,
		"remaining": duration,
		"start_time": Time.get_ticks_msec()
	}


## Update all timers.
func update(delta: float) -> Array[int]:
	var expired: Array[int] = []

	for unit_id in _timers:
		_timers[unit_id]["remaining"] -= delta

		var remaining: float = _timers[unit_id]["remaining"]
		var total: float = _timers[unit_id]["total_duration"]
		var progress := 1.0 - (remaining / total) if total > 0 else 1.0

		hack_progress_updated.emit(unit_id, progress, remaining)

		if remaining <= 0:
			expired.append(unit_id)

	# Handle expired timers
	for unit_id in expired:
		hack_expired.emit(unit_id)
		_timers.erase(unit_id)

	return expired


## Stop timer (unit unhacked or destroyed).
func stop_timer(unit_id: int) -> void:
	_timers.erase(unit_id)


## Extend hack duration.
func extend_duration(unit_id: int, additional_time: float) -> void:
	if _timers.has(unit_id):
		_timers[unit_id]["remaining"] += additional_time
		_timers[unit_id]["total_duration"] += additional_time
		hack_extended.emit(unit_id, _timers[unit_id]["remaining"])


## Get remaining time.
func get_remaining_time(unit_id: int) -> float:
	var timer_data: Dictionary = _timers.get(unit_id, {})
	return timer_data.get("remaining", 0.0)


## Get hack progress (0.0 = just hacked, 1.0 = about to expire).
func get_hack_progress(unit_id: int) -> float:
	var timer_data: Dictionary = _timers.get(unit_id, {})
	if timer_data.is_empty():
		return 0.0

	var remaining: float = timer_data.get("remaining", 0.0)
	var total: float = timer_data.get("total_duration", DEFAULT_DURATION)

	return 1.0 - (remaining / total) if total > 0 else 1.0


## Check if unit has active timer.
func has_timer(unit_id: int) -> bool:
	return _timers.has(unit_id)


## Get all timed units.
func get_timed_units() -> Array[int]:
	var result: Array[int] = []
	for unit_id in _timers:
		result.append(unit_id)
	return result


## Clear all timers.
func clear() -> void:
	_timers.clear()


## Get timer count.
func get_timer_count() -> int:
	return _timers.size()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"timers": _timers.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_timers = data.get("timers", {}).duplicate(true)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var timer_list: Array[Dictionary] = []
	for unit_id in _timers:
		timer_list.append({
			"unit_id": unit_id,
			"remaining": _timers[unit_id]["remaining"],
			"progress": get_hack_progress(unit_id)
		})

	return {
		"active_timers": _timers.size(),
		"timers": timer_list
	}
