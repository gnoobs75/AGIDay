class_name DistrictState
extends RefCounted
## DistrictState is a serializable snapshot of a district for save/load and multiplayer sync.

## District ID
var id: int = -1

## String ID in format "DISTRICT_X_Y"
var string_id: String = ""

## Grid coordinates
var grid_x: int = 0
var grid_y: int = 0

## Owner faction ID (empty = neutral/uncaptured)
var owner_faction: String = ""

## Control level (0.0 to 1.0)
var control_level: float = 0.0

## Capture progress by faction
var capture_progress: Dictionary = {}

## District type
var district_type: int = DistrictType.Type.MIXED

## Whether contested
var is_contested: bool = false

## Unit presence by faction
var unit_presence: Dictionary = {}

## Building counts (building_type -> count)
var building_counts: Dictionary = {}

## Total buildings (affects income calculation)
var total_buildings: int = 0

## Destroyed buildings (reduces income proportionally)
var destroyed_buildings: int = 0

## Income generation rates (modified by building destruction)
var power_income_rate: float = 0.0
var ree_income_rate: float = 0.0
var research_income_rate: float = 0.0

## Timestamp of last update
var last_update_time: int = 0


func _init() -> void:
	last_update_time = Time.get_ticks_msec()


## Create from a District instance.
static func from_district(district: District, config: DistrictGridConfig = null) -> DistrictState:
	var state := DistrictState.new()
	state.id = district.id
	state.grid_x = district.grid_x
	state.grid_y = district.grid_y
	state.owner_faction = district.owner_faction
	state.control_level = district.control_level
	state.capture_progress = district.capture_progress.duplicate()
	state.district_type = district.district_type
	state.is_contested = district.is_contested
	state.unit_presence = district.unit_presence.duplicate()

	if config != null:
		state.string_id = config.get_string_id(district.id)
	else:
		state.string_id = "DISTRICT_%d_%d" % [district.grid_x, district.grid_y]

	if district.type_config != null:
		state.power_income_rate = district.type_config.power_rate
		state.ree_income_rate = district.type_config.ree_rate
		state.research_income_rate = district.type_config.research_rate

	return state


## Apply state to a District instance.
func apply_to_district(district: District) -> void:
	district.owner_faction = owner_faction
	district.control_level = control_level
	district.capture_progress = capture_progress.duplicate()
	district.district_type = district_type
	district.is_contested = is_contested
	district.unit_presence = unit_presence.duplicate()


## Get effective income modifier based on building destruction.
func get_building_modifier() -> float:
	if total_buildings <= 0:
		return 1.0
	var remaining := total_buildings - destroyed_buildings
	return float(remaining) / float(total_buildings)


## Get effective power income rate.
func get_effective_power_rate() -> float:
	return power_income_rate * get_building_modifier() * control_level


## Get effective REE income rate.
func get_effective_ree_rate() -> float:
	return ree_income_rate * get_building_modifier() * control_level


## Get effective research income rate.
func get_effective_research_rate() -> float:
	return research_income_rate * get_building_modifier() * control_level


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"string_id": string_id,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"owner_faction": owner_faction,
		"control_level": control_level,
		"capture_progress": capture_progress.duplicate(),
		"district_type": district_type,
		"is_contested": is_contested,
		"unit_presence": unit_presence.duplicate(),
		"building_counts": building_counts.duplicate(),
		"total_buildings": total_buildings,
		"destroyed_buildings": destroyed_buildings,
		"power_income_rate": power_income_rate,
		"ree_income_rate": ree_income_rate,
		"research_income_rate": research_income_rate,
		"last_update_time": last_update_time
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> DistrictState:
	var state := DistrictState.new()
	state.id = data.get("id", -1)
	state.string_id = data.get("string_id", "")
	state.grid_x = data.get("grid_x", 0)
	state.grid_y = data.get("grid_y", 0)
	state.owner_faction = data.get("owner_faction", "")
	state.control_level = data.get("control_level", 0.0)
	state.capture_progress = data.get("capture_progress", {}).duplicate()
	state.district_type = data.get("district_type", DistrictType.Type.MIXED)
	state.is_contested = data.get("is_contested", false)
	state.unit_presence = data.get("unit_presence", {}).duplicate()
	state.building_counts = data.get("building_counts", {}).duplicate()
	state.total_buildings = data.get("total_buildings", 0)
	state.destroyed_buildings = data.get("destroyed_buildings", 0)
	state.power_income_rate = data.get("power_income_rate", 0.0)
	state.ree_income_rate = data.get("ree_income_rate", 0.0)
	state.research_income_rate = data.get("research_income_rate", 0.0)
	state.last_update_time = data.get("last_update_time", 0)
	return state


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": string_id,
		"owner": owner_faction if not owner_faction.is_empty() else "uncaptured",
		"control": "%.0f%%" % (control_level * 100),
		"type": DistrictType.get_type_name(district_type),
		"buildings": "%d/%d" % [total_buildings - destroyed_buildings, total_buildings],
		"contested": is_contested
	}
