class_name ViewportCompositor
extends RefCounted
## ViewportCompositor combines multiple viewport layers into the final output.

signal composition_updated()

## Composition order (lower = rendered first/behind)
const LAYER_ORDER := {
	ViewportLayerManager.LAYER_MAIN: 0,
	ViewportLayerManager.LAYER_FACTORY_DETAIL: 1,
	ViewportLayerManager.LAYER_MINIMAP: 2,
	ViewportLayerManager.LAYER_UI: 3
}

## Layer blend modes
enum BlendMode {
	NORMAL,
	ADDITIVE,
	MULTIPLY,
	OVERLAY
}

## Composition settings per layer
var _layer_settings: Dictionary = {}  ## layer_name -> LayerSettings

## Viewport manager reference
var _viewport_manager: ViewportLayerManager = null

## Output canvas
var _output_canvas: CanvasLayer = null
var _layer_sprites: Dictionary = {}  ## layer_name -> TextureRect


## Layer settings class
class LayerSettings:
	var blend_mode: BlendMode = BlendMode.NORMAL
	var opacity: float = 1.0
	var visible: bool = true
	var position: Vector2 = Vector2.ZERO
	var scale: Vector2 = Vector2.ONE
	var z_index: int = 0


func _init() -> void:
	_setup_default_settings()


## Set up default layer settings.
func _setup_default_settings() -> void:
	# Main layer
	var main_settings := LayerSettings.new()
	main_settings.z_index = 0
	_layer_settings[ViewportLayerManager.LAYER_MAIN] = main_settings

	# Factory detail layer
	var factory_settings := LayerSettings.new()
	factory_settings.z_index = 1
	_layer_settings[ViewportLayerManager.LAYER_FACTORY_DETAIL] = factory_settings

	# Minimap layer
	var minimap_settings := LayerSettings.new()
	minimap_settings.z_index = 2
	minimap_settings.position = Vector2(20, 20)  # Top-left offset
	_layer_settings[ViewportLayerManager.LAYER_MINIMAP] = minimap_settings

	# UI layer
	var ui_settings := LayerSettings.new()
	ui_settings.z_index = 3
	_layer_settings[ViewportLayerManager.LAYER_UI] = ui_settings


## Initialize with viewport manager and output node.
func initialize(viewport_manager: ViewportLayerManager, output_parent: Node) -> void:
	_viewport_manager = viewport_manager

	# Create output canvas layer
	_output_canvas = CanvasLayer.new()
	_output_canvas.name = "CompositorCanvas"
	_output_canvas.layer = 100  # Above most other canvas layers
	output_parent.add_child(_output_canvas)

	# Create sprites for each layer
	_create_layer_sprites()


## Create TextureRect for each viewport layer.
func _create_layer_sprites() -> void:
	if _viewport_manager == null:
		return

	var sorted_layers := _get_sorted_layers()

	for layer_name in sorted_layers:
		var viewport := _viewport_manager.get_viewport(layer_name)
		if viewport == null:
			continue

		var sprite := TextureRect.new()
		sprite.name = "LayerSprite_%s" % layer_name
		sprite.texture = viewport.get_texture()
		sprite.stretch_mode = TextureRect.STRETCH_SCALE

		# Apply settings
		var settings: LayerSettings = _layer_settings.get(layer_name)
		if settings != null:
			sprite.modulate.a = settings.opacity
			sprite.position = settings.position
			sprite.scale = settings.scale
			sprite.visible = settings.visible
			sprite.z_index = settings.z_index

		_output_canvas.add_child(sprite)
		_layer_sprites[layer_name] = sprite


## Get layers sorted by render order.
func _get_sorted_layers() -> Array[String]:
	var layers: Array[String] = []

	for layer_name in _viewport_manager.get_layer_names():
		layers.append(layer_name)

	layers.sort_custom(func(a, b): return LAYER_ORDER.get(a, 0) < LAYER_ORDER.get(b, 0))

	return layers


## Update composition (call when viewports change).
func update_composition() -> void:
	if _viewport_manager == null:
		return

	for layer_name in _layer_sprites:
		var sprite: TextureRect = _layer_sprites[layer_name]
		var viewport := _viewport_manager.get_viewport(layer_name)

		if viewport != null:
			sprite.texture = viewport.get_texture()

		# Sync visibility with viewport container
		var container := _viewport_manager.get_container(layer_name)
		if container != null:
			sprite.visible = container.visible

	composition_updated.emit()


## Set layer opacity.
func set_layer_opacity(layer_name: String, opacity: float) -> void:
	if _layer_settings.has(layer_name):
		_layer_settings[layer_name].opacity = clampf(opacity, 0.0, 1.0)

	if _layer_sprites.has(layer_name):
		_layer_sprites[layer_name].modulate.a = opacity


## Set layer visibility.
func set_layer_visible(layer_name: String, visible: bool) -> void:
	if _layer_settings.has(layer_name):
		_layer_settings[layer_name].visible = visible

	if _layer_sprites.has(layer_name):
		_layer_sprites[layer_name].visible = visible


## Set layer position.
func set_layer_position(layer_name: String, position: Vector2) -> void:
	if _layer_settings.has(layer_name):
		_layer_settings[layer_name].position = position

	if _layer_sprites.has(layer_name):
		_layer_sprites[layer_name].position = position


## Set layer scale.
func set_layer_scale(layer_name: String, scale: Vector2) -> void:
	if _layer_settings.has(layer_name):
		_layer_settings[layer_name].scale = scale

	if _layer_sprites.has(layer_name):
		_layer_sprites[layer_name].scale = scale


## Set layer z-index.
func set_layer_z_index(layer_name: String, z_index: int) -> void:
	if _layer_settings.has(layer_name):
		_layer_settings[layer_name].z_index = z_index

	if _layer_sprites.has(layer_name):
		_layer_sprites[layer_name].z_index = z_index


## Add a new layer to composition.
func add_layer(layer_name: String, settings: LayerSettings = null) -> void:
	if settings == null:
		settings = LayerSettings.new()

	_layer_settings[layer_name] = settings

	# Create sprite if viewport exists
	if _viewport_manager != null and _output_canvas != null:
		var viewport := _viewport_manager.get_viewport(layer_name)
		if viewport != null:
			var sprite := TextureRect.new()
			sprite.name = "LayerSprite_%s" % layer_name
			sprite.texture = viewport.get_texture()
			sprite.stretch_mode = TextureRect.STRETCH_SCALE
			sprite.modulate.a = settings.opacity
			sprite.position = settings.position
			sprite.scale = settings.scale
			sprite.visible = settings.visible
			sprite.z_index = settings.z_index

			_output_canvas.add_child(sprite)
			_layer_sprites[layer_name] = sprite


## Remove a layer from composition.
func remove_layer(layer_name: String) -> void:
	if _layer_sprites.has(layer_name):
		var sprite: TextureRect = _layer_sprites[layer_name]
		if is_instance_valid(sprite):
			sprite.queue_free()
		_layer_sprites.erase(layer_name)

	_layer_settings.erase(layer_name)


## Get layer settings.
func get_layer_settings(layer_name: String) -> LayerSettings:
	return _layer_settings.get(layer_name)


## Fade layer in/out (would need tween in real implementation).
func fade_layer(layer_name: String, target_opacity: float, duration: float) -> void:
	# Simplified - just set opacity directly
	# Full implementation would use Tween
	set_layer_opacity(layer_name, target_opacity)


## Cleanup.
func cleanup() -> void:
	for layer_name in _layer_sprites.keys():
		remove_layer(layer_name)

	if _output_canvas != null and is_instance_valid(_output_canvas):
		_output_canvas.queue_free()

	_layer_settings.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var layer_info: Dictionary = {}
	for layer_name in _layer_settings:
		var settings: LayerSettings = _layer_settings[layer_name]
		layer_info[layer_name] = {
			"opacity": settings.opacity,
			"visible": settings.visible,
			"z_index": settings.z_index,
			"position": settings.position
		}

	return {
		"layer_count": _layer_sprites.size(),
		"has_canvas": _output_canvas != null,
		"layers": layer_info
	}
