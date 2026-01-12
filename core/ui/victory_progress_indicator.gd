class_name VictoryProgressIndicator
extends RefCounted
## VictoryProgressIndicator shows real-time progress toward victory conditions.

signal near_victory(condition: String, progress: float)
signal victory_condition_met(condition: String)

## Victory conditions
const DISTRICT_VICTORY_THRESHOLD := 0.75  ## 75% districts required
const NEAR_VICTORY_THRESHOLD := 0.9       ## 90% shows "near victory" warning

## Panel sizing
const PANEL_WIDTH := 200
const PANEL_HEIGHT := 100

## Current state
var _district_control := 0.0      ## 0.0 to 1.0
var _rival_factories := 0
var _total_districts := 256

## UI components
var _container: PanelContainer = null
var _district_bar: ProgressBar = null
var _district_label: Label = null
var _factories_label: Label = null
var _status_label: Label = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "VictoryProgressIndicator"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d", 0.85)
	style.border_color = _faction_color.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_container.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_container.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "Victory Progress"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color("#aaaaaa"))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# District control section
	var district_container := VBoxContainer.new()
	district_container.add_theme_constant_override("separation", 4)

	var district_row := HBoxContainer.new()
	district_row.add_theme_constant_override("separation", 4)

	var district_icon := Label.new()
	district_icon.text = "[D]"
	district_icon.add_theme_font_size_override("font_size", 10)
	district_icon.add_theme_color_override("font_color", _faction_color)
	district_row.add_child(district_icon)

	_district_label = Label.new()
	_district_label.text = "Districts: 0%"
	_district_label.add_theme_font_size_override("font_size", 11)
	_district_label.add_theme_color_override("font_color", Color.WHITE)
	_district_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	district_row.add_child(_district_label)

	district_container.add_child(district_row)

	# District progress bar
	_district_bar = ProgressBar.new()
	_district_bar.min_value = 0.0
	_district_bar.max_value = 100.0
	_district_bar.value = 0.0
	_district_bar.show_percentage = false
	_district_bar.custom_minimum_size.y = 8

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_district_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = _faction_color
	bar_fill.set_corner_radius_all(2)
	_district_bar.add_theme_stylebox_override("fill", bar_fill)

	# Victory threshold marker
	var threshold_marker := ColorRect.new()
	threshold_marker.color = Color.GOLD
	threshold_marker.custom_minimum_size = Vector2(2, 8)
	threshold_marker.position.x = DISTRICT_VICTORY_THRESHOLD * (_district_bar.custom_minimum_size.x - 2)

	district_container.add_child(_district_bar)
	vbox.add_child(district_container)

	# Rival factories
	var factories_row := HBoxContainer.new()
	factories_row.add_theme_constant_override("separation", 4)

	var factories_icon := Label.new()
	factories_icon.text = "[F]"
	factories_icon.add_theme_font_size_override("font_size", 10)
	factories_icon.add_theme_color_override("font_color", Color.ORANGE)
	factories_row.add_child(factories_icon)

	_factories_label = Label.new()
	_factories_label.text = "Rival Factories: 0 remaining"
	_factories_label.add_theme_font_size_override("font_size", 11)
	_factories_label.add_theme_color_override("font_color", Color.WHITE)
	_factories_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	factories_row.add_child(_factories_label)

	vbox.add_child(factories_row)

	# Status label
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", Color.GOLD)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.visible = false
	vbox.add_child(_status_label)

	parent.add_child(_container)
	return _container


## Update district control.
func update_district_control(controlled: int, total: int) -> void:
	_total_districts = maxi(total, 1)
	_district_control = float(controlled) / float(_total_districts)

	_update_display()

	# Check near victory
	if _district_control >= NEAR_VICTORY_THRESHOLD and _district_control < 1.0:
		near_victory.emit("district", _district_control)

	# Check victory
	if _district_control >= DISTRICT_VICTORY_THRESHOLD:
		victory_condition_met.emit("district")


## Update rival factories.
func update_rival_factories(remaining: int) -> void:
	_rival_factories = remaining
	_update_display()

	# Check victory (all factories destroyed)
	if _rival_factories == 0:
		victory_condition_met.emit("factories")


## Update full state.
func update_progress(controlled_districts: int, total_districts: int, rival_factories: int) -> void:
	_total_districts = maxi(total_districts, 1)
	_district_control = float(controlled_districts) / float(_total_districts)
	_rival_factories = rival_factories

	_update_display()


## Update display.
func _update_display() -> void:
	var percent := _district_control * 100.0

	if _district_label != null:
		_district_label.text = "Districts: %.0f%%" % percent

	if _district_bar != null:
		_district_bar.value = percent

		var bar_fill := _district_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			if _district_control >= DISTRICT_VICTORY_THRESHOLD:
				bar_fill.bg_color = Color.GOLD
			elif _district_control >= NEAR_VICTORY_THRESHOLD * DISTRICT_VICTORY_THRESHOLD:
				bar_fill.bg_color = Color.YELLOW
			else:
				bar_fill.bg_color = _faction_color

	if _factories_label != null:
		_factories_label.text = "Rival Factories: %d remaining" % _rival_factories

		if _rival_factories == 0:
			_factories_label.add_theme_color_override("font_color", Color.GREEN)
		elif _rival_factories == 1:
			_factories_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			_factories_label.add_theme_color_override("font_color", Color.WHITE)

	# Update status
	if _status_label != null:
		if _district_control >= DISTRICT_VICTORY_THRESHOLD and _rival_factories == 0:
			_status_label.text = "VICTORY CONDITIONS MET"
			_status_label.add_theme_color_override("font_color", Color.GOLD)
			_status_label.visible = true
		elif _district_control >= NEAR_VICTORY_THRESHOLD * DISTRICT_VICTORY_THRESHOLD:
			_status_label.text = "Near District Domination!"
			_status_label.add_theme_color_override("font_color", Color.YELLOW)
			_status_label.visible = true
		elif _rival_factories == 1:
			_status_label.text = "One Factory Remaining!"
			_status_label.add_theme_color_override("font_color", Color.ORANGE)
			_status_label.visible = true
		else:
			_status_label.visible = false


## Get current progress.
func get_progress() -> Dictionary:
	return {
		"district_control": _district_control,
		"rival_factories": _rival_factories,
		"district_victory_progress": _district_control / DISTRICT_VICTORY_THRESHOLD,
		"factory_victory_progress": 1.0 if _rival_factories == 0 else 0.0
	}


## Is near victory.
func is_near_victory() -> bool:
	return _district_control >= NEAR_VICTORY_THRESHOLD * DISTRICT_VICTORY_THRESHOLD or _rival_factories <= 1


## Has met victory conditions.
func has_met_victory_conditions() -> bool:
	return _district_control >= DISTRICT_VICTORY_THRESHOLD and _rival_factories == 0


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _container != null:
		var style := _container.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = _faction_color.darkened(0.3)

	_update_display()


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
