class_name FactoryManager
extends RefCounted
## FactoryManager coordinates all factories and production.
## Integrates with resource and unit management systems.

signal factory_created(factory: Factory)
signal factory_destroyed(factory: Factory)
signal unit_produced(unit_type: String, factory_id: int, faction_id: String)
signal faction_eliminated(faction_id: String)

## All factories (id -> Factory)
var factories: Dictionary = {}

## Factories by faction (faction_id -> Array of factory IDs)
var faction_factories: Dictionary = {}

## Next factory ID
var _next_factory_id: int = 1

## Resource manager reference (injected)
var resource_manager = null

## Unit manager reference (injected)
var unit_manager = null


func _init() -> void:
	pass


## Create a new factory.
func create_factory(
	faction_id: String,
	factory_type: int,
	position: Vector3,
	district_id: int = -1
) -> Factory:
	var factory := Factory.new(factory_type)
	factory.id = _next_factory_id
	_next_factory_id += 1
	factory.faction_id = faction_id
	factory.position = position
	factory.district_id = district_id
	factory.production_queue.faction_id = faction_id
	factory.production_queue.factory_id = factory.id

	# Connect signals
	factory.unit_produced.connect(_on_unit_produced)
	factory.factory_destroyed.connect(_on_factory_destroyed)

	# Register factory
	factories[factory.id] = factory

	if not faction_factories.has(faction_id):
		faction_factories[faction_id] = []
	faction_factories[faction_id].append(factory.id)

	factory_created.emit(factory)
	return factory


## Destroy factory.
func destroy_factory(factory_id: int) -> bool:
	var factory: Factory = factories.get(factory_id)
	if factory == null:
		return false

	factory.is_destroyed = true
	factory.is_operational = false
	factory.production_queue.clear()

	# Remove from faction list
	var faction_list: Array = faction_factories.get(factory.faction_id, [])
	var idx := faction_list.find(factory_id)
	if idx >= 0:
		faction_list.remove_at(idx)

	# Check for faction elimination
	if faction_list.is_empty():
		faction_eliminated.emit(factory.faction_id)

	factory_destroyed.emit(factory)
	return true


## Get factory by ID.
func get_factory(id: int) -> Factory:
	return factories.get(id)


## Get factories for faction.
func get_faction_factories(faction_id: String) -> Array[Factory]:
	var result: Array[Factory] = []
	var ids: Array = faction_factories.get(faction_id, [])

	for factory_id in ids:
		var factory: Factory = factories.get(factory_id)
		if factory != null and not factory.is_destroyed:
			result.append(factory)

	return result


## Get factories by type.
func get_factories_by_type(factory_type: int) -> Array[Factory]:
	var result: Array[Factory] = []
	for factory in factories.values():
		if factory.type == factory_type and not factory.is_destroyed:
			result.append(factory)
	return result


## Get factory at position.
func get_factory_at(position: Vector3, radius: float = 5.0) -> Factory:
	var closest: Factory = null
	var closest_dist := INF

	for factory in factories.values():
		if factory.is_destroyed:
			continue

		var dist := position.distance_to(factory.position)
		if dist < radius and dist < closest_dist:
			closest_dist = dist
			closest = factory

	return closest


## Queue unit at factory.
func queue_unit(factory_id: int, unit_type: String) -> UnitProduction:
	var factory: Factory = factories.get(factory_id)
	if factory == null:
		return null

	return factory.queue_unit(unit_type)


## Cancel production at factory.
func cancel_production(factory_id: int, production_id: int) -> bool:
	var factory: Factory = factories.get(factory_id)
	if factory == null:
		return false

	return factory.cancel_production(production_id)


## Process all factories.
func process(delta: float) -> Dictionary:
	var result := {
		"units_produced": [],
		"total_ree_consumed": 0.0,
		"total_power_consumed": 0.0
	}

	for factory in factories.values():
		if factory.is_destroyed:
			continue

		# Get available resources for faction
		var available_ree := _get_faction_ree(factory.faction_id)
		var available_power := _get_faction_power(factory.faction_id)

		# Process factory
		var factory_result := factory.process(delta, available_ree, available_power)

		# Consume resources
		if factory_result["ree_consumed"] > 0:
			_consume_faction_ree(factory.faction_id, factory_result["ree_consumed"])
			result["total_ree_consumed"] += factory_result["ree_consumed"]

		if factory_result["power_consumed"] > 0:
			_consume_faction_power(factory.faction_id, factory_result["power_consumed"])
			result["total_power_consumed"] += factory_result["power_consumed"]

		# Track produced units
		for unit_type in factory_result["units_produced"]:
			result["units_produced"].append({
				"unit_type": unit_type,
				"factory_id": factory.id,
				"faction_id": factory.faction_id,
				"position": factory.position
			})

	return result


## Get faction REE (from resource manager).
func _get_faction_ree(faction_id: String) -> float:
	if resource_manager != null and resource_manager.has_method("get_faction_ree"):
		return resource_manager.get_faction_ree(faction_id)
	return INF  # Unlimited if no resource manager


## Get faction power (from resource manager).
func _get_faction_power(faction_id: String) -> float:
	if resource_manager != null and resource_manager.has_method("get_faction_power"):
		return resource_manager.get_faction_power(faction_id)
	return INF  # Unlimited if no resource manager


## Consume faction REE.
func _consume_faction_ree(faction_id: String, amount: float) -> void:
	if resource_manager != null and resource_manager.has_method("consume_faction_ree"):
		resource_manager.consume_faction_ree(faction_id, amount)


## Consume faction power.
func _consume_faction_power(faction_id: String, amount: float) -> void:
	if resource_manager != null and resource_manager.has_method("consume_faction_power"):
		resource_manager.consume_faction_power(faction_id, amount)


## Handle unit produced.
func _on_unit_produced(unit_type: String, factory_id: int) -> void:
	var factory: Factory = factories.get(factory_id)
	if factory == null:
		return

	# Spawn unit via unit manager
	if unit_manager != null and unit_manager.has_method("spawn_unit"):
		unit_manager.spawn_unit(unit_type, factory.faction_id, factory.position)

	unit_produced.emit(unit_type, factory_id, factory.faction_id)


## Handle factory destroyed.
func _on_factory_destroyed(factory_id: int) -> void:
	var factory: Factory = factories.get(factory_id)
	if factory != null:
		factory_destroyed.emit(factory)

		# Check faction elimination
		var remaining := get_faction_factories(factory.faction_id)
		if remaining.is_empty():
			faction_eliminated.emit(factory.faction_id)


## Set overclock for factory.
func set_factory_overclock(factory_id: int, multiplier: float) -> void:
	var factory: Factory = factories.get(factory_id)
	if factory != null:
		factory.set_overclock(multiplier)


## Upgrade factory.
func upgrade_factory(factory_id: int) -> bool:
	var factory: Factory = factories.get(factory_id)
	if factory == null:
		return false

	return factory.upgrade()


## Get total production capacity for faction.
func get_faction_production_capacity(faction_id: String) -> int:
	var total := 0
	for factory in get_faction_factories(faction_id):
		total += factory.production_queue.max_queue_size
	return total


## Get total queued units for faction.
func get_faction_queue_size(faction_id: String) -> int:
	var total := 0
	for factory in get_faction_factories(faction_id):
		total += factory.production_queue.get_queue_size()
	return total


## Check if faction has any factories.
func faction_has_factories(faction_id: String) -> bool:
	var factory_list: Array = faction_factories.get(faction_id, [])

	for factory_id in factory_list:
		var factory: Factory = factories.get(factory_id)
		if factory != null and not factory.is_destroyed:
			return true

	return false


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var factories_data: Dictionary = {}
	for id in factories:
		factories_data[str(id)] = factories[id].to_dict()

	return {
		"factories": factories_data,
		"faction_factories": faction_factories.duplicate(true),
		"next_factory_id": _next_factory_id
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> FactoryManager:
	var manager := FactoryManager.new()
	manager._next_factory_id = data.get("next_factory_id", 1)
	manager.faction_factories = data.get("faction_factories", {}).duplicate(true)

	manager.factories.clear()
	for id_str in data.get("factories", {}):
		var factory := Factory.from_dict(data["factories"][id_str])
		manager.factories[int(id_str)] = factory

		# Reconnect signals
		factory.unit_produced.connect(manager._on_unit_produced)
		factory.factory_destroyed.connect(manager._on_factory_destroyed)

	return manager


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_counts: Dictionary = {}
	var total_queue := 0

	for factory in factories.values():
		if not factory.is_destroyed:
			var type_name := factory.get_type_name()
			type_counts[type_name] = type_counts.get(type_name, 0) + 1
			total_queue += factory.production_queue.get_queue_size()

	return {
		"factories": factories.size(),
		"active": factories.values().filter(func(f): return not f.is_destroyed).size(),
		"types": type_counts,
		"total_queue": total_queue,
		"factions": faction_factories.size()
	}
