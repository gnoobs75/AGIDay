class_name WaveOrchestrator
extends RefCounted
## WaveOrchestrator is the central controller for wave progression.
## Coordinates difficulty calculation, spawning, and state management.

signal wave_starting(wave_number: int, countdown: float)
signal wave_started(wave_number: int, config: WaveConfiguration)
signal wave_completed(wave_number: int, history: WaveHistory)
signal wave_failed(wave_number: int, reason: String)
signal countdown_tick(remaining: float)
signal spawn_requested(unit_type: String, position: Vector3, faction: String, modifiers: Dictionary)
signal all_units_eliminated(wave_number: int)
signal orchestrator_error(error: String)
signal performance_warning(message: String, frame_time_ms: float)

## Orchestrator states
enum State {
	STOPPED = 0,
	COUNTDOWN = 1,
	SPAWNING = 2,
	ACTIVE = 3,
	PAUSED = 4,
	ERROR = 5
}

## Default countdown duration
const DEFAULT_COUNTDOWN := 2.5

## Performance threshold (ms per frame budget)
const FRAME_TIME_BUDGET_MS := 2.0

## Maximum spawn batch size per frame
const MAX_SPAWNS_PER_FRAME := 10

## Current state
var state: int = State.STOPPED

## Wave queue for upcoming waves
var wave_queue: WaveQueue = null

## Difficulty calculator
var difficulty_calculator: WaveDifficultyCalculator = null

## Wave state manager for history
var state_manager: WaveStateManager = null

## Current wave configuration
var current_config: WaveConfiguration = null

## Current wave progress
var current_progress: WaveProgress = null

## Countdown remaining
var countdown_remaining: float = 0.0

## Countdown duration setting
var countdown_duration: float = DEFAULT_COUNTDOWN

## Whether to auto-advance to next wave
var auto_advance: bool = true

## Whether skip countdown is enabled
var skip_countdown_enabled: bool = true

## Error message if in error state
var last_error: String = ""

## Performance tracking
var _frame_times: Array[float] = []
var _max_frame_samples := 30

## State before pause
var _state_before_pause: int = State.STOPPED


func _init() -> void:
	wave_queue = WaveQueue.new()
	difficulty_calculator = WaveDifficultyCalculator.new()
	state_manager = WaveStateManager.new()

	# Connect queue to calculator
	wave_queue.set_difficulty_calculator(difficulty_calculator)


## Initialize orchestrator with seed.
func initialize(seed: int = 0) -> void:
	wave_queue.initialize(seed)
	state = State.STOPPED
	last_error = ""
	_frame_times.clear()


## Set spawn locations.
func set_spawn_locations(locations: Array[Vector3]) -> void:
	wave_queue.set_spawn_locations(locations)


## Set enemy faction.
func set_enemy_faction(faction: String) -> void:
	wave_queue.set_enemy_faction(faction)


## Set countdown duration.
func set_countdown_duration(duration: float) -> void:
	countdown_duration = maxf(0.0, duration)


## Set difficulty mode.
func set_difficulty_mode(mode: int) -> void:
	difficulty_calculator.set_scaling_mode(mode)


## Set difficulty multiplier.
func set_difficulty_multiplier(multiplier: float) -> void:
	difficulty_calculator.set_difficulty_multiplier(multiplier)


## Start wave system.
func start() -> void:
	if state != State.STOPPED:
		return

	_start_next_wave()


## Stop wave system.
func stop() -> void:
	state = State.STOPPED
	current_config = null
	current_progress = null
	countdown_remaining = 0.0


## Pause wave system.
func pause() -> void:
	if state == State.PAUSED or state == State.STOPPED:
		return

	_state_before_pause = state
	state = State.PAUSED


## Resume wave system.
func resume() -> void:
	if state != State.PAUSED:
		return

	state = _state_before_pause


## Skip countdown and start wave immediately.
func skip_countdown() -> void:
	if not skip_countdown_enabled:
		return

	if state == State.COUNTDOWN:
		countdown_remaining = 0.0
		_begin_wave()


## Process orchestrator (call every frame).
func process(delta: float) -> void:
	if state == State.STOPPED or state == State.PAUSED or state == State.ERROR:
		return

	var start_time := Time.get_ticks_usec()

	match state:
		State.COUNTDOWN:
			_process_countdown(delta)
		State.SPAWNING, State.ACTIVE:
			_process_active_wave(delta)

	# Track performance
	var frame_time := (Time.get_ticks_usec() - start_time) / 1000.0
	_track_frame_time(frame_time)


## Process countdown phase.
func _process_countdown(delta: float) -> void:
	countdown_remaining -= delta
	countdown_tick.emit(countdown_remaining)

	if countdown_remaining <= 0:
		_begin_wave()


## Begin wave spawning.
func _begin_wave() -> void:
	if current_config == null:
		_set_error("No wave configuration available")
		return

	state = State.SPAWNING

	# Start wave tracking
	current_progress = state_manager.start_wave(current_config)
	if current_progress == null:
		_set_error("Failed to create wave progress")
		return

	wave_started.emit(current_config.wave_number, current_config)


## Process active wave.
func _process_active_wave(delta: float) -> void:
	if current_progress == null:
		_set_error("Wave progress lost during active wave")
		return

	# Get units to spawn with batching
	var to_spawn := current_progress.update(delta)
	var spawned_count := 0

	for spawn_data in to_spawn:
		if spawned_count >= MAX_SPAWNS_PER_FRAME:
			# Defer remaining spawns to next frame
			break

		_request_spawn(spawn_data)
		spawned_count += 1

	# Check if all spawned
	if current_progress.all_spawned() and state == State.SPAWNING:
		state = State.ACTIVE

	# Check wave completion
	if current_progress.wave_complete:
		_complete_wave()


## Request unit spawn.
func _request_spawn(spawn_data: Dictionary) -> void:
	var unit_type: String = spawn_data.get("unit_type", "basic")
	var position: Vector3 = spawn_data.get("spawn_location", Vector3.ZERO)
	var faction: String = current_config.faction if current_config else "enemy"

	# Get modifiers from config
	var modifiers := {}
	if current_config != null:
		modifiers = {
			"health": current_config.get_modifier("health", 1.0),
			"damage": current_config.get_modifier("damage", 1.0),
			"speed": current_config.get_modifier("speed", 1.0)
		}

	spawn_requested.emit(unit_type, position, faction, modifiers)


## Start next wave.
func _start_next_wave() -> void:
	current_config = wave_queue.dequeue()

	if current_config == null:
		_set_error("Failed to get next wave configuration")
		return

	if not current_config.validate():
		_set_error("Invalid wave configuration for wave " + str(current_config.wave_number))
		return

	# Start countdown
	state = State.COUNTDOWN
	countdown_remaining = countdown_duration

	wave_starting.emit(current_config.wave_number, countdown_remaining)


## Complete current wave.
func _complete_wave() -> void:
	if current_progress == null:
		return

	var history := state_manager.complete_wave()
	var wave_number := current_config.wave_number if current_config else 0

	wave_completed.emit(wave_number, history)

	# Auto-advance to next wave
	if auto_advance:
		_start_next_wave()
	else:
		state = State.STOPPED


## Handle unit spawned callback.
func on_unit_spawned(unit_id: int) -> void:
	if current_progress != null:
		current_progress.unit_spawned(unit_id)


## Handle unit killed callback.
func on_unit_killed(unit_id: int, killer_faction: String = "") -> void:
	if current_progress != null:
		current_progress.unit_killed(unit_id, killer_faction)

		# Check if all eliminated
		if current_progress.units_remaining == 0 and current_progress.all_spawned():
			all_units_eliminated.emit(current_config.wave_number if current_config else 0)


## Handle damage dealt callback.
func on_damage_dealt(faction_id: String, amount: float) -> void:
	if current_progress != null:
		current_progress.damage_dealt(faction_id, amount)


## Fail current wave.
func fail_wave(reason: String = "Wave failed") -> void:
	var wave_number := current_config.wave_number if current_config else 0
	state = State.STOPPED
	wave_failed.emit(wave_number, reason)


## Set error state.
func _set_error(error: String) -> void:
	last_error = error
	state = State.ERROR
	orchestrator_error.emit(error)


## Clear error and reset.
func clear_error() -> void:
	if state == State.ERROR:
		state = State.STOPPED
		last_error = ""


## Track frame time for performance monitoring.
func _track_frame_time(time_ms: float) -> void:
	_frame_times.append(time_ms)

	while _frame_times.size() > _max_frame_samples:
		_frame_times.pop_front()

	# Check for performance issues
	if time_ms > FRAME_TIME_BUDGET_MS:
		performance_warning.emit("Wave processing exceeded frame budget", time_ms)


## Get average frame time.
func get_average_frame_time() -> float:
	if _frame_times.is_empty():
		return 0.0

	var total := 0.0
	for t in _frame_times:
		total += t
	return total / _frame_times.size()


## Get current wave number.
func get_current_wave() -> int:
	if current_config != null:
		return current_config.wave_number
	return wave_queue.current_wave


## Get state name.
func get_state_name() -> String:
	match state:
		State.STOPPED: return "STOPPED"
		State.COUNTDOWN: return "COUNTDOWN"
		State.SPAWNING: return "SPAWNING"
		State.ACTIVE: return "ACTIVE"
		State.PAUSED: return "PAUSED"
		State.ERROR: return "ERROR"
	return "UNKNOWN"


## Check if wave is active.
func is_wave_active() -> bool:
	return state == State.SPAWNING or state == State.ACTIVE


## Check if in countdown.
func is_counting_down() -> bool:
	return state == State.COUNTDOWN


## Get wave preview.
func get_wave_preview() -> Array[WaveConfiguration]:
	return wave_queue.get_preview()


## Get wave history.
func get_history() -> Array[WaveHistory]:
	return state_manager.get_history()


## Get statistics.
func get_statistics() -> Dictionary:
	return state_manager.get_statistics()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"state": state,
		"countdown_remaining": countdown_remaining,
		"countdown_duration": countdown_duration,
		"auto_advance": auto_advance,
		"skip_countdown_enabled": skip_countdown_enabled,
		"wave_queue": wave_queue.to_dict(),
		"difficulty_calculator": difficulty_calculator.to_dict(),
		"state_manager": state_manager.to_dict(),
		"current_config": current_config.to_dict() if current_config != null else {},
		"current_progress": current_progress.to_dict() if current_progress != null else {}
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	state = data.get("state", State.STOPPED)
	countdown_remaining = data.get("countdown_remaining", 0.0)
	countdown_duration = data.get("countdown_duration", DEFAULT_COUNTDOWN)
	auto_advance = data.get("auto_advance", true)
	skip_countdown_enabled = data.get("skip_countdown_enabled", true)

	wave_queue.from_dict(data.get("wave_queue", {}))
	difficulty_calculator.from_dict(data.get("difficulty_calculator", {}))
	state_manager.from_dict(data.get("state_manager", {}))

	var config_data: Dictionary = data.get("current_config", {})
	if not config_data.is_empty():
		current_config = WaveConfiguration.from_dict(config_data)

	var progress_data: Dictionary = data.get("current_progress", {})
	if not progress_data.is_empty():
		current_progress = WaveProgress.from_dict(progress_data)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var progress_summary := {}
	if current_progress != null:
		progress_summary = current_progress.get_summary()

	return {
		"state": get_state_name(),
		"wave": get_current_wave(),
		"countdown": "%.1fs" % countdown_remaining if state == State.COUNTDOWN else "n/a",
		"progress": progress_summary,
		"queue": wave_queue.get_summary(),
		"difficulty": difficulty_calculator.get_summary(),
		"stats": state_manager.get_summary(),
		"avg_frame_ms": "%.2fms" % get_average_frame_time(),
		"error": last_error if not last_error.is_empty() else "none"
	}
