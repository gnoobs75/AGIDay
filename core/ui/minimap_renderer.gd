class_name MinimapRenderer
extends RefCounted
## MinimapRenderer handles viewport-based minimap texture generation.

signal render_complete()

## Render state
var _render_size: int = 512
var _viewport: SubViewport = null
var _canvas: CanvasLayer = null
var _background: ColorRect = null
var _render_texture: ViewportTexture = null

## Layer containers for drawing
var _terrain_layer: Control = null
var _district_layer: Control = null
var _building_layer: Control = null
var _unit_layer: Control = null
var _fog_layer: Control = null
var _power_layer: Control = null

## Drawing state
var _is_initialized := false
var _needs_redraw := true


func _init() -> void:
	pass


## Initialize renderer with size.
func initialize(size: int) -> void:
	_render_size = size
	_create_viewport()
	_is_initialized = true


## Create the render viewport.
func _create_viewport() -> void:
	# Create SubViewport
	_viewport = SubViewport.new()
	_viewport.name = "MinimapViewport"
	_viewport.size = Vector2i(_render_size, _render_size)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR

	# Background color
	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = Color("#1a1a1a")
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_background)

	# Create layer containers
	_terrain_layer = Control.new()
	_terrain_layer.name = "TerrainLayer"
	_terrain_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_terrain_layer)

	_district_layer = Control.new()
	_district_layer.name = "DistrictLayer"
	_district_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_district_layer)

	_power_layer = Control.new()
	_power_layer.name = "PowerLayer"
	_power_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_power_layer)

	_building_layer = Control.new()
	_building_layer.name = "BuildingLayer"
	_building_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_building_layer)

	_unit_layer = Control.new()
	_unit_layer.name = "UnitLayer"
	_unit_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_unit_layer)

	_fog_layer = Control.new()
	_fog_layer.name = "FogLayer"
	_fog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_fog_layer)


## Get SubViewport for adding to scene tree.
func get_viewport() -> SubViewport:
	return _viewport


## Get render texture.
func get_texture() -> Texture2D:
	if _viewport == null:
		return null
	return _viewport.get_texture()


## Get terrain layer.
func get_terrain_layer() -> Control:
	return _terrain_layer


## Get district layer.
func get_district_layer() -> Control:
	return _district_layer


## Get building layer.
func get_building_layer() -> Control:
	return _building_layer


## Get unit layer.
func get_unit_layer() -> Control:
	return _unit_layer


## Get fog layer.
func get_fog_layer() -> Control:
	return _fog_layer


## Get power layer.
func get_power_layer() -> Control:
	return _power_layer


## Get render size.
func get_render_size() -> int:
	return _render_size


## Convert world coordinates to minimap coordinates.
func world_to_minimap(world_x: float, world_z: float, world_size: float = 512.0) -> Vector2:
	return Vector2(
		(world_x / world_size) * _render_size,
		(world_z / world_size) * _render_size
	)


## Set layer visibility.
func set_layer_visible(layer_name: String, visible: bool) -> void:
	var layer: Control = null

	match layer_name:
		"terrain": layer = _terrain_layer
		"districts": layer = _district_layer
		"buildings": layer = _building_layer
		"units": layer = _unit_layer
		"fog": layer = _fog_layer
		"power_grid": layer = _power_layer

	if layer != null:
		layer.visible = visible


## Request redraw.
func request_redraw() -> void:
	_needs_redraw = true


## Clear a specific layer.
func clear_layer(layer_name: String) -> void:
	var layer: Control = null

	match layer_name:
		"terrain": layer = _terrain_layer
		"districts": layer = _district_layer
		"buildings": layer = _building_layer
		"units": layer = _unit_layer
		"fog": layer = _fog_layer
		"power_grid": layer = _power_layer

	if layer != null:
		for child in layer.get_children():
			child.queue_free()


## Clear all layers.
func clear_all() -> void:
	clear_layer("terrain")
	clear_layer("districts")
	clear_layer("buildings")
	clear_layer("units")
	clear_layer("fog")
	clear_layer("power_grid")


## Check if initialized.
func is_initialized() -> bool:
	return _is_initialized


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"render_size": _render_size,
		"is_initialized": _is_initialized,
		"has_viewport": _viewport != null,
		"terrain_children": _terrain_layer.get_child_count() if _terrain_layer else 0,
		"building_children": _building_layer.get_child_count() if _building_layer else 0,
		"unit_children": _unit_layer.get_child_count() if _unit_layer else 0
	}


## Cleanup.
func cleanup() -> void:
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()

	_viewport = null
	_canvas = null
	_background = null
	_terrain_layer = null
	_district_layer = null
	_building_layer = null
	_unit_layer = null
	_fog_layer = null
	_power_layer = null
	_is_initialized = false
