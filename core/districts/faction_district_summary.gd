class_name FactionDistrictSummary
extends RefCounted
## FactionDistrictSummary tracks owned districts and total income for a faction.

signal districts_changed(owned_count: int)
signal income_updated(power: float, ree: float, research: float)

## Faction ID
var faction_id: String = ""

## Owned district IDs
var owned_districts: Array[int] = []

## District states by ID
var district_states: Dictionary = {}

## Total income rates
var total_power_rate: float = 0.0
var total_ree_rate: float = 0.0
var total_research_rate: float = 0.0

## Accumulated income (since last collection)
var accumulated_power: float = 0.0
var accumulated_ree: float = 0.0
var accumulated_research: float = 0.0

## Districts by type
var districts_by_type: Dictionary = {}

## Contested districts owned by this faction
var contested_districts: Array[int] = []


func _init(p_faction_id: String = "") -> void:
	faction_id = p_faction_id
	# Initialize type tracking
	for type in [DistrictType.Type.POWER_HUB, DistrictType.Type.INDUSTRIAL,
				 DistrictType.Type.RESEARCH, DistrictType.Type.RESIDENTIAL,
				 DistrictType.Type.MIXED]:
		districts_by_type[type] = []


## Add a district to this faction's ownership.
func add_district(district_id: int, state: DistrictState) -> void:
	if district_id in owned_districts:
		return

	owned_districts.append(district_id)
	district_states[district_id] = state

	# Track by type
	if not districts_by_type.has(state.district_type):
		districts_by_type[state.district_type] = []
	districts_by_type[state.district_type].append(district_id)

	# Track contested
	if state.is_contested:
		contested_districts.append(district_id)

	_recalculate_income()
	districts_changed.emit(owned_districts.size())


## Remove a district from this faction's ownership.
func remove_district(district_id: int) -> void:
	var idx := owned_districts.find(district_id)
	if idx < 0:
		return

	owned_districts.remove_at(idx)

	var state: DistrictState = district_states.get(district_id)
	if state != null:
		# Remove from type tracking
		if districts_by_type.has(state.district_type):
			var type_idx := districts_by_type[state.district_type].find(district_id)
			if type_idx >= 0:
				districts_by_type[state.district_type].remove_at(type_idx)

	district_states.erase(district_id)

	# Remove from contested
	var contested_idx := contested_districts.find(district_id)
	if contested_idx >= 0:
		contested_districts.remove_at(contested_idx)

	_recalculate_income()
	districts_changed.emit(owned_districts.size())


## Update a district's state.
func update_district(district_id: int, state: DistrictState) -> void:
	if district_id not in owned_districts:
		return

	district_states[district_id] = state

	# Update contested tracking
	var contested_idx := contested_districts.find(district_id)
	if state.is_contested and contested_idx < 0:
		contested_districts.append(district_id)
	elif not state.is_contested and contested_idx >= 0:
		contested_districts.remove_at(contested_idx)

	_recalculate_income()


## Recalculate total income rates.
func _recalculate_income() -> void:
	total_power_rate = 0.0
	total_ree_rate = 0.0
	total_research_rate = 0.0

	for district_id in owned_districts:
		var state: DistrictState = district_states.get(district_id)
		if state != null:
			total_power_rate += state.get_effective_power_rate()
			total_ree_rate += state.get_effective_ree_rate()
			total_research_rate += state.get_effective_research_rate()

	income_updated.emit(total_power_rate, total_ree_rate, total_research_rate)


## Generate income for a time delta.
func generate_income(delta: float) -> Dictionary:
	var power := total_power_rate * delta
	var ree := total_ree_rate * delta
	var research := total_research_rate * delta

	accumulated_power += power
	accumulated_ree += ree
	accumulated_research += research

	return {
		"power": power,
		"ree": ree,
		"research": research
	}


## Collect accumulated income and reset.
func collect_income() -> Dictionary:
	var income := {
		"power": accumulated_power,
		"ree": accumulated_ree,
		"research": accumulated_research
	}

	accumulated_power = 0.0
	accumulated_ree = 0.0
	accumulated_research = 0.0

	return income


## Get number of owned districts.
func get_district_count() -> int:
	return owned_districts.size()


## Get districts of a specific type.
func get_districts_of_type(type: int) -> Array[int]:
	var result: Array[int] = []
	if districts_by_type.has(type):
		for id in districts_by_type[type]:
			result.append(id)
	return result


## Get count of districts by type.
func get_type_counts() -> Dictionary:
	var counts := {}
	for type in districts_by_type:
		counts[type] = districts_by_type[type].size()
	return counts


## Check if faction owns a district.
func owns_district(district_id: int) -> bool:
	return district_id in owned_districts


## Get contested district count.
func get_contested_count() -> int:
	return contested_districts.size()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var states_data := {}
	for district_id in district_states:
		states_data[district_id] = district_states[district_id].to_dict()

	return {
		"faction_id": faction_id,
		"owned_districts": owned_districts.duplicate(),
		"district_states": states_data,
		"total_power_rate": total_power_rate,
		"total_ree_rate": total_ree_rate,
		"total_research_rate": total_research_rate,
		"accumulated_power": accumulated_power,
		"accumulated_ree": accumulated_ree,
		"accumulated_research": accumulated_research,
		"contested_districts": contested_districts.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> FactionDistrictSummary:
	var summary := FactionDistrictSummary.new()
	summary.faction_id = data.get("faction_id", "")

	summary.owned_districts.clear()
	for id in data.get("owned_districts", []):
		summary.owned_districts.append(int(id))

	var states_data: Dictionary = data.get("district_states", {})
	for district_id_str in states_data:
		var district_id := int(district_id_str)
		summary.district_states[district_id] = DistrictState.from_dict(states_data[district_id_str])

		# Rebuild type tracking
		var state: DistrictState = summary.district_states[district_id]
		if not summary.districts_by_type.has(state.district_type):
			summary.districts_by_type[state.district_type] = []
		summary.districts_by_type[state.district_type].append(district_id)

	summary.total_power_rate = data.get("total_power_rate", 0.0)
	summary.total_ree_rate = data.get("total_ree_rate", 0.0)
	summary.total_research_rate = data.get("total_research_rate", 0.0)
	summary.accumulated_power = data.get("accumulated_power", 0.0)
	summary.accumulated_ree = data.get("accumulated_ree", 0.0)
	summary.accumulated_research = data.get("accumulated_research", 0.0)

	summary.contested_districts.clear()
	for id in data.get("contested_districts", []):
		summary.contested_districts.append(int(id))

	return summary


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"faction_id": faction_id,
		"district_count": owned_districts.size(),
		"contested_count": contested_districts.size(),
		"income_rates": {
			"power": total_power_rate,
			"ree": total_ree_rate,
			"research": total_research_rate
		},
		"accumulated": {
			"power": accumulated_power,
			"ree": accumulated_ree,
			"research": accumulated_research
		},
		"type_counts": get_type_counts()
	}
