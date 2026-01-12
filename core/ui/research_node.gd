class_name ResearchNode
extends RefCounted
## ResearchNode represents a single technology node in the research tree.

signal node_clicked(tech_id: String)
signal node_double_clicked(tech_id: String)

## Node sizing (matches ResearchTreePanel)
const NODE_WIDTH := 140
const NODE_HEIGHT := 80

## Technology states
enum TechState {
	LOCKED,       ## Prerequisites not met
	AVAILABLE,    ## Can be researched
	RESEARCHING,  ## Currently researching
	COMPLETED     ## Already researched
}

## State colors
const STATE_COLORS := {
	TechState.LOCKED: Color.RED.darkened(0.3),
	TechState.AVAILABLE: Color.YELLOW,
	TechState.RESEARCHING: Color.CYAN,
	TechState.COMPLETED: Color.GREEN
}

## Node data
var _tech_id := ""
var _tech_name := ""
var _tech_description := ""
var _state := TechState.LOCKED
var _progress := 0.0
var _tier := 0

## UI components
var _container: PanelContainer = null
var _name_label: Label = null
var _state_indicator: ColorRect = null
var _progress_bar: ProgressBar = null
var _tier_label: Label = null

## Faction accent color
var _faction_color := Color("#808080")

## Click tracking for double-click detection
var _last_click_time := 0.0
const DOUBLE_CLICK_TIME := 0.3


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, tech_id: String, data: Dictionary, faction_color: Color) -> Control:
	_tech_id = tech_id
	_faction_color = faction_color
	_tech_name = data.get("name", "Unknown Tech")
	_tech_description = data.get("description", "")
	_state = data.get("state", TechState.LOCKED)
	_progress = data.get("progress", 0.0)
	_tier = data.get("tier", 0)

	# Main container
	_container = PanelContainer.new()
	_container.name = "ResearchNode_%s" % tech_id
	_container.custom_minimum_size = Vector2(NODE_WIDTH, NODE_HEIGHT)

	# Apply panel style based on state
	_apply_state_style()

	# Make clickable
	_container.gui_input.connect(_on_gui_input)
	_container.mouse_entered.connect(_on_mouse_entered)
	_container.mouse_exited.connect(_on_mouse_exited)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_container.add_child(vbox)

	# Tier indicator (small label in corner)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)

	_tier_label = Label.new()
	_tier_label.text = "T%d" % _tier
	_tier_label.add_theme_font_size_override("font_size", 9)
	_tier_label.add_theme_color_override("font_color", Color("#888888"))
	header.add_child(_tier_label)

	# State indicator
	_state_indicator = ColorRect.new()
	_state_indicator.custom_minimum_size = Vector2(8, 8)
	_state_indicator.color = STATE_COLORS[_state]
	header.add_child(_state_indicator)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	vbox.add_child(header)

	# Technology name
	_name_label = Label.new()
	_name_label.text = _tech_name
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_name_label)

	# Progress bar (only visible when researching)
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = _progress * 100.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size.y = 6
	_progress_bar.visible = _state == TechState.RESEARCHING

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.CYAN
	bar_fill.set_corner_radius_all(2)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)

	vbox.add_child(_progress_bar)

	parent.add_child(_container)
	return _container


## Apply style based on current state.
func _apply_state_style() -> void:
	if _container == null:
		return

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)

	match _state:
		TechState.LOCKED:
			style.bg_color = Color("#1a1a1a", 0.8)
			style.border_color = Color("#444444")
		TechState.AVAILABLE:
			style.bg_color = Color("#2a2a1a", 0.9)
			style.border_color = Color.YELLOW.darkened(0.3)
		TechState.RESEARCHING:
			style.bg_color = Color("#1a2a2a", 0.95)
			style.border_color = Color.CYAN
		TechState.COMPLETED:
			style.bg_color = Color("#1a2a1a", 0.9)
			style.border_color = Color.GREEN.darkened(0.2)

	style.set_border_width_all(2)
	_container.add_theme_stylebox_override("panel", style)


## Handle input events.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var current_time := Time.get_ticks_msec() / 1000.0
			if current_time - _last_click_time < DOUBLE_CLICK_TIME:
				node_double_clicked.emit(_tech_id)
			else:
				node_clicked.emit(_tech_id)
			_last_click_time = current_time


## Handle mouse enter.
func _on_mouse_entered() -> void:
	if _container == null:
		return

	# Highlight effect
	var tween := _container.create_tween()
	tween.tween_property(_container, "modulate", Color(1.2, 1.2, 1.2), 0.1)


## Handle mouse exit.
func _on_mouse_exited() -> void:
	if _container == null:
		return

	var tween := _container.create_tween()
	tween.tween_property(_container, "modulate", Color.WHITE, 0.1)


## Update technology state.
func update_state(state: int, progress: float = 0.0) -> void:
	_state = state
	_progress = progress

	_apply_state_style()

	if _state_indicator != null:
		_state_indicator.color = STATE_COLORS[_state]

	if _progress_bar != null:
		_progress_bar.visible = _state == TechState.RESEARCHING
		_progress_bar.value = _progress * 100.0


## Set position.
func set_position(pos: Vector2) -> void:
	if _container != null:
		_container.position = pos


## Get position.
func get_position() -> Vector2:
	if _container != null:
		return _container.position
	return Vector2.ZERO


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])


## Get container.
func get_container() -> Control:
	return _container


## Get tech ID.
func get_tech_id() -> String:
	return _tech_id


## Get state.
func get_state() -> int:
	return _state


## Is available for research.
func is_available() -> bool:
	return _state == TechState.AVAILABLE


## Is completed.
func is_completed() -> bool:
	return _state == TechState.COMPLETED


## Is locked.
func is_locked() -> bool:
	return _state == TechState.LOCKED


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
