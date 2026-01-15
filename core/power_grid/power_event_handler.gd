class_name PowerEventHandler
extends RefCounted
## PowerEventHandler coordinates power plant destruction and blackout events.
## Provides event-driven architecture for power infrastructure changes.

signal plant_destroyed(plant: PowerPlant)
signal plant_damaged(plant: PowerPlant, damage: float, remaining_health: float)
signal district_blackout(district: DistrictPowerState)
signal district_power_restored(district: DistrictPowerState)
signal production_paused(district_id: int, factory_ids: Array)
signal production_resumed(district_id: int, factory_ids: Array)
signal income_multiplier_changed(district_id: int, multiplier: float)
signal cascade_event(source_type: String, source_id: int, affected_districts: Array)

## Blackout income multiplier
const BLACKOUT_INCOME_MULTIPLIER := 0.50  ## 50% income during blackout

## References
var _power_system = null  # PowerGridSystem

## District income multipliers (district_id -> multiplier)
var _district_income_multipliers: Dictionary = {}

## Paused factories (district_id -> Array[int] factory_ids)
var _paused_factories: Dictionary = {}

## Event history for debugging
var _event_history: Array[Dictionary] = []
const MAX_HISTORY := 100


func _init() -> void:
	pass


## Set power system reference.
func set_power_system(system) -> void:
	_power_system = system

	if _power_system != null:
		_connect_signals()


## Connect to power system signals.
func _connect_signals() -> void:
	if _power_system.power_api != null:
		_power_system.power_api.blackout_alert.connect(_on_blackout_alert)
		_power_system.power_api.power_restored.connect(_on_power_restored)
		_power_system.power_api.infrastructure_damaged.connect(_on_infrastructure_damaged)


# ============================================
# POWER PLANT DAMAGE & DESTRUCTION
# ============================================

## Take damage on a power plant.
func take_plant_damage(plant_id: int, damage: float) -> void:
	if _power_system == null:
		return

	var plant: PowerPlant = _power_system.power_api.grid_manager.get_plant(plant_id)
	if plant == null:
		return

	var was_operational: bool = plant.is_operational()
	plant.apply_damage(damage)

	_log_event("plant_damaged", {
		"plant_id": plant_id,
		"damage": damage,
		"remaining_health": plant.current_health
	})

	plant_damaged.emit(plant, damage, plant.current_health)

	if was_operational and not plant.is_operational():
		on_power_plant_destroyed(plant_id)


## Handle power plant destruction.
func on_power_plant_destroyed(plant_id: int) -> void:
	if _power_system == null:
		return

	var plant: PowerPlant = _power_system.power_api.grid_manager.get_plant(plant_id)
	if plant == null:
		return

	_log_event("plant_destroyed", {
		"plant_id": plant_id,
		"faction_id": plant.faction_id,
		"plant_type": plant.plant_type
	})

	# Get affected districts before network recalculation
	var affected_districts: Array[int] = []
	for line_id in plant.connected_line_ids:
		var line: PowerLine = _power_system.power_api.grid_manager.get_line(line_id)
		if line != null:
			affected_districts.append(line.target_district_id)

	# Emit cascade event
	cascade_event.emit("plant", plant_id, affected_districts)

	# Emit destruction signal
	plant_destroyed.emit(plant)

	# Trigger power flow recalculation
	_power_system.power_api.recalculate()

	# Check for cascading blackouts
	_check_cascading_blackouts(affected_districts)


## Check for cascading blackouts after destruction.
func _check_cascading_blackouts(district_ids: Array[int]) -> void:
	for district_id in district_ids:
		var district: DistrictPowerState = _power_system.power_api.grid_manager.get_district(district_id)
		if district != null and district.is_blackout:
			on_district_blackout(district_id)


# ============================================
# POWER LINE DAMAGE & DESTRUCTION
# ============================================

## Take damage on a power line.
func take_line_damage(line_id: int, damage: float) -> void:
	if _power_system == null:
		return

	var line: PowerLine = _power_system.power_api.grid_manager.get_line(line_id)
	if line == null:
		return

	var was_active: bool = line.is_active()
	line.apply_damage(damage)

	if was_active and not line.is_active():
		on_power_line_destroyed(line_id)


## Handle power line destruction.
func on_power_line_destroyed(line_id: int) -> void:
	if _power_system == null:
		return

	var line: PowerLine = _power_system.power_api.grid_manager.get_line(line_id)
	if line == null:
		return

	var district_id: int = line.target_district_id

	_log_event("line_destroyed", {
		"line_id": line_id,
		"district_id": district_id
	})

	# Emit cascade event
	cascade_event.emit("line", line_id, [district_id])

	# Trigger power flow recalculation
	_power_system.power_api.recalculate()

	# Check for blackout
	var check_district: DistrictPowerState = _power_system.power_api.grid_manager.get_district(district_id)
	if check_district != null and check_district.is_blackout:
		on_district_blackout(district_id)


# ============================================
# DISTRICT BLACKOUT EVENTS
# ============================================

## Handle district blackout.
func on_district_blackout(district_id: int) -> void:
	if _power_system == null:
		return

	var district: DistrictPowerState = _power_system.power_api.grid_manager.get_district(district_id)
	if district == null:
		return

	_log_event("district_blackout", {
		"district_id": district_id,
		"power_ratio": district.get_power_ratio()
	})

	# Set income multiplier
	_district_income_multipliers[district_id] = BLACKOUT_INCOME_MULTIPLIER
	income_multiplier_changed.emit(district_id, BLACKOUT_INCOME_MULTIPLIER)

	# Pause production in factories
	_pause_district_production(district_id)

	# Emit blackout signal
	district_blackout.emit(district)


## Handle district power restoration.
func on_district_power_restored(district_id: int) -> void:
	if _power_system == null:
		return

	var restored_district: DistrictPowerState = _power_system.power_api.grid_manager.get_district(district_id)
	if restored_district == null:
		return

	_log_event("district_power_restored", {
		"district_id": district_id
	})

	# Restore income multiplier
	_district_income_multipliers[district_id] = 1.0
	income_multiplier_changed.emit(district_id, 1.0)

	# Resume production in factories
	_resume_district_production(district_id)

	# Emit restoration signal
	district_power_restored.emit(restored_district)


# ============================================
# PRODUCTION FACILITY INTEGRATION
# ============================================

## Pause production in district factories.
func _pause_district_production(district_id: int) -> void:
	var factory_ids: Array[int] = []

	var consumers := _power_system.consumer_manager.get_district_consumers(district_id)
	for consumer in consumers:
		if consumer.consumer_type == PowerConsumer.ConsumerType.FACTORY:
			factory_ids.append(consumer.consumer_id)

	_paused_factories[district_id] = factory_ids
	production_paused.emit(district_id, factory_ids)


## Resume production in district factories.
func _resume_district_production(district_id: int) -> void:
	var factory_ids: Array = _paused_factories.get(district_id, [])
	_paused_factories.erase(district_id)
	production_resumed.emit(district_id, factory_ids)


## Get income multiplier for district.
func get_district_income_multiplier(district_id: int) -> float:
	return _district_income_multipliers.get(district_id, 1.0)


## Check if district production is paused.
func is_district_production_paused(district_id: int) -> bool:
	return _paused_factories.has(district_id) and not _paused_factories[district_id].is_empty()


## Get paused factory IDs for district.
func get_paused_factories(district_id: int) -> Array:
	return _paused_factories.get(district_id, [])


# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_blackout_alert(district_id: int, severity: int) -> void:
	on_district_blackout(district_id)


func _on_power_restored(district_id: int) -> void:
	on_district_power_restored(district_id)


func _on_infrastructure_damaged(type: String, id: int) -> void:
	_log_event("infrastructure_damaged", {
		"type": type,
		"id": id
	})


# ============================================
# EVENT LOGGING
# ============================================

func _log_event(event_type: String, data: Dictionary) -> void:
	var event := {
		"type": event_type,
		"time": Time.get_ticks_msec() / 1000.0,
		"data": data
	}

	_event_history.append(event)

	# Trim history
	while _event_history.size() > MAX_HISTORY:
		_event_history.pop_front()


## Get recent events.
func get_recent_events(count: int = 10) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := maxi(0, _event_history.size() - count)

	for i in range(start, _event_history.size()):
		result.append(_event_history[i])

	return result


## Get events by type.
func get_events_by_type(event_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for event in _event_history:
		if event["type"] == event_type:
			result.append(event)

	return result


# ============================================
# SERIALIZATION
# ============================================

func to_dict() -> Dictionary:
	return {
		"district_income_multipliers": _district_income_multipliers.duplicate(),
		"paused_factories": _paused_factories.duplicate(true)
	}


func from_dict(data: Dictionary) -> void:
	_district_income_multipliers = data.get("district_income_multipliers", {}).duplicate()
	_paused_factories = data.get("paused_factories", {}).duplicate(true)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var blackout_districts := 0
	var paused_factory_count := 0

	for district_id in _district_income_multipliers:
		if _district_income_multipliers[district_id] < 1.0:
			blackout_districts += 1

	for district_id in _paused_factories:
		paused_factory_count += _paused_factories[district_id].size()

	return {
		"blackout_districts": blackout_districts,
		"paused_factories": paused_factory_count,
		"event_history_size": _event_history.size()
	}
