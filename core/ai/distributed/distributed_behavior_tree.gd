class_name DistributedBehaviorTree
extends RefCounted
## DistributedBehaviorTree manages per-unit autonomous decision making.
## Each unit has its own behavior tree instance with local blackboard.

signal decision_made(unit_id: int, decision: String, status: int)
signal tree_switched(unit_id: int, old_tree: String, new_tree: String)

## Behavior tree status
const STATUS_SUCCESS := LimboAIWrapper.BTStatus.SUCCESS
const STATUS_FAILURE := LimboAIWrapper.BTStatus.FAILURE
const STATUS_RUNNING := LimboAIWrapper.BTStatus.RUNNING

## Unit behavior tree data
class UnitBTData extends RefCounted:
	var unit_id: int
	var faction_id: String
	var tree_name: String
	var root: LimboAIWrapper.BTNode
	var blackboard: Dictionary
	var last_status: int
	var last_decision_time: float
	var deterministic_seed: int

	func _init(p_unit_id: int, p_faction_id: String) -> void:
		unit_id = p_unit_id
		faction_id = p_faction_id
		tree_name = ""
		root = null
		blackboard = {}
		last_status = STATUS_FAILURE
		last_decision_time = 0.0
		deterministic_seed = p_unit_id  ## Use unit ID as base seed


## Registered units (unit_id -> UnitBTData)
var _units: Dictionary = {}

## Tree templates (tree_name -> BTNode)
var _tree_templates: Dictionary = {}

## Random generator for deterministic behavior
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	pass


## Register a tree template.
func register_tree_template(tree_name: String, root: LimboAIWrapper.BTNode) -> void:
	_tree_templates[tree_name] = root


## Register unit with behavior tree.
func register_unit(unit_id: int, faction_id: String, tree_name: String) -> bool:
	if not _tree_templates.has(tree_name):
		return false

	var data := UnitBTData.new(unit_id, faction_id)
	data.tree_name = tree_name
	data.root = _clone_tree(_tree_templates[tree_name])
	data.blackboard = _create_initial_blackboard(unit_id, faction_id)

	_units[unit_id] = data
	return true


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_units.erase(unit_id)


## Clone a behavior tree (deep copy).
func _clone_tree(node: LimboAIWrapper.BTNode) -> LimboAIWrapper.BTNode:
	# For now, share tree structure - each unit has own blackboard
	# Full deep clone would be needed for stateful decorators
	return node


## Create initial blackboard for unit.
func _create_initial_blackboard(unit_id: int, faction_id: String) -> Dictionary:
	return {
		"unit_id": unit_id,
		"faction_id": faction_id,
		"position": Vector3.ZERO,
		"target_id": -1,
		"target_position": Vector3.INF,
		"allies_nearby": [],
		"enemies_nearby": [],
		"health_percent": 1.0,
		"in_combat": false,
		"has_destination": false,
		"_random_seed": unit_id
	}


## Update unit blackboard data.
func update_blackboard(unit_id: int, key: String, value: Variant) -> void:
	if not _units.has(unit_id):
		return

	_units[unit_id].blackboard[key] = value


## Batch update blackboard.
func update_blackboard_batch(unit_id: int, updates: Dictionary) -> void:
	if not _units.has(unit_id):
		return

	for key in updates:
		_units[unit_id].blackboard[key] = updates[key]


## Get blackboard value.
func get_blackboard_value(unit_id: int, key: String, default: Variant = null) -> Variant:
	if not _units.has(unit_id):
		return default

	return _units[unit_id].blackboard.get(key, default)


## Execute behavior tree for unit.
func execute(unit_id: int) -> int:
	if not _units.has(unit_id):
		return STATUS_FAILURE

	var data: UnitBTData = _units[unit_id]

	if data.root == null:
		return STATUS_FAILURE

	# Set deterministic random seed
	_rng.seed = data.deterministic_seed + int(data.last_decision_time * 1000)
	data.blackboard["_rng"] = _rng

	# Execute tree
	var status := data.root.execute(data.blackboard)

	data.last_status = status
	data.last_decision_time = Time.get_ticks_msec() / 1000.0

	# Update seed for next execution
	data.deterministic_seed = _rng.randi()

	decision_made.emit(unit_id, data.tree_name, status)

	return status


## Switch unit to different behavior tree.
func switch_tree(unit_id: int, new_tree_name: String) -> bool:
	if not _units.has(unit_id):
		return false

	if not _tree_templates.has(new_tree_name):
		return false

	var data: UnitBTData = _units[unit_id]
	var old_tree := data.tree_name

	data.tree_name = new_tree_name
	data.root = _clone_tree(_tree_templates[new_tree_name])

	tree_switched.emit(unit_id, old_tree, new_tree_name)

	return true


## Get unit's current tree name.
func get_tree_name(unit_id: int) -> String:
	if not _units.has(unit_id):
		return ""
	return _units[unit_id].tree_name


## Get unit's last status.
func get_last_status(unit_id: int) -> int:
	if not _units.has(unit_id):
		return STATUS_FAILURE
	return _units[unit_id].last_status


## Get all units for faction.
func get_faction_units(faction_id: String) -> Array[int]:
	var units: Array[int] = []

	for unit_id in _units:
		if _units[unit_id].faction_id == faction_id:
			units.append(unit_id)

	return units


## Get unit count.
func get_unit_count() -> int:
	return _units.size()


## Serialization.
func to_dict() -> Dictionary:
	var units_data: Dictionary = {}

	for unit_id in _units:
		var data: UnitBTData = _units[unit_id]
		units_data[str(unit_id)] = {
			"faction_id": data.faction_id,
			"tree_name": data.tree_name,
			"blackboard": _serialize_blackboard(data.blackboard),
			"last_status": data.last_status,
			"deterministic_seed": data.deterministic_seed
		}

	return {
		"units": units_data,
		"registered_trees": _tree_templates.keys()
	}


func _serialize_blackboard(blackboard: Dictionary) -> Dictionary:
	var serialized: Dictionary = {}

	for key in blackboard:
		var value = blackboard[key]

		# Skip non-serializable values
		if value is Callable or value is RandomNumberGenerator:
			continue

		if value is Vector3:
			serialized[key] = {"_type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
		elif value is Array or value is Dictionary or value is int or value is float or value is String or value is bool:
			serialized[key] = value

	return serialized


func from_dict(data: Dictionary) -> void:
	var units_data: Dictionary = data.get("units", {})

	for unit_id_str in units_data:
		var unit_id := int(unit_id_str)
		var unit_data: Dictionary = units_data[unit_id_str]

		if register_unit(unit_id, unit_data["faction_id"], unit_data["tree_name"]):
			var udata: UnitBTData = _units[unit_id]
			udata.last_status = unit_data.get("last_status", STATUS_FAILURE)
			udata.deterministic_seed = unit_data.get("deterministic_seed", unit_id)

			# Restore blackboard
			var saved_bb: Dictionary = unit_data.get("blackboard", {})
			for key in saved_bb:
				var value = saved_bb[key]
				if value is Dictionary and value.has("_type"):
					if value["_type"] == "Vector3":
						udata.blackboard[key] = Vector3(value["x"], value["y"], value["z"])
				else:
					udata.blackboard[key] = value


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_counts: Dictionary = {}
	var tree_counts: Dictionary = {}
	var status_counts := {STATUS_SUCCESS: 0, STATUS_FAILURE: 0, STATUS_RUNNING: 0}

	for unit_id in _units:
		var data: UnitBTData = _units[unit_id]

		faction_counts[data.faction_id] = faction_counts.get(data.faction_id, 0) + 1
		tree_counts[data.tree_name] = tree_counts.get(data.tree_name, 0) + 1
		status_counts[data.last_status] += 1

	return {
		"total_units": _units.size(),
		"registered_trees": _tree_templates.size(),
		"units_by_faction": faction_counts,
		"units_by_tree": tree_counts,
		"last_status_distribution": {
			"success": status_counts[STATUS_SUCCESS],
			"failure": status_counts[STATUS_FAILURE],
			"running": status_counts[STATUS_RUNNING]
		}
	}
