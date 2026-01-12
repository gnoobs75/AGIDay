class_name CameraSystem
extends RefCounted
## CameraSystem provides complete camera management for factory view.

signal zoom_changed(level: float)
signal factory_focused(factory_id: int)
signal view_mode_changed(mode: String)

## View modes
const MODE_OVERVIEW := "overview"
const MODE_TACTICAL := "tactical"
const MODE_DETAIL := "detail"

## Sub-systems
var _camera_controller: FactoryCameraController = null
var _target_system: FactoryTargetSystem = null
var _input_handler: CameraInputHandler = null

## Camera reference
var _camera: Camera3D = null

## Current state
var _current_mode: String = MODE_OVERVIEW
var _is_initialized: bool = false


func _init() -> void:
	_camera_controller = FactoryCameraController.new()
	_target_system = FactoryTargetSystem.new()
	_input_handler = CameraInputHandler.new()

	# Wire up systems
	_target_system.set_camera_controller(_camera_controller)
	_input_handler.set_camera_controller(_camera_controller)
	_input_handler.set_target_system(_target_system)

	# Connect signals
	_camera_controller.zoom_completed.connect(_on_zoom_completed)
	_camera_controller.zoom_progress.connect(_on_zoom_progress)
	_target_system.factory_selected.connect(_on_factory_selected)
	_input_handler.factory_click_requested.connect(_on_factory_click)


## Initialize with camera.
func initialize(camera: Camera3D) -> void:
	_camera = camera
	_camera_controller.set_camera(camera)
	_is_initialized = true


## Update camera (call each frame).
func update(delta: float) -> void:
	if not _is_initialized:
		return

	_camera_controller.update(delta)


## Handle input event.
func handle_input(event: InputEvent) -> bool:
	return _input_handler.handle_input(event)


## Register a factory.
func register_factory(
	factory_id: int,
	position: Vector3,
	faction_id: String,
	display_name: String = ""
) -> void:
	_target_system.register_factory(factory_id, position, faction_id, display_name)


## Unregister a factory.
func unregister_factory(factory_id: int) -> void:
	_target_system.unregister_factory(factory_id)


## Update factory position.
func update_factory_position(factory_id: int, position: Vector3) -> void:
	_target_system.update_factory_position(factory_id, position)


## Select a factory.
func select_factory(factory_id: int) -> bool:
	return _target_system.select_factory(factory_id)


## Deselect current factory.
func deselect_factory() -> void:
	_target_system.deselect()


## Zoom to level.
func zoom_to(level: float) -> void:
	_camera_controller.zoom_to(level)


## Zoom to overview.
func zoom_to_overview() -> void:
	_camera_controller.zoom_to_overview()


## Zoom to detail.
func zoom_to_detail() -> void:
	_camera_controller.zoom_to_detail()


## Get current zoom level.
func get_zoom_level() -> float:
	return _camera_controller.get_zoom_level()


## Check if transitioning.
func is_transitioning() -> bool:
	return _camera_controller.is_transitioning()


## Get selected factory.
func get_selected_factory() -> int:
	return _target_system.get_selected_factory_id()


## Get current view mode.
func get_view_mode() -> String:
	return _current_mode


## Handle zoom completion.
func _on_zoom_completed(level: float) -> void:
	var old_mode := _current_mode

	# Determine mode from zoom level
	if level < 0.3:
		_current_mode = MODE_OVERVIEW
	elif level < 0.7:
		_current_mode = MODE_TACTICAL
	else:
		_current_mode = MODE_DETAIL

	zoom_changed.emit(level)

	if old_mode != _current_mode:
		view_mode_changed.emit(_current_mode)


## Handle zoom progress.
func _on_zoom_progress(level: float) -> void:
	zoom_changed.emit(level)


## Handle factory selection.
func _on_factory_selected(factory_id: int) -> void:
	factory_focused.emit(factory_id)


## Handle factory click.
func _on_factory_click(screen_pos: Vector2) -> void:
	if _camera != null:
		_input_handler.handle_factory_click(screen_pos, _camera)


## Set transition time.
func set_transition_time(time: float) -> void:
	_camera_controller.set_transition_time(time)


## Set camera settings.
func set_overview_settings(position: Vector3, rotation: Vector3, fov: float) -> void:
	_camera_controller.set_overview_settings(position, rotation, fov)


func set_detail_settings(offset: Vector3, rotation: Vector3, fov: float) -> void:
	_camera_controller.set_detail_settings(offset, rotation, fov)


## Set input settings.
func set_mouse_wheel_zoom(enabled: bool) -> void:
	_input_handler.mouse_wheel_zoom_enabled = enabled


func set_click_to_select(enabled: bool) -> void:
	_input_handler.click_to_select = enabled


func set_zoom_step(step: float) -> void:
	_input_handler.set_zoom_step(step)


## Get sub-systems for advanced configuration.
func get_camera_controller() -> FactoryCameraController:
	return _camera_controller


func get_target_system() -> FactoryTargetSystem:
	return _target_system


func get_input_handler() -> CameraInputHandler:
	return _input_handler


## Check if initialized.
func is_initialized() -> bool:
	return _is_initialized


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"is_initialized": _is_initialized,
		"current_mode": _current_mode,
		"zoom_level": _camera_controller.get_zoom_level(),
		"selected_factory": _target_system.get_selected_factory_id(),
		"factory_count": _target_system.get_factory_count(),
		"is_transitioning": _camera_controller.is_transitioning(),
		"has_camera": _camera != null
	}
