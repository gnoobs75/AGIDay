class_name ResourcePlacementSystem
extends RefCounted
## ResourcePlacementSystem strategically distributes resources throughout the city.
## Places REE nodes, power plants, and research facilities at tactical locations.

signal resource_placed(node_id: int, position: Vector3, resource_type: String)
signal power_plant_placed(plant_id: int, position: Vector3, plant_type: String)
signal research_facility_placed(facility_id: int, position: Vector3)
signal placement_complete(total_resources: int, total_power: int, total_research: int)

## Resource placement constraints
const MIN_REE_NODES := 20
const MAX_REE_NODES := 50
const MIN_POWER_PLANTS := 8
const MAX_POWER_PLANTS := 16
const MIN_RESEARCH_FACILITIES := 4
const MAX_RESEARCH_FACILITIES := 8

## Spacing constraints
const MIN_REE_SPACING := 32.0
const MIN_POWER_SPACING := 64.0
const MIN_RESEARCH_SPACING := 96.0

## Power plant types
enum PowerPlantType {
	SOLAR,
	FUSION
}

## Power output by type
const POWER_OUTPUT := {
	PowerPlantType.SOLAR: 100.0,
	PowerPlantType.FUSION: 500.0
}

## Resource types with faction bonuses
const FACTION_BONUSES := {
	"aether_swarm": {"ree_bonus": 1.2, "power_bonus": 0.8},
	"optiforge": {"ree_bonus": 1.0, "power_bonus": 1.5},
	"dynapods": {"ree_bonus": 1.1, "power_bonus": 1.1},
	"logibots": {"ree_bonus": 0.9, "power_bonus": 1.3}
}


## Resource node data.
class PlacedResource:
	var node_id: int = 0
	var position: Vector3 = Vector3.ZERO
	var resource_type: String = "ree"
	var base_amount: float = 0.0
	var faction_bonus: String = ""
	var district_id: int = -1


## Power plant data.
class PlacedPowerPlant:
	var plant_id: int = 0
	var position: Vector3 = Vector3.ZERO
	var plant_type: int = PowerPlantType.SOLAR
	var power_output: float = 0.0
	var connected_to: Array[int] = []  ## District IDs
	var district_id: int = -1


## Research facility data.
class PlacedResearchFacility:
	var facility_id: int = 0
	var position: Vector3 = Vector3.ZERO
	var research_bonus: float = 1.0
	var specialization: String = ""  ## combat, economy, engineering
	var district_id: int = -1


## Placed resources
var _ree_nodes: Dictionary = {}  ## node_id -> PlacedResource
var _power_plants: Dictionary = {}  ## plant_id -> PlacedPowerPlant
var _research_facilities: Dictionary = {}  ## facility_id -> PlacedResearchFacility

## Position lookups
var _position_to_resource: Dictionary = {}  ## "x,z" -> node_id
var _position_to_power: Dictionary = {}  ## "x,z" -> plant_id
var _position_to_research: Dictionary = {}  ## "x,z" -> facility_id

## ID counters
var _next_ree_id: int = 1
var _next_power_id: int = 1
var _next_research_id: int = 1

## RNG for placement
var _rng: RandomNumberGenerator = null

## World size
var _world_size: int = 512


func _init() -> void:
	_rng = RandomNumberGenerator.new()


## Initialize with seed and world size.
func initialize(seed_value: int, world_size: int = 512) -> void:
	_rng.seed = seed_value
	_world_size = world_size


## Generate all resource placements.
func generate_placements(district_centers: Array[Vector3] = []) -> void:
	# Clear existing
	_ree_nodes.clear()
	_power_plants.clear()
	_research_facilities.clear()
	_position_to_resource.clear()
	_position_to_power.clear()
	_position_to_research.clear()

	# Determine counts based on world size
	var size_factor := float(_world_size) / 512.0
	var ree_count := clampi(int(_rng.randi_range(MIN_REE_NODES, MAX_REE_NODES) * size_factor), MIN_REE_NODES, MAX_REE_NODES * 2)
	var power_count := clampi(int(_rng.randi_range(MIN_POWER_PLANTS, MAX_POWER_PLANTS) * size_factor), MIN_POWER_PLANTS, MAX_POWER_PLANTS * 2)
	var research_count := clampi(int(_rng.randi_range(MIN_RESEARCH_FACILITIES, MAX_RESEARCH_FACILITIES) * size_factor), MIN_RESEARCH_FACILITIES, MAX_RESEARCH_FACILITIES * 2)

	# Place resources with strategic consideration
	_place_ree_nodes(ree_count, district_centers)
	_place_power_plants(power_count, district_centers)
	_place_research_facilities(research_count, district_centers)

	placement_complete.emit(_ree_nodes.size(), _power_plants.size(), _research_facilities.size())


## Place REE nodes strategically.
func _place_ree_nodes(count: int, district_centers: Array[Vector3]) -> void:
	var placed_positions: Array[Vector3] = []

	for i in count:
		var position := _find_strategic_position(placed_positions, MIN_REE_SPACING, district_centers, 0.3)
		if position == Vector3.ZERO:
			continue

		var resource := PlacedResource.new()
		resource.node_id = _next_ree_id
		resource.position = position
		resource.resource_type = "ree"
		resource.base_amount = _rng.randf_range(50.0, 150.0)

		# Assign faction bonus based on position (corners favor factions)
		resource.faction_bonus = _determine_faction_bonus(position)

		# Assign to nearest district
		resource.district_id = _find_nearest_district(position, district_centers)

		_ree_nodes[_next_ree_id] = resource
		_position_to_resource[_pos_to_key(position)] = _next_ree_id

		placed_positions.append(position)
		resource_placed.emit(_next_ree_id, position, "ree")
		_next_ree_id += 1


## Place power plants strategically.
func _place_power_plants(count: int, district_centers: Array[Vector3]) -> void:
	var placed_positions: Array[Vector3] = []

	# Ensure at least one fusion plant
	var fusion_count := maxi(1, count / 4)
	var solar_count := count - fusion_count

	# Place fusion plants first (more strategic)
	for i in fusion_count:
		var position := _find_strategic_position(placed_positions, MIN_POWER_SPACING, district_centers, 0.5)
		if position == Vector3.ZERO:
			continue

		_place_power_plant_at(position, PowerPlantType.FUSION, district_centers)
		placed_positions.append(position)

	# Place solar plants
	for i in solar_count:
		var position := _find_strategic_position(placed_positions, MIN_POWER_SPACING, district_centers, 0.4)
		if position == Vector3.ZERO:
			continue

		_place_power_plant_at(position, PowerPlantType.SOLAR, district_centers)
		placed_positions.append(position)


## Place a power plant at position.
func _place_power_plant_at(position: Vector3, plant_type: int, district_centers: Array[Vector3]) -> void:
	var plant := PlacedPowerPlant.new()
	plant.plant_id = _next_power_id
	plant.position = position
	plant.plant_type = plant_type
	plant.power_output = POWER_OUTPUT[plant_type]
	plant.district_id = _find_nearest_district(position, district_centers)

	_power_plants[_next_power_id] = plant
	_position_to_power[_pos_to_key(position)] = _next_power_id

	var type_name := "fusion" if plant_type == PowerPlantType.FUSION else "solar"
	power_plant_placed.emit(_next_power_id, position, type_name)
	_next_power_id += 1


## Place research facilities.
func _place_research_facilities(count: int, district_centers: Array[Vector3]) -> void:
	var placed_positions: Array[Vector3] = []
	var specializations := ["combat", "economy", "engineering"]

	for i in count:
		var position := _find_strategic_position(placed_positions, MIN_RESEARCH_SPACING, district_centers, 0.6)
		if position == Vector3.ZERO:
			continue

		var facility := PlacedResearchFacility.new()
		facility.facility_id = _next_research_id
		facility.position = position
		facility.research_bonus = _rng.randf_range(1.1, 1.5)
		facility.specialization = specializations[i % specializations.size()]
		facility.district_id = _find_nearest_district(position, district_centers)

		_research_facilities[_next_research_id] = facility
		_position_to_research[_pos_to_key(position)] = _next_research_id

		placed_positions.append(position)
		research_facility_placed.emit(_next_research_id, position)
		_next_research_id += 1


## Find strategic position with spacing and district consideration.
func _find_strategic_position(
	existing: Array[Vector3],
	min_spacing: float,
	district_centers: Array[Vector3],
	district_weight: float
) -> Vector3:
	var max_attempts := 100
	var best_position := Vector3.ZERO
	var best_score := -INF

	for attempt in max_attempts:
		# Generate candidate position
		var x := _rng.randf_range(16, _world_size - 16)
		var z := _rng.randf_range(16, _world_size - 16)
		var candidate := Vector3(x, 0, z)

		# Check spacing from existing
		var too_close := false
		for pos in existing:
			if candidate.distance_to(pos) < min_spacing:
				too_close = true
				break

		if too_close:
			continue

		# Calculate strategic score
		var score := _calculate_position_score(candidate, district_centers, district_weight)

		if score > best_score:
			best_score = score
			best_position = candidate

	return best_position


## Calculate strategic score for position.
func _calculate_position_score(position: Vector3, district_centers: Array[Vector3], district_weight: float) -> float:
	var score := 0.0

	# Bonus for being near district centers
	if not district_centers.is_empty():
		var min_dist := INF
		for center in district_centers:
			var dist := position.distance_to(center)
			min_dist = minf(min_dist, dist)

		# Closer to districts = higher score, but not too close
		if min_dist > 20 and min_dist < 100:
			score += (100 - min_dist) * district_weight

	# Bonus for strategic corners (faction areas)
	var corner_bonus := _get_corner_bonus(position)
	score += corner_bonus * 10

	# Some randomness
	score += _rng.randf_range(0, 20)

	return score


## Get corner bonus (near faction spawn areas).
func _get_corner_bonus(position: Vector3) -> float:
	var corners := [
		Vector3(0, 0, 0),
		Vector3(_world_size, 0, 0),
		Vector3(0, 0, _world_size),
		Vector3(_world_size, 0, _world_size)
	]

	var min_corner_dist := INF
	for corner in corners:
		min_corner_dist = minf(min_corner_dist, position.distance_to(corner))

	# Bonus for being between center and corners (strategic contested areas)
	var center := Vector3(_world_size / 2.0, 0, _world_size / 2.0)
	var center_dist := position.distance_to(center)

	if center_dist > _world_size * 0.2 and center_dist < _world_size * 0.4:
		return 1.0

	return 0.0


## Determine faction bonus based on position.
func _determine_faction_bonus(position: Vector3) -> String:
	var factions := ["aether_swarm", "optiforge", "dynapods", "logibots"]
	var corners := [
		Vector3(0, 0, 0),
		Vector3(_world_size, 0, 0),
		Vector3(0, 0, _world_size),
		Vector3(_world_size, 0, _world_size)
	]

	# Find nearest corner
	var min_dist := INF
	var nearest_idx := 0

	for i in corners.size():
		var dist := position.distance_to(corners[i])
		if dist < min_dist:
			min_dist = dist
			nearest_idx = i

	# Only assign bonus if reasonably close to corner
	if min_dist < _world_size * 0.3:
		return factions[nearest_idx]

	return ""


## Find nearest district.
func _find_nearest_district(position: Vector3, district_centers: Array[Vector3]) -> int:
	if district_centers.is_empty():
		return -1

	var min_dist := INF
	var nearest_idx := -1

	for i in district_centers.size():
		var dist := position.distance_to(district_centers[i])
		if dist < min_dist:
			min_dist = dist
			nearest_idx = i

	return nearest_idx


## Convert position to key.
func _pos_to_key(position: Vector3) -> String:
	return "%d,%d" % [int(position.x), int(position.z)]


## Get REE node at position.
func get_ree_node_at(position: Vector3) -> PlacedResource:
	var key := _pos_to_key(position)
	if _position_to_resource.has(key):
		return _ree_nodes.get(_position_to_resource[key])
	return null


## Get power plant at position.
func get_power_plant_at(position: Vector3) -> PlacedPowerPlant:
	var key := _pos_to_key(position)
	if _position_to_power.has(key):
		return _power_plants.get(_position_to_power[key])
	return null


## Get research facility at position.
func get_research_facility_at(position: Vector3) -> PlacedResearchFacility:
	var key := _pos_to_key(position)
	if _position_to_research.has(key):
		return _research_facilities.get(_position_to_research[key])
	return null


## Get all REE nodes.
func get_all_ree_nodes() -> Array:
	return _ree_nodes.values()


## Get all power plants.
func get_all_power_plants() -> Array:
	return _power_plants.values()


## Get all research facilities.
func get_all_research_facilities() -> Array:
	return _research_facilities.values()


## Get resources by district.
func get_resources_in_district(district_id: int) -> Dictionary:
	var result := {
		"ree": [],
		"power": [],
		"research": []
	}

	for node in _ree_nodes.values():
		if node.district_id == district_id:
			result["ree"].append(node)

	for plant in _power_plants.values():
		if plant.district_id == district_id:
			result["power"].append(plant)

	for facility in _research_facilities.values():
		if facility.district_id == district_id:
			result["research"].append(facility)

	return result


## Get total power output.
func get_total_power_output() -> float:
	var total := 0.0
	for plant in _power_plants.values():
		total += plant.power_output
	return total


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var ree_data: Array = []
	for node in _ree_nodes.values():
		ree_data.append({
			"id": node.node_id,
			"position": [node.position.x, node.position.y, node.position.z],
			"type": node.resource_type,
			"amount": node.base_amount,
			"faction_bonus": node.faction_bonus,
			"district_id": node.district_id
		})

	var power_data: Array = []
	for plant in _power_plants.values():
		power_data.append({
			"id": plant.plant_id,
			"position": [plant.position.x, plant.position.y, plant.position.z],
			"type": plant.plant_type,
			"output": plant.power_output,
			"district_id": plant.district_id
		})

	var research_data: Array = []
	for facility in _research_facilities.values():
		research_data.append({
			"id": facility.facility_id,
			"position": [facility.position.x, facility.position.y, facility.position.z],
			"bonus": facility.research_bonus,
			"specialization": facility.specialization,
			"district_id": facility.district_id
		})

	return {
		"ree_nodes": ree_data,
		"power_plants": power_data,
		"research_facilities": research_data,
		"next_ree_id": _next_ree_id,
		"next_power_id": _next_power_id,
		"next_research_id": _next_research_id
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_ree_nodes.clear()
	_power_plants.clear()
	_research_facilities.clear()
	_position_to_resource.clear()
	_position_to_power.clear()
	_position_to_research.clear()

	_next_ree_id = data.get("next_ree_id", 1)
	_next_power_id = data.get("next_power_id", 1)
	_next_research_id = data.get("next_research_id", 1)

	for r in data.get("ree_nodes", []):
		var node := PlacedResource.new()
		node.node_id = r["id"]
		var pos: Array = r["position"]
		node.position = Vector3(pos[0], pos[1], pos[2])
		node.resource_type = r["type"]
		node.base_amount = r["amount"]
		node.faction_bonus = r.get("faction_bonus", "")
		node.district_id = r.get("district_id", -1)
		_ree_nodes[node.node_id] = node
		_position_to_resource[_pos_to_key(node.position)] = node.node_id

	for p in data.get("power_plants", []):
		var plant := PlacedPowerPlant.new()
		plant.plant_id = p["id"]
		var pos: Array = p["position"]
		plant.position = Vector3(pos[0], pos[1], pos[2])
		plant.plant_type = p["type"]
		plant.power_output = p["output"]
		plant.district_id = p.get("district_id", -1)
		_power_plants[plant.plant_id] = plant
		_position_to_power[_pos_to_key(plant.position)] = plant.plant_id

	for f in data.get("research_facilities", []):
		var facility := PlacedResearchFacility.new()
		facility.facility_id = f["id"]
		var pos: Array = f["position"]
		facility.position = Vector3(pos[0], pos[1], pos[2])
		facility.research_bonus = f["bonus"]
		facility.specialization = f.get("specialization", "")
		facility.district_id = f.get("district_id", -1)
		_research_facilities[facility.facility_id] = facility
		_position_to_research[_pos_to_key(facility.position)] = facility.facility_id


## Get statistics.
func get_statistics() -> Dictionary:
	var solar_count := 0
	var fusion_count := 0
	for plant in _power_plants.values():
		if plant.plant_type == PowerPlantType.SOLAR:
			solar_count += 1
		else:
			fusion_count += 1

	return {
		"ree_nodes": _ree_nodes.size(),
		"power_plants": _power_plants.size(),
		"solar_plants": solar_count,
		"fusion_plants": fusion_count,
		"research_facilities": _research_facilities.size(),
		"total_power_output": get_total_power_output()
	}
