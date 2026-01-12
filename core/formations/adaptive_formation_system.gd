class_name AdaptiveFormationSystem
extends RefCounted
## AdaptiveFormationSystem manages dynamic squad formation for all units.
## Automatically organizes units based on proximity and threat levels.

signal squad_formed(squad_id: int, unit_ids: Array[int])
signal squad_disbanded(squad_id: int)
signal squads_merged(kept_id: int, merged_id: int)
signal squad_split(original_id: int, new_id: int)
signal formation_positions_updated(positions: Dictionary)

## Performance settings
const UPDATE_FREQUENCY := 30.0  ## 30Hz
const MAX_UPDATE_TIME_MS := 1.0  ## 1ms budget
const MAX_UNITS := 5000
const MAX_SQUADS := 200

## Auto-grouping settings
const AUTO_GROUP_DISTANCE := 15.0
const MERGE_DISTANCE := 10.0
const SPLIT_DISTANCE := 25.0

## Squads by ID
var _squads: Dictionary = {}  ## squad_id -> Squad

## Unit to squad mapping
var _unit_squad: Dictionary = {}  ## unit_id -> squad_id

## Next squad ID
var _next_squad_id: int = 0

## Update timing
var _update_accumulator: float = 0.0
var _update_interval: float = 1.0 / UPDATE_FREQUENCY

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _get_unit_faction: Callable  ## (unit_id) -> String
var _get_threat_level: Callable  ## (position, faction_id) -> float


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_faction(callback: Callable) -> void:
	_get_unit_faction = callback


func set_get_threat_level(callback: Callable) -> void:
	_get_threat_level = callback


## Update system (called each frame).
func update(delta: float) -> void:
	_update_accumulator += delta

	if _update_accumulator >= _update_interval:
		_update_accumulator -= _update_interval
		_process_formation_update()


## Process formation update within time budget.
func _process_formation_update() -> void:
	var start_time := Time.get_ticks_usec()

	# Collect all unit positions
	var positions := _collect_unit_positions()

	# Update existing squads
	_update_squads(positions)

	# Check time budget
	var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
	if elapsed > MAX_UPDATE_TIME_MS:
		return

	# Check for squad merges
	_check_squad_merges()

	elapsed = (Time.get_ticks_usec() - start_time) / 1000.0
	if elapsed > MAX_UPDATE_TIME_MS:
		return

	# Check for squad splits
	_check_squad_splits(positions)

	# Emit updated positions
	var all_positions := _get_all_desired_positions()
	if not all_positions.is_empty():
		formation_positions_updated.emit(all_positions)


## Collect positions for all tracked units.
func _collect_unit_positions() -> Dictionary:
	var positions: Dictionary = {}

	if not _get_unit_position.is_valid():
		return positions

	for unit_id in _unit_squad:
		var pos: Vector3 = _get_unit_position.call(unit_id)
		if pos != Vector3.INF:
			positions[unit_id] = pos

	return positions


## Update all squads.
func _update_squads(positions: Dictionary) -> void:
	var to_disband: Array[int] = []

	for squad_id in _squads:
		var squad: Squad = _squads[squad_id]

		# Update threat level
		if _get_threat_level.is_valid():
			var threat: float = _get_threat_level.call(squad.get_center(), squad.faction_id)
			squad.set_threat_level(threat)

		# Update squad
		squad.update(_update_interval, positions)

		# Check for empty squads
		if squad.get_unit_count() == 0:
			to_disband.append(squad_id)

	# Disband empty squads
	for squad_id in to_disband:
		_disband_squad(squad_id)


## Check for squads that should merge.
func _check_squad_merges() -> void:
	var squads_list: Array[int] = []
	for squad_id in _squads:
		squads_list.append(squad_id)

	var merged: Array[int] = []

	for i in range(squads_list.size()):
		var squad_a_id: int = squads_list[i]
		if squad_a_id in merged:
			continue

		var squad_a: Squad = _squads.get(squad_a_id)
		if squad_a == null:
			continue

		for j in range(i + 1, squads_list.size()):
			var squad_b_id: int = squads_list[j]
			if squad_b_id in merged:
				continue

			var squad_b: Squad = _squads.get(squad_b_id)
			if squad_b == null:
				continue

			# Only merge same faction
			if squad_a.faction_id != squad_b.faction_id:
				continue

			# Check distance
			var distance := squad_a.get_center().distance_to(squad_b.get_center())
			if distance <= MERGE_DISTANCE:
				# Merge smaller into larger
				if squad_a.get_unit_count() >= squad_b.get_unit_count():
					_merge_squads(squad_a_id, squad_b_id)
					merged.append(squad_b_id)
				else:
					_merge_squads(squad_b_id, squad_a_id)
					merged.append(squad_a_id)
					break


## Merge two squads.
func _merge_squads(keep_id: int, merge_id: int) -> void:
	var keep_squad: Squad = _squads.get(keep_id)
	var merge_squad: Squad = _squads.get(merge_id)

	if keep_squad == null or merge_squad == null:
		return

	# Move units to kept squad
	for unit_id in merge_squad.get_unit_ids():
		keep_squad.add_unit(unit_id)
		_unit_squad[unit_id] = keep_id

	# Remove merged squad
	_squads.erase(merge_id)
	squads_merged.emit(keep_id, merge_id)


## Check for squads that should split.
func _check_squad_splits(positions: Dictionary) -> void:
	var to_process: Array[int] = []
	for squad_id in _squads:
		to_process.append(squad_id)

	for squad_id in to_process:
		var squad: Squad = _squads.get(squad_id)
		if squad == null or squad.get_unit_count() < 4:
			continue

		# Find units far from center
		var center := squad.get_center()
		var far_units: Array[int] = []

		for unit_id in squad.get_unit_ids():
			if positions.has(unit_id):
				var distance := positions[unit_id].distance_to(center)
				if distance > SPLIT_DISTANCE:
					far_units.append(unit_id)

		# Split if enough units are far
		if far_units.size() >= 2:
			_split_squad(squad_id, far_units)


## Split units from squad into new squad.
func _split_squad(squad_id: int, unit_ids: Array[int]) -> void:
	var squad: Squad = _squads.get(squad_id)
	if squad == null:
		return

	# Create new squad
	var new_id := _next_squad_id
	_next_squad_id += 1

	var new_squad := Squad.new(new_id)
	new_squad.configure_for_faction(squad.faction_id)

	# Move units
	for unit_id in unit_ids:
		squad.remove_unit(unit_id)
		new_squad.add_unit(unit_id)
		_unit_squad[unit_id] = new_id

	_squads[new_id] = new_squad
	squad_split.emit(squad_id, new_id)


## Disband squad.
func _disband_squad(squad_id: int) -> void:
	if _squads.has(squad_id):
		_squads.erase(squad_id)
		squad_disbanded.emit(squad_id)


## Register unit with system.
func register_unit(unit_id: int, faction_id: String) -> void:
	if _unit_squad.has(unit_id):
		return

	if _unit_squad.size() >= MAX_UNITS:
		return

	# Find nearby squad or create new one
	var target_squad_id := _find_nearby_squad(unit_id, faction_id)

	if target_squad_id == -1:
		target_squad_id = _create_squad(faction_id)

	var squad: Squad = _squads.get(target_squad_id)
	if squad:
		squad.add_unit(unit_id)
		_unit_squad[unit_id] = target_squad_id


## Find nearby squad for unit.
func _find_nearby_squad(unit_id: int, faction_id: String) -> int:
	if not _get_unit_position.is_valid():
		return -1

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	if unit_pos == Vector3.INF:
		return -1

	var best_squad_id := -1
	var best_distance := AUTO_GROUP_DISTANCE

	for squad_id in _squads:
		var squad: Squad = _squads[squad_id]
		if squad.faction_id != faction_id:
			continue

		if squad.get_unit_count() >= Squad.MAX_SQUAD_SIZE:
			continue

		var distance := squad.get_center().distance_to(unit_pos)
		if distance < best_distance:
			best_distance = distance
			best_squad_id = squad_id

	return best_squad_id


## Create new squad.
func _create_squad(faction_id: String) -> int:
	if _squads.size() >= MAX_SQUADS:
		return -1

	var squad_id := _next_squad_id
	_next_squad_id += 1

	var squad := Squad.new(squad_id)
	squad.configure_for_faction(faction_id)

	_squads[squad_id] = squad
	squad_formed.emit(squad_id, [])

	return squad_id


## Unregister unit from system.
func unregister_unit(unit_id: int) -> void:
	if not _unit_squad.has(unit_id):
		return

	var squad_id: int = _unit_squad[unit_id]
	var squad: Squad = _squads.get(squad_id)

	if squad:
		squad.remove_unit(unit_id)

	_unit_squad.erase(unit_id)


## Record unit death.
func record_unit_death(unit_id: int) -> void:
	if not _unit_squad.has(unit_id):
		return

	var squad_id: int = _unit_squad[unit_id]
	var squad: Squad = _squads.get(squad_id)

	if squad:
		squad.record_death(unit_id)

	_unit_squad.erase(unit_id)


## Get desired position for unit.
func get_desired_position(unit_id: int) -> Vector3:
	if not _unit_squad.has(unit_id):
		return Vector3.INF

	var squad_id: int = _unit_squad[unit_id]
	var squad: Squad = _squads.get(squad_id)

	if squad:
		return squad.get_desired_position(unit_id)

	return Vector3.INF


## Get all desired positions.
func _get_all_desired_positions() -> Dictionary:
	var positions: Dictionary = {}

	for squad_id in _squads:
		var squad: Squad = _squads[squad_id]
		var squad_positions := squad.get_desired_positions()
		for unit_id in squad_positions:
			positions[unit_id] = squad_positions[unit_id]

	return positions


## Get squad for unit.
func get_unit_squad(unit_id: int) -> Squad:
	if not _unit_squad.has(unit_id):
		return null

	var squad_id: int = _unit_squad[unit_id]
	return _squads.get(squad_id)


## Get squad by ID.
func get_squad(squad_id: int) -> Squad:
	return _squads.get(squad_id)


## Get squad count.
func get_squad_count() -> int:
	return _squads.size()


## Get unit count.
func get_unit_count() -> int:
	return _unit_squad.size()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var squads_data: Dictionary = {}
	for squad_id in _squads:
		squads_data[str(squad_id)] = _squads[squad_id].to_dict()

	var unit_squad_data: Dictionary = {}
	for unit_id in _unit_squad:
		unit_squad_data[str(unit_id)] = _unit_squad[unit_id]

	return {
		"squads": squads_data,
		"unit_squad": unit_squad_data,
		"next_squad_id": _next_squad_id
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_squads.clear()
	for squad_id_str in data.get("squads", {}):
		var squad := Squad.new()
		squad.from_dict(data["squads"][squad_id_str])
		_squads[int(squad_id_str)] = squad

	_unit_squad.clear()
	for unit_id_str in data.get("unit_squad", {}):
		_unit_squad[int(unit_id_str)] = data["unit_squad"][unit_id_str]

	_next_squad_id = data.get("next_squad_id", 0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var squad_summaries: Array[Dictionary] = []
	for squad_id in _squads:
		squad_summaries.append(_squads[squad_id].get_summary())

	return {
		"total_units": _unit_squad.size(),
		"total_squads": _squads.size(),
		"update_frequency": "%.0f Hz" % UPDATE_FREQUENCY,
		"squads": squad_summaries
	}
