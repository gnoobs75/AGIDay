class_name BrownoutSystem
extends RefCounted
## BrownoutSystem handles partial power loss and emergency power management.

signal brownout_started(district_id: int, power_ratio: float)
signal brownout_ended(district_id: int)
signal emergency_power_activated(district_id: int)
signal emergency_power_depleted(district_id: int)
signal power_priority_changed(district_id: int, priority: int)
signal load_balanced(faction_id: String, districts_affected: int)

## Power thresholds
const BROWNOUT_THRESHOLD := 0.75   ## Below 75% = brownout
const BLACKOUT_THRESHOLD := 0.50   ## Below 50% = blackout
const CRITICAL_THRESHOLD := 0.25   ## Below 25% = critical

## Power state levels
enum PowerState {
	FULL,       ## 100% power
	BROWNOUT,   ## 50-75% power
	BLACKOUT,   ## 25-50% power
	CRITICAL    ## <25% power
}

## Priority levels
enum Priority {
	LOW,
	NORMAL,
	HIGH,
	CRITICAL
}

## District power states (district_id -> state_data)
var _district_states: Dictionary = {}

## District priorities (district_id -> priority)
var _district_priorities: Dictionary = {}

## Emergency power reserves (district_id -> reserve_data)
var _emergency_reserves: Dictionary = {}

## Emergency power configuration
const EMERGENCY_RESERVE_CAPACITY := 500.0  ## Power units
const EMERGENCY_DRAIN_RATE := 10.0         ## Per second
const EMERGENCY_RECHARGE_RATE := 5.0       ## Per second when powered


func _init() -> void:
	pass


## Update district power state.
func update_district_power(district_id: int, current_power: float, demand: float) -> int:
	var ratio := 1.0 if demand <= 0.0 else minf(current_power / demand, 1.0)
	var old_state: int = _district_states.get(district_id, {}).get("state", PowerState.FULL)

	var new_state: int
	if ratio >= BROWNOUT_THRESHOLD:
		new_state = PowerState.FULL
	elif ratio >= BLACKOUT_THRESHOLD:
		new_state = PowerState.BROWNOUT
	elif ratio >= CRITICAL_THRESHOLD:
		new_state = PowerState.BLACKOUT
	else:
		new_state = PowerState.CRITICAL

	_district_states[district_id] = {
		"state": new_state,
		"ratio": ratio,
		"current_power": current_power,
		"demand": demand,
		"deficit": maxf(0.0, demand - current_power)
	}

	# Emit state change events
	if new_state == PowerState.BROWNOUT and old_state == PowerState.FULL:
		brownout_started.emit(district_id, ratio)
	elif new_state == PowerState.FULL and old_state == PowerState.BROWNOUT:
		brownout_ended.emit(district_id)

	return new_state


## Get power state for district.
func get_power_state(district_id: int) -> int:
	return _district_states.get(district_id, {}).get("state", PowerState.FULL)


## Get power ratio for district.
func get_power_ratio(district_id: int) -> float:
	return _district_states.get(district_id, {}).get("ratio", 1.0)


## Get power state name.
func get_state_name(state: int) -> String:
	match state:
		PowerState.FULL:
			return "full"
		PowerState.BROWNOUT:
			return "brownout"
		PowerState.BLACKOUT:
			return "blackout"
		PowerState.CRITICAL:
			return "critical"
		_:
			return "unknown"


## Get brownout production multiplier.
func get_brownout_multiplier(district_id: int) -> float:
	var state := get_power_state(district_id)

	match state:
		PowerState.FULL:
			return 1.0
		PowerState.BROWNOUT:
			# Scale between 75% and 50% based on actual ratio
			var ratio := get_power_ratio(district_id)
			return 0.5 + (ratio - BLACKOUT_THRESHOLD) / (BROWNOUT_THRESHOLD - BLACKOUT_THRESHOLD) * 0.5
		PowerState.BLACKOUT:
			return 0.25
		PowerState.CRITICAL:
			return 0.0
		_:
			return 1.0


## Check if district is in brownout.
func is_brownout(district_id: int) -> bool:
	return get_power_state(district_id) == PowerState.BROWNOUT


## Check if district is in blackout or worse.
func is_blackout(district_id: int) -> bool:
	var state := get_power_state(district_id)
	return state == PowerState.BLACKOUT or state == PowerState.CRITICAL


# ============================================
# EMERGENCY POWER
# ============================================

## Initialize emergency reserve for district.
func init_emergency_reserve(district_id: int, capacity: float = EMERGENCY_RESERVE_CAPACITY) -> void:
	_emergency_reserves[district_id] = {
		"capacity": capacity,
		"current": capacity,  # Start full
		"active": false,
		"drain_rate": EMERGENCY_DRAIN_RATE
	}


## Activate emergency power for district.
func activate_emergency_power(district_id: int) -> bool:
	if not _emergency_reserves.has(district_id):
		return false

	var reserve: Dictionary = _emergency_reserves[district_id]
	if reserve["current"] <= 0.0:
		return false

	reserve["active"] = true
	emergency_power_activated.emit(district_id)
	return true


## Deactivate emergency power.
func deactivate_emergency_power(district_id: int) -> void:
	if _emergency_reserves.has(district_id):
		_emergency_reserves[district_id]["active"] = false


## Update emergency power (call each frame).
func update_emergency_power(delta: float) -> void:
	for district_id in _emergency_reserves:
		var reserve: Dictionary = _emergency_reserves[district_id]

		if reserve["active"]:
			# Drain reserve
			reserve["current"] = maxf(0.0, reserve["current"] - reserve["drain_rate"] * delta)

			if reserve["current"] <= 0.0:
				reserve["active"] = false
				emergency_power_depleted.emit(district_id)
		else:
			# Recharge if district has power
			var state := get_power_state(district_id)
			if state == PowerState.FULL:
				reserve["current"] = minf(reserve["capacity"], reserve["current"] + EMERGENCY_RECHARGE_RATE * delta)


## Get emergency power level.
func get_emergency_power_level(district_id: int) -> float:
	if not _emergency_reserves.has(district_id):
		return 0.0

	var reserve: Dictionary = _emergency_reserves[district_id]
	return reserve["current"] / reserve["capacity"] if reserve["capacity"] > 0 else 0.0


## Check if emergency power is active.
func is_emergency_power_active(district_id: int) -> bool:
	return _emergency_reserves.get(district_id, {}).get("active", false)


## Get emergency power supplement.
func get_emergency_power_output(district_id: int) -> float:
	if not is_emergency_power_active(district_id):
		return 0.0

	var reserve: Dictionary = _emergency_reserves[district_id]
	# Emergency power provides steady output when active
	return minf(reserve["current"], EMERGENCY_DRAIN_RATE * 10.0)


# ============================================
# PRIORITY SYSTEM
# ============================================

## Set district priority.
func set_district_priority(district_id: int, priority: int) -> void:
	_district_priorities[district_id] = priority
	power_priority_changed.emit(district_id, priority)


## Get district priority.
func get_district_priority(district_id: int) -> int:
	return _district_priorities.get(district_id, Priority.NORMAL)


## Get priority name.
func get_priority_name(priority: int) -> String:
	match priority:
		Priority.LOW:
			return "low"
		Priority.NORMAL:
			return "normal"
		Priority.HIGH:
			return "high"
		Priority.CRITICAL:
			return "critical"
		_:
			return "unknown"


## Perform load balancing across districts.
func balance_load(faction_id: String, available_power: float, district_demands: Dictionary) -> Dictionary:
	var allocations: Dictionary = {}
	var total_demand := 0.0

	# Sort districts by priority
	var priority_groups: Dictionary = {}
	for district_id in district_demands:
		var priority := get_district_priority(district_id)
		if not priority_groups.has(priority):
			priority_groups[priority] = []
		priority_groups[priority].append(district_id)
		total_demand += district_demands[district_id]

	var remaining_power := available_power

	# Allocate power by priority (highest first)
	for priority in [Priority.CRITICAL, Priority.HIGH, Priority.NORMAL, Priority.LOW]:
		if not priority_groups.has(priority):
			continue

		var group: Array = priority_groups[priority]
		var group_demand := 0.0

		for district_id in group:
			group_demand += district_demands[district_id]

		if group_demand <= remaining_power:
			# Fully satisfy this priority group
			for district_id in group:
				allocations[district_id] = district_demands[district_id]
			remaining_power -= group_demand
		else:
			# Proportionally allocate remaining power
			for district_id in group:
				var ratio := district_demands[district_id] / group_demand if group_demand > 0 else 0.0
				allocations[district_id] = remaining_power * ratio
			remaining_power = 0.0

	var affected := 0
	for district_id in allocations:
		if allocations[district_id] < district_demands.get(district_id, 0.0):
			affected += 1

	if affected > 0:
		load_balanced.emit(faction_id, affected)

	return allocations


# ============================================
# POWER REDUNDANCY
# ============================================

## Calculate redundancy score for faction.
func calculate_redundancy(faction_id: String, total_generation: float, total_demand: float, generator_count: int) -> Dictionary:
	var redundancy := {
		"score": 0.0,
		"has_backup": false,
		"excess_capacity": 0.0,
		"generators_needed_for_full": 1,
		"can_survive_loss": false
	}

	if generator_count <= 0 or total_demand <= 0:
		return redundancy

	# Calculate excess capacity
	redundancy["excess_capacity"] = maxf(0.0, total_generation - total_demand)

	# Calculate if we can survive losing one generator
	var avg_generation := total_generation / generator_count
	var power_after_loss := total_generation - avg_generation
	redundancy["can_survive_loss"] = power_after_loss >= total_demand * BLACKOUT_THRESHOLD

	# Backup indicator
	redundancy["has_backup"] = generator_count >= 2 and redundancy["can_survive_loss"]

	# Score from 0.0 to 1.0
	var ratio := total_generation / total_demand
	var generator_factor := minf(generator_count / 3.0, 1.0)  # More generators = more redundancy
	redundancy["score"] = clampf((ratio - 1.0) * 0.5 + generator_factor * 0.5, 0.0, 1.0)

	# Minimum generators needed
	redundancy["generators_needed_for_full"] = ceili(total_demand / avg_generation) if avg_generation > 0 else 1

	return redundancy


## Serialization.
func to_dict() -> Dictionary:
	return {
		"district_states": _district_states.duplicate(true),
		"district_priorities": _district_priorities.duplicate(),
		"emergency_reserves": _emergency_reserves.duplicate(true)
	}


func from_dict(data: Dictionary) -> void:
	_district_states = data.get("district_states", {}).duplicate(true)
	_district_priorities = data.get("district_priorities", {}).duplicate()
	_emergency_reserves = data.get("emergency_reserves", {}).duplicate(true)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var state_counts: Dictionary = {}
	for state in PowerState.values():
		state_counts[get_state_name(state)] = 0

	for district_id in _district_states:
		var state: int = _district_states[district_id]["state"]
		var name := get_state_name(state)
		state_counts[name] += 1

	var active_emergency := 0
	for district_id in _emergency_reserves:
		if _emergency_reserves[district_id]["active"]:
			active_emergency += 1

	return {
		"tracked_districts": _district_states.size(),
		"state_counts": state_counts,
		"emergency_reserves": _emergency_reserves.size(),
		"active_emergency": active_emergency
	}
