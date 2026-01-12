class_name WaveManager
extends RefCounted
## WaveManager orchestrates wave progression and spawning.
## Central coordinator for the Endless Wave Escalation system.

signal wave_starting(wave_number: int, config: WaveConfiguration)
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int, history: WaveHistory)
signal wave_failed(wave_number: int)
signal unit_spawn_requested(unit_type: String, position: Vector3, faction: String)
signal all_units_eliminated(wave_number: int)

## Wave states
enum State {
	IDLE = 0,
	COUNTDOWN = 1,
	SPAWNING = 2,
	ACTIVE = 3,
	COMPLETED = 4,
	FAILED = 5
}

## Base units for wave 1
const BASE_UNITS := 50

## Growth rate per wave
const GROWTH_RATE := 1.15

## Pause between waves (seconds)
const INTER_WAVE_PAUSE := 2.5

## Current state
var state: int = State.IDLE

## Current wave number
var current_wave: int = 0

## Wave state manager
var state_manager: WaveStateManager = null

## Current wave configuration
var current_config: WaveConfiguration = null

## Current wave progress
var current_progress: WaveProgress = null

## Inter-wave countdown timer
var countdown_timer: float = 0.0

## Faction for enemy waves
var enemy_faction: String = "enemy"

## Available factions for wave composition
var available_factions: Array[String] = []

## Default unit composition
var default_composition: Dictionary = {
	"basic": 0.6,
	"ranged": 0.25,
	"heavy": 0.15
}

## Spawn locations
var spawn_locations: Array[Vector3] = []

## Faction seed for deterministic waves
var faction_seed: int = 0

## RNG for wave generation
var _rng: RandomNumberGenerator = null


func _init() -> void:
	state_manager = WaveStateManager.new()
	_rng = RandomNumberGenerator.new()


## Initialize wave manager.
func initialize(seed: int = 0) -> void:
	faction_seed = seed if seed != 0 else randi()
	_rng.seed = faction_seed


## Set spawn locations.
func set_spawn_locations(locations: Array[Vector3]) -> void:
	spawn_locations = locations.duplicate()


## Add spawn location.
func add_spawn_location(location: Vector3) -> void:
	spawn_locations.append(location)


## Set enemy faction.
func set_enemy_faction(faction: String) -> void:
	enemy_faction = faction


## Set unit composition.
func set_unit_composition(composition: Dictionary) -> void:
	default_composition = composition.duplicate()


## Start the wave system.
func start() -> void:
	if state != State.IDLE:
		return

	current_wave = 0
	_start_next_wave()


## Start next wave.
func _start_next_wave() -> void:
	current_wave += 1

	# Generate wave configuration
	current_config = _generate_wave_config(current_wave)

	# Start countdown
	state = State.COUNTDOWN
	countdown_timer = INTER_WAVE_PAUSE

	wave_starting.emit(current_wave, current_config)


## Generate wave configuration.
func _generate_wave_config(wave_number: int) -> WaveConfiguration:
	var config := WaveConfiguration.new()

	# Calculate seed deterministically
	var wave_seed := hash(str(faction_seed) + str(wave_number))
	_rng.seed = wave_seed

	# Initialize configuration
	config.initialize(wave_number, enemy_faction, BASE_UNITS, wave_seed)
	config.set_composition(default_composition)
	config.set_spawn_locations(spawn_locations)

	# Configure spawn timing
	config.spawn_timing.set_gradual(10.0 + wave_number * 0.5)  # Longer spawn duration for later waves
	config.spawn_timing.initial_delay = 1.0

	return config


## Process wave manager.
func process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_process_countdown(delta)
		State.SPAWNING, State.ACTIVE:
			_process_active_wave(delta)


## Process countdown phase.
func _process_countdown(delta: float) -> void:
	countdown_timer -= delta

	if countdown_timer <= 0:
		_begin_wave()


## Begin wave spawning.
func _begin_wave() -> void:
	state = State.SPAWNING

	# Start wave in state manager
	current_progress = state_manager.start_wave(current_config)

	wave_started.emit(current_wave)


## Process active wave.
func _process_active_wave(delta: float) -> void:
	if current_progress == null:
		return

	# Get units to spawn
	var to_spawn := current_progress.update(delta)

	for spawn_data in to_spawn:
		_spawn_unit(spawn_data)

	# Check if all spawned and in active state
	if current_progress.all_spawned() and state == State.SPAWNING:
		state = State.ACTIVE

	# Check wave complete
	if current_progress.wave_complete:
		_complete_wave()


## Spawn a unit.
func _spawn_unit(spawn_data: Dictionary) -> void:
	var unit_type: String = spawn_data.get("unit_type", "basic")
	var position: Vector3 = spawn_data.get("spawn_location", Vector3.ZERO)

	unit_spawn_requested.emit(unit_type, position, enemy_faction)

	# Simulate unit spawned (in real game, unit manager would call back)
	# current_progress.unit_spawned(unit_id)


## Register unit spawned (called by unit manager).
func on_unit_spawned(unit_id: int) -> void:
	if current_progress != null:
		current_progress.unit_spawned(unit_id)


## Register unit killed (called by combat system).
func on_unit_killed(unit_id: int, killer_faction: String = "") -> void:
	if current_progress != null:
		current_progress.unit_killed(unit_id, killer_faction)

		# Check if all eliminated
		if current_progress.units_remaining == 0 and current_progress.all_spawned():
			all_units_eliminated.emit(current_wave)


## Register damage dealt (called by combat system).
func on_damage_dealt(faction_id: String, amount: float) -> void:
	if current_progress != null:
		current_progress.damage_dealt(faction_id, amount)


## Complete current wave.
func _complete_wave() -> void:
	state = State.COMPLETED

	var history := state_manager.complete_wave()
	wave_completed.emit(current_wave, history)

	# Start next wave
	_start_next_wave()


## Fail current wave.
func fail_wave() -> void:
	state = State.FAILED
	wave_failed.emit(current_wave)


## Pause wave progression.
func pause() -> void:
	# Store current state for resume
	pass


## Resume wave progression.
func resume() -> void:
	pass


## Get current state name.
func get_state_name() -> String:
	match state:
		State.IDLE: return "IDLE"
		State.COUNTDOWN: return "COUNTDOWN"
		State.SPAWNING: return "SPAWNING"
		State.ACTIVE: return "ACTIVE"
		State.COMPLETED: return "COMPLETED"
		State.FAILED: return "FAILED"
		_: return "UNKNOWN"


## Get countdown remaining.
func get_countdown() -> float:
	return maxf(0.0, countdown_timer)


## Check if wave is active.
func is_wave_active() -> bool:
	return state == State.SPAWNING or state == State.ACTIVE


## Get statistics.
func get_statistics() -> Dictionary:
	return state_manager.get_statistics()


## Get wave history.
func get_history() -> Array[WaveHistory]:
	return state_manager.get_history()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"state": state,
		"current_wave": current_wave,
		"countdown_timer": countdown_timer,
		"enemy_faction": enemy_faction,
		"default_composition": default_composition.duplicate(),
		"faction_seed": faction_seed,
		"state_manager": state_manager.to_dict(),
		"current_config": current_config.to_dict() if current_config != null else {}
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	state = data.get("state", State.IDLE)
	current_wave = data.get("current_wave", 0)
	countdown_timer = data.get("countdown_timer", 0.0)
	enemy_faction = data.get("enemy_faction", "enemy")
	default_composition = data.get("default_composition", default_composition).duplicate()
	faction_seed = data.get("faction_seed", 0)

	state_manager.from_dict(data.get("state_manager", {}))

	var config_data: Dictionary = data.get("current_config", {})
	if not config_data.is_empty():
		current_config = WaveConfiguration.from_dict(config_data)

	if faction_seed != 0:
		_rng.seed = faction_seed


## Get summary for debugging.
func get_summary() -> Dictionary:
	var progress_summary := {}
	if current_progress != null:
		progress_summary = current_progress.get_summary()

	return {
		"state": get_state_name(),
		"wave": current_wave,
		"countdown": "%.1fs" % countdown_timer if state == State.COUNTDOWN else "n/a",
		"progress": progress_summary,
		"stats": state_manager.get_summary()
	}
