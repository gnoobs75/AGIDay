class_name VisionComponent
extends RefCounted
## VisionComponent provides unit vision properties and calculations.

signal vision_range_changed(old_range: float, new_range: float)
signal vision_blocked(blocker_position: Vector3)

## Vision types
enum VisionType {
	GROUND,  ## Standard ground vision
	AIR,     ## Air unit vision (can see over buildings)
	THERMAL  ## Can see through some obstacles
}

## Faction vision multipliers
const FACTION_VISION_MULTIPLIERS := {
	"AETHER_SWARM": 1.0,
	"OPTIFORGE_LEGION": 1.1,
	"DYNAPODS_VANGUARD": 1.05,
	"LOGIBOTS_COLOSSUS": 0.95
}

## Unit type base vision ranges
const UNIT_VISION_RANGES := {
	"nanoreaplet": 6.0,
	"spikelet": 7.0,
	"buzzblade": 10.0,
	"wispfire": 8.0,
	"scout_tank": 8.0,
	"main_tank": 6.0,
	"artillery": 12.0,
	"scout": 9.0,
	"warrior": 7.0,
	"flyer": 11.0,
	"heavy_unit": 5.0,
	"colossus": 6.0,
	"sensor": 10.0,
	"default": 7.0
}

## Component properties
var unit_id: int = -1
var faction_id: String = ""
var unit_type: String = ""

## Vision properties
var base_vision_range: float = 7.0
var vision_range: float = 7.0  ## Effective range after multipliers
var vision_height: float = 2.0
var vision_type: int = VisionType.GROUND

## Special properties
var can_see_through_buildings: bool = false
var can_see_stealth: bool = false

## Cached position
var position: Vector3 = Vector3.ZERO

## Vision modifier stack (source -> multiplier)
var _modifiers: Dictionary = {}


func _init() -> void:
	pass


## Initialize component.
func initialize(p_unit_id: int, p_faction_id: String, p_unit_type: String) -> void:
	unit_id = p_unit_id
	faction_id = p_faction_id
	unit_type = p_unit_type

	# Set base vision range from unit type
	base_vision_range = UNIT_VISION_RANGES.get(unit_type.to_lower(), UNIT_VISION_RANGES["default"])

	# Set vision type based on unit
	if unit_type.to_lower() in ["flyer", "wispfire"]:
		vision_type = VisionType.AIR
		vision_height = 10.0
	elif unit_type.to_lower() in ["sensor"]:
		can_see_stealth = true

	# Special properties
	if unit_type.to_lower() in ["artillery", "sensor"]:
		can_see_through_buildings = false  ## Actually needs LOS

	_recalculate_vision_range()


## Recalculate effective vision range.
func _recalculate_vision_range() -> void:
	var old_range := vision_range

	# Start with base range
	var effective := base_vision_range

	# Apply faction multiplier
	var faction_mult := FACTION_VISION_MULTIPLIERS.get(faction_id, 1.0)
	effective *= faction_mult

	# Apply modifiers
	for source in _modifiers:
		effective *= _modifiers[source]

	vision_range = effective

	if abs(vision_range - old_range) > 0.01:
		vision_range_changed.emit(old_range, vision_range)


## Add vision modifier.
func add_modifier(source: String, multiplier: float) -> void:
	_modifiers[source] = multiplier
	_recalculate_vision_range()


## Remove vision modifier.
func remove_modifier(source: String) -> void:
	_modifiers.erase(source)
	_recalculate_vision_range()


## Update position.
func update_position(new_position: Vector3) -> void:
	position = new_position


## Get vision range in voxels.
func get_vision_range_voxels() -> int:
	return int(ceil(vision_range))


## Check if position is within vision range.
func is_in_range(target_pos: Vector3) -> bool:
	var distance := position.distance_to(target_pos)
	return distance <= vision_range


## Get effective vision height for LOS calculations.
func get_effective_height() -> float:
	return position.y + vision_height


## Serialization.
func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"base_vision_range": base_vision_range,
		"vision_range": vision_range,
		"vision_height": vision_height,
		"vision_type": vision_type,
		"can_see_through_buildings": can_see_through_buildings,
		"can_see_stealth": can_see_stealth,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"modifiers": _modifiers.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	unit_id = data.get("unit_id", -1)
	faction_id = data.get("faction_id", "")
	unit_type = data.get("unit_type", "")
	base_vision_range = data.get("base_vision_range", 7.0)
	vision_range = data.get("vision_range", 7.0)
	vision_height = data.get("vision_height", 2.0)
	vision_type = data.get("vision_type", VisionType.GROUND)
	can_see_through_buildings = data.get("can_see_through_buildings", false)
	can_see_stealth = data.get("can_see_stealth", false)

	var pos: Dictionary = data.get("position", {})
	position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	_modifiers = data.get("modifiers", {}).duplicate()
