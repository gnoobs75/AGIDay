class_name MassProductionAbility
extends RefCounted
## MassProductionAbility gives OptiForge Legion faster unit spawning.
## Passive ability - production speed increases based on factories controlled.
## More factories = faster production across all factories.

signal production_speed_changed(factory_id: int, multiplier: float)
signal unit_produced_faster(factory_id: int, time_saved: float)

## Configuration
const ABILITY_ID := "mass_production"
const BASE_SPEED_MULTIPLIER := 1.0  ## Normal production speed
const SPEED_PER_FACTORY := 0.15  ## +15% speed per additional factory
const MAX_SPEED_MULTIPLIER := 2.5  ## 250% max production speed (2.5x)
const MIN_FACTORIES_FOR_BONUS := 2  ## Need 2+ factories for bonus

## Factory data (factory_id -> production_data)
var _factory_data: Dictionary = {}

## Current state
var _controlled_factories: int = 0
var _current_multiplier: float = 1.0

## Stats tracking
var _total_time_saved: float = 0.0
var _units_produced: int = 0


func _init() -> void:
	pass


## Register factory for mass production.
func register_factory(factory_id: int) -> void:
	_factory_data[factory_id] = {
		"units_produced": 0,
		"time_saved": 0.0,
		"is_active": true
	}
	_update_multiplier()


## Unregister factory.
func unregister_factory(factory_id: int) -> void:
	_factory_data.erase(factory_id)
	_update_multiplier()


## Set factory active state (e.g., destroyed = inactive).
func set_factory_active(factory_id: int, active: bool) -> void:
	if _factory_data.has(factory_id):
		_factory_data[factory_id]["is_active"] = active
		_update_multiplier()


## Update the production multiplier based on active factories.
func _update_multiplier() -> void:
	_controlled_factories = 0
	for factory_id in _factory_data:
		if _factory_data[factory_id]["is_active"]:
			_controlled_factories += 1

	var old_multiplier: float = _current_multiplier

	if _controlled_factories >= MIN_FACTORIES_FOR_BONUS:
		var bonus_factories: int = _controlled_factories - 1  # First factory is baseline
		_current_multiplier = BASE_SPEED_MULTIPLIER + (bonus_factories * SPEED_PER_FACTORY)
		_current_multiplier = minf(_current_multiplier, MAX_SPEED_MULTIPLIER)
	else:
		_current_multiplier = BASE_SPEED_MULTIPLIER

	# Emit signal if multiplier changed
	if absf(_current_multiplier - old_multiplier) > 0.01:
		for factory_id in _factory_data:
			if _factory_data[factory_id]["is_active"]:
				production_speed_changed.emit(factory_id, _current_multiplier)


## Get production time multiplier (lower = faster).
## Returns value to multiply production time by.
func get_production_time_multiplier() -> float:
	# Invert so higher multiplier = faster (lower time)
	return 1.0 / _current_multiplier


## Get production speed multiplier (higher = faster).
func get_production_speed_multiplier() -> float:
	return _current_multiplier


## Calculate reduced production time.
## Returns the actual time needed for production.
func calculate_production_time(base_time: float) -> float:
	return base_time * get_production_time_multiplier()


## Record a unit being produced (for stats).
func record_production(factory_id: int, base_time: float) -> void:
	var actual_time: float = calculate_production_time(base_time)
	var time_saved: float = base_time - actual_time

	_units_produced += 1
	_total_time_saved += time_saved

	if _factory_data.has(factory_id):
		_factory_data[factory_id]["units_produced"] += 1
		_factory_data[factory_id]["time_saved"] += time_saved

	if time_saved > 0:
		unit_produced_faster.emit(factory_id, time_saved)


## Get number of controlled factories.
func get_controlled_factories() -> int:
	return _controlled_factories


## Get current speed bonus percentage.
func get_speed_bonus_percent() -> float:
	return (_current_multiplier - 1.0) * 100.0


## Check if mass production bonus is active.
func is_bonus_active() -> bool:
	return _controlled_factories >= MIN_FACTORIES_FOR_BONUS


## Get factory stats.
func get_factory_stats(factory_id: int) -> Dictionary:
	if not _factory_data.has(factory_id):
		return {"units_produced": 0, "time_saved": 0.0, "is_active": false}
	return _factory_data[factory_id].duplicate()


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"base_speed_multiplier": BASE_SPEED_MULTIPLIER,
		"speed_per_factory": SPEED_PER_FACTORY,
		"max_speed_multiplier": MAX_SPEED_MULTIPLIER,
		"min_factories_for_bonus": MIN_FACTORIES_FOR_BONUS
	}


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"controlled_factories": _controlled_factories,
		"current_multiplier": _current_multiplier,
		"speed_bonus_percent": get_speed_bonus_percent(),
		"total_time_saved": _total_time_saved,
		"units_produced": _units_produced
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var factory_data_export: Dictionary = {}
	for factory_id in _factory_data:
		factory_data_export[str(factory_id)] = _factory_data[factory_id].duplicate()

	return {
		"factory_data": factory_data_export,
		"controlled_factories": _controlled_factories,
		"current_multiplier": _current_multiplier,
		"total_time_saved": _total_time_saved,
		"units_produced": _units_produced
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_controlled_factories = data.get("controlled_factories", 0)
	_current_multiplier = data.get("current_multiplier", 1.0)
	_total_time_saved = data.get("total_time_saved", 0.0)
	_units_produced = data.get("units_produced", 0)

	_factory_data.clear()
	for factory_id_str in data.get("factory_data", {}):
		_factory_data[int(factory_id_str)] = data["factory_data"][factory_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"factories": _controlled_factories,
		"speed_bonus": "+%.0f%%" % get_speed_bonus_percent() if is_bonus_active() else "None",
		"multiplier": "%.2fx" % _current_multiplier,
		"time_saved": "%.1fs" % _total_time_saved,
		"units_produced": _units_produced
	}
