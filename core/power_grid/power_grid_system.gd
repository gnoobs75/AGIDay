class_name PowerGridSystem
extends RefCounted
## PowerGridSystem is the central coordinator for all power grid functionality.
## Provides integration points for other game systems.

signal power_update_completed(delta: float)
signal faction_power_changed(faction_id: String, analytics: Dictionary)
signal district_captured(district_id: int, old_faction: String, new_faction: String)
signal factory_blackout_effect(factory_id: int, multiplier: float)
signal plant_constructed(plant_id: int, faction_id: String, cost: Dictionary)
signal system_ready()

## Core systems
var power_api: PowerGridAPI = null
var consumer_manager: PowerConsumerManager = null
var stability_tracker: GridStability = null

## Integration callbacks
var _on_district_capture: Callable
var _on_factory_production_update: Callable
var _on_resource_deduction: Callable

## Update timing
var _update_interval: float = 0.1
var _accumulated_time: float = 0.0

## Power analytics cache per faction
var _faction_analytics: Dictionary = {}

## Frame statistics
var _last_update_time_ms: float = 0.0
var _total_updates: int = 0


func _init() -> void:
	_initialize_systems()


## Initialize all subsystems.
func _initialize_systems() -> void:
	power_api = PowerGridAPI.new()
	consumer_manager = PowerConsumerManager.new()
	stability_tracker = GridStability.new()

	# Wire up references
	consumer_manager.set_power_api(power_api)
	stability_tracker.set_power_api(power_api)
	stability_tracker.set_consumer_manager(consumer_manager)

	# Connect signals for integration
	power_api.blackout_alert.connect(_on_blackout_alert)
	power_api.power_restored.connect(_on_power_restored)
	power_api.infrastructure_damaged.connect(_on_infrastructure_damaged)

	consumer_manager.consumer_power_state_changed.connect(_on_consumer_power_changed)

	system_ready.emit()


## Set update interval.
func set_update_interval(interval: float) -> void:
	_update_interval = maxf(0.016, interval)


# ============================================
# MAIN UPDATE LOOP
# ============================================

## Main update - call each frame.
func update(delta: float) -> void:
	_accumulated_time += delta

	if _accumulated_time < _update_interval:
		return

	_accumulated_time = 0.0
	_perform_update(delta)


## Perform full update cycle.
func _perform_update(delta: float) -> void:
	var start_time := Time.get_ticks_usec()

	# 1. Update power generation
	update_power_generation(delta)

	# 2. Update power consumption
	update_power_consumption()

	# 3. Recalculate power distribution
	power_api.recalculate()

	# 4. Update consumer states (applies blackout effects)
	consumer_manager.update_from_power_grid()

	# 5. Update stability tracking
	stability_tracker.update_all()

	# 6. Update analytics
	_update_faction_analytics()

	# Track performance
	_last_update_time_ms = float(Time.get_ticks_usec() - start_time) / 1000.0
	_total_updates += 1

	power_update_completed.emit(delta)


## Update power generation from all plants.
func update_power_generation(delta: float) -> void:
	# Power generation is already handled per-frame in PowerGridManager
	# This is where we could add time-based generation effects
	power_api.update(delta)


## Update power consumption from all consumers.
func update_power_consumption() -> void:
	# Aggregate consumption into districts
	for district_id in _get_all_district_ids():
		var consumers := consumer_manager.get_district_consumers(district_id)
		var total_demand := 0.0

		for consumer in consumers:
			total_demand += consumer.power_requirement

		power_api.set_district_demand(district_id, total_demand)


func _get_all_district_ids() -> Array[int]:
	var ids: Array[int] = []
	# Get from grid manager's districts
	for district_id in power_api.grid_manager._districts:
		ids.append(district_id)
	return ids


# ============================================
# POWER PLANT API
# ============================================

## Create solar plant with resource cost.
func create_solar_plant(faction_id: String, position: Vector3, deduct_resources: bool = true) -> int:
	var cost := get_solar_plant_cost()

	if deduct_resources and _on_resource_deduction.is_valid():
		if not _on_resource_deduction.call(faction_id, cost):
			return -1  # Failed to deduct resources

	var plant_id := power_api.create_solar_plant(faction_id, position)

	if plant_id >= 0:
		plant_constructed.emit(plant_id, faction_id, cost)

	return plant_id


## Create fusion plant with resource cost.
func create_fusion_plant(faction_id: String, position: Vector3, deduct_resources: bool = true) -> int:
	var cost := get_fusion_plant_cost()

	if deduct_resources and _on_resource_deduction.is_valid():
		if not _on_resource_deduction.call(faction_id, cost):
			return -1  # Failed to deduct resources

	var plant_id := power_api.create_fusion_plant(faction_id, position)

	if plant_id >= 0:
		plant_constructed.emit(plant_id, faction_id, cost)

	return plant_id


## Get solar plant construction cost.
func get_solar_plant_cost() -> Dictionary:
	return {
		"ree": 100,
		"energy": 50
	}


## Get fusion plant construction cost.
func get_fusion_plant_cost() -> Dictionary:
	return {
		"ree": 250,
		"energy": 150
	}


# ============================================
# DISTRICT INTEGRATION
# ============================================

## Handle district capture.
func on_district_captured(district_id: int, old_faction: String, new_faction: String) -> void:
	var district := power_api.grid_manager.get_district(district_id)
	if district != null:
		district.set_controlling_faction(new_faction)

	# Update consumers in district
	var consumers := consumer_manager.get_district_consumers(district_id)
	for consumer in consumers:
		consumer.faction_id = new_faction

	# Recalculate power
	power_api.recalculate()

	district_captured.emit(district_id, old_faction, new_faction)


## Create district for faction.
func create_district(faction_id: String, power_demand: float = 100.0) -> int:
	return power_api.create_district(faction_id, power_demand)


## Connect power line to district.
func connect_plant_to_district(plant_id: int, district_id: int, capacity: float = 100.0) -> int:
	return power_api.create_power_line(plant_id, district_id, capacity)


# ============================================
# FACTORY INTEGRATION
# ============================================

## Register factory as power consumer.
func register_factory(faction_id: String, district_id: int, power_requirement: float = 50.0) -> int:
	var consumer := consumer_manager.register_factory(faction_id, district_id)
	consumer.set_power_requirement(power_requirement)
	return consumer.consumer_id


## Unregister factory.
func unregister_factory(consumer_id: int) -> void:
	consumer_manager.unregister_consumer(consumer_id)


## Get factory production multiplier (accounting for blackouts).
func get_factory_production_multiplier(consumer_id: int) -> float:
	return consumer_manager.get_production_multiplier(consumer_id)


## Set factory production update callback.
func set_factory_production_callback(callback: Callable) -> void:
	_on_factory_production_update = callback


# ============================================
# RESOURCE INTEGRATION
# ============================================

## Set resource deduction callback.
func set_resource_deduction_callback(callback: Callable) -> void:
	_on_resource_deduction = callback


# ============================================
# POWER ANALYTICS
# ============================================

## Get power analytics for faction.
func get_power_analytics(faction_id: String) -> Dictionary:
	if _faction_analytics.has(faction_id):
		return _faction_analytics[faction_id]

	return _calculate_faction_analytics(faction_id)


## Calculate faction analytics.
func _calculate_faction_analytics(faction_id: String) -> Dictionary:
	var status := power_api.get_faction_power_status(faction_id)
	var stability := stability_tracker.get_stability(faction_id)
	var consumption := consumer_manager.get_faction_consumption(faction_id)

	var generation: float = status.get("generation", 0.0)
	var demand: float = status.get("demand", 0.0)

	var plants_info: Dictionary = status.get("plants", {})
	var districts_info: Dictionary = status.get("districts", {})

	return {
		"faction_id": faction_id,
		"generation": {
			"total": generation,
			"solar": _get_solar_generation(faction_id),
			"fusion": _get_fusion_generation(faction_id)
		},
		"consumption": {
			"total": consumption,
			"demand": demand,
			"deficit": maxf(0.0, demand - generation)
		},
		"balance": {
			"surplus": maxf(0.0, generation - demand),
			"deficit": maxf(0.0, demand - generation),
			"ratio": status.get("ratio", 0.0)
		},
		"plants": {
			"total": plants_info.get("total", 0),
			"operational": plants_info.get("operational", 0),
			"destroyed": plants_info.get("destroyed", 0)
		},
		"districts": {
			"total": districts_info.get("total", 0),
			"powered": districts_info.get("powered", 0),
			"blackout": districts_info.get("blackout", 0)
		},
		"stability": {
			"score": stability.get("stability_score", 0.0),
			"risk_level": stability.get("risk_level", 0),
			"vulnerabilities": stability.get("vulnerabilities", [])
		},
		"consumers": {
			"factories": _get_consumer_count(faction_id, PowerConsumer.ConsumerType.FACTORY),
			"infrastructure": _get_consumer_count(faction_id, PowerConsumer.ConsumerType.INFRASTRUCTURE),
			"defense": _get_consumer_count(faction_id, PowerConsumer.ConsumerType.DEFENSE),
			"research": _get_consumer_count(faction_id, PowerConsumer.ConsumerType.RESEARCH)
		}
	}


## Update faction analytics cache.
func _update_faction_analytics() -> void:
	var factions: Dictionary = {}

	# Get all factions from plants
	for plant_id in power_api.grid_manager._plants:
		var plant: PowerPlant = power_api.grid_manager._plants[plant_id]
		factions[plant.faction_id] = true

	# Get all factions from consumers
	for consumer_id in consumer_manager._consumers:
		var consumer: PowerConsumer = consumer_manager._consumers[consumer_id]
		factions[consumer.faction_id] = true

	# Update analytics for each faction
	for faction_id in factions:
		var analytics := _calculate_faction_analytics(faction_id)
		var old_analytics: Dictionary = _faction_analytics.get(faction_id, {})

		_faction_analytics[faction_id] = analytics

		# Check for significant changes
		var old_gen: float = old_analytics.get("generation", {}).get("total", -1.0)
		var new_gen: float = analytics["generation"]["total"]

		if abs(old_gen - new_gen) > 1.0:
			faction_power_changed.emit(faction_id, analytics)


func _get_solar_generation(faction_id: String) -> float:
	var total := 0.0
	for plant in power_api.grid_manager.get_faction_plants(faction_id):
		if plant.plant_type == PowerPlant.PlantType.SOLAR and plant.is_operational():
			total += plant.current_output
	return total


func _get_fusion_generation(faction_id: String) -> float:
	var total := 0.0
	for plant in power_api.grid_manager.get_faction_plants(faction_id):
		if plant.plant_type == PowerPlant.PlantType.FUSION and plant.is_operational():
			total += plant.current_output
	return total


func _get_consumer_count(faction_id: String, consumer_type: int) -> int:
	var count := 0
	for consumer in consumer_manager.get_faction_consumers(faction_id):
		if consumer.consumer_type == consumer_type:
			count += 1
	return count


# ============================================
# QUERY API
# ============================================

## Get all plants for faction.
func get_faction_plants(faction_id: String) -> Array[PowerPlant]:
	return power_api.grid_manager.get_faction_plants(faction_id)


## Get all districts for faction.
func get_faction_districts(faction_id: String) -> Array[DistrictPowerState]:
	return power_api.grid_manager.get_faction_districts(faction_id)


## Get all power lines.
func get_all_power_lines() -> Array[PowerLine]:
	var lines: Array[PowerLine] = []
	for line_id in power_api.grid_manager._lines:
		lines.append(power_api.grid_manager._lines[line_id])
	return lines


## Get power lines for plant.
func get_plant_lines(plant_id: int) -> Array[PowerLine]:
	var lines: Array[PowerLine] = []
	var plant := power_api.grid_manager.get_plant(plant_id)
	if plant == null:
		return lines

	for line_id in plant.connected_line_ids:
		var line := power_api.grid_manager.get_line(line_id)
		if line != null:
			lines.append(line)

	return lines


## Check if faction has power surplus.
func has_power_surplus(faction_id: String) -> bool:
	return power_api.has_power_surplus(faction_id)


## Check if faction has power deficit.
func has_power_deficit(faction_id: String) -> bool:
	return power_api.has_power_deficit(faction_id)


## Check if district is in blackout.
func is_district_in_blackout(district_id: int) -> bool:
	return power_api.is_district_in_blackout(district_id)


# ============================================
# DAYLIGHT INTEGRATION
# ============================================

## Set daylight multiplier (0.0 = night, 1.0 = full daylight).
func set_daylight_multiplier(multiplier: float) -> void:
	power_api.set_daylight_multiplier(multiplier)


# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_blackout_alert(district_id: int, severity: int) -> void:
	# Notify factories in this district
	var consumers := consumer_manager.get_district_consumers(district_id)
	for consumer in consumers:
		if consumer.consumer_type == PowerConsumer.ConsumerType.FACTORY:
			var multiplier := consumer.get_production_multiplier()
			factory_blackout_effect.emit(consumer.consumer_id, multiplier)

			if _on_factory_production_update.is_valid():
				_on_factory_production_update.call(consumer.consumer_id, multiplier)


func _on_power_restored(district_id: int) -> void:
	# Notify factories power is restored
	var consumers := consumer_manager.get_district_consumers(district_id)
	for consumer in consumers:
		if consumer.consumer_type == PowerConsumer.ConsumerType.FACTORY:
			factory_blackout_effect.emit(consumer.consumer_id, 1.0)

			if _on_factory_production_update.is_valid():
				_on_factory_production_update.call(consumer.consumer_id, 1.0)


func _on_infrastructure_damaged(type: String, id: int) -> void:
	# Trigger immediate recalculation
	power_api.recalculate()
	stability_tracker.update_all()


func _on_consumer_power_changed(consumer_id: int, is_powered: bool) -> void:
	var consumer := consumer_manager.get_consumer(consumer_id)
	if consumer != null and consumer.consumer_type == PowerConsumer.ConsumerType.FACTORY:
		var multiplier := consumer.get_production_multiplier()
		factory_blackout_effect.emit(consumer_id, multiplier)


# ============================================
# SERIALIZATION
# ============================================

func to_dict() -> Dictionary:
	return {
		"power_api": power_api.to_dict(),
		"consumer_manager": consumer_manager.to_dict(),
		"stability_tracker": stability_tracker.to_dict(),
		"update_interval": _update_interval,
		"faction_analytics": _faction_analytics.duplicate(true)
	}


func from_dict(data: Dictionary) -> void:
	if data.has("power_api"):
		power_api.from_dict(data["power_api"])
	if data.has("consumer_manager"):
		consumer_manager.from_dict(data["consumer_manager"])
	if data.has("stability_tracker"):
		stability_tracker.from_dict(data["stability_tracker"])

	_update_interval = data.get("update_interval", 0.1)
	_faction_analytics = data.get("faction_analytics", {}).duplicate(true)


func get_summary() -> Dictionary:
	return {
		"update_interval": _update_interval,
		"last_update_time_ms": _last_update_time_ms,
		"total_updates": _total_updates,
		"power_api": power_api.get_summary(),
		"consumer_manager": consumer_manager.get_summary(),
		"stability_tracker": stability_tracker.get_summary(),
		"tracked_factions": _faction_analytics.size()
	}
