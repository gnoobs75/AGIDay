class_name ViewportManager
extends RefCounted
## ViewportManager handles multi-viewport architecture for rendering layers.
## Manages main world, UI, factory detail, and minimap viewports.

signal viewport_created(viewport_id: String)
signal viewport_resized(viewport_id: String, size: Vector2i)
signal viewport_visibility_changed(viewport_id: String, visible: bool)
signal render_mode_changed(mode: int)

## Viewport types
enum ViewportType {
	MAIN_WORLD,      ## 3D world rendering
	UI_LAYER,        ## HUD and panels
	FACTORY_DETAIL,  ## Factory close-up
	MINIMAP          ## Real-time minimap
}

## Render modes
enum RenderMode {
	QUALITY,         ## Full quality, 60Hz all viewports
	PERFORMANCE,     ## Reduced quality, minimap 30Hz
	MINIMAL          ## Essential only
}

## Viewport configurations
const VIEWPORT_CONFIGS := {
	ViewportType.MAIN_WORLD: {
		"update_mode": 0,  # SubViewport.UPDATE_ALWAYS
		"msaa": 2,         # MSAA_2X
		"fxaa": true,
		"shadow_atlas_size": 4096,
		"priority": 0
	},
	ViewportType.UI_LAYER: {
		"update_mode": 0,
		"msaa": 0,
		"fxaa": false,
		"transparent": true,
		"priority": 100
	},
	ViewportType.FACTORY_DETAIL: {
		"update_mode": 1,  # UPDATE_ONCE or when needed
		"msaa": 2,
		"fxaa": true,
		"shadow_atlas_size": 2048,
		"priority": 50
	},
	ViewportType.MINIMAP: {
		"update_mode": 0,
		"msaa": 0,
		"fxaa": false,
		"size": Vector2i(256, 256),
		"priority": 10
	}
}

## Viewport data
var _viewports: Dictionary = {}       ## ViewportType -> ViewportData
var _render_mode: RenderMode = RenderMode.QUALITY
var _screen_size := Vector2i(1920, 1080)

## Performance settings
var _minimap_update_rate := 60        ## Hz
var _factory_visible := false


func _init() -> void:
	_initialize_viewport_data()


## Initialize viewport data structures.
func _initialize_viewport_data() -> void:
	for vp_type in ViewportType.values():
		var data := ViewportData.new()
		data.type = vp_type
		data.config = VIEWPORT_CONFIGS[vp_type].duplicate()
		data.is_active = true
		data.is_visible = true

		_viewports[vp_type] = data


## Set screen size.
func set_screen_size(size: Vector2i) -> void:
	_screen_size = size

	# Update viewport sizes
	_viewports[ViewportType.MAIN_WORLD].size = size
	_viewports[ViewportType.UI_LAYER].size = size

	# Factory detail is a portion of screen
	_viewports[ViewportType.FACTORY_DETAIL].size = Vector2i(
		int(size.x * 0.4),
		int(size.y * 0.4)
	)

	for vp_type in _viewports:
		viewport_resized.emit(_get_viewport_name(vp_type), _viewports[vp_type].size)


## Set render mode.
func set_render_mode(mode: RenderMode) -> void:
	_render_mode = mode

	match mode:
		RenderMode.QUALITY:
			_minimap_update_rate = 60
			_apply_quality_settings()
		RenderMode.PERFORMANCE:
			_minimap_update_rate = 30
			_apply_performance_settings()
		RenderMode.MINIMAL:
			_minimap_update_rate = 15
			_apply_minimal_settings()

	render_mode_changed.emit(mode)


## Apply quality render settings.
func _apply_quality_settings() -> void:
	var main: ViewportData = _viewports[ViewportType.MAIN_WORLD]
	main.config["msaa"] = 2
	main.config["fxaa"] = true
	main.config["shadow_atlas_size"] = 4096

	var factory: ViewportData = _viewports[ViewportType.FACTORY_DETAIL]
	factory.config["msaa"] = 2
	factory.config["shadow_atlas_size"] = 2048


## Apply performance render settings.
func _apply_performance_settings() -> void:
	var main: ViewportData = _viewports[ViewportType.MAIN_WORLD]
	main.config["msaa"] = 1
	main.config["fxaa"] = true
	main.config["shadow_atlas_size"] = 2048

	var factory: ViewportData = _viewports[ViewportType.FACTORY_DETAIL]
	factory.config["msaa"] = 0
	factory.config["shadow_atlas_size"] = 1024


## Apply minimal render settings.
func _apply_minimal_settings() -> void:
	var main: ViewportData = _viewports[ViewportType.MAIN_WORLD]
	main.config["msaa"] = 0
	main.config["fxaa"] = false
	main.config["shadow_atlas_size"] = 1024

	var factory: ViewportData = _viewports[ViewportType.FACTORY_DETAIL]
	factory.config["msaa"] = 0
	factory.config["shadow_atlas_size"] = 512


## Set viewport visibility.
func set_viewport_visible(vp_type: ViewportType, visible: bool) -> void:
	if _viewports.has(vp_type):
		_viewports[vp_type].is_visible = visible
		viewport_visibility_changed.emit(_get_viewport_name(vp_type), visible)


## Set viewport active (enables/disables rendering).
func set_viewport_active(vp_type: ViewportType, active: bool) -> void:
	if _viewports.has(vp_type):
		_viewports[vp_type].is_active = active


## Show factory detail viewport.
func show_factory_detail() -> void:
	_factory_visible = true
	set_viewport_visible(ViewportType.FACTORY_DETAIL, true)
	set_viewport_active(ViewportType.FACTORY_DETAIL, true)


## Hide factory detail viewport.
func hide_factory_detail() -> void:
	_factory_visible = false
	set_viewport_visible(ViewportType.FACTORY_DETAIL, false)
	set_viewport_active(ViewportType.FACTORY_DETAIL, false)


## Toggle factory detail.
func toggle_factory_detail() -> void:
	if _factory_visible:
		hide_factory_detail()
	else:
		show_factory_detail()


## Get viewport data.
func get_viewport_data(vp_type: ViewportType) -> ViewportData:
	return _viewports.get(vp_type)


## Get viewport configuration.
func get_viewport_config(vp_type: ViewportType) -> Dictionary:
	if _viewports.has(vp_type):
		return _viewports[vp_type].config.duplicate()
	return {}


## Get viewport size.
func get_viewport_size(vp_type: ViewportType) -> Vector2i:
	if _viewports.has(vp_type):
		return _viewports[vp_type].size
	return Vector2i.ZERO


## Check if viewport is active.
func is_viewport_active(vp_type: ViewportType) -> bool:
	if _viewports.has(vp_type):
		return _viewports[vp_type].is_active
	return false


## Check if viewport is visible.
func is_viewport_visible(vp_type: ViewportType) -> bool:
	if _viewports.has(vp_type):
		return _viewports[vp_type].is_visible
	return false


## Get minimap update rate.
func get_minimap_update_rate() -> int:
	return _minimap_update_rate


## Get current render mode.
func get_render_mode() -> RenderMode:
	return _render_mode


## Get viewport name.
func _get_viewport_name(vp_type: ViewportType) -> String:
	match vp_type:
		ViewportType.MAIN_WORLD: return "main_world"
		ViewportType.UI_LAYER: return "ui_layer"
		ViewportType.FACTORY_DETAIL: return "factory_detail"
		ViewportType.MINIMAP: return "minimap"
	return "unknown"


## Get render mode name.
static func get_render_mode_name(mode: RenderMode) -> String:
	match mode:
		RenderMode.QUALITY: return "Quality"
		RenderMode.PERFORMANCE: return "Performance"
		RenderMode.MINIMAL: return "Minimal"
	return "Unknown"


## Update viewports (call each frame for timing).
func update(delta: float) -> void:
	# Update minimap at reduced rate if needed
	if _render_mode != RenderMode.QUALITY:
		var minimap: ViewportData = _viewports[ViewportType.MINIMAP]
		minimap.update_timer += delta

		var update_interval := 1.0 / float(_minimap_update_rate)
		if minimap.update_timer >= update_interval:
			minimap.update_timer = 0.0
			minimap.needs_update = true
		else:
			minimap.needs_update = false


## Check if minimap needs update this frame.
func should_update_minimap() -> bool:
	if _render_mode == RenderMode.QUALITY:
		return true
	return _viewports[ViewportType.MINIMAP].needs_update


## Get statistics.
func get_statistics() -> Dictionary:
	var active_count := 0
	var visible_count := 0

	for vp_type in _viewports:
		if _viewports[vp_type].is_active:
			active_count += 1
		if _viewports[vp_type].is_visible:
			visible_count += 1

	return {
		"screen_size": _screen_size,
		"render_mode": _render_mode,
		"render_mode_name": get_render_mode_name(_render_mode),
		"active_viewports": active_count,
		"visible_viewports": visible_count,
		"minimap_update_rate": _minimap_update_rate,
		"factory_visible": _factory_visible
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var viewport_states := {}
	for vp_type in _viewports:
		var vp: ViewportData = _viewports[vp_type]
		viewport_states[vp_type] = {
			"is_active": vp.is_active,
			"is_visible": vp.is_visible,
			"size": {"x": vp.size.x, "y": vp.size.y}
		}

	return {
		"render_mode": _render_mode,
		"screen_size": {"x": _screen_size.x, "y": _screen_size.y},
		"viewport_states": viewport_states,
		"factory_visible": _factory_visible
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_render_mode = data.get("render_mode", RenderMode.QUALITY)

	var size: Dictionary = data.get("screen_size", {})
	_screen_size = Vector2i(size.get("x", 1920), size.get("y", 1080))

	_factory_visible = data.get("factory_visible", false)

	var states: Dictionary = data.get("viewport_states", {})
	for vp_type_str in states:
		var vp_type := int(vp_type_str)
		if _viewports.has(vp_type):
			var state: Dictionary = states[vp_type_str]
			_viewports[vp_type].is_active = state.get("is_active", true)
			_viewports[vp_type].is_visible = state.get("is_visible", true)

			var vp_size: Dictionary = state.get("size", {})
			_viewports[vp_type].size = Vector2i(vp_size.get("x", 0), vp_size.get("y", 0))

	set_render_mode(_render_mode)


## ViewportData class.
class ViewportData:
	var type: ViewportType = ViewportType.MAIN_WORLD
	var config: Dictionary = {}
	var size: Vector2i = Vector2i(1920, 1080)
	var is_active: bool = true
	var is_visible: bool = true
	var update_timer: float = 0.0
	var needs_update: bool = true
