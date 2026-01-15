class_name WaveQueue
extends RefCounted
## WaveQueue manages upcoming waves with pre-generation and lookahead.
## Enables deterministic wave sequencing and preview functionality.

signal wave_queued(wave_number: int, config: WaveConfiguration)
signal queue_updated(queue_size: int)

## Queue of upcoming wave configurations
var _queue: Array[WaveConfiguration] = []

## Maximum waves to pre-generate
var max_queue_size: int = 5

## Current wave number (last dequeued)
var current_wave: int = 0

## Difficulty calculator reference
var difficulty_calculator: WaveDifficultyCalculator = null

## Faction seed for deterministic generation
var faction_seed: int = 0

## RNG for wave generation
var _rng: RandomNumberGenerator = null

## Default spawn locations
var _spawn_locations: Array[Vector3] = []

## Enemy faction identifier
var _enemy_faction: String = "enemy"


func _init() -> void:
	_rng = RandomNumberGenerator.new()


## Initialize queue with seed.
func initialize(seed: int = 0) -> void:
	faction_seed = seed if seed != 0 else randi()
	_rng.seed = faction_seed
	_queue.clear()
	current_wave = 0

	# Pre-fill queue
	_fill_queue()


## Set difficulty calculator.
func set_difficulty_calculator(calculator: WaveDifficultyCalculator) -> void:
	difficulty_calculator = calculator


## Set spawn locations.
func set_spawn_locations(locations: Array[Vector3]) -> void:
	_spawn_locations = locations.duplicate()


## Set enemy faction.
func set_enemy_faction(faction: String) -> void:
	_enemy_faction = faction


## Get next wave from queue.
func dequeue() -> WaveConfiguration:
	if _queue.is_empty():
		_fill_queue()

	if _queue.is_empty():
		return null

	var config: WaveConfiguration = _queue.pop_front()
	current_wave = config.wave_number

	# Maintain queue size
	_fill_queue()

	queue_updated.emit(_queue.size())
	return config


## Peek at next wave without removing.
func peek() -> WaveConfiguration:
	if _queue.is_empty():
		_fill_queue()

	if _queue.is_empty():
		return null

	return _queue[0]


## Peek at wave at index (0 = next).
func peek_at(index: int) -> WaveConfiguration:
	if index < 0 or index >= _queue.size():
		return null
	return _queue[index]


## Get all queued waves (preview).
func get_preview() -> Array[WaveConfiguration]:
	return _queue.duplicate()


## Get number of queued waves.
func get_queue_size() -> int:
	return _queue.size()


## Fill queue to max size.
func _fill_queue() -> void:
	while _queue.size() < max_queue_size:
		var next_wave := _get_next_wave_number()
		var config := _generate_wave_config(next_wave)
		_queue.append(config)
		wave_queued.emit(next_wave, config)


## Get next wave number to generate.
func _get_next_wave_number() -> int:
	if _queue.is_empty():
		return current_wave + 1

	return _queue.back().wave_number + 1


## Generate wave configuration.
func _generate_wave_config(wave_number: int) -> WaveConfiguration:
	var config := WaveConfiguration.new()

	# Calculate deterministic seed
	var wave_seed := hash(str(faction_seed) + str(wave_number))
	_rng.seed = wave_seed

	# Get difficulty parameters
	var params := {}
	if difficulty_calculator != null:
		params = difficulty_calculator.calculate(wave_number)
	else:
		params = _default_params(wave_number)

	# Initialize configuration
	config.initialize(wave_number, _enemy_faction, params.get("unit_count", 50), wave_seed)

	# Set composition
	var composition: Dictionary = params.get("composition", {
		"basic": 0.6,
		"ranged": 0.25,
		"heavy": 0.15
	})
	config.set_composition(composition)

	# Set spawn locations
	if not _spawn_locations.is_empty():
		config.set_spawn_locations(_spawn_locations)
	else:
		# Default spawn point
		config.add_spawn_location(Vector3(0, 0, 100))

	# Configure spawn timing
	var duration: float = params.get("spawn_duration", 10.0)
	config.spawn_timing.set_gradual(duration)
	config.spawn_timing.initial_delay = 1.0

	# Apply modifiers from difficulty
	if params.has("health_multiplier"):
		config.set_modifier("health", params["health_multiplier"])
	if params.has("damage_multiplier"):
		config.set_modifier("damage", params["damage_multiplier"])
	if params.has("speed_multiplier"):
		config.set_modifier("speed", params["speed_multiplier"])

	return config


## Default difficulty parameters without calculator.
func _default_params(wave_number: int) -> Dictionary:
	var unit_count := int(50 * pow(1.15, wave_number - 1))

	return {
		"wave_number": wave_number,
		"unit_count": unit_count,
		"health_multiplier": 1.0 + (wave_number - 1) * 0.05,
		"damage_multiplier": 1.0 + (wave_number - 1) * 0.03,
		"speed_multiplier": minf(1.0 + (wave_number - 1) * 0.02, 1.5),
		"composition": {
			"basic": maxf(0.3, 0.6 - wave_number * 0.02),
			"ranged": minf(0.4, 0.25 + wave_number * 0.01),
			"heavy": 0.15
		},
		"spawn_duration": 10.0 + wave_number * 0.5
	}


## Clear queue and reset.
func clear() -> void:
	_queue.clear()
	current_wave = 0
	queue_updated.emit(0)


## Skip to specific wave.
func skip_to_wave(wave_number: int) -> void:
	_queue.clear()
	current_wave = wave_number - 1
	_fill_queue()
	queue_updated.emit(_queue.size())


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var queue_data: Array = []
	for config in _queue:
		queue_data.append(config.to_dict())

	var locations_data: Array = []
	for loc in _spawn_locations:
		locations_data.append({"x": loc.x, "y": loc.y, "z": loc.z})

	return {
		"current_wave": current_wave,
		"faction_seed": faction_seed,
		"max_queue_size": max_queue_size,
		"enemy_faction": _enemy_faction,
		"spawn_locations": locations_data,
		"queue": queue_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	current_wave = data.get("current_wave", 0)
	faction_seed = data.get("faction_seed", 0)
	max_queue_size = data.get("max_queue_size", 5)
	_enemy_faction = data.get("enemy_faction", "enemy")

	if faction_seed != 0:
		_rng.seed = faction_seed

	_spawn_locations.clear()
	for loc_data in data.get("spawn_locations", []):
		_spawn_locations.append(Vector3(
			loc_data.get("x", 0.0),
			loc_data.get("y", 0.0),
			loc_data.get("z", 0.0)
		))

	_queue.clear()
	for config_data in data.get("queue", []):
		_queue.append(WaveConfiguration.from_dict(config_data))


## Get summary for debugging.
func get_summary() -> Dictionary:
	var preview: Array[Dictionary] = []
	for i in mini(_queue.size(), 3):
		preview.append({
			"wave": _queue[i].wave_number,
			"units": _queue[i].unit_count
		})

	return {
		"current_wave": current_wave,
		"queue_size": _queue.size(),
		"preview": preview
	}
