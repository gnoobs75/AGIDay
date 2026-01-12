class_name PassiveIncomeGenerator
extends RefCounted
## PassiveIncomeGenerator handles tick-based resource generation.
## Manages district income, scaling, and buff integration.

signal income_generated(faction_id: int, ree: float, power: float)
signal tick_completed(tick_count: int)

## Income per district per tick
const BASE_REE_PER_DISTRICT := 10.0
const BASE_POWER_PER_DISTRICT := 50.0

## Tick interval in seconds
const TICK_INTERVAL := 1.0

## Economic scaling over match duration
const SCALING_MAX_MULTIPLIER := 1.5
const SCALING_DURATION_SECONDS := 1800.0  # 30 minutes

## Current state
var _time_accumulator: float = 0.0
var _match_start_time: int = 0
var _tick_count: int = 0

## Faction district counts (faction_id -> district_count)
var _faction_districts: Dictionary = {}

## Faction buff multipliers (faction_id -> {ree_mult, power_mult})
var _faction_buffs: Dictionary = {}

## Resource pools reference (faction_id -> ResourcePool)
var _resource_pools: Dictionary = {}


func _init() -> void:
	_match_start_time = Time.get_ticks_msec()


## Register a resource pool for a faction.
func register_faction(faction_id: int, pool: ResourcePool, initial_districts: int = 0) -> void:
	_resource_pools[faction_id] = pool
	_faction_districts[faction_id] = initial_districts
	_faction_buffs[faction_id] = {"ree_mult": 1.0, "power_mult": 1.0}


## Set district count for a faction.
func set_district_count(faction_id: int, count: int) -> void:
	_faction_districts[faction_id] = maxi(0, count)


## Add a district to a faction.
func add_district(faction_id: int) -> void:
	_faction_districts[faction_id] = _faction_districts.get(faction_id, 0) + 1


## Remove a district from a faction.
func remove_district(faction_id: int) -> void:
	_faction_districts[faction_id] = maxi(0, _faction_districts.get(faction_id, 0) - 1)


## Get district count for a faction.
func get_district_count(faction_id: int) -> int:
	return _faction_districts.get(faction_id, 0)


## Set buff multipliers for a faction.
func set_faction_buffs(faction_id: int, ree_mult: float, power_mult: float) -> void:
	_faction_buffs[faction_id] = {
		"ree_mult": maxf(0.0, ree_mult),
		"power_mult": maxf(0.0, power_mult)
	}


## Get current economic scaling multiplier based on match duration.
func get_scaling_multiplier() -> float:
	var elapsed_ms := Time.get_ticks_msec() - _match_start_time
	var elapsed_seconds := float(elapsed_ms) / 1000.0

	# Linear scaling from 1.0 to SCALING_MAX_MULTIPLIER over SCALING_DURATION_SECONDS
	var progress := clampf(elapsed_seconds / SCALING_DURATION_SECONDS, 0.0, 1.0)
	return 1.0 + (SCALING_MAX_MULTIPLIER - 1.0) * progress


## Process a frame and generate income if tick elapsed.
func process(delta: float) -> void:
	_time_accumulator += delta

	while _time_accumulator >= TICK_INTERVAL:
		_time_accumulator -= TICK_INTERVAL
		_generate_tick()


## Generate income for all factions.
func _generate_tick() -> void:
	_tick_count += 1
	var scaling := get_scaling_multiplier()

	for faction_id in _resource_pools:
		var pool: ResourcePool = _resource_pools[faction_id]
		var districts: int = _faction_districts.get(faction_id, 0)
		var buffs: Dictionary = _faction_buffs.get(faction_id, {"ree_mult": 1.0, "power_mult": 1.0})

		if districts > 0:
			var ree_income := BASE_REE_PER_DISTRICT * districts * buffs["ree_mult"] * scaling
			var power_income := BASE_POWER_PER_DISTRICT * districts * buffs["power_mult"] * scaling

			pool.add_ree(ree_income, "district_income")
			pool.add_power(power_income, "district_income")

			income_generated.emit(faction_id, ree_income, power_income)

	tick_completed.emit(_tick_count)


## Force a tick (for testing or manual triggering).
func force_tick() -> void:
	_generate_tick()


## Get tick count.
func get_tick_count() -> int:
	return _tick_count


## Get match elapsed time in seconds.
func get_match_elapsed() -> float:
	return float(Time.get_ticks_msec() - _match_start_time) / 1000.0


## Calculate projected income for a faction.
func get_projected_income(faction_id: int) -> Dictionary:
	var districts: int = _faction_districts.get(faction_id, 0)
	var buffs: Dictionary = _faction_buffs.get(faction_id, {"ree_mult": 1.0, "power_mult": 1.0})
	var scaling := get_scaling_multiplier()

	var ree_per_tick := BASE_REE_PER_DISTRICT * districts * buffs["ree_mult"] * scaling
	var power_per_tick := BASE_POWER_PER_DISTRICT * districts * buffs["power_mult"] * scaling

	return {
		"ree_per_tick": ree_per_tick,
		"power_per_tick": power_per_tick,
		"ree_per_minute": ree_per_tick * 60.0,
		"power_per_minute": power_per_tick * 60.0,
		"districts": districts,
		"scaling": scaling
	}


## Reset income generator for new match.
func reset() -> void:
	_time_accumulator = 0.0
	_match_start_time = Time.get_ticks_msec()
	_tick_count = 0
	_faction_districts.clear()
	_faction_buffs.clear()
	# Note: Resource pools are not cleared, they are managed externally


## Clear all registered factions.
func clear_factions() -> void:
	_resource_pools.clear()
	_faction_districts.clear()
	_faction_buffs.clear()


## Serialize state.
func to_dict() -> Dictionary:
	return {
		"tick_count": _tick_count,
		"match_start_time": _match_start_time,
		"faction_districts": _faction_districts.duplicate(),
		"faction_buffs": _faction_buffs.duplicate()
	}


## Deserialize state.
func from_dict(data: Dictionary) -> void:
	_tick_count = data.get("tick_count", 0)
	_match_start_time = data.get("match_start_time", Time.get_ticks_msec())
	_faction_districts = data.get("faction_districts", {}).duplicate()
	_faction_buffs = data.get("faction_buffs", {}).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_incomes := {}
	for faction_id in _resource_pools:
		faction_incomes[faction_id] = get_projected_income(faction_id)

	return {
		"tick_count": _tick_count,
		"match_elapsed": get_match_elapsed(),
		"scaling_multiplier": get_scaling_multiplier(),
		"faction_incomes": faction_incomes
	}
