class_name PerformanceTierSystem
extends RefCounted
## PerformanceTierSystem divides units into update frequency tiers.
## Tier 1: In combat - every frame
## Tier 2: Nearby combat - every 2 frames
## Tier 3: Far from combat - every 4 frames

signal tier_changed(unit_id: int, old_tier: int, new_tier: int)
signal batch_processed(tier: int, count: int, time_ms: float)

## Performance tiers
enum Tier {
	IN_COMBAT = 1,     ## Update every frame
	NEAR_COMBAT = 2,   ## Update every 2 frames
	FAR_FROM_COMBAT = 3  ## Update every 4 frames
}

## Tier names for debugging
const TIER_NAMES := {
	Tier.IN_COMBAT: "in_combat",
	Tier.NEAR_COMBAT: "near_combat",
	Tier.FAR_FROM_COMBAT: "far_from_combat"
}

## Update intervals (in frames)
const TIER_INTERVALS := {
	Tier.IN_COMBAT: 1,
	Tier.NEAR_COMBAT: 2,
	Tier.FAR_FROM_COMBAT: 4
}

## Distance thresholds for tier assignment
const COMBAT_RANGE := 30.0  ## In combat within this range of enemy
const NEAR_COMBAT_RANGE := 60.0  ## Near combat within this range

## Unit tier data (unit_id -> tier data)
var _unit_tiers: Dictionary = {}

## Units per tier (tier -> Array[int])
var _tier_units: Dictionary = {
	Tier.IN_COMBAT: [],
	Tier.NEAR_COMBAT: [],
	Tier.FAR_FROM_COMBAT: []
}

## Current frame counter
var _frame_count := 0

## Performance metrics
var _tier_process_times: Dictionary = {
	Tier.IN_COMBAT: 0.0,
	Tier.NEAR_COMBAT: 0.0,
	Tier.FAR_FROM_COMBAT: 0.0
}

## Callbacks
var _get_unit_position: Callable
var _get_nearest_enemy_distance: Callable


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_nearest_enemy_distance(callback: Callable) -> void:
	_get_nearest_enemy_distance = callback


## Register unit with initial tier.
func register_unit(unit_id: int, initial_tier: int = Tier.FAR_FROM_COMBAT) -> void:
	_unit_tiers[unit_id] = {
		"tier": initial_tier,
		"last_update_frame": 0,
		"combat_distance": INF
	}

	_tier_units[initial_tier].append(unit_id)


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	if not _unit_tiers.has(unit_id):
		return

	var tier: int = _unit_tiers[unit_id]["tier"]
	_unit_tiers.erase(unit_id)

	var idx: int = _tier_units[tier].find(unit_id)
	if idx != -1:
		_tier_units[tier].remove_at(idx)


## Update tier assignments based on combat proximity.
func update_tiers() -> void:
	for unit_id in _unit_tiers:
		var new_tier := _calculate_tier(unit_id)
		var current_tier: int = _unit_tiers[unit_id]["tier"]

		if new_tier != current_tier:
			_change_tier(unit_id, current_tier, new_tier)


## Calculate tier for unit based on combat proximity.
func _calculate_tier(unit_id: int) -> int:
	if not _get_nearest_enemy_distance.is_valid():
		return Tier.FAR_FROM_COMBAT

	var distance: float = _get_nearest_enemy_distance.call(unit_id)
	_unit_tiers[unit_id]["combat_distance"] = distance

	if distance <= COMBAT_RANGE:
		return Tier.IN_COMBAT
	elif distance <= NEAR_COMBAT_RANGE:
		return Tier.NEAR_COMBAT

	return Tier.FAR_FROM_COMBAT


## Change unit tier.
func _change_tier(unit_id: int, old_tier: int, new_tier: int) -> void:
	# Remove from old tier
	var old_idx: int = _tier_units[old_tier].find(unit_id)
	if old_idx != -1:
		_tier_units[old_tier].remove_at(old_idx)

	# Add to new tier
	_tier_units[new_tier].append(unit_id)
	_unit_tiers[unit_id]["tier"] = new_tier

	tier_changed.emit(unit_id, old_tier, new_tier)


## Get units to update this frame.
func get_units_to_update() -> Array[int]:
	var units: Array[int] = []

	for tier in Tier.values():
		var interval: int = TIER_INTERVALS[tier]

		if _frame_count % interval == 0:
			for unit_id in _tier_units[tier]:
				units.append(unit_id)

	return units


## Advance frame counter.
func advance_frame() -> void:
	_frame_count += 1

	# Wrap to prevent overflow
	if _frame_count > 1000000:
		_frame_count = 0


## Check if unit should update this frame.
func should_update(unit_id: int) -> bool:
	if not _unit_tiers.has(unit_id):
		return true

	var tier: int = _unit_tiers[unit_id]["tier"]
	var interval: int = TIER_INTERVALS[tier]

	return _frame_count % interval == 0


## Get unit tier.
func get_tier(unit_id: int) -> int:
	if not _unit_tiers.has(unit_id):
		return Tier.FAR_FROM_COMBAT
	return _unit_tiers[unit_id]["tier"]


## Get tier name.
func get_tier_name(unit_id: int) -> String:
	return TIER_NAMES.get(get_tier(unit_id), "unknown")


## Get unit count per tier.
func get_tier_counts() -> Dictionary:
	return {
		Tier.IN_COMBAT: _tier_units[Tier.IN_COMBAT].size(),
		Tier.NEAR_COMBAT: _tier_units[Tier.NEAR_COMBAT].size(),
		Tier.FAR_FROM_COMBAT: _tier_units[Tier.FAR_FROM_COMBAT].size()
	}


## Record processing time for tier.
func record_process_time(tier: int, time_ms: float) -> void:
	_tier_process_times[tier] = time_ms
	batch_processed.emit(tier, _tier_units[tier].size(), time_ms)


## Force unit to highest priority tier.
func prioritize_unit(unit_id: int) -> void:
	if not _unit_tiers.has(unit_id):
		return

	var current_tier: int = _unit_tiers[unit_id]["tier"]
	if current_tier != Tier.IN_COMBAT:
		_change_tier(unit_id, current_tier, Tier.IN_COMBAT)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var counts := get_tier_counts()

	return {
		"frame_count": _frame_count,
		"total_units": _unit_tiers.size(),
		"tier_counts": {
			"in_combat": counts[Tier.IN_COMBAT],
			"near_combat": counts[Tier.NEAR_COMBAT],
			"far_from_combat": counts[Tier.FAR_FROM_COMBAT]
		},
		"tier_intervals": TIER_INTERVALS.duplicate(),
		"process_times_ms": _tier_process_times.duplicate()
	}
