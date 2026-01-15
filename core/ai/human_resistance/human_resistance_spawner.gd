class_name HumanResistanceSpawner
extends RefCounted
## HumanResistanceSpawner manages wave-based spawning of Human Resistance units.
## Creates unpredictable third-party threat affecting all robot factions.

signal wave_started(wave_number: int, unit_count: int)
signal wave_completed(wave_number: int)
signal unit_spawned(unit_id: int, unit_type: String, position: Vector3)
signal units_spawned(count: int, positions: Array[Vector3])
signal patrol_group_created(group_id: int, unit_ids: Array[int])
signal difficulty_increased(new_multiplier: float)
signal max_units_reached(current_count: int)
signal unit_defeated(unit_id: int)

## Spawn configuration
const SPAWN_LOCATION_COUNT := 8
const INITIAL_SPAWN_INTERVAL := 15.0    ## Seconds between waves
const INITIAL_WAVE_SIZE := 3
const MIN_SPAWN_INTERVAL := 5.0         ## Minimum seconds between waves
const MAX_UNIT_CAP := 500               ## Maximum simultaneous units
const MAX_PATROL_GROUPS := 20

## Difficulty scaling
const DIFFICULTY_INCREMENT_PER_WAVE := 0.1  ## +10% per wave
const SPAWN_INTERVAL_REDUCTION := 0.5        ## -0.5s per wave
const MAX_DIFFICULTY_MULTIPLIER := 5.0

## Unit type distribution (weights)
enum UnitType { SOLDIER, SNIPER, HEAVY_GUNNER, COMMANDER }
const UNIT_WEIGHTS := {
	UnitType.SOLDIER: 60,
	UnitType.SNIPER: 25,
	UnitType.HEAVY_GUNNER: 10,
	UnitType.COMMANDER: 5
}
const TOTAL_WEIGHT := 100  ## Sum of weights

## Performance target
const SPAWN_BUDGET_MS := 1.0            ## Max ms per spawn operation

## State
var _is_active: bool = false
var _spawn_timer: float = 0.0
var _current_wave: int = 0
var _difficulty_multiplier: float = 1.0
var _current_spawn_interval: float = INITIAL_SPAWN_INTERVAL

## Units and groups
var _active_units: Dictionary = {}      ## unit_id -> UnitData
var _patrol_groups: Dictionary = {}     ## group_id -> PatrolGroup
var _next_group_id: int = 0

## Spawn locations
var _spawn_locations: Array[Vector3] = []
var _city_bounds: Rect2 = Rect2(0, 0, 512, 512)
var _spawn_distance_from_center := 200.0

## RNG
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Initialize spawner with city bounds.
func initialize(city_bounds: Rect2, spawn_distance: float = 200.0) -> void:
	_city_bounds = city_bounds
	_spawn_distance_from_center = spawn_distance
	_generate_spawn_locations()


## Generate spawn locations around city edges.
func _generate_spawn_locations() -> void:
	_spawn_locations.clear()

	var center := Vector2(
		_city_bounds.position.x + _city_bounds.size.x * 0.5,
		_city_bounds.position.y + _city_bounds.size.y * 0.5
	)

	var angle_step := TAU / float(SPAWN_LOCATION_COUNT)

	for i in SPAWN_LOCATION_COUNT:
		var angle := angle_step * i
		var offset := Vector2(
			cos(angle) * _spawn_distance_from_center,
			sin(angle) * _spawn_distance_from_center
		)
		var pos := center + offset

		# Clamp to city bounds
		pos.x = clampf(pos.x, _city_bounds.position.x + 10, _city_bounds.end.x - 10)
		pos.y = clampf(pos.y, _city_bounds.position.y + 10, _city_bounds.end.y - 10)

		_spawn_locations.append(Vector3(pos.x, 0, pos.y))


## Start spawning.
func start() -> void:
	_is_active = true
	_spawn_timer = _current_spawn_interval  # Spawn immediately on first update


## Stop spawning.
func stop() -> void:
	_is_active = false


## Pause spawning.
func pause() -> void:
	_is_active = false


## Resume spawning.
func resume() -> void:
	_is_active = true


## Update spawner each frame.
func update(delta: float) -> void:
	if not _is_active:
		return

	_spawn_timer += delta

	if _spawn_timer >= _current_spawn_interval:
		_spawn_timer = 0.0
		_spawn_wave()


## Spawn a new wave of units.
func _spawn_wave() -> void:
	# Check unit cap
	if _active_units.size() >= MAX_UNIT_CAP:
		max_units_reached.emit(_active_units.size())
		return

	_current_wave += 1

	# Calculate wave size with difficulty scaling
	var base_wave_size := INITIAL_WAVE_SIZE + (_current_wave - 1)
	var scaled_wave_size := int(base_wave_size * _difficulty_multiplier)
	var actual_wave_size := mini(scaled_wave_size, MAX_UNIT_CAP - _active_units.size())

	wave_started.emit(_current_wave, actual_wave_size)

	# Select spawn location
	var spawn_location_idx := _rng.randi() % _spawn_locations.size()
	var base_spawn_pos := _spawn_locations[spawn_location_idx]

	# Spawn units
	var spawned_ids: Array[int] = []
	var spawned_positions: Array[Vector3] = []
	var start_time := Time.get_ticks_usec()

	for i in actual_wave_size:
		# Check performance budget
		var elapsed_ms := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed_ms > SPAWN_BUDGET_MS * actual_wave_size:
			break

		var unit_type := _select_unit_type()
		var spawn_pos := _get_offset_spawn_position(base_spawn_pos, i)

		var unit_id := _spawn_unit(unit_type, spawn_pos)
		if unit_id >= 0:
			spawned_ids.append(unit_id)
			spawned_positions.append(spawn_pos)

	if not spawned_positions.is_empty():
		units_spawned.emit(spawned_ids.size(), spawned_positions)

	# Create patrol group if enough units
	if spawned_ids.size() >= 2 and _patrol_groups.size() < MAX_PATROL_GROUPS:
		_create_patrol_group(spawned_ids)

	# Update difficulty
	_update_difficulty()

	wave_completed.emit(_current_wave)


## Select unit type based on weights.
func _select_unit_type() -> UnitType:
	var roll := _rng.randi() % TOTAL_WEIGHT

	var cumulative := 0
	for unit_type in UNIT_WEIGHTS:
		cumulative += UNIT_WEIGHTS[unit_type]
		if roll < cumulative:
			return unit_type

	return UnitType.SOLDIER  # Default fallback


## Get spawn position with offset for multiple units.
func _get_offset_spawn_position(base_pos: Vector3, index: int) -> Vector3:
	var row := index / 3
	var col := index % 3
	var spacing := 2.0

	return Vector3(
		base_pos.x + (col - 1) * spacing,
		base_pos.y,
		base_pos.z + row * spacing
	)


## Spawn a single unit and return its ID.
func _spawn_unit(unit_type: UnitType, spawn_pos: Vector3) -> int:
	var unit_id := _generate_unit_id()

	var unit_data := UnitData.new()
	unit_data.id = unit_id
	unit_data.unit_type = unit_type
	unit_data.position = spawn_pos
	unit_data.spawn_wave = _current_wave
	unit_data.spawn_time = Time.get_ticks_msec()
	unit_data.is_alive = true

	_active_units[unit_id] = unit_data

	unit_spawned.emit(unit_id, _get_unit_type_name(unit_type), spawn_pos)
	return unit_id


## Generate unique unit ID.
func _generate_unit_id() -> int:
	return hash(str(Time.get_ticks_usec()) + str(_rng.randi()))


## Create patrol group from spawned units.
func _create_patrol_group(unit_ids: Array[int]) -> void:
	var group := PatrolGroup.new()
	group.id = _next_group_id
	group.unit_ids = unit_ids.duplicate()
	group.spawn_location = _active_units[unit_ids[0]].position if not unit_ids.is_empty() else Vector3.ZERO
	group.is_active = true

	_patrol_groups[_next_group_id] = group
	patrol_group_created.emit(_next_group_id, unit_ids)

	_next_group_id += 1


## Update difficulty scaling.
func _update_difficulty() -> void:
	var old_multiplier := _difficulty_multiplier

	# Increase difficulty
	_difficulty_multiplier = minf(
		1.0 + (_current_wave * DIFFICULTY_INCREMENT_PER_WAVE),
		MAX_DIFFICULTY_MULTIPLIER
	)

	# Decrease spawn interval
	_current_spawn_interval = maxf(
		INITIAL_SPAWN_INTERVAL - (_current_wave * SPAWN_INTERVAL_REDUCTION),
		MIN_SPAWN_INTERVAL
	)

	if _difficulty_multiplier != old_multiplier:
		difficulty_increased.emit(_difficulty_multiplier)


## Register unit defeat.
func register_unit_defeated(unit_id: int) -> void:
	if not _active_units.has(unit_id):
		return

	var unit_data: UnitData = _active_units[unit_id]
	unit_data.is_alive = false
	_active_units.erase(unit_id)

	# Remove from patrol group
	for group_id in _patrol_groups:
		var group: PatrolGroup = _patrol_groups[group_id]
		var idx := group.unit_ids.find(unit_id)
		if idx >= 0:
			group.unit_ids.remove_at(idx)
			if group.unit_ids.is_empty():
				_patrol_groups.erase(group_id)
			break

	unit_defeated.emit(unit_id)


## Get unit type name.
func _get_unit_type_name(unit_type: UnitType) -> String:
	match unit_type:
		UnitType.SOLDIER: return "soldier"
		UnitType.SNIPER: return "sniper"
		UnitType.HEAVY_GUNNER: return "heavy_gunner"
		UnitType.COMMANDER: return "commander"
	return "unknown"


## Get current unit count.
func get_unit_count() -> int:
	return _active_units.size()


## Get current wave number.
func get_current_wave() -> int:
	return _current_wave


## Get difficulty multiplier.
func get_difficulty_multiplier() -> float:
	return _difficulty_multiplier


## Get current spawn interval.
func get_spawn_interval() -> float:
	return _current_spawn_interval


## Get time until next wave.
func get_time_until_next_wave() -> float:
	return maxf(0.0, _current_spawn_interval - _spawn_timer)


## Get patrol group count.
func get_patrol_group_count() -> int:
	return _patrol_groups.size()


## Get all active unit IDs.
func get_active_unit_ids() -> Array[int]:
	var result: Array[int] = []
	for unit_id in _active_units:
		result.append(unit_id)
	return result


## Get spawn locations.
func get_spawn_locations() -> Array[Vector3]:
	return _spawn_locations.duplicate()


## Reset spawner to initial state.
func reset() -> void:
	_is_active = false
	_spawn_timer = 0.0
	_current_wave = 0
	_difficulty_multiplier = 1.0
	_current_spawn_interval = INITIAL_SPAWN_INTERVAL
	_active_units.clear()
	_patrol_groups.clear()
	_next_group_id = 0


## Get statistics.
func get_statistics() -> Dictionary:
	var type_counts := {}
	for unit_type in UnitType.values():
		type_counts[_get_unit_type_name(unit_type)] = 0

	for unit_id in _active_units:
		var unit_data: UnitData = _active_units[unit_id]
		var type_name := _get_unit_type_name(unit_data.unit_type)
		type_counts[type_name] += 1

	return {
		"is_active": _is_active,
		"current_wave": _current_wave,
		"active_units": _active_units.size(),
		"max_units": MAX_UNIT_CAP,
		"patrol_groups": _patrol_groups.size(),
		"difficulty_multiplier": _difficulty_multiplier,
		"spawn_interval": _current_spawn_interval,
		"time_until_next": get_time_until_next_wave(),
		"spawn_locations": _spawn_locations.size(),
		"unit_type_counts": type_counts
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var units := {}
	for unit_id in _active_units:
		var unit_data: UnitData = _active_units[unit_id]
		units[str(unit_id)] = unit_data.to_dict()

	var groups := {}
	for group_id in _patrol_groups:
		var group: PatrolGroup = _patrol_groups[group_id]
		groups[str(group_id)] = group.to_dict()

	var locations := []
	for loc in _spawn_locations:
		locations.append({"x": loc.x, "y": loc.y, "z": loc.z})

	return {
		"is_active": _is_active,
		"spawn_timer": _spawn_timer,
		"current_wave": _current_wave,
		"difficulty_multiplier": _difficulty_multiplier,
		"current_spawn_interval": _current_spawn_interval,
		"active_units": units,
		"patrol_groups": groups,
		"next_group_id": _next_group_id,
		"spawn_locations": locations,
		"city_bounds": {
			"x": _city_bounds.position.x,
			"y": _city_bounds.position.y,
			"w": _city_bounds.size.x,
			"h": _city_bounds.size.y
		},
		"spawn_distance": _spawn_distance_from_center
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_is_active = data.get("is_active", false)
	_spawn_timer = data.get("spawn_timer", 0.0)
	_current_wave = data.get("current_wave", 0)
	_difficulty_multiplier = data.get("difficulty_multiplier", 1.0)
	_current_spawn_interval = data.get("current_spawn_interval", INITIAL_SPAWN_INTERVAL)
	_next_group_id = data.get("next_group_id", 0)
	_spawn_distance_from_center = data.get("spawn_distance", 200.0)

	# Restore city bounds
	var bounds: Dictionary = data.get("city_bounds", {})
	_city_bounds = Rect2(
		bounds.get("x", 0),
		bounds.get("y", 0),
		bounds.get("w", 512),
		bounds.get("h", 512)
	)

	# Restore spawn locations
	_spawn_locations.clear()
	var locations: Array = data.get("spawn_locations", [])
	for loc in locations:
		_spawn_locations.append(Vector3(loc.get("x", 0), loc.get("y", 0), loc.get("z", 0)))

	# Restore units
	_active_units.clear()
	var units: Dictionary = data.get("active_units", {})
	for key in units:
		var unit_data := UnitData.new()
		unit_data.from_dict(units[key])
		_active_units[int(key)] = unit_data

	# Restore patrol groups
	_patrol_groups.clear()
	var groups: Dictionary = data.get("patrol_groups", {})
	for key in groups:
		var group := PatrolGroup.new()
		group.from_dict(groups[key])
		_patrol_groups[int(key)] = group


## UnitData inner class.
class UnitData:
	var id: int = -1
	var unit_type: UnitType = UnitType.SOLDIER
	var position: Vector3 = Vector3.ZERO
	var spawn_wave: int = 0
	var spawn_time: int = 0
	var is_alive: bool = true

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"unit_type": unit_type,
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"spawn_wave": spawn_wave,
			"spawn_time": spawn_time,
			"is_alive": is_alive
		}

	func from_dict(data: Dictionary) -> void:
		id = data.get("id", -1)
		unit_type = data.get("unit_type", UnitType.SOLDIER)
		var pos: Dictionary = data.get("position", {})
		position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		spawn_wave = data.get("spawn_wave", 0)
		spawn_time = data.get("spawn_time", 0)
		is_alive = data.get("is_alive", true)


## PatrolGroup inner class.
class PatrolGroup:
	var id: int = -1
	var unit_ids: Array[int] = []
	var spawn_location: Vector3 = Vector3.ZERO
	var is_active: bool = true

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"unit_ids": unit_ids.duplicate(),
			"spawn_location": {"x": spawn_location.x, "y": spawn_location.y, "z": spawn_location.z},
			"is_active": is_active
		}

	func from_dict(data: Dictionary) -> void:
		id = data.get("id", -1)
		var ids: Array = data.get("unit_ids", [])
		unit_ids.clear()
		for uid in ids:
			unit_ids.append(uid)
		var loc: Dictionary = data.get("spawn_location", {})
		spawn_location = Vector3(loc.get("x", 0), loc.get("y", 0), loc.get("z", 0))
		is_active = data.get("is_active", true)
