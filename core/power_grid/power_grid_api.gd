class_name PowerGridAPI
extends RefCounted
## PowerGridAPI provides a high-level interface for power grid operations.
## Unified access point for power status, balance, and blackout information.

signal power_status_changed(faction_id: String, status: Dictionary)
signal blackout_alert(district_id: int, severity: int)
signal power_restored(district_id: int)
signal infrastructure_damaged(type: String, id: int)
signal infrastructure_repaired(type: String, id: int)

## Core systems
var grid_manager: PowerGridManager = null
var cascade_system: BlackoutCascade = null

## Cached status per faction
var _faction_status_cache: Dictionary = {}
var _cache_dirty: bool = true


func _init() -> void:
	grid_manager = PowerGridManager.new()
	cascade_system = BlackoutCascade.new()
	cascade_system.set_grid_manager(grid_manager)

	# Connect grid manager signals
	grid_manager.plant_destroyed.connect(_on_plant_destroyed)
	grid_manager.line_destroyed.connect(_on_line_destroyed)
	grid_manager.blackout_changed.connect(_on_blackout_changed)
	grid_manager.network_topology_changed.connect(_on_topology_changed)


## Update the power grid system.
func update(delta: float) -> void:
	grid_manager.update(delta)
	cascade_system.update_cascades()

	if _cache_dirty:
		_update_faction_caches()
		_cache_dirty = false


## Force immediate power recalculation.
func recalculate() -> void:
	grid_manager.force_recalculation()
	cascade_system.update_cascades()
	_cache_dirty = true


# ============================================
# POWER PLANT API
# ============================================

## Create a new solar power plant.
func create_solar_plant(faction_id: String, position: Vector3) -> int:
	var plant := grid_manager.create_solar_plant(faction_id, position)
	_cache_dirty = true
	return plant.id


## Create a new fusion power plant.
func create_fusion_plant(faction_id: String, position: Vector3) -> int:
	var plant := grid_manager.create_fusion_plant(faction_id, position)
	_cache_dirty = true
	return plant.id


## Get power plant info.
func get_plant_info(plant_id: int) -> Dictionary:
	var plant := grid_manager.get_plant(plant_id)
	if plant == null:
		return {}
	return plant.get_summary()


## Damage a power plant.
func damage_plant(plant_id: int, damage: float) -> void:
	var plant := grid_manager.get_plant(plant_id)
	if plant != null:
		plant.apply_damage(damage)


## Repair a power plant.
func repair_plant(plant_id: int, amount: float) -> void:
	var plant := grid_manager.get_plant(plant_id)
	if plant != null:
		plant.repair(amount)
		if plant.is_operational():
			infrastructure_repaired.emit("plant", plant_id)
			_cache_dirty = true


## Fully repair a power plant.
func full_repair_plant(plant_id: int) -> void:
	var plant := grid_manager.get_plant(plant_id)
	if plant != null:
		var was_destroyed := plant.is_destroyed
		plant.full_repair()
		if was_destroyed:
			infrastructure_repaired.emit("plant", plant_id)
			_cache_dirty = true


# ============================================
# POWER LINE API
# ============================================

## Create a power line between plant and district.
func create_power_line(source_plant_id: int, target_district_id: int, capacity: float = 100.0) -> int:
	var line := grid_manager.create_power_line(source_plant_id, target_district_id, capacity)
	if line == null:
		return -1
	_cache_dirty = true
	return line.id


## Get power line info.
func get_line_info(line_id: int) -> Dictionary:
	var line := grid_manager.get_line(line_id)
	if line == null:
		return {}
	return line.get_summary()


## Damage a power line.
func damage_line(line_id: int, damage: float) -> void:
	var line := grid_manager.get_line(line_id)
	if line != null:
		line.apply_damage(damage)


## Repair a power line.
func repair_line(line_id: int, amount: float) -> void:
	var line := grid_manager.get_line(line_id)
	if line != null:
		var was_destroyed := line.is_destroyed
		line.repair(amount)
		if was_destroyed and line.is_active():
			infrastructure_repaired.emit("line", line_id)
			_cache_dirty = true


## Fully repair a power line.
func full_repair_line(line_id: int) -> void:
	var line := grid_manager.get_line(line_id)
	if line != null:
		var was_destroyed := line.is_destroyed
		line.full_repair()
		if was_destroyed:
			infrastructure_repaired.emit("line", line_id)
			_cache_dirty = true


# ============================================
# DISTRICT API
# ============================================

## Create a new district.
func create_district(faction_id: String, power_demand: float = 100.0) -> int:
	var district := grid_manager.create_district(faction_id, power_demand)
	_cache_dirty = true
	return district.district_id


## Get district power info.
func get_district_info(district_id: int) -> Dictionary:
	var district := grid_manager.get_district(district_id)
	if district == null:
		return {}

	var info := district.get_summary()
	info["blackout_severity"] = cascade_system.get_blackout_severity(district_id)
	info["production_penalty"] = cascade_system.get_production_penalty(district_id)
	info["production_multiplier"] = cascade_system.get_production_multiplier(district_id)

	return info


## Set district power demand.
func set_district_demand(district_id: int, demand: float) -> void:
	var district := grid_manager.get_district(district_id)
	if district != null:
		district.set_power_demand(demand)
		_cache_dirty = true


## Get production multiplier for district (accounting for blackouts).
func get_district_production_multiplier(district_id: int) -> float:
	return cascade_system.get_production_multiplier(district_id)


# ============================================
# POWER STATUS API
# ============================================

## Get power status for a faction.
func get_faction_power_status(faction_id: String) -> Dictionary:
	if _faction_status_cache.has(faction_id):
		return _faction_status_cache[faction_id]
	return _calculate_faction_status(faction_id)


## Get power balance for faction.
func get_power_balance(faction_id: String) -> float:
	var status := get_faction_power_status(faction_id)
	return status.get("balance", 0.0)


## Check if faction has power surplus.
func has_power_surplus(faction_id: String) -> bool:
	return get_power_balance(faction_id) > 0.0


## Check if faction has power deficit.
func has_power_deficit(faction_id: String) -> bool:
	return get_power_balance(faction_id) < 0.0


## Get total generation for faction.
func get_faction_generation(faction_id: String) -> float:
	return grid_manager.get_faction_generation(faction_id)


## Get total demand for faction.
func get_faction_demand(faction_id: String) -> float:
	return grid_manager.get_faction_demand(faction_id)


# ============================================
# BLACKOUT API
# ============================================

## Get all blackout districts for faction.
func get_faction_blackouts(faction_id: String) -> Array[int]:
	var result: Array[int] = []
	var districts := grid_manager.get_faction_blackouts(faction_id)
	for district in districts:
		result.append(district.district_id)
	return result


## Check if district is in blackout.
func is_district_in_blackout(district_id: int) -> bool:
	var district := grid_manager.get_district(district_id)
	if district == null:
		return false
	return district.is_blackout


## Get blackout severity for district.
func get_blackout_severity(district_id: int) -> int:
	return cascade_system.get_blackout_severity(district_id)


## Get all affected districts from cascades.
func get_cascade_affected_districts() -> Array[int]:
	return cascade_system.get_affected_districts()


# ============================================
# DAYLIGHT API
# ============================================

## Set daylight multiplier (affects solar plants).
func set_daylight_multiplier(multiplier: float) -> void:
	grid_manager.set_daylight_multiplier(multiplier)
	_cache_dirty = true


# ============================================
# INTERNAL METHODS
# ============================================

func _calculate_faction_status(faction_id: String) -> Dictionary:
	var generation := grid_manager.get_faction_generation(faction_id)
	var demand := grid_manager.get_faction_demand(faction_id)
	var balance := generation - demand

	var plants := grid_manager.get_faction_plants(faction_id)
	var operational_plants := 0
	var destroyed_plants := 0
	for plant in plants:
		if plant.is_operational():
			operational_plants += 1
		else:
			destroyed_plants += 1

	var districts := grid_manager.get_faction_districts(faction_id)
	var powered_districts := 0
	var blackout_districts := 0
	for district in districts:
		if district.is_blackout:
			blackout_districts += 1
		else:
			powered_districts += 1

	var ratio := 1.0 if demand <= 0.0 else minf(generation / demand, 1.0)

	return {
		"faction_id": faction_id,
		"generation": generation,
		"demand": demand,
		"balance": balance,
		"ratio": ratio,
		"has_surplus": balance > 0.0,
		"has_deficit": balance < 0.0,
		"plants": {
			"total": plants.size(),
			"operational": operational_plants,
			"destroyed": destroyed_plants
		},
		"districts": {
			"total": districts.size(),
			"powered": powered_districts,
			"blackout": blackout_districts
		}
	}


func _update_faction_caches() -> void:
	_faction_status_cache.clear()

	# Get all unique faction IDs
	var factions: Dictionary = {}
	for plant in grid_manager._plants.values():
		factions[plant.faction_id] = true
	for district in grid_manager._districts.values():
		factions[district.controlling_faction] = true

	for faction_id in factions:
		var status := _calculate_faction_status(faction_id)
		_faction_status_cache[faction_id] = status
		power_status_changed.emit(faction_id, status)


func _on_plant_destroyed(plant_id: int) -> void:
	cascade_system.on_plant_destroyed(plant_id)
	infrastructure_damaged.emit("plant", plant_id)
	_cache_dirty = true


func _on_line_destroyed(line_id: int) -> void:
	cascade_system.on_line_destroyed(line_id)
	infrastructure_damaged.emit("line", line_id)
	_cache_dirty = true


func _on_blackout_changed(district_id: int, is_blackout: bool) -> void:
	if is_blackout:
		var severity := cascade_system.get_blackout_severity(district_id)
		blackout_alert.emit(district_id, severity)
	else:
		power_restored.emit(district_id)
	_cache_dirty = true


func _on_topology_changed() -> void:
	_cache_dirty = true


## Serialization.
func to_dict() -> Dictionary:
	return {
		"grid_manager": grid_manager.to_dict(),
		"cascade_system": cascade_system.to_dict()
	}


func from_dict(data: Dictionary) -> void:
	if data.has("grid_manager"):
		grid_manager.from_dict(data["grid_manager"])
	if data.has("cascade_system"):
		cascade_system.from_dict(data["cascade_system"])
	_cache_dirty = true


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"grid": grid_manager.get_summary(),
		"cascades": cascade_system.get_summary(),
		"cached_factions": _faction_status_cache.size()
	}
