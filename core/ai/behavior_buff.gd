class_name BehaviorBuff
extends RefCounted
## BehaviorBuff represents a temporary or permanent modifier to unit behavior.
## Used for faction-unlocked abilities, status effects, and progression benefits.

## Unique buff identifier
var buff_id: String = ""

## Human-readable name
var buff_name: String = ""

## Buff source (faction, ability, status, etc.)
var source: String = ""

## Duration in seconds (-1 for permanent)
var duration: float = -1.0

## Time remaining (-1 for permanent)
var time_remaining: float = -1.0

## Whether buff is currently active
var _is_active: bool = true

## Stat modifiers (stat_name -> multiplier, 1.0 = no change)
var modifiers: Dictionary = {}

## Behavior modifications
var behavior_mods: Dictionary = {}


func _init(p_buff_id: String = "", p_duration: float = -1.0) -> void:
	buff_id = p_buff_id
	buff_name = p_buff_id
	duration = p_duration
	time_remaining = p_duration


## Initialize buff with parameters.
func initialize(p_buff_id: String, p_name: String, p_source: String, p_duration: float = -1.0) -> void:
	buff_id = p_buff_id
	buff_name = p_name
	source = p_source
	duration = p_duration
	time_remaining = p_duration
	_is_active = true


## Add a stat modifier.
func add_modifier(stat: String, multiplier: float) -> void:
	modifiers[stat] = multiplier


## Get modifier for a stat (returns 1.0 if not found).
func get_modifier(stat: String) -> float:
	return modifiers.get(stat, 1.0)


## Add a behavior modification.
func add_behavior_mod(behavior_key: String, value: Variant) -> void:
	behavior_mods[behavior_key] = value


## Get a behavior modification.
func get_behavior_mod(behavior_key: String, default: Variant = null) -> Variant:
	return behavior_mods.get(behavior_key, default)


## Update buff (called every frame).
## Returns true if buff has expired.
func update(delta: float) -> bool:
	if duration < 0:
		return false  # Permanent buff

	time_remaining -= delta
	if time_remaining <= 0:
		_is_active = false
		return true

	return false


## Check if buff is active.
func is_active() -> bool:
	return _is_active


## Check if buff is permanent.
func is_permanent() -> bool:
	return duration < 0


## Get remaining duration percentage (0.0 to 1.0).
func get_remaining_percent() -> float:
	if duration < 0:
		return 1.0
	if duration <= 0:
		return 0.0
	return clampf(time_remaining / duration, 0.0, 1.0)


## Refresh buff duration.
func refresh() -> void:
	time_remaining = duration
	_is_active = true


## Extend buff duration.
func extend(additional_time: float) -> void:
	if duration >= 0:
		time_remaining += additional_time


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"buff_id": buff_id,
		"buff_name": buff_name,
		"source": source,
		"duration": duration,
		"time_remaining": time_remaining,
		"is_active": _is_active,
		"modifiers": modifiers.duplicate(),
		"behavior_mods": behavior_mods.duplicate(true)
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> BehaviorBuff:
	var buff := BehaviorBuff.new()
	buff.buff_id = data.get("buff_id", "")
	buff.buff_name = data.get("buff_name", "")
	buff.source = data.get("source", "")
	buff.duration = data.get("duration", -1.0)
	buff.time_remaining = data.get("time_remaining", -1.0)
	buff._is_active = data.get("is_active", true)
	buff.modifiers = data.get("modifiers", {}).duplicate()
	buff.behavior_mods = data.get("behavior_mods", {}).duplicate(true)
	return buff


## Create a damage buff.
static func create_damage_buff(buff_id: String, multiplier: float, duration: float = -1.0) -> BehaviorBuff:
	var buff := BehaviorBuff.new(buff_id, duration)
	buff.buff_name = "Damage Boost"
	buff.source = "faction"
	buff.add_modifier("damage", multiplier)
	return buff


## Create a speed buff.
static func create_speed_buff(buff_id: String, multiplier: float, duration: float = -1.0) -> BehaviorBuff:
	var buff := BehaviorBuff.new(buff_id, duration)
	buff.buff_name = "Speed Boost"
	buff.source = "faction"
	buff.add_modifier("speed", multiplier)
	return buff


## Create an armor buff.
static func create_armor_buff(buff_id: String, multiplier: float, duration: float = -1.0) -> BehaviorBuff:
	var buff := BehaviorBuff.new(buff_id, duration)
	buff.buff_name = "Armor Boost"
	buff.source = "faction"
	buff.add_modifier("armor", multiplier)
	return buff


## Create a combined combat buff.
static func create_combat_buff(buff_id: String, damage_mult: float, armor_mult: float, duration: float = -1.0) -> BehaviorBuff:
	var buff := BehaviorBuff.new(buff_id, duration)
	buff.buff_name = "Combat Boost"
	buff.source = "faction"
	buff.add_modifier("damage", damage_mult)
	buff.add_modifier("armor", armor_mult)
	return buff


## Get summary for debugging.
func get_summary() -> String:
	var duration_str := "permanent" if duration < 0 else "%.1fs" % time_remaining
	return "%s (%s): %s" % [buff_name, buff_id, duration_str]
