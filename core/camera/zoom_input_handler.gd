class_name ZoomInputHandler
extends RefCounted
## ZoomInputHandler manages zoom input from mouse wheel and hotkeys.

signal zoom_level_changed(level: float)
signal zoom_to_factory_requested(factory_id: int)
signal zoom_to_overview_requested()
signal factory_selection_changed(factory_id: int)

## Zoom configuration
const DEFAULT_SENSITIVITY := 0.1
const MIN_ZOOM := 0.0
const MAX_ZOOM := 1.0

## Sensitivity setting
var zoom_sensitivity: float = DEFAULT_SENSITIVITY

## Current zoom state
var _current_zoom: float = MIN_ZOOM
var _target_zoom: float = MIN_ZOOM

## Selected factory
var _selected_factory_id: int = -1

## Factory view controller reference (for integration)
var _view_controller: RefCounted = null

## Input enabled state
var _input_enabled: bool = true


func _init() -> void:
	pass


## Set zoom sensitivity.
func set_sensitivity(sensitivity: float) -> void:
	zoom_sensitivity = maxf(sensitivity, 0.01)


## Set factory view controller.
func set_view_controller(controller: RefCounted) -> void:
	_view_controller = controller


## Handle input event.
func handle_input(event: InputEvent) -> bool:
	if not _input_enabled:
		return false

	# Handle mouse wheel
	if event is InputEventMouseButton:
		return _handle_mouse_button(event)

	# Handle keyboard
	if event is InputEventKey:
		return _handle_key(event)

	return false


## Handle mouse button input.
func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	if not event.pressed:
		return false

	# Mouse wheel up - zoom in
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_in()
		return true

	# Mouse wheel down - zoom out
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_out()
		return true

	return false


## Handle key input.
func _handle_key(event: InputEventKey) -> bool:
	if not event.pressed:
		return false

	# F key - quick zoom to selected factory
	if event.keycode == KEY_F:
		return _zoom_to_selected_factory()

	# Escape key - zoom out to overview
	if event.keycode == KEY_ESCAPE:
		_zoom_to_overview()
		return true

	return false


## Zoom in by sensitivity amount.
func _zoom_in() -> void:
	_target_zoom = minf(_target_zoom + zoom_sensitivity, MAX_ZOOM)
	_apply_zoom()


## Zoom out by sensitivity amount.
func _zoom_out() -> void:
	_target_zoom = maxf(_target_zoom - zoom_sensitivity, MIN_ZOOM)
	_apply_zoom()

	# Clear selection when at overview
	if _target_zoom <= MIN_ZOOM:
		_clear_selection()


## Zoom to selected factory (F key).
func _zoom_to_selected_factory() -> bool:
	# Only works when a factory is selected
	if _selected_factory_id < 0:
		return false

	_target_zoom = MAX_ZOOM
	_apply_zoom()

	zoom_to_factory_requested.emit(_selected_factory_id)

	return true


## Zoom out to overview (Escape key).
func _zoom_to_overview() -> void:
	_target_zoom = MIN_ZOOM
	_apply_zoom()
	_clear_selection()

	zoom_to_overview_requested.emit()


## Apply current zoom level.
func _apply_zoom() -> void:
	_current_zoom = _target_zoom

	# Update view controller if set
	if _view_controller != null and _view_controller.has_method("set_target_zoom_level"):
		_view_controller.call("set_target_zoom_level", _target_zoom)

	zoom_level_changed.emit(_current_zoom)


## Clear factory selection.
func _clear_selection() -> void:
	if _selected_factory_id < 0:
		return

	var old_id := _selected_factory_id
	_selected_factory_id = -1

	# Update view controller if set
	if _view_controller != null and _view_controller.has_method("set_selected_factory"):
		_view_controller.call("set_selected_factory", -1)

	factory_selection_changed.emit(-1)


## Select a factory.
func select_factory(factory_id: int) -> void:
	_selected_factory_id = factory_id

	# Update view controller if set
	if _view_controller != null and _view_controller.has_method("set_selected_factory"):
		_view_controller.call("set_selected_factory", factory_id)

	factory_selection_changed.emit(factory_id)


## Set zoom level directly.
func set_zoom_level(level: float) -> void:
	_target_zoom = clampf(level, MIN_ZOOM, MAX_ZOOM)
	_current_zoom = _target_zoom


## Get current zoom level.
func get_zoom_level() -> float:
	return _current_zoom


## Get target zoom level.
func get_target_zoom_level() -> float:
	return _target_zoom


## Get selected factory ID.
func get_selected_factory() -> int:
	return _selected_factory_id


## Check if factory is selected.
func has_factory_selected() -> bool:
	return _selected_factory_id >= 0


## Enable/disable input handling.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


## Check if input is enabled.
func is_input_enabled() -> bool:
	return _input_enabled


## Check if at overview level.
func is_at_overview() -> bool:
	return _current_zoom <= MIN_ZOOM


## Check if at detail level.
func is_at_detail() -> bool:
	return _current_zoom >= MAX_ZOOM


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"current_zoom": _current_zoom,
		"target_zoom": _target_zoom,
		"sensitivity": zoom_sensitivity,
		"selected_factory": _selected_factory_id,
		"input_enabled": _input_enabled,
		"has_view_controller": _view_controller != null
	}
