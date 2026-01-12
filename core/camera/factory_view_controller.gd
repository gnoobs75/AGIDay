class_name FactoryViewController
extends RefCounted
## FactoryViewController coordinates zoom input with camera and factory systems.

signal view_changed(zoom_level: float, factory_id: int)
signal overview_activated()
signal detail_view_activated(factory_id: int)

## Zoom thresholds
const OVERVIEW_THRESHOLD := 0.2
const DETAIL_THRESHOLD := 0.8

## Current state
var target_zoom_level: float = 0.0
var selected_factory: int = -1

## Previous state for change detection
var _previous_zoom: float = 0.0
var _previous_factory: int = -1

## Input handler
var _input_handler: ZoomInputHandler = null

## Camera controller reference
var _camera_controller: FactoryCameraController = null

## Factory data
var _factory_positions: Dictionary = {}  ## factory_id -> Vector3


func _init() -> void:
	_input_handler = ZoomInputHandler.new()
	_input_handler.set_view_controller(self)

	# Connect signals
	_input_handler.zoom_level_changed.connect(_on_zoom_changed)
	_input_handler.factory_selection_changed.connect(_on_factory_changed)
	_input_handler.zoom_to_factory_requested.connect(_on_zoom_to_factory)
	_input_handler.zoom_to_overview_requested.connect(_on_zoom_to_overview)


## Set camera controller.
func set_camera_controller(controller: FactoryCameraController) -> void:
	_camera_controller = controller


## Handle input event.
func handle_input(event: InputEvent) -> bool:
	return _input_handler.handle_input(event)


## Register a factory.
func register_factory(factory_id: int, position: Vector3) -> void:
	_factory_positions[factory_id] = position


## Unregister a factory.
func unregister_factory(factory_id: int) -> void:
	_factory_positions.erase(factory_id)

	if selected_factory == factory_id:
		set_selected_factory(-1)


## Update factory position.
func update_factory_position(factory_id: int, position: Vector3) -> void:
	_factory_positions[factory_id] = position

	# Update camera target if this is selected factory
	if factory_id == selected_factory and _camera_controller != null:
		_camera_controller.target_factory(factory_id, position)


## Set target zoom level (called by input handler).
func set_target_zoom_level(level: float) -> void:
	target_zoom_level = clampf(level, 0.0, 1.0)

	if _camera_controller != null:
		_camera_controller.zoom_to(target_zoom_level)

	_check_state_changes()


## Set selected factory (called by input handler).
func set_selected_factory(factory_id: int) -> void:
	selected_factory = factory_id

	# Update camera target
	if _camera_controller != null:
		if factory_id >= 0 and _factory_positions.has(factory_id):
			_camera_controller.target_factory(factory_id, _factory_positions[factory_id])
		else:
			_camera_controller.clear_target()

	_check_state_changes()


## Select factory and zoom to it.
func select_and_zoom_to_factory(factory_id: int) -> void:
	if not _factory_positions.has(factory_id):
		return

	set_selected_factory(factory_id)
	set_target_zoom_level(1.0)


## Zoom to overview.
func zoom_to_overview() -> void:
	set_selected_factory(-1)
	set_target_zoom_level(0.0)


## Handle zoom level change from input handler.
func _on_zoom_changed(level: float) -> void:
	target_zoom_level = level
	_check_state_changes()


## Handle factory selection change from input handler.
func _on_factory_changed(factory_id: int) -> void:
	selected_factory = factory_id
	_check_state_changes()


## Handle zoom to factory request.
func _on_zoom_to_factory(factory_id: int) -> void:
	if _factory_positions.has(factory_id) and _camera_controller != null:
		_camera_controller.target_factory(factory_id, _factory_positions[factory_id])
		_camera_controller.zoom_to_detail()


## Handle zoom to overview request.
func _on_zoom_to_overview() -> void:
	if _camera_controller != null:
		_camera_controller.clear_target()
		_camera_controller.zoom_to_overview()


## Check for state changes and emit appropriate signals.
func _check_state_changes() -> void:
	var zoom_changed := not is_equal_approx(_previous_zoom, target_zoom_level)
	var factory_changed := _previous_factory != selected_factory

	if zoom_changed or factory_changed:
		view_changed.emit(target_zoom_level, selected_factory)

	# Check for mode transitions
	if _previous_zoom >= OVERVIEW_THRESHOLD and target_zoom_level < OVERVIEW_THRESHOLD:
		overview_activated.emit()

	if _previous_zoom < DETAIL_THRESHOLD and target_zoom_level >= DETAIL_THRESHOLD and selected_factory >= 0:
		detail_view_activated.emit(selected_factory)

	_previous_zoom = target_zoom_level
	_previous_factory = selected_factory


## Get input handler.
func get_input_handler() -> ZoomInputHandler:
	return _input_handler


## Get zoom level.
func get_zoom_level() -> float:
	return target_zoom_level


## Get selected factory.
func get_selected_factory() -> int:
	return selected_factory


## Check if in overview mode.
func is_overview_mode() -> bool:
	return target_zoom_level < OVERVIEW_THRESHOLD


## Check if in detail mode.
func is_detail_mode() -> bool:
	return target_zoom_level >= DETAIL_THRESHOLD and selected_factory >= 0


## Set zoom sensitivity.
func set_zoom_sensitivity(sensitivity: float) -> void:
	_input_handler.set_sensitivity(sensitivity)


## Enable/disable input.
func set_input_enabled(enabled: bool) -> void:
	_input_handler.set_input_enabled(enabled)


## Get all factory IDs.
func get_factory_ids() -> Array:
	return _factory_positions.keys()


## Get factory position.
func get_factory_position(factory_id: int) -> Vector3:
	return _factory_positions.get(factory_id, Vector3.ZERO)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"target_zoom": target_zoom_level,
		"selected_factory": selected_factory,
		"factory_count": _factory_positions.size(),
		"is_overview": is_overview_mode(),
		"is_detail": is_detail_mode(),
		"input_handler": _input_handler.get_summary() if _input_handler != null else {},
		"has_camera_controller": _camera_controller != null
	}
