class_name PowerStatusPanel
extends RefCounted
## PowerStatusPanel displays faction power analytics.

signal power_critical()
signal power_restored()

## Power thresholds
const POWER_LOW_THRESHOLD := 0.2   ## 20% surplus triggers warning
const POWER_CRITICAL_THRESHOLD := 0.0  ## No surplus = critical

## Panel sizing
const PANEL_WIDTH := 240
const PANEL_HEIGHT := 200

## Current state
var _total_generation := 0.0
var _total_demand := 0.0
var _surplus := 0.0
var _blackout_count := 0
var _total_plants := 0
var _operational_plants := 0
var _was_critical := false

## UI components
var _container: PanelContainer = null
var _generation_label: Label = null
var _demand_label: Label = null
var _surplus_label: Label = null
var _surplus_bar: ProgressBar = null
var _blackout_label: Label = null
var _plants_label: Label = null
var _status_indicator: ColorRect = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "PowerStatusPanel"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d", 0.9)
	style.border_color = _faction_color.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	_container.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_container.add_child(vbox)

	# Header with status indicator
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Power Grid"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_status_indicator = ColorRect.new()
	_status_indicator.custom_minimum_size = Vector2(16, 16)
	_status_indicator.color = Color.GREEN
	header.add_child(_status_indicator)

	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	# Generation
	var gen_row := _create_stat_row("Generation:", "0 MW")
	_generation_label = gen_row.get_node("Value") as Label
	vbox.add_child(gen_row)

	# Demand
	var demand_row := _create_stat_row("Demand:", "0 MW")
	_demand_label = demand_row.get_node("Value") as Label
	vbox.add_child(demand_row)

	# Surplus with bar
	var surplus_container := VBoxContainer.new()
	surplus_container.add_theme_constant_override("separation", 4)

	var surplus_row := _create_stat_row("Surplus:", "+0 MW")
	_surplus_label = surplus_row.get_node("Value") as Label
	surplus_container.add_child(surplus_row)

	_surplus_bar = ProgressBar.new()
	_surplus_bar.min_value = -100.0
	_surplus_bar.max_value = 100.0
	_surplus_bar.value = 0.0
	_surplus_bar.show_percentage = false
	_surplus_bar.custom_minimum_size.y = 8

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_surplus_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.GREEN
	bar_fill.set_corner_radius_all(2)
	_surplus_bar.add_theme_stylebox_override("fill", bar_fill)

	surplus_container.add_child(_surplus_bar)
	vbox.add_child(surplus_container)

	vbox.add_child(HSeparator.new())

	# Blackout districts
	var blackout_row := _create_stat_row("Blackouts:", "0 districts")
	_blackout_label = blackout_row.get_node("Value") as Label
	vbox.add_child(blackout_row)

	# Plants
	var plants_row := _create_stat_row("Plants:", "0/0 operational")
	_plants_label = plants_row.get_node("Value") as Label
	vbox.add_child(plants_row)

	parent.add_child(_container)
	return _container


## Create a stat row.
func _create_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("#888888"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value := Label.new()
	value.name = "Value"
	value.text = value_text
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", Color.WHITE)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	return row


## Update power statistics.
func update_power(generation: float, demand: float, blackout_count: int, operational_plants: int, total_plants: int) -> void:
	_total_generation = generation
	_total_demand = demand
	_surplus = generation - demand
	_blackout_count = blackout_count
	_operational_plants = operational_plants
	_total_plants = total_plants

	_update_display()


## Update display.
func _update_display() -> void:
	if _generation_label != null:
		_generation_label.text = "%.0f MW" % _total_generation

	if _demand_label != null:
		_demand_label.text = "%.0f MW" % _total_demand

	if _surplus_label != null:
		var prefix := "+" if _surplus >= 0 else ""
		_surplus_label.text = "%s%.0f MW" % [prefix, _surplus]
		if _surplus < 0:
			_surplus_label.add_theme_color_override("font_color", Color.RED)
		elif _surplus < _total_demand * POWER_LOW_THRESHOLD:
			_surplus_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			_surplus_label.add_theme_color_override("font_color", Color.GREEN)

	if _surplus_bar != null:
		# Scale surplus relative to demand
		var bar_value := 0.0
		if _total_demand > 0:
			bar_value = (_surplus / _total_demand) * 100.0
		_surplus_bar.value = clampf(bar_value, -100.0, 100.0)

		var bar_fill := _surplus_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			if _surplus < 0:
				bar_fill.bg_color = Color.RED
			elif _surplus < _total_demand * POWER_LOW_THRESHOLD:
				bar_fill.bg_color = Color.YELLOW
			else:
				bar_fill.bg_color = Color.GREEN

	if _blackout_label != null:
		_blackout_label.text = "%d districts" % _blackout_count
		if _blackout_count > 0:
			_blackout_label.add_theme_color_override("font_color", Color.RED)
		else:
			_blackout_label.add_theme_color_override("font_color", Color.GREEN)

	if _plants_label != null:
		_plants_label.text = "%d/%d operational" % [_operational_plants, _total_plants]
		if _operational_plants < _total_plants:
			_plants_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			_plants_label.add_theme_color_override("font_color", Color.WHITE)

	# Update status indicator
	if _status_indicator != null:
		if _surplus < 0:
			_status_indicator.color = Color.RED
		elif _surplus < _total_demand * POWER_LOW_THRESHOLD:
			_status_indicator.color = Color.YELLOW
		else:
			_status_indicator.color = Color.GREEN

	# Check for critical state change
	var is_critical := _surplus < 0
	if is_critical and not _was_critical:
		power_critical.emit()
	elif not is_critical and _was_critical:
		power_restored.emit()
	_was_critical = is_critical


## Get power status summary.
func get_summary() -> Dictionary:
	return {
		"generation": _total_generation,
		"demand": _total_demand,
		"surplus": _surplus,
		"blackout_count": _blackout_count,
		"operational_plants": _operational_plants,
		"total_plants": _total_plants,
		"is_critical": _surplus < 0
	}


## Is power critical.
func is_critical() -> bool:
	return _surplus < 0


## Is power low.
func is_low() -> bool:
	return _surplus < _total_demand * POWER_LOW_THRESHOLD


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


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
