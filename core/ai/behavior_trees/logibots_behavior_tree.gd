class_name LogiBotsBehaviorTree
extends RefCounted
## LogiBotsBehaviorTree implements heavy lifting, cargo transport, and siege tactics.

## Behavior tree status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

## Root node
var _root: BehaviorTreeNode = null

## Callbacks
var _get_unit_position: Callable
var _get_unit_type: Callable
var _get_enemies_in_range: Callable
var _get_allies_in_range: Callable
var _set_attack_target: Callable
var _request_movement: Callable
var _get_cargo: Callable  ## (unit_id) -> Dictionary
var _set_cargo: Callable  ## (unit_id, cargo) -> void
var _get_pickup_targets: Callable  ## (position, radius) -> Array
var _get_construct_targets: Callable  ## (position, radius) -> Array
var _start_construction: Callable  ## (unit_id, target) -> void
var _sync_with_allies: Callable  ## (unit_id) -> Array


func _init() -> void:
	_build_behavior_tree()


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_type(callback: Callable) -> void:
	_get_unit_type = callback


func set_get_enemies_in_range(callback: Callable) -> void:
	_get_enemies_in_range = callback


func set_get_allies_in_range(callback: Callable) -> void:
	_get_allies_in_range = callback


func set_attack_target(callback: Callable) -> void:
	_set_attack_target = callback


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback


func set_get_cargo(callback: Callable) -> void:
	_get_cargo = callback


func set_set_cargo(callback: Callable) -> void:
	_set_cargo = callback


func set_get_pickup_targets(callback: Callable) -> void:
	_get_pickup_targets = callback


func set_get_construct_targets(callback: Callable) -> void:
	_get_construct_targets = callback


func set_start_construction(callback: Callable) -> void:
	_start_construction = callback


func set_sync_with_allies(callback: Callable) -> void:
	_sync_with_allies = callback


## Build the behavior tree structure.
func _build_behavior_tree() -> void:
	_root = BehaviorTreeNode.Selector.new("logibots_root")

	# Priority 1: Synchronized strike when allies ready
	var sync_sequence := BehaviorTreeNode.Sequence.new("sync_strike_sequence")
	sync_sequence.add_child(BehaviorTreeNode.Condition.new("allies_synced", _check_allies_synced))
	sync_sequence.add_child(BehaviorTreeNode.Condition.new("enemy_in_range", _check_enemy_in_range))
	sync_sequence.add_child(BehaviorTreeNode.Action.new("synchronized_strike", _action_synchronized_strike))
	_root.add_child(sync_sequence)

	# Priority 2: Siege construction
	var siege_sequence := BehaviorTreeNode.Sequence.new("siege_sequence")
	siege_sequence.add_child(BehaviorTreeNode.Condition.new("can_build_siege", _check_can_build_siege))
	siege_sequence.add_child(BehaviorTreeNode.Action.new("construct_siege", _action_construct_siege))
	_root.add_child(siege_sequence)

	# Priority 3: Cargo delivery
	var deliver_sequence := BehaviorTreeNode.Sequence.new("deliver_sequence")
	deliver_sequence.add_child(BehaviorTreeNode.Condition.new("has_cargo", _check_has_cargo))
	deliver_sequence.add_child(BehaviorTreeNode.Action.new("deliver_cargo", _action_deliver_cargo))
	_root.add_child(deliver_sequence)

	# Priority 4: Pickup cargo
	var pickup_sequence := BehaviorTreeNode.Sequence.new("pickup_sequence")
	pickup_sequence.add_child(BehaviorTreeNode.Condition.new("cargo_available", _check_cargo_available))
	pickup_sequence.add_child(BehaviorTreeNode.Action.new("pickup_cargo", _action_pickup_cargo))
	_root.add_child(pickup_sequence)

	# Priority 5: Heavy lift support
	var lift_sequence := BehaviorTreeNode.Sequence.new("lift_sequence")
	lift_sequence.add_child(BehaviorTreeNode.Condition.new("lift_needed", _check_lift_needed))
	lift_sequence.add_child(BehaviorTreeNode.Action.new("heavy_lift", _action_heavy_lift))
	_root.add_child(lift_sequence)

	# Priority 6: Standard combat
	var combat_sequence := BehaviorTreeNode.Sequence.new("combat_sequence")
	combat_sequence.add_child(BehaviorTreeNode.Condition.new("enemy_detected", _check_enemy_detected))
	combat_sequence.add_child(BehaviorTreeNode.Action.new("engage_enemy", _action_engage_enemy))
	_root.add_child(combat_sequence)

	# Priority 7: Patrol/idle
	var patrol := BehaviorTreeNode.Action.new("patrol", _action_patrol)
	_root.add_child(patrol)


## Execute behavior tree.
func execute(unit_id: int) -> int:
	var context := {
		"unit_id": unit_id,
		"faction_id": "logibots"
	}

	if _get_unit_type.is_valid():
		context["unit_type"] = _get_unit_type.call(unit_id)
	else:
		context["unit_type"] = "hauler"

	return _root.execute(context)


## Condition: Allies synced for coordinated attack.
func _check_allies_synced(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _sync_with_allies.is_valid():
		return false

	var synced_allies: Array = _sync_with_allies.call(unit_id)

	if synced_allies.size() >= 2:  ## Need at least 2 allies synced
		context["synced_allies"] = synced_allies
		return true

	return false


## Condition: Enemy in range for synchronized strike.
func _check_enemy_in_range(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 20.0, "logibots")

	if not enemies.is_empty():
		context["strike_target"] = enemies[0]
		return true

	return false


## Condition: Can build siege equipment.
func _check_can_build_siege(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]
	var unit_type: String = context.get("unit_type", "hauler")

	# Only certain units can build siege
	if unit_type != "engineer" and unit_type != "constructor":
		return false

	if not _get_unit_position.is_valid() or not _get_construct_targets.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var targets: Array = _get_construct_targets.call(pos, 30.0)

	if not targets.is_empty():
		context["construct_target"] = targets[0]
		return true

	return false


## Condition: Has cargo to deliver.
func _check_has_cargo(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_cargo.is_valid():
		return false

	var cargo: Dictionary = _get_cargo.call(unit_id)

	if not cargo.is_empty() and cargo.get("amount", 0) > 0:
		context["cargo"] = cargo
		return true

	return false


## Condition: Cargo available for pickup.
func _check_cargo_available(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_pickup_targets.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var pickups: Array = _get_pickup_targets.call(pos, 25.0)

	if not pickups.is_empty():
		context["pickup_target"] = pickups[0]
		return true

	return false


## Condition: Heavy lift assistance needed.
func _check_lift_needed(context: Dictionary) -> bool:
	# Check for allies that need lift assistance
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_allies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var allies: Array = _get_allies_in_range.call(pos, 15.0, "logibots")

	# Check if any ally needs lift help (simplified)
	for ally_id in allies:
		if ally_id == unit_id:
			continue
		# Would check ally state for lift request
		context["lift_target"] = ally_id
		return false  ## Disabled by default, enable when lift system ready

	return false


## Condition: Enemy detected.
func _check_enemy_detected(context: Dictionary) -> bool:
	var unit_id: int = context["unit_id"]

	if not _get_unit_position.is_valid() or not _get_enemies_in_range.is_valid():
		return false

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var enemies: Array = _get_enemies_in_range.call(pos, 25.0, "logibots")

	if not enemies.is_empty():
		context["detected_enemies"] = enemies
		context["primary_target"] = enemies[0]
		return true

	return false


## Action: Synchronized strike with allies.
func _action_synchronized_strike(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var target_id: int = context.get("strike_target", -1)

	if target_id == -1:
		return Status.FAILURE

	if _set_attack_target.is_valid():
		_set_attack_target.call(unit_id, target_id)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Construct siege equipment.
func _action_construct_siege(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var target = context.get("construct_target")

	if target == null:
		return Status.FAILURE

	if not _get_unit_position.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var target_pos: Vector3 = target.get("position", Vector3.INF)

	if target_pos == Vector3.INF:
		return Status.FAILURE

	# Move to construction site
	if pos.distance_to(target_pos) > 5.0:
		if _request_movement.is_valid():
			_request_movement.call(unit_id, target_pos)
			return Status.RUNNING

	# Start construction
	if _start_construction.is_valid():
		_start_construction.call(unit_id, target)
		return Status.RUNNING

	return Status.FAILURE


## Action: Deliver cargo to destination.
func _action_deliver_cargo(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var cargo: Dictionary = context.get("cargo", {})

	if cargo.is_empty():
		return Status.FAILURE

	var destination: Vector3 = cargo.get("destination", Vector3.INF)

	if destination == Vector3.INF:
		return Status.FAILURE

	if not _get_unit_position.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)

	if pos.distance_to(destination) > 3.0:
		if _request_movement.is_valid():
			_request_movement.call(unit_id, destination)
			return Status.RUNNING

	# Deliver
	if _set_cargo.is_valid():
		_set_cargo.call(unit_id, {})  ## Clear cargo
		return Status.SUCCESS

	return Status.FAILURE


## Action: Pickup cargo.
func _action_pickup_cargo(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var pickup = context.get("pickup_target")

	if pickup == null:
		return Status.FAILURE

	if not _get_unit_position.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var pickup_pos: Vector3 = pickup.get("position", Vector3.INF)

	if pickup_pos == Vector3.INF:
		return Status.FAILURE

	if pos.distance_to(pickup_pos) > 2.0:
		if _request_movement.is_valid():
			_request_movement.call(unit_id, pickup_pos)
			return Status.RUNNING

	# Pickup
	if _set_cargo.is_valid():
		_set_cargo.call(unit_id, pickup)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Heavy lift.
func _action_heavy_lift(context: Dictionary) -> int:
	# Implementation for heavy lift assistance
	return Status.FAILURE


## Action: Engage enemy.
func _action_engage_enemy(context: Dictionary) -> int:
	var unit_id: int = context["unit_id"]
	var target_id: int = context.get("primary_target", -1)

	if target_id == -1:
		return Status.FAILURE

	if not _get_unit_position.is_valid():
		return Status.FAILURE

	var pos: Vector3 = _get_unit_position.call(unit_id)
	var target_pos: Vector3 = _get_unit_position.call(target_id)

	if target_pos == Vector3.INF:
		return Status.FAILURE

	# Move to attack range
	if pos.distance_to(target_pos) > 18.0:
		if _request_movement.is_valid():
			_request_movement.call(unit_id, target_pos)
			return Status.RUNNING

	# Attack
	if _set_attack_target.is_valid():
		_set_attack_target.call(unit_id, target_id)
		return Status.SUCCESS

	return Status.FAILURE


## Action: Patrol.
func _action_patrol(context: Dictionary) -> int:
	return Status.SUCCESS


## Get tree name.
func get_name() -> String:
	return "LogiBotsBehaviorTree"
