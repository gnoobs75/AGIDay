class_name DistrictPowerState
extends RefCounted
## DistrictPowerState tracks power consumption and blackout status for a district.

signal power_updated(district_id: int, current_power: float, demand: float)
signal blackout_started(district_id: int)
signal blackout_ended(district_id: int)

## Blackout threshold - blackout occurs when power < 50% of demand
const BLACKOUT_THRESHOLD := 0.5

## District identity
var district_id: int = -1
var controlling_faction: String = ""

## Power state
var current_power: float = 0.0
var power_demand: float = 100.0
var is_blackout: bool = false

## Connected power lines
var connected_line_ids: Array[int] = []

## Statistics
var time_in_blackout: float = 0.0
var total_blackout_events: int = 0


func _init() -> void:
	pass


## Initialize district power state.
func initialize(p_district_id: int, p_faction: String, p_demand: float = 100.0) -> void:
	district_id = p_district_id
	controlling_faction = p_faction
	power_demand = p_demand
	current_power = 0.0
	is_blackout = true  # Start in blackout until power is provided


## Set power demand.
func set_power_demand(demand: float) -> void:
	power_demand = maxf(0.0, demand)
	update_power_state()


## Add connected power line.
func add_connected_line(line_id: int) -> void:
	if not connected_line_ids.has(line_id):
		connected_line_ids.append(line_id)


## Remove connected power line.
func remove_connected_line(line_id: int) -> void:
	var idx := connected_line_ids.find(line_id)
	if idx != -1:
		connected_line_ids.remove_at(idx)


## Set current power from all connected lines.
func set_current_power(power: float) -> void:
	current_power = maxf(0.0, power)
	update_power_state()


## Update power state and determine blackout status.
func update_power_state() -> void:
	var was_blackout := is_blackout

	# Blackout occurs when current power < 50% of demand
	if power_demand <= 0.0:
		is_blackout = false
	else:
		var power_ratio := current_power / power_demand
		is_blackout = power_ratio < BLACKOUT_THRESHOLD

	# Emit state change signals
	if is_blackout and not was_blackout:
		total_blackout_events += 1
		blackout_started.emit(district_id)
	elif not is_blackout and was_blackout:
		blackout_ended.emit(district_id)

	power_updated.emit(district_id, current_power, power_demand)


## Update blackout time tracking.
func update_time(delta: float) -> void:
	if is_blackout:
		time_in_blackout += delta


## Get power satisfaction ratio.
func get_power_ratio() -> float:
	if power_demand <= 0.0:
		return 1.0
	return minf(current_power / power_demand, 1.0)


## Get power deficit.
func get_power_deficit() -> float:
	return maxf(0.0, power_demand - current_power)


## Get power surplus.
func get_power_surplus() -> float:
	return maxf(0.0, current_power - power_demand)


## Check if fully powered.
func is_fully_powered() -> bool:
	return current_power >= power_demand


## Check if partially powered.
func is_partially_powered() -> bool:
	return not is_blackout and not is_fully_powered()


## Change controlling faction.
func set_controlling_faction(faction: String) -> void:
	controlling_faction = faction


## Serialization.
func to_dict() -> Dictionary:
	return {
		"district_id": district_id,
		"controlling_faction": controlling_faction,
		"current_power": current_power,
		"power_demand": power_demand,
		"is_blackout": is_blackout,
		"connected_line_ids": connected_line_ids.duplicate(),
		"time_in_blackout": time_in_blackout,
		"total_blackout_events": total_blackout_events
	}


func from_dict(data: Dictionary) -> void:
	district_id = data.get("district_id", -1)
	controlling_faction = data.get("controlling_faction", "")
	current_power = data.get("current_power", 0.0)
	power_demand = data.get("power_demand", 100.0)
	is_blackout = data.get("is_blackout", false)
	time_in_blackout = data.get("time_in_blackout", 0.0)
	total_blackout_events = data.get("total_blackout_events", 0)

	connected_line_ids.clear()
	var lines: Array = data.get("connected_line_ids", [])
	for line_id in lines:
		connected_line_ids.append(int(line_id))


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"district_id": district_id,
		"faction": controlling_faction,
		"power": current_power,
		"demand": power_demand,
		"ratio": get_power_ratio(),
		"is_blackout": is_blackout,
		"connected_lines": connected_line_ids.size(),
		"blackout_events": total_blackout_events
	}
