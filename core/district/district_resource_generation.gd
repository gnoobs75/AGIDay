class_name DistrictResourceGeneration
extends RefCounted
## DistrictResourceGeneration handles passive resource income from controlled districts.
## Applies faction modifiers and district count bonuses.

signal resources_generated(faction_id: String, power: float, ree: float, research: float)
signal faction_bonus_changed(faction_id: String, bonus_type: String, value: float)

## Generation interval
const GENERATION_INTERVAL := 0.5  ## Seconds

## District type base generation rates
const DISTRICT_RATES := {
	"POWER_HUB": {"power": 500.0, "ree": 5.0, "research": 0.0},
	"INDUSTRIAL": {"power": 100.0, "ree": 20.0, "research": 0.0},
	"RESEARCH": {"power": 50.0, "ree": 10.0, "research": 50.0},
	"RESIDENTIAL": {"power": 0.0, "ree": 30.0, "research": 0.0},
	"MIXED": {"power": 100.0, "ree": 15.0, "research": 10.0}
}

## Faction modifiers
const FACTION_MODIFIERS := {
	"aether_swarm": {"power": 0.8, "ree": 1.2, "research": 1.0},
	"optiforge": {"power": 1.1, "ree": 1.0, "research": 1.2},
	"dynapods": {"power": 1.0, "ree": 1.1, "research": 0.9},
	"logibots": {"power": 1.2, "ree": 0.9, "research": 1.0}
}

## District count bonus thresholds
const DISTRICT_COUNT_BONUSES := [
	{"count": 4, "type": "production", "value": 1.1},
	{"count": 8, "type": "research", "value": 1.1},
	{"count": 16, "type": "unit_health", "value": 1.05},
	{"count": 32, "type": "unit_damage", "value": 1.05},
	{"count": 48, "type": "unit_health_damage", "value": 1.1}
]


## Accumulated resources per faction
var _faction_resources: Dictionary = {}  ## faction_id -> {power, ree, research}

## District count per faction
var _faction_district_counts: Dictionary = {}  ## faction_id -> count

## Active bonuses per faction
var _faction_bonuses: Dictionary = {}  ## faction_id -> {bonus_type: value}

## Generation timer
var _timer: float = 0.0

## Resource system callback
var _resource_callback: Callable = Callable()


func _init() -> void:
	pass


## Set resource system callback.
## Callback signature: func(faction_id: String, power: float, ree: float, research: float) -> void
func set_resource_callback(callback: Callable) -> void:
	_resource_callback = callback


## Update district resources (call every frame).
func update(delta: float, districts: Array) -> void:
	_timer += delta

	if _timer >= GENERATION_INTERVAL:
		_timer -= GENERATION_INTERVAL
		generate_district_resources(districts)


## Generate resources from all districts.
func generate_district_resources(districts: Array) -> void:
	# Reset counts
	_faction_district_counts.clear()

	# Track resources by faction
	var faction_totals: Dictionary = {}  ## faction_id -> {power, ree, research}

	for district in districts:
		var faction: String = district.owning_faction
		if faction.is_empty():
			continue  # Neutral districts generate nothing

		# Count districts per faction
		_faction_district_counts[faction] = _faction_district_counts.get(faction, 0) + 1

		# Get base rates for district type
		var rates := _get_district_rates(district)

		# Apply faction modifiers
		rates = apply_faction_modifiers(faction, rates)

		# Accumulate
		if not faction_totals.has(faction):
			faction_totals[faction] = {"power": 0.0, "ree": 0.0, "research": 0.0}

		faction_totals[faction]["power"] += rates["power"] * GENERATION_INTERVAL
		faction_totals[faction]["ree"] += rates["ree"] * GENERATION_INTERVAL
		faction_totals[faction]["research"] += rates["research"] * GENERATION_INTERVAL

	# Apply district count bonuses and emit resources
	for faction in faction_totals:
		var totals: Dictionary = faction_totals[faction]

		# Apply production bonus from district count
		var production_mult := _get_district_count_bonus(faction, "production")
		var research_mult := _get_district_count_bonus(faction, "research")

		totals["power"] *= production_mult
		totals["ree"] *= production_mult
		totals["research"] *= research_mult

		# Store accumulated
		_faction_resources[faction] = totals.duplicate()

		# Emit to resource system
		if _resource_callback.is_valid():
			_resource_callback.call(faction, totals["power"], totals["ree"], totals["research"])

		resources_generated.emit(faction, totals["power"], totals["ree"], totals["research"])

	# Update faction bonuses
	_calculate_faction_bonuses()


## Get base rates for district type.
func _get_district_rates(district) -> Dictionary:
	var type_name: String

	# Map district type enum to rate key
	match district.district_type:
		DistrictZone.DistrictType.CORNER:
			type_name = "POWER_HUB"
		DistrictZone.DistrictType.INDUSTRIAL:
			type_name = "INDUSTRIAL"
		DistrictZone.DistrictType.CENTER:
			type_name = "RESEARCH"
		DistrictZone.DistrictType.RESIDENTIAL:
			type_name = "RESIDENTIAL"
		_:
			type_name = "MIXED"

	return DISTRICT_RATES.get(type_name, {"power": 0.0, "ree": 0.0, "research": 0.0}).duplicate()


## Apply faction-specific modifiers.
func apply_faction_modifiers(faction_id: String, rates: Dictionary) -> Dictionary:
	var modifiers: Dictionary = FACTION_MODIFIERS.get(faction_id, {"power": 1.0, "ree": 1.0, "research": 1.0})

	return {
		"power": rates["power"] * modifiers["power"],
		"ree": rates["ree"] * modifiers["ree"],
		"research": rates["research"] * modifiers["research"]
	}


## Get district count bonus multiplier.
func _get_district_count_bonus(faction_id: String, bonus_type: String) -> float:
	var count: int = _faction_district_counts.get(faction_id, 0)
	var multiplier := 1.0

	for bonus in DISTRICT_COUNT_BONUSES:
		if count >= bonus["count"]:
			if bonus["type"] == bonus_type:
				multiplier = maxf(multiplier, bonus["value"])
			elif bonus["type"] == "unit_health_damage" and (bonus_type == "unit_health" or bonus_type == "unit_damage"):
				multiplier = maxf(multiplier, bonus["value"])

	return multiplier


## Calculate and update faction bonuses.
func _calculate_faction_bonuses() -> void:
	for faction in _faction_district_counts:
		var count: int = _faction_district_counts[faction]
		var bonuses: Dictionary = {}

		for bonus in DISTRICT_COUNT_BONUSES:
			if count >= bonus["count"]:
				var btype: String = bonus["type"]
				bonuses[btype] = bonus["value"]
				faction_bonus_changed.emit(faction, btype, bonus["value"])

		_faction_bonuses[faction] = bonuses


## Get faction bonuses.
func calculate_faction_bonuses(faction_id: String) -> Dictionary:
	return _faction_bonuses.get(faction_id, {}).duplicate()


## Get accumulated resources for faction.
func get_faction_resources(faction_id: String) -> Dictionary:
	return _faction_resources.get(faction_id, {"power": 0.0, "ree": 0.0, "research": 0.0}).duplicate()


## Get district count for faction.
func get_faction_district_count(faction_id: String) -> int:
	return _faction_district_counts.get(faction_id, 0)


## Get generation rate for district.
func get_district_generation_rate(district) -> Dictionary:
	var rates := _get_district_rates(district)
	if not district.owning_faction.is_empty():
		rates = apply_faction_modifiers(district.owning_faction, rates)
	return rates


## Get total generation rate for faction.
func get_faction_generation_rate(faction_id: String, districts: Array) -> Dictionary:
	var total := {"power": 0.0, "ree": 0.0, "research": 0.0}

	for district in districts:
		if district.owning_faction == faction_id:
			var rates := _get_district_rates(district)
			rates = apply_faction_modifiers(faction_id, rates)
			total["power"] += rates["power"]
			total["ree"] += rates["ree"]
			total["research"] += rates["research"]

	return total


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"faction_resources": _faction_resources.duplicate(true),
		"faction_district_counts": _faction_district_counts.duplicate(),
		"faction_bonuses": _faction_bonuses.duplicate(true),
		"timer": _timer
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_faction_resources = data.get("faction_resources", {}).duplicate(true)
	_faction_district_counts = data.get("faction_district_counts", {}).duplicate()
	_faction_bonuses = data.get("faction_bonuses", {}).duplicate(true)
	_timer = data.get("timer", 0.0)


## Get statistics.
func get_statistics() -> Dictionary:
	var total_power := 0.0
	var total_ree := 0.0
	var total_research := 0.0

	for res in _faction_resources.values():
		total_power += res["power"]
		total_ree += res["ree"]
		total_research += res["research"]

	return {
		"factions_generating": _faction_resources.size(),
		"total_power_generated": total_power,
		"total_ree_generated": total_ree,
		"total_research_generated": total_research,
		"faction_counts": _faction_district_counts.duplicate()
	}
