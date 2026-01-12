class_name NextWaveCountdown
extends RefCounted
## NextWaveCountdown displays countdown timer between waves with skip option.

signal countdown_complete()
signal countdown_skipped()

## Default countdown duration
const DEFAULT_COUNTDOWN := 3.0
const SKIP_HOTKEY_TEXT := "[SPACE to Skip]"

## UI components
var _container: Control = null
var _countdown_label: Label = null
var _skip_label: Label = null
var _progress_ring: Control = null

## State
var _countdown_time := DEFAULT_COUNTDOWN
var _time_remaining := 0.0
var _is_counting := false
var _next_wave_number := 0

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container - centered
	_container = Control.new()
	_container.name = "NextWaveCountdown"
	_container.set_anchors_preset(Control.PRESET_CENTER)
	_container.custom_minimum_size = Vector2(200, 200)
	_container.position = Vector2(-100, -100)
	_container.visible = false

	# Background circle
	var bg := ColorRect.new()
	bg.color = Color("#1a1a1a", 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.add_child(bg)

	# Progress ring (custom draw)
	_progress_ring = Control.new()
	_progress_ring.name = "ProgressRing"
	_progress_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress_ring.draw.connect(_draw_progress_ring)
	_container.add_child(_progress_ring)

	# Content container
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_container.add_child(vbox)

	# "Next Wave" text
	var next_label := Label.new()
	next_label.text = "NEXT WAVE"
	next_label.add_theme_font_size_override("font_size", 14)
	next_label.add_theme_color_override("font_color", Color("#888888"))
	next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(next_label)

	# Countdown number
	_countdown_label = Label.new()
	_countdown_label.text = "3"
	_countdown_label.add_theme_font_size_override("font_size", 48)
	_countdown_label.add_theme_color_override("font_color", Color.WHITE)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_countdown_label)

	# Skip hint
	_skip_label = Label.new()
	_skip_label.text = SKIP_HOTKEY_TEXT
	_skip_label.add_theme_font_size_override("font_size", 11)
	_skip_label.add_theme_color_override("font_color", Color("#666666"))
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_skip_label)

	parent.add_child(_container)
	return _container


## Draw the progress ring.
func _draw_progress_ring() -> void:
	if _progress_ring == null or not _is_counting:
		return

	var center := _progress_ring.size / 2
	var radius := minf(center.x, center.y) - 10
	var progress := 1.0 - (_time_remaining / _countdown_time)
	var end_angle := -PI / 2 + progress * TAU

	# Background ring
	_progress_ring.draw_arc(center, radius, 0, TAU, 64, Color("#333333"), 6.0)

	# Progress arc
	if progress > 0:
		_progress_ring.draw_arc(center, radius, -PI / 2, end_angle, 64, _faction_color, 6.0)


## Start countdown.
func start_countdown(duration: float = DEFAULT_COUNTDOWN, next_wave: int = 0) -> void:
	_countdown_time = duration
	_time_remaining = duration
	_next_wave_number = next_wave
	_is_counting = true

	_container.visible = true
	_container.modulate.a = 0.0

	# Fade in
	var tween := _container.create_tween()
	tween.tween_property(_container, "modulate:a", 1.0, 0.2)


## Update countdown (call each frame).
func update(delta: float) -> void:
	if not _is_counting:
		return

	_time_remaining -= delta
	_time_remaining = maxf(_time_remaining, 0.0)

	# Update display
	if _countdown_label != null:
		_countdown_label.text = str(ceili(_time_remaining))

	if _progress_ring != null:
		_progress_ring.queue_redraw()

	# Check completion
	if _time_remaining <= 0:
		_complete_countdown()


## Skip the countdown.
func skip() -> void:
	if not _is_counting:
		return

	_time_remaining = 0
	countdown_skipped.emit()
	_complete_countdown()


## Complete the countdown.
func _complete_countdown() -> void:
	_is_counting = false

	# Fade out
	var tween := _container.create_tween()
	tween.tween_property(_container, "modulate:a", 0.0, 0.2)
	tween.finished.connect(func():
		_container.visible = false
		countdown_complete.emit()
	)


## Check if counting.
func is_counting() -> bool:
	return _is_counting


## Get remaining time.
func get_time_remaining() -> float:
	return _time_remaining


## Cancel countdown.
func cancel() -> void:
	_is_counting = false
	_container.visible = false


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])


## Get container.
func get_container() -> Control:
	return _container


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
