class_name DistrictVictorySystem
extends RefCounted
## DistrictVictorySystem handles 5-second income distribution and victory conditions.
## Includes domination victory check and endless mode support.

signal income_distributed(faction_id: String, power: float, ree: float, research: float)
signal victory_achieved(faction_id: String, victory_type: String)
signal faction_eliminated(faction_id: String)
signal endless_mode_started()

## Income distribution interval
const INCOME_INTERVAL := 5.0  ## 5 seconds

## Base income rates per 5 seconds
const POWER_HUB_POWER := 50.0
const REE_NODE_REE := 100.0
const RESEARCH_FACILITY_RESEARCH := 10.0

## Mixed district rates (balanced)
const MIXED_POWER := 15.0
const MIXED_REE := 30.0
const MIXED_RESEARCH := 3.0

## Total districts for domination victory
const TOTAL_DISTRICTS := 256

## District types (map to generation)
enum DistrictCategory {
	POWER_HUB,
	REE_NODE,
	RESEARCH,
	MIXED,
	EMPTY
}

## References
var _district_manager: DistrictManager = null

## Resource callbacks
var _add_power_callback: Callable = Callable()
var _add_ree_callback: Callable = Callable()
var _add_research_callback: Callable = Callable()

## Timing
var _income_timer: float = 0.0

## Victory state
var _victory_achieved: bool = false
var _victor_faction: String = ""
var _endless_mode: bool = false

## Faction tracking
var _active_factions: Dictionary = {}  ## faction_id -> {districts, eliminated}


func _init() -> void:
	pass


## Initialize with district manager.
func initialize(district_manager: DistrictManager) -> void:
	_district_manager = district_manager


## Set resource callbacks.
func set_resource_callbacks(add_power: Callable, add_ree: Callable, add_research: Callable) -> void:
	_add_power_callback = add_power
	_add_ree_callback = add_ree
	_add_research_callback = add_research


## Register faction.
func register_faction(faction_id: String) -> void:
	_active_factions[faction_id] = {
		"districts": 0,
		"eliminated": false
	}


## Update system (call every frame).
func update(delta: float) -> void:
	_income_timer += delta

	if _income_timer >= INCOME_INTERVAL:
		_income_timer -= INCOME_INTERVAL
		_distribute_income()
		_check_victory_conditions()


## Distribute income to all factions.
func _distribute_income() -> void:
	# Update district counts
	_update_faction_districts()

	for faction_id in _active_factions:
		var faction_data: Dictionary = _active_factions[faction_id]

		if faction_data["eliminated"]:
			continue

		var districts := _district_manager.get_faction_districts(faction_id)
		if districts.is_empty():
			continue

		var total_power := 0.0
		var total_ree := 0.0
		var total_research := 0.0

		for district in districts:
			# Skip contested districts
			if district.contested:
				continue

			# Calculate income based on district type and building status
			var income := _calculate_district_income(district)

			total_power += income["power"]
			total_ree += income["ree"]
			total_research += income["research"]

		# Apply to resource system
		if total_power > 0 and _add_power_callback.is_valid():
			_add_power_callback.call(faction_id, total_power)

		if total_ree > 0 and _add_ree_callback.is_valid():
			_add_ree_callback.call(faction_id, total_ree)

		if total_research > 0 and _add_research_callback.is_valid():
			_add_research_callback.call(faction_id, total_research)

		income_distributed.emit(faction_id, total_power, total_ree, total_research)


## Calculate income for a district.
func _calculate_district_income(district: District) -> Dictionary:
	# Get building ratio (buildings / max buildings)
	var max_buildings := 10  # Default max
	var building_ratio := float(district.building_count) / float(max_buildings)

	# If all buildings destroyed, no income
	if district.building_count == 0:
		return {"power": 0.0, "ree": 0.0, "research": 0.0}

	# Determine district category
	var category := _get_district_category(district)

	var base_power := 0.0
	var base_ree := 0.0
	var base_research := 0.0

	match category:
		DistrictCategory.POWER_HUB:
			base_power = POWER_HUB_POWER
		DistrictCategory.REE_NODE:
			base_ree = REE_NODE_REE
		DistrictCategory.RESEARCH:
			base_research = RESEARCH_FACILITY_RESEARCH
		DistrictCategory.MIXED:
			base_power = MIXED_POWER
			base_ree = MIXED_REE
			base_research = MIXED_RESEARCH
		DistrictCategory.EMPTY:
			return {"power": 0.0, "ree": 0.0, "research": 0.0}

	# Scale by building ratio
	return {
		"power": base_power * building_ratio,
		"ree": base_ree * building_ratio,
		"research": base_research * building_ratio
	}


## Get district category.
func _get_district_category(district: District) -> int:
	match district.district_type:
		District.DistrictType.CORNER:
			return DistrictCategory.POWER_HUB
		District.DistrictType.EDGE:
			return DistrictCategory.REE_NODE
		District.DistrictType.CENTER:
			return DistrictCategory.RESEARCH
		District.DistrictType.INDUSTRIAL, District.DistrictType.COMMERCIAL:
			return DistrictCategory.MIXED
		District.DistrictType.RESIDENTIAL:
			if district.building_count > 0:
				return DistrictCategory.MIXED
			return DistrictCategory.EMPTY
		_:
			return DistrictCategory.EMPTY


## Update faction district counts.
func _update_faction_districts() -> void:
	for faction_id in _active_factions:
		var count := _district_manager.get_faction_districts(faction_id).size()
		_active_factions[faction_id]["districts"] = count

		# Check for elimination
		if count == 0 and not _active_factions[faction_id]["eliminated"]:
			_handle_faction_elimination(faction_id)


## Check victory conditions.
func _check_victory_conditions() -> void:
	if _victory_achieved and not _endless_mode:
		return

	# Check for domination (one faction controls all districts)
	for faction_id in _active_factions:
		var faction_data: Dictionary = _active_factions[faction_id]

		if faction_data["eliminated"]:
			continue

		var district_count: int = faction_data["districts"]

		# Check domination victory
		if district_count >= TOTAL_DISTRICTS:
			_handle_victory(faction_id, "domination")
			return

	# Check if only one faction remains (elimination victory)
	var active_count := 0
	var last_active := ""

	for faction_id in _active_factions:
		if not _active_factions[faction_id]["eliminated"]:
			active_count += 1
			last_active = faction_id

	if active_count == 1 and _active_factions.size() > 1:
		_handle_victory(last_active, "elimination")


## Handle victory.
func _handle_victory(faction_id: String, victory_type: String) -> void:
	if _victory_achieved:
		return

	_victory_achieved = true
	_victor_faction = faction_id

	victory_achieved.emit(faction_id, victory_type)


## Handle faction elimination.
func _handle_faction_elimination(faction_id: String) -> void:
	_active_factions[faction_id]["eliminated"] = true

	# Release captured districts
	for district in _district_manager.get_faction_districts(faction_id):
		district.set_owning_faction("")

	faction_eliminated.emit(faction_id)


## Start endless mode (continue after victory).
func start_endless_mode() -> void:
	_endless_mode = true
	endless_mode_started.emit()


## Check if game is over.
func is_game_over() -> bool:
	return _victory_achieved and not _endless_mode


## Get winner.
func get_victor() -> String:
	return _victor_faction


## Check if victory achieved.
func is_victory_achieved() -> bool:
	return _victory_achieved


## Get faction status.
func get_faction_status(faction_id: String) -> Dictionary:
	if not _active_factions.has(faction_id):
		return {"districts": 0, "eliminated": true}

	return _active_factions[faction_id].duplicate()


## Get domination progress.
func get_domination_progress(faction_id: String) -> float:
	var count := _active_factions.get(faction_id, {}).get("districts", 0)
	return float(count) / float(TOTAL_DISTRICTS)


## Get estimated income for faction.
func get_estimated_income(faction_id: String) -> Dictionary:
	var districts := _district_manager.get_faction_districts(faction_id)

	var total := {"power": 0.0, "ree": 0.0, "research": 0.0}

	for district in districts:
		if district.contested:
			continue

		var income := _calculate_district_income(district)
		total["power"] += income["power"]
		total["ree"] += income["ree"]
		total["research"] += income["research"]

	return total


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"income_timer": _income_timer,
		"victory_achieved": _victory_achieved,
		"victor_faction": _victor_faction,
		"endless_mode": _endless_mode,
		"active_factions": _active_factions.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_income_timer = data.get("income_timer", 0.0)
	_victory_achieved = data.get("victory_achieved", false)
	_victor_faction = data.get("victor_faction", "")
	_endless_mode = data.get("endless_mode", false)
	_active_factions = data.get("active_factions", {}).duplicate(true)


## Get statistics.
func get_statistics() -> Dictionary:
	var faction_stats: Dictionary = {}

	for faction_id in _active_factions:
		faction_stats[faction_id] = {
			"districts": _active_factions[faction_id]["districts"],
			"eliminated": _active_factions[faction_id]["eliminated"],
			"domination_progress": get_domination_progress(faction_id)
		}

	return {
		"victory_achieved": _victory_achieved,
		"victor": _victor_faction,
		"endless_mode": _endless_mode,
		"total_districts": TOTAL_DISTRICTS,
		"factions": faction_stats
	}
