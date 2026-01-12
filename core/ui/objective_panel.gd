class_name ObjectivePanel
extends RefCounted
## ObjectivePanel displays current mission objectives for tactical view.

signal objective_clicked(objective_id: String)
signal objective_complete(objective_id: String)

## Panel sizing
const PANEL_WIDTH := 300
const PANEL_HEIGHT := 60

## Current objective data
var _objective_text := ""
var _objective_progress := -1.0  ## -1 = no progress bar
var _objective_id := ""

## UI components
var _container: PanelContainer = null
var _objective_label: Label = null
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
	_container.name = "ObjectivePanel"
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

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var icon := Label.new()
	icon.text = "[OBJ]"
	icon.add_theme_color_override("font_color", Color.GOLD)
	icon.add_theme_font_size_override("font_size", 12)
	header.add_child(icon)

	var title := Label.new()
	title.text = "Current Objective"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("#888888"))
	header.add_child(title)

	vbox.add_child(header)

	# Objective text
	_objective_label = Label.new()
	_objective_label.text = "No active objective"
	_objective_label.add_theme_font_size_override("font_size", 14)
	_objective_label.add_theme_color_override("font_color", Color.WHITE)
	_objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_objective_label)

	# Progress section (optional)
	var progress_hbox := HBoxContainer.new()
	progress_hbox.add_theme_constant_override("separation", 8)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0, 8)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.visible = false

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.GOLD
	bar_fill.set_corner_radius_all(2)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)

	progress_hbox.add_child(_progress_bar)

	_progress_label = Label.new()
	_progress_label.text = ""
	_progress_label.add_theme_font_size_override("font_size", 10)
	_progress_label.add_theme_color_override("font_color", Color("#888888"))
	_progress_label.custom_minimum_size.x = 40
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_label.visible = false
	progress_hbox.add_child(_progress_label)

	vbox.add_child(progress_hbox)

	parent.add_child(_container)
	return _container


## Update objective display.
func update_objective(text: String, progress: float = -1.0, objective_id: String = "") -> void:
	var old_progress := _objective_progress

	_objective_text = text
	_objective_progress = progress
	_objective_id = objective_id

	_update_display()

	# Check for completion
	if progress >= 100.0 and old_progress < 100.0 and not objective_id.is_empty():
		objective_complete.emit(objective_id)


## Update display elements.
func _update_display() -> void:
	if _objective_label != null:
		if _objective_text.is_empty():
			_objective_label.text = "No active objective"
			_objective_label.add_theme_color_override("font_color", Color("#666666"))
		else:
			_objective_label.text = _objective_text
			_objective_label.add_theme_color_override("font_color", Color.WHITE)

	# Show/hide progress bar
	var show_progress := _objective_progress >= 0.0

	if _progress_bar != null:
		_progress_bar.visible = show_progress
		if show_progress:
			_progress_bar.value = _objective_progress

	if _progress_label != null:
		_progress_label.visible = show_progress
		if show_progress:
			_progress_label.text = "%.0f%%" % _objective_progress


## Set sub-objectives for complex missions.
func set_sub_objectives(objectives: Array[Dictionary]) -> void:
	# Could add sub-objective list here
	# Each dict: {text: String, complete: bool}
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


## Get current objective.
func get_objective() -> Dictionary:
	return {
		"text": _objective_text,
		"progress": _objective_progress,
		"id": _objective_id
	}


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_objective_label = null
	_progress_bar = null
	_progress_label = null
