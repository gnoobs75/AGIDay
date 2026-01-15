class_name WaveSpawner
extends RefCounted
## WaveSpawner coordinates wave-based enemy spawning across multiple factions.
## Integrates with EnemySpawner and WaveManager for wave progression.

signal wave_spawn_started(wave_number: int)
signal wave_spawn_progress(wave_number: int, progress: float)
signal wave_spawn_completed(wave_number: int)
signal faction_spawn_started(faction_id: int, unit_count: int)
signal faction_spawn_completed(faction_id: int)

## Configuration
const DEFAULT_START_DELAY := 3.0    ## Delay before first batch
const DEFAULT_WAVE_DURATION := 45.0 ## Total time to spawn wave

## Spawner per faction
var _faction_spawners: Dictionary = {}  ## faction_id -> EnemySpawner

## Unit pool reference
var _unit_pool: UnitPool = null

## Wave state
var _current_wave := 0
var _is_spawning := false
var _start_delay_timer := 0.0
var _active_factions: Array[int] = []

## Factory positions (corners of map)
var _factory_positions: Dictionary = {
	0: Vector3(-200, 0, -200),  ## Aether - SW corner
	1: Vector3(200, 0, -200),   ## OptiForge - SE corner
	2: Vector3(-200, 0, 200),   ## Dynapods - NW corner
	3: Vector3(200, 0, 200)     ## LogiBots - NE corner
}

## Wave configuration
var _wave_config: WaveConfig = null


func _init() -> void:
	pass


## Initialize with unit pool.
func initialize(unit_pool: UnitPool) -> void:
	_unit_pool = unit_pool

	# Create spawner for each faction
	for faction_id in [0, 1, 2, 3]:
		var spawner := EnemySpawner.new()
		spawner.initialize(unit_pool)

		# Connect signals
		spawner.spawn_completed.connect(func(wave): _on_faction_spawn_completed(faction_id))
		spawner.batch_spawned.connect(func(batch, count): _update_progress())

		_faction_spawners[faction_id] = spawner


## Set factory position for faction.
func set_factory_position(faction_id: int, position: Vector3) -> void:
	_factory_positions[faction_id] = position


## Start spawning a wave.
func start_wave(wave_number: int, wave_config: WaveConfig) -> void:
	if _is_spawning:
		push_warning("WaveSpawner: Already spawning wave %d" % _current_wave)
		return

	_current_wave = wave_number
	_wave_config = wave_config
	_is_spawning = true
	_start_delay_timer = wave_config.start_delay
	_active_factions.clear()

	wave_spawn_started.emit(wave_number)


## Update spawner (call each frame).
func update(delta: float) -> void:
	if not _is_spawning:
		return

	# Handle start delay
	if _start_delay_timer > 0:
		_start_delay_timer -= delta
		if _start_delay_timer <= 0:
			_begin_faction_spawns()
		return

	# Update all active spawners
	for faction_id in _faction_spawners:
		var spawner: EnemySpawner = _faction_spawners[faction_id]
		spawner.update(delta)


## Begin spawning for all factions.
func _begin_faction_spawns() -> void:
	if _wave_config == null:
		return

	for faction_id in _wave_config.faction_units:
		var unit_count: int = _wave_config.faction_units[faction_id]
		if unit_count <= 0:
			continue

		_active_factions.append(faction_id)

		var spawner: EnemySpawner = _faction_spawners[faction_id]
		var factory_pos: Vector3 = _factory_positions.get(faction_id, Vector3.ZERO)
		var faction_seed: int = _wave_config.wave_seed + faction_id * 10000

		spawner.start_wave_spawn(
			_current_wave,
			faction_id,
			unit_count,
			factory_pos,
			faction_seed
		)

		faction_spawn_started.emit(faction_id, unit_count)


## Handle faction spawn completed.
func _on_faction_spawn_completed(faction_id: int) -> void:
	_active_factions.erase(faction_id)
	faction_spawn_completed.emit(faction_id)

	if _active_factions.is_empty():
		_is_spawning = false
		wave_spawn_completed.emit(_current_wave)


## Update spawn progress.
func _update_progress() -> void:
	var total_progress := 0.0
	var faction_count := 0

	for faction_id in _faction_spawners:
		var spawner: EnemySpawner = _faction_spawners[faction_id]
		if spawner.is_spawning() or spawner.get_total_spawned() > 0:
			total_progress += spawner.get_spawn_progress()
			faction_count += 1

	if faction_count > 0:
		var avg_progress := total_progress / float(faction_count)
		wave_spawn_progress.emit(_current_wave, avg_progress)


## Cancel current wave spawn.
func cancel_wave() -> void:
	for faction_id in _faction_spawners:
		_faction_spawners[faction_id].cancel_spawn()

	_active_factions.clear()
	_is_spawning = false


## Return unit to pool.
func return_unit(unit_id: int) -> void:
	if _unit_pool != null:
		_unit_pool.return_unit(unit_id)


## Is spawning active.
func is_spawning() -> bool:
	return _is_spawning


## Get current wave.
func get_current_wave() -> int:
	return _current_wave


## Get total spawned this wave.
func get_total_spawned() -> int:
	var total := 0
	for faction_id in _faction_spawners:
		total += _faction_spawners[faction_id].get_total_spawned()
	return total


## Get spawned count by faction.
func get_spawned_by_faction(faction_id: int) -> int:
	if _faction_spawners.has(faction_id):
		return _faction_spawners[faction_id].get_total_spawned()
	return 0


## Get statistics.
func get_statistics() -> Dictionary:
	var faction_stats: Dictionary = {}
	for faction_id in _faction_spawners:
		faction_stats[faction_id] = _faction_spawners[faction_id].get_statistics()

	return {
		"is_spawning": _is_spawning,
		"current_wave": _current_wave,
		"active_factions": _active_factions.duplicate(),
		"total_spawned": get_total_spawned(),
		"factions": faction_stats
	}


## WaveConfig data class.
class WaveConfig:
	var wave_number: int = 1
	var wave_seed: int = 0
	var start_delay: float = DEFAULT_START_DELAY
	var wave_duration: float = DEFAULT_WAVE_DURATION
	var faction_units: Dictionary = {}  ## faction_id -> unit_count
	var difficulty: float = 1.0

	static func create(wave_num: int, units_per_faction: Dictionary,
					   difficulty: float = 1.0) -> WaveConfig:
		var config := WaveConfig.new()
		config.wave_number = wave_num
		config.wave_seed = wave_num * 12345
		config.faction_units = units_per_faction.duplicate()
		config.difficulty = difficulty

		# Scale duration based on total units
		var total := 0
		for faction in units_per_faction:
			total += units_per_faction[faction]
		config.wave_duration = clampf(float(total) / 50.0 * 15.0, 30.0, 60.0)

		return config
