class_name CameraInputHandler
extends RefCounted
## CameraInputHandler manages input for camera zoom and factory selection.

signal zoom_in_requested()
signal zoom_out_requested()
signal zoom_to_level_requested(level: float)
signal factory_click_requested(screen_position: Vector2)
signal back_requested()

## Input action names (can be customized)
var action_zoom_in := "camera_zoom_in"
var action_zoom_out := "camera_zoom_out"
var action_detail_view := "camera_detail_view"
var action_overview := "camera_overview"
var action_next_factory := "camera_next_factory"
var action_prev_factory := "camera_prev_factory"
var action_back := "ui_cancel"

## Mouse settings
var mouse_wheel_zoom_enabled := true
var mouse_wheel_sensitivity := 0.1
var click_to_select := true

## Keyboard shortcuts
var key_zoom_in: Key = KEY_EQUAL  # +
var key_zoom_out: Key = KEY_MINUS  # -
var key_detail: Key = KEY_ENTER
var key_overview: Key = KEY_ESCAPE
var key_next: Key = KEY_TAB
var key_prev: Key = KEY_NONE  # Shift+Tab handled separately

## Camera controller reference
var _camera_controller: FactoryCameraController = null

## Target system reference
var _target_system: FactoryTargetSystem = null

## Current zoom level for incremental zoom
var _target_zoom: float = 0.0

## Zoom step for incremental zoom
var zoom_step := 0.25


func _init() -> void:
	pass


## Set camera controller.
func set_camera_controller(controller: FactoryCameraController) -> void:
	_camera_controller = controller
	if controller != null:
		_target_zoom = controller.get_zoom_level()


## Set target system.
func set_target_system(system: FactoryTargetSystem) -> void:
	_target_system = system


## Handle input event.
func handle_input(event: InputEvent) -> bool:
	# Mouse wheel zoom
	if event is InputEventMouseButton and mouse_wheel_zoom_enabled:
		return _handle_mouse_wheel(event)

	# Mouse click for factory selection
	if event is InputEventMouseButton and click_to_select:
		return _handle_mouse_click(event)

	# Keyboard input
	if event is InputEventKey:
		return _handle_keyboard(event)

	return false


## Handle mouse wheel input.
func _handle_mouse_wheel(event: InputEventMouseButton) -> bool:
	if not event.pressed:
		return false

	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_in()
		return true
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_out()
		return true

	return false


## Handle mouse click input.
func _handle_mouse_click(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false

	if not event.pressed:
		return false

	factory_click_requested.emit(event.position)

	return true


## Handle keyboard input.
func _handle_keyboard(event: InputEventKey) -> bool:
	if not event.pressed:
		return false

	# Zoom in
	if event.keycode == key_zoom_in:
		_zoom_in()
		return true

	# Zoom out
	if event.keycode == key_zoom_out:
		_zoom_out()
		return true

	# Detail view
	if event.keycode == key_detail:
		_zoom_to_detail()
		return true

	# Overview
	if event.keycode == key_overview:
		_zoom_to_overview()
		return true

	# Next factory
	if event.keycode == key_next and not event.shift_pressed:
		_select_next_factory()
		return true

	# Previous factory (Shift+Tab)
	if event.keycode == key_next and event.shift_pressed:
		_select_prev_factory()
		return true

	return false


## Zoom in by one step.
func _zoom_in() -> void:
	_target_zoom = minf(_target_zoom + zoom_step, 1.0)

	if _camera_controller != null:
		_camera_controller.zoom_to(_target_zoom)

	zoom_in_requested.emit()


## Zoom out by one step.
func _zoom_out() -> void:
	_target_zoom = maxf(_target_zoom - zoom_step, 0.0)

	if _camera_controller != null:
		_camera_controller.zoom_to(_target_zoom)

	zoom_out_requested.emit()


## Zoom to full detail view.
func _zoom_to_detail() -> void:
	_target_zoom = 1.0

	if _camera_controller != null:
		_camera_controller.zoom_to_detail()

	zoom_to_level_requested.emit(1.0)


## Zoom to overview.
func _zoom_to_overview() -> void:
	_target_zoom = 0.0

	if _camera_controller != null:
		_camera_controller.zoom_to_overview()

	if _target_system != null:
		_target_system.deselect()

	zoom_to_level_requested.emit(0.0)
	back_requested.emit()


## Select next factory.
func _select_next_factory() -> void:
	if _target_system != null:
		_target_system.select_next_factory()


## Select previous factory.
func _select_prev_factory() -> void:
	if _target_system != null:
		_target_system.select_previous_factory()


## Handle factory click at screen position.
func handle_factory_click(screen_pos: Vector2, camera: Camera3D) -> void:
	if _target_system == null:
		return

	var factory_id := _target_system.get_factory_at_screen_position(screen_pos, camera)
	if factory_id >= 0:
		_target_system.select_factory(factory_id)


## Set zoom step size.
func set_zoom_step(step: float) -> void:
	zoom_step = clampf(step, 0.05, 0.5)


## Get current target zoom.
func get_target_zoom() -> float:
	return _target_zoom


## Sync target zoom with camera.
func sync_zoom() -> void:
	if _camera_controller != null:
		_target_zoom = _camera_controller.get_zoom_level()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"target_zoom": _target_zoom,
		"zoom_step": zoom_step,
		"mouse_wheel_enabled": mouse_wheel_zoom_enabled,
		"click_to_select": click_to_select,
		"has_camera_controller": _camera_controller != null,
		"has_target_system": _target_system != null
	}
