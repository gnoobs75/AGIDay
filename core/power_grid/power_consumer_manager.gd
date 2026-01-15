class_name PowerConsumerManager
extends RefCounted
## PowerConsumerManager tracks all power consumers and integrates with the power grid.

signal consumer_registered(consumer_id: int, consumer_type: int)
signal consumer_unregistered(consumer_id: int)
signal faction_consumption_changed(faction_id: String, total_consumption: float)
signal consumer_power_state_changed(consumer_id: int, is_powered: bool)
signal blackout_applied(faction_id: String, affected_count: int)

## All consumers (consumer_id -> PowerConsumer)
var _consumers: Dictionary = {}

## Consumers by faction (faction_id -> Array[int])
var _faction_consumers: Dictionary = {}

## Consumers by type (consumer_type -> Array[int])
var _type_consumers: Dictionary = {}

## Consumers by district (district_id -> Array[int])
var _district_consumers: Dictionary = {}

## Next consumer ID
var _next_consumer_id: int = 1

## Faction consumption cache (faction_id -> total_consumption)
var _faction_consumption: Dictionary = {}

## Reference to power grid API
var _power_api = null  # PowerGridAPI


func _init() -> void:
	# Initialize type arrays
	for consumer_type in PowerConsumer.ConsumerType.values():
		_type_consumers[consumer_type] = []


## Set power grid API reference.
func set_power_api(api) -> void:
	_power_api = api


## Register a factory consumer.
func register_factory(faction_id: String, district_id: int = -1, name: String = "") -> PowerConsumer:
	var consumer := PowerConsumer.new()
	consumer.init_as_factory(_next_consumer_id, faction_id, name)
	consumer.district_id = district_id
	return _register_consumer(consumer)


## Register an infrastructure consumer.
func register_infrastructure(faction_id: String, district_id: int = -1, name: String = "") -> PowerConsumer:
	var consumer := PowerConsumer.new()
	consumer.init_as_infrastructure(_next_consumer_id, faction_id, name)
	consumer.district_id = district_id
	return _register_consumer(consumer)


## Register a defense consumer.
func register_defense(faction_id: String, district_id: int = -1, name: String = "") -> PowerConsumer:
	var consumer := PowerConsumer.new()
	consumer.init_as_defense(_next_consumer_id, faction_id, name)
	consumer.district_id = district_id
	return _register_consumer(consumer)


## Register a research consumer.
func register_research(faction_id: String, district_id: int = -1, name: String = "") -> PowerConsumer:
	var consumer := PowerConsumer.new()
	consumer.init_as_research(_next_consumer_id, faction_id, name)
	consumer.district_id = district_id
	return _register_consumer(consumer)


## Internal registration.
func _register_consumer(consumer: PowerConsumer) -> PowerConsumer:
	_consumers[_next_consumer_id] = consumer
	_next_consumer_id += 1

	# Add to faction list
	if not _faction_consumers.has(consumer.faction_id):
		_faction_consumers[consumer.faction_id] = []
	_faction_consumers[consumer.faction_id].append(consumer.consumer_id)

	# Add to type list
	_type_consumers[consumer.consumer_type].append(consumer.consumer_id)

	# Add to district list
	if consumer.district_id >= 0:
		if not _district_consumers.has(consumer.district_id):
			_district_consumers[consumer.district_id] = []
		_district_consumers[consumer.district_id].append(consumer.consumer_id)

	# Update faction consumption
	_update_faction_consumption(consumer.faction_id)

	consumer_registered.emit(consumer.consumer_id, consumer.consumer_type)

	return consumer


## Unregister a consumer.
func unregister_consumer(consumer_id: int) -> void:
	if not _consumers.has(consumer_id):
		return

	var consumer: PowerConsumer = _consumers[consumer_id]
	var faction_id := consumer.faction_id

	# Remove from faction list
	if _faction_consumers.has(faction_id):
		var idx: int = _faction_consumers[faction_id].find(consumer_id)
		if idx != -1:
			_faction_consumers[faction_id].remove_at(idx)

	# Remove from type list
	var type_list: Array = _type_consumers[consumer.consumer_type]
	var type_idx: int = type_list.find(consumer_id)
	if type_idx != -1:
		type_list.remove_at(type_idx)

	# Remove from district list
	if consumer.district_id >= 0 and _district_consumers.has(consumer.district_id):
		var district_idx: int = _district_consumers[consumer.district_id].find(consumer_id)
		if district_idx != -1:
			_district_consumers[consumer.district_id].remove_at(district_idx)

	_consumers.erase(consumer_id)

	# Update faction consumption
	_update_faction_consumption(faction_id)

	consumer_unregistered.emit(consumer_id)


## Get consumer by ID.
func get_consumer(consumer_id: int) -> PowerConsumer:
	return _consumers.get(consumer_id)


## Get all consumers for faction.
func get_faction_consumers(faction_id: String) -> Array[PowerConsumer]:
	var consumers: Array[PowerConsumer] = []
	if not _faction_consumers.has(faction_id):
		return consumers

	for consumer_id in _faction_consumers[faction_id]:
		var consumer: PowerConsumer = _consumers.get(consumer_id)
		if consumer != null:
			consumers.append(consumer)

	return consumers


## Get all consumers in district.
func get_district_consumers(district_id: int) -> Array[PowerConsumer]:
	var consumers: Array[PowerConsumer] = []
	if not _district_consumers.has(district_id):
		return consumers

	for consumer_id in _district_consumers[district_id]:
		var consumer: PowerConsumer = _consumers.get(consumer_id)
		if consumer != null:
			consumers.append(consumer)

	return consumers


## Get total consumption for faction.
func get_faction_consumption(faction_id: String) -> float:
	return _faction_consumption.get(faction_id, 0.0)


## Update faction consumption total.
func _update_faction_consumption(faction_id: String) -> void:
	var total := 0.0

	for consumer in get_faction_consumers(faction_id):
		total += consumer.power_requirement

	_faction_consumption[faction_id] = total
	faction_consumption_changed.emit(faction_id, total)


## Update all consumers based on power grid state.
func update_from_power_grid() -> void:
	if _power_api == null:
		return

	var factions_affected: Dictionary = {}

	for consumer_id in _consumers:
		var consumer: PowerConsumer = _consumers[consumer_id]

		# Get power state from grid
		var is_blackout := false
		var available_power := 0.0

		if consumer.district_id >= 0:
			is_blackout = _power_api.is_district_in_blackout(consumer.district_id)
			var district_info: Dictionary = _power_api.get_district_info(consumer.district_id)
			available_power = district_info.get("power", 0.0)
		else:
			# Not in a district - check faction-level blackout
			var faction_status: Dictionary = _power_api.get_faction_power_status(consumer.faction_id)
			is_blackout = faction_status.get("has_deficit", false)
			available_power = faction_status.get("generation", 0.0)

		var was_powered := consumer.is_powered
		consumer.update_power_state(available_power, is_blackout)

		if consumer.is_powered != was_powered:
			consumer_power_state_changed.emit(consumer_id, consumer.is_powered)

		if is_blackout:
			if not factions_affected.has(consumer.faction_id):
				factions_affected[consumer.faction_id] = 0
			factions_affected[consumer.faction_id] += 1

	# Emit blackout notifications
	for faction_id in factions_affected:
		blackout_applied.emit(faction_id, factions_affected[faction_id])


## Get production multiplier for a consumer.
func get_production_multiplier(consumer_id: int) -> float:
	var consumer := get_consumer(consumer_id)
	if consumer == null:
		return 1.0
	return consumer.get_production_multiplier()


## Get consumers in blackout for faction.
func get_blackout_consumers(faction_id: String) -> Array[PowerConsumer]:
	var result: Array[PowerConsumer] = []
	for consumer in get_faction_consumers(faction_id):
		if consumer.is_in_blackout:
			result.append(consumer)
	return result


## Get offline consumers for faction.
func get_offline_consumers(faction_id: String) -> Array[PowerConsumer]:
	var result: Array[PowerConsumer] = []
	for consumer in get_faction_consumers(faction_id):
		if consumer.is_offline():
			result.append(consumer)
	return result


## Serialization.
func to_dict() -> Dictionary:
	var consumers_data: Dictionary = {}
	for consumer_id in _consumers:
		consumers_data[str(consumer_id)] = _consumers[consumer_id].to_dict()

	return {
		"consumers": consumers_data,
		"next_consumer_id": _next_consumer_id
	}


func from_dict(data: Dictionary) -> void:
	_consumers.clear()
	_faction_consumers.clear()
	_district_consumers.clear()
	_faction_consumption.clear()

	for consumer_type in PowerConsumer.ConsumerType.values():
		_type_consumers[consumer_type] = []

	_next_consumer_id = data.get("next_consumer_id", 1)

	var consumers_data: Dictionary = data.get("consumers", {})
	for consumer_id_str in consumers_data:
		var consumer := PowerConsumer.new()
		consumer.from_dict(consumers_data[consumer_id_str])

		_consumers[int(consumer_id_str)] = consumer

		# Rebuild indexes
		if not _faction_consumers.has(consumer.faction_id):
			_faction_consumers[consumer.faction_id] = []
		_faction_consumers[consumer.faction_id].append(consumer.consumer_id)

		_type_consumers[consumer.consumer_type].append(consumer.consumer_id)

		if consumer.district_id >= 0:
			if not _district_consumers.has(consumer.district_id):
				_district_consumers[consumer.district_id] = []
			_district_consumers[consumer.district_id].append(consumer.consumer_id)

	# Rebuild consumption cache
	for faction_id in _faction_consumers:
		_update_faction_consumption(faction_id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_counts: Dictionary = {}
	for consumer_type in PowerConsumer.ConsumerType.values():
		var type_name: String
		match consumer_type:
			PowerConsumer.ConsumerType.FACTORY:
				type_name = "factories"
			PowerConsumer.ConsumerType.INFRASTRUCTURE:
				type_name = "infrastructure"
			PowerConsumer.ConsumerType.DEFENSE:
				type_name = "defense"
			PowerConsumer.ConsumerType.RESEARCH:
				type_name = "research"
		type_counts[type_name] = _type_consumers[consumer_type].size()

	var powered_count := 0
	var blackout_count := 0
	var offline_count := 0

	for consumer_id in _consumers:
		var consumer: PowerConsumer = _consumers[consumer_id]
		if consumer.is_offline():
			offline_count += 1
		elif consumer.is_in_blackout:
			blackout_count += 1
		else:
			powered_count += 1

	return {
		"total_consumers": _consumers.size(),
		"by_type": type_counts,
		"powered": powered_count,
		"blackout": blackout_count,
		"offline": offline_count,
		"factions": _faction_consumers.size(),
		"total_consumption": _get_total_consumption()
	}


func _get_total_consumption() -> float:
	var total := 0.0
	for faction_id in _faction_consumption:
		total += _faction_consumption[faction_id]
	return total
