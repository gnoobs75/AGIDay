class_name VisionSource
extends RefCounted
## VisionSource is a unified interface for anything that grants vision.
## Supports units, structures, and temporary abilities.

signal vision_changed(source_id: int)
signal source_activated(source_id: int)
signal source_deactivated(source_id: int)

## Source types
enum SourceType {
	UNIT,
	STRUCTURE,
	ABILITY,
	CONSUMABLE
}

## Vision modes
enum VisionMode {
	CONTINUOUS,  ## Always active
	PERIODIC,    ## Scans at intervals
	ONE_SHOT     ## Single reveal then expires
}

## Source properties
var source_id: int = -1
var faction_id: String = ""
var source_type: int = SourceType.UNIT
var vision_mode: int = VisionMode.CONTINUOUS

## Vision properties
var position: Vector3 = Vector3.ZERO
var vision_range: float = 10.0
var vision_height: float = 2.0
var ignores_line_of_sight: bool = false
var can_detect_stealth: bool = false

## State
var is_active: bool = true
var is_stealthed: bool = false

## Periodic scanning
var scan_interval: float = 0.0
var last_scan_time: float = 0.0

## Temporary sources
var duration: float = -1.0  ## -1 = permanent
var created_time: float = 0.0


func _init() -> void:
	created_time = Time.get_ticks_msec() / 1000.0


## Initialize as unit source.
func init_as_unit(p_source_id: int, p_faction_id: String, p_range: float) -> void:
	source_id = p_source_id
	faction_id = p_faction_id
	source_type = SourceType.UNIT
	vision_mode = VisionMode.CONTINUOUS
	vision_range = p_range


## Initialize as structure source.
func init_as_structure(p_source_id: int, p_faction_id: String, p_range: float, is_radar: bool = false) -> void:
	source_id = p_source_id
	faction_id = p_faction_id
	source_type = SourceType.STRUCTURE
	vision_range = p_range

	if is_radar:
		vision_mode = VisionMode.PERIODIC
		scan_interval = 2.0
		ignores_line_of_sight = true
	else:
		vision_mode = VisionMode.CONTINUOUS


## Initialize as ability source.
func init_as_ability(p_source_id: int, p_faction_id: String, p_range: float, p_duration: float) -> void:
	source_id = p_source_id
	faction_id = p_faction_id
	source_type = SourceType.ABILITY
	vision_mode = VisionMode.ONE_SHOT
	vision_range = p_range
	duration = p_duration


## Check if source is currently providing vision.
func is_providing_vision() -> bool:
	if not is_active:
		return false

	if is_stealthed:
		return false

	# Check if expired
	if duration > 0:
		var age := (Time.get_ticks_msec() / 1000.0) - created_time
		if age > duration:
			return false

	return true


## Check if should scan now (for periodic sources).
func should_scan() -> bool:
	if vision_mode != VisionMode.PERIODIC:
		return is_providing_vision()

	if not is_providing_vision():
		return false

	var current_time := Time.get_ticks_msec() / 1000.0
	return current_time - last_scan_time >= scan_interval


## Mark scan completed.
func mark_scanned() -> void:
	last_scan_time = Time.get_ticks_msec() / 1000.0


## Activate source.
func activate() -> void:
	if not is_active:
		is_active = true
		source_activated.emit(source_id)
		vision_changed.emit(source_id)


## Deactivate source.
func deactivate() -> void:
	if is_active:
		is_active = false
		source_deactivated.emit(source_id)
		vision_changed.emit(source_id)


## Enter stealth.
func enter_stealth() -> void:
	if not is_stealthed:
		is_stealthed = true
		vision_changed.emit(source_id)


## Exit stealth.
func exit_stealth() -> void:
	if is_stealthed:
		is_stealthed = false
		vision_changed.emit(source_id)


## Update position.
func update_position(new_pos: Vector3) -> void:
	position = new_pos


## Check if source has expired.
func is_expired() -> bool:
	if duration <= 0:
		return false

	var age := (Time.get_ticks_msec() / 1000.0) - created_time
	return age > duration


## Serialization.
func to_dict() -> Dictionary:
	return {
		"source_id": source_id,
		"faction_id": faction_id,
		"source_type": source_type,
		"vision_mode": vision_mode,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"vision_range": vision_range,
		"vision_height": vision_height,
		"ignores_line_of_sight": ignores_line_of_sight,
		"can_detect_stealth": can_detect_stealth,
		"is_active": is_active,
		"is_stealthed": is_stealthed,
		"scan_interval": scan_interval,
		"last_scan_time": last_scan_time,
		"duration": duration,
		"created_time": created_time
	}


func from_dict(data: Dictionary) -> void:
	source_id = data.get("source_id", -1)
	faction_id = data.get("faction_id", "")
	source_type = data.get("source_type", SourceType.UNIT)
	vision_mode = data.get("vision_mode", VisionMode.CONTINUOUS)

	var pos: Dictionary = data.get("position", {})
	position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	vision_range = data.get("vision_range", 10.0)
	vision_height = data.get("vision_height", 2.0)
	ignores_line_of_sight = data.get("ignores_line_of_sight", false)
	can_detect_stealth = data.get("can_detect_stealth", false)
	is_active = data.get("is_active", true)
	is_stealthed = data.get("is_stealthed", false)
	scan_interval = data.get("scan_interval", 0.0)
	last_scan_time = data.get("last_scan_time", 0.0)
	duration = data.get("duration", -1.0)
	created_time = data.get("created_time", 0.0)
