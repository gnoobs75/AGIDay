class_name BuilderAIController
extends RefCounted
## BuilderAIController manages autonomous builder behavior.
## Implements scan → select → navigate → repair → repeat loop.

signal state_changed(builder_id: int, old_state: int, new_state: int)
signal target_selected(builder_id: int, target_id: int, target_position: Vector3)
signal repair_started(builder_id: int, target_id: int)
signal repair_completed(builder_id: int, target_id: int)
signal threat_detected(builder_id: int, threat_id: int)
signal evade_started(builder_id: int, threat_id: int)

## Configuration
const REPAIR_RANGE := 5.0
const SCAN_RADIUS := 50.0
const THREAT_DETECTION_RANGE := 20.0
const EVADE_DURATION := 2.0
const SCAN_INTERVAL := 1.0  ## Seconds between scans

## Builder data class
class BuilderData extends RefCounted:
	var builder_id: int
	var faction_id: String
	var current_state: int = BuilderAIState.State.IDLE
	var target_id: int = -1
	var target_position: Vector3 = Vector3.INF
	var current_position: Vector3 = Vector3.ZERO
	var last_scan_time: float = 0.0
	var evade_start_time: float = 0.0
	var evade_direction: Vector3 = Vector3.ZERO

	## Faction special abilities
	var can_repair_while_moving: bool = false
	var can_repair_while_dodging: bool = false


## Registered builders (builder_id -> BuilderData)
var _builders: Dictionary = {}

## Callbacks
var _get_position: Callable  ## (builder_id) -> Vector3
var _get_repair_targets: Callable  ## (position, radius) -> Array
var _get_threats: Callable  ## (position, radius) -> Array
var _request_navigation: Callable  ## (builder_id, target_pos) -> void
var _start_repair: Callable  ## (builder_id, target_id) -> void
var _stop_repair: Callable  ## (builder_id) -> void
var _is_target_repaired: Callable  ## (target_id) -> bool
var _get_evade_position: Callable  ## (builder_id, threat_pos) -> Vector3


func _init() -> void:
	pass


## Set callbacks.
func set_get_position(callback: Callable) -> void:
	_get_position = callback


func set_get_repair_targets(callback: Callable) -> void:
	_get_repair_targets = callback


func set_get_threats(callback: Callable) -> void:
	_get_threats = callback


func set_request_navigation(callback: Callable) -> void:
	_request_navigation = callback


func set_start_repair(callback: Callable) -> void:
	_start_repair = callback


func set_stop_repair(callback: Callable) -> void:
	_stop_repair = callback


func set_is_target_repaired(callback: Callable) -> void:
	_is_target_repaired = callback


func set_get_evade_position(callback: Callable) -> void:
	_get_evade_position = callback


## Register builder.
func register_builder(builder_id: int, faction_id: String) -> void:
	var data := BuilderData.new()
	data.builder_id = builder_id
	data.faction_id = faction_id

	# Set faction-specific abilities
	match faction_id.to_lower():
		"aether_swarm":
			data.can_repair_while_moving = true
		"dynapods":
			data.can_repair_while_dodging = true

	_builders[builder_id] = data


## Unregister builder.
func unregister_builder(builder_id: int) -> void:
	_builders.erase(builder_id)


## Update all builders - call each frame.
func update(delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0

	for builder_id in _builders:
		_update_builder(builder_id, delta, current_time)


## Update single builder.
func _update_builder(builder_id: int, delta: float, current_time: float) -> void:
	var data: BuilderData = _builders[builder_id]

	# Update position
	if _get_position.is_valid():
		data.current_position = _get_position.call(builder_id)

	# Check for threats first (highest priority)
	if _check_for_threats(data, current_time):
		return

	# Process current state
	match data.current_state:
		BuilderAIState.State.IDLE:
			_process_idle_state(data, current_time)
		BuilderAIState.State.SCANNING:
			_process_scanning_state(data, current_time)
		BuilderAIState.State.NAVIGATING:
			_process_navigating_state(data)
		BuilderAIState.State.REPAIRING:
			_process_repairing_state(data)
		BuilderAIState.State.EVADING:
			_process_evading_state(data, current_time)
		BuilderAIState.State.RETREATING:
			_process_retreating_state(data)


## Check for nearby threats.
func _check_for_threats(data: BuilderData, current_time: float) -> bool:
	if data.current_state == BuilderAIState.State.EVADING:
		return false  ## Already evading

	if not _get_threats.is_valid():
		return false

	var threats: Array = _get_threats.call(data.current_position, THREAT_DETECTION_RANGE)

	if threats.is_empty():
		return false

	var threat_id: int = threats[0]
	threat_detected.emit(data.builder_id, threat_id)

	# Start evading
	_transition_state(data, BuilderAIState.State.EVADING)
	data.evade_start_time = current_time

	if _get_evade_position.is_valid() and _get_position.is_valid():
		var threat_pos: Vector3 = _get_position.call(threat_id)
		var evade_pos: Vector3 = _get_evade_position.call(data.builder_id, threat_pos)

		if _request_navigation.is_valid() and evade_pos != Vector3.INF:
			_request_navigation.call(data.builder_id, evade_pos)

	evade_started.emit(data.builder_id, threat_id)

	return true


## Process idle state.
func _process_idle_state(data: BuilderData, current_time: float) -> void:
	if current_time - data.last_scan_time >= SCAN_INTERVAL:
		_transition_state(data, BuilderAIState.State.SCANNING)


## Process scanning state.
func _process_scanning_state(data: BuilderData, current_time: float) -> void:
	data.last_scan_time = current_time

	if not _get_repair_targets.is_valid():
		_transition_state(data, BuilderAIState.State.IDLE)
		return

	var targets: Array = _get_repair_targets.call(data.current_position, SCAN_RADIUS)

	if targets.is_empty():
		_transition_state(data, BuilderAIState.State.IDLE)
		return

	# Select best target (first one for now)
	var target: Dictionary = targets[0]
	data.target_id = target.get("id", -1)
	data.target_position = target.get("position", Vector3.INF)

	target_selected.emit(data.builder_id, data.target_id, data.target_position)

	# Check if already in range
	if _is_in_repair_range(data):
		_transition_state(data, BuilderAIState.State.REPAIRING)
		_begin_repair(data)
	else:
		_transition_state(data, BuilderAIState.State.NAVIGATING)
		_navigate_to_target(data)


## Process navigating state.
func _process_navigating_state(data: BuilderData) -> void:
	if data.target_id == -1 or data.target_position == Vector3.INF:
		_transition_state(data, BuilderAIState.State.SCANNING)
		return

	# Check if target still needs repair
	if _is_target_repaired.is_valid() and _is_target_repaired.call(data.target_id):
		_transition_state(data, BuilderAIState.State.SCANNING)
		return

	# Check if in range
	if _is_in_repair_range(data):
		_transition_state(data, BuilderAIState.State.REPAIRING)
		_begin_repair(data)
		return

	# Faction ability: repair while moving (Aether Swarm)
	if data.can_repair_while_moving and _is_in_repair_range(data, REPAIR_RANGE * 2.0):
		# Can repair at reduced efficiency while moving
		if _start_repair.is_valid():
			_start_repair.call(data.builder_id, data.target_id)


## Process repairing state.
func _process_repairing_state(data: BuilderData) -> void:
	if data.target_id == -1:
		_transition_state(data, BuilderAIState.State.SCANNING)
		return

	# Check if repair complete
	if _is_target_repaired.is_valid() and _is_target_repaired.call(data.target_id):
		repair_completed.emit(data.builder_id, data.target_id)

		if _stop_repair.is_valid():
			_stop_repair.call(data.builder_id)

		data.target_id = -1
		data.target_position = Vector3.INF

		_transition_state(data, BuilderAIState.State.SCANNING)
		return

	# Check if still in range
	if not _is_in_repair_range(data):
		if _stop_repair.is_valid():
			_stop_repair.call(data.builder_id)
		_transition_state(data, BuilderAIState.State.NAVIGATING)
		_navigate_to_target(data)


## Process evading state.
func _process_evading_state(data: BuilderData, current_time: float) -> void:
	if current_time - data.evade_start_time >= EVADE_DURATION:
		# Check if still threatened
		if _get_threats.is_valid():
			var threats: Array = _get_threats.call(data.current_position, THREAT_DETECTION_RANGE)

			if not threats.is_empty():
				# Continue evading
				data.evade_start_time = current_time
				return

		# Safe, resume normal operation
		_transition_state(data, BuilderAIState.State.SCANNING)

	# Faction ability: repair while dodging (Dynapods)
	if data.can_repair_while_dodging and data.target_id != -1:
		if _is_in_repair_range(data, REPAIR_RANGE * 1.5):
			if _start_repair.is_valid():
				_start_repair.call(data.builder_id, data.target_id)


## Process retreating state.
func _process_retreating_state(data: BuilderData) -> void:
	# Placeholder for retreat behavior
	_transition_state(data, BuilderAIState.State.IDLE)


## Check if in repair range.
func _is_in_repair_range(data: BuilderData, range_override: float = -1.0) -> bool:
	if data.target_position == Vector3.INF:
		return false

	var check_range := range_override if range_override > 0 else REPAIR_RANGE
	return data.current_position.distance_to(data.target_position) <= check_range


## Navigate to target.
func _navigate_to_target(data: BuilderData) -> void:
	if _request_navigation.is_valid() and data.target_position != Vector3.INF:
		_request_navigation.call(data.builder_id, data.target_position)


## Begin repair.
func _begin_repair(data: BuilderData) -> void:
	if _start_repair.is_valid() and data.target_id != -1:
		_start_repair.call(data.builder_id, data.target_id)
		repair_started.emit(data.builder_id, data.target_id)


## Transition state.
func _transition_state(data: BuilderData, new_state: int) -> void:
	if not BuilderAIState.is_valid_transition(data.current_state, new_state):
		return

	var old_state := data.current_state
	data.current_state = new_state

	state_changed.emit(data.builder_id, old_state, new_state)


## Get builder state.
func get_builder_state(builder_id: int) -> int:
	if not _builders.has(builder_id):
		return BuilderAIState.State.IDLE
	return _builders[builder_id].current_state


## Get builder target.
func get_builder_target(builder_id: int) -> int:
	if not _builders.has(builder_id):
		return -1
	return _builders[builder_id].target_id


## Force builder to scan.
func force_scan(builder_id: int) -> void:
	if not _builders.has(builder_id):
		return

	var data: BuilderData = _builders[builder_id]
	data.last_scan_time = 0.0
	_transition_state(data, BuilderAIState.State.SCANNING)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var state_counts: Dictionary = {}
	for state in BuilderAIState.State.values():
		state_counts[BuilderAIState.get_state_name(state)] = 0

	for builder_id in _builders:
		var state_name := BuilderAIState.get_state_name(_builders[builder_id].current_state)
		state_counts[state_name] += 1

	return {
		"registered_builders": _builders.size(),
		"state_distribution": state_counts
	}
