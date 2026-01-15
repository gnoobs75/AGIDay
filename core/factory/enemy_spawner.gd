class_name EnemySpawner
extends RefCounted
## EnemySpawner handles batch spawning of enemy units during waves.
## Distributes unit creation over time to prevent frame drops.

signal spawn_started(wave_number: int, total_units: int)
signal batch_spawned(batch_number: int, unit_count: int)
signal spawn_completed(wave_number: int)
signal unit_spawned(unit_id: int, unit_type: String, position: Vector3)
signal spawn_failed(reason: String)

## Spawn timing configuration
const MIN_WAVE_DURATION := 30.0   ## Minimum 30 seconds to spawn wave
const MAX_WAVE_DURATION := 60.0   ## Maximum 60 seconds to spawn wave
const MIN_BATCH_SIZE := 10
const MAX_BATCH_SIZE := 50

## Faction spawn radii from factory corners
const SPAWN_RADIUS := 15.0
const SPAWN_OFFSET := 5.0

## Unit pool reference
var _unit_pool: UnitPool = null

## Spawn state
var _is_spawning := false
var _current_wave := 0
var _spawn_queue: Array[SpawnBatch] = []
var _spawn_timer := 0.0
var _spawn_interval := 0.0

## Faction data
var _faction_compositions: Dictionary = {}

## RNG for deterministic spawning
var _rng: RandomNumberGenerator = null
var _wave_seed := 0

## Statistics
var _total_spawned := 0
var _batches_completed := 0


func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_setup_faction_compositions()


## Initialize with unit pool.
func initialize(unit_pool: UnitPool) -> void:
	_unit_pool = unit_pool


## Setup default faction compositions.
func _setup_faction_compositions() -> void:
	# Aether Swarm - many small units
	_faction_compositions[0] = {
		"unit_types": ["aether_drone", "aether_scout", "aether_infiltrator", "aether_phaser"],
		"weights": [0.5, 0.25, 0.15, 0.1],
		"batch_size": MAX_BATCH_SIZE,  ## Spawn many at once
		"power_multiplier": 0.5  ## Lower individual power
	}

	# OptiForge Legion - balanced horde
	_faction_compositions[1] = {
		"unit_types": ["opti_grunt", "opti_soldier", "opti_heavy", "opti_elite"],
		"weights": [0.4, 0.3, 0.2, 0.1],
		"batch_size": 30,
		"power_multiplier": 0.8
	}

	# Dynapods Vanguard - agile units
	_faction_compositions[2] = {
		"unit_types": ["dyna_runner", "dyna_striker", "dyna_acrobat", "dyna_juggernaut"],
		"weights": [0.35, 0.3, 0.25, 0.1],
		"batch_size": 25,
		"power_multiplier": 1.0
	}

	# LogiBots Colossus - fewer heavy units
	_faction_compositions[3] = {
		"unit_types": ["logi_worker", "logi_defender", "logi_artillery", "logi_titan"],
		"weights": [0.3, 0.3, 0.25, 0.15],
		"batch_size": MIN_BATCH_SIZE,  ## Spawn fewer at once
		"power_multiplier": 1.5  ## Higher individual power
	}

	# Human Remnant
	_faction_compositions[4] = {
		"unit_types": ["human_soldier", "human_heavy", "human_vehicle"],
		"weights": [0.5, 0.35, 0.15],
		"batch_size": 20,
		"power_multiplier": 1.0
	}


## Start spawning for a wave.
func start_wave_spawn(wave_number: int, faction_id: int, total_units: int,
					  factory_position: Vector3, faction_seed: int = 0) -> void:
	if _is_spawning:
		push_warning("EnemySpawner: Already spawning wave %d" % _current_wave)
		return

	_current_wave = wave_number
	_is_spawning = true
	_total_spawned = 0
	_batches_completed = 0

	# Setup deterministic RNG
	_wave_seed = faction_seed + wave_number * 1000
	_rng.seed = _wave_seed

	# Get faction composition
	var composition: Dictionary = _faction_compositions.get(faction_id, _faction_compositions[0])
	var batch_size: int = composition.get("batch_size", 20)

	# Calculate spawn timing
	var batch_count := ceili(float(total_units) / float(batch_size))
	var wave_duration := clampf(
		float(total_units) / 100.0 * 10.0,  ## ~10 seconds per 100 units
		MIN_WAVE_DURATION,
		MAX_WAVE_DURATION
	)
	_spawn_interval = wave_duration / float(batch_count)

	# Generate spawn batches
	_spawn_queue.clear()
	var remaining := total_units

	for i in batch_count:
		var batch := SpawnBatch.new()
		batch.batch_number = i
		batch.faction_id = faction_id
		batch.factory_position = factory_position

		# Determine batch unit count
		var batch_unit_count := mini(batch_size, remaining)
		remaining -= batch_unit_count

		# Select unit types for batch
		batch.unit_types = _select_unit_types(composition, batch_unit_count)
		batch.spawn_positions = _generate_spawn_positions(factory_position, batch_unit_count)

		_spawn_queue.append(batch)

	_spawn_timer = 0.0
	spawn_started.emit(wave_number, total_units)


## Select unit types based on composition weights.
func _select_unit_types(composition: Dictionary, count: int) -> Array[String]:
	var types: Array[String] = []
	var unit_types: Array = composition.get("unit_types", [])
	var weights: Array = composition.get("weights", [])

	if unit_types.is_empty():
		return types

	for i in count:
		var roll := _rng.randf()
		var cumulative := 0.0

		for j in weights.size():
			cumulative += weights[j]
			if roll <= cumulative:
				types.append(unit_types[j])
				break

		# Fallback to first type
		if types.size() <= i:
			types.append(unit_types[0])

	return types


## Generate spawn positions around factory.
func _generate_spawn_positions(factory_pos: Vector3, count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []

	for i in count:
		var angle := _rng.randf() * TAU
		var radius := SPAWN_RADIUS + _rng.randf() * SPAWN_OFFSET
		var offset := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		positions.append(factory_pos + offset)

	return positions


## Update spawner (call each frame).
func update(delta: float) -> void:
	if not _is_spawning:
		return

	_spawn_timer += delta

	if _spawn_timer >= _spawn_interval and not _spawn_queue.is_empty():
		_spawn_timer -= _spawn_interval
		_process_next_batch()

	if _spawn_queue.is_empty() and _is_spawning:
		_complete_spawn()


## Process next spawn batch.
func _process_next_batch() -> void:
	if _spawn_queue.is_empty():
		return

	var batch: SpawnBatch = _spawn_queue.pop_front()
	var spawned_count := 0

	for i in batch.unit_types.size():
		var unit_type: String = batch.unit_types[i]
		var position: Vector3 = batch.spawn_positions[i]

		var unit := _spawn_unit(unit_type, batch.faction_id, position)
		if not unit.is_empty():
			spawned_count += 1
			unit_spawned.emit(unit["id"], unit_type, position)

	_total_spawned += spawned_count
	_batches_completed += 1
	batch_spawned.emit(batch.batch_number, spawned_count)


## Spawn a single unit.
func _spawn_unit(unit_type: String, faction_id: int, position: Vector3) -> Dictionary:
	if _unit_pool == null:
		push_error("EnemySpawner: Unit pool not initialized")
		return {}

	var unit := _unit_pool.get_unit(unit_type)
	if unit.is_empty():
		return {}

	# Set initial position
	unit["position"] = position
	unit["faction_id"] = faction_id
	unit["is_active"] = true

	return unit


## Complete wave spawn.
func _complete_spawn() -> void:
	_is_spawning = false
	spawn_completed.emit(_current_wave)


## Cancel current spawn.
func cancel_spawn() -> void:
	_spawn_queue.clear()
	_is_spawning = false


## Return unit to pool (when killed).
func return_unit(unit_id: int) -> void:
	if _unit_pool != null:
		_unit_pool.return_unit(unit_id)


## Is currently spawning.
func is_spawning() -> bool:
	return _is_spawning


## Get spawn progress.
func get_spawn_progress() -> float:
	if _spawn_queue.is_empty():
		return 1.0
	var total := _batches_completed + _spawn_queue.size()
	if total == 0:
		return 1.0
	return float(_batches_completed) / float(total)


## Get remaining batches.
func get_remaining_batches() -> int:
	return _spawn_queue.size()


## Get total spawned this wave.
func get_total_spawned() -> int:
	return _total_spawned


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"is_spawning": _is_spawning,
		"current_wave": _current_wave,
		"total_spawned": _total_spawned,
		"batches_completed": _batches_completed,
		"remaining_batches": _spawn_queue.size(),
		"spawn_progress": get_spawn_progress()
	}


## SpawnBatch helper class.
class SpawnBatch:
	var batch_number: int = 0
	var faction_id: int = 0
	var factory_position: Vector3 = Vector3.ZERO
	var unit_types: Array[String] = []
	var spawn_positions: Array[Vector3] = []
