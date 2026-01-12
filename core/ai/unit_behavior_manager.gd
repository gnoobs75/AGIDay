class_name UnitBehaviorManager
extends RefCounted
## UnitBehaviorManager manages behavior state for all units.
## Designed for high-performance (<50μs per unit) to support 5,000+ units.
## Coordinates behavior tree evaluation with game action execution.

signal unit_registered(unit_id: int)
signal unit_unregistered(unit_id: int)
signal behavior_updated(unit_id: int, action: String)
signal buff_applied(unit_id: int, buff_id: String)
signal buff_expired(unit_id: int, buff_id: String)

## Unit behavior states (unit_id -> UnitBehaviorState)
var _unit_states: Dictionary = {}

## Behavior tree wrappers (unit_id -> BehaviorTreeWrapper)
var _behavior_trees: Dictionary = {}

## Behavior tree registry for templates
var _bt_registry: BehaviorTreeRegistry = null

## Object pool for UnitBehaviorState reuse
var _state_pool: Array[UnitBehaviorState] = []
var _pool_size: int = 100

## Update statistics
var _last_update_time_us: int = 0
var _total_updates: int = 0
var _total_update_time_us: int = 0

## Batch processing
var _update_batch_size: int = 500
var _current_batch_start: int = 0
var _unit_ids_array: Array[int] = []


func _init() -> void:
	_bt_registry = BehaviorTreeRegistry.new()
	_initialize_pool()


## Initialize object pool.
func _initialize_pool() -> void:
	for i in _pool_size:
		_state_pool.append(UnitBehaviorState.new())


## Get a state from pool or create new.
func _get_state_from_pool() -> UnitBehaviorState:
	if not _state_pool.is_empty():
		return _state_pool.pop_back()
	return UnitBehaviorState.new()


## Return state to pool.
func _return_state_to_pool(state: UnitBehaviorState) -> void:
	state.reset()
	if _state_pool.size() < _pool_size * 2:
		_state_pool.append(state)


## Register a unit for behavior management.
func register_unit(unit_id: int, faction_id: int, unit_type: String, position: Vector3 = Vector3.ZERO) -> UnitBehaviorState:
	if _unit_states.has(unit_id):
		return _unit_states[unit_id]

	var state := _get_state_from_pool()
	state.initialize(unit_id, faction_id, unit_type, position)
	_unit_states[unit_id] = state

	# Create behavior tree
	var bt := _bt_registry.create_wrapper(unit_id, faction_id, unit_type, state.bt_seed)
	_behavior_trees[unit_id] = bt

	# Update ID array for batch processing
	_unit_ids_array.append(unit_id)

	unit_registered.emit(unit_id)
	return state


## Unregister a unit.
func unregister_unit(unit_id: int) -> void:
	if not _unit_states.has(unit_id):
		return

	var state: UnitBehaviorState = _unit_states[unit_id]
	_return_state_to_pool(state)
	_unit_states.erase(unit_id)
	_behavior_trees.erase(unit_id)

	# Update ID array
	var idx := _unit_ids_array.find(unit_id)
	if idx >= 0:
		_unit_ids_array.remove_at(idx)

	unit_unregistered.emit(unit_id)


## Get unit behavior state.
func get_state(unit_id: int) -> UnitBehaviorState:
	return _unit_states.get(unit_id)


## Get behavior tree wrapper for unit.
func get_behavior_tree(unit_id: int) -> BehaviorTreeWrapper:
	return _behavior_trees.get(unit_id)


## Update a single unit's behavior.
## Returns the action string for the unit to execute.
func update_unit(unit_id: int, delta: float, unit_data: Dictionary, nearby_units: Array) -> String:
	var state: UnitBehaviorState = _unit_states.get(unit_id)
	if state == null or state.is_paused:
		return "idle"

	var bt: BehaviorTreeWrapper = _behavior_trees.get(unit_id)
	if bt == null:
		return "idle"

	# Update state from unit data
	state.update_from_unit(unit_data)

	# Update buffs
	state.update_buffs(delta)

	# Prepare blackboard data
	bt.set_blackboard_var("position", state.position)
	bt.set_blackboard_var("velocity", state.velocity)
	bt.set_blackboard_var("health_ratio", state.health_ratio)
	bt.set_blackboard_var("threat_level", state.threat_level)
	bt.set_blackboard_var("delta", delta)

	# Convert nearby units to potential targets
	var potential_targets: Array = []
	var nearby_allies: Array = []
	for unit in nearby_units:
		if unit.get("faction_id", state.faction_id) == state.faction_id:
			nearby_allies.append(unit)
		else:
			potential_targets.append(unit)

	bt.set_blackboard_var("potential_targets", potential_targets)
	bt.set_blackboard_var("nearby_allies", nearby_allies)

	# Apply buff modifiers to blackboard
	bt.set_blackboard_var("damage_modifier", state.get_buff_modifier("damage"))
	bt.set_blackboard_var("speed_modifier", state.get_buff_modifier("speed"))
	bt.set_blackboard_var("armor_modifier", state.get_buff_modifier("armor"))

	# Evaluate behavior tree
	var action := bt.evaluate()

	# Update state from behavior tree
	state.current_action = action
	state.target_id = bt.get_blackboard_var("target_id", -1)
	state.target_position = bt.get_blackboard_var("target_position", Vector3.ZERO)
	state.target_distance = bt.get_blackboard_var("target_distance", INF)
	state.move_target = bt.get_blackboard_var("move_target", Vector3.ZERO)
	state.attack_target_id = bt.get_blackboard_var("attack_target_id", -1)

	behavior_updated.emit(unit_id, action)
	return action


## Update all units (batch processing for performance).
func update_all(delta: float, unit_data_provider: Callable, nearby_units_provider: Callable) -> Dictionary:
	var start_time := Time.get_ticks_usec()
	var results: Dictionary = {}

	var unit_count := _unit_ids_array.size()
	if unit_count == 0:
		return results

	# Process all units (or batch if needed)
	for unit_id in _unit_ids_array:
		var unit_data: Dictionary = unit_data_provider.call(unit_id)
		var nearby: Array = nearby_units_provider.call(unit_id)
		results[unit_id] = update_unit(unit_id, delta, unit_data, nearby)

	# Track statistics
	var end_time := Time.get_ticks_usec()
	_last_update_time_us = end_time - start_time
	_total_updates += 1
	_total_update_time_us += _last_update_time_us

	return results


## Update units in batches (for spreading load across frames).
func update_batch(delta: float, unit_data_provider: Callable, nearby_units_provider: Callable) -> Dictionary:
	var start_time := Time.get_ticks_usec()
	var results: Dictionary = {}

	var unit_count := _unit_ids_array.size()
	if unit_count == 0:
		return results

	var batch_end := mini(_current_batch_start + _update_batch_size, unit_count)

	for i in range(_current_batch_start, batch_end):
		var unit_id: int = _unit_ids_array[i]
		var unit_data: Dictionary = unit_data_provider.call(unit_id)
		var nearby: Array = nearby_units_provider.call(unit_id)
		results[unit_id] = update_unit(unit_id, delta, unit_data, nearby)

	# Move to next batch
	_current_batch_start = batch_end
	if _current_batch_start >= unit_count:
		_current_batch_start = 0

	# Track statistics
	var end_time := Time.get_ticks_usec()
	_last_update_time_us = end_time - start_time

	return results


## Set target for a unit.
func set_unit_target(unit_id: int, target_id: int, target_position: Vector3 = Vector3.ZERO, target_distance: float = INF) -> void:
	var state: UnitBehaviorState = _unit_states.get(unit_id)
	if state != null:
		state.set_target(target_id, target_position, target_distance)

	var bt: BehaviorTreeWrapper = _behavior_trees.get(unit_id)
	if bt != null:
		bt.set_target(target_id, target_position, target_distance)


## Clear target for a unit.
func clear_unit_target(unit_id: int) -> void:
	var state: UnitBehaviorState = _unit_states.get(unit_id)
	if state != null:
		state.clear_target()

	var bt: BehaviorTreeWrapper = _behavior_trees.get(unit_id)
	if bt != null:
		bt.clear_target()


## Get unit's current target ID.
func get_unit_target(unit_id: int) -> int:
	var state: UnitBehaviorState = _unit_states.get(unit_id)
	if state != null:
		return state.target_id
	return -1


## Apply a buff to a unit.
func apply_buff_to_unit(unit_id: int, buff: BehaviorBuff) -> void:
	var state: UnitBehaviorState = _unit_states.get(unit_id)
	if state != null:
		state.apply_buff(buff)
		buff_applied.emit(unit_id, buff.buff_id)


## Remove a buff from a unit.
func remove_buff_from_unit(unit_id: int, buff_id: String) -> void:
	var state: UnitBehaviorState = _unit_states.get(unit_id)
	if state != null and state.remove_buff(buff_id):
		buff_expired.emit(unit_id, buff_id)


## Apply a buff to all units of a faction.
func apply_buff_to_faction(faction_id: int, buff: BehaviorBuff) -> int:
	var count := 0
	for unit_id in _unit_states:
		var state: UnitBehaviorState = _unit_states[unit_id]
		if state.faction_id == faction_id:
			var buff_copy := BehaviorBuff.from_dict(buff.to_dict())
			state.apply_buff(buff_copy)
			buff_applied.emit(unit_id, buff.buff_id)
			count += 1
	return count


## Pause a unit's behavior.
func pause_unit(unit_id: int) -> void:
	var state: UnitBehaviorState = _unit_states.get(unit_id)
	if state != null:
		state.is_paused = true

	var bt: BehaviorTreeWrapper = _behavior_trees.get(unit_id)
	if bt != null:
		bt.pause()


## Resume a unit's behavior.
func resume_unit(unit_id: int) -> void:
	var state: UnitBehaviorState = _unit_states.get(unit_id)
	if state != null:
		state.is_paused = false

	var bt: BehaviorTreeWrapper = _behavior_trees.get(unit_id)
	if bt != null:
		bt.resume()


## Get unit count.
func get_unit_count() -> int:
	return _unit_states.size()


## Get all unit IDs.
func get_all_unit_ids() -> Array[int]:
	return _unit_ids_array.duplicate()


## Get units by faction.
func get_units_by_faction(faction_id: int) -> Array[int]:
	var result: Array[int] = []
	for unit_id in _unit_states:
		var state: UnitBehaviorState = _unit_states[unit_id]
		if state.faction_id == faction_id:
			result.append(unit_id)
	return result


## Get average update time per unit (microseconds).
func get_average_update_time_per_unit() -> float:
	if _total_updates == 0 or _unit_states.is_empty():
		return 0.0
	return float(_total_update_time_us) / float(_total_updates) / float(_unit_states.size())


## Serialize all states.
func to_dict() -> Dictionary:
	var states_data := {}
	for unit_id in _unit_states:
		states_data[unit_id] = _unit_states[unit_id].to_dict()

	return {
		"unit_states": states_data,
		"total_updates": _total_updates
	}


## Deserialize states.
func from_dict(data: Dictionary) -> void:
	_unit_states.clear()
	_behavior_trees.clear()
	_unit_ids_array.clear()

	var states_data: Dictionary = data.get("unit_states", {})
	for unit_id_str in states_data:
		var unit_id: int = int(unit_id_str)
		var state := UnitBehaviorState.from_dict(states_data[unit_id_str])
		_unit_states[unit_id] = state
		_unit_ids_array.append(unit_id)

		# Recreate behavior tree
		var bt := _bt_registry.create_wrapper(unit_id, state.faction_id, state.unit_type, state.bt_seed)
		_behavior_trees[unit_id] = bt

	_total_updates = data.get("total_updates", 0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"unit_count": _unit_states.size(),
		"pool_size": _state_pool.size(),
		"last_update_us": _last_update_time_us,
		"avg_update_per_unit_us": get_average_update_time_per_unit(),
		"total_updates": _total_updates
	}
