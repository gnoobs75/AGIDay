class_name TacticalBehaviorManager
extends RefCounted
## TacticalBehaviorManager coordinates dodge and flank behaviors for units.

signal behavior_changed(unit_id: int, behavior_type: String)
signal dodge_executed(unit_id: int)
signal flank_executed(unit_id: int, target_id: int)

## Behavior types
enum BehaviorType {
	NONE,
	DODGE,
	FLANK,
	DODGE_AND_FLANK
}

## Behavior tree status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Sub-behaviors
var dodge_behavior: DodgeBehavior = null
var flank_behavior: FlankBehavior = null

## Unit behavior assignments (unit_id -> BehaviorType)
var _unit_behaviors: Dictionary = {}

## Unit targets for flanking (unit_id -> target_id)
var _unit_flank_targets: Dictionary = {}

## Callbacks
var _get_unit_position: Callable
var _get_unit_attack_range: Callable
var _get_target_position: Callable
var _get_nearby_projectiles: Callable
var _request_movement: Callable
var _is_position_valid: Callable


func _init() -> void:
	dodge_behavior = DodgeBehavior.new()
	flank_behavior = FlankBehavior.new()

	# Connect signals
	dodge_behavior.dodge_triggered.connect(_on_dodge_triggered)
	dodge_behavior.dodge_completed.connect(_on_dodge_completed)
	flank_behavior.flank_started.connect(_on_flank_started)
	flank_behavior.flank_reached.connect(_on_flank_reached)


## Set all callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback
	dodge_behavior.set_get_unit_position(callback)
	flank_behavior.set_get_unit_position(callback)


func set_get_unit_attack_range(callback: Callable) -> void:
	_get_unit_attack_range = callback
	flank_behavior.set_get_unit_attack_range(callback)


func set_get_target_position(callback: Callable) -> void:
	_get_target_position = callback
	flank_behavior.set_get_target_position(callback)


func set_get_nearby_projectiles(callback: Callable) -> void:
	_get_nearby_projectiles = callback
	dodge_behavior.set_get_nearby_projectiles(callback)


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback
	dodge_behavior.set_request_movement(callback)
	flank_behavior.set_request_movement(callback)


func set_is_position_valid(callback: Callable) -> void:
	_is_position_valid = callback
	flank_behavior.set_is_position_valid(callback)


## Assign behavior type to unit.
func assign_behavior(unit_id: int, behavior_type: int) -> void:
	var old_type: int = _unit_behaviors.get(unit_id, BehaviorType.NONE)
	_unit_behaviors[unit_id] = behavior_type

	if old_type != behavior_type:
		behavior_changed.emit(unit_id, BehaviorType.keys()[behavior_type])


## Set flank target for unit.
func set_flank_target(unit_id: int, target_id: int) -> void:
	_unit_flank_targets[unit_id] = target_id


## Execute behavior for unit.
func execute(unit_id: int, delta: float) -> int:
	var behavior_type: int = _unit_behaviors.get(unit_id, BehaviorType.NONE)

	match behavior_type:
		BehaviorType.NONE:
			return Status.FAILURE
		BehaviorType.DODGE:
			return dodge_behavior.execute(unit_id, delta)
		BehaviorType.FLANK:
			return _execute_flank(unit_id, delta)
		BehaviorType.DODGE_AND_FLANK:
			return _execute_dodge_and_flank(unit_id, delta)

	return Status.FAILURE


## Execute flank behavior.
func _execute_flank(unit_id: int, delta: float) -> int:
	var target_id: int = _unit_flank_targets.get(unit_id, -1)
	if target_id == -1:
		return Status.FAILURE

	return flank_behavior.execute(unit_id, target_id, delta)


## Execute combined dodge and flank behavior.
func _execute_dodge_and_flank(unit_id: int, delta: float) -> int:
	# Dodge takes priority
	if dodge_behavior.should_dodge(unit_id):
		return dodge_behavior.execute(unit_id, delta)

	# Otherwise flank
	if dodge_behavior.is_dodging(unit_id):
		# Wait for dodge to complete
		return dodge_behavior.execute(unit_id, delta)

	return _execute_flank(unit_id, delta)


## Update all units (batch processing).
func update(delta: float) -> void:
	for unit_id in _unit_behaviors:
		execute(unit_id, delta)


## Clear unit from system.
func clear_unit(unit_id: int) -> void:
	_unit_behaviors.erase(unit_id)
	_unit_flank_targets.erase(unit_id)
	dodge_behavior.clear_unit(unit_id)
	flank_behavior.clear_unit(unit_id)


## Check if unit should dodge.
func should_dodge(unit_id: int) -> bool:
	return dodge_behavior.should_dodge(unit_id)


## Check if unit is dodging.
func is_dodging(unit_id: int) -> bool:
	return dodge_behavior.is_dodging(unit_id)


## Check if unit is flanking.
func is_flanking(unit_id: int) -> bool:
	return flank_behavior.is_flanking(unit_id)


## Get current behavior for unit.
func get_behavior(unit_id: int) -> int:
	return _unit_behaviors.get(unit_id, BehaviorType.NONE)


## Signal handlers.
func _on_dodge_triggered(unit_id: int, direction: Vector3) -> void:
	dodge_executed.emit(unit_id)


func _on_dodge_completed(unit_id: int) -> void:
	pass  # Could resume flanking here


func _on_flank_started(unit_id: int, target_id: int, position: Vector3) -> void:
	flank_executed.emit(unit_id, target_id)


func _on_flank_reached(unit_id: int, target_id: int) -> void:
	pass  # Could start attack here


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var behaviors_data: Dictionary = {}
	for unit_id in _unit_behaviors:
		behaviors_data[str(unit_id)] = _unit_behaviors[unit_id]

	var targets_data: Dictionary = {}
	for unit_id in _unit_flank_targets:
		targets_data[str(unit_id)] = _unit_flank_targets[unit_id]

	return {
		"unit_behaviors": behaviors_data,
		"unit_flank_targets": targets_data,
		"dodge_behavior": dodge_behavior.to_dict(),
		"flank_behavior": flank_behavior.to_dict()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_behaviors.clear()
	for unit_id_str in data.get("unit_behaviors", {}):
		_unit_behaviors[int(unit_id_str)] = data["unit_behaviors"][unit_id_str]

	_unit_flank_targets.clear()
	for unit_id_str in data.get("unit_flank_targets", {}):
		_unit_flank_targets[int(unit_id_str)] = data["unit_flank_targets"][unit_id_str]

	dodge_behavior.from_dict(data.get("dodge_behavior", {}))
	flank_behavior.from_dict(data.get("flank_behavior", {}))


## Get summary for debugging.
func get_summary() -> Dictionary:
	var behavior_counts: Dictionary = {}
	for behavior_type in BehaviorType.values():
		behavior_counts[BehaviorType.keys()[behavior_type]] = 0

	for unit_id in _unit_behaviors:
		var type_name: String = BehaviorType.keys()[_unit_behaviors[unit_id]]
		behavior_counts[type_name] += 1

	return {
		"total_units": _unit_behaviors.size(),
		"behavior_counts": behavior_counts,
		"dodge": dodge_behavior.get_summary(),
		"flank": flank_behavior.get_summary()
	}
