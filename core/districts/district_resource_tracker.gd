class_name DistrictResourceTracker
extends RefCounted
## DistrictResourceTracker tracks resources per district.
## Manages REE generation, power generation, and power consumption.

signal resources_updated(district_id: int)
signal power_deficit(district_id: int, deficit: float)

## District ID
var district_id: int = -1

## REE generation rate (per second)
var ree_generation_rate: float = 0.0

## Power generation rate (per second)
var power_generation_rate: float = 0.0

## Power consumption rate (per second)
var power_consumption_rate: float = 0.0

## Accumulated REE (not yet collected)
var accumulated_ree: float = 0.0

## Accumulated power (not yet used)
var accumulated_power: float = 0.0

## Building counts affecting resources
var building_counts: Dictionary = {}

## Resource nodes in district
var resource_nodes: Array[int] = []

## Power generators in district
var power_generators: Array[int] = []

## Power consumers in district
var power_consumers: Array[int] = []


func _init(p_district_id: int = -1) -> void:
	district_id = p_district_id


## Add a resource node.
func add_resource_node(node_id: int, ree_rate: float) -> void:
	if node_id not in resource_nodes:
		resource_nodes.append(node_id)
		ree_generation_rate += ree_rate


## Remove a resource node.
func remove_resource_node(node_id: int, ree_rate: float) -> void:
	var idx := resource_nodes.find(node_id)
	if idx >= 0:
		resource_nodes.remove_at(idx)
		ree_generation_rate = maxf(0.0, ree_generation_rate - ree_rate)


## Add a power generator.
func add_power_generator(generator_id: int, power_rate: float) -> void:
	if generator_id not in power_generators:
		power_generators.append(generator_id)
		power_generation_rate += power_rate


## Remove a power generator.
func remove_power_generator(generator_id: int, power_rate: float) -> void:
	var idx := power_generators.find(generator_id)
	if idx >= 0:
		power_generators.remove_at(idx)
		power_generation_rate = maxf(0.0, power_generation_rate - power_rate)


## Add a power consumer.
func add_power_consumer(consumer_id: int, consumption_rate: float) -> void:
	if consumer_id not in power_consumers:
		power_consumers.append(consumer_id)
		power_consumption_rate += consumption_rate


## Remove a power consumer.
func remove_power_consumer(consumer_id: int, consumption_rate: float) -> void:
	var idx := power_consumers.find(consumer_id)
	if idx >= 0:
		power_consumers.remove_at(idx)
		power_consumption_rate = maxf(0.0, power_consumption_rate - consumption_rate)


## Update building count.
func set_building_count(building_type: String, count: int) -> void:
	building_counts[building_type] = count


## Get building count.
func get_building_count(building_type: String) -> int:
	return building_counts.get(building_type, 0)


## Get total building count.
func get_total_buildings() -> int:
	var total := 0
	for count in building_counts.values():
		total += count
	return total


## Process resources for a time delta.
func process(delta: float) -> Dictionary:
	# Generate REE
	var ree_generated := ree_generation_rate * delta
	accumulated_ree += ree_generated

	# Generate and consume power
	var power_generated := power_generation_rate * delta
	var power_consumed := power_consumption_rate * delta

	accumulated_power += power_generated - power_consumed

	# Check for power deficit
	if accumulated_power < 0:
		power_deficit.emit(district_id, -accumulated_power)
		accumulated_power = 0.0

	resources_updated.emit(district_id)

	return {
		"ree_generated": ree_generated,
		"power_generated": power_generated,
		"power_consumed": power_consumed,
		"ree_accumulated": accumulated_ree,
		"power_accumulated": accumulated_power
	}


## Collect accumulated REE.
func collect_ree() -> float:
	var collected := accumulated_ree
	accumulated_ree = 0.0
	return collected


## Get net power rate.
func get_net_power_rate() -> float:
	return power_generation_rate - power_consumption_rate


## Check if district has power surplus.
func has_power_surplus() -> bool:
	return get_net_power_rate() >= 0


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"district_id": district_id,
		"ree_generation_rate": ree_generation_rate,
		"power_generation_rate": power_generation_rate,
		"power_consumption_rate": power_consumption_rate,
		"accumulated_ree": accumulated_ree,
		"accumulated_power": accumulated_power,
		"building_counts": building_counts.duplicate(),
		"resource_nodes": resource_nodes.duplicate(),
		"power_generators": power_generators.duplicate(),
		"power_consumers": power_consumers.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> DistrictResourceTracker:
	var tracker := DistrictResourceTracker.new()
	tracker.district_id = data.get("district_id", -1)
	tracker.ree_generation_rate = data.get("ree_generation_rate", 0.0)
	tracker.power_generation_rate = data.get("power_generation_rate", 0.0)
	tracker.power_consumption_rate = data.get("power_consumption_rate", 0.0)
	tracker.accumulated_ree = data.get("accumulated_ree", 0.0)
	tracker.accumulated_power = data.get("accumulated_power", 0.0)
	tracker.building_counts = data.get("building_counts", {}).duplicate()

	tracker.resource_nodes.clear()
	for id in data.get("resource_nodes", []):
		tracker.resource_nodes.append(int(id))

	tracker.power_generators.clear()
	for id in data.get("power_generators", []):
		tracker.power_generators.append(int(id))

	tracker.power_consumers.clear()
	for id in data.get("power_consumers", []):
		tracker.power_consumers.append(int(id))

	return tracker


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"district_id": district_id,
		"ree_rate": ree_generation_rate,
		"power_gen": power_generation_rate,
		"power_use": power_consumption_rate,
		"net_power": get_net_power_rate(),
		"accumulated_ree": accumulated_ree,
		"buildings": get_total_buildings()
	}
