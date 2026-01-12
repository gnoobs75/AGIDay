class_name WaveDisplay
extends RefCounted
## WaveDisplay shows wave counter, timer, and remaining enemies in HUD.

signal skip_countdown_requested()

## Panel sizing
const PANEL_WIDTH := 180
const PANEL_HEIGHT := 100

## Current state
var _wave_number := 0
var _elapsed_time := 0.0
var _enemies_remaining := 0
var _total_enemies := 0

## UI components
var _container: PanelContainer = null
var _wave_label: Label = null
var _timer_label: Label = null
var _enemies_label: Label = null
var _enemies_bar: ProgressBar = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container - top center
	_container = PanelContainer.new()
	_container.name = "WaveDisplay"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d", 0.85)
	style.border_color = _faction_color.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	_container.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_container.add_child(vbox)

	# Wave number (prominent)
	_wave_label = Label.new()
	_wave_label.text = "WAVE 1"
	_wave_label.add_theme_font_size_override("font_size", 24)
	_wave_label.add_theme_color_override("font_color", Color.WHITE)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_wave_label)

	# Timer
	var timer_row := HBoxContainer.new()
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.add_theme_constant_override("separation", 8)

	var timer_icon := Label.new()
	timer_icon.text = "[TIME]"
	timer_icon.add_theme_font_size_override("font_size", 10)
	timer_icon.add_theme_color_override("font_color", Color("#888888"))
	timer_row.add_child(timer_icon)

	_timer_label = Label.new()
	_timer_label.text = "00:00"
	_timer_label.add_theme_font_size_override("font_size", 14)
	_timer_label.add_theme_color_override("font_color", Color("#cccccc"))
	timer_row.add_child(_timer_label)

	vbox.add_child(timer_row)

	# Enemies remaining
	var enemies_row := HBoxContainer.new()
	enemies_row.add_theme_constant_override("separation", 8)

	var enemies_icon := Label.new()
	enemies_icon.text = "[ENEMIES]"
	enemies_icon.add_theme_font_size_override("font_size", 10)
	enemies_icon.add_theme_color_override("font_color", Color.RED.darkened(0.3))
	enemies_row.add_child(enemies_icon)

	_enemies_label = Label.new()
	_enemies_label.text = "0/0"
	_enemies_label.add_theme_font_size_override("font_size", 12)
	_enemies_label.add_theme_color_override("font_color", Color.WHITE)
	enemies_row.add_child(_enemies_label)

	vbox.add_child(enemies_row)

	# Progress bar for enemies
	_enemies_bar = ProgressBar.new()
	_enemies_bar.min_value = 0.0
	_enemies_bar.max_value = 100.0
	_enemies_bar.value = 100.0
	_enemies_bar.show_percentage = false
	_enemies_bar.custom_minimum_size.y = 8

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_enemies_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.RED
	bar_fill.set_corner_radius_all(2)
	_enemies_bar.add_theme_stylebox_override("fill", bar_fill)

	vbox.add_child(_enemies_bar)

	parent.add_child(_container)
	return _container


## Update wave information.
func update_wave(wave_number: int, elapsed_time: float, enemies_remaining: int, total_enemies: int) -> void:
	_wave_number = wave_number
	_elapsed_time = elapsed_time
	_enemies_remaining = enemies_remaining
	_total_enemies = total_enemies
	_update_display()


## Update just the wave number.
func set_wave_number(wave_number: int) -> void:
	_wave_number = wave_number
	if _wave_label != null:
		_wave_label.text = "WAVE %d" % wave_number


## Update elapsed time.
func set_elapsed_time(elapsed: float) -> void:
	_elapsed_time = elapsed
	if _timer_label != null:
		var minutes := int(elapsed) / 60
		var seconds := int(elapsed) % 60
		_timer_label.text = "%02d:%02d" % [minutes, seconds]


## Update enemies remaining.
func set_enemies(remaining: int, total: int) -> void:
	_enemies_remaining = remaining
	_total_enemies = total

	if _enemies_label != null:
		_enemies_label.text = "%d/%d" % [remaining, total]

	if _enemies_bar != null and total > 0:
		_enemies_bar.value = (float(remaining) / float(total)) * 100.0

		# Color based on remaining
		var bar_fill := _enemies_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			if remaining <= total * 0.1:
				bar_fill.bg_color = Color.GREEN  ## Almost done
			elif remaining <= total * 0.5:
				bar_fill.bg_color = Color.YELLOW
			else:
				bar_fill.bg_color = Color.RED


## Update full display.
func _update_display() -> void:
	set_wave_number(_wave_number)
	set_elapsed_time(_elapsed_time)
	set_enemies(_enemies_remaining, _total_enemies)


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


## Get current state.
func get_state() -> Dictionary:
	return {
		"wave_number": _wave_number,
		"elapsed_time": _elapsed_time,
		"enemies_remaining": _enemies_remaining,
		"total_enemies": _total_enemies
	}


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
