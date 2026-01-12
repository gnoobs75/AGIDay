class_name ViewportSystem
extends RefCounted
## ViewportSystem provides the complete multi-viewport rendering infrastructure.

signal system_initialized()
signal zoom_level_changed(zoom: float)
signal factory_view_activated(factory_id: int)
signal factory_view_deactivated()

## Zoom thresholds
const ZOOM_STRATEGIC := 0.0
const ZOOM_TACTICAL := 0.3
const ZOOM_FACTORY := 0.6
const ZOOM_DETAIL := 1.0

## Sub-systems
var _layer_manager: ViewportLayerManager = null
var _compositor: ViewportCompositor = null

## State
var _current_zoom: float = ZOOM_STRATEGIC
var _active_factory_id: int = -1
var _is_initialized: bool = false

## Parent nodes
var _scene_root: Node = null
var _main_camera: Camera3D = null


func _init() -> void:
	_layer_manager = ViewportLayerManager.new()
	_compositor = ViewportCompositor.new()


## Initialize the viewport system.
func initialize(scene_root: Node) -> void:
	if _is_initialized:
		return

	_scene_root = scene_root

	# Initialize layer manager
	_layer_manager.initialize(scene_root)
	_layer_manager.create_standard_viewports()

	# Initialize compositor
	_compositor.initialize(_layer_manager, scene_root)

	# Connect signals
	_layer_manager.viewport_visibility_changed.connect(_on_viewport_visibility_changed)

	_is_initialized = true
	system_initialized.emit()


## Set zoom level (0.0 = strategic, 1.0 = detail).
func set_zoom_level(zoom: float) -> void:
	var old_zoom := _current_zoom
	_current_zoom = clampf(zoom, 0.0, 1.0)

	# Update layer manager for culling
	_layer_manager.set_zoom_level(_current_zoom)

	# Update compositor for transitions
	_update_layer_visibility()

	if old_zoom != _current_zoom:
		zoom_level_changed.emit(_current_zoom)


## Get current zoom level.
func get_zoom_level() -> float:
	return _current_zoom


## Update layer visibility based on zoom.
func _update_layer_visibility() -> void:
	# Factory detail only visible at factory zoom or higher
	var show_factory := _current_zoom >= ZOOM_FACTORY
	_compositor.set_layer_visible(ViewportLayerManager.LAYER_FACTORY_DETAIL, show_factory and _active_factory_id >= 0)

	# Minimap always visible but fades at high zoom
	var minimap_opacity := 1.0 - (_current_zoom * 0.5)
	_compositor.set_layer_opacity(ViewportLayerManager.LAYER_MINIMAP, minimap_opacity)

	# Update composition
	_compositor.update_composition()


## Activate factory detail view.
func activate_factory_view(factory_id: int) -> void:
	_active_factory_id = factory_id

	# Show factory detail viewport
	_layer_manager.set_viewport_visible(ViewportLayerManager.LAYER_FACTORY_DETAIL, true)
	_compositor.set_layer_visible(ViewportLayerManager.LAYER_FACTORY_DETAIL, true)

	_compositor.update_composition()

	factory_view_activated.emit(factory_id)


## Deactivate factory detail view.
func deactivate_factory_view() -> void:
	_active_factory_id = -1

	# Hide factory detail viewport
	_layer_manager.set_viewport_visible(ViewportLayerManager.LAYER_FACTORY_DETAIL, false)
	_compositor.set_layer_visible(ViewportLayerManager.LAYER_FACTORY_DETAIL, false)

	_compositor.update_composition()

	factory_view_deactivated.emit()


## Get factory detail viewport.
func get_factory_viewport() -> SubViewport:
	return _layer_manager.get_viewport(ViewportLayerManager.LAYER_FACTORY_DETAIL)


## Get main viewport.
func get_main_viewport() -> SubViewport:
	return _layer_manager.get_viewport(ViewportLayerManager.LAYER_MAIN)


## Get UI viewport.
func get_ui_viewport() -> SubViewport:
	return _layer_manager.get_viewport(ViewportLayerManager.LAYER_UI)


## Get minimap viewport.
func get_minimap_viewport() -> SubViewport:
	return _layer_manager.get_viewport(ViewportLayerManager.LAYER_MINIMAP)


## Get layer manager.
func get_layer_manager() -> ViewportLayerManager:
	return _layer_manager


## Get compositor.
func get_compositor() -> ViewportCompositor:
	return _compositor


## Set minimap position.
func set_minimap_position(position: Vector2) -> void:
	_compositor.set_layer_position(ViewportLayerManager.LAYER_MINIMAP, position)


## Set minimap scale.
func set_minimap_scale(scale: float) -> void:
	_compositor.set_layer_scale(ViewportLayerManager.LAYER_MINIMAP, Vector2(scale, scale))


## Resize viewports for window size change.
func handle_window_resize(new_size: Vector2i) -> void:
	# Main viewport matches window
	_layer_manager.resize_viewport(ViewportLayerManager.LAYER_MAIN, new_size)

	# UI viewport matches window
	_layer_manager.resize_viewport(ViewportLayerManager.LAYER_UI, new_size)

	# Factory detail stays fixed size for performance
	# Minimap stays fixed size


## Check if factory view is active.
func is_factory_view_active() -> bool:
	return _active_factory_id >= 0


## Get active factory ID.
func get_active_factory_id() -> int:
	return _active_factory_id


## Handle viewport visibility changes.
func _on_viewport_visibility_changed(layer_name: String, visible: bool) -> void:
	_compositor.set_layer_visible(layer_name, visible)
	_compositor.update_composition()


## Check if system is initialized.
func is_initialized() -> bool:
	return _is_initialized


## Get zoom level category.
func get_zoom_category() -> String:
	if _current_zoom < ZOOM_TACTICAL:
		return "strategic"
	elif _current_zoom < ZOOM_FACTORY:
		return "tactical"
	elif _current_zoom < ZOOM_DETAIL:
		return "factory"
	else:
		return "detail"


## Cleanup.
func cleanup() -> void:
	_compositor.cleanup()
	_layer_manager.cleanup()
	_is_initialized = false


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"is_initialized": _is_initialized,
		"current_zoom": _current_zoom,
		"zoom_category": get_zoom_category(),
		"active_factory": _active_factory_id,
		"factory_view_active": is_factory_view_active(),
		"layer_manager": _layer_manager.get_summary() if _layer_manager != null else {},
		"compositor": _compositor.get_summary() if _compositor != null else {}
	}
