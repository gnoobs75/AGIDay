class_name AISystem
extends RefCounted
## AISystem coordinates distributed behavior trees with faction-level learning.
## Manages 3ms frame budget for behavior tree processing.

signal unit_registered(unit_id: int, faction_id: String)
signal unit_unregistered(unit_id: int)
signal faction_leveled(faction_id: String, category: String, level: int)
signal frame_budget_exceeded(elapsed_ms: float)

## Performance configuration
const FRAME_BUDGET_MS := 3.0  ## 3ms per frame for AI processing
const MAX_UNITS_PER_FRAME := 100  ## Max units to process per frame
const UPDATE_FREQUENCY := 30.0  ## Target Hz for AI updates

## Core systems
var faction_knowledge: FactionKnowledge = null
var hive_mind: HiveMindProgression = null
var distributed_bt: DistributedBehaviorTree = null

## Processing state
var _pending_units: Array[int] = []
var _current_index := 0
var _accumulated_time := 0.0
var _update_interval := 1.0 / UPDATE_FREQUENCY

## Performance metrics
var _last_frame_time_ms := 0.0
var _avg_frame_time_ms := 0.0
var _frame_count := 0
var _budget_exceeded_count := 0

## Unit faction mapping (unit_id -> faction_id)
var _unit_factions: Dictionary = {}


func _init() -> void:
	faction_knowledge = FactionKnowledge.new()
	hive_mind = HiveMindProgression.new()
	distributed_bt = DistributedBehaviorTree.new()

	hive_mind.set_faction_knowledge(faction_knowledge)

	# Connect signals
	faction_knowledge.level_up.connect(_on_faction_level_up)
	hive_mind.buff_unlocked.connect(_on_buff_unlocked)
	hive_mind.behavior_unlocked.connect(_on_behavior_unlocked)


## Register behavior tree template.
func register_tree_template(tree_name: String, root: LimboAIWrapper.BTNode) -> void:
	distributed_bt.register_tree_template(tree_name, root)


## Register unit with AI system.
func register_unit(unit_id: int, faction_id: String, tree_name: String) -> bool:
	if not distributed_bt.register_unit(unit_id, faction_id, tree_name):
		return false

	_unit_factions[unit_id] = faction_id
	_pending_units.append(unit_id)

	# Apply current faction buffs
	hive_mind.apply_to_unit(unit_id, faction_id)

	unit_registered.emit(unit_id, faction_id)
	return true


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	distributed_bt.unregister_unit(unit_id)
	hive_mind.remove_unit(unit_id)
	_unit_factions.erase(unit_id)

	var idx := _pending_units.find(unit_id)
	if idx != -1:
		_pending_units.remove_at(idx)
		if _current_index > idx:
			_current_index -= 1

	unit_unregistered.emit(unit_id)


## Update AI system - call each frame.
func update(delta: float) -> void:
	_accumulated_time += delta

	if _accumulated_time < _update_interval:
		return

	_accumulated_time = 0.0
	_process_frame()


## Process one frame of AI updates.
func _process_frame() -> void:
	if _pending_units.is_empty():
		return

	var start_time := Time.get_ticks_usec()
	var units_processed := 0
	var budget_us := int(FRAME_BUDGET_MS * 1000)

	while units_processed < MAX_UNITS_PER_FRAME:
		if _current_index >= _pending_units.size():
			_current_index = 0

		var unit_id: int = _pending_units[_current_index]

		# Execute behavior tree
		distributed_bt.execute(unit_id)
		units_processed += 1
		_current_index += 1

		# Check time budget
		var elapsed := Time.get_ticks_usec() - start_time
		if elapsed > budget_us:
			_budget_exceeded_count += 1
			frame_budget_exceeded.emit(float(elapsed) / 1000.0)
			break

	# Update metrics
	var elapsed_ms := float(Time.get_ticks_usec() - start_time) / 1000.0
	_last_frame_time_ms = elapsed_ms
	_frame_count += 1

	# Rolling average
	_avg_frame_time_ms = (_avg_frame_time_ms * (_frame_count - 1) + elapsed_ms) / float(_frame_count)


## Update unit blackboard.
func update_unit_data(unit_id: int, key: String, value: Variant) -> void:
	distributed_bt.update_blackboard(unit_id, key, value)


## Batch update unit blackboard.
func update_unit_data_batch(unit_id: int, updates: Dictionary) -> void:
	distributed_bt.update_blackboard_batch(unit_id, updates)


## Add faction XP.
func add_faction_xp(faction_id: String, category: int, amount: float) -> void:
	faction_knowledge.add_xp(faction_id, category, amount)


## Add combat XP (convenience).
func add_combat_xp(faction_id: String, amount: float) -> void:
	add_faction_xp(faction_id, FactionKnowledge.Category.COMBAT, amount)


## Add economy XP (convenience).
func add_economy_xp(faction_id: String, amount: float) -> void:
	add_faction_xp(faction_id, FactionKnowledge.Category.ECONOMY, amount)


## Add engineering XP (convenience).
func add_engineering_xp(faction_id: String, amount: float) -> void:
	add_faction_xp(faction_id, FactionKnowledge.Category.ENGINEERING, amount)


## Get unit buff value from hive mind.
func get_unit_buff(unit_id: int, buff_type: int) -> float:
	return hive_mind.get_unit_buff(unit_id, buff_type)


## Check if unit has unlocked behavior.
func unit_has_behavior(unit_id: int, behavior: String) -> bool:
	return hive_mind.unit_has_behavior(unit_id, behavior)


## Switch unit behavior tree.
func switch_unit_tree(unit_id: int, new_tree_name: String) -> bool:
	return distributed_bt.switch_tree(unit_id, new_tree_name)


## Get all units for faction.
func get_faction_units(faction_id: String) -> Array[int]:
	return distributed_bt.get_faction_units(faction_id)


## Force immediate update for unit.
func update_unit_immediate(unit_id: int) -> int:
	return distributed_bt.execute(unit_id)


## Handle faction level up.
func _on_faction_level_up(faction_id: String, category: String, new_level: int) -> void:
	# Refresh all faction units with new buffs
	var units := get_faction_units(faction_id)
	hive_mind.refresh_faction_units(faction_id, units)

	faction_leveled.emit(faction_id, category, new_level)


## Handle buff unlocked.
func _on_buff_unlocked(faction_id: String, buff_id: String) -> void:
	pass  ## Buffs are applied via refresh_faction_units


## Handle behavior unlocked.
func _on_behavior_unlocked(faction_id: String, behavior_id: String) -> void:
	pass  ## Behaviors are applied via refresh_faction_units


## Serialization.
func to_dict() -> Dictionary:
	var factions_data: Dictionary = {}
	for unit_id in _unit_factions:
		factions_data[str(unit_id)] = _unit_factions[unit_id]

	return {
		"faction_knowledge": faction_knowledge.to_dict(),
		"hive_mind": hive_mind.to_dict(),
		"distributed_bt": distributed_bt.to_dict(),
		"unit_factions": factions_data,
		"pending_units": _pending_units.duplicate(),
		"current_index": _current_index,
		"metrics": {
			"frame_count": _frame_count,
			"avg_frame_time_ms": _avg_frame_time_ms,
			"budget_exceeded_count": _budget_exceeded_count
		}
	}


func from_dict(data: Dictionary) -> void:
	if data.has("faction_knowledge"):
		faction_knowledge.from_dict(data["faction_knowledge"])

	if data.has("hive_mind"):
		hive_mind.from_dict(data["hive_mind"])

	if data.has("distributed_bt"):
		distributed_bt.from_dict(data["distributed_bt"])

	_unit_factions.clear()
	var factions_data: Dictionary = data.get("unit_factions", {})
	for unit_id_str in factions_data:
		_unit_factions[int(unit_id_str)] = factions_data[unit_id_str]

	_pending_units.clear()
	for unit_id in data.get("pending_units", []):
		_pending_units.append(unit_id)

	_current_index = data.get("current_index", 0)

	var metrics: Dictionary = data.get("metrics", {})
	_frame_count = metrics.get("frame_count", 0)
	_avg_frame_time_ms = metrics.get("avg_frame_time_ms", 0.0)
	_budget_exceeded_count = metrics.get("budget_exceeded_count", 0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"total_units": _pending_units.size(),
		"last_frame_time_ms": _last_frame_time_ms,
		"avg_frame_time_ms": _avg_frame_time_ms,
		"frame_count": _frame_count,
		"budget_exceeded_count": _budget_exceeded_count,
		"budget_ms": FRAME_BUDGET_MS,
		"target_hz": UPDATE_FREQUENCY,
		"faction_knowledge": faction_knowledge.get_summary(),
		"hive_mind": hive_mind.get_summary(),
		"distributed_bt": distributed_bt.get_summary()
	}
