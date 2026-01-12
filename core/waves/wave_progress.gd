class_name WaveProgress
extends RefCounted
## WaveProgress tracks the current state of an active wave.

signal units_spawned_changed(spawned: int, total: int)
signal units_remaining_changed(remaining: int)
signal wave_completed()

## Current wave number
var current_wave: int = 0

## Wave configuration reference
var configuration: WaveConfiguration = null

## Wave start time (msec)
var wave_start_time: int = 0

## Number of units spawned so far
var units_spawned: int = 0

## Number of units remaining alive
var units_remaining: int = 0

## Total units to spawn this wave
var total_units: int = 0

## Whether wave is complete
var wave_complete: bool = false

## Units killed this wave
var units_killed: int = 0

## Faction performance tracking
var faction_performance: Dictionary = {}

## Spawn queue (units waiting to spawn)
var spawn_queue: Array[Dictionary] = []

## Active unit IDs from this wave
var active_unit_ids: Array[int] = []

## Time elapsed since wave start
var elapsed_time: float = 0.0


func _init() -> void:
	pass


## Start a new wave.
func start_wave(config: WaveConfiguration) -> void:
	configuration = config
	current_wave = config.wave_number
	wave_start_time = Time.get_ticks_msec()
	total_units = config.unit_count
	units_spawned = 0
	units_remaining = 0
	units_killed = 0
	wave_complete = false
	elapsed_time = 0.0
	spawn_queue.clear()
	active_unit_ids.clear()
	faction_performance.clear()

	# Build spawn queue
	_build_spawn_queue()


## Build the spawn queue based on configuration.
func _build_spawn_queue() -> void:
	if configuration == null:
		return

	var units_by_type := configuration.get_units_by_type()
	var spawn_locations := configuration.spawn_locations
	var timing := configuration.spawn_timing

	var unit_index := 0
	for unit_type in units_by_type:
		var count: int = units_by_type[unit_type]
		for i in count:
			var spawn_time := timing.get_spawn_time(unit_index, total_units)
			var spawn_loc := spawn_locations[unit_index % spawn_locations.size()]

			spawn_queue.append({
				"unit_type": unit_type,
				"spawn_time": spawn_time,
				"spawn_location": spawn_loc,
				"index": unit_index
			})

			unit_index += 1

	# Sort by spawn time
	spawn_queue.sort_custom(func(a, b): return a["spawn_time"] < b["spawn_time"])


## Update wave progress.
func update(delta: float) -> Array[Dictionary]:
	if wave_complete:
		return []

	elapsed_time += delta

	# Get units ready to spawn
	var to_spawn: Array[Dictionary] = []
	while not spawn_queue.is_empty() and spawn_queue[0]["spawn_time"] <= elapsed_time:
		to_spawn.append(spawn_queue.pop_front())

	return to_spawn


## Register unit spawned.
func unit_spawned(unit_id: int) -> void:
	units_spawned += 1
	units_remaining += 1
	active_unit_ids.append(unit_id)
	units_spawned_changed.emit(units_spawned, total_units)


## Register unit killed.
func unit_killed(unit_id: int, killer_faction: String = "") -> void:
	var idx := active_unit_ids.find(unit_id)
	if idx >= 0:
		active_unit_ids.remove_at(idx)

	units_remaining -= 1
	units_killed += 1

	# Track faction performance
	if not killer_faction.is_empty():
		if not faction_performance.has(killer_faction):
			faction_performance[killer_faction] = {"kills": 0, "damage_dealt": 0}
		faction_performance[killer_faction]["kills"] += 1

	units_remaining_changed.emit(units_remaining)

	# Check wave complete
	if units_remaining <= 0 and spawn_queue.is_empty():
		_complete_wave()


## Track damage dealt by faction.
func damage_dealt(faction_id: String, amount: float) -> void:
	if not faction_performance.has(faction_id):
		faction_performance[faction_id] = {"kills": 0, "damage_dealt": 0}
	faction_performance[faction_id]["damage_dealt"] += amount


## Complete the wave.
func _complete_wave() -> void:
	wave_complete = true
	wave_completed.emit()


## Get spawn progress percentage.
func get_spawn_progress() -> float:
	if total_units <= 0:
		return 1.0
	return float(units_spawned) / float(total_units)


## Get kill progress percentage.
func get_kill_progress() -> float:
	if total_units <= 0:
		return 1.0
	return float(units_killed) / float(total_units)


## Get wave duration so far.
func get_duration() -> float:
	return elapsed_time


## Check if all units spawned.
func all_spawned() -> bool:
	return units_spawned >= total_units


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var queue_data: Array = []
	for item in spawn_queue:
		var loc: Vector3 = item.get("spawn_location", Vector3.ZERO)
		queue_data.append({
			"unit_type": item.get("unit_type", ""),
			"spawn_time": item.get("spawn_time", 0.0),
			"spawn_location": {"x": loc.x, "y": loc.y, "z": loc.z},
			"index": item.get("index", 0)
		})

	return {
		"current_wave": current_wave,
		"wave_start_time": wave_start_time,
		"units_spawned": units_spawned,
		"units_remaining": units_remaining,
		"total_units": total_units,
		"wave_complete": wave_complete,
		"units_killed": units_killed,
		"faction_performance": faction_performance.duplicate(true),
		"spawn_queue": queue_data,
		"active_unit_ids": active_unit_ids.duplicate(),
		"elapsed_time": elapsed_time,
		"configuration": configuration.to_dict() if configuration != null else {}
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> WaveProgress:
	var progress := WaveProgress.new()
	progress.current_wave = data.get("current_wave", 0)
	progress.wave_start_time = data.get("wave_start_time", 0)
	progress.units_spawned = data.get("units_spawned", 0)
	progress.units_remaining = data.get("units_remaining", 0)
	progress.total_units = data.get("total_units", 0)
	progress.wave_complete = data.get("wave_complete", false)
	progress.units_killed = data.get("units_killed", 0)
	progress.faction_performance = data.get("faction_performance", {}).duplicate(true)
	progress.elapsed_time = data.get("elapsed_time", 0.0)

	progress.active_unit_ids.clear()
	for id in data.get("active_unit_ids", []):
		progress.active_unit_ids.append(int(id))

	progress.spawn_queue.clear()
	for item_data in data.get("spawn_queue", []):
		var loc_data: Dictionary = item_data.get("spawn_location", {})
		progress.spawn_queue.append({
			"unit_type": item_data.get("unit_type", ""),
			"spawn_time": item_data.get("spawn_time", 0.0),
			"spawn_location": Vector3(loc_data.get("x", 0.0), loc_data.get("y", 0.0), loc_data.get("z", 0.0)),
			"index": item_data.get("index", 0)
		})

	var config_data: Dictionary = data.get("configuration", {})
	if not config_data.is_empty():
		progress.configuration = WaveConfiguration.from_dict(config_data)

	return progress


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"wave": current_wave,
		"spawned": "%d/%d" % [units_spawned, total_units],
		"remaining": units_remaining,
		"killed": units_killed,
		"complete": wave_complete,
		"elapsed": "%.1fs" % elapsed_time
	}
