class_name CameraController
extends RefCounted
## CameraController manages camera movement, zoom, and mode transitions.
## Supports strategic, tactical, and factory view modes.

signal camera_moved(position: Vector3)
signal zoom_changed(zoom_level: float)
signal mode_changed(old_mode: int, new_mode: int)
signal transition_started(from_mode: int, to_mode: int)
signal transition_completed(mode: int)

## Camera modes
enum CameraMode {
	STRATEGIC,   ## God-view, wide FOV
	TACTICAL,    ## Mid-range, unit management
	FACTORY      ## Close-up, factory detail
}

## Mode configurations
const MODE_CONFIGS := {
	CameraMode.STRATEGIC: {
		"height": 150.0,
		"fov": 60.0,
		"pitch": -70.0,
		"zoom_min": 100.0,
		"zoom_max": 250.0
	},
	CameraMode.TACTICAL: {
		"height": 75.0,
		"fov": 50.0,
		"pitch": -55.0,
		"zoom_min": 40.0,
		"zoom_max": 120.0
	},
	CameraMode.FACTORY: {
		"height": 25.0,
		"fov": 40.0,
		"pitch": -40.0,
		"zoom_min": 15.0,
		"zoom_max": 50.0
	}
}

## Movement settings
const PAN_SPEED := 50.0
const ZOOM_SPEED := 10.0
const KEYBOARD_PAN_SPEED := 100.0
const TRANSITION_DURATION := 0.5

## Camera bounds
var bounds_min := Vector3(-256, 0, -256)
var bounds_max := Vector3(768, 300, 768)

## Current state
var _mode: CameraMode = CameraMode.TACTICAL
var _position := Vector3(256, 75, 256)
var _target_position := Vector3(256, 75, 256)
var _zoom_level := 1.0
var _pitch := -55.0
var _yaw := 0.0

## Transition state
var _is_transitioning := false
var _transition_progress := 0.0
var _transition_start_pos := Vector3.ZERO
var _transition_end_pos := Vector3.ZERO
var _transition_start_zoom := 1.0
var _transition_end_zoom := 1.0
var _transition_start_pitch := 0.0
var _transition_end_pitch := 0.0

## Follow mode
var _follow_target_id := -1
var _follow_offset := Vector3.ZERO
var _is_following := false

## Input state
var _is_panning := false
var _pan_start := Vector2.ZERO
var _last_mouse_pos := Vector2.ZERO


func _init() -> void:
	_apply_mode_config(_mode)


## Update camera (call each frame).
func update(delta: float) -> void:
	if _is_transitioning:
		_update_transition(delta)
	else:
		_update_movement(delta)


## Update transition animation.
func _update_transition(delta: float) -> void:
	_transition_progress += delta / TRANSITION_DURATION

	if _transition_progress >= 1.0:
		_transition_progress = 1.0
		_is_transitioning = false
		_position = _transition_end_pos
		_zoom_level = _transition_end_zoom
		_pitch = _transition_end_pitch
		transition_completed.emit(_mode)
	else:
		# Ease out cubic
		var t := 1.0 - pow(1.0 - _transition_progress, 3)

		_position = _transition_start_pos.lerp(_transition_end_pos, t)
		_zoom_level = lerpf(_transition_start_zoom, _transition_end_zoom, t)
		_pitch = lerpf(_transition_start_pitch, _transition_end_pitch, t)

	camera_moved.emit(_position)


## Update normal camera movement.
func _update_movement(delta: float) -> void:
	# Smooth position interpolation
	if _position.distance_to(_target_position) > 0.1:
		_position = _position.lerp(_target_position, delta * 10.0)
		camera_moved.emit(_position)

	# Follow target
	if _is_following and _follow_target_id >= 0:
		# Target position would be updated by external system
		pass


## Set camera mode with transition.
func set_mode(new_mode: CameraMode, instant: bool = false) -> void:
	if new_mode == _mode:
		return

	var old_mode := _mode
	_mode = new_mode

	var config: Dictionary = MODE_CONFIGS[new_mode]

	if instant:
		_position.y = config["height"]
		_pitch = config["pitch"]
		_apply_mode_config(new_mode)
		mode_changed.emit(old_mode, new_mode)
	else:
		_start_transition(config)
		transition_started.emit(old_mode, new_mode)
		mode_changed.emit(old_mode, new_mode)


## Start camera transition.
func _start_transition(target_config: Dictionary) -> void:
	_is_transitioning = true
	_transition_progress = 0.0

	_transition_start_pos = _position
	_transition_end_pos = Vector3(_position.x, target_config["height"], _position.z)

	_transition_start_zoom = _zoom_level
	_transition_end_zoom = 1.0

	_transition_start_pitch = _pitch
	_transition_end_pitch = target_config["pitch"]


## Apply mode configuration.
func _apply_mode_config(mode: CameraMode) -> void:
	var config: Dictionary = MODE_CONFIGS[mode]
	_position.y = config["height"]
	_pitch = config["pitch"]


## Pan camera by delta.
func pan(delta: Vector2) -> void:
	if _is_transitioning:
		return

	var pan_amount := delta * PAN_SPEED * _zoom_level
	_target_position.x += pan_amount.x
	_target_position.z += pan_amount.y

	_clamp_to_bounds()


## Pan with keyboard input.
func pan_keyboard(direction: Vector2, delta: float) -> void:
	if _is_transitioning:
		return

	var pan_amount := direction * KEYBOARD_PAN_SPEED * delta * _zoom_level
	_target_position.x += pan_amount.x
	_target_position.z += pan_amount.y

	_clamp_to_bounds()


## Zoom camera.
func zoom(amount: float) -> void:
	if _is_transitioning:
		return

	var config: Dictionary = MODE_CONFIGS[_mode]
	var old_zoom := _zoom_level

	_zoom_level = clampf(
		_zoom_level - amount * ZOOM_SPEED * 0.1,
		config["zoom_min"] / config["height"],
		config["zoom_max"] / config["height"]
	)

	# Adjust height based on zoom
	_target_position.y = config["height"] * _zoom_level
	_position.y = _target_position.y

	if old_zoom != _zoom_level:
		zoom_changed.emit(_zoom_level)


## Set zoom level directly.
func set_zoom(level: float) -> void:
	var config: Dictionary = MODE_CONFIGS[_mode]

	_zoom_level = clampf(
		level,
		config["zoom_min"] / config["height"],
		config["zoom_max"] / config["height"]
	)

	_target_position.y = config["height"] * _zoom_level
	_position.y = _target_position.y
	zoom_changed.emit(_zoom_level)


## Move camera to position.
func move_to(position: Vector3, instant: bool = false) -> void:
	_target_position = Vector3(position.x, _target_position.y, position.z)
	_clamp_to_bounds()

	if instant:
		_position = _target_position
		camera_moved.emit(_position)


## Focus on position with zoom.
func focus_on(position: Vector3, zoom_level: float = -1.0) -> void:
	move_to(position)

	if zoom_level > 0:
		set_zoom(zoom_level)


## Start following a target.
func follow_target(target_id: int, offset: Vector3 = Vector3.ZERO) -> void:
	_follow_target_id = target_id
	_follow_offset = offset
	_is_following = true


## Stop following.
func stop_following() -> void:
	_is_following = false
	_follow_target_id = -1


## Update follow target position.
func update_follow_position(position: Vector3) -> void:
	if _is_following:
		_target_position = position + _follow_offset
		_target_position.y = _position.y
		_clamp_to_bounds()


## Clamp position to bounds.
func _clamp_to_bounds() -> void:
	_target_position.x = clampf(_target_position.x, bounds_min.x, bounds_max.x)
	_target_position.z = clampf(_target_position.z, bounds_min.z, bounds_max.z)


## Set camera bounds.
func set_bounds(min_pos: Vector3, max_pos: Vector3) -> void:
	bounds_min = min_pos
	bounds_max = max_pos
	_clamp_to_bounds()


## Get camera transform for Camera3D.
func get_camera_transform() -> Transform3D:
	var transform := Transform3D.IDENTITY
	transform.origin = _position

	# Apply rotation
	var rotation := Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0)
	transform.basis = Basis.from_euler(rotation)

	return transform


## Get view frustum for culling.
func get_view_frustum() -> Array[Plane]:
	# Simplified frustum calculation
	var frustum: Array[Plane] = []

	var config: Dictionary = MODE_CONFIGS[_mode]
	var fov_rad := deg_to_rad(config["fov"])
	var aspect := 16.0 / 9.0  # Assume 16:9

	# Near and far planes
	frustum.append(Plane(Vector3(0, 0, -1), -1.0))      # Near
	frustum.append(Plane(Vector3(0, 0, 1), 500.0))     # Far

	return frustum


## Get current mode.
func get_mode() -> CameraMode:
	return _mode


## Get current position.
func get_position() -> Vector3:
	return _position


## Get target position.
func get_target_position() -> Vector3:
	return _target_position


## Get zoom level.
func get_zoom_level() -> float:
	return _zoom_level


## Get pitch angle.
func get_pitch() -> float:
	return _pitch


## Get FOV for current mode.
func get_fov() -> float:
	return MODE_CONFIGS[_mode]["fov"]


## Check if transitioning.
func is_transitioning() -> bool:
	return _is_transitioning


## Check if following.
func is_following() -> bool:
	return _is_following


## Cancel current transition.
func cancel_transition() -> void:
	_is_transitioning = false


## Get camera state.
func get_state() -> CameraState:
	var state := CameraState.new()
	state.mode = _mode
	state.position = _position
	state.target_position = _target_position
	state.zoom_level = _zoom_level
	state.pitch = _pitch
	state.yaw = _yaw
	return state


## Restore camera state.
func restore_state(state: CameraState) -> void:
	_mode = state.mode
	_position = state.position
	_target_position = state.target_position
	_zoom_level = state.zoom_level
	_pitch = state.pitch
	_yaw = state.yaw


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"mode": _mode,
		"position": _position,
		"zoom_level": _zoom_level,
		"pitch": _pitch,
		"is_transitioning": _is_transitioning,
		"is_following": _is_following,
		"follow_target": _follow_target_id
	}
