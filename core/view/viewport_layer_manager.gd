class_name ViewportLayerManager
extends RefCounted
## ViewportLayerManager creates and manages multiple viewport rendering layers.

signal viewport_created(layer_name: String)
signal viewport_destroyed(layer_name: String)
signal viewport_visibility_changed(layer_name: String, visible: bool)

## Viewport layer names
const LAYER_MAIN := "main"
const LAYER_FACTORY_DETAIL := "factory_detail"
const LAYER_UI := "ui"
const LAYER_MINIMAP := "minimap"

## Viewport configurations
const CONFIG_FACTORY_DETAIL_SIZE := Vector2i(1280, 720)
const CONFIG_UI_SIZE := Vector2i(1920, 1080)
const CONFIG_MINIMAP_SIZE := Vector2i(512, 512)

## Performance limits
const MAX_VIEWPORT_LAYERS := 10
const MEMORY_BUDGET_MB := 50.0
const CULLING_ZOOM_THRESHOLD := 0.5

## Viewport storage
var _viewports: Dictionary = {}  ## layer_name -> SubViewport
var _viewport_containers: Dictionary = {}  ## layer_name -> SubViewportContainer
var _viewport_configs: Dictionary = {}  ## layer_name -> ViewportConfig

## Parent node for viewports
var _parent_node: Node = null

## Current zoom level for culling
var _current_zoom: float = 1.0

## Performance tracking
var _estimated_memory_mb: float = 0.0


## Viewport configuration class
class ViewportConfig:
	var size: Vector2i = Vector2i(1920, 1080)
	var msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
	var update_mode: SubViewport.UpdateMode = SubViewport.UPDATE_ALWAYS
	var transparent_bg: bool = false
	var render_target_clear_mode: SubViewport.ClearMode = SubViewport.CLEAR_MODE_ALWAYS
	var use_hdr_2d: bool = false
	var scaling_3d_mode: Viewport.Scaling3DMode = Viewport.SCALING_3D_MODE_BILINEAR
	var disable_3d: bool = false
	var cull_on_low_zoom: bool = false
	var priority: int = 0


func _init() -> void:
	_setup_default_configs()


## Set up default viewport configurations.
func _setup_default_configs() -> void:
	# Main viewport config
	var main_config := ViewportConfig.new()
	main_config.size = Vector2i(1920, 1080)
	main_config.msaa = Viewport.MSAA_2X
	main_config.update_mode = SubViewport.UPDATE_ALWAYS
	main_config.priority = 0
	_viewport_configs[LAYER_MAIN] = main_config

	# Factory detail viewport config
	var factory_config := ViewportConfig.new()
	factory_config.size = CONFIG_FACTORY_DETAIL_SIZE
	factory_config.msaa = Viewport.MSAA_2X
	factory_config.update_mode = SubViewport.UPDATE_ALWAYS
	factory_config.cull_on_low_zoom = true
	factory_config.priority = 1
	_viewport_configs[LAYER_FACTORY_DETAIL] = factory_config

	# UI viewport config
	var ui_config := ViewportConfig.new()
	ui_config.size = CONFIG_UI_SIZE
	ui_config.msaa = Viewport.MSAA_DISABLED
	ui_config.update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	ui_config.transparent_bg = true
	ui_config.disable_3d = true
	ui_config.priority = 2
	_viewport_configs[LAYER_UI] = ui_config

	# Minimap viewport config
	var minimap_config := ViewportConfig.new()
	minimap_config.size = CONFIG_MINIMAP_SIZE
	minimap_config.msaa = Viewport.MSAA_DISABLED
	minimap_config.update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	minimap_config.priority = 3
	_viewport_configs[LAYER_MINIMAP] = minimap_config


## Initialize with parent node.
func initialize(parent: Node) -> void:
	_parent_node = parent


## Create all standard viewports.
func create_standard_viewports() -> void:
	create_viewport(LAYER_MAIN)
	create_viewport(LAYER_FACTORY_DETAIL)
	create_viewport(LAYER_UI)
	create_viewport(LAYER_MINIMAP)


## Create a viewport layer.
func create_viewport(layer_name: String, custom_config: ViewportConfig = null) -> SubViewport:
	if _viewports.size() >= MAX_VIEWPORT_LAYERS:
		push_warning("Maximum viewport layers reached")
		return null

	if _viewports.has(layer_name):
		return _viewports[layer_name]

	# Get config
	var config: ViewportConfig = custom_config if custom_config != null else _viewport_configs.get(layer_name)
	if config == null:
		config = ViewportConfig.new()
		_viewport_configs[layer_name] = config

	# Check memory budget
	var estimated_size := _estimate_viewport_memory(config)
	if _estimated_memory_mb + estimated_size > MEMORY_BUDGET_MB:
		push_warning("Viewport would exceed memory budget")
		return null

	# Create viewport container
	var container := SubViewportContainer.new()
	container.name = "ViewportContainer_%s" % layer_name
	container.stretch = true

	# Create viewport
	var viewport := SubViewport.new()
	viewport.name = "Viewport_%s" % layer_name

	# Configure viewport
	_configure_viewport(viewport, config)

	# Add to tree
	container.add_child(viewport)
	if _parent_node != null:
		_parent_node.add_child(container)

	# Store references
	_viewports[layer_name] = viewport
	_viewport_containers[layer_name] = container
	_estimated_memory_mb += estimated_size

	viewport_created.emit(layer_name)

	return viewport


## Configure a viewport with settings.
func _configure_viewport(viewport: SubViewport, config: ViewportConfig) -> void:
	viewport.size = config.size
	viewport.msaa_2d = config.msaa
	viewport.msaa_3d = config.msaa

	viewport.render_target_update_mode = config.update_mode
	viewport.render_target_clear_mode = config.render_target_clear_mode

	viewport.transparent_bg = config.transparent_bg
	viewport.use_hdr_2d = config.use_hdr_2d
	viewport.scaling_3d_mode = config.scaling_3d_mode
	viewport.disable_3d = config.disable_3d

	# Set up canvas for UI layer
	if config.transparent_bg:
		viewport.transparent_bg = true


## Estimate viewport memory usage in MB.
func _estimate_viewport_memory(config: ViewportConfig) -> float:
	# Estimate: width * height * 4 bytes (RGBA) * MSAA multiplier
	var pixels := config.size.x * config.size.y
	var bytes_per_pixel := 4.0

	var msaa_multiplier := 1.0
	match config.msaa:
		Viewport.MSAA_2X:
			msaa_multiplier = 2.0
		Viewport.MSAA_4X:
			msaa_multiplier = 4.0
		Viewport.MSAA_8X:
			msaa_multiplier = 8.0

	# Include depth buffer estimate
	var depth_bytes := pixels * 4.0  # 32-bit depth

	var total_bytes := (pixels * bytes_per_pixel * msaa_multiplier) + depth_bytes
	return total_bytes / (1024.0 * 1024.0)


## Get a viewport by layer name.
func get_viewport(layer_name: String) -> SubViewport:
	return _viewports.get(layer_name)


## Get a viewport container by layer name.
func get_container(layer_name: String) -> SubViewportContainer:
	return _viewport_containers.get(layer_name)


## Set viewport visibility.
func set_viewport_visible(layer_name: String, visible: bool) -> void:
	if _viewport_containers.has(layer_name):
		_viewport_containers[layer_name].visible = visible
		viewport_visibility_changed.emit(layer_name, visible)


## Set zoom level for viewport culling.
func set_zoom_level(zoom: float) -> void:
	_current_zoom = zoom
	_update_viewport_culling()


## Update viewport culling based on zoom.
func _update_viewport_culling() -> void:
	for layer_name in _viewport_configs:
		var config: ViewportConfig = _viewport_configs[layer_name]

		if config.cull_on_low_zoom:
			var should_cull := _current_zoom < CULLING_ZOOM_THRESHOLD
			set_viewport_visible(layer_name, not should_cull)


## Resize a viewport.
func resize_viewport(layer_name: String, new_size: Vector2i) -> void:
	if not _viewports.has(layer_name):
		return

	var viewport: SubViewport = _viewports[layer_name]
	var old_config: ViewportConfig = _viewport_configs.get(layer_name)

	# Update memory estimate
	if old_config != null:
		_estimated_memory_mb -= _estimate_viewport_memory(old_config)
		old_config.size = new_size
		_estimated_memory_mb += _estimate_viewport_memory(old_config)

	viewport.size = new_size


## Destroy a viewport.
func destroy_viewport(layer_name: String) -> void:
	if not _viewports.has(layer_name):
		return

	var viewport: SubViewport = _viewports[layer_name]
	var container: SubViewportContainer = _viewport_containers[layer_name]

	# Update memory estimate
	if _viewport_configs.has(layer_name):
		_estimated_memory_mb -= _estimate_viewport_memory(_viewport_configs[layer_name])

	# Remove from tree
	if container != null and is_instance_valid(container):
		container.queue_free()

	_viewports.erase(layer_name)
	_viewport_containers.erase(layer_name)

	viewport_destroyed.emit(layer_name)


## Destroy all viewports.
func destroy_all_viewports() -> void:
	for layer_name in _viewports.keys():
		destroy_viewport(layer_name)


## Get viewport texture for compositing.
func get_viewport_texture(layer_name: String) -> ViewportTexture:
	if _viewports.has(layer_name):
		return _viewports[layer_name].get_texture()
	return null


## Set viewport update mode.
func set_update_mode(layer_name: String, mode: SubViewport.UpdateMode) -> void:
	if _viewports.has(layer_name):
		_viewports[layer_name].render_target_update_mode = mode

		if _viewport_configs.has(layer_name):
			_viewport_configs[layer_name].update_mode = mode


## Force viewport update.
func force_update(layer_name: String) -> void:
	if _viewports.has(layer_name):
		_viewports[layer_name].render_target_update_mode = SubViewport.UPDATE_ONCE


## Get all layer names.
func get_layer_names() -> Array[String]:
	var names: Array[String] = []
	for name in _viewports:
		names.append(name)
	return names


## Check if layer exists.
func has_layer(layer_name: String) -> bool:
	return _viewports.has(layer_name)


## Get layer count.
func get_layer_count() -> int:
	return _viewports.size()


## Get estimated memory usage in MB.
func get_estimated_memory_mb() -> float:
	return _estimated_memory_mb


## Check if within memory budget.
func is_within_memory_budget() -> bool:
	return _estimated_memory_mb <= MEMORY_BUDGET_MB


## Cleanup all viewports.
func cleanup() -> void:
	destroy_all_viewports()
	_viewport_configs.clear()
	_estimated_memory_mb = 0.0


## Get summary for debugging.
func get_summary() -> Dictionary:
	var layer_info: Dictionary = {}
	for layer_name in _viewports:
		var viewport: SubViewport = _viewports[layer_name]
		var container: SubViewportContainer = _viewport_containers.get(layer_name)

		layer_info[layer_name] = {
			"size": viewport.size,
			"visible": container.visible if container != null else false,
			"update_mode": viewport.render_target_update_mode
		}

	return {
		"layer_count": _viewports.size(),
		"estimated_memory_mb": _estimated_memory_mb,
		"memory_budget_mb": MEMORY_BUDGET_MB,
		"within_budget": is_within_memory_budget(),
		"current_zoom": _current_zoom,
		"layers": layer_info
	}
