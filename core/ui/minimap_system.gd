class_name MinimapSystem
extends RefCounted
## MinimapSystem provides real-time minimap with unit positions, fog, and interaction.

signal minimap_clicked(world_position: Vector3)
signal minimap_dragged(start_world: Vector3, end_world: Vector3)
signal layer_toggled(layer_name: String, visible: bool)
signal camera_pan_requested(world_position: Vector3)

## Minimap sizing
const RENDER_SIZE := 512      ## Internal render resolution
const DISPLAY_SIZE := 256     ## Display size in pixels
const BORDER_WIDTH := 2
const MARGIN := 16            ## Margin from screen edge

## Update frequencies
const UPDATE_RATE_NORMAL := 1.0 / 60.0   ## 60Hz
const UPDATE_RATE_PERF := 1.0 / 30.0     ## 30Hz

## World bounds (matches 512x512 voxel grid)
const WORLD_MIN := Vector3(0, 0, 0)
const WORLD_MAX := Vector3(512, 64, 512)

## Subsystems
var _renderer: MinimapRenderer = null
var _content: MinimapContent = null
var _interaction: MinimapInteraction = null

## UI components
var _container: Control = null
var _minimap_rect: TextureRect = null
var _border_panel: Panel = null
var _view_indicator: Control = null

## State
var _is_initialized := false
var _performance_mode := false
var _update_timer := 0.0
var _current_faction := "neutral"

## Layer visibility
var _layer_visibility := {
	"units": true,
	"buildings": true,
	"fog": true,
	"districts": true,
	"power_grid": false,
	"resources": false
}


func _init() -> void:
	_renderer = MinimapRenderer.new()
	_content = MinimapContent.new()
	_interaction = MinimapInteraction.new()

	# Wire up signals
	_interaction.minimap_clicked.connect(_on_minimap_clicked)
	_interaction.minimap_dragged.connect(_on_minimap_dragged)


## Initialize minimap.
func initialize(parent: Control, faction_id: String = "neutral") -> void:
	_current_faction = faction_id

	_create_ui(parent)
	_renderer.initialize(RENDER_SIZE)
	_content.initialize(_renderer)
	_interaction.initialize(_minimap_rect, RENDER_SIZE, DISPLAY_SIZE)

	_is_initialized = true


## Create UI components.
func _create_ui(parent: Control) -> void:
	var faction_color := UITheme.FACTION_COLORS.get(_current_faction, UITheme.FACTION_COLORS["neutral"])

	# Main container anchored to bottom-right
	_container = Control.new()
	_container.name = "MinimapContainer"
	_container.custom_minimum_size = Vector2(DISPLAY_SIZE + BORDER_WIDTH * 2, DISPLAY_SIZE + BORDER_WIDTH * 2)
	_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_container.position = Vector2(-DISPLAY_SIZE - BORDER_WIDTH * 2 - MARGIN, -DISPLAY_SIZE - BORDER_WIDTH * 2 - MARGIN)

	# Border panel
	_border_panel = Panel.new()
	_border_panel.name = "MinimapBorder"
	_border_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color("#1a1a1a")
	border_style.border_color = faction_color
	border_style.set_border_width_all(BORDER_WIDTH)
	border_style.set_corner_radius_all(0)
	_border_panel.add_theme_stylebox_override("panel", border_style)
	_container.add_child(_border_panel)

	# Minimap texture display
	_minimap_rect = TextureRect.new()
	_minimap_rect.name = "MinimapTexture"
	_minimap_rect.position = Vector2(BORDER_WIDTH, BORDER_WIDTH)
	_minimap_rect.size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	_minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_container.add_child(_minimap_rect)

	# Camera view indicator overlay
	_view_indicator = Control.new()
	_view_indicator.name = "ViewIndicator"
	_view_indicator.position = Vector2(BORDER_WIDTH, BORDER_WIDTH)
	_view_indicator.size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	_view_indicator.draw.connect(_draw_view_indicator)
	_container.add_child(_view_indicator)

	parent.add_child(_container)


## Update minimap (call each frame).
func update(delta: float) -> void:
	if not _is_initialized:
		return

	var update_rate := UPDATE_RATE_PERF if _performance_mode else UPDATE_RATE_NORMAL

	_update_timer += delta
	if _update_timer >= update_rate:
		_update_timer -= update_rate
		_update_minimap()


## Update minimap content.
func _update_minimap() -> void:
	# Render content to texture
	_content.render_to_texture(_layer_visibility)

	# Update display texture
	var texture := _renderer.get_texture()
	if texture != null:
		_minimap_rect.texture = texture

	# Request view indicator redraw
	_view_indicator.queue_redraw()


## Draw camera view indicator.
func _draw_view_indicator() -> void:
	if _view_indicator == null:
		return

	# Get camera view bounds from interaction system
	var view_rect := _interaction.get_camera_view_rect()
	if view_rect.size == Vector2.ZERO:
		return

	# Draw rectangle outline
	var faction_color := UITheme.FACTION_COLORS.get(_current_faction, Color.WHITE)
	_view_indicator.draw_rect(view_rect, faction_color, false, 2.0)


## Set camera view bounds for indicator.
func set_camera_view(camera_position: Vector3, camera_size: Vector2) -> void:
	# Convert world position to minimap coords
	var minimap_pos := world_to_minimap(camera_position)
	var minimap_size := camera_size * (float(DISPLAY_SIZE) / (WORLD_MAX.x - WORLD_MIN.x))

	_interaction.set_camera_view_rect(Rect2(minimap_pos - minimap_size * 0.5, minimap_size))
	_view_indicator.queue_redraw()


## Convert world position to minimap coordinates.
func world_to_minimap(world_pos: Vector3) -> Vector2:
	var normalized := Vector2(
		(world_pos.x - WORLD_MIN.x) / (WORLD_MAX.x - WORLD_MIN.x),
		(world_pos.z - WORLD_MIN.z) / (WORLD_MAX.z - WORLD_MIN.z)
	)
	return normalized * DISPLAY_SIZE


## Convert minimap coordinates to world position.
func minimap_to_world(minimap_pos: Vector2) -> Vector3:
	var normalized := minimap_pos / DISPLAY_SIZE
	return Vector3(
		WORLD_MIN.x + normalized.x * (WORLD_MAX.x - WORLD_MIN.x),
		0,
		WORLD_MIN.z + normalized.y * (WORLD_MAX.z - WORLD_MIN.z)
	)


## Add unit to minimap.
func add_unit(unit_id: int, position: Vector3, faction_id: String) -> void:
	_content.add_unit(unit_id, position, faction_id)


## Update unit position.
func update_unit(unit_id: int, position: Vector3) -> void:
	_content.update_unit(unit_id, position)


## Remove unit from minimap.
func remove_unit(unit_id: int) -> void:
	_content.remove_unit(unit_id)


## Add building to minimap.
func add_building(building_id: int, position: Vector3, faction_id: String, size: float = 1.0) -> void:
	_content.add_building(building_id, position, faction_id, size)


## Remove building from minimap.
func remove_building(building_id: int) -> void:
	_content.remove_building(building_id)


## Update fog of war.
func update_fog(fog_texture: ImageTexture) -> void:
	_content.set_fog_texture(fog_texture)


## Update district control.
func update_district(district_id: int, bounds: Rect2, faction_id: String) -> void:
	_content.update_district(district_id, bounds, faction_id)


## Toggle layer visibility.
func toggle_layer(layer_name: String) -> void:
	if _layer_visibility.has(layer_name):
		_layer_visibility[layer_name] = not _layer_visibility[layer_name]
		layer_toggled.emit(layer_name, _layer_visibility[layer_name])


## Set layer visibility.
func set_layer_visible(layer_name: String, visible: bool) -> void:
	if _layer_visibility.has(layer_name):
		_layer_visibility[layer_name] = visible
		layer_toggled.emit(layer_name, visible)


## Is layer visible.
func is_layer_visible(layer_name: String) -> bool:
	return _layer_visibility.get(layer_name, false)


## Set performance mode.
func set_performance_mode(enabled: bool) -> void:
	_performance_mode = enabled


## Set faction theme.
func set_faction(faction_id: String) -> void:
	_current_faction = faction_id

	var faction_color := UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _border_panel != null:
		var style := _border_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = faction_color


## Handle minimap click.
func _on_minimap_clicked(minimap_pos: Vector2) -> void:
	var world_pos := minimap_to_world(minimap_pos)
	minimap_clicked.emit(world_pos)
	camera_pan_requested.emit(world_pos)


## Handle minimap drag.
func _on_minimap_dragged(start: Vector2, end: Vector2) -> void:
	var start_world := minimap_to_world(start)
	var end_world := minimap_to_world(end)
	minimap_dragged.emit(start_world, end_world)


## Get container for positioning.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"is_initialized": _is_initialized,
		"performance_mode": _performance_mode,
		"faction": _current_faction,
		"layers": _layer_visibility.duplicate(),
		"unit_count": _content.get_unit_count() if _content != null else 0,
		"building_count": _content.get_building_count() if _content != null else 0
	}


## Cleanup.
func cleanup() -> void:
	if _renderer != null:
		_renderer.cleanup()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()

	_container = null
	_minimap_rect = null
	_border_panel = null
	_view_indicator = null
	_is_initialized = false
