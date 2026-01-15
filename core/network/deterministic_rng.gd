class_name DeterministicRNG
extends RefCounted
## DeterministicRNG provides deterministic random number generation shared across all clients.
## Uses a seeded PRNG to ensure identical sequences on all machines for lockstep simulation.

signal seed_changed(new_seed: int)
signal state_synced(frame: int)

## Xorshift128+ state (64-bit compatible)
## Using two 64-bit state values for high-quality randomness
var _state_a: int = 1
var _state_b: int = 0

## Initial seed for resynchronization
var _initial_seed: int = 0

## Frame tracking for determinism verification
var _current_frame: int = 0
var _state_history: Dictionary = {}  ## frame -> state snapshot
const MAX_HISTORY := 256

## Verification
var _verification_enabled := false
var _verification_errors: Array[String] = []


func _init() -> void:
	pass


## Initialize with a seed.
func initialize(seed_value: int) -> void:
	_initial_seed = seed_value
	_state_a = seed_value
	_state_b = seed_value ^ 0x5DEECE66D  ## Mix the seed
	_current_frame = 0
	_state_history.clear()

	# Warm up the generator (improves initial distribution)
	for i in 10:
		_next_raw()

	seed_changed.emit(seed_value)


## Synchronize state with server.
func sync_state(seed_value: int, frame: int) -> void:
	initialize(seed_value)

	# Advance to the correct frame
	for i in frame:
		_next_raw()
		_current_frame += 1

	state_synced.emit(frame)


## Advance to a specific frame.
func advance_to_frame(target_frame: int) -> void:
	while _current_frame < target_frame:
		_next_raw()
		_current_frame += 1


## Get the next raw random value (internal).
func _next_raw() -> int:
	# Xorshift128+ algorithm
	var s1 := _state_a
	var s0 := _state_b

	_state_a = s0
	s1 ^= (s1 << 23) & 0x7FFFFFFFFFFFFFFF  ## Mask to prevent overflow
	_state_b = s1 ^ s0 ^ (s1 >> 17) ^ (s0 >> 26)

	var result := (_state_b + s0) & 0x7FFFFFFFFFFFFFFF

	# Record state for verification
	if _verification_enabled:
		_record_state()

	return result


## Generate random float [0.0, 1.0).
func randf() -> float:
	return float(_next_raw()) / float(0x7FFFFFFFFFFFFFFF)


## Generate random float in range [min, max).
func randf_range(min_val: float, max_val: float) -> float:
	return min_val + randf() * (max_val - min_val)


## Generate random integer in range [min, max].
func randi_range(min_val: int, max_val: int) -> int:
	if min_val > max_val:
		var temp := min_val
		min_val = max_val
		max_val = temp

	var range_size := max_val - min_val + 1
	return min_val + (_next_raw() % range_size)


## Generate random integer.
func randi() -> int:
	return _next_raw()


## Generate random boolean.
func randb() -> bool:
	return (_next_raw() & 1) == 1


## Generate random boolean with probability.
func randb_probability(probability: float) -> bool:
	return randf() < probability


## Generate random Vector2 with components in [0, 1).
func rand_vector2() -> Vector2:
	return Vector2(randf(), randf())


## Generate random Vector2 in range.
func rand_vector2_range(min_val: Vector2, max_val: Vector2) -> Vector2:
	return Vector2(
		randf_range(min_val.x, max_val.x),
		randf_range(min_val.y, max_val.y)
	)


## Generate random Vector3 with components in [0, 1).
func rand_vector3() -> Vector3:
	return Vector3(randf(), randf(), randf())


## Generate random Vector3 in range.
func rand_vector3_range(min_val: Vector3, max_val: Vector3) -> Vector3:
	return Vector3(
		randf_range(min_val.x, max_val.x),
		randf_range(min_val.y, max_val.y),
		randf_range(min_val.z, max_val.z)
	)


## Generate random unit vector (normalized).
func rand_direction_2d() -> Vector2:
	var angle := randf() * TAU
	return Vector2(cos(angle), sin(angle))


## Generate random 3D direction on unit sphere.
func rand_direction_3d() -> Vector3:
	var theta := randf() * TAU
	var phi := acos(2.0 * randf() - 1.0)
	return Vector3(
		sin(phi) * cos(theta),
		sin(phi) * sin(theta),
		cos(phi)
	)


## Generate random point inside unit circle.
func rand_point_in_circle() -> Vector2:
	var r := sqrt(randf())
	var theta := randf() * TAU
	return Vector2(r * cos(theta), r * sin(theta))


## Generate random point inside unit sphere.
func rand_point_in_sphere() -> Vector3:
	var direction := rand_direction_3d()
	var radius := pow(randf(), 1.0 / 3.0)
	return direction * radius


## Pick random element from array.
func pick_random(array: Array) -> Variant:
	if array.is_empty():
		return null
	return array[randi_range(0, array.size() - 1)]


## Shuffle array in place (Fisher-Yates).
func shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := randi_range(0, i)
		var temp: Variant = array[i]
		array[i] = array[j]
		array[j] = temp


## Get shuffled copy of array.
func shuffled(array: Array) -> Array:
	var copy := array.duplicate()
	shuffle(copy)
	return copy


## Weighted random selection.
func weighted_random(weights: Array[float]) -> int:
	if weights.is_empty():
		return -1

	var total := 0.0
	for w in weights:
		total += w

	if total <= 0:
		return randi_range(0, weights.size() - 1)

	var roll := randf() * total
	var cumulative := 0.0

	for i in weights.size():
		cumulative += weights[i]
		if roll < cumulative:
			return i

	return weights.size() - 1


## Record current state for verification.
func _record_state() -> void:
	_state_history[_current_frame] = {
		"state_a": _state_a,
		"state_b": _state_b
	}

	# Limit history size
	if _state_history.size() > MAX_HISTORY:
		var oldest := _current_frame - MAX_HISTORY
		for frame in _state_history.keys():
			if frame < oldest:
				_state_history.erase(frame)


## Verify state matches expected (for desync detection).
func verify_state(frame: int, expected_state_a: int, expected_state_b: int) -> bool:
	if _state_history.has(frame):
		var recorded: Dictionary = _state_history[frame]
		if recorded["state_a"] != expected_state_a or recorded["state_b"] != expected_state_b:
			var error := "RNG desync at frame %d: expected (%d, %d), got (%d, %d)" % [
				frame, expected_state_a, expected_state_b,
				recorded["state_a"], recorded["state_b"]
			]
			_verification_errors.append(error)
			push_error("DeterministicRNG: " + error)
			return false
	return true


## Get current state for synchronization.
func get_state() -> Dictionary:
	return {
		"seed": _initial_seed,
		"frame": _current_frame,
		"state_a": _state_a,
		"state_b": _state_b
	}


## Restore state from synchronization data.
func restore_state(state: Dictionary) -> void:
	_initial_seed = state.get("seed", 0)
	_current_frame = state.get("frame", 0)
	_state_a = state.get("state_a", 1)
	_state_b = state.get("state_b", 0)


## Enable/disable verification mode.
func set_verification_enabled(enabled: bool) -> void:
	_verification_enabled = enabled
	if not enabled:
		_state_history.clear()
		_verification_errors.clear()


## Get verification errors.
func get_verification_errors() -> Array[String]:
	return _verification_errors.duplicate()


## Get current frame.
func get_current_frame() -> int:
	return _current_frame


## Increment frame (call at start of each simulation frame).
func next_frame() -> void:
	_current_frame += 1


## Get initial seed.
func get_seed() -> int:
	return _initial_seed


## Reset to initial state.
func reset() -> void:
	initialize(_initial_seed)
