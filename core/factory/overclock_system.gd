class_name OverclockSystem
extends RefCounted
## OverclockSystem manages overclock states for all factories.

signal factory_heat_changed(factory_id: int, heat_level: float)
signal factory_overclock_changed(factory_id: int, multiplier: float)
signal factory_meltdown_started(factory_id: int)
signal factory_meltdown_recovered(factory_id: int)
signal system_updated()

## Update frequency
const HEAT_UPDATE_INTERVAL := 0.1  ## Seconds between heat updates

## Factory limits
const MAX_FACTORIES := 100

## Factory overclock states
var _factory_overclocks: Dictionary = {}  ## factory_id -> FactoryOverclock

## Update timing
var _time_since_update: float = 0.0

## Performance tracking
var _last_update_time_us: int = 0


func _init() -> void:
	pass


## Register a factory.
func register_factory(factory_id: int) -> FactoryOverclock:
	if _factory_overclocks.size() >= MAX_FACTORIES:
		push_warning("Maximum factories reached for overclock system")
		return null

	if _factory_overclocks.has(factory_id):
		return _factory_overclocks[factory_id]

	var overclock := FactoryOverclock.new()
	overclock.initialize(factory_id)

	# Connect signals
	overclock.heat_changed.connect(_on_heat_changed)
	overclock.overclock_changed.connect(_on_overclock_changed)
	overclock.meltdown_started.connect(_on_meltdown_started)
	overclock.meltdown_recovered.connect(_on_meltdown_recovered)

	_factory_overclocks[factory_id] = overclock

	return overclock


## Unregister a factory.
func unregister_factory(factory_id: int) -> void:
	if not _factory_overclocks.has(factory_id):
		return

	var overclock: FactoryOverclock = _factory_overclocks[factory_id]

	# Disconnect signals
	if overclock.heat_changed.is_connected(_on_heat_changed):
		overclock.heat_changed.disconnect(_on_heat_changed)
	if overclock.overclock_changed.is_connected(_on_overclock_changed):
		overclock.overclock_changed.disconnect(_on_overclock_changed)
	if overclock.meltdown_started.is_connected(_on_meltdown_started):
		overclock.meltdown_started.disconnect(_on_meltdown_started)
	if overclock.meltdown_recovered.is_connected(_on_meltdown_recovered):
		overclock.meltdown_recovered.disconnect(_on_meltdown_recovered)

	_factory_overclocks.erase(factory_id)


## Get factory overclock state.
func get_factory_overclock(factory_id: int) -> FactoryOverclock:
	return _factory_overclocks.get(factory_id)


## Set overclock level for a factory.
func set_overclock(factory_id: int, level: float) -> void:
	if _factory_overclocks.has(factory_id):
		_factory_overclocks[factory_id].set_overclock(level)


## Get overclock level for a factory.
func get_overclock(factory_id: int) -> float:
	if _factory_overclocks.has(factory_id):
		return _factory_overclocks[factory_id].overclock_level
	return 1.0


## Get heat level for a factory.
func get_heat(factory_id: int) -> float:
	if _factory_overclocks.has(factory_id):
		return _factory_overclocks[factory_id].heat_level
	return 0.0


## Check if factory is in meltdown.
func is_meltdown(factory_id: int) -> bool:
	if _factory_overclocks.has(factory_id):
		return _factory_overclocks[factory_id].is_meltdown
	return false


## Check if factory can produce.
func can_produce(factory_id: int) -> bool:
	if _factory_overclocks.has(factory_id):
		return _factory_overclocks[factory_id].can_produce()
	return true


## Update all factory heat levels (call each frame).
func update(delta: float) -> void:
	_time_since_update += delta

	if _time_since_update < HEAT_UPDATE_INTERVAL:
		return

	var start_time := Time.get_ticks_usec()

	# Batch update all factories
	var batch_delta := _time_since_update
	_time_since_update = 0.0

	for factory_id in _factory_overclocks:
		var overclock: FactoryOverclock = _factory_overclocks[factory_id]
		overclock.update_heat(batch_delta)

	_last_update_time_us = Time.get_ticks_usec() - start_time

	system_updated.emit()


## Force update all factories immediately.
func force_update() -> void:
	var delta := _time_since_update if _time_since_update > 0 else HEAT_UPDATE_INTERVAL
	_time_since_update = HEAT_UPDATE_INTERVAL
	update(0.0)


## Signal handlers.
func _on_heat_changed(factory_id: int, heat_level: float) -> void:
	factory_heat_changed.emit(factory_id, heat_level)


func _on_overclock_changed(factory_id: int, multiplier: float) -> void:
	factory_overclock_changed.emit(factory_id, multiplier)


func _on_meltdown_started(factory_id: int) -> void:
	factory_meltdown_started.emit(factory_id)


func _on_meltdown_recovered(factory_id: int) -> void:
	factory_meltdown_recovered.emit(factory_id)


## Get all factory IDs.
func get_all_factory_ids() -> Array[int]:
	var ids: Array[int] = []
	for factory_id in _factory_overclocks:
		ids.append(factory_id)
	return ids


## Get all factories in meltdown.
func get_meltdown_factories() -> Array[int]:
	var ids: Array[int] = []
	for factory_id in _factory_overclocks:
		if _factory_overclocks[factory_id].is_meltdown:
			ids.append(factory_id)
	return ids


## Get all factories with high heat (> 0.8).
func get_high_heat_factories() -> Array[int]:
	var ids: Array[int] = []
	for factory_id in _factory_overclocks:
		if _factory_overclocks[factory_id].heat_level > 0.8:
			ids.append(factory_id)
	return ids


## Get factory count.
func get_factory_count() -> int:
	return _factory_overclocks.size()


## Get last update time in microseconds.
func get_last_update_time_us() -> int:
	return _last_update_time_us


## Check if update is within performance budget.
func is_within_performance_budget() -> bool:
	# Budget: 0.1ms = 100 microseconds
	return _last_update_time_us < 100


## Reset all factories.
func reset_all() -> void:
	for factory_id in _factory_overclocks:
		_factory_overclocks[factory_id].reset()


## Clear all factories.
func clear() -> void:
	for factory_id in _factory_overclocks.keys():
		unregister_factory(factory_id)


## Serialization.
func to_dict() -> Dictionary:
	var factory_data: Dictionary = {}
	for factory_id in _factory_overclocks:
		factory_data[str(factory_id)] = _factory_overclocks[factory_id].to_dict()

	return {
		"factories": factory_data
	}


func from_dict(data: Dictionary) -> void:
	clear()

	var factory_data: Dictionary = data.get("factories", {})
	for factory_id_str in factory_data:
		var factory_id := int(factory_id_str)
		var overclock := register_factory(factory_id)
		if overclock != null:
			overclock.from_dict(factory_data[factory_id_str])


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_heat := 0.0
	var meltdown_count := 0
	var overclocked_count := 0

	for factory_id in _factory_overclocks:
		var overclock: FactoryOverclock = _factory_overclocks[factory_id]
		total_heat += overclock.heat_level
		if overclock.is_meltdown:
			meltdown_count += 1
		if overclock.overclock_level > 1.0:
			overclocked_count += 1

	var avg_heat := total_heat / _factory_overclocks.size() if not _factory_overclocks.is_empty() else 0.0

	return {
		"factory_count": _factory_overclocks.size(),
		"average_heat": avg_heat,
		"meltdown_count": meltdown_count,
		"overclocked_count": overclocked_count,
		"last_update_us": _last_update_time_us,
		"within_budget": is_within_performance_budget()
	}
