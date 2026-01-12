class_name BlackoutWarning
extends RefCounted
## BlackoutWarning displays visual warnings for power blackouts and plant destruction.

signal warning_dismissed()
signal plant_destruction_acknowledged()

## Warning types
enum WarningType {
	DISTRICT_BLACKOUT,
	PLANT_DESTROYED,
	LOW_POWER,
	GRID_CRITICAL
}

## Warning colors
const WARNING_COLORS := {
	WarningType.DISTRICT_BLACKOUT: Color.RED,
	WarningType.PLANT_DESTROYED: Color.ORANGE,
	WarningType.LOW_POWER: Color.YELLOW,
	WarningType.GRID_CRITICAL: Color.RED
}

## Warning icons/prefixes
const WARNING_ICONS := {
	WarningType.DISTRICT_BLACKOUT: "[!] ",
	WarningType.PLANT_DESTROYED: "[X] ",
	WarningType.LOW_POWER: "[*] ",
	WarningType.GRID_CRITICAL: "[!!] "
}

## Animation timing
const FADE_IN_TIME := 0.2
const DISPLAY_TIME := 4.0
const FADE_OUT_TIME := 0.5
const PULSE_SPEED := 2.0

## Panel sizing
const WARNING_WIDTH := 300
const WARNING_HEIGHT := 60

## Active warnings
var _warnings: Array[Dictionary] = []
var _max_warnings := 5

## UI components
var _container: VBoxContainer = null
var _warning_panels: Array[PanelContainer] = []

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container - positioned at top-right
	_container = VBoxContainer.new()
	_container.name = "BlackoutWarning"
	_container.add_theme_constant_override("separation", 8)
	_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_container.position = Vector2(-WARNING_WIDTH - 20, 80)
	_container.custom_minimum_size.x = WARNING_WIDTH

	parent.add_child(_container)
	return _container


## Show district blackout warning.
func show_district_blackout(district_name: String) -> void:
	var message := "District '%s' lost power!" % district_name
	_add_warning(WarningType.DISTRICT_BLACKOUT, message)


## Show plant destroyed warning.
func show_plant_destroyed(plant_name: String) -> void:
	var message := "Power plant '%s' destroyed!" % plant_name
	_add_warning(WarningType.PLANT_DESTROYED, message)


## Show low power warning.
func show_low_power(surplus_percent: float) -> void:
	var message := "Low power! Surplus at %.0f%%" % surplus_percent
	_add_warning(WarningType.LOW_POWER, message)


## Show grid critical warning.
func show_grid_critical() -> void:
	var message := "GRID CRITICAL! Blackouts imminent!"
	_add_warning(WarningType.GRID_CRITICAL, message)


## Add a warning.
func _add_warning(type: WarningType, message: String) -> void:
	# Check if similar warning already exists
	for warning in _warnings:
		if warning["type"] == type and warning["message"] == message:
			return  # Don't duplicate

	# Remove oldest if at max
	if _warnings.size() >= _max_warnings:
		_remove_warning(0)

	# Add new warning
	var warning := {
		"type": type,
		"message": message,
		"time": Time.get_ticks_msec() / 1000.0
	}
	_warnings.append(warning)

	# Create panel
	var panel := _create_warning_panel(type, message)
	_warning_panels.append(panel)

	# Start auto-dismiss timer
	_start_dismiss_timer(panel, _warnings.size() - 1)


## Create warning panel.
func _create_warning_panel(type: WarningType, message: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WARNING_WIDTH, WARNING_HEIGHT)
	panel.modulate.a = 0.0

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a", 0.95)
	style.border_color = WARNING_COLORS[type]
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	# Content
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Warning icon/indicator
	var icon := Label.new()
	icon.text = WARNING_ICONS[type]
	icon.add_theme_font_size_override("font_size", 16)
	icon.add_theme_color_override("font_color", WARNING_COLORS[type])
	hbox.add_child(icon)

	# Message
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(label)

	# Dismiss button
	var dismiss := Button.new()
	dismiss.text = "X"
	dismiss.custom_minimum_size = Vector2(24, 24)
	dismiss.add_theme_font_size_override("font_size", 10)
	dismiss.pressed.connect(func(): _on_dismiss_pressed(panel))
	hbox.add_child(dismiss)

	_container.add_child(panel)

	# Fade in
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, FADE_IN_TIME)

	# Pulse for critical warnings
	if type == WarningType.GRID_CRITICAL or type == WarningType.DISTRICT_BLACKOUT:
		_start_pulse_animation(panel)

	return panel


## Start pulse animation for urgent warnings.
func _start_pulse_animation(panel: PanelContainer) -> void:
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return

	var original_color := style.border_color
	var pulse_tween := panel.create_tween()
	pulse_tween.set_loops(3)
	pulse_tween.tween_method(func(v: float):
		style.border_color = original_color.lerp(Color.WHITE, v)
	, 0.0, 1.0, 0.25 / PULSE_SPEED)
	pulse_tween.tween_method(func(v: float):
		style.border_color = original_color.lerp(Color.WHITE, v)
	, 1.0, 0.0, 0.25 / PULSE_SPEED)


## Start dismiss timer.
func _start_dismiss_timer(panel: PanelContainer, index: int) -> void:
	var tween := panel.create_tween()
	tween.tween_interval(DISPLAY_TIME)
	tween.tween_callback(func():
		if is_instance_valid(panel) and panel.get_parent() != null:
			_dismiss_panel(panel)
	)


## Handle dismiss button pressed.
func _on_dismiss_pressed(panel: PanelContainer) -> void:
	_dismiss_panel(panel)


## Dismiss a panel.
func _dismiss_panel(panel: PanelContainer) -> void:
	if not is_instance_valid(panel):
		return

	# Find and remove from arrays
	var index := _warning_panels.find(panel)
	if index >= 0:
		_warnings.remove_at(index)
		_warning_panels.remove_at(index)

	# Fade out and remove
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, FADE_OUT_TIME)
	tween.tween_callback(func():
		if is_instance_valid(panel):
			panel.queue_free()
	)

	warning_dismissed.emit()


## Remove warning by index.
func _remove_warning(index: int) -> void:
	if index < 0 or index >= _warnings.size():
		return

	_warnings.remove_at(index)
	if index < _warning_panels.size():
		var panel := _warning_panels[index]
		_warning_panels.remove_at(index)
		if is_instance_valid(panel):
			panel.queue_free()


## Clear all warnings.
func clear_all() -> void:
	for panel in _warning_panels:
		if is_instance_valid(panel):
			panel.queue_free()
	_warning_panels.clear()
	_warnings.clear()


## Get active warning count.
func get_warning_count() -> int:
	return _warnings.size()


## Has active warnings.
func has_warnings() -> bool:
	return not _warnings.is_empty()


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	clear_all()
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
