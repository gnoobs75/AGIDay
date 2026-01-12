class_name CameraState
extends RefCounted
## CameraState data model for camera position, zoom, and selection state.
## Supports serialization for save files, replays, and network synchronization.

signal state_changed()

## Camera transform
var camera_position: Vector3 = Vector3.ZERO
var camera_rotation: Vector3 = Vector3.ZERO  ## Euler angles

## Zoom
var zoom_level: float = 1.0
const ZOOM_MIN := 0.25
const ZOOM_MAX := 4.0

## Selection state
var selected_factory_id: int = -1
var focused_entity_id: int = -1
var follow_target_id: int = -1

## View mode
enum ViewMode {
	FREE,           ## Free camera movement
	FACTORY_VIEW,   ## Zoomed into factory
	FOLLOW_UNIT,    ## Following a specific unit
	OVERVIEW        ## Strategic overview
}
var view_mode: int = ViewMode.FREE

## Constraints
var bounds_min: Vector3 = Vector3(-1000, -100, -1000)
var bounds_max: Vector3 = Vector3(1000, 100, 1000)

## Timestamp for synchronization ordering
var timestamp: int = 0


func _init() -> void:
	pass


## Set position with bounds checking.
func set_position(pos: Vector3) -> void:
	camera_position = pos.clamp(bounds_min, bounds_max)
	timestamp = Time.get_ticks_msec()
	state_changed.emit()


## Set rotation.
func set_rotation(rot: Vector3) -> void:
	camera_rotation = rot
	timestamp = Time.get_ticks_msec()
	state_changed.emit()


## Set zoom level with clamping.
func set_zoom(level: float) -> void:
	zoom_level = clampf(level, ZOOM_MIN, ZOOM_MAX)
	timestamp = Time.get_ticks_msec()
	state_changed.emit()


## Select a factory.
func select_factory(factory_id: int) -> void:
	selected_factory_id = factory_id
	if factory_id >= 0:
		view_mode = ViewMode.FACTORY_VIEW
	timestamp = Time.get_ticks_msec()
	state_changed.emit()


## Clear factory selection.
func clear_factory_selection() -> void:
	selected_factory_id = -1
	if view_mode == ViewMode.FACTORY_VIEW:
		view_mode = ViewMode.FREE
	timestamp = Time.get_ticks_msec()
	state_changed.emit()


## Focus on an entity.
func focus_entity(entity_id: int) -> void:
	focused_entity_id = entity_id
	timestamp = Time.get_ticks_msec()
	state_changed.emit()


## Start following a target.
func follow_target(target_id: int) -> void:
	follow_target_id = target_id
	if target_id >= 0:
		view_mode = ViewMode.FOLLOW_UNIT
	else:
		view_mode = ViewMode.FREE
	timestamp = Time.get_ticks_msec()
	state_changed.emit()


## Set view mode.
func set_view_mode(mode: int) -> void:
	view_mode = mode
	timestamp = Time.get_ticks_msec()
	state_changed.emit()


## Set camera bounds.
func set_bounds(min_bounds: Vector3, max_bounds: Vector3) -> void:
	bounds_min = min_bounds
	bounds_max = max_bounds
	# Re-clamp position
	camera_position = camera_position.clamp(bounds_min, bounds_max)


## Convert to dictionary for serialization.
func to_dict() -> Dictionary:
	return {
		"position": {
			"x": camera_position.x,
			"y": camera_position.y,
			"z": camera_position.z
		},
		"rotation": {
			"x": camera_rotation.x,
			"y": camera_rotation.y,
			"z": camera_rotation.z
		},
		"zoom_level": zoom_level,
		"selected_factory_id": selected_factory_id,
		"focused_entity_id": focused_entity_id,
		"follow_target_id": follow_target_id,
		"view_mode": view_mode,
		"timestamp": timestamp
	}


## Restore from dictionary.
func from_dict(data: Dictionary) -> void:
	var pos: Dictionary = data.get("position", {})
	camera_position = Vector3(
		pos.get("x", 0.0),
		pos.get("y", 0.0),
		pos.get("z", 0.0)
	)

	var rot: Dictionary = data.get("rotation", {})
	camera_rotation = Vector3(
		rot.get("x", 0.0),
		rot.get("y", 0.0),
		rot.get("z", 0.0)
	)

	zoom_level = data.get("zoom_level", 1.0)
	selected_factory_id = data.get("selected_factory_id", -1)
	focused_entity_id = data.get("focused_entity_id", -1)
	follow_target_id = data.get("follow_target_id", -1)
	view_mode = data.get("view_mode", ViewMode.FREE)
	timestamp = data.get("timestamp", 0)


## Create from dictionary (factory method).
static func create_from_dict(data: Dictionary) -> CameraState:
	var state := CameraState.new()
	state.from_dict(data)
	return state


## Clone this state.
func clone() -> CameraState:
	return CameraState.create_from_dict(to_dict())


## Check if this state is newer than another.
func is_newer_than(other: CameraState) -> bool:
	return timestamp > other.timestamp


## Interpolate between two camera states.
static func interpolate(from: CameraState, to: CameraState, t: float) -> CameraState:
	var result := CameraState.new()
	result.camera_position = from.camera_position.lerp(to.camera_position, t)
	result.camera_rotation = from.camera_rotation.lerp(to.camera_rotation, t)
	result.zoom_level = lerpf(from.zoom_level, to.zoom_level, t)

	# Non-interpolated values - use target state
	result.selected_factory_id = to.selected_factory_id
	result.focused_entity_id = to.focused_entity_id
	result.follow_target_id = to.follow_target_id
	result.view_mode = to.view_mode
	result.timestamp = to.timestamp

	return result


## Check if position/zoom has changed significantly.
func has_significant_change(other: CameraState, pos_threshold: float = 0.1, zoom_threshold: float = 0.01) -> bool:
	var pos_diff := camera_position.distance_to(other.camera_position)
	var zoom_diff := absf(zoom_level - other.zoom_level)

	return pos_diff > pos_threshold or zoom_diff > zoom_threshold


## Get view mode name.
func get_view_mode_name() -> String:
	match view_mode:
		ViewMode.FREE: return "free"
		ViewMode.FACTORY_VIEW: return "factory_view"
		ViewMode.FOLLOW_UNIT: return "follow_unit"
		ViewMode.OVERVIEW: return "overview"
		_: return "unknown"


## Debug string representation.
func _to_string() -> String:
	return "CameraState(pos=%s, zoom=%.2f, factory=%d, mode=%s)" % [
		camera_position, zoom_level, selected_factory_id, get_view_mode_name()
	]
