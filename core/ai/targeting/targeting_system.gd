class_name TargetingSystem
extends RefCounted
## TargetingSystem manages target selection with evolutionary AI.

signal target_selected(unit_id: int, target_id: int, reason: String)
signal target_lost(unit_id: int, old_target: int)
signal targeting_mode_evolved(faction_id: String, new_mode: String)

## Performance settings
const MAX_UPDATE_TIME_MS := 3.0
const DEFAULT_UPDATE_FREQUENCY := 30.0  ## Hz
const MAX_UNITS := 5000

## Visibility range
const DEFAULT_VISIBILITY_RANGE := 30.0

## Sub-systems
var threat_calculator: ThreatCalculator = null
var priority_targeting: PriorityTargeting = null

## Targeting modes per faction (faction_id -> TargetingMode)
var _faction_modes: Dictionary = {}

## Current targets (unit_id -> target_id)
var _current_targets: Dictionary = {}

## Update timing
var _update_accumulator: float = 0.0
var _update_frequency: float = DEFAULT_UPDATE_FREQUENCY

## Visibility range
var visibility_range: float = DEFAULT_VISIBILITY_RANGE

## Callbacks
var _get_unit_position: Callable
var _get_unit_faction: Callable
var _get_faction_xp: Callable
var _get_enemies_in_range: Callable  ## (position, range, faction_id) -> Array[int]
var _get_unit_type: Callable
var _get_unit_health_percent: Callable


func _init() -> void:
	threat_calculator = ThreatCalculator.new()
	priority_targeting = PriorityTargeting.new()


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback
	priority_targeting.set_get_unit_position(callback)


func set_get_unit_faction(callback: Callable) -> void:
	_get_unit_faction = callback


func set_get_faction_xp(callback: Callable) -> void:
	_get_faction_xp = callback


func set_get_enemies_in_range(callback: Callable) -> void:
	_get_enemies_in_range = callback


func set_get_unit_type(callback: Callable) -> void:
	_get_unit_type = callback
	priority_targeting.set_get_unit_type(callback)


func set_get_unit_health_percent(callback: Callable) -> void:
	_get_unit_health_percent = callback
	priority_targeting.set_get_unit_health_percent(callback)


## Set update frequency.
func set_update_frequency(hz: float) -> void:
	_update_frequency = clampf(hz, 15.0, 60.0)


## Record damage for threat calculation.
func record_damage(attacker_id: int, victim_id: int, damage: float, attacker_dps: float = 0.0) -> void:
	threat_calculator.record_damage(attacker_id, damage, attacker_dps)


## Update system (called each frame).
func update(delta: float) -> void:
	threat_calculator.update(delta)

	_update_accumulator += delta
	var update_interval := 1.0 / _update_frequency

	if _update_accumulator >= update_interval:
		_update_accumulator -= update_interval
		_process_targeting_update()


## Process targeting update.
func _process_targeting_update() -> void:
	var start_time := Time.get_ticks_usec()

	# Update faction modes
	_update_faction_modes()

	# Update unit targets
	for unit_id in _current_targets.keys():
		var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed > MAX_UPDATE_TIME_MS:
			break

		_update_unit_target(unit_id)


## Update faction targeting modes.
func _update_faction_modes() -> void:
	if not _get_faction_xp.is_valid():
		return

	for faction_id in _faction_modes:
		var xp: float = _get_faction_xp.call(faction_id)
		var mode: TargetingMode = _faction_modes[faction_id]
		var old_mode := mode.mode

		mode.update_from_xp(xp)

		if old_mode != mode.mode:
			targeting_mode_evolved.emit(faction_id, mode.get_mode_name())


## Update target for single unit.
func _update_unit_target(unit_id: int) -> void:
	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	if unit_pos == Vector3.INF:
		return

	# Get unit faction
	var faction_id := ""
	if _get_unit_faction.is_valid():
		faction_id = _get_unit_faction.call(unit_id)

	# Ensure faction mode exists
	if not _faction_modes.has(faction_id):
		_faction_modes[faction_id] = TargetingMode.new()

	var mode: TargetingMode = _faction_modes[faction_id]

	# Get visible enemies
	var enemies: Array = _get_enemies_in_range.call(unit_pos, visibility_range, faction_id)
	if enemies.is_empty():
		var old_target: int = _current_targets.get(unit_id, -1)
		if old_target != -1:
			_current_targets[unit_id] = -1
			target_lost.emit(unit_id, old_target)
		return

	# Convert to typed array
	var enemy_ids: Array[int] = []
	for e in enemies:
		enemy_ids.append(e)

	# Select target based on mode weights
	var target := _select_target_weighted(unit_id, unit_pos, enemy_ids, mode)

	var old_target: int = _current_targets.get(unit_id, -1)
	if target != old_target:
		_current_targets[unit_id] = target
		if target != -1:
			target_selected.emit(unit_id, target, _get_target_reason(mode))
		elif old_target != -1:
			target_lost.emit(unit_id, old_target)


## Select target using weighted modes.
func _select_target_weighted(unit_id: int, unit_pos: Vector3, enemies: Array[int], mode: TargetingMode) -> int:
	if enemies.is_empty():
		return -1

	# Calculate scores for each enemy
	var scores: Array[Dictionary] = []

	for enemy_id in enemies:
		var score := 0.0

		# Nearest score
		var nearest_score := _calculate_nearest_score(enemy_id, unit_pos)
		score += nearest_score * mode.nearest_weight

		# Threat score
		var threat_score := threat_calculator.get_threat(enemy_id) / 100.0
		score += threat_score * mode.threat_weight

		# Priority score
		var priority_score := priority_targeting.calculate_priority(enemy_id, unit_pos)
		score += priority_score * mode.priority_weight

		scores.append({"id": enemy_id, "score": score})

	# Sort by score
	scores.sort_custom(func(a, b): return a["score"] > b["score"])

	if scores.is_empty():
		return -1

	return scores[0]["id"]


## Calculate nearest score (inverse distance normalized).
func _calculate_nearest_score(enemy_id: int, unit_pos: Vector3) -> float:
	if not _get_unit_position.is_valid():
		return 0.0

	var enemy_pos: Vector3 = _get_unit_position.call(enemy_id)
	if enemy_pos == Vector3.INF:
		return 0.0

	var distance := unit_pos.distance_to(enemy_pos)
	if distance < 1.0:
		return 1.0

	# Inverse distance, normalized to visibility range
	return clampf(1.0 - distance / visibility_range, 0.0, 1.0)


## Get reason string for target selection.
func _get_target_reason(mode: TargetingMode) -> String:
	match mode.mode:
		TargetingMode.Mode.NEAREST:
			return "nearest"
		TargetingMode.Mode.THREAT_BASED:
			return "threat"
		TargetingMode.Mode.PRIORITY:
			return "priority"
	return "unknown"


## Register unit with system.
func register_unit(unit_id: int) -> void:
	if not _current_targets.has(unit_id):
		_current_targets[unit_id] = -1


## Unregister unit from system.
func unregister_unit(unit_id: int) -> void:
	_current_targets.erase(unit_id)
	priority_targeting.clear_unit(unit_id)


## Get current target for unit.
func get_target(unit_id: int) -> int:
	return _current_targets.get(unit_id, -1)


## Force target selection for unit.
func force_target(unit_id: int, target_id: int) -> void:
	var old_target: int = _current_targets.get(unit_id, -1)
	_current_targets[unit_id] = target_id
	if old_target != target_id and target_id != -1:
		target_selected.emit(unit_id, target_id, "forced")


## Get targeting mode for faction.
func get_faction_mode(faction_id: String) -> TargetingMode:
	if not _faction_modes.has(faction_id):
		_faction_modes[faction_id] = TargetingMode.new()
	return _faction_modes[faction_id]


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var modes_data: Dictionary = {}
	for faction_id in _faction_modes:
		modes_data[faction_id] = _faction_modes[faction_id].to_dict()

	var targets_data: Dictionary = {}
	for unit_id in _current_targets:
		targets_data[str(unit_id)] = _current_targets[unit_id]

	return {
		"faction_modes": modes_data,
		"current_targets": targets_data,
		"visibility_range": visibility_range,
		"update_frequency": _update_frequency,
		"threat_calculator": threat_calculator.to_dict(),
		"priority_targeting": priority_targeting.to_dict()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_faction_modes.clear()
	for faction_id in data.get("faction_modes", {}):
		var mode := TargetingMode.new()
		mode.from_dict(data["faction_modes"][faction_id])
		_faction_modes[faction_id] = mode

	_current_targets.clear()
	for unit_id_str in data.get("current_targets", {}):
		_current_targets[int(unit_id_str)] = data["current_targets"][unit_id_str]

	visibility_range = data.get("visibility_range", DEFAULT_VISIBILITY_RANGE)
	_update_frequency = data.get("update_frequency", DEFAULT_UPDATE_FREQUENCY)

	threat_calculator.from_dict(data.get("threat_calculator", {}))
	priority_targeting.from_dict(data.get("priority_targeting", {}))


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_summaries: Dictionary = {}
	for faction_id in _faction_modes:
		faction_summaries[faction_id] = _faction_modes[faction_id].get_summary()

	var units_with_targets := 0
	for unit_id in _current_targets:
		if _current_targets[unit_id] != -1:
			units_with_targets += 1

	return {
		"tracked_units": _current_targets.size(),
		"units_with_targets": units_with_targets,
		"factions": faction_summaries,
		"threat": threat_calculator.get_summary(),
		"priority": priority_targeting.get_summary(),
		"update_frequency": "%.0f Hz" % _update_frequency
	}
