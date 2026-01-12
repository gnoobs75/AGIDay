class_name DefeatScreen
extends RefCounted
## DefeatScreen displays defeat message with final stats and options.

signal spectate_pressed()
signal return_to_menu_pressed()
signal screen_dismissed()

## Defeat reasons
enum DefeatReason {
	FACTORY_DESTROYED,
	ALL_UNITS_ELIMINATED,
	BOTH
}

## Animation timing
const FADE_IN_TIME := 0.5

## Panel sizing
const PANEL_WIDTH := 600
const PANEL_HEIGHT := 480

## UI components
var _container: Control = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _faction_label: Label = null
var _reason_label: Label = null
var _stats_grid: GridContainer = null
var _duration_label: Label = null
var _wave_label: Label = null
var _spectate_button: Button = null
var _menu_button: Button = null

## Stats labels
var _stat_labels: Dictionary = {}

## Faction accent color
var _faction_color := Color("#808080")

## State
var _is_showing := false
var _can_spectate := false


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Full screen overlay
	_container = Control.new()
	_container.name = "DefeatScreen"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.visible = false
	_container.modulate.a = 0.0

	# Dark background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0, 0, 0.85)
	_container.add_child(bg)

	# Center panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.position = Vector2(-PANEL_WIDTH / 2, -PANEL_HEIGHT / 2)

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a", 0.98)
	style.border_color = Color.DARK_RED
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	_container.add_child(_panel)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "DEFEATED"
	_title_label.add_theme_font_size_override("font_size", 42)
	_title_label.add_theme_color_override("font_color", Color.DARK_RED)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# Faction name
	_faction_label = Label.new()
	_faction_label.text = "Faction Name"
	_faction_label.add_theme_font_size_override("font_size", 22)
	_faction_label.add_theme_color_override("font_color", _faction_color)
	_faction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_faction_label)

	# Defeat reason
	_reason_label = Label.new()
	_reason_label.text = "Factory Destroyed"
	_reason_label.add_theme_font_size_override("font_size", 14)
	_reason_label.add_theme_color_override("font_color", Color("#cc6666"))
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_reason_label)

	vbox.add_child(HSeparator.new())

	# Duration and wave info
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 32)
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER

	_duration_label = Label.new()
	_duration_label.text = "Duration: 00:00"
	_duration_label.add_theme_font_size_override("font_size", 14)
	_duration_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	info_row.add_child(_duration_label)

	_wave_label = Label.new()
	_wave_label.text = "Final Wave: 0"
	_wave_label.add_theme_font_size_override("font_size", 14)
	_wave_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	info_row.add_child(_wave_label)

	vbox.add_child(info_row)

	# Stats grid
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 32)
	_stats_grid.add_theme_constant_override("v_separation", 8)

	var stats := [
		["units_killed", "Units Killed"],
		["units_produced", "Units Produced"],
		["resources_earned", "Resources Earned"],
		["districts_captured", "Districts Captured"],
		["research_completed", "Research Completed"],
		["waves_survived", "Waves Survived"]
	]

	for stat in stats:
		var key: String = stat[0]
		var label_text: String = stat[1]

		var label := Label.new()
		label.text = label_text + ":"
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("#888888"))
		_stats_grid.add_child(label)

		var value := Label.new()
		value.text = "0"
		value.add_theme_font_size_override("font_size", 13)
		value.add_theme_color_override("font_color", Color.WHITE)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats_grid.add_child(value)
		_stat_labels[key] = value

	vbox.add_child(_stats_grid)

	vbox.add_child(HSeparator.new())

	# Buttons
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 16)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER

	_spectate_button = Button.new()
	_spectate_button.text = "Watch Remaining"
	_spectate_button.custom_minimum_size = Vector2(160, 48)
	_spectate_button.pressed.connect(_on_spectate_pressed)
	_spectate_button.visible = false
	button_row.add_child(_spectate_button)

	_menu_button = Button.new()
	_menu_button.text = "Return to Menu"
	_menu_button.custom_minimum_size = Vector2(160, 48)
	_menu_button.pressed.connect(_on_menu_pressed)
	button_row.add_child(_menu_button)

	vbox.add_child(button_row)

	parent.add_child(_container)
	return _container


## Show defeat screen with data.
func show_defeat(data: Dictionary) -> void:
	if _is_showing:
		return

	_is_showing = true

	# Set faction info
	var faction_name: String = data.get("faction_name", "Unknown Faction")
	var faction_id: String = data.get("faction_id", "neutral")
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _faction_label != null:
		_faction_label.text = faction_name
		_faction_label.add_theme_color_override("font_color", _faction_color)

	# Set defeat reason
	var reason: int = data.get("defeat_reason", DefeatReason.FACTORY_DESTROYED)
	if _reason_label != null:
		match reason:
			DefeatReason.FACTORY_DESTROYED:
				_reason_label.text = "Factory Destroyed"
			DefeatReason.ALL_UNITS_ELIMINATED:
				_reason_label.text = "All Units Eliminated"
			DefeatReason.BOTH:
				_reason_label.text = "Factory Destroyed & All Units Eliminated"

	# Set duration
	var duration: float = data.get("duration", 0.0)
	if _duration_label != null:
		var mins := int(duration) / 60
		var secs := int(duration) % 60
		_duration_label.text = "Duration: %02d:%02d" % [mins, secs]

	# Set wave
	if _wave_label != null:
		_wave_label.text = "Final Wave: %d" % data.get("wave_number", 0)

	# Set stats
	_set_stat("units_killed", data.get("units_killed", 0))
	_set_stat("units_produced", data.get("units_produced", 0))
	_set_stat("resources_earned", data.get("resources_earned", 0))
	_set_stat("districts_captured", data.get("districts_captured", 0))
	_set_stat("research_completed", data.get("research_completed", 0))
	_set_stat("waves_survived", data.get("waves_survived", 0))

	# Spectate button visibility
	_can_spectate = data.get("can_spectate", false)
	if _spectate_button != null:
		_spectate_button.visible = _can_spectate

	# Show with animation
	_container.visible = true
	_container.modulate.a = 0.0

	var tween := _container.create_tween()
	tween.tween_property(_container, "modulate:a", 1.0, FADE_IN_TIME)


## Set stat value.
func _set_stat(key: String, value: int) -> void:
	if _stat_labels.has(key):
		_stat_labels[key].text = str(value)


## Handle spectate button.
func _on_spectate_pressed() -> void:
	spectate_pressed.emit()
	hide_screen()


## Handle menu button.
func _on_menu_pressed() -> void:
	return_to_menu_pressed.emit()
	hide_screen()


## Hide screen.
func hide_screen() -> void:
	if not _is_showing:
		return

	var tween := _container.create_tween()
	tween.tween_property(_container, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		_container.visible = false
		_is_showing = false
		screen_dismissed.emit()
	)


## Is showing.
func is_showing() -> bool:
	return _is_showing


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _faction_label != null:
		_faction_label.add_theme_color_override("font_color", _faction_color)


## Get container.
func get_container() -> Control:
	return _container


## Cleanup.
func cleanup() -> void:
	_stat_labels.clear()
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
