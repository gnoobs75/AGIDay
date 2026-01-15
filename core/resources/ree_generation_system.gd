class_name REEGenerationSystem
extends RefCounted
## REEGenerationSystem creates REE from destruction and salvage events.
## Primary resource generation mechanism rewarding destruction.

signal ree_generated(amount: float, source: String, faction_id: String, position: Vector3)
signal building_destroyed_ree(building_id: int, amount: float, faction_id: String)
signal unit_salvaged_ree(unit_id: int, amount: float, faction_id: String)
signal district_income_generated(district_id: int, amount: float, faction_id: String)

## REE source categories
enum Source {
	DESTRUCTION = 0,
	SALVAGE = 1,
	DISTRICT_INCOME = 2
}

## Building base values by type
const BUILDING_BASE_VALUES := {
	"small_residential": 100.0,
	"medium_residential": 300.0,
	"large_residential": 700.0,
	"small_commercial": 150.0,
	"medium_commercial": 450.0,
	"large_commercial": 1000.0,
	"small_industrial": 200.0,
	"medium_industrial": 600.0,
	"large_industrial": 1200.0,
	"power_station": 2000.0,
	"power_substation": 500.0,
	"ree_extractor": 1500.0,
	"warehouse": 400.0,
	"default": 200.0
}

## Unit salvage values by type
const UNIT_SALVAGE_VALUES := {
	"infantry": 25.0,
	"tank": 100.0,
	"artillery": 150.0,
	"harvester": 75.0,
	"medic": 40.0,
	"engineer": 50.0,
	"scout": 15.0,
	"default": 30.0
}

## District income rates per second by type
const DISTRICT_INCOME_RATES := {
	"power_plant": 0.0,      ## Power districts don't generate REE
	"resource_node": 10.0,   ## Resource districts generate most
	"mixed": 2.0             ## Mixed districts generate some
}

## REE drop manager reference
var drop_manager: REEDropManager = null

## Resource drop generator reference
var drop_generator: ResourceDropGenerator = null

## Generation statistics by source
var stats: Dictionary = {
	"destruction_total": 0.0,
	"salvage_total": 0.0,
	"district_income_total": 0.0,
	"events_destruction": 0,
	"events_salvage": 0,
	"events_district": 0
}


func _init() -> void:
	drop_generator = ResourceDropGenerator.new()


## Set drop manager.
func set_drop_manager(manager: REEDropManager) -> void:
	drop_manager = manager
	drop_generator.set_drop_manager(manager)


## Generate REE from building destruction.
func on_building_destroyed(
	building_id: int,
	building_type: String,
	position: Vector3,
	faction_id: String,
	hp_stage: int = 0,
	max_hp_stages: int = 4
) -> float:
	var base_value: float = BUILDING_BASE_VALUES.get(building_type, BUILDING_BASE_VALUES["default"])

	# HP stage multiplier: more intact = more REE
	# Stage 0 (full HP) = 100%, Stage 4 (destroyed) = 0%
	var hp_multiplier := 1.0 - (float(hp_stage) / float(max_hp_stages))
	hp_multiplier = maxf(0.1, hp_multiplier)  # Minimum 10%

	var amount := base_value * hp_multiplier

	# Create REE drop
	if drop_generator != null:
		drop_generator.generate_from_building(
			position,
			building_type,
			_get_size_from_type(building_type),
			faction_id,
			"combat"
		)

	# Track statistics
	stats["destruction_total"] += amount
	stats["events_destruction"] += 1

	building_destroyed_ree.emit(building_id, amount, faction_id)
	ree_generated.emit(amount, "destruction", faction_id, position)

	return amount


## Generate REE from unit death/salvage.
func on_unit_salvaged(
	unit_id: int,
	unit_type: String,
	position: Vector3,
	faction_id: String,
	salvage_rate: float = 0.5
) -> float:
	var base_value: float = UNIT_SALVAGE_VALUES.get(unit_type, UNIT_SALVAGE_VALUES["default"])
	var amount := base_value * salvage_rate

	# Create REE drop
	if drop_generator != null:
		drop_generator.generate_from_unit(position, unit_type, base_value, faction_id)

	# Track statistics
	stats["salvage_total"] += amount
	stats["events_salvage"] += 1

	unit_salvaged_ree.emit(unit_id, amount, faction_id)
	ree_generated.emit(amount, "salvage", faction_id, position)

	return amount


## Generate district income (called per frame).
func generate_district_income(
	district_id: int,
	district_type: String,
	faction_id: String,
	delta: float
) -> float:
	var rate: float = DISTRICT_INCOME_RATES.get(district_type, 0.0)

	if rate <= 0:
		return 0.0

	var amount := rate * delta

	# Add directly to faction (no physical drop for income)
	if drop_manager != null and drop_manager.resource_manager != null:
		if drop_manager.resource_manager.has_method("add_faction_ree"):
			drop_manager.resource_manager.add_faction_ree(faction_id, amount)

	# Track statistics
	stats["district_income_total"] += amount
	stats["events_district"] += 1

	district_income_generated.emit(district_id, amount, faction_id)

	return amount


## Process all district income for frame.
func process_district_income(districts: Array, delta: float) -> Dictionary:
	var income_by_faction: Dictionary = {}

	for district in districts:
		if district == null:
			continue

		var faction_id: String = ""
		var district_type: String = ""
		var district_id: int = 0

		# Get district properties (handle different district class types)
		if "owner_faction" in district:
			faction_id = district.owner_faction
		elif "controlling_faction" in district:
			faction_id = district.controlling_faction

		if faction_id.is_empty():
			continue

		if "type" in district:
			district_type = _get_district_type_name(district.type)
		elif "get_type_name" in district:
			district_type = district.get_type_name().to_lower()

		if "id" in district:
			district_id = district.id

		var income := generate_district_income(district_id, district_type, faction_id, delta)

		if income > 0:
			if not income_by_faction.has(faction_id):
				income_by_faction[faction_id] = 0.0
			income_by_faction[faction_id] += income

	return income_by_faction


## Get size category from building type.
func _get_size_from_type(building_type: String) -> int:
	if building_type.begins_with("small"):
		return 0
	elif building_type.begins_with("medium"):
		return 1
	elif building_type.begins_with("large"):
		return 2
	return 0


## Get district type name from enum.
func _get_district_type_name(type: int) -> String:
	match type:
		0: return "power_plant"
		1: return "resource_node"
		2: return "mixed"
	return "mixed"


## Calculate building REE value (for preview/UI).
static func calculate_building_value(building_type: String, hp_stage: int = 0) -> float:
	var base_value: float = BUILDING_BASE_VALUES.get(building_type, BUILDING_BASE_VALUES["default"])
	var hp_multiplier := 1.0 - (float(hp_stage) / 4.0)
	return base_value * maxf(0.1, hp_multiplier)


## Calculate unit salvage value (for preview/UI).
static func calculate_unit_value(unit_type: String, salvage_rate: float = 0.5) -> float:
	var base_value: float = UNIT_SALVAGE_VALUES.get(unit_type, UNIT_SALVAGE_VALUES["default"])
	return base_value * salvage_rate


## Get statistics.
func get_statistics() -> Dictionary:
	var total: float = stats["destruction_total"] + stats["salvage_total"] + stats["district_income_total"]
	return {
		"total_generated": total,
		"destruction": stats["destruction_total"],
		"salvage": stats["salvage_total"],
		"district_income": stats["district_income_total"],
		"events": {
			"destruction": stats["events_destruction"],
			"salvage": stats["events_salvage"],
			"district": stats["events_district"]
		}
	}


## Reset statistics.
func reset_statistics() -> void:
	stats = {
		"destruction_total": 0.0,
		"salvage_total": 0.0,
		"district_income_total": 0.0,
		"events_destruction": 0,
		"events_salvage": 0,
		"events_district": 0
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"stats": stats.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	stats = data.get("stats", stats).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var statistics := get_statistics()
	return {
		"total_ree": "%.1f" % statistics["total_generated"],
		"destruction": "%.1f (%d events)" % [statistics["destruction"], statistics["events"]["destruction"]],
		"salvage": "%.1f (%d events)" % [statistics["salvage"], statistics["events"]["salvage"]],
		"income": "%.1f" % statistics["district_income"]
	}
