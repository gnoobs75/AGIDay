class_name AIComponent
extends RefCounted
## AIComponent is the ECS component for AI-controlled units.
## Integrates with AISystem for behavior tree execution and faction learning.

signal state_changed(old_state: int, new_state: int)
signal decision_made(action: String, target_id: int)
signal buff_applied(buff_type: int, value: float)

## AI states
enum State {
	IDLE,
	PATROLLING,
	PURSUING,
	ATTACKING,
	FLEEING,
	SUPPORTING,
	BUILDING,
	DEAD
}

## State names for debugging
const STATE_NAMES := {
	State.IDLE: "idle",
	State.PATROLLING: "patrolling",
	State.PURSUING: "pursuing",
	State.ATTACKING: "attacking",
	State.FLEEING: "fleeing",
	State.SUPPORTING: "supporting",
	State.BUILDING: "building",
	State.DEAD: "dead"
}

## Component data
var entity_id: int = -1
var faction_id: String = ""
var unit_type: String = ""
var behavior_tree: String = ""
var current_state: int = State.IDLE

## Target tracking
var target_entity_id: int = -1
var target_position: Vector3 = Vector3.INF

## Perception data
var detection_range: float = 20.0
var attack_range: float = 10.0
var aggression: float = 0.5

## Last decision
var last_decision_time: float = 0.0
var last_action: String = ""

## Cached buff values
var _buff_cache: Dictionary = {}


func _init() -> void:
	pass


## Initialize component.
func initialize(p_entity_id: int, p_faction_id: String, p_unit_type: String, p_tree: String) -> void:
	entity_id = p_entity_id
	faction_id = p_faction_id
	unit_type = p_unit_type
	behavior_tree = p_tree
	current_state = State.IDLE


## Set state.
func set_state(new_state: int) -> void:
	if current_state == new_state:
		return

	var old_state := current_state
	current_state = new_state
	state_changed.emit(old_state, new_state)


## Get state name.
func get_state_name() -> String:
	return STATE_NAMES.get(current_state, "unknown")


## Set target.
func set_target(target_id: int, target_pos: Vector3 = Vector3.INF) -> void:
	target_entity_id = target_id
	if target_pos != Vector3.INF:
		target_position = target_pos


## Clear target.
func clear_target() -> void:
	target_entity_id = -1
	target_position = Vector3.INF


## Has valid target.
func has_target() -> bool:
	return target_entity_id != -1


## Record decision.
func record_decision(action: String, target_id: int = -1) -> void:
	last_action = action
	last_decision_time = Time.get_ticks_msec() / 1000.0
	decision_made.emit(action, target_id)


## Apply buff from hive mind.
func apply_buff(buff_type: int, value: float) -> void:
	_buff_cache[buff_type] = value
	buff_applied.emit(buff_type, value)


## Get buff value.
func get_buff(buff_type: int) -> float:
	return _buff_cache.get(buff_type, 0.0)


## Get all buffs.
func get_all_buffs() -> Dictionary:
	return _buff_cache.duplicate()


## Create blackboard data for behavior tree.
func create_blackboard_update() -> Dictionary:
	return {
		"entity_id": entity_id,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"current_state": current_state,
		"target_id": target_entity_id,
		"target_position": target_position,
		"detection_range": detection_range,
		"attack_range": attack_range,
		"aggression": aggression,
		"last_action": last_action
	}


## Serialization.
func to_dict() -> Dictionary:
	return {
		"entity_id": entity_id,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"behavior_tree": behavior_tree,
		"current_state": current_state,
		"target_entity_id": target_entity_id,
		"target_position": {"x": target_position.x, "y": target_position.y, "z": target_position.z},
		"detection_range": detection_range,
		"attack_range": attack_range,
		"aggression": aggression,
		"last_action": last_action,
		"last_decision_time": last_decision_time,
		"buff_cache": _buff_cache.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	entity_id = data.get("entity_id", -1)
	faction_id = data.get("faction_id", "")
	unit_type = data.get("unit_type", "")
	behavior_tree = data.get("behavior_tree", "")
	current_state = data.get("current_state", State.IDLE)
	target_entity_id = data.get("target_entity_id", -1)

	var pos: Dictionary = data.get("target_position", {})
	target_position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
	if target_position == Vector3.ZERO and target_entity_id == -1:
		target_position = Vector3.INF

	detection_range = data.get("detection_range", 20.0)
	attack_range = data.get("attack_range", 10.0)
	aggression = data.get("aggression", 0.5)
	last_action = data.get("last_action", "")
	last_decision_time = data.get("last_decision_time", 0.0)
	_buff_cache = data.get("buff_cache", {}).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"entity_id": entity_id,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"state": get_state_name(),
		"has_target": has_target(),
		"target_id": target_entity_id,
		"last_action": last_action,
		"buff_count": _buff_cache.size()
	}
