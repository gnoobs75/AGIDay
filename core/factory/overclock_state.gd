class_name OverclockState
extends RefCounted
## OverclockState handles serialization of factory overclock data.

## State data
var factory_id: int = -1
var overclock_level: float = 1.0
var heat_level: float = 0.0
var is_melting_down: bool = false
var meltdown_time_remaining: float = 0.0
var faction_id: String = ""
var timestamp: float = 0.0


func _init() -> void:
	pass


## Create from factory overclock instance.
static func create_from_overclock(overclock: FactoryOverclock, faction: String = "") -> OverclockState:
	var state := OverclockState.new()
	state.factory_id = overclock.factory_id
	state.overclock_level = overclock.overclock_level
	state.heat_level = overclock.heat_level
	state.is_melting_down = overclock.is_meltdown
	state.meltdown_time_remaining = overclock.meltdown_timer
	state.faction_id = faction
	state.timestamp = Time.get_unix_time_from_system()
	return state


## Apply state to factory overclock instance.
func apply_to_overclock(overclock: FactoryOverclock) -> void:
	overclock.factory_id = factory_id
	overclock.overclock_level = overclock_level
	overclock.heat_level = heat_level
	overclock.is_meltdown = is_melting_down
	overclock.meltdown_timer = meltdown_time_remaining
	overclock.is_production_enabled = not is_melting_down


## Convert state to saveable dictionary.
func to_dict() -> Dictionary:
	return {
		"factory_id": factory_id,
		"overclock_level": overclock_level,
		"heat_level": heat_level,
		"is_melting_down": is_melting_down,
		"meltdown_time_remaining": meltdown_time_remaining,
		"faction_id": faction_id,
		"timestamp": timestamp
	}


## Restore state from loaded dictionary.
func from_dict(data: Dictionary) -> void:
	factory_id = data.get("factory_id", -1)
	overclock_level = data.get("overclock_level", 1.0)
	heat_level = data.get("heat_level", 0.0)
	is_melting_down = data.get("is_melting_down", false)
	meltdown_time_remaining = data.get("meltdown_time_remaining", 0.0)
	faction_id = data.get("faction_id", "")
	timestamp = data.get("timestamp", 0.0)


## Static constructor from dictionary.
static func create_from_dict(data: Dictionary) -> OverclockState:
	var state := OverclockState.new()
	state.from_dict(data)
	return state


## Validate state data.
func is_valid() -> bool:
	if factory_id < 0:
		return false
	if overclock_level < 1.0 or overclock_level > 2.5:
		return false
	if heat_level < 0.0 or heat_level > 1.0:
		return false
	if is_melting_down and meltdown_time_remaining <= 0.0:
		return false
	return true


## Get estimated save size in bytes.
func get_estimated_size() -> int:
	# Approximate JSON size: keys + values
	# factory_id: ~15 + 10 = 25
	# overclock_level: ~20 + 5 = 25
	# heat_level: ~15 + 5 = 20
	# is_melting_down: ~20 + 5 = 25
	# meltdown_time_remaining: ~25 + 5 = 30
	# faction_id: ~15 + 20 = 35
	# timestamp: ~15 + 15 = 30
	return 200  # ~200 bytes per factory state


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"factory_id": factory_id,
		"overclock": overclock_level,
		"heat": heat_level,
		"is_meltdown": is_melting_down,
		"meltdown_remaining": meltdown_time_remaining,
		"faction": faction_id,
		"is_valid": is_valid()
	}
