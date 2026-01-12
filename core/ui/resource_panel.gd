class_name ResourcePanel
extends RefCounted
## ResourcePanel displays REE count, power percentage, and faction-specific resources.

signal resource_clicked(resource_type: String)
signal resource_warning(resource_type: String, is_low: bool)

## Resource thresholds for warnings
const LOW_REE_THRESHOLD := 100.0
const LOW_POWER_THRESHOLD := 0.2  ## 20%
const CRITICAL_POWER_THRESHOLD := 0.1  ## 10%

## Panel styling
const PANEL_WIDTH := 200
const PANEL_HEIGHT := 100

## Current values
var _ree_count := 0.0
var _power_current := 0.0
var _power_max := 100.0
var _faction_resources: Dictionary = {}  ## resource_name -> value

## UI components
var _container: PanelContainer = null
var _ree_label: Label = null
var _power_bar: ProgressBar = null
var _power_label: Label = null
var _resource_vbox: VBoxContainer = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "ResourcePanel"
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
	_resource_vbox = VBoxContainer.new()
	_resource_vbox.add_theme_constant_override("separation", 8)
	_container.add_child(_resource_vbox)

	# REE display
	var ree_hbox := HBoxContainer.new()
	ree_hbox.add_theme_constant_override("separation", 8)

	var ree_icon := Label.new()
	ree_icon.text = "[REE]"
	ree_icon.add_theme_color_override("font_color", _faction_color)
	ree_icon.add_theme_font_size_override("font_size", 12)
	ree_hbox.add_child(ree_icon)

	_ree_label = Label.new()
	_ree_label.text = "0"
	_ree_label.add_theme_font_size_override("font_size", 16)
	_ree_label.add_theme_color_override("font_color", Color.WHITE)
	_ree_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ree_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ree_hbox.add_child(_ree_label)

	_resource_vbox.add_child(ree_hbox)

	# Power display
	var power_hbox := HBoxContainer.new()
	power_hbox.add_theme_constant_override("separation", 8)

	var power_icon := Label.new()
	power_icon.text = "[PWR]"
	power_icon.add_theme_color_override("font_color", Color.YELLOW)
	power_icon.add_theme_font_size_override("font_size", 12)
	power_hbox.add_child(power_icon)

	var power_container := VBoxContainer.new()
	power_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_power_bar = ProgressBar.new()
	_power_bar.min_value = 0.0
	_power_bar.max_value = 100.0
	_power_bar.value = 100.0
	_power_bar.show_percentage = false
	_power_bar.custom_minimum_size.y = 12

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_power_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.YELLOW
	bar_fill.set_corner_radius_all(2)
	_power_bar.add_theme_stylebox_override("fill", bar_fill)

	power_container.add_child(_power_bar)

	_power_label = Label.new()
	_power_label.text = "100%"
	_power_label.add_theme_font_size_override("font_size", 10)
	_power_label.add_theme_color_override("font_color", Color("#888888"))
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	power_container.add_child(_power_label)

	power_hbox.add_child(power_container)
	_resource_vbox.add_child(power_hbox)

	parent.add_child(_container)
	return _container


## Update resource values.
func update_resources(ree: float, power: float, power_max: float) -> void:
	var old_ree := _ree_count
	var old_power_ratio := _power_current / maxf(_power_max, 1.0)

	_ree_count = ree
	_power_current = power
	_power_max = maxf(power_max, 1.0)

	_update_display()

	# Check for warnings
	var new_power_ratio := _power_current / _power_max

	if _ree_count < LOW_REE_THRESHOLD and old_ree >= LOW_REE_THRESHOLD:
		resource_warning.emit("ree", true)
	elif _ree_count >= LOW_REE_THRESHOLD and old_ree < LOW_REE_THRESHOLD:
		resource_warning.emit("ree", false)

	if new_power_ratio < LOW_POWER_THRESHOLD and old_power_ratio >= LOW_POWER_THRESHOLD:
		resource_warning.emit("power", true)
	elif new_power_ratio >= LOW_POWER_THRESHOLD and old_power_ratio < LOW_POWER_THRESHOLD:
		resource_warning.emit("power", false)


## Update display elements.
func _update_display() -> void:
	if _ree_label != null:
		_ree_label.text = _format_number(_ree_count)

		# Color based on threshold
		if _ree_count < LOW_REE_THRESHOLD:
			_ree_label.add_theme_color_override("font_color", Color.RED)
		else:
			_ree_label.add_theme_color_override("font_color", Color.WHITE)

	if _power_bar != null:
		var power_percent := (_power_current / _power_max) * 100.0
		_power_bar.value = power_percent

		# Update bar color based on level
		var bar_fill := _power_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			if power_percent < CRITICAL_POWER_THRESHOLD * 100:
				bar_fill.bg_color = Color.RED
			elif power_percent < LOW_POWER_THRESHOLD * 100:
				bar_fill.bg_color = Color.ORANGE
			else:
				bar_fill.bg_color = Color.YELLOW

	if _power_label != null:
		var power_percent := (_power_current / _power_max) * 100.0
		_power_label.text = "%.0f%% (%.0f/%.0f)" % [power_percent, _power_current, _power_max]


## Format large numbers with K/M suffix.
func _format_number(value: float) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fK" % (value / 1000.0)
	else:
		return "%.0f" % value


## Add faction-specific resource display.
func add_faction_resource(resource_name: String, value: float, icon_text: String = "") -> void:
	_faction_resources[resource_name] = value

	# Create new row if needed
	var row_name := "faction_" + resource_name

	# Check if row exists
	for child in _resource_vbox.get_children():
		if child.name == row_name:
			_update_faction_resource_row(child, value)
			return

	# Create new row
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 8)

	var icon := Label.new()
	icon.text = icon_text if not icon_text.is_empty() else ("[%s]" % resource_name.substr(0, 3).to_upper())
	icon.add_theme_color_override("font_color", _faction_color)
	icon.add_theme_font_size_override("font_size", 12)
	row.add_child(icon)

	var value_label := Label.new()
	value_label.name = "ValueLabel"
	value_label.text = _format_number(value)
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color.WHITE)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	_resource_vbox.add_child(row)


## Update faction resource row.
func _update_faction_resource_row(row: Control, value: float) -> void:
	var value_label := row.get_node_or_null("ValueLabel") as Label
	if value_label != null:
		value_label.text = _format_number(value)


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
func get_resources() -> Dictionary:
	return {
		"ree": _ree_count,
		"power": _power_current,
		"power_max": _power_max,
		"power_percent": (_power_current / _power_max) * 100.0,
		"faction_resources": _faction_resources.duplicate()
	}


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_ree_label = null
	_power_bar = null
	_power_label = null
	_resource_vbox = null
