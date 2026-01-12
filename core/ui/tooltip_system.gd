class_name TooltipSystem
extends RefCounted
## TooltipSystem manages tooltip display, caching, and pooling.

signal tooltip_shown(control: Control)
signal tooltip_hidden()

## Timing constants
const HOVER_DELAY := 0.5           ## Seconds before tooltip appears
const FADE_IN_TIME := 0.2          ## Fade-in animation duration
const FADE_OUT_TIME := 0.1         ## Fade-out duration
const CURSOR_OFFSET := Vector2(8, 8)  ## Offset from cursor

## Performance mode timing (instant)
const PERF_HOVER_DELAY := 0.0
const PERF_FADE_TIME := 0.0

## Styling constants
const MAX_WIDTH := 300
const PADDING := 6
const FONT_SIZE := 11
const BACKGROUND_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const TEXT_COLOR := Color.WHITE
const BORDER_WIDTH := 1

## State
var _enabled := true
var _performance_mode := false
var _current_tooltip: Control = null
var _hover_timer := 0.0
var _is_hovering := false
var _pending_control: Control = null
var _cached_tooltips: Dictionary = {}  ## control_id -> TooltipData
var _tooltip_pool: Array[PanelContainer] = []
var _pool_size := 5

## Faction color for border
var _faction_color := Color.CYAN

## Container for tooltips
var _container: CanvasLayer = null


func _init() -> void:
	pass


## Initialize the tooltip system.
func initialize(root: Node) -> void:
	# Create canvas layer for tooltips (always on top)
	_container = CanvasLayer.new()
	_container.name = "TooltipLayer"
	_container.layer = 100
	root.add_child(_container)

	# Pre-create tooltip pool
	for i in _pool_size:
		var tooltip := _create_tooltip_panel()
		tooltip.visible = false
		_container.add_child(tooltip)
		_tooltip_pool.append(tooltip)


## Create a tooltip panel.
func _create_tooltip_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Tooltip"
	panel.custom_minimum_size.x = 0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND_COLOR
	style.border_color = _faction_color
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(PADDING)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", FONT_SIZE + 2)
	title.add_theme_color_override("font_color", _faction_color)
	vbox.add_child(title)

	# Description
	var desc := Label.new()
	desc.name = "Description"
	desc.add_theme_font_size_override("font_size", FONT_SIZE)
	desc.add_theme_color_override("font_color", TEXT_COLOR)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = MAX_WIDTH - PADDING * 2
	vbox.add_child(desc)

	# Hotkey
	var hotkey := Label.new()
	hotkey.name = "Hotkey"
	hotkey.add_theme_font_size_override("font_size", FONT_SIZE)
	hotkey.add_theme_color_override("font_color", Color("#888888"))
	hotkey.visible = false
	vbox.add_child(hotkey)

	# Status
	var status := Label.new()
	status.name = "Status"
	status.add_theme_font_size_override("font_size", FONT_SIZE)
	status.add_theme_color_override("font_color", Color.GREEN)
	status.visible = false
	vbox.add_child(status)

	return panel


## Register a control for tooltips.
func register_tooltip(control: Control, data: Dictionary) -> void:
	if control == null:
		return

	var control_id := control.get_instance_id()
	_cached_tooltips[control_id] = data

	# Connect signals
	if not control.mouse_entered.is_connected(_on_control_mouse_entered):
		control.mouse_entered.connect(func(): _on_control_mouse_entered(control))
	if not control.mouse_exited.is_connected(_on_control_mouse_exited):
		control.mouse_exited.connect(func(): _on_control_mouse_exited(control))


## Unregister a control.
func unregister_tooltip(control: Control) -> void:
	if control == null:
		return

	var control_id := control.get_instance_id()
	_cached_tooltips.erase(control_id)


## Update tooltip content for a control.
func update_tooltip_content(control: Control, data: Dictionary) -> void:
	if control == null:
		return

	var control_id := control.get_instance_id()
	_cached_tooltips[control_id] = data

	# If this tooltip is currently shown, update it
	if _pending_control == control and _current_tooltip != null:
		_apply_tooltip_data(_current_tooltip, data)


## Update each frame (call from _process).
func update(delta: float, mouse_position: Vector2) -> void:
	if not _enabled:
		return

	if _is_hovering and _pending_control != null:
		_hover_timer += delta

		var delay := PERF_HOVER_DELAY if _performance_mode else HOVER_DELAY
		if _hover_timer >= delay and _current_tooltip == null:
			_show_tooltip(_pending_control, mouse_position)

	# Update tooltip position
	if _current_tooltip != null and _current_tooltip.visible:
		_update_tooltip_position(mouse_position)


## Handle mouse entering a control.
func _on_control_mouse_entered(control: Control) -> void:
	if not _enabled:
		return

	_is_hovering = true
	_pending_control = control
	_hover_timer = 0.0


## Handle mouse exiting a control.
func _on_control_mouse_exited(_control: Control) -> void:
	_is_hovering = false
	_pending_control = null
	_hover_timer = 0.0
	_hide_tooltip()


## Show tooltip for control.
func _show_tooltip(control: Control, position: Vector2) -> void:
	var control_id := control.get_instance_id()
	if not _cached_tooltips.has(control_id):
		return

	var data: Dictionary = _cached_tooltips[control_id]

	# Get tooltip from pool
	_current_tooltip = _get_pooled_tooltip()
	if _current_tooltip == null:
		return

	_apply_tooltip_data(_current_tooltip, data)
	_update_tooltip_position(position)

	# Show with animation
	_current_tooltip.visible = true
	_current_tooltip.modulate.a = 0.0

	var fade_time := PERF_FADE_TIME if _performance_mode else FADE_IN_TIME
	if fade_time > 0:
		var tween := _current_tooltip.create_tween()
		tween.tween_property(_current_tooltip, "modulate:a", 1.0, fade_time)
	else:
		_current_tooltip.modulate.a = 1.0

	tooltip_shown.emit(control)


## Hide current tooltip.
func _hide_tooltip() -> void:
	if _current_tooltip == null:
		return

	var fade_time := PERF_FADE_TIME if _performance_mode else FADE_OUT_TIME
	if fade_time > 0:
		var tween := _current_tooltip.create_tween()
		tween.tween_property(_current_tooltip, "modulate:a", 0.0, fade_time)
		tween.tween_callback(func():
			if _current_tooltip != null:
				_current_tooltip.visible = false
				_return_to_pool(_current_tooltip)
				_current_tooltip = null
		)
	else:
		_current_tooltip.visible = false
		_return_to_pool(_current_tooltip)
		_current_tooltip = null

	tooltip_hidden.emit()


## Apply data to tooltip panel.
func _apply_tooltip_data(tooltip: PanelContainer, data: Dictionary) -> void:
	var content := tooltip.get_node("Content")
	if content == null:
		return

	# Title
	var title := content.get_node("Title") as Label
	if title != null:
		title.text = data.get("title", "")
		title.visible = not data.get("title", "").is_empty()

	# Description
	var desc := content.get_node("Description") as Label
	if desc != null:
		desc.text = data.get("description", "")
		desc.visible = not data.get("description", "").is_empty()

	# Hotkey
	var hotkey := content.get_node("Hotkey") as Label
	if hotkey != null:
		var hotkey_text: String = data.get("hotkey", "")
		if not hotkey_text.is_empty():
			hotkey.text = "Hotkey: " + hotkey_text
			hotkey.visible = true
		else:
			hotkey.visible = false

	# Status
	var status := content.get_node("Status") as Label
	if status != null:
		var status_text: String = data.get("status", "")
		if not status_text.is_empty():
			status.text = status_text
			# Color based on status
			if status_text.begins_with("Available"):
				status.add_theme_color_override("font_color", Color.GREEN)
			elif status_text.begins_with("Cooldown"):
				status.add_theme_color_override("font_color", Color.ORANGE)
			elif status_text.begins_with("Disabled"):
				status.add_theme_color_override("font_color", Color.RED)
			else:
				status.add_theme_color_override("font_color", Color.WHITE)
			status.visible = true
		else:
			status.visible = false

	# Update border color
	var style := tooltip.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		style.border_color = _faction_color


## Update tooltip position to follow cursor.
func _update_tooltip_position(mouse_pos: Vector2) -> void:
	if _current_tooltip == null:
		return

	var tooltip_size := _current_tooltip.size
	var viewport_size := _container.get_viewport().get_visible_rect().size

	var pos := mouse_pos + CURSOR_OFFSET

	# Keep on screen
	if pos.x + tooltip_size.x > viewport_size.x:
		pos.x = mouse_pos.x - tooltip_size.x - CURSOR_OFFSET.x
	if pos.y + tooltip_size.y > viewport_size.y:
		pos.y = mouse_pos.y - tooltip_size.y - CURSOR_OFFSET.y

	_current_tooltip.position = pos


## Get tooltip from pool.
func _get_pooled_tooltip() -> PanelContainer:
	for tooltip in _tooltip_pool:
		if not tooltip.visible:
			return tooltip

	# Pool exhausted, create new one
	var tooltip := _create_tooltip_panel()
	_container.add_child(tooltip)
	_tooltip_pool.append(tooltip)
	return tooltip


## Return tooltip to pool.
func _return_to_pool(tooltip: PanelContainer) -> void:
	tooltip.visible = false


## Set enabled state.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_hide_tooltip()


## Set performance mode.
func set_performance_mode(enabled: bool) -> void:
	_performance_mode = enabled


## Set faction color.
func set_faction_color(color: Color) -> void:
	_faction_color = color


## Is tooltip currently visible.
func is_showing() -> bool:
	return _current_tooltip != null and _current_tooltip.visible


## Clear all cached tooltips.
func clear_cache() -> void:
	_cached_tooltips.clear()


## Cleanup.
func cleanup() -> void:
	_hide_tooltip()
	_cached_tooltips.clear()
	_tooltip_pool.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
