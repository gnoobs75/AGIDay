class_name DistrictInfoPanel
extends RefCounted
## DistrictInfoPanel displays detailed information about a selected/hovered district.

signal capture_button_pressed(district_id: int)

## Panel sizing
const PANEL_WIDTH := 280
const PANEL_HEIGHT := 240

## Current district
var _current_district_id: int = -1
var _district_data: Dictionary = {}

## UI components
var _container: PanelContainer = null
var _header_label: Label = null
var _owner_label: Label = null
var _type_label: Label = null
var _coords_label: Label = null
var _income_container: VBoxContainer = null
var _units_label: Label = null
var _buildings_label: Label = null
var _capture_container: VBoxContainer = null
var _capture_bar: ProgressBar = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "DistrictInfoPanel"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_container.visible = false  ## Hidden by default

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

	# Header with district ID
	_header_label = Label.new()
	_header_label.text = "District #0"
	_header_label.add_theme_font_size_override("font_size", 16)
	_header_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_header_label)

	# Separator
	vbox.add_child(HSeparator.new())

	# Info grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)

	# Owner
	grid.add_child(_create_info_label("Owner:"))
	_owner_label = _create_value_label("Neutral")
	grid.add_child(_owner_label)

	# Type
	grid.add_child(_create_info_label("Type:"))
	_type_label = _create_value_label("Unknown")
	grid.add_child(_type_label)

	# Coordinates
	grid.add_child(_create_info_label("Location:"))
	_coords_label = _create_value_label("(0, 0)")
	grid.add_child(_coords_label)

	# Units present
	grid.add_child(_create_info_label("Units:"))
	_units_label = _create_value_label("0")
	grid.add_child(_units_label)

	# Buildings
	grid.add_child(_create_info_label("Buildings:"))
	_buildings_label = _create_value_label("0")
	grid.add_child(_buildings_label)

	vbox.add_child(grid)

	# Income section
	var income_header := Label.new()
	income_header.text = "Income (per 5s):"
	income_header.add_theme_font_size_override("font_size", 12)
	income_header.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(income_header)

	_income_container = VBoxContainer.new()
	_income_container.add_theme_constant_override("separation", 2)
	vbox.add_child(_income_container)

	# Capture progress section (hidden when not contested)
	_capture_container = VBoxContainer.new()
	_capture_container.visible = false
	_capture_container.add_theme_constant_override("separation", 4)

	var capture_header := Label.new()
	capture_header.text = "Capture Progress:"
	capture_header.add_theme_font_size_override("font_size", 12)
	capture_header.add_theme_color_override("font_color", Color.ORANGE)
	_capture_container.add_child(capture_header)

	_capture_bar = ProgressBar.new()
	_capture_bar.min_value = 0.0
	_capture_bar.max_value = 100.0
	_capture_bar.value = 0.0
	_capture_bar.show_percentage = true
	_capture_bar.custom_minimum_size.y = 16

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(4)
	_capture_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.ORANGE
	bar_fill.set_corner_radius_all(4)
	_capture_bar.add_theme_stylebox_override("fill", bar_fill)

	_capture_container.add_child(_capture_bar)
	vbox.add_child(_capture_container)

	parent.add_child(_container)
	return _container


## Create info label.
func _create_info_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("#888888"))
	return label


## Create value label.
func _create_value_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	return label


## Show panel for district.
func show_district(district_id: int, data: Dictionary) -> void:
	_current_district_id = district_id
	_district_data = data.duplicate()
	_update_display()
	_container.visible = true


## Hide panel.
func hide_panel() -> void:
	_container.visible = false
	_current_district_id = -1


## Update display.
func _update_display() -> void:
	if _header_label != null:
		_header_label.text = "District #%d" % _current_district_id

	# Calculate grid coordinates
	var grid_x := _current_district_id % 16
	var grid_y := _current_district_id / 16

	if _coords_label != null:
		_coords_label.text = "(%d, %d)" % [grid_x, grid_y]

	# Owner
	var owner: String = _district_data.get("owner", "")
	if _owner_label != null:
		if owner.is_empty():
			_owner_label.text = "Neutral"
			_owner_label.add_theme_color_override("font_color", Color.GRAY)
		else:
			_owner_label.text = _format_faction_name(owner)
			var faction_color: Color = UITheme.FACTION_COLORS.get(owner, Color.WHITE)
			_owner_label.add_theme_color_override("font_color", faction_color)

	# Type
	if _type_label != null:
		var type: String = _district_data.get("type", "unknown")
		_type_label.text = _format_type_name(type)

	# Units
	if _units_label != null:
		var units: int = _district_data.get("units", 0)
		_units_label.text = str(units)

	# Buildings
	if _buildings_label != null:
		var buildings: int = _district_data.get("buildings", 0)
		_buildings_label.text = str(buildings)

	# Income
	_update_income_display()

	# Capture progress
	var contested: bool = _district_data.get("contested", false)
	if _capture_container != null:
		_capture_container.visible = contested

	if contested and _capture_bar != null:
		var progress: float = _district_data.get("capture_progress", 0.0)
		_capture_bar.value = progress


## Update income display.
func _update_income_display() -> void:
	if _income_container == null:
		return

	# Clear existing
	for child in _income_container.get_children():
		child.queue_free()

	var income: Dictionary = _district_data.get("income", {"power": 0, "ree": 0, "research": 0})

	for resource in ["power", "ree", "research"]:
		var value: float = income.get(resource, 0.0)
		if value > 0:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)

			var icon := Label.new()
			match resource:
				"power": icon.text = "[PWR]"
				"ree": icon.text = "[REE]"
				"research": icon.text = "[RES]"
			icon.add_theme_font_size_override("font_size", 10)
			icon.add_theme_color_override("font_color", Color("#666666"))
			row.add_child(icon)

			var val_label := Label.new()
			val_label.text = "+%.0f" % value
			val_label.add_theme_font_size_override("font_size", 11)
			val_label.add_theme_color_override("font_color", Color.GREEN)
			row.add_child(val_label)

			_income_container.add_child(row)


## Format faction name.
func _format_faction_name(faction_id: String) -> String:
	match faction_id:
		"aether_swarm": return "Aether Swarm"
		"optiforge": return "OptiForge"
		"dynapods": return "Dynapods"
		"logibots": return "LogiBots"
		"human_remnant": return "Human Remnant"
		_: return faction_id.capitalize()


## Format type name.
func _format_type_name(type: String) -> String:
	match type:
		"power_hub": return "Power Hub"
		"ree_node": return "REE Node"
		"research_facility": return "Research"
		"mixed": return "Mixed"
		"empty": return "Empty"
		_: return type.capitalize()


## Position panel near point.
func position_near(screen_pos: Vector2, viewport_size: Vector2) -> void:
	if _container == null:
		return

	var pos := screen_pos + Vector2(20, 0)

	# Adjust if off-screen
	if pos.x + PANEL_WIDTH > viewport_size.x:
		pos.x = screen_pos.x - PANEL_WIDTH - 20

	if pos.y + PANEL_HEIGHT > viewport_size.y:
		pos.y = viewport_size.y - PANEL_HEIGHT - 10

	_container.position = pos


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


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
