class_name UnitBehaviorState
extends Resource
## UnitBehaviorState tracks behavior data for a single unit.
## Designed for high-performance (<50μs per update) to support 5,000+ units.

## Unit ID this state belongs to
var unit_id: int = -1

## Faction ID for faction-specific behavior
var faction_id: int = 0

## Unit type for type-specific behavior
var unit_type: String = ""

## Current behavior pattern name
var current_behavior: String = "standard"

## Current action being executed
var current_action: String = "idle"

## Current AI state (mirrors AIComponent.AIState)
var ai_state: int = 0  # IDLE

## Current target unit ID (-1 if none)
var target_id: int = -1

## Target position
var target_position: Vector3 = Vector3.ZERO

## Distance to target
var target_distance: float = INF

## Current threat level (0.0 to 1.0)
var threat_level: float = 0.0

## Health ratio (0.0 to 1.0)
var health_ratio: float = 1.0

## Unit position (cached for queries)
var position: Vector3 = Vector3.ZERO

## Unit velocity
var velocity: Vector3 = Vector3.ZERO

## Move target (where unit should move)
var move_target: Vector3 = Vector3.ZERO

## Attack target ID (when attacking)
var attack_target_id: int = -1

## Active behavior buffs (buff_id -> BehaviorBuff)
var active_buffs: Dictionary = {}

## Last update timestamp (for delta calculation)
var last_update_time: int = 0

## Behavior tree seed for determinism
var bt_seed: int = 0

## Whether behavior is paused
var is_paused: bool = false

## Custom behavior data (for advanced behaviors)
var custom_data: Dictionary = {}


func _init(p_unit_id: int = -1) -> void:
	unit_id = p_unit_id
	last_update_time = Time.get_ticks_msec()


## Initialize state with unit data.
func initialize(p_unit_id: int, p_faction_id: int, p_unit_type: String, p_position: Vector3 = Vector3.ZERO) -> void:
	unit_id = p_unit_id
	faction_id = p_faction_id
	unit_type = p_unit_type
	position = p_position
	last_update_time = Time.get_ticks_msec()

	# Generate deterministic seed based on unit ID
	bt_seed = hash(str(unit_id) + str(faction_id))


## Update from unit data.
func update_from_unit(unit_data: Dictionary) -> void:
	position = unit_data.get("position", position)
	velocity = unit_data.get("velocity", velocity)
	health_ratio = unit_data.get("health_ratio", health_ratio)
	faction_id = unit_data.get("faction_id", faction_id)


## Update from AI component data.
func update_from_ai(ai_data: Dictionary) -> void:
	current_action = ai_data.get("action", current_action)
	ai_state = ai_data.get("state", ai_state)
	target_id = ai_data.get("target_id", target_id)
	target_position = ai_data.get("target_position", target_position)
	target_distance = ai_data.get("target_distance", target_distance)
	threat_level = ai_data.get("threat_level", threat_level)


## Set current target.
func set_target(p_target_id: int, p_target_position: Vector3 = Vector3.ZERO, p_target_distance: float = INF) -> void:
	target_id = p_target_id
	target_position = p_target_position
	target_distance = p_target_distance


## Clear target.
func clear_target() -> void:
	target_id = -1
	target_position = Vector3.ZERO
	target_distance = INF


## Check if has valid target.
func has_target() -> bool:
	return target_id >= 0


## Set move target.
func set_move_target(target: Vector3) -> void:
	move_target = target


## Set attack target.
func set_attack_target(p_attack_target_id: int) -> void:
	attack_target_id = p_attack_target_id


## Apply a behavior buff.
func apply_buff(buff: BehaviorBuff) -> void:
	active_buffs[buff.buff_id] = buff


## Remove a behavior buff.
func remove_buff(buff_id: String) -> bool:
	return active_buffs.erase(buff_id)


## Check if buff is active.
func has_buff(buff_id: String) -> bool:
	return active_buffs.has(buff_id)


## Get a buff by ID.
func get_buff(buff_id: String) -> BehaviorBuff:
	return active_buffs.get(buff_id)


## Get total buff modifier for a stat.
func get_buff_modifier(stat: String) -> float:
	var modifier := 1.0
	for buff_id in active_buffs:
		var buff: BehaviorBuff = active_buffs[buff_id]
		if buff.is_active():
			modifier *= buff.get_modifier(stat)
	return modifier


## Update buff durations.
func update_buffs(delta: float) -> void:
	var expired: Array[String] = []
	for buff_id in active_buffs:
		var buff: BehaviorBuff = active_buffs[buff_id]
		if buff.update(delta):
			expired.append(buff_id)

	for buff_id in expired:
		active_buffs.erase(buff_id)


## Get custom data value.
func get_custom(key: String, default: Variant = null) -> Variant:
	return custom_data.get(key, default)


## Set custom data value.
func set_custom(key: String, value: Variant) -> void:
	custom_data[key] = value


## Reset state for reuse.
func reset() -> void:
	unit_id = -1
	faction_id = 0
	unit_type = ""
	current_behavior = "standard"
	current_action = "idle"
	ai_state = 0
	target_id = -1
	target_position = Vector3.ZERO
	target_distance = INF
	threat_level = 0.0
	health_ratio = 1.0
	position = Vector3.ZERO
	velocity = Vector3.ZERO
	move_target = Vector3.ZERO
	attack_target_id = -1
	active_buffs.clear()
	last_update_time = 0
	bt_seed = 0
	is_paused = false
	custom_data.clear()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var buffs_data := {}
	for buff_id in active_buffs:
		buffs_data[buff_id] = active_buffs[buff_id].to_dict()

	return {
		"unit_id": unit_id,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"current_behavior": current_behavior,
		"current_action": current_action,
		"ai_state": ai_state,
		"target_id": target_id,
		"target_position": {"x": target_position.x, "y": target_position.y, "z": target_position.z},
		"target_distance": target_distance,
		"threat_level": threat_level,
		"health_ratio": health_ratio,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"move_target": {"x": move_target.x, "y": move_target.y, "z": move_target.z},
		"attack_target_id": attack_target_id,
		"active_buffs": buffs_data,
		"bt_seed": bt_seed,
		"is_paused": is_paused,
		"custom_data": custom_data.duplicate(true)
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> UnitBehaviorState:
	var state := UnitBehaviorState.new()
	state.unit_id = data.get("unit_id", -1)
	state.faction_id = data.get("faction_id", 0)
	state.unit_type = data.get("unit_type", "")
	state.current_behavior = data.get("current_behavior", "standard")
	state.current_action = data.get("current_action", "idle")
	state.ai_state = data.get("ai_state", 0)
	state.target_id = data.get("target_id", -1)
	state.target_distance = data.get("target_distance", INF)
	state.threat_level = data.get("threat_level", 0.0)
	state.health_ratio = data.get("health_ratio", 1.0)
	state.attack_target_id = data.get("attack_target_id", -1)
	state.bt_seed = data.get("bt_seed", 0)
	state.is_paused = data.get("is_paused", false)
	state.custom_data = data.get("custom_data", {}).duplicate(true)

	# Deserialize vectors
	var tp: Dictionary = data.get("target_position", {})
	state.target_position = Vector3(tp.get("x", 0.0), tp.get("y", 0.0), tp.get("z", 0.0))

	var pos: Dictionary = data.get("position", {})
	state.position = Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))

	var vel: Dictionary = data.get("velocity", {})
	state.velocity = Vector3(vel.get("x", 0.0), vel.get("y", 0.0), vel.get("z", 0.0))

	var mt: Dictionary = data.get("move_target", {})
	state.move_target = Vector3(mt.get("x", 0.0), mt.get("y", 0.0), mt.get("z", 0.0))

	# Deserialize buffs
	var buffs_data: Dictionary = data.get("active_buffs", {})
	for buff_id in buffs_data:
		state.active_buffs[buff_id] = BehaviorBuff.from_dict(buffs_data[buff_id])

	return state


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"unit_id": unit_id,
		"behavior": current_behavior,
		"action": current_action,
		"target_id": target_id,
		"threat": threat_level,
		"health": health_ratio,
		"buffs": active_buffs.size()
	}
