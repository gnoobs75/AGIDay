class_name REEAnalyticsPanel
extends RefCounted
## REEAnalyticsPanel displays detailed REE resource analytics and generation breakdown.

signal storage_full_warning()
signal efficiency_changed(new_efficiency: float)

## Panel sizing
const PANEL_WIDTH := 260
const PANEL_HEIGHT := 280

## Storage thresholds
const STORAGE_WARNING_THRESHOLD := 0.9  ## 90%
const STORAGE_FULL_THRESHOLD := 0.99

## Generation sources
const SOURCE_TYPES := ["destruction", "salvage", "district_income", "unit_collection"]

## Current state
var _current_ree := 0.0
var _max_storage := 1000.0
var _generation_rate := 0.0  ## Per second
var _consumption_rate := 0.0
var _total_generated := 0.0
var _total_consumed := 0.0
var _source_breakdown: Dictionary = {}  ## source_type -> amount

## UI components
var _container: PanelContainer = null
var _ree_label: Label = null
var _rate_label: Label = null
var _storage_bar: ProgressBar = null
var _storage_label: Label = null
var _storage_warning: Label = null
var _analytics_container: VBoxContainer = null
var _efficiency_label: Label = null
var _source_bars: Dictionary = {}  ## source_type -> ProgressBar

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	for source in SOURCE_TYPES:
		_source_breakdown[source] = 0.0


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "REEAnalyticsPanel"
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
	vbox.add_theme_constant_override("separation", 10)
	_container.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "REE Resources"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color.CYAN)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	# Current REE and rate
	var current_row := HBoxContainer.new()
	current_row.add_theme_constant_override("separation", 16)

	var ree_container := VBoxContainer.new()
	var ree_header := Label.new()
	ree_header.text = "Current"
	ree_header.add_theme_font_size_override("font_size", 10)
	ree_header.add_theme_color_override("font_color", Color("#888888"))
	ree_container.add_child(ree_header)

	_ree_label = Label.new()
	_ree_label.text = "0"
	_ree_label.add_theme_font_size_override("font_size", 20)
	_ree_label.add_theme_color_override("font_color", Color.WHITE)
	ree_container.add_child(_ree_label)
	current_row.add_child(ree_container)

	var rate_container := VBoxContainer.new()
	var rate_header := Label.new()
	rate_header.text = "Rate/sec"
	rate_header.add_theme_font_size_override("font_size", 10)
	rate_header.add_theme_color_override("font_color", Color("#888888"))
	rate_container.add_child(rate_header)

	_rate_label = Label.new()
	_rate_label.text = "+0.0"
	_rate_label.add_theme_font_size_override("font_size", 16)
	_rate_label.add_theme_color_override("font_color", Color.GREEN)
	rate_container.add_child(_rate_label)
	current_row.add_child(rate_container)

	vbox.add_child(current_row)

	# Storage bar
	var storage_container := VBoxContainer.new()
	storage_container.add_theme_constant_override("separation", 2)

	var storage_header := HBoxContainer.new()
	var storage_title := Label.new()
	storage_title.text = "Storage:"
	storage_title.add_theme_font_size_override("font_size", 11)
	storage_title.add_theme_color_override("font_color", Color("#888888"))
	storage_header.add_child(storage_title)

	_storage_label = Label.new()
	_storage_label.text = "0/1000 (0%)"
	_storage_label.add_theme_font_size_override("font_size", 11)
	_storage_label.add_theme_color_override("font_color", Color.WHITE)
	_storage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	storage_header.add_child(_storage_label)

	storage_container.add_child(storage_header)

	_storage_bar = ProgressBar.new()
	_storage_bar.min_value = 0.0
	_storage_bar.max_value = 100.0
	_storage_bar.value = 0.0
	_storage_bar.show_percentage = false
	_storage_bar.custom_minimum_size.y = 12

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_storage_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.CYAN
	bar_fill.set_corner_radius_all(2)
	_storage_bar.add_theme_stylebox_override("fill", bar_fill)

	storage_container.add_child(_storage_bar)

	_storage_warning = Label.new()
	_storage_warning.text = "STORAGE FULL!"
	_storage_warning.add_theme_font_size_override("font_size", 12)
	_storage_warning.add_theme_color_override("font_color", Color.RED)
	_storage_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storage_warning.visible = false
	storage_container.add_child(_storage_warning)

	vbox.add_child(storage_container)

	# Analytics section
	vbox.add_child(HSeparator.new())

	var analytics_header := Label.new()
	analytics_header.text = "Generation Sources"
	analytics_header.add_theme_font_size_override("font_size", 12)
	analytics_header.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(analytics_header)

	_analytics_container = VBoxContainer.new()
	_analytics_container.add_theme_constant_override("separation", 4)

	for source in SOURCE_TYPES:
		var row := _create_source_row(source)
		_analytics_container.add_child(row)

	vbox.add_child(_analytics_container)

	# Efficiency
	var efficiency_row := HBoxContainer.new()
	var eff_label := Label.new()
	eff_label.text = "Efficiency:"
	eff_label.add_theme_font_size_override("font_size", 11)
	eff_label.add_theme_color_override("font_color", Color("#888888"))
	efficiency_row.add_child(eff_label)

	_efficiency_label = Label.new()
	_efficiency_label.text = "100%"
	_efficiency_label.add_theme_font_size_override("font_size", 11)
	_efficiency_label.add_theme_color_override("font_color", Color.GREEN)
	_efficiency_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_efficiency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	efficiency_row.add_child(_efficiency_label)

	vbox.add_child(efficiency_row)

	parent.add_child(_container)
	return _container


## Create a source breakdown row.
func _create_source_row(source: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := Label.new()
	icon.text = _get_source_icon(source)
	icon.add_theme_font_size_override("font_size", 10)
	icon.add_theme_color_override("font_color", _get_source_color(source))
	icon.custom_minimum_size.x = 40
	row.add_child(icon)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(80, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#1f1f1f")
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = _get_source_color(source)
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)

	row.add_child(bar)
	_source_bars[source] = bar

	var value_label := Label.new()
	value_label.name = "ValueLabel"
	value_label.text = "0"
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	value_label.custom_minimum_size.x = 50
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	return row


## Get source icon.
func _get_source_icon(source: String) -> String:
	match source:
		"destruction": return "[DESTR]"
		"salvage": return "[SALV]"
		"district_income": return "[DIST]"
		"unit_collection": return "[UNIT]"
		_: return "[???]"


## Get source color.
func _get_source_color(source: String) -> Color:
	match source:
		"destruction": return Color.ORANGE
		"salvage": return Color.YELLOW
		"district_income": return Color.CYAN
		"unit_collection": return Color.GREEN
		_: return Color.GRAY


## Update all values.
func update_ree(current: float, max_storage: float, gen_rate: float, consume_rate: float) -> void:
	var was_full := _current_ree >= _max_storage * STORAGE_FULL_THRESHOLD

	_current_ree = current
	_max_storage = maxf(max_storage, 1.0)
	_generation_rate = gen_rate
	_consumption_rate = consume_rate

	_update_display()

	# Check storage full
	var is_full := _current_ree >= _max_storage * STORAGE_FULL_THRESHOLD
	if is_full and not was_full:
		storage_full_warning.emit()


## Update source breakdown.
func update_sources(sources: Dictionary) -> void:
	for source in SOURCE_TYPES:
		_source_breakdown[source] = sources.get(source, 0.0)

	_update_source_display()


## Update analytics totals.
func update_analytics(total_generated: float, total_consumed: float) -> void:
	_total_generated = total_generated
	_total_consumed = total_consumed
	_update_efficiency()


## Update display.
func _update_display() -> void:
	if _ree_label != null:
		_ree_label.text = str(int(_current_ree))

	if _rate_label != null:
		var net_rate := _generation_rate - _consumption_rate
		if net_rate >= 0:
			_rate_label.text = "+%.1f" % net_rate
			_rate_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			_rate_label.text = "%.1f" % net_rate
			_rate_label.add_theme_color_override("font_color", Color.RED)

	if _storage_bar != null:
		var percent := (_current_ree / _max_storage) * 100.0
		_storage_bar.value = percent

		var bar_fill := _storage_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			if percent >= STORAGE_FULL_THRESHOLD * 100:
				bar_fill.bg_color = Color.RED
			elif percent >= STORAGE_WARNING_THRESHOLD * 100:
				bar_fill.bg_color = Color.ORANGE
			else:
				bar_fill.bg_color = Color.CYAN

	if _storage_label != null:
		var percent := (_current_ree / _max_storage) * 100.0
		_storage_label.text = "%d/%d (%.0f%%)" % [int(_current_ree), int(_max_storage), percent]

	if _storage_warning != null:
		_storage_warning.visible = _current_ree >= _max_storage * STORAGE_FULL_THRESHOLD


## Update source breakdown display.
func _update_source_display() -> void:
	var total := 0.0
	for value in _source_breakdown.values():
		total += value

	for source in SOURCE_TYPES:
		if _source_bars.has(source):
			var bar: ProgressBar = _source_bars[source]
			var percent: float = (_source_breakdown[source] / maxf(total, 1.0)) * 100.0
			bar.value = percent

			# Update value label
			var row := bar.get_parent()
			var value_label := row.get_node_or_null("ValueLabel") as Label
			if value_label != null:
				value_label.text = str(int(_source_breakdown[source]))


## Update efficiency display.
func _update_efficiency() -> void:
	if _efficiency_label == null:
		return

	var efficiency := 100.0
	if _total_consumed > 0:
		efficiency = (_total_generated / _total_consumed) * 100.0

	_efficiency_label.text = "%.0f%%" % efficiency

	if efficiency >= 100:
		_efficiency_label.add_theme_color_override("font_color", Color.GREEN)
	elif efficiency >= 50:
		_efficiency_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		_efficiency_label.add_theme_color_override("font_color", Color.RED)

	efficiency_changed.emit(efficiency / 100.0)


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


## Get analytics.
func get_analytics() -> Dictionary:
	return {
		"current": _current_ree,
		"max_storage": _max_storage,
		"generation_rate": _generation_rate,
		"consumption_rate": _consumption_rate,
		"total_generated": _total_generated,
		"total_consumed": _total_consumed,
		"sources": _source_breakdown.duplicate(),
		"efficiency": _total_generated / maxf(_total_consumed, 1.0)
	}


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_source_bars.clear()
