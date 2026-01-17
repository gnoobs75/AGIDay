class_name PowerGridManager
extends RefCounted
## PowerGridManager orchestrates all power grid components.
## Manages plants, lines, districts, and network topology.

signal plant_registered(plant_id: int)
signal plant_destroyed(plant_id: int)
signal line_registered(line_id: int)
signal line_destroyed(line_id: int)
signal district_registered(district_id: int)
signal blackout_changed(district_id: int, is_blackout: bool)
signal network_topology_changed()

## All power plants (plant_id -> PowerPlant)
var _plants: Dictionary = {}

## All power lines (line_id -> PowerLine)
var _lines: Dictionary = {}

## All districts (district_id -> DistrictPowerState)
var _districts: Dictionary = {}

## All networks (network_id -> PowerNetwork)
var _networks: Dictionary = {}

## Next IDs
var _next_plant_id: int = 1
var _next_line_id: int = 1
var _next_district_id: int = 1
var _next_network_id: int = 1

## Daylight state for solar plants
var _daylight_multiplier: float = 1.0

## Pending recalculation
var _needs_recalculation: bool = false


func _init() -> void:
	pass


## Create solar power plant.
func create_solar_plant(faction_id: String, position: Vector3) -> PowerPlant:
	var plant := PowerPlant.new()
	plant.init_as_solar(_next_plant_id, faction_id, position)
	plant.set_daylight_multiplier(_daylight_multiplier)

	_plants[_next_plant_id] = plant
	_next_plant_id += 1

	# Connect signals
	plant.plant_destroyed.connect(_on_plant_destroyed)
	plant.plant_repaired.connect(_on_plant_repaired)

	_needs_recalculation = true
	plant_registered.emit(plant.id)

	return plant


## Create fusion power plant.
func create_fusion_plant(faction_id: String, position: Vector3) -> PowerPlant:
	var plant := PowerPlant.new()
	plant.init_as_fusion(_next_plant_id, faction_id, position)

	_plants[_next_plant_id] = plant
	_next_plant_id += 1

	# Connect signals
	plant.plant_destroyed.connect(_on_plant_destroyed)
	plant.plant_repaired.connect(_on_plant_repaired)

	_needs_recalculation = true
	plant_registered.emit(plant.id)

	return plant


## Create power line.
func create_power_line(source_plant_id: int, target_district_id: int, capacity: float = 100.0) -> PowerLine:
	var plant := get_plant(source_plant_id)
	var district := get_district(target_district_id)

	if plant == null or district == null:
		return null

	var line := PowerLine.new()
	line.initialize(_next_line_id, source_plant_id, target_district_id, capacity)
	line.set_positions(plant.position, Vector3.ZERO)  # District position would come from game

	_lines[_next_line_id] = line
	_next_line_id += 1

	# Update connections
	plant.add_connected_line(line.id)
	district.add_connected_line(line.id)

	# Connect signals
	line.line_destroyed.connect(_on_line_destroyed)
	line.line_repaired.connect(_on_line_repaired)

	_needs_recalculation = true
	line_registered.emit(line.id)

	return line


## Create district.
func create_district(faction_id: String, power_demand: float = 100.0) -> DistrictPowerState:
	var district := DistrictPowerState.new()
	district.initialize(_next_district_id, faction_id, power_demand)

	_districts[_next_district_id] = district
	_next_district_id += 1

	# Connect signals
	district.blackout_started.connect(_on_blackout_started)
	district.blackout_ended.connect(_on_blackout_ended)

	_needs_recalculation = true
	district_registered.emit(district.district_id)

	return district


## Get plant by ID.
func get_plant(plant_id: int) -> PowerPlant:
	return _plants.get(plant_id)


## Get line by ID.
func get_line(line_id: int) -> PowerLine:
	return _lines.get(line_id)


## Get district by ID.
func get_district(district_id: int) -> DistrictPowerState:
	return _districts.get(district_id)


## Get network by ID.
func get_network(network_id: int) -> PowerNetwork:
	return _networks.get(network_id)


## Get all plants dictionary (for UI display).
func get_all_plants() -> Dictionary:
	return _plants


## Get all lines dictionary (for UI display).
func get_all_lines() -> Dictionary:
	return _lines


## Get all districts dictionary (for UI display).
func get_all_districts() -> Dictionary:
	return _districts


## Set daylight multiplier for all solar plants.
func set_daylight_multiplier(multiplier: float) -> void:
	_daylight_multiplier = clampf(multiplier, 0.0, 1.0)

	for plant_id in _plants:
		var plant: PowerPlant = _plants[plant_id]
		if plant.plant_type == PowerPlant.PlantType.SOLAR:
			plant.set_daylight_multiplier(_daylight_multiplier)

	_needs_recalculation = true


## Update all networks.
func update(delta: float) -> void:
	# Update blackout timers
	for district_id in _districts:
		var district: DistrictPowerState = _districts[district_id]
		district.update_time(delta)

	# Recalculate if needed
	if _needs_recalculation:
		_recalculate_networks()
		_needs_recalculation = false


## Force immediate recalculation.
func force_recalculation() -> void:
	_recalculate_networks()
	_needs_recalculation = false


## Recalculate all network components and power flow.
func _recalculate_networks() -> void:
	# Clear existing networks
	_networks.clear()
	_next_network_id = 1

	# Build networks from connected components
	var visited_plants: Dictionary = {}

	for plant_id in _plants:
		if visited_plants.has(plant_id):
			continue

		var plant: PowerPlant = _plants[plant_id]
		if plant.is_destroyed:
			continue

		# Create new network for this connected component
		var network := PowerNetwork.new()
		network.initialize(_next_network_id, plant.faction_id)
		network.set_references(_plants, _lines, _districts)

		# BFS to find all connected components
		_build_network_component(network, plant_id, visited_plants)

		if not network.plant_ids.is_empty():
			_networks[_next_network_id] = network
			_next_network_id += 1

			# Assign network ID to plants
			for pid in network.plant_ids:
				var p: PowerPlant = _plants.get(pid)
				if p != null:
					p.network_id = network.network_id

	# Update power flow for all networks
	for network_id in _networks:
		var network: PowerNetwork = _networks[network_id]
		network.recalculate()

	network_topology_changed.emit()


## Build network component using BFS.
func _build_network_component(network: PowerNetwork, start_plant_id: int, visited: Dictionary) -> void:
	var queue: Array[int] = [start_plant_id]

	while not queue.is_empty():
		var plant_id: int = queue.pop_front()

		if visited.has(plant_id):
			continue

		var plant: PowerPlant = _plants.get(plant_id)
		if plant == null or plant.is_destroyed:
			continue

		visited[plant_id] = true
		network.add_plant(plant_id)

		# Follow power lines to districts
		for line_id in plant.connected_line_ids:
			var line: PowerLine = _lines.get(line_id)
			if line == null or not line.is_active():
				continue

			network.add_line(line_id)

			# Add connected district
			var district_id := line.target_district_id
			if not network.district_ids.has(district_id):
				network.add_district(district_id)


## Handle plant destruction.
func _on_plant_destroyed(plant_id: int) -> void:
	_needs_recalculation = true
	plant_destroyed.emit(plant_id)


## Handle plant repair.
func _on_plant_repaired(plant_id: int) -> void:
	_needs_recalculation = true


## Handle line destruction.
func _on_line_destroyed(line_id: int) -> void:
	_needs_recalculation = true
	line_destroyed.emit(line_id)


## Handle line repair.
func _on_line_repaired(line_id: int) -> void:
	_needs_recalculation = true


## Handle blackout start.
func _on_blackout_started(district_id: int) -> void:
	blackout_changed.emit(district_id, true)


## Handle blackout end.
func _on_blackout_ended(district_id: int) -> void:
	blackout_changed.emit(district_id, false)


## Destroy a plant.
func destroy_plant(plant_id: int) -> void:
	var plant := get_plant(plant_id)
	if plant != null:
		plant.apply_damage(plant.max_health)


## Destroy a line.
func destroy_line(line_id: int) -> void:
	var line := get_line(line_id)
	if line != null:
		line.apply_damage(line.max_health)


## Get all plants for faction.
func get_faction_plants(faction_id: String) -> Array[PowerPlant]:
	var plants: Array[PowerPlant] = []
	for plant_id in _plants:
		var plant: PowerPlant = _plants[plant_id]
		if plant.faction_id == faction_id:
			plants.append(plant)
	return plants


## Get all districts for faction.
func get_faction_districts(faction_id: String) -> Array[DistrictPowerState]:
	var districts: Array[DistrictPowerState] = []
	for district_id in _districts:
		var district: DistrictPowerState = _districts[district_id]
		if district.controlling_faction == faction_id:
			districts.append(district)
	return districts


## Get total power generation for faction.
func get_faction_generation(faction_id: String) -> float:
	var total := 0.0
	for plant in get_faction_plants(faction_id):
		if plant.is_operational():
			total += plant.current_output
	return total


## Get total power demand for faction.
func get_faction_demand(faction_id: String) -> float:
	var total := 0.0
	for district in get_faction_districts(faction_id):
		total += district.power_demand
	return total


## Get blackout districts for faction.
func get_faction_blackouts(faction_id: String) -> Array[DistrictPowerState]:
	var blackouts: Array[DistrictPowerState] = []
	for district in get_faction_districts(faction_id):
		if district.is_blackout:
			blackouts.append(district)
	return blackouts


## Serialization.
func to_dict() -> Dictionary:
	var plants_data: Dictionary = {}
	for plant_id in _plants:
		plants_data[str(plant_id)] = _plants[plant_id].to_dict()

	var lines_data: Dictionary = {}
	for line_id in _lines:
		lines_data[str(line_id)] = _lines[line_id].to_dict()

	var districts_data: Dictionary = {}
	for district_id in _districts:
		districts_data[str(district_id)] = _districts[district_id].to_dict()

	return {
		"plants": plants_data,
		"lines": lines_data,
		"districts": districts_data,
		"next_plant_id": _next_plant_id,
		"next_line_id": _next_line_id,
		"next_district_id": _next_district_id,
		"daylight_multiplier": _daylight_multiplier
	}


func from_dict(data: Dictionary) -> void:
	_plants.clear()
	_lines.clear()
	_districts.clear()
	_networks.clear()

	_next_plant_id = data.get("next_plant_id", 1)
	_next_line_id = data.get("next_line_id", 1)
	_next_district_id = data.get("next_district_id", 1)
	_daylight_multiplier = data.get("daylight_multiplier", 1.0)

	# Load plants
	var plants_data: Dictionary = data.get("plants", {})
	for plant_id_str in plants_data:
		var plant := PowerPlant.new()
		plant.from_dict(plants_data[plant_id_str])
		_plants[int(plant_id_str)] = plant
		plant.plant_destroyed.connect(_on_plant_destroyed)
		plant.plant_repaired.connect(_on_plant_repaired)

	# Load lines
	var lines_data: Dictionary = data.get("lines", {})
	for line_id_str in lines_data:
		var line := PowerLine.new()
		line.from_dict(lines_data[line_id_str])
		_lines[int(line_id_str)] = line
		line.line_destroyed.connect(_on_line_destroyed)
		line.line_repaired.connect(_on_line_repaired)

	# Load districts
	var districts_data: Dictionary = data.get("districts", {})
	for district_id_str in districts_data:
		var district := DistrictPowerState.new()
		district.from_dict(districts_data[district_id_str])
		_districts[int(district_id_str)] = district
		district.blackout_started.connect(_on_blackout_started)
		district.blackout_ended.connect(_on_blackout_ended)

	_needs_recalculation = true


## Get summary for debugging.
func get_summary() -> Dictionary:
	var operational_plants := 0
	var destroyed_plants := 0
	var total_generation := 0.0

	for plant_id in _plants:
		var plant: PowerPlant = _plants[plant_id]
		if plant.is_operational():
			operational_plants += 1
			total_generation += plant.current_output
		else:
			destroyed_plants += 1

	var active_lines := 0
	var destroyed_lines := 0
	for line_id in _lines:
		var line: PowerLine = _lines[line_id]
		if line.is_active():
			active_lines += 1
		else:
			destroyed_lines += 1

	var powered_districts := 0
	var blackout_districts := 0
	var total_demand := 0.0
	for district_id in _districts:
		var district: DistrictPowerState = _districts[district_id]
		total_demand += district.power_demand
		if district.is_blackout:
			blackout_districts += 1
		else:
			powered_districts += 1

	return {
		"plants": {
			"total": _plants.size(),
			"operational": operational_plants,
			"destroyed": destroyed_plants
		},
		"lines": {
			"total": _lines.size(),
			"active": active_lines,
			"destroyed": destroyed_lines
		},
		"districts": {
			"total": _districts.size(),
			"powered": powered_districts,
			"blackout": blackout_districts
		},
		"networks": _networks.size(),
		"total_generation": total_generation,
		"total_demand": total_demand,
		"daylight": _daylight_multiplier
	}
