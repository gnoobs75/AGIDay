class_name ResearchPanel
extends RefCounted
## ResearchPanel displays current tech level and research progress.

signal research_clicked()
signal research_complete(tech_name: String)

## Panel sizing
const PANEL_WIDTH := 200
const PANEL_HEIGHT := 80

## Current values
var _tech_level := 0
var _current_tech := ""
var _research_progress := 0.0

## UI components
var _container: PanelContainer = null
var _level_label: Label = null
var _tech_label: Label = null
var _progress_bar: ProgressBar = null
var _progress_label: Label = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "ResearchPanel"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d", 0.7)
	style.border_color = _faction_color.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_container.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_container.add_child(vbox)

	# Header with tech level
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var icon := Label.new()
	icon.text = "[RES]"
	icon.add_theme_color_override("font_color", Color.CYAN)
	icon.add_theme_font_size_override("font_size", 12)
	header.add_child(icon)

	_level_label = Label.new()
	_level_label.text = "Tech Level 0"
	_level_label.add_theme_font_size_override("font_size", 14)
	_level_label.add_theme_color_override("font_color", Color.WHITE)
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_level_label)

	vbox.add_child(header)

	# Current research name
	_tech_label = Label.new()
	_tech_label.text = "No research"
	_tech_label.add_theme_font_size_override("font_size", 12)
	_tech_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	_tech_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(_tech_label)

	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size.y = 10

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.CYAN
	bar_fill.set_corner_radius_all(2)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)

	vbox.add_child(_progress_bar)

	# Progress percentage
	_progress_label = Label.new()
	_progress_label.text = "0%"
	_progress_label.add_theme_font_size_override("font_size", 10)
	_progress_label.add_theme_color_override("font_color", Color("#666666"))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_progress_label)

	parent.add_child(_container)
	return _container


## Update research display.
func update_research(tech_level: int, current_tech: String, progress: float) -> void:
	var was_complete := _research_progress >= 100.0
	var old_tech := _current_tech

	_tech_level = tech_level
	_current_tech = current_tech
	_research_progress = clampf(progress, 0.0, 100.0)

	_update_display()

	# Check for completion
	if _research_progress >= 100.0 and not was_complete and not old_tech.is_empty():
		research_complete.emit(old_tech)


## Update display elements.
func _update_display() -> void:
	if _level_label != null:
		_level_label.text = "Tech Level %d" % _tech_level

	if _tech_label != null:
		if _current_tech.is_empty():
			_tech_label.text = "No research"
			_tech_label.add_theme_color_override("font_color", Color("#666666"))
		else:
			_tech_label.text = _current_tech
			_tech_label.add_theme_color_override("font_color", Color("#aaaaaa"))

	if _progress_bar != null:
		_progress_bar.value = _research_progress

		# Hide bar if no research
		_progress_bar.visible = not _current_tech.is_empty()

	if _progress_label != null:
		if _current_tech.is_empty():
			_progress_label.text = ""
		else:
			_progress_label.text = "%.0f%%" % _research_progress


## Set available research options (for tooltip/click).
func set_available_research(options: Array[String]) -> void:
	# Could be used for dropdown or tooltip
	pass


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _container != null:
		var style := _container.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = _faction_color.darkened(0.3)


## Get container.
func get_container() -> Control:
	return _container


## Get current values.
func get_research_state() -> Dictionary:
	return {
		"tech_level": _tech_level,
		"current_tech": _current_tech,
		"progress": _research_progress
	}


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_level_label = null
	_tech_label = null
	_progress_bar = null
	_progress_label = null
