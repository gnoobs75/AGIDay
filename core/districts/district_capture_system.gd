class_name DistrictCaptureSystem
extends RefCounted
## DistrictCaptureSystem handles capture mechanics for district control.
## Updates capture progress based on unit presence every 0.5 seconds.

signal district_captured(district_id: int, new_owner: String, old_owner: String)
signal district_contested(district_id: int, factions: Array)
signal capture_progress_updated(district_id: int, faction_id: String, progress: float)

## Capture update interval in seconds
const UPDATE_INTERVAL := 0.5

## Capture rates
const ATTACK_CAPTURE_RATE := 0.1   ## Rate for attacking faction (per unit control %)
const DEFEND_MAINTAIN_RATE := 0.05  ## Rate for defending faction to maintain
const NO_PRESENCE_DECAY_RATE := 0.1 ## Rate of decay when no units present

## Reference to district manager
var _district_manager: DistrictManager = null

## Time accumulator for update interval
var _time_accumulator: float = 0.0

## Capture history for each district (district_id -> CaptureHistory)
var _capture_history: Dictionary = {}

## Performance tracking
var _last_update_time_us: int = 0

## RNG seed for deterministic behavior
var _rng_seed: int = 0
var _rng: RandomNumberGenerator = null


func _init(district_manager: DistrictManager = null) -> void:
	_district_manager = district_manager
	_rng = RandomNumberGenerator.new()


## Set the district manager.
func set_district_manager(manager: DistrictManager) -> void:
	_district_manager = manager


## Initialize with seed for deterministic replay.
func initialize(seed: int) -> void:
	_rng_seed = seed
	_rng.seed = seed


## Process capture updates.
## unit_positions_provider: Callable that returns Dictionary of faction_id -> Array[Vector3]
func process(delta: float, unit_positions_provider: Callable) -> void:
	_time_accumulator += delta

	if _time_accumulator < UPDATE_INTERVAL:
		return

	_time_accumulator -= UPDATE_INTERVAL
	_update_all_districts(unit_positions_provider)


## Update all districts.
func _update_all_districts(unit_positions_provider: Callable) -> void:
	if _district_manager == null:
		return

	var start_time := Time.get_ticks_usec()

	# Get unit positions by faction
	var faction_positions: Dictionary = unit_positions_provider.call()

	# Count units per district per faction
	var district_unit_counts: Dictionary = {}  # district_id -> {faction_id -> count}

	for faction_id in faction_positions:
		var positions: Array = faction_positions[faction_id]
		for pos in positions:
			var district_id := _district_manager.get_district_id_at_position(pos)
			if district_id < 0:
				continue

			if not district_unit_counts.has(district_id):
				district_unit_counts[district_id] = {}

			if not district_unit_counts[district_id].has(faction_id):
				district_unit_counts[district_id][faction_id] = 0

			district_unit_counts[district_id][faction_id] += 1

	# Update each district
	for i in _district_manager.get_total_district_count():
		var district := _district_manager.get_district(i)
		if district == null:
			continue

		var unit_counts: Dictionary = district_unit_counts.get(i, {})
		_update_district_control(district, unit_counts)

	_last_update_time_us = Time.get_ticks_usec() - start_time


## Update control for a single district.
func _update_district_control(district: District, unit_counts: Dictionary) -> void:
	# Update unit presence on district
	for faction_id in unit_counts:
		district.update_unit_presence(faction_id, unit_counts[faction_id])

	# Clear presence for factions not in this district
	var factions_to_clear: Array = []
	for faction_id in district.unit_presence:
		if not unit_counts.has(faction_id):
			factions_to_clear.append(faction_id)

	for faction_id in factions_to_clear:
		district.update_unit_presence(faction_id, 0)

	# Calculate dominant faction and control percentages
	var total_units := district.get_total_unit_count()
	var dominant_faction := ""
	var dominant_count := 0

	for faction_id in unit_counts:
		if unit_counts[faction_id] > dominant_count:
			dominant_count = unit_counts[faction_id]
			dominant_faction = faction_id

	# Update capture progress
	_update_capture_progress(district, unit_counts, total_units, dominant_faction)


## Update capture progress for a district.
func _update_capture_progress(district: District, unit_counts: Dictionary, total_units: int, dominant_faction: String) -> void:
	var owner := district.owner_faction

	# Case 1: District is neutral
	if district.is_neutral():
		if dominant_faction.is_empty():
			# No units, no change
			return

		# Attacking faction captures
		var control_percentage := float(unit_counts.get(dominant_faction, 0)) / float(maxi(total_units, 1))
		var progress_rate := ATTACK_CAPTURE_RATE * control_percentage
		district.add_capture_progress(dominant_faction, progress_rate)
		capture_progress_updated.emit(district.id, dominant_faction, district.get_capture_progress(dominant_faction))

		# Check for contested status
		if unit_counts.size() > 1:
			district_contested.emit(district.id, unit_counts.keys())

		# Check for capture completion (handled in District.add_capture_progress)
		if district.owner_faction != owner:
			_record_capture(district.id, owner, district.owner_faction)
			district_captured.emit(district.id, district.owner_faction, owner)

		return

	# Case 2: District is owned
	var owner_units: int = unit_counts.get(owner, 0)
	var enemy_units := total_units - owner_units

	# Case 2a: Only owner has units - maintain control
	if enemy_units == 0 and owner_units > 0:
		# Owner maintains/increases control
		district.set_control_level(minf(district.control_level + DEFEND_MAINTAIN_RATE, 1.0))
		return

	# Case 2b: No units present - decay control
	if total_units == 0:
		var new_control := district.control_level - NO_PRESENCE_DECAY_RATE
		if new_control <= 0:
			var old_owner := district.owner_faction
			district.clear_owner()
			_record_capture(district.id, old_owner, "")
			district_captured.emit(district.id, "", old_owner)
		else:
			district.set_control_level(new_control)
		return

	# Case 2c: Contested - enemy capturing
	if enemy_units > 0:
		district_contested.emit(district.id, unit_counts.keys())

		# Find strongest enemy
		var strongest_enemy := ""
		var strongest_count := 0
		for faction_id in unit_counts:
			if faction_id != owner and unit_counts[faction_id] > strongest_count:
				strongest_count = unit_counts[faction_id]
				strongest_enemy = faction_id

		if strongest_enemy.is_empty():
			return

		# Calculate contest result
		var enemy_control := float(strongest_count) / float(total_units)
		var owner_control := float(owner_units) / float(total_units)

		if enemy_control > owner_control:
			# Enemy is winning - reduce owner control
			var reduction := ATTACK_CAPTURE_RATE * (enemy_control - owner_control)
			var new_control := district.control_level - reduction

			if new_control <= 0:
				# Owner loses district, becomes neutral
				var old_owner := district.owner_faction
				district.clear_owner()
				_record_capture(district.id, old_owner, "")
				district_captured.emit(district.id, "", old_owner)

				# Start enemy capture
				district.add_capture_progress(strongest_enemy, ATTACK_CAPTURE_RATE * enemy_control)
			else:
				district.set_control_level(new_control)
		else:
			# Owner defending successfully
			district.set_control_level(minf(district.control_level + DEFEND_MAINTAIN_RATE * owner_control, 1.0))


## Record capture in history.
func _record_capture(district_id: int, old_owner: String, new_owner: String) -> void:
	if not _capture_history.has(district_id):
		_capture_history[district_id] = []

	_capture_history[district_id].append({
		"timestamp": Time.get_ticks_msec(),
		"old_owner": old_owner,
		"new_owner": new_owner
	})


## Get capture history for a district.
func get_capture_history(district_id: int) -> Array:
	return _capture_history.get(district_id, []).duplicate()


## Get last capture info for a district.
func get_last_capture(district_id: int) -> Dictionary:
	var history: Array = _capture_history.get(district_id, [])
	if history.is_empty():
		return {}
	return history[history.size() - 1]


## Force capture a district (for testing/cheats).
func force_capture(district_id: int, faction_id: String) -> void:
	if _district_manager == null:
		return

	var district := _district_manager.get_district(district_id)
	if district == null:
		return

	var old_owner := district.owner_faction
	district.set_owner(faction_id)
	_record_capture(district_id, old_owner, faction_id)
	district_captured.emit(district_id, faction_id, old_owner)


## Get districts being captured by a faction.
func get_capturing_districts(faction_id: String) -> Array[int]:
	var result: Array[int] = []
	if _district_manager == null:
		return result

	for i in _district_manager.get_total_district_count():
		var district := _district_manager.get_district(i)
		if district != null and district.get_capture_progress(faction_id) > 0:
			result.append(i)

	return result


## Get performance stats.
func get_performance_stats() -> Dictionary:
	return {
		"last_update_us": _last_update_time_us,
		"update_interval": UPDATE_INTERVAL,
		"capture_histories": _capture_history.size()
	}


## Serialize capture state.
func to_dict() -> Dictionary:
	return {
		"capture_history": _capture_history.duplicate(true),
		"time_accumulator": _time_accumulator,
		"rng_seed": _rng_seed
	}


## Deserialize capture state.
func from_dict(data: Dictionary) -> void:
	_capture_history = data.get("capture_history", {}).duplicate(true)
	_time_accumulator = data.get("time_accumulator", 0.0)
	_rng_seed = data.get("rng_seed", 0)
	if _rng_seed != 0:
		_rng.seed = _rng_seed
