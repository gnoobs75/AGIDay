class_name PowerNetwork
extends RefCounted
## PowerNetwork manages a connected component of power plants, lines, and districts.
## Handles power flow calculation and distribution.

signal power_flow_updated(network_id: int, total_generation: float, total_demand: float)
signal network_recalculated(network_id: int)
signal plant_added(network_id: int, plant_id: int)
signal plant_removed(network_id: int, plant_id: int)

## Network identity
var network_id: int = -1
var faction_id: String = ""

## Connected components
var plant_ids: Array[int] = []
var line_ids: Array[int] = []
var district_ids: Array[int] = []

## Power state
var total_generation: float = 0.0
var total_demand: float = 0.0
var power_surplus: float = 0.0

## References to actual objects (set by PowerGridManager)
var _plants: Dictionary = {}  # plant_id -> PowerPlant
var _lines: Dictionary = {}   # line_id -> PowerLine
var _districts: Dictionary = {}  # district_id -> DistrictPowerState


func _init() -> void:
	pass


## Initialize network.
func initialize(p_network_id: int, p_faction_id: String) -> void:
	network_id = p_network_id
	faction_id = p_faction_id


## Set object references.
func set_references(plants: Dictionary, lines: Dictionary, districts: Dictionary) -> void:
	_plants = plants
	_lines = lines
	_districts = districts


## Add plant to network.
func add_plant(plant_id: int) -> void:
	if not plant_ids.has(plant_id):
		plant_ids.append(plant_id)
		plant_added.emit(network_id, plant_id)


## Remove plant from network.
func remove_plant(plant_id: int) -> void:
	var idx := plant_ids.find(plant_id)
	if idx != -1:
		plant_ids.remove_at(idx)
		plant_removed.emit(network_id, plant_id)


## Add line to network.
func add_line(line_id: int) -> void:
	if not line_ids.has(line_id):
		line_ids.append(line_id)


## Remove line from network.
func remove_line(line_id: int) -> void:
	var idx := line_ids.find(line_id)
	if idx != -1:
		line_ids.remove_at(idx)


## Add district to network.
func add_district(district_id: int) -> void:
	if not district_ids.has(district_id):
		district_ids.append(district_id)


## Remove district from network.
func remove_district(district_id: int) -> void:
	var idx := district_ids.find(district_id)
	if idx != -1:
		district_ids.remove_at(idx)


## Update power flow - calculates total generation and demand.
func update_power_flow() -> void:
	total_generation = 0.0
	total_demand = 0.0

	# Calculate total generation from active plants
	for plant_id in plant_ids:
		var plant: PowerPlant = _plants.get(plant_id)
		if plant != null and plant.is_operational():
			total_generation += plant.generate_power()

	# Calculate total demand from districts
	for district_id in district_ids:
		var district: DistrictPowerState = _districts.get(district_id)
		if district != null:
			total_demand += district.power_demand

	power_surplus = total_generation - total_demand

	power_flow_updated.emit(network_id, total_generation, total_demand)


## Distribute power proportionally to districts.
func distribute_power() -> void:
	if total_demand <= 0.0:
		# No demand, all districts get 0
		for district_id in district_ids:
			var district: DistrictPowerState = _districts.get(district_id)
			if district != null:
				district.set_current_power(0.0)
		return

	# Calculate power available through active lines
	var available_power := _calculate_deliverable_power()

	# Distribute proportionally based on demand
	for district_id in district_ids:
		var district: DistrictPowerState = _districts.get(district_id)
		if district == null:
			continue

		var demand_ratio := district.power_demand / total_demand
		var allocated_power := available_power * demand_ratio

		# Update power lines to this district
		_update_lines_to_district(district_id, allocated_power)

		# Update district state
		district.set_current_power(allocated_power)


## Calculate total deliverable power through active lines.
func _calculate_deliverable_power() -> float:
	var deliverable := 0.0

	# Count power from plants with active connections
	for plant_id in plant_ids:
		var plant: PowerPlant = _plants.get(plant_id)
		if plant == null or not plant.is_operational():
			continue

		# Check if plant has any active lines
		var has_active_line := false
		for line_id in plant.connected_line_ids:
			var line: PowerLine = _lines.get(line_id)
			if line != null and line.is_active():
				has_active_line = true
				break

		if has_active_line:
			deliverable += plant.current_output

	return minf(deliverable, total_generation)


## Update power flow through lines to a specific district.
func _update_lines_to_district(district_id: int, power: float) -> void:
	var district: DistrictPowerState = _districts.get(district_id)
	if district == null:
		return

	var active_lines: Array[PowerLine] = []

	for line_id in district.connected_line_ids:
		var line: PowerLine = _lines.get(line_id)
		if line != null and line.is_active():
			active_lines.append(line)

	if active_lines.is_empty():
		return

	# Distribute power across lines
	var power_per_line := power / active_lines.size()

	for line in active_lines:
		line.set_power_flow(power_per_line)


## Recalculate network when topology changes.
func recalculate() -> void:
	update_power_flow()
	distribute_power()
	network_recalculated.emit(network_id)


## Check if network is operational.
func is_operational() -> bool:
	# Network is operational if it has at least one working plant
	for plant_id in plant_ids:
		var plant: PowerPlant = _plants.get(plant_id)
		if plant != null and plant.is_operational():
			return true
	return false


## Get power satisfaction ratio.
func get_power_ratio() -> float:
	if total_demand <= 0.0:
		return 1.0
	return minf(total_generation / total_demand, 1.0)


## Check if network has surplus.
func has_surplus() -> bool:
	return power_surplus > 0.0


## Check if network has deficit.
func has_deficit() -> bool:
	return power_surplus < 0.0


## Get list of districts in blackout.
func get_blackout_districts() -> Array[int]:
	var blackouts: Array[int] = []

	for district_id in district_ids:
		var district: DistrictPowerState = _districts.get(district_id)
		if district != null and district.is_blackout:
			blackouts.append(district_id)

	return blackouts


## Merge another network into this one.
func merge(other: PowerNetwork) -> void:
	for plant_id in other.plant_ids:
		add_plant(plant_id)

	for line_id in other.line_ids:
		add_line(line_id)

	for district_id in other.district_ids:
		add_district(district_id)


## Clear all components.
func clear() -> void:
	plant_ids.clear()
	line_ids.clear()
	district_ids.clear()
	total_generation = 0.0
	total_demand = 0.0
	power_surplus = 0.0


## Serialization.
func to_dict() -> Dictionary:
	return {
		"network_id": network_id,
		"faction_id": faction_id,
		"plant_ids": plant_ids.duplicate(),
		"line_ids": line_ids.duplicate(),
		"district_ids": district_ids.duplicate(),
		"total_generation": total_generation,
		"total_demand": total_demand,
		"power_surplus": power_surplus
	}


func from_dict(data: Dictionary) -> void:
	network_id = data.get("network_id", -1)
	faction_id = data.get("faction_id", "")
	total_generation = data.get("total_generation", 0.0)
	total_demand = data.get("total_demand", 0.0)
	power_surplus = data.get("power_surplus", 0.0)

	plant_ids.clear()
	for pid in data.get("plant_ids", []):
		plant_ids.append(int(pid))

	line_ids.clear()
	for lid in data.get("line_ids", []):
		line_ids.append(int(lid))

	district_ids.clear()
	for did in data.get("district_ids", []):
		district_ids.append(int(did))


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"network_id": network_id,
		"faction": faction_id,
		"plants": plant_ids.size(),
		"lines": line_ids.size(),
		"districts": district_ids.size(),
		"generation": total_generation,
		"demand": total_demand,
		"surplus": power_surplus,
		"ratio": get_power_ratio(),
		"is_operational": is_operational(),
		"blackout_count": get_blackout_districts().size()
	}
