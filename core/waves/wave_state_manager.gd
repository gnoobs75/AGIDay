class_name WaveStateManager
extends RefCounted
## WaveStateManager provides thread-safe access to wave state data.
## Manages wave history, current progress, and persistence.

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int, history: WaveHistory)
signal state_saved()
signal state_loaded()

## Current wave progress
var current_progress: WaveProgress = null

## Wave history (most recent first)
var history: Array[WaveHistory] = []

## Maximum history entries to keep
var max_history_size: int = 100

## Current wave number
var current_wave: int = 0

## Highest wave reached
var highest_wave: int = 0

## Total waves completed
var total_waves_completed: int = 0

## Mutex for thread safety
var _mutex: Mutex = null

## Whether state has unsaved changes
var _dirty: bool = false


func _init() -> void:
	_mutex = Mutex.new()


## Start a new wave.
func start_wave(config: WaveConfiguration) -> WaveProgress:
	_mutex.lock()

	current_progress = WaveProgress.new()
	current_progress.start_wave(config)
	current_wave = config.wave_number

	if current_wave > highest_wave:
		highest_wave = current_wave

	_dirty = true
	_mutex.unlock()

	wave_started.emit(current_wave)
	return current_progress


## Complete current wave.
func complete_wave() -> WaveHistory:
	_mutex.lock()

	if current_progress == null:
		_mutex.unlock()
		return null

	var wave_history := WaveHistory.from_progress(current_progress)
	_add_history(wave_history)

	total_waves_completed += 1
	_dirty = true

	var completed_wave := current_wave
	current_progress = null

	_mutex.unlock()

	wave_completed.emit(completed_wave, wave_history)
	return wave_history


## Add history entry (internal).
func _add_history(entry: WaveHistory) -> void:
	history.insert(0, entry)

	# Trim if over max
	while history.size() > max_history_size:
		history.pop_back()


## Get current progress (thread-safe).
func get_current_progress() -> WaveProgress:
	_mutex.lock()
	var progress := current_progress
	_mutex.unlock()
	return progress


## Get history (thread-safe copy).
func get_history() -> Array[WaveHistory]:
	_mutex.lock()
	var copy: Array[WaveHistory] = history.duplicate()
	_mutex.unlock()
	return copy


## Get history entry by wave number.
func get_history_for_wave(wave_number: int) -> WaveHistory:
	_mutex.lock()
	for entry in history:
		if entry.wave_number == wave_number:
			_mutex.unlock()
			return entry
	_mutex.unlock()
	return null


## Get statistics.
func get_statistics() -> Dictionary:
	_mutex.lock()

	var total_kills := 0
	var total_spawned := 0
	var total_duration := 0.0
	var successful_waves := 0

	for entry in history:
		total_kills += entry.units_killed
		total_spawned += entry.units_spawned
		total_duration += entry.duration
		if entry.was_successful:
			successful_waves += 1

	var avg_duration := 0.0
	var avg_kill_rate := 0.0
	if history.size() > 0:
		avg_duration = total_duration / history.size()
	if total_spawned > 0:
		avg_kill_rate = float(total_kills) / float(total_spawned)

	var stats := {
		"current_wave": current_wave,
		"highest_wave": highest_wave,
		"total_completed": total_waves_completed,
		"total_kills": total_kills,
		"total_spawned": total_spawned,
		"total_duration": total_duration,
		"successful_waves": successful_waves,
		"average_duration": avg_duration,
		"average_kill_rate": avg_kill_rate,
		"history_size": history.size()
	}

	_mutex.unlock()
	return stats


## Check if state needs saving.
func needs_save() -> bool:
	_mutex.lock()
	var dirty := _dirty
	_mutex.unlock()
	return dirty


## Mark as saved.
func mark_saved() -> void:
	_mutex.lock()
	_dirty = false
	_mutex.unlock()
	state_saved.emit()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	_mutex.lock()

	var history_data: Array = []
	for entry in history:
		history_data.append(entry.to_dict())

	var data := {
		"current_wave": current_wave,
		"highest_wave": highest_wave,
		"total_waves_completed": total_waves_completed,
		"history": history_data,
		"current_progress": current_progress.to_dict() if current_progress != null else {}
	}

	_mutex.unlock()
	return data


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_mutex.lock()

	current_wave = data.get("current_wave", 0)
	highest_wave = data.get("highest_wave", 0)
	total_waves_completed = data.get("total_waves_completed", 0)

	history.clear()
	for entry_data in data.get("history", []):
		history.append(WaveHistory.from_dict(entry_data))

	var progress_data: Dictionary = data.get("current_progress", {})
	if not progress_data.is_empty():
		current_progress = WaveProgress.from_dict(progress_data)
	else:
		current_progress = null

	_dirty = false
	_mutex.unlock()

	state_loaded.emit()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"current_wave": current_wave,
		"highest_wave": highest_wave,
		"completed": total_waves_completed,
		"history_size": history.size(),
		"in_progress": current_progress != null,
		"dirty": _dirty
	}
