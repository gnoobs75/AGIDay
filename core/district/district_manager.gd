class_name DistrictManager
extends RefCounted
## DistrictManager handles all district control and resource generation.

signal district_created(district_id: int)
signal district_captured(district_id: int, old_faction: String, new_faction: String)
signal resource_node_created(node_id: int)
signal income_collected(faction_id: String, ree: float, power: float)
signal power_distributed(faction_id: String, districts_powered: int, districts_unpowered: int)

## Corner power plant configuration
const CORNER_POWER_OUTPUT := 1000.0
const CORNER_POWER_RANGE := 200.0

## Districts (district_id -> District)
var _districts: Dictionary = {}

## Resource nodes (node_id -> ResourceNode)
var _resource_nodes: Dictionary = {}

## Districts by faction (faction_id -> Array[int])
var _faction_districts: Dictionary = {}

## Resource nodes by district (district_id -> Array[int])
var _district_nodes: Dictionary = {}

## Next IDs
var _next_district_id: int = 1
var _next_node_id: int = 1

## City bounds
var _city_min: Vector3i = Vector3i.ZERO
var _city_max: Vector3i = Vector3i(512, 64, 512)


func _init() -> void:
	pass


## Set city bounds.
func set_city_bounds(min_bounds: Vector3i, max_bounds: Vector3i) -> void:
	_city_min = min_bounds
	_city_max = max_bounds


## Create district.
func create_district(name: String, district_type: int, min_bounds: Vector3i, max_bounds: Vector3i, faction_id: String = "") -> District:
	var district := District.new()
	district.initialize(_next_district_id, name, district_type, min_bounds, max_bounds)

	if not faction_id.is_empty():
		district.set_owning_faction(faction_id)

	_districts[_next_district_id] = district
	_next_district_id += 1

	# Add to faction map
	if not faction_id.is_empty():
		if not _faction_districts.has(faction_id):
			_faction_districts[faction_id] = []
		_faction_districts[faction_id].append(district.district_id)

	# Connect signals
	district.ownership_changed.connect(_on_ownership_changed)
	district.district_captured.connect(_on_district_captured)

	district_created.emit(district.district_id)

	return district


## Create corner district with power plant.
func create_corner_district(name: String, corner: int, faction_id: String = "") -> District:
	var district_size := District.DISTRICT_SIZE
	var min_bounds: Vector3i
	var max_bounds: Vector3i

	match corner:
		0:  # Top-left
			min_bounds = _city_min
			max_bounds = _city_min + Vector3i(district_size, 64, district_size)
		1:  # Top-right
			min_bounds = Vector3i(_city_max.x - district_size, _city_min.y, _city_min.z)
			max_bounds = Vector3i(_city_max.x, _city_max.y, _city_min.z + district_size)
		2:  # Bottom-left
			min_bounds = Vector3i(_city_min.x, _city_min.y, _city_max.z - district_size)
			max_bounds = Vector3i(_city_min.x + district_size, _city_max.y, _city_max.z)
		3:  # Bottom-right
			min_bounds = Vector3i(_city_max.x - district_size, _city_min.y, _city_max.z - district_size)
			max_bounds = _city_max

	var district := create_district(name, District.DistrictType.CORNER, min_bounds, max_bounds, faction_id)
	district.power_generation_rate = CORNER_POWER_OUTPUT

	return district


## Create edge district with resource node.
func create_edge_district(name: String, edge_position: Vector3i, faction_id: String = "") -> District:
	var district_size := District.DISTRICT_SIZE
	var min_bounds := edge_position
	var max_bounds := edge_position + Vector3i(district_size, 64, district_size)

	var district := create_district(name, District.DistrictType.EDGE, min_bounds, max_bounds, faction_id)

	# Create REE resource node
	var node_pos := Vector3(district.center_position.x, 0.0, district.center_position.z)
	create_ree_node(district.district_id, node_pos, 10.0, faction_id)

	return district


## Create REE resource node.
func create_ree_node(district_id: int, position: Vector3, rate: float = 10.0, faction_id: String = "") -> ResourceNode:
	var node := ResourceNode.new()
	node.init_as_ree(_next_node_id, district_id, position, rate)
	node.set_owning_faction(faction_id)

	_resource_nodes[_next_node_id] = node
	_next_node_id += 1

	# Add to district map
	if not _district_nodes.has(district_id):
		_district_nodes[district_id] = []
	_district_nodes[district_id].append(node.node_id)

	resource_node_created.emit(node.node_id)

	return node


## Create power resource node.
func create_power_node(district_id: int, position: Vector3, rate: float = 50.0, faction_id: String = "") -> ResourceNode:
	var node := ResourceNode.new()
	node.init_as_power(_next_node_id, district_id, position, rate)
	node.set_owning_faction(faction_id)

	_resource_nodes[_next_node_id] = node
	_next_node_id += 1

	# Add to district map
	if not _district_nodes.has(district_id):
		_district_nodes[district_id] = []
	_district_nodes[district_id].append(node.node_id)

	resource_node_created.emit(node.node_id)

	return node


## Get district by ID.
func get_district(district_id: int) -> District:
	return _districts.get(district_id)


## Get resource node by ID.
func get_resource_node(node_id: int) -> ResourceNode:
	return _resource_nodes.get(node_id)


## Get district at position.
func get_district_at_position(position: Vector3) -> District:
	for district_id in _districts:
		var district: District = _districts[district_id]
		if district.contains_position(position):
			return district
	return null


## Get districts for faction.
func get_faction_districts(faction_id: String) -> Array[District]:
	var districts: Array[District] = []

	if not _faction_districts.has(faction_id):
		return districts

	for district_id in _faction_districts[faction_id]:
		var district: District = _districts.get(district_id)
		if district != null:
			districts.append(district)

	return districts


## Get resource nodes for district.
func get_district_resource_nodes(district_id: int) -> Array[ResourceNode]:
	var nodes: Array[ResourceNode] = []

	if not _district_nodes.has(district_id):
		return nodes

	for node_id in _district_nodes[district_id]:
		var node: ResourceNode = _resource_nodes.get(node_id)
		if node != null:
			nodes.append(node)

	return nodes


## Capture district.
func capture_district(district_id: int, capturing_faction: String) -> void:
	var district := get_district(district_id)
	if district == null:
		return

	var old_faction := district.owning_faction

	# Remove from old faction list
	if _faction_districts.has(old_faction):
		var idx := _faction_districts[old_faction].find(district_id)
		if idx != -1:
			_faction_districts[old_faction].remove_at(idx)

	# Add to new faction list
	if not _faction_districts.has(capturing_faction):
		_faction_districts[capturing_faction] = []
	_faction_districts[capturing_faction].append(district_id)

	# Update district and its resource nodes
	district.capture(capturing_faction)

	for node in get_district_resource_nodes(district_id):
		node.set_owning_faction(capturing_faction)


## Update power distribution.
func distribute_power(faction_id: String, available_power: float) -> void:
	var districts := get_faction_districts(faction_id)
	if districts.is_empty():
		return

	# Calculate total demand
	var total_demand := 0.0
	for district in districts:
		total_demand += district.power_consumption

	# Distribute proportionally
	var powered := 0
	var unpowered := 0

	for district in districts:
		var ratio := district.power_consumption / total_demand if total_demand > 0 else 0.0
		var allocated := available_power * ratio

		var has_enough := allocated >= district.power_consumption * 0.5
		district.set_power_state(has_enough, allocated)

		if has_enough:
			powered += 1
		else:
			unpowered += 1

	power_distributed.emit(faction_id, powered, unpowered)


## Generate income for all factions (call each frame).
func generate_income(delta: float) -> Dictionary:
	var faction_income: Dictionary = {}

	for district_id in _districts:
		var district: District = _districts[district_id]
		if district.owning_faction.is_empty():
			continue

		var faction := district.owning_faction
		if not faction_income.has(faction):
			faction_income[faction] = {"ree": 0.0, "power": 0.0}

		# Generate from district
		var multiplier := district.get_income_multiplier()
		var district_income := district.generate_income(delta)
		faction_income[faction]["ree"] += district_income["ree"] * multiplier
		faction_income[faction]["power"] += district_income["power"] * multiplier

		# Generate from resource nodes
		for node in get_district_resource_nodes(district_id):
			var amount := node.generate(delta) * multiplier
			if node.resource_type == ResourceNode.ResourceType.REE:
				faction_income[faction]["ree"] += amount
			else:
				faction_income[faction]["power"] += amount

	# Emit income events
	for faction_id in faction_income:
		var income: Dictionary = faction_income[faction_id]
		if income["ree"] > 0.0 or income["power"] > 0.0:
			income_collected.emit(faction_id, income["ree"], income["power"])

	return faction_income


## Update unit counts for districts.
func update_district_units(district_id: int, faction_id: String, unit_delta: int) -> void:
	var district := get_district(district_id)
	if district == null:
		return

	if faction_id == district.owning_faction:
		district.friendly_unit_count = maxi(0, district.friendly_unit_count + unit_delta)
	else:
		district.enemy_unit_count = maxi(0, district.enemy_unit_count + unit_delta)

	district.update_unit_counts(district.friendly_unit_count, district.enemy_unit_count)


## Get total income rate for faction.
func get_faction_income_rate(faction_id: String) -> Dictionary:
	var total := {"ree": 0.0, "power": 0.0}

	for district in get_faction_districts(faction_id):
		var multiplier := district.get_income_multiplier()
		total["ree"] += district.ree_generation_rate * multiplier
		total["power"] += district.power_generation_rate * multiplier

		for node in get_district_resource_nodes(district.district_id):
			if node.is_producing():
				if node.resource_type == ResourceNode.ResourceType.REE:
					total["ree"] += node.current_rate * multiplier
				else:
					total["power"] += node.current_rate * multiplier

	return total


## Signal handlers.
func _on_ownership_changed(district_id: int, old_faction: String, new_faction: String) -> void:
	# Update faction maps
	if _faction_districts.has(old_faction):
		var idx := _faction_districts[old_faction].find(district_id)
		if idx != -1:
			_faction_districts[old_faction].remove_at(idx)

	if not new_faction.is_empty():
		if not _faction_districts.has(new_faction):
			_faction_districts[new_faction] = []
		if not _faction_districts[new_faction].has(district_id):
			_faction_districts[new_faction].append(district_id)


func _on_district_captured(district_id: int, capturing_faction: String) -> void:
	var district := get_district(district_id)
	if district != null:
		district_captured.emit(district_id, "", capturing_faction)


## Serialization.
func to_dict() -> Dictionary:
	var districts_data: Dictionary = {}
	for district_id in _districts:
		districts_data[str(district_id)] = _districts[district_id].to_dict()

	var nodes_data: Dictionary = {}
	for node_id in _resource_nodes:
		nodes_data[str(node_id)] = _resource_nodes[node_id].to_dict()

	return {
		"districts": districts_data,
		"resource_nodes": nodes_data,
		"next_district_id": _next_district_id,
		"next_node_id": _next_node_id,
		"city_min": {"x": _city_min.x, "y": _city_min.y, "z": _city_min.z},
		"city_max": {"x": _city_max.x, "y": _city_max.y, "z": _city_max.z}
	}


func from_dict(data: Dictionary) -> void:
	_districts.clear()
	_resource_nodes.clear()
	_faction_districts.clear()
	_district_nodes.clear()

	_next_district_id = data.get("next_district_id", 1)
	_next_node_id = data.get("next_node_id", 1)

	var cmin: Dictionary = data.get("city_min", {})
	_city_min = Vector3i(cmin.get("x", 0), cmin.get("y", 0), cmin.get("z", 0))

	var cmax: Dictionary = data.get("city_max", {})
	_city_max = Vector3i(cmax.get("x", 512), cmax.get("y", 64), cmax.get("z", 512))

	# Load districts
	var districts_data: Dictionary = data.get("districts", {})
	for district_id_str in districts_data:
		var district := District.new()
		district.from_dict(districts_data[district_id_str])
		_districts[int(district_id_str)] = district

		district.ownership_changed.connect(_on_ownership_changed)
		district.district_captured.connect(_on_district_captured)

		# Rebuild faction map
		if not district.owning_faction.is_empty():
			if not _faction_districts.has(district.owning_faction):
				_faction_districts[district.owning_faction] = []
			_faction_districts[district.owning_faction].append(district.district_id)

	# Load resource nodes
	var nodes_data: Dictionary = data.get("resource_nodes", {})
	for node_id_str in nodes_data:
		var node := ResourceNode.new()
		node.from_dict(nodes_data[node_id_str])
		_resource_nodes[int(node_id_str)] = node

		# Rebuild district node map
		if not _district_nodes.has(node.district_id):
			_district_nodes[node.district_id] = []
		_district_nodes[node.district_id].append(node.node_id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_counts: Dictionary = {}
	for t in District.DistrictType.values():
		type_counts[t] = 0

	for district_id in _districts:
		var district: District = _districts[district_id]
		type_counts[district.district_type] += 1

	return {
		"total_districts": _districts.size(),
		"total_resource_nodes": _resource_nodes.size(),
		"factions": _faction_districts.size(),
		"district_types": type_counts
	}
