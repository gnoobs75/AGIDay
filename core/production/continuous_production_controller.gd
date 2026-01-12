class_name ContinuousProductionController
extends RefCounted
## ContinuousProductionController manages ongoing factory-based unit creation.
## Replaces discrete waves with continuous reinforcement production.

signal production_cycle_complete(units_produced: Array)
signal production_started(factory_id: int, unit_type: String)
signal production_completed(factory_id: int, unit_type: String, unit_id: int)
signal production_failed(factory_id: int, reason: String)
signal factory_idle(factory_id: int)

## Factory manager reference
var factory_manager: FactoryManager = null

## Resource manager reference (injected)
var resource_manager = null

## Unit manager reference (injected)
var unit_manager = null

## Production speed multiplier (global)
var global_speed_multiplier: float = 1.0

## Whether production is paused
var is_paused: bool = false

## Production statistics
var stats: Dictionary = {
	"total_units_produced": 0,
	"units_produced_by_type": {},
	"units_produced_by_faction": {},
	"production_time_total": 0.0,
	"failed_productions": 0
}

## Frame budget for production processing (ms)
const FRAME_BUDGET_MS := 2.0


func _init() -> void:
	factory_manager = FactoryManager.new()


## Set resource manager.
func set_resource_manager(manager) -> void:
	resource_manager = manager
	factory_manager.resource_manager = manager


## Set unit manager.
func set_unit_manager(manager) -> void:
	unit_manager = manager
	factory_manager.unit_manager = manager


## Create factory.
func create_factory(
	faction_id: String,
	factory_type: int,
	position: Vector3,
	district_id: int = -1
) -> Factory:
	return factory_manager.create_factory(faction_id, factory_type, position, district_id)


## Queue unit at factory.
func queue_unit(factory_id: int, unit_type: String) -> UnitProduction:
	var factory := factory_manager.get_factory(factory_id)
	if factory == null:
		production_failed.emit(factory_id, "Factory not found")
		return null

	var production := factory.queue_unit(unit_type)
	if production != null:
		production_started.emit(factory_id, unit_type)
	else:
		production_failed.emit(factory_id, "Queue failed for " + unit_type)

	return production


## Queue multiple units.
func queue_units(factory_id: int, unit_type: String, count: int) -> Array[UnitProduction]:
	var productions: Array[UnitProduction] = []

	for i in count:
		var production := queue_unit(factory_id, unit_type)
		if production != null:
			productions.append(production)
		else:
			break  # Stop if queue is full

	return productions


## Cancel production.
func cancel_production(factory_id: int, production_id: int) -> bool:
	return factory_manager.cancel_production(factory_id, production_id)


## Process continuous production (called every frame).
func process(delta: float) -> Array:
	if is_paused:
		return []

	var start_time := Time.get_ticks_usec()
	var effective_delta := delta * global_speed_multiplier

	# Process all factories
	var result := factory_manager.process(effective_delta)

	# Track produced units
	var units_produced: Array = []

	for unit_data in result["units_produced"]:
		var unit_type: String = unit_data["unit_type"]
		var factory_id: int = unit_data["factory_id"]
		var faction_id: String = unit_data["faction_id"]
		var spawn_position: Vector3 = unit_data["position"]

		# Spawn unit
		var unit_id := _spawn_unit(unit_type, faction_id, spawn_position)

		if unit_id >= 0:
			units_produced.append({
				"unit_type": unit_type,
				"unit_id": unit_id,
				"factory_id": factory_id,
				"faction_id": faction_id
			})

			production_completed.emit(factory_id, unit_type, unit_id)
			_update_stats(unit_type, faction_id)
		else:
			stats["failed_productions"] += 1
			production_failed.emit(factory_id, "Unit spawn failed")

	# Track production time
	var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
	stats["production_time_total"] += elapsed

	if not units_produced.is_empty():
		production_cycle_complete.emit(units_produced)

	# Check for idle factories
	_check_idle_factories()

	return units_produced


## Spawn unit via unit manager.
func _spawn_unit(unit_type: String, faction_id: String, position: Vector3) -> int:
	if unit_manager != null and unit_manager.has_method("create_unit"):
		var unit = unit_manager.create_unit(unit_type, faction_id)
		if unit != null:
			if unit.has_method("set_position"):
				unit.set_position(position)
			return unit.id if "id" in unit else 0
	return -1


## Update production statistics.
func _update_stats(unit_type: String, faction_id: String) -> void:
	stats["total_units_produced"] += 1

	if not stats["units_produced_by_type"].has(unit_type):
		stats["units_produced_by_type"][unit_type] = 0
	stats["units_produced_by_type"][unit_type] += 1

	if not stats["units_produced_by_faction"].has(faction_id):
		stats["units_produced_by_faction"][faction_id] = 0
	stats["units_produced_by_faction"][faction_id] += 1


## Check for idle factories.
func _check_idle_factories() -> void:
	for factory in factory_manager.factories.values():
		if factory.is_destroyed:
			continue

		if factory.production_queue.is_empty():
			factory_idle.emit(factory.id)


## Pause production.
func pause() -> void:
	is_paused = true


## Resume production.
func resume() -> void:
	is_paused = false


## Set global speed multiplier.
func set_speed_multiplier(multiplier: float) -> void:
	global_speed_multiplier = clampf(multiplier, 0.1, 10.0)


## Set factory overclock.
func set_factory_overclock(factory_id: int, multiplier: float) -> void:
	factory_manager.set_factory_overclock(factory_id, multiplier)


## Get factory.
func get_factory(factory_id: int) -> Factory:
	return factory_manager.get_factory(factory_id)


## Get factories for faction.
func get_faction_factories(faction_id: String) -> Array[Factory]:
	return factory_manager.get_faction_factories(faction_id)


## Get production queue for factory.
func get_production_queue(factory_id: int) -> ProductionQueue:
	var factory := factory_manager.get_factory(factory_id)
	if factory != null:
		return factory.production_queue
	return null


## Get current production for factory.
func get_current_production(factory_id: int) -> UnitProduction:
	var queue := get_production_queue(factory_id)
	if queue != null:
		return queue.current_production
	return null


## Get total queued units for faction.
func get_faction_queue_size(faction_id: String) -> int:
	return factory_manager.get_faction_queue_size(faction_id)


## Get production statistics.
func get_statistics() -> Dictionary:
	return stats.duplicate(true)


## Reset statistics.
func reset_statistics() -> void:
	stats = {
		"total_units_produced": 0,
		"units_produced_by_type": {},
		"units_produced_by_faction": {},
		"production_time_total": 0.0,
		"failed_productions": 0
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"factory_manager": factory_manager.to_dict(),
		"global_speed_multiplier": global_speed_multiplier,
		"is_paused": is_paused,
		"stats": stats.duplicate(true)
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> ContinuousProductionController:
	var controller := ContinuousProductionController.new()
	controller.factory_manager = FactoryManager.from_dict(data.get("factory_manager", {}))
	controller.global_speed_multiplier = data.get("global_speed_multiplier", 1.0)
	controller.is_paused = data.get("is_paused", false)
	controller.stats = data.get("stats", {}).duplicate(true)
	return controller


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"factories": factory_manager.get_summary(),
		"speed_multiplier": "%.1fx" % global_speed_multiplier,
		"paused": is_paused,
		"total_produced": stats["total_units_produced"],
		"failed": stats["failed_productions"]
	}
