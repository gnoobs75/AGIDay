class_name HumanResistanceAISystem
extends RefCounted
## HumanResistanceAISystem manages batch AI updates for Human Resistance units.
## Handles 500+ units with <5ms per batch update budget.

signal unit_decision_made(unit_id: int, decision: Dictionary)
signal batch_completed(units_processed: int, time_ms: float)
signal commander_buff_applied(commander_id: int, ally_count: int)

## Performance configuration
const MAX_UNITS_PER_BATCH := 50  ## Process 50 units per frame
const TARGET_BATCH_TIME_MS := 5.0  ## Stay under 5ms per batch
const UPDATE_INTERVAL := 0.033  ## ~30Hz update rate

## Behavior tree (shared instance)
var _behavior_tree: HumanResistanceBehaviorTree = null

## Registered units (unit_id -> unit_data)
var _units: Dictionary = {}

## Batch processing state
var _pending_units: Array[int] = []
var _current_batch_index := 0
var _accumulated_time := 0.0

## Performance tracking
var _last_batch_time_ms := 0.0
var _avg_time_per_unit_ms := 0.0
var _total_updates := 0

## Callbacks
var _get_unit_position: Callable
var _get_unit_type: Callable
var _get_enemies_in_range: Callable
var _get_allies_in_range: Callable
var _set_attack_target: Callable
var _request_movement: Callable
var _get_high_ground: Callable
var _get_cover_position: Callable
var _get_patrol_point: Callable
var _apply_buff: Callable


func _init() -> void:
	_behavior_tree = HumanResistanceBehaviorTree.new()


## Set callbacks - propagate to behavior tree.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback
	_behavior_tree.set_get_unit_position(callback)


func set_get_unit_type(callback: Callable) -> void:
	_get_unit_type = callback
	_behavior_tree.set_get_unit_type(callback)


func set_get_enemies_in_range(callback: Callable) -> void:
	_get_enemies_in_range = callback
	_behavior_tree.set_get_enemies_in_range(callback)


func set_get_allies_in_range(callback: Callable) -> void:
	_get_allies_in_range = callback
	_behavior_tree.set_get_allies_in_range(callback)


func set_attack_target(callback: Callable) -> void:
	_set_attack_target = callback
	_behavior_tree.set_attack_target(callback)


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback
	_behavior_tree.set_request_movement(callback)


func set_get_high_ground(callback: Callable) -> void:
	_get_high_ground = callback
	_behavior_tree.set_get_high_ground(callback)


func set_get_cover_position(callback: Callable) -> void:
	_get_cover_position = callback
	_behavior_tree.set_get_cover_position(callback)


func set_get_patrol_point(callback: Callable) -> void:
	_get_patrol_point = callback
	_behavior_tree.set_get_patrol_point(callback)


func set_apply_buff(callback: Callable) -> void:
	_apply_buff = callback
	_behavior_tree.set_apply_buff(callback)


## Register unit for AI management.
func register_unit(unit_id: int, unit_type: String) -> void:
	_units[unit_id] = {
		"unit_type": unit_type,
		"last_update": 0.0,
		"last_decision": {},
		"priority": _calculate_priority(unit_type)
	}
	_rebuild_pending_list()


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_units.erase(unit_id)
	var idx := _pending_units.find(unit_id)
	if idx != -1:
		_pending_units.remove_at(idx)


## Calculate unit priority (commanders update first).
func _calculate_priority(unit_type: String) -> int:
	match unit_type.to_lower():
		"commander":
			return 0  ## Highest priority
		"sniper":
			return 1
		"heavy_gunner":
			return 2
		_:
			return 3


## Rebuild pending list sorted by priority.
func _rebuild_pending_list() -> void:
	_pending_units.clear()

	var unit_list: Array = []
	for unit_id in _units:
		unit_list.append({
			"id": unit_id,
			"priority": _units[unit_id]["priority"]
		})

	unit_list.sort_custom(func(a, b): return a["priority"] < b["priority"])

	for item in unit_list:
		_pending_units.append(item["id"])

	_current_batch_index = 0


## Update AI system - call each frame.
func update(delta: float) -> void:
	_accumulated_time += delta

	if _accumulated_time < UPDATE_INTERVAL:
		return

	_accumulated_time = 0.0
	_process_batch()


## Process one batch of units.
func _process_batch() -> void:
	if _pending_units.is_empty():
		return

	var start_time := Time.get_ticks_usec()
	var units_processed := 0
	var batch_end := mini(_current_batch_index + MAX_UNITS_PER_BATCH, _pending_units.size())

	while _current_batch_index < batch_end:
		var unit_id: int = _pending_units[_current_batch_index]

		if _units.has(unit_id):
			_process_unit(unit_id)
			units_processed += 1

		_current_batch_index += 1

		# Check time budget
		var elapsed_us := Time.get_ticks_usec() - start_time
		if elapsed_us > TARGET_BATCH_TIME_MS * 1000:
			break

	# Reset when complete
	if _current_batch_index >= _pending_units.size():
		_current_batch_index = 0

	# Update performance metrics
	var elapsed_ms := float(Time.get_ticks_usec() - start_time) / 1000.0
	_last_batch_time_ms = elapsed_ms

	if units_processed > 0:
		_avg_time_per_unit_ms = elapsed_ms / float(units_processed)
		_total_updates += units_processed

	batch_completed.emit(units_processed, elapsed_ms)


## Process individual unit.
func _process_unit(unit_id: int) -> void:
	var result: int = _behavior_tree.execute(unit_id)

	var decision := {
		"status": result,
		"timestamp": Time.get_ticks_msec()
	}

	_units[unit_id]["last_decision"] = decision
	_units[unit_id]["last_update"] = Time.get_ticks_msec()

	unit_decision_made.emit(unit_id, decision)


## Force immediate update for specific unit.
func update_unit_immediate(unit_id: int) -> Dictionary:
	if not _units.has(unit_id):
		return {"error": "unit_not_registered"}

	var result: int = _behavior_tree.execute(unit_id)

	var decision := {
		"status": result,
		"timestamp": Time.get_ticks_msec()
	}

	_units[unit_id]["last_decision"] = decision
	_units[unit_id]["last_update"] = Time.get_ticks_msec()

	return decision


## Get unit count by type.
func get_unit_count_by_type() -> Dictionary:
	var counts: Dictionary = {}

	for unit_id in _units:
		var unit_type: String = _units[unit_id]["unit_type"]
		counts[unit_type] = counts.get(unit_type, 0) + 1

	return counts


## Get all commanders.
func get_commanders() -> Array[int]:
	var commanders: Array[int] = []

	for unit_id in _units:
		if _units[unit_id]["unit_type"].to_lower() == "commander":
			commanders.append(unit_id)

	return commanders


## Serialization.
func to_dict() -> Dictionary:
	var units_data: Dictionary = {}
	for unit_id in _units:
		units_data[str(unit_id)] = _units[unit_id].duplicate()

	return {
		"units": units_data,
		"current_batch_index": _current_batch_index,
		"total_updates": _total_updates
	}


func from_dict(data: Dictionary) -> void:
	_units.clear()

	var units_data: Dictionary = data.get("units", {})
	for unit_id_str in units_data:
		_units[int(unit_id_str)] = units_data[unit_id_str]

	_current_batch_index = data.get("current_batch_index", 0)
	_total_updates = data.get("total_updates", 0)

	_rebuild_pending_list()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"registered_units": _units.size(),
		"units_by_type": get_unit_count_by_type(),
		"commander_count": get_commanders().size(),
		"pending_in_batch": _pending_units.size() - _current_batch_index,
		"last_batch_time_ms": _last_batch_time_ms,
		"avg_time_per_unit_ms": _avg_time_per_unit_ms,
		"total_updates": _total_updates,
		"batch_size": MAX_UNITS_PER_BATCH,
		"update_rate_hz": 1.0 / UPDATE_INTERVAL
	}
