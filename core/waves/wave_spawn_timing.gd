class_name WaveSpawnTiming
extends RefCounted
## WaveSpawnTiming controls how units are spawned over time during a wave.

## Timing modes
enum Mode {
	INSTANT = 0,      ## All units spawn at once
	SEQUENTIAL = 1,   ## Units spawn one at a time
	BURST = 2,        ## Units spawn in groups
	GRADUAL = 3       ## Units spawn continuously over duration
}

## Spawn mode
var mode: int = Mode.GRADUAL

## Total duration to spawn all units (seconds)
var spawn_duration: float = 10.0

## Delay between spawns (for SEQUENTIAL mode)
var spawn_delay: float = 0.5

## Burst size (for BURST mode)
var burst_size: int = 5

## Delay between bursts (for BURST mode)
var burst_delay: float = 2.0

## Initial delay before wave starts
var initial_delay: float = 3.0

## Whether to randomize spawn order
var randomize_order: bool = true


func _init() -> void:
	pass


## Configure for instant spawn.
func set_instant() -> void:
	mode = Mode.INSTANT
	spawn_duration = 0.0


## Configure for sequential spawn.
func set_sequential(delay: float) -> void:
	mode = Mode.SEQUENTIAL
	spawn_delay = delay


## Configure for burst spawn.
func set_burst(size: int, delay: float) -> void:
	mode = Mode.BURST
	burst_size = size
	burst_delay = delay


## Configure for gradual spawn.
func set_gradual(duration: float) -> void:
	mode = Mode.GRADUAL
	spawn_duration = duration


## Calculate spawn delay for a given unit index.
func get_spawn_time(unit_index: int, total_units: int) -> float:
	match mode:
		Mode.INSTANT:
			return initial_delay
		Mode.SEQUENTIAL:
			return initial_delay + (unit_index * spawn_delay)
		Mode.BURST:
			var burst_index := unit_index / burst_size
			return initial_delay + (burst_index * burst_delay)
		Mode.GRADUAL:
			if total_units <= 1:
				return initial_delay
			return initial_delay + (float(unit_index) / float(total_units - 1)) * spawn_duration

	return initial_delay


## Get total wave duration.
func get_total_duration(total_units: int) -> float:
	match mode:
		Mode.INSTANT:
			return initial_delay
		Mode.SEQUENTIAL:
			return initial_delay + ((total_units - 1) * spawn_delay)
		Mode.BURST:
			var num_bursts := ceili(float(total_units) / float(burst_size))
			return initial_delay + ((num_bursts - 1) * burst_delay)
		Mode.GRADUAL:
			return initial_delay + spawn_duration

	return initial_delay


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"mode": mode,
		"spawn_duration": spawn_duration,
		"spawn_delay": spawn_delay,
		"burst_size": burst_size,
		"burst_delay": burst_delay,
		"initial_delay": initial_delay,
		"randomize_order": randomize_order
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> WaveSpawnTiming:
	var timing := WaveSpawnTiming.new()
	timing.mode = data.get("mode", Mode.GRADUAL)
	timing.spawn_duration = data.get("spawn_duration", 10.0)
	timing.spawn_delay = data.get("spawn_delay", 0.5)
	timing.burst_size = data.get("burst_size", 5)
	timing.burst_delay = data.get("burst_delay", 2.0)
	timing.initial_delay = data.get("initial_delay", 3.0)
	timing.randomize_order = data.get("randomize_order", true)
	return timing
