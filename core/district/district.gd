class_name DistrictZone
extends RefCounted
## DistrictZone represents a territorial control zone in the city.

signal ownership_changed(district_id: int, old_faction: String, new_faction: String)
signal district_captured(district_id: int, capturing_faction: String)
signal contested_started(district_id: int)
signal contested_ended(district_id: int)
signal power_state_changed(district_id: int, has_power: bool)
signal income_generated(district_id: int, ree: float, power: float)

## District size in voxels
const DISTRICT_SIZE := 64

## District types
enum DistrictType {
	RESIDENTIAL,
	INDUSTRIAL,
	COMMERCIAL,
	CORNER,       ## Power plant location
	EDGE,         ## Resource nodes
	CENTER        ## Strategic importance
}

## District identity
var district_id: int = -1
var district_name: String = ""
var district_type: int = DistrictType.RESIDENTIAL

## Boundaries (voxel coordinates)
var bounds_min: Vector3i = Vector3i.ZERO
var bounds_max: Vector3i = Vector3i.ZERO
var center_position: Vector3 = Vector3.ZERO

## Ownership
var owning_faction: String = ""
var contested: bool = false
var capture_progress: float = 0.0

## Power state
var has_power: bool = true
var power_consumption: float = 50.0
var power_received: float = 0.0

## Resource generation
var ree_generation_rate: float = 0.0
var power_generation_rate: float = 0.0

## Units and buildings tracking
var friendly_unit_count: int = 0
var enemy_unit_count: int = 0
var building_count: int = 0

## Strategic value
var strategic_value: float = 1.0


func _init() -> void:
	pass


## Initialize district.
func initialize(p_id: int, p_name: String, p_type: int, min_bounds: Vector3i, max_bounds: Vector3i) -> void:
	district_id = p_id
	district_name = p_name
	district_type = p_type
	bounds_min = min_bounds
	bounds_max = max_bounds

	# Calculate center
	center_position = Vector3(
		float(bounds_min.x + bounds_max.x) / 2.0,
		float(bounds_min.y + bounds_max.y) / 2.0,
		float(bounds_min.z + bounds_max.z) / 2.0
	)

	# Set type-specific defaults
	_configure_by_type()


## Configure district based on type.
func _configure_by_type() -> void:
	match district_type:
		DistrictType.RESIDENTIAL:
			power_consumption = 30.0
			strategic_value = 0.5
		DistrictType.INDUSTRIAL:
			power_consumption = 100.0
			strategic_value = 1.5
		DistrictType.COMMERCIAL:
			power_consumption = 50.0
			strategic_value = 1.0
		DistrictType.CORNER:
			power_consumption = 20.0
			power_generation_rate = 1000.0  # Power plant location
			strategic_value = 2.0
		DistrictType.EDGE:
			power_consumption = 40.0
			ree_generation_rate = 10.0  # Resource nodes
			strategic_value = 1.5
		DistrictType.CENTER:
			power_consumption = 75.0
			strategic_value = 2.5


## Check if position is within district bounds.
func contains_position(position: Vector3) -> bool:
	var vi := Vector3i(int(floor(position.x)), int(floor(position.y)), int(floor(position.z)))
	return contains_voxel(vi)


## Check if voxel is within district bounds.
func contains_voxel(voxel: Vector3i) -> bool:
	return (voxel.x >= bounds_min.x and voxel.x <= bounds_max.x and
			voxel.y >= bounds_min.y and voxel.y <= bounds_max.y and
			voxel.z >= bounds_min.z and voxel.z <= bounds_max.z)


## Set owning faction.
func set_owning_faction(faction_id: String) -> void:
	if owning_faction == faction_id:
		return

	var old_faction := owning_faction
	owning_faction = faction_id
	ownership_changed.emit(district_id, old_faction, faction_id)


## Capture district.
func capture(capturing_faction: String) -> void:
	set_owning_faction(capturing_faction)
	contested = false
	capture_progress = 0.0
	district_captured.emit(district_id, capturing_faction)


## Set contested state.
func set_contested(is_contested: bool) -> void:
	if contested == is_contested:
		return

	contested = is_contested
	if contested:
		contested_started.emit(district_id)
	else:
		contested_ended.emit(district_id)


## Update power state.
func set_power_state(powered: bool, received: float = 0.0) -> void:
	power_received = received
	if has_power != powered:
		has_power = powered
		power_state_changed.emit(district_id, powered)


## Update unit counts.
func update_unit_counts(friendly: int, enemy: int) -> void:
	friendly_unit_count = friendly
	enemy_unit_count = enemy

	# Update contested state
	set_contested(friendly > 0 and enemy > 0)


## Check capture conditions.
func check_capture_conditions(attacking_faction: String) -> bool:
	# Capture when all enemy units and buildings are eliminated
	if owning_faction.is_empty():
		return friendly_unit_count > 0
	elif attacking_faction != owning_faction:
		return enemy_unit_count == 0 and building_count == 0
	return false


## Generate income (call each update).
func generate_income(delta: float) -> Dictionary:
	if owning_faction.is_empty() or not has_power:
		return {"ree": 0.0, "power": 0.0}

	var ree := ree_generation_rate * delta
	var power := power_generation_rate * delta

	if ree > 0.0 or power > 0.0:
		income_generated.emit(district_id, ree, power)

	return {"ree": ree, "power": power}


## Get income multiplier (affected by power state and contested).
func get_income_multiplier() -> float:
	var multiplier := 1.0

	if not has_power:
		multiplier *= 0.0  # No income without power
	elif contested:
		multiplier *= 0.5  # Half income when contested

	return multiplier


## Get production multiplier (affected by power).
func get_production_multiplier() -> float:
	if not has_power:
		return 0.0
	return 1.0


## Get type name.
func get_type_name() -> String:
	match district_type:
		DistrictType.RESIDENTIAL:
			return "residential"
		DistrictType.INDUSTRIAL:
			return "industrial"
		DistrictType.COMMERCIAL:
			return "commercial"
		DistrictType.CORNER:
			return "corner"
		DistrictType.EDGE:
			return "edge"
		DistrictType.CENTER:
			return "center"
		_:
			return "unknown"


## Serialization.
func to_dict() -> Dictionary:
	return {
		"district_id": district_id,
		"district_name": district_name,
		"district_type": district_type,
		"bounds_min": {"x": bounds_min.x, "y": bounds_min.y, "z": bounds_min.z},
		"bounds_max": {"x": bounds_max.x, "y": bounds_max.y, "z": bounds_max.z},
		"owning_faction": owning_faction,
		"contested": contested,
		"capture_progress": capture_progress,
		"has_power": has_power,
		"power_consumption": power_consumption,
		"power_received": power_received,
		"ree_generation_rate": ree_generation_rate,
		"power_generation_rate": power_generation_rate,
		"strategic_value": strategic_value,
		"friendly_unit_count": friendly_unit_count,
		"enemy_unit_count": enemy_unit_count,
		"building_count": building_count
	}


func from_dict(data: Dictionary) -> void:
	district_id = data.get("district_id", -1)
	district_name = data.get("district_name", "")
	district_type = data.get("district_type", DistrictType.RESIDENTIAL)

	var bmin: Dictionary = data.get("bounds_min", {})
	bounds_min = Vector3i(bmin.get("x", 0), bmin.get("y", 0), bmin.get("z", 0))

	var bmax: Dictionary = data.get("bounds_max", {})
	bounds_max = Vector3i(bmax.get("x", 0), bmax.get("y", 0), bmax.get("z", 0))

	center_position = Vector3(
		float(bounds_min.x + bounds_max.x) / 2.0,
		float(bounds_min.y + bounds_max.y) / 2.0,
		float(bounds_min.z + bounds_max.z) / 2.0
	)

	owning_faction = data.get("owning_faction", "")
	contested = data.get("contested", false)
	capture_progress = data.get("capture_progress", 0.0)
	has_power = data.get("has_power", true)
	power_consumption = data.get("power_consumption", 50.0)
	power_received = data.get("power_received", 0.0)
	ree_generation_rate = data.get("ree_generation_rate", 0.0)
	power_generation_rate = data.get("power_generation_rate", 0.0)
	strategic_value = data.get("strategic_value", 1.0)
	friendly_unit_count = data.get("friendly_unit_count", 0)
	enemy_unit_count = data.get("enemy_unit_count", 0)
	building_count = data.get("building_count", 0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": district_id,
		"name": district_name,
		"type": get_type_name(),
		"faction": owning_faction,
		"contested": contested,
		"has_power": has_power,
		"power_ratio": power_received / power_consumption if power_consumption > 0 else 1.0,
		"ree_rate": ree_generation_rate,
		"power_rate": power_generation_rate,
		"value": strategic_value
	}
