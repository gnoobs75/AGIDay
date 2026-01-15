class_name PerformanceProfiler
extends RefCounted
## PerformanceProfiler monitors and reports game performance metrics.
## Tracks frame times, memory usage, and key system performance.

signal frame_budget_exceeded(system: String, time_ms: float, budget_ms: float)
signal memory_warning(usage_mb: float, threshold_mb: float)
signal benchmark_completed(name: String, results: Dictionary)

## Frame budget allocations (ms)
const BUDGET_TOTAL := 16.67           ## 60fps target
const BUDGET_RENDERING := 8.0
const BUDGET_PHYSICS := 4.0
const BUDGET_AI := 2.0
const BUDGET_ECS := 2.0
const BUDGET_OTHER := 0.67

## Memory thresholds (MB)
const MEMORY_WARNING_MB := 1500.0
const MEMORY_CRITICAL_MB := 1800.0
const MEMORY_TARGET_MB := 2048.0

## Profiling state
var _is_profiling := false
var _profile_start_time := 0

## System timings (current frame)
var _system_times: Dictionary = {}

## Frame history
const HISTORY_SIZE := 60
var _frame_times: Array[float] = []
var _system_histories: Dictionary = {}

## Memory tracking
var _last_memory_check := 0.0
const MEMORY_CHECK_INTERVAL := 1.0    ## Check every second

## Benchmark results
var _benchmarks: Dictionary = {}


func _init() -> void:
	_initialize_histories()


## Initialize history arrays.
func _initialize_histories() -> void:
	_frame_times = []
	_system_histories = {
		"rendering": [],
		"physics": [],
		"ai": [],
		"ecs": [],
		"other": []
	}


## Start profiling a system.
func begin_profile(system: String) -> void:
	_system_times[system] = Time.get_ticks_usec()


## End profiling a system.
func end_profile(system: String) -> void:
	if not _system_times.has(system):
		return

	var start: int = _system_times[system]
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0  # Convert to ms

	_system_times[system] = elapsed

	# Check budget
	var budget := _get_budget_for_system(system)
	if elapsed > budget:
		frame_budget_exceeded.emit(system, elapsed, budget)

	# Add to history
	if _system_histories.has(system):
		_system_histories[system].append(elapsed)
		if _system_histories[system].size() > HISTORY_SIZE:
			_system_histories[system].pop_front()


## Get budget for system.
func _get_budget_for_system(system: String) -> float:
	match system:
		"rendering": return BUDGET_RENDERING
		"physics": return BUDGET_PHYSICS
		"ai": return BUDGET_AI
		"ecs": return BUDGET_ECS
		_: return BUDGET_OTHER


## Record frame time.
func record_frame_time(delta: float) -> void:
	var frame_time := delta * 1000.0  # Convert to ms
	_frame_times.append(frame_time)

	if _frame_times.size() > HISTORY_SIZE:
		_frame_times.pop_front()


## Check memory usage.
func check_memory(delta: float) -> void:
	_last_memory_check += delta
	if _last_memory_check < MEMORY_CHECK_INTERVAL:
		return

	_last_memory_check = 0.0

	var memory_mb := get_memory_usage_mb()

	if memory_mb > MEMORY_CRITICAL_MB:
		memory_warning.emit(memory_mb, MEMORY_CRITICAL_MB)
	elif memory_mb > MEMORY_WARNING_MB:
		memory_warning.emit(memory_mb, MEMORY_WARNING_MB)


## Get current memory usage in MB.
func get_memory_usage_mb() -> float:
	return float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)


## Get peak memory usage in MB.
func get_peak_memory_mb() -> float:
	return float(OS.get_static_memory_peak_usage()) / (1024.0 * 1024.0)


## Get average frame time.
func get_average_frame_time() -> float:
	if _frame_times.is_empty():
		return 0.0

	var total := 0.0
	for time in _frame_times:
		total += time

	return total / float(_frame_times.size())


## Get current FPS.
func get_current_fps() -> float:
	var avg_time := get_average_frame_time()
	if avg_time <= 0:
		return 0.0
	return 1000.0 / avg_time


## Get minimum FPS (worst frame).
func get_min_fps() -> float:
	if _frame_times.is_empty():
		return 0.0

	var max_time := 0.0
	for time in _frame_times:
		max_time = maxf(max_time, time)

	if max_time <= 0:
		return 0.0
	return 1000.0 / max_time


## Get system average time.
func get_system_average(system: String) -> float:
	if not _system_histories.has(system) or _system_histories[system].is_empty():
		return 0.0

	var history: Array = _system_histories[system]
	var total := 0.0
	for time in history:
		total += time

	return total / float(history.size())


## Run benchmark.
func run_benchmark(name: String, callback: Callable, iterations: int = 100) -> Dictionary:
	var times: Array[float] = []

	for i in iterations:
		var start := Time.get_ticks_usec()
		callback.call()
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		times.append(elapsed)

	var total := 0.0
	var min_time := INF
	var max_time := 0.0

	for time in times:
		total += time
		min_time = minf(min_time, time)
		max_time = maxf(max_time, time)

	var results := {
		"name": name,
		"iterations": iterations,
		"total_ms": total,
		"average_ms": total / float(iterations),
		"min_ms": min_time,
		"max_ms": max_time
	}

	_benchmarks[name] = results
	benchmark_completed.emit(name, results)

	return results


## Get frame budget status.
func get_budget_status() -> Dictionary:
	var total_used := 0.0

	var status := {}
	for system in ["rendering", "physics", "ai", "ecs", "other"]:
		var avg := get_system_average(system)
		var budget := _get_budget_for_system(system)
		status[system] = {
			"used_ms": avg,
			"budget_ms": budget,
			"percent": (avg / budget * 100.0) if budget > 0 else 0.0
		}
		total_used += avg

	status["total"] = {
		"used_ms": total_used,
		"budget_ms": BUDGET_TOTAL,
		"percent": (total_used / BUDGET_TOTAL * 100.0)
	}

	return status


## Get performance grade.
func get_performance_grade() -> String:
	var fps := get_current_fps()
	var memory := get_memory_usage_mb()

	if fps >= 60 and memory < MEMORY_WARNING_MB:
		return "A"
	elif fps >= 55 and memory < MEMORY_CRITICAL_MB:
		return "B"
	elif fps >= 45 and memory < MEMORY_TARGET_MB:
		return "C"
	elif fps >= 30:
		return "D"
	else:
		return "F"


## Check if meeting performance targets.
func is_meeting_targets() -> bool:
	return get_current_fps() >= 60 and get_memory_usage_mb() < MEMORY_TARGET_MB


## Get full statistics.
func get_statistics() -> Dictionary:
	return {
		"fps": {
			"current": get_current_fps(),
			"average": 1000.0 / get_average_frame_time() if get_average_frame_time() > 0 else 0.0,
			"minimum": get_min_fps(),
			"target": 60.0
		},
		"frame_time": {
			"average_ms": get_average_frame_time(),
			"target_ms": BUDGET_TOTAL
		},
		"memory": {
			"current_mb": get_memory_usage_mb(),
			"peak_mb": get_peak_memory_mb(),
			"target_mb": MEMORY_TARGET_MB,
			"warning_mb": MEMORY_WARNING_MB
		},
		"budget_status": get_budget_status(),
		"grade": get_performance_grade(),
		"meeting_targets": is_meeting_targets(),
		"benchmarks": _benchmarks.duplicate()
	}


## Reset statistics.
func reset() -> void:
	_initialize_histories()
	_system_times.clear()
	_benchmarks.clear()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"frame_times": _frame_times.duplicate(),
		"system_histories": _system_histories.duplicate(true),
		"benchmarks": _benchmarks.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_frame_times = data.get("frame_times", []).duplicate()
	_system_histories = data.get("system_histories", {}).duplicate(true)
	_benchmarks = data.get("benchmarks", {}).duplicate(true)
