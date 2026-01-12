class_name District
extends RefCounted
## District represents a single 64x64 voxel territory on the map.
## The map is divided into 64 districts in an 8x8 grid.

signal ownership_changed(old_owner: String, new_owner: String)
signal control_level_changed(old_level: float, new_level: float)
signal capture_progress_changed(progress: float)

## Map constants
const MAP_SIZE := 512
const GRID_SIZE := 8
const DISTRICT_SIZE := 64  # 512 / 8 = 64 voxels per district
const TOTAL_DISTRICTS := 64

## District ID (0-63)
var id: int = -1

## Grid position (0-7, 0-7)
var grid_x: int = 0
var grid_y: int = 0

## World position (center of district)
var world_position: Vector3 = Vector3.ZERO

## Owner faction ID (empty string = neutral)
var owner_faction: String = ""

## Control level (0.0 to 1.0, 1.0 = full control)
var control_level: float = 0.0

## Capture progress by faction (faction_id -> progress 0.0-1.0)
var capture_progress: Dictionary = {}

## District type
var district_type: int = DistrictType.Type.MIXED

## Type configuration
var type_config: DistrictTypeConfig = null

## Whether district is contested (multiple factions fighting)
var is_contested: bool = false

## Units in this district by faction (faction_id -> count)
var unit_presence: Dictionary = {}

## Total resources generated
var total_power_generated: float = 0.0
var total_ree_generated: float = 0.0
var total_research_generated: float = 0.0


func _init(p_id: int = -1) -> void:
	id = p_id
	if id >= 0:
		_calculate_positions()
	type_config = DistrictTypeConfig.new()
	type_config.initialize_for_type(district_type)


## Calculate grid and world positions from ID.
func _calculate_positions() -> void:
	grid_x = id % GRID_SIZE
	grid_y = id / GRID_SIZE

	# Calculate world position (center of district)
	var half_district := DISTRICT_SIZE / 2.0
	world_position = Vector3(
		grid_x * DISTRICT_SIZE + half_district,
		0.0,
		grid_y * DISTRICT_SIZE + half_district
	)


## Initialize district with ID and type.
func initialize(p_id: int, p_type: int = DistrictType.Type.MIXED) -> void:
	id = p_id
	district_type = p_type
	_calculate_positions()
	type_config = DistrictTypeConfig.new()
	type_config.initialize_for_type(district_type)


## Set owner faction.
func set_owner(faction_id: String) -> void:
	if faction_id == owner_faction:
		return
	var old_owner := owner_faction
	owner_faction = faction_id
	if not faction_id.is_empty():
		control_level = 1.0
	ownership_changed.emit(old_owner, owner_faction)


## Clear ownership (make neutral).
func clear_owner() -> void:
	set_owner("")
	control_level = 0.0
	capture_progress.clear()


## Check if district is neutral.
func is_neutral() -> bool:
	return owner_faction.is_empty()


## Check if owned by faction.
func is_owned_by(faction_id: String) -> bool:
	return owner_faction == faction_id


## Set control level.
func set_control_level(level: float) -> void:
	var old_level := control_level
	control_level = clampf(level, 0.0, 1.0)
	if absf(control_level - old_level) > 0.001:
		control_level_changed.emit(old_level, control_level)


## Add capture progress for a faction.
func add_capture_progress(faction_id: String, amount: float) -> void:
	var current: float = capture_progress.get(faction_id, 0.0)
	capture_progress[faction_id] = clampf(current + amount, 0.0, 1.0)
	capture_progress_changed.emit(capture_progress[faction_id])

	# Check if capture complete
	if capture_progress[faction_id] >= 1.0:
		set_owner(faction_id)
		capture_progress.clear()


## Get capture progress for a faction.
func get_capture_progress(faction_id: String) -> float:
	return capture_progress.get(faction_id, 0.0)


## Reset capture progress for a faction.
func reset_capture_progress(faction_id: String) -> void:
	capture_progress.erase(faction_id)


## Update unit presence.
func update_unit_presence(faction_id: String, count: int) -> void:
	if count <= 0:
		unit_presence.erase(faction_id)
	else:
		unit_presence[faction_id] = count

	# Update contested status
	is_contested = unit_presence.size() > 1


## Get unit count for faction.
func get_unit_count(faction_id: String) -> int:
	return unit_presence.get(faction_id, 0)


## Get total unit count in district.
func get_total_unit_count() -> int:
	var total := 0
	for count in unit_presence.values():
		total += count
	return total


## Check if world position is within this district.
func contains_position(pos: Vector3) -> bool:
	var min_x := grid_x * DISTRICT_SIZE
	var max_x := min_x + DISTRICT_SIZE
	var min_z := grid_y * DISTRICT_SIZE
	var max_z := min_z + DISTRICT_SIZE
	return pos.x >= min_x and pos.x < max_x and pos.z >= min_z and pos.z < max_z


## Get district bounds as AABB.
func get_bounds() -> AABB:
	var min_pos := Vector3(grid_x * DISTRICT_SIZE, 0, grid_y * DISTRICT_SIZE)
	var size := Vector3(DISTRICT_SIZE, 64, DISTRICT_SIZE)  # 64 height for voxels
	return AABB(min_pos, size)


## Generate resources for a time delta.
func generate_resources(delta: float, faction_modifier: float = 1.0) -> Dictionary:
	if is_neutral() or control_level <= 0:
		return {"power": 0.0, "ree": 0.0, "research": 0.0}

	var effective_modifier := control_level * faction_modifier

	var power := type_config.power_rate * delta * effective_modifier
	var ree := type_config.ree_rate * delta * effective_modifier
	var research := type_config.research_rate * delta * effective_modifier

	total_power_generated += power
	total_ree_generated += ree
	total_research_generated += research

	return {
		"power": power,
		"ree": ree,
		"research": research
	}


## Get type name.
func get_type_name() -> String:
	return DistrictType.get_type_name(district_type)


## Get neighbor district IDs.
func get_neighbor_ids() -> Array[int]:
	var neighbors: Array[int] = []

	# Left
	if grid_x > 0:
		neighbors.append(id - 1)
	# Right
	if grid_x < GRID_SIZE - 1:
		neighbors.append(id + 1)
	# Up
	if grid_y > 0:
		neighbors.append(id - GRID_SIZE)
	# Down
	if grid_y < GRID_SIZE - 1:
		neighbors.append(id + GRID_SIZE)

	return neighbors


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"owner_faction": owner_faction,
		"control_level": control_level,
		"capture_progress": capture_progress.duplicate(),
		"district_type": district_type,
		"is_contested": is_contested,
		"unit_presence": unit_presence.duplicate(),
		"total_power_generated": total_power_generated,
		"total_ree_generated": total_ree_generated,
		"total_research_generated": total_research_generated
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> District:
	var district := District.new()
	district.id = data.get("id", -1)
	district.grid_x = data.get("grid_x", 0)
	district.grid_y = data.get("grid_y", 0)
	district.owner_faction = data.get("owner_faction", "")
	district.control_level = data.get("control_level", 0.0)
	district.capture_progress = data.get("capture_progress", {}).duplicate()
	district.district_type = data.get("district_type", DistrictType.Type.MIXED)
	district.is_contested = data.get("is_contested", false)
	district.unit_presence = data.get("unit_presence", {}).duplicate()
	district.total_power_generated = data.get("total_power_generated", 0.0)
	district.total_ree_generated = data.get("total_ree_generated", 0.0)
	district.total_research_generated = data.get("total_research_generated", 0.0)

	district._calculate_positions()
	district.type_config = DistrictTypeConfig.new()
	district.type_config.initialize_for_type(district.district_type)

	return district


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"position": "(%d, %d)" % [grid_x, grid_y],
		"type": get_type_name(),
		"owner": owner_faction if not owner_faction.is_empty() else "neutral",
		"control": "%.0f%%" % (control_level * 100),
		"contested": is_contested,
		"units": get_total_unit_count()
	}
