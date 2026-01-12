class_name WaveCompletePopup
extends RefCounted
## WaveCompletePopup shows "Wave Complete!" message with stats.

signal animation_finished()
signal continue_pressed()

## Animation timing
const FADE_IN_TIME := 0.3
const DISPLAY_TIME := 2.0
const FADE_OUT_TIME := 0.5

## Panel sizing
const PANEL_WIDTH := 350
const PANEL_HEIGHT := 200

## Current state
var _is_showing := false
var _wave_number := 0
var _duration := 0.0
var _kills := 0

## UI components
var _container: PanelContainer = null
var _title_label: Label = null
var _wave_label: Label = null
var _duration_label: Label = null
var _kills_label: Label = null
var _continue_button: Button = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container - centered
	_container = PanelContainer.new()
	_container.name = "WaveCompletePopup"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_container.set_anchors_preset(Control.PRESET_CENTER)
	_container.position = Vector2(-PANEL_WIDTH / 2, -PANEL_HEIGHT / 2)
	_container.visible = false
	_container.modulate.a = 0.0

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a", 0.95)
	style.border_color = _faction_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	_container.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_container.add_child(vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "WAVE COMPLETE!"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color.GREEN)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# Wave number
	_wave_label = Label.new()
	_wave_label.text = "Wave 1"
	_wave_label.add_theme_font_size_override("font_size", 18)
	_wave_label.add_theme_color_override("font_color", Color.WHITE)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_wave_label)

	# Stats container
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 16)
	stats.add_theme_constant_override("v_separation", 8)

	# Duration
	var dur_label := Label.new()
	dur_label.text = "Duration:"
	dur_label.add_theme_font_size_override("font_size", 14)
	dur_label.add_theme_color_override("font_color", Color("#888888"))
	stats.add_child(dur_label)

	_duration_label = Label.new()
	_duration_label.text = "00:00"
	_duration_label.add_theme_font_size_override("font_size", 14)
	_duration_label.add_theme_color_override("font_color", Color.WHITE)
	stats.add_child(_duration_label)

	# Kills
	var kills_label := Label.new()
	kills_label.text = "Enemies Defeated:"
	kills_label.add_theme_font_size_override("font_size", 14)
	kills_label.add_theme_color_override("font_color", Color("#888888"))
	stats.add_child(kills_label)

	_kills_label = Label.new()
	_kills_label.text = "0"
	_kills_label.add_theme_font_size_override("font_size", 14)
	_kills_label.add_theme_color_override("font_color", Color.WHITE)
	stats.add_child(_kills_label)

	vbox.add_child(stats)

	# Continue button (optional)
	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.custom_minimum_size = Vector2(120, 40)
	_continue_button.visible = false
	_continue_button.pressed.connect(func():
		continue_pressed.emit()
		hide_popup()
	)
	vbox.add_child(_continue_button)

	parent.add_child(_container)
	return _container


## Show popup with wave stats.
func show_popup(wave_number: int, duration: float, kills: int, show_continue_button: bool = false) -> void:
	if _is_showing:
		return

	_wave_number = wave_number
	_duration = duration
	_kills = kills
	_is_showing = true

	# Update content
	if _wave_label != null:
		_wave_label.text = "Wave %d" % wave_number

	if _duration_label != null:
		var minutes := int(duration) / 60
		var seconds := int(duration) % 60
		_duration_label.text = "%02d:%02d" % [minutes, seconds]

	if _kills_label != null:
		_kills_label.text = str(kills)

	if _continue_button != null:
		_continue_button.visible = show_continue_button

	# Show with animation
	_container.visible = true
	_container.modulate.a = 0.0
	_container.scale = Vector2(0.8, 0.8)

	var tween := _container.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_container, "modulate:a", 1.0, FADE_IN_TIME)
	tween.tween_property(_container, "scale", Vector2(1.0, 1.0), FADE_IN_TIME).set_trans(Tween.TRANS_BACK)

	# Auto-hide after delay if no continue button
	if not show_continue_button:
		tween.chain().tween_interval(DISPLAY_TIME)
		tween.chain().tween_callback(hide_popup)


## Hide popup.
func hide_popup() -> void:
	if not _is_showing:
		return

	var tween := _container.create_tween()
	tween.tween_property(_container, "modulate:a", 0.0, FADE_OUT_TIME)
	tween.finished.connect(func():
		_container.visible = false
		_is_showing = false
		animation_finished.emit()
	)


## Check if showing.
func is_showing() -> bool:
	return _is_showing


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _container != null:
		var style := _container.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = _faction_color


## Get container.
func get_container() -> Control:
	return _container


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
