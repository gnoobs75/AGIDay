class_name FactoryCameraController
extends RefCounted
## FactoryCameraController manages camera transitions between overview and detail views.

signal zoom_started(from_level: float, to_level: float)
signal zoom_completed(level: float)
signal zoom_progress(level: float)
signal factory_targeted(factory_id: int)
signal factory_target_cleared()
signal transition_started()
signal transition_completed()

## Zoom levels
const ZOOM_OVERVIEW := 0.0
const ZOOM_TACTICAL := 0.5
const ZOOM_DETAIL := 1.0

## Default transition timing
const DEFAULT_TRANSITION_TIME := 1.0
const MIN_TRANSITION_TIME := 0.2
const MAX_TRANSITION_TIME := 3.0

## Camera positions for each view mode
var _overview_position := Vector3(0, 100, 50)
var _overview_rotation := Vector3(-60, 0, 0)  ## Degrees
var _overview_fov := 60.0

var _detail_offset := Vector3(0, 10, 8)  ## Offset from factory
var _detail_rotation := Vector3(-45, 0, 0)  ## Degrees
var _detail_fov := 45.0

## Current state
var _current_zoom: float = ZOOM_OVERVIEW
var _target_zoom: float = ZOOM_OVERVIEW
var _is_transitioning: bool = false
var _transition_progress: float = 0.0
var _transition_time: float = DEFAULT_TRANSITION_TIME

## Camera reference
var _camera: Camera3D = null

## Target tracking
var _target_factory_id: int = -1
var _target_factory_position := Vector3.ZERO

## Interpolated values
var _current_position := Vector3.ZERO
var _current_rotation := Vector3.ZERO
var _current_fov := 60.0

## Transition start values
var _start_position := Vector3.ZERO
var _start_rotation := Vector3.ZERO
var _start_fov := 60.0

## Transition end values
var _end_position := Vector3.ZERO
var _end_rotation := Vector3.ZERO
var _end_fov := 60.0


func _init() -> void:
	_current_position = _overview_position
	_current_rotation = _overview_rotation
	_current_fov = _overview_fov


## Set camera reference.
func set_camera(camera: Camera3D) -> void:
	_camera = camera
	_apply_camera_state()


## Set overview camera settings.
func set_overview_settings(position: Vector3, rotation: Vector3, fov: float) -> void:
	_overview_position = position
	_overview_rotation = rotation
	_overview_fov = fov


## Set detail camera settings.
func set_detail_settings(offset: Vector3, rotation: Vector3, fov: float) -> void:
	_detail_offset = offset
	_detail_rotation = rotation
	_detail_fov = fov


## Set transition time.
func set_transition_time(time: float) -> void:
	_transition_time = clampf(time, MIN_TRANSITION_TIME, MAX_TRANSITION_TIME)


## Zoom to specific level.
func zoom_to(target_level: float) -> void:
	target_level = clampf(target_level, 0.0, 1.0)

	if is_equal_approx(target_level, _current_zoom):
		return

	_start_transition(target_level)


## Zoom to overview.
func zoom_to_overview() -> void:
	zoom_to(ZOOM_OVERVIEW)


## Zoom to tactical.
func zoom_to_tactical() -> void:
	zoom_to(ZOOM_TACTICAL)


## Zoom to detail.
func zoom_to_detail() -> void:
	zoom_to(ZOOM_DETAIL)


## Target a specific factory for detail view.
func target_factory(factory_id: int, factory_position: Vector3) -> void:
	_target_factory_id = factory_id
	_target_factory_position = factory_position

	factory_targeted.emit(factory_id)

	# If already in detail view, transition to new factory
	if _current_zoom >= ZOOM_TACTICAL:
		_start_transition(_target_zoom)


## Clear factory target.
func clear_target() -> void:
	_target_factory_id = -1
	_target_factory_position = Vector3.ZERO

	factory_target_cleared.emit()


## Start a zoom transition.
func _start_transition(target_level: float) -> void:
	var old_zoom := _current_zoom
	_target_zoom = target_level
	_transition_progress = 0.0
	_is_transitioning = true

	# Store start values
	_start_position = _current_position
	_start_rotation = _current_rotation
	_start_fov = _current_fov

	# Calculate end values
	_calculate_end_state(target_level)

	transition_started.emit()
	zoom_started.emit(old_zoom, target_level)


## Calculate end camera state for target zoom level.
func _calculate_end_state(zoom_level: float) -> void:
	if zoom_level <= 0.0:
		# Pure overview
		_end_position = _overview_position
		_end_rotation = _overview_rotation
		_end_fov = _overview_fov
	elif zoom_level >= 1.0:
		# Pure detail
		if _target_factory_id >= 0:
			_end_position = _target_factory_position + _detail_offset
		else:
			_end_position = _detail_offset
		_end_rotation = _detail_rotation
		_end_fov = _detail_fov
	else:
		# Interpolate between overview and detail
		var detail_pos := _target_factory_position + _detail_offset if _target_factory_id >= 0 else _detail_offset

		_end_position = _overview_position.lerp(detail_pos, zoom_level)
		_end_rotation = _overview_rotation.lerp(_detail_rotation, zoom_level)
		_end_fov = lerpf(_overview_fov, _detail_fov, zoom_level)


## Update camera transition (call each frame).
func update(delta: float) -> void:
	if not _is_transitioning:
		return

	# Advance transition
	_transition_progress += delta / _transition_time
	_transition_progress = minf(_transition_progress, 1.0)

	# Use smooth step for nicer easing
	var t := _smooth_step(_transition_progress)

	# Interpolate current values
	_current_position = _start_position.lerp(_end_position, t)
	_current_rotation = _start_rotation.lerp(_end_rotation, t)
	_current_fov = lerpf(_start_fov, _end_fov, t)
	_current_zoom = lerpf(_current_zoom, _target_zoom, t)

	# Apply to camera
	_apply_camera_state()

	zoom_progress.emit(_current_zoom)

	# Check completion
	if _transition_progress >= 1.0:
		_complete_transition()


## Smooth step easing function.
func _smooth_step(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Complete the current transition.
func _complete_transition() -> void:
	_is_transitioning = false
	_current_zoom = _target_zoom
	_current_position = _end_position
	_current_rotation = _end_rotation
	_current_fov = _end_fov

	_apply_camera_state()

	transition_completed.emit()
	zoom_completed.emit(_current_zoom)


## Apply current state to camera.
func _apply_camera_state() -> void:
	if _camera == null:
		return

	_camera.position = _current_position
	_camera.rotation_degrees = _current_rotation
	_camera.fov = _current_fov


## Cancel current transition.
func cancel_transition() -> void:
	if _is_transitioning:
		_is_transitioning = false
		_target_zoom = _current_zoom


## Instant zoom (no transition).
func instant_zoom(level: float) -> void:
	_current_zoom = clampf(level, 0.0, 1.0)
	_target_zoom = _current_zoom
	_calculate_end_state(_current_zoom)

	_current_position = _end_position
	_current_rotation = _end_rotation
	_current_fov = _end_fov

	_apply_camera_state()

	zoom_completed.emit(_current_zoom)


## Get current zoom level.
func get_zoom_level() -> float:
	return _current_zoom


## Get target zoom level.
func get_target_zoom() -> float:
	return _target_zoom


## Check if transitioning.
func is_transitioning() -> bool:
	return _is_transitioning


## Get transition progress (0.0 to 1.0).
func get_transition_progress() -> float:
	return _transition_progress


## Get target factory ID.
func get_target_factory_id() -> int:
	return _target_factory_id


## Check if factory is targeted.
func has_target() -> bool:
	return _target_factory_id >= 0


## Check if in overview mode.
func is_overview_mode() -> bool:
	return _current_zoom < 0.3 and not _is_transitioning


## Check if in detail mode.
func is_detail_mode() -> bool:
	return _current_zoom > 0.7 and not _is_transitioning


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"current_zoom": _current_zoom,
		"target_zoom": _target_zoom,
		"is_transitioning": _is_transitioning,
		"transition_progress": _transition_progress,
		"target_factory_id": _target_factory_id,
		"camera_position": _current_position,
		"camera_rotation": _current_rotation,
		"camera_fov": _current_fov,
		"has_camera": _camera != null
	}
