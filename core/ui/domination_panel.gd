class_name DominationPanel
extends RefCounted
## DominationPanel displays faction control percentages and domination progress.

signal faction_clicked(faction_id: String)

## Panel sizing
const PANEL_WIDTH := 220
const PANEL_HEIGHT := 180
const BAR_HEIGHT := 16
const BAR_SPACING := 4

## Total districts
const TOTAL_DISTRICTS := 256

## Faction data
var _faction_counts: Dictionary = {}  ## faction_id -> district_count

## UI components
var _container: PanelContainer = null
var _faction_bars: Dictionary = {}    ## faction_id -> {bar, label, percent_label}
var _bars_container: VBoxContainer = null

## Player faction
var _player_faction := "neutral"


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, player_faction: String = "neutral") -> Control:
	_player_faction = player_faction

	# Main container
	_container = PanelContainer.new()
	_container.name = "DominationPanel"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d", 0.85)
	style.border_color = Color("#404040")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	_container.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_container.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "Map Control"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color.WHITE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Separator
	vbox.add_child(HSeparator.new())

	# Bars container
	_bars_container = VBoxContainer.new()
	_bars_container.add_theme_constant_override("separation", BAR_SPACING)
	vbox.add_child(_bars_container)

	# Create bars for known factions
	for faction_id in UITheme.FACTION_COLORS:
		if faction_id != "neutral":
			_create_faction_bar(faction_id)

	# Neutral bar
	_create_faction_bar("neutral")

	parent.add_child(_container)
	return _container


## Create a faction progress bar.
func _create_faction_bar(faction_id: String) -> void:
	var faction_color := UITheme.FACTION_COLORS.get(faction_id, Color.GRAY)

	var row := HBoxContainer.new()
	row.name = "FactionRow_%s" % faction_id
	row.add_theme_constant_override("separation", 8)

	# Faction name/indicator
	var name_label := Label.new()
	name_label.text = _get_faction_abbreviation(faction_id)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", faction_color)
	name_label.custom_minimum_size.x = 30
	name_label.tooltip_text = _get_faction_full_name(faction_id)
	row.add_child(name_label)

	# Progress bar
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = faction_color
	bar_fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", bar_fill)

	row.add_child(bar)

	# Percentage label
	var percent_label := Label.new()
	percent_label.text = "0%"
	percent_label.add_theme_font_size_override("font_size", 10)
	percent_label.add_theme_color_override("font_color", Color("#888888"))
	percent_label.custom_minimum_size.x = 35
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(percent_label)

	# District count label
	var count_label := Label.new()
	count_label.text = "(0)"
	count_label.add_theme_font_size_override("font_size", 10)
	count_label.add_theme_color_override("font_color", Color("#666666"))
	count_label.custom_minimum_size.x = 35
	row.add_child(count_label)

	_bars_container.add_child(row)

	_faction_bars[faction_id] = {
		"bar": bar,
		"name_label": name_label,
		"percent_label": percent_label,
		"count_label": count_label,
		"row": row
	}

	# Make clickable
	row.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			faction_clicked.emit(faction_id)
	)


## Update faction district counts.
func update_faction_counts(counts: Dictionary) -> void:
	_faction_counts = counts.duplicate()
	_update_display()


## Update single faction count.
func update_faction(faction_id: String, district_count: int) -> void:
	_faction_counts[faction_id] = district_count
	_update_display()


## Update display.
func _update_display() -> void:
	var total := 0
	for count in _faction_counts.values():
		total += count

	# Calculate neutral count
	var captured := 0
	for faction_id in _faction_counts:
		if faction_id != "neutral":
			captured += _faction_counts[faction_id]

	_faction_counts["neutral"] = TOTAL_DISTRICTS - captured

	for faction_id in _faction_bars:
		var data: Dictionary = _faction_bars[faction_id]
		var count: int = _faction_counts.get(faction_id, 0)
		var percent := (float(count) / float(TOTAL_DISTRICTS)) * 100.0

		var bar: ProgressBar = data["bar"]
		var percent_label: Label = data["percent_label"]
		var count_label: Label = data["count_label"]
		var row: Control = data["row"]

		bar.value = percent
		percent_label.text = "%.1f%%" % percent
		count_label.text = "(%d)" % count

		# Hide factions with 0 districts (except player and neutral)
		var should_show := count > 0 or faction_id == _player_faction or faction_id == "neutral"
		row.visible = should_show


## Get faction abbreviation.
func _get_faction_abbreviation(faction_id: String) -> String:
	match faction_id:
		"aether_swarm": return "AS"
		"optiforge": return "OF"
		"dynapods": return "DP"
		"logibots": return "LB"
		"human_remnant": return "HR"
		"neutral": return "N"
		_: return faction_id.substr(0, 2).to_upper()


## Get faction full name.
func _get_faction_full_name(faction_id: String) -> String:
	match faction_id:
		"aether_swarm": return "Aether Swarm"
		"optiforge": return "OptiForge Legion"
		"dynapods": return "Dynapods Vanguard"
		"logibots": return "LogiBots Colossus"
		"human_remnant": return "Human Remnant"
		"neutral": return "Neutral"
		_: return faction_id.capitalize()


## Set player faction (for highlighting).
func set_player_faction(faction_id: String) -> void:
	_player_faction = faction_id

	# Highlight player faction bar
	for fid in _faction_bars:
		var data: Dictionary = _faction_bars[fid]
		var name_label: Label = data["name_label"]

		if fid == faction_id:
			name_label.add_theme_font_size_override("font_size", 12)
		else:
			name_label.add_theme_font_size_override("font_size", 11)


## Get domination progress for faction.
func get_domination_progress(faction_id: String) -> float:
	var count: int = _faction_counts.get(faction_id, 0)
	return (float(count) / float(TOTAL_DISTRICTS)) * 100.0


## Check if faction has won (controls all districts).
func check_domination_victory() -> String:
	for faction_id in _faction_counts:
		if faction_id != "neutral" and _faction_counts[faction_id] >= TOTAL_DISTRICTS:
			return faction_id
	return ""


## Get container.
func get_container() -> Control:
	return _container


## Get statistics.
func get_statistics() -> Dictionary:
	var stats: Dictionary = {}
	for faction_id in _faction_counts:
		stats[faction_id] = {
			"districts": _faction_counts[faction_id],
			"percent": get_domination_progress(faction_id)
		}
	return stats


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_faction_bars.clear()
