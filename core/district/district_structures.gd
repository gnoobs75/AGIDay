class_name DistrictStructures
extends RefCounted
## DistrictStructures manages special buildings within districts.
## Handles PowerPlants, Factories, ResearchLabs, and Watchtowers with bonuses.

signal structure_placed(structure_id: int, structure_type: String, district_id: int)
signal structure_destroyed(structure_id: int, structure_type: String)
signal structure_repaired(structure_id: int, structure_type: String)
signal bonus_changed(district_id: int, bonus_type: String, value: float)

## Structure types
enum StructureType {
	POWER_PLANT,
	SUBSTATION,
	FUSION_REACTOR,
	FACTORY,
	WORKSHOP,
	ADVANCED_FACTORY,
	RESEARCH_LAB,
	DATA_CENTER,
	ADVANCED_LAB,
	WATCHTOWER,
	RESIDENTIAL,
	COMMERCIAL
}

## District type to allowed structures
const DISTRICT_ALLOWED_STRUCTURES := {
	DistrictZone.DistrictType.RESIDENTIAL: [StructureType.RESIDENTIAL, StructureType.COMMERCIAL, StructureType.WATCHTOWER],
	DistrictZone.DistrictType.INDUSTRIAL: [StructureType.FACTORY, StructureType.WORKSHOP, StructureType.ADVANCED_FACTORY, StructureType.WATCHTOWER],
	DistrictZone.DistrictType.COMMERCIAL: [StructureType.COMMERCIAL, StructureType.RESIDENTIAL, StructureType.WATCHTOWER],
	DistrictZone.DistrictType.CORNER: [StructureType.POWER_PLANT, StructureType.SUBSTATION, StructureType.FUSION_REACTOR],
	DistrictZone.DistrictType.EDGE: [StructureType.FACTORY, StructureType.WATCHTOWER, StructureType.WORKSHOP],
	DistrictZone.DistrictType.CENTER: [StructureType.RESEARCH_LAB, StructureType.DATA_CENTER, StructureType.ADVANCED_LAB, StructureType.WATCHTOWER]
}

## Default bonus values
const POWER_PLANT_OUTPUT := 500.0       ## MW
const SUBSTATION_OUTPUT := 200.0
const FUSION_REACTOR_OUTPUT := 2000.0
const FACTORY_SPEED := 1.0              ## Multiplier
const WORKSHOP_SPEED := 0.75
const ADVANCED_FACTORY_SPEED := 1.5
const RESEARCH_LAB_RATE := 50.0         ## Per second
const DATA_CENTER_RATE := 75.0
const ADVANCED_LAB_RATE := 100.0
const WATCHTOWER_VISION := 20.0         ## Units


## Base structure data.
class Structure:
	var structure_id: int = 0
	var structure_type: int = StructureType.POWER_PLANT
	var position: Vector3 = Vector3.ZERO
	var district_id: int = -1
	var is_destroyed: bool = false
	var health: float = 100.0
	var max_health: float = 100.0

	func get_type_name() -> String:
		match structure_type:
			StructureType.POWER_PLANT: return "power_plant"
			StructureType.SUBSTATION: return "substation"
			StructureType.FUSION_REACTOR: return "fusion_reactor"
			StructureType.FACTORY: return "factory"
			StructureType.WORKSHOP: return "workshop"
			StructureType.ADVANCED_FACTORY: return "advanced_factory"
			StructureType.RESEARCH_LAB: return "research_lab"
			StructureType.DATA_CENTER: return "data_center"
			StructureType.ADVANCED_LAB: return "advanced_lab"
			StructureType.WATCHTOWER: return "watchtower"
			StructureType.RESIDENTIAL: return "residential"
			StructureType.COMMERCIAL: return "commercial"
			_: return "unknown"


## Power plant structure.
class PowerPlant extends Structure:
	var power_output: float = POWER_PLANT_OUTPUT

	func _init() -> void:
		structure_type = StructureType.POWER_PLANT
		max_health = 200.0
		health = max_health

	func get_power_output() -> float:
		if is_destroyed:
			return 0.0
		return power_output * (health / max_health)


## Factory structure.
class Factory extends Structure:
	var production_speed: float = FACTORY_SPEED

	func _init() -> void:
		structure_type = StructureType.FACTORY
		max_health = 150.0
		health = max_health

	func get_production_speed() -> float:
		if is_destroyed:
			return 0.0
		return production_speed * (health / max_health)


## Research lab structure.
class ResearchLab extends Structure:
	var research_rate: float = RESEARCH_LAB_RATE

	func _init() -> void:
		structure_type = StructureType.RESEARCH_LAB
		max_health = 100.0
		health = max_health

	func get_research_rate() -> float:
		if is_destroyed:
			return 0.0
		return research_rate * (health / max_health)


## Watchtower structure.
class Watchtower extends Structure:
	var vision_range: float = WATCHTOWER_VISION

	func _init() -> void:
		structure_type = StructureType.WATCHTOWER
		max_health = 75.0
		health = max_health

	func get_vision_range() -> float:
		if is_destroyed:
			return 0.0
		return vision_range


## Structure storage by type per district
var _power_plants: Dictionary = {}     ## structure_id -> PowerPlant
var _factories: Dictionary = {}        ## structure_id -> Factory
var _research_labs: Dictionary = {}    ## structure_id -> ResearchLab
var _watchtowers: Dictionary = {}      ## structure_id -> Watchtower

## All structures by ID
var _all_structures: Dictionary = {}   ## structure_id -> Structure

## District to structures lookup
var _district_structures: Dictionary = {}  ## district_id -> Array[structure_id]

## Next structure ID
var _next_id: int = 1


func _init() -> void:
	pass


## Place a power plant.
func place_power_plant(position: Vector3, district_id: int, plant_type: int = StructureType.POWER_PLANT) -> int:
	var plant := PowerPlant.new()
	plant.structure_id = _next_id
	plant.position = position
	plant.district_id = district_id
	plant.structure_type = plant_type

	# Set output based on type
	match plant_type:
		StructureType.SUBSTATION:
			plant.power_output = SUBSTATION_OUTPUT
		StructureType.FUSION_REACTOR:
			plant.power_output = FUSION_REACTOR_OUTPUT
			plant.max_health = 300.0
			plant.health = plant.max_health
		_:
			plant.power_output = POWER_PLANT_OUTPUT

	_register_structure(plant, _power_plants)
	return plant.structure_id


## Place a factory.
func place_factory(position: Vector3, district_id: int, factory_type: int = StructureType.FACTORY) -> int:
	var factory := Factory.new()
	factory.structure_id = _next_id
	factory.position = position
	factory.district_id = district_id
	factory.structure_type = factory_type

	# Set speed based on type
	match factory_type:
		StructureType.WORKSHOP:
			factory.production_speed = WORKSHOP_SPEED
		StructureType.ADVANCED_FACTORY:
			factory.production_speed = ADVANCED_FACTORY_SPEED
			factory.max_health = 200.0
			factory.health = factory.max_health
		_:
			factory.production_speed = FACTORY_SPEED

	_register_structure(factory, _factories)
	return factory.structure_id


## Place a research lab.
func place_research_lab(position: Vector3, district_id: int, lab_type: int = StructureType.RESEARCH_LAB) -> int:
	var lab := ResearchLab.new()
	lab.structure_id = _next_id
	lab.position = position
	lab.district_id = district_id
	lab.structure_type = lab_type

	# Set rate based on type
	match lab_type:
		StructureType.DATA_CENTER:
			lab.research_rate = DATA_CENTER_RATE
		StructureType.ADVANCED_LAB:
			lab.research_rate = ADVANCED_LAB_RATE
			lab.max_health = 125.0
			lab.health = lab.max_health
		_:
			lab.research_rate = RESEARCH_LAB_RATE

	_register_structure(lab, _research_labs)
	return lab.structure_id


## Place a watchtower.
func place_watchtower(position: Vector3, district_id: int) -> int:
	var tower := Watchtower.new()
	tower.structure_id = _next_id
	tower.position = position
	tower.district_id = district_id

	_register_structure(tower, _watchtowers)
	return tower.structure_id


## Register a structure.
func _register_structure(structure: Structure, type_dict: Dictionary) -> void:
	type_dict[structure.structure_id] = structure
	_all_structures[structure.structure_id] = structure

	if not _district_structures.has(structure.district_id):
		_district_structures[structure.district_id] = []
	_district_structures[structure.district_id].append(structure.structure_id)

	structure_placed.emit(structure.structure_id, structure.get_type_name(), structure.district_id)
	_next_id += 1


## Damage a structure.
func damage_structure(structure_id: int, damage: float) -> void:
	if not _all_structures.has(structure_id):
		return

	var structure: Structure = _all_structures[structure_id]
	structure.health = maxf(0.0, structure.health - damage)

	if structure.health <= 0.0 and not structure.is_destroyed:
		structure.is_destroyed = true
		structure_destroyed.emit(structure_id, structure.get_type_name())


## Repair a structure.
func repair_structure(structure_id: int, amount: float) -> void:
	if not _all_structures.has(structure_id):
		return

	var structure: Structure = _all_structures[structure_id]
	var was_destroyed := structure.is_destroyed

	structure.health = minf(structure.max_health, structure.health + amount)

	if structure.health > 0.0 and was_destroyed:
		structure.is_destroyed = false
		structure_repaired.emit(structure_id, structure.get_type_name())


## Get total power output for district.
func get_district_power_output(district_id: int) -> float:
	var total := 0.0
	for id in _power_plants:
		var plant: PowerPlant = _power_plants[id]
		if plant.district_id == district_id:
			total += plant.get_power_output()
	return total


## Get total production speed bonus for district.
func get_district_production_speed(district_id: int) -> float:
	var total := 0.0
	var count := 0
	for id in _factories:
		var factory: Factory = _factories[id]
		if factory.district_id == district_id and not factory.is_destroyed:
			total += factory.get_production_speed()
			count += 1

	if count == 0:
		return 1.0  # Base production
	return total / count  # Average speed


## Get total research rate for district.
func get_district_research_rate(district_id: int) -> float:
	var total := 0.0
	for id in _research_labs:
		var lab: ResearchLab = _research_labs[id]
		if lab.district_id == district_id:
			total += lab.get_research_rate()
	return total


## Get vision range for district.
func get_district_vision_range(district_id: int) -> float:
	var max_range := 0.0
	for id in _watchtowers:
		var tower: Watchtower = _watchtowers[id]
		if tower.district_id == district_id:
			max_range = maxf(max_range, tower.get_vision_range())
	return max_range


## Get all structures in district.
func get_structures_in_district(district_id: int) -> Array:
	var result: Array = []
	if _district_structures.has(district_id):
		for id in _district_structures[district_id]:
			if _all_structures.has(id):
				result.append(_all_structures[id])
	return result


## Get structure by ID.
func get_structure(structure_id: int) -> Structure:
	return _all_structures.get(structure_id)


## Check if structure type is allowed in district type.
func is_structure_allowed(structure_type: int, district_type: int) -> bool:
	if not DISTRICT_ALLOWED_STRUCTURES.has(district_type):
		return true  # Allow all if no restrictions

	return structure_type in DISTRICT_ALLOWED_STRUCTURES[district_type]


## Get district bonuses summary.
func get_district_bonuses(district_id: int) -> Dictionary:
	return {
		"power_output": get_district_power_output(district_id),
		"production_speed": get_district_production_speed(district_id),
		"research_rate": get_district_research_rate(district_id),
		"vision_range": get_district_vision_range(district_id)
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var structures_data: Array = []
	for id in _all_structures:
		var s: Structure = _all_structures[id]
		var data := {
			"id": s.structure_id,
			"type": s.structure_type,
			"position": [s.position.x, s.position.y, s.position.z],
			"district_id": s.district_id,
			"is_destroyed": s.is_destroyed,
			"health": s.health,
			"max_health": s.max_health
		}

		# Add type-specific data
		if s is PowerPlant:
			data["power_output"] = s.power_output
		elif s is Factory:
			data["production_speed"] = s.production_speed
		elif s is ResearchLab:
			data["research_rate"] = s.research_rate
		elif s is Watchtower:
			data["vision_range"] = s.vision_range

		structures_data.append(data)

	return {
		"structures": structures_data,
		"next_id": _next_id
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_power_plants.clear()
	_factories.clear()
	_research_labs.clear()
	_watchtowers.clear()
	_all_structures.clear()
	_district_structures.clear()

	_next_id = data.get("next_id", 1)

	for s_data in data.get("structures", []):
		var stype: int = s_data.get("type", 0)
		var pos_arr: Array = s_data.get("position", [0, 0, 0])
		var position := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		var district_id: int = s_data.get("district_id", -1)

		var structure: Structure
		match stype:
			StructureType.POWER_PLANT, StructureType.SUBSTATION, StructureType.FUSION_REACTOR:
				var plant := PowerPlant.new()
				plant.power_output = s_data.get("power_output", POWER_PLANT_OUTPUT)
				structure = plant
				_power_plants[s_data["id"]] = plant

			StructureType.FACTORY, StructureType.WORKSHOP, StructureType.ADVANCED_FACTORY:
				var factory := Factory.new()
				factory.production_speed = s_data.get("production_speed", FACTORY_SPEED)
				structure = factory
				_factories[s_data["id"]] = factory

			StructureType.RESEARCH_LAB, StructureType.DATA_CENTER, StructureType.ADVANCED_LAB:
				var lab := ResearchLab.new()
				lab.research_rate = s_data.get("research_rate", RESEARCH_LAB_RATE)
				structure = lab
				_research_labs[s_data["id"]] = lab

			StructureType.WATCHTOWER:
				var tower := Watchtower.new()
				tower.vision_range = s_data.get("vision_range", WATCHTOWER_VISION)
				structure = tower
				_watchtowers[s_data["id"]] = tower

			_:
				structure = Structure.new()

		structure.structure_id = s_data["id"]
		structure.structure_type = stype
		structure.position = position
		structure.district_id = district_id
		structure.is_destroyed = s_data.get("is_destroyed", false)
		structure.health = s_data.get("health", 100.0)
		structure.max_health = s_data.get("max_health", 100.0)

		_all_structures[structure.structure_id] = structure

		if not _district_structures.has(district_id):
			_district_structures[district_id] = []
		_district_structures[district_id].append(structure.structure_id)


## Get statistics.
func get_statistics() -> Dictionary:
	var destroyed := 0
	for s in _all_structures.values():
		if s.is_destroyed:
			destroyed += 1

	return {
		"total_structures": _all_structures.size(),
		"power_plants": _power_plants.size(),
		"factories": _factories.size(),
		"research_labs": _research_labs.size(),
		"watchtowers": _watchtowers.size(),
		"destroyed": destroyed
	}
