class_name FactoryHeatDisplay
extends RefCounted
## FactoryHeatDisplay shows heat level and overclocking controls.

signal overclock_changed(multiplier: float)
signal meltdown_warning()
signal meltdown_triggered()

## Heat thresholds (matching WO-99 requirements)
const HEAT_WARNING_THRESHOLD := 50.0   ## 50% - warning level
const HEAT_DANGER_THRESHOLD := 80.0    ## 80% - critical level
const HEAT_MELTDOWN_THRESHOLD := 100.0

## Warning messages
const MSG_WARNING := "WARNING: High heat"
const MSG_CRITICAL := "CRITICAL: MELTDOWN IMMINENT"
const MSG_MELTDOWN := "MELTDOWN IN PROGRESS"

## Overclock range
const MIN_OVERCLOCK := 1.0
const MAX_OVERCLOCK := 2.0
const OVERCLOCK_STEP := 0.1

## Current state
var _heat_level: float = 0.0
var _overclock_multiplier: float = 1.0
var _is_overheating: bool = false
var _is_meltdown: bool = false

## UI components
var _container: VBoxContainer = null
var _heat_bar: ProgressBar = null
var _heat_label: Label = null
var _overclock_slider: HSlider = null
var _overclock_label: Label = null
var _warning_label: Label = null
var _overclock_button_up: Button = null
var _overclock_button_down: Button = null


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control) -> Control:
	_container = VBoxContainer.new()
	_container.name = "HeatDisplay"

	# Heat section header
	var heat_header := Label.new()
	heat_header.text = "Heat Management"
	heat_header.add_theme_font_size_override("font_size", 14)
	_container.add_child(heat_header)

	# Heat bar
	var heat_bar_container := HBoxContainer.new()

	var heat_text := Label.new()
	heat_text.text = "Heat:"
	heat_text.custom_minimum_size.x = 50
	heat_bar_container.add_child(heat_text)

	_heat_bar = ProgressBar.new()
	_heat_bar.name = "HeatBar"
	_heat_bar.min_value = 0.0
	_heat_bar.max_value = 100.0
	_heat_bar.value = 0.0
	_heat_bar.show_percentage = false
	_heat_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heat_bar_container.add_child(_heat_bar)

	_heat_label = Label.new()
	_heat_label.text = "0%"
	_heat_label.custom_minimum_size.x = 45
	_heat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heat_bar_container.add_child(_heat_label)

	_container.add_child(heat_bar_container)

	# Warning label
	_warning_label = Label.new()
	_warning_label.name = "WarningLabel"
	_warning_label.text = ""
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.visible = false
	_container.add_child(_warning_label)

	# Separator
	var sep := HSeparator.new()
	_container.add_child(sep)

	# Overclock section
	var overclock_header := Label.new()
	overclock_header.text = "Overclocking"
	overclock_header.add_theme_font_size_override("font_size", 14)
	_container.add_child(overclock_header)

	# Overclock slider
	var slider_container := HBoxContainer.new()

	_overclock_button_down = Button.new()
	_overclock_button_down.text = "-"
	_overclock_button_down.custom_minimum_size = Vector2(30, 30)
	_overclock_button_down.pressed.connect(_decrease_overclock)
	slider_container.add_child(_overclock_button_down)

	_overclock_slider = HSlider.new()
	_overclock_slider.name = "OverclockSlider"
	_overclock_slider.min_value = MIN_OVERCLOCK
	_overclock_slider.max_value = MAX_OVERCLOCK
	_overclock_slider.step = OVERCLOCK_STEP
	_overclock_slider.value = 1.0
	_overclock_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overclock_slider.value_changed.connect(_on_slider_changed)
	slider_container.add_child(_overclock_slider)

	_overclock_button_up = Button.new()
	_overclock_button_up.text = "+"
	_overclock_button_up.custom_minimum_size = Vector2(30, 30)
	_overclock_button_up.pressed.connect(_increase_overclock)
	slider_container.add_child(_overclock_button_up)

	_container.add_child(slider_container)

	# Overclock label
	_overclock_label = Label.new()
	_overclock_label.text = "Speed: 1.0x"
	_overclock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_container.add_child(_overclock_label)

	parent.add_child(_container)

	_update_heat_bar_color()

	return _container


## Update heat level.
func set_heat_level(heat: float) -> void:
	_heat_level = clampf(heat, 0.0, 100.0)

	if _heat_bar != null:
		_heat_bar.value = _heat_level

	if _heat_label != null:
		_heat_label.text = "%.0f%%" % _heat_level

	_update_heat_bar_color()
	_check_heat_warnings()


## Update heat bar color based on level.
func _update_heat_bar_color() -> void:
	if _heat_bar == null:
		return

	var color: Color

	if _heat_level < HEAT_WARNING_THRESHOLD:
		color = Color.GREEN
	elif _heat_level < HEAT_DANGER_THRESHOLD:
		color = Color.YELLOW
	else:
		color = Color.RED

	var style := StyleBoxFlat.new()
	style.bg_color = color
	_heat_bar.add_theme_stylebox_override("fill", style)


## Check heat warnings.
func _check_heat_warnings() -> void:
	var old_overheating := _is_overheating
	var old_meltdown := _is_meltdown

	_is_overheating = _heat_level >= HEAT_WARNING_THRESHOLD
	_is_meltdown = _heat_level >= HEAT_MELTDOWN_THRESHOLD

	# Update warning label
	if _warning_label != null:
		if _is_meltdown:
			_warning_label.text = MSG_MELTDOWN
			_warning_label.add_theme_color_override("font_color", Color.RED)
			_warning_label.visible = true
			# Disable overclock controls during meltdown
			set_overclock_enabled(false)
		elif _heat_level >= HEAT_DANGER_THRESHOLD:
			_warning_label.text = MSG_CRITICAL
			_warning_label.add_theme_color_override("font_color", Color.ORANGE)
			_warning_label.visible = true
		elif _is_overheating:
			_warning_label.text = MSG_WARNING
			_warning_label.add_theme_color_override("font_color", Color.YELLOW)
			_warning_label.visible = true
		else:
			_warning_label.visible = false

	# Emit signals
	if _is_overheating and not old_overheating:
		meltdown_warning.emit()

	if _is_meltdown and not old_meltdown:
		meltdown_triggered.emit()


## Handle factory melted down signal.
func on_factory_melted_down() -> void:
	_is_meltdown = true
	if _warning_label != null:
		_warning_label.text = MSG_MELTDOWN
		_warning_label.add_theme_color_override("font_color", Color.RED)
		_warning_label.visible = true
	set_overclock_enabled(false)


## Handle factory recovered signal.
func on_factory_recovered() -> void:
	_is_meltdown = false
	_is_overheating = false
	_heat_level = 0.0
	if _heat_bar != null:
		_heat_bar.value = 0.0
	if _heat_label != null:
		_heat_label.text = "0%"
	if _warning_label != null:
		_warning_label.visible = false
	set_overclock_enabled(true)
	_update_heat_bar_color()


## Set overclock multiplier.
func set_overclock_multiplier(multiplier: float) -> void:
	_overclock_multiplier = clampf(multiplier, MIN_OVERCLOCK, MAX_OVERCLOCK)

	if _overclock_slider != null:
		_overclock_slider.value = _overclock_multiplier

	if _overclock_label != null:
		_overclock_label.text = "Speed: %.1fx" % _overclock_multiplier


## Handle slider value change.
func _on_slider_changed(value: float) -> void:
	_overclock_multiplier = value

	if _overclock_label != null:
		_overclock_label.text = "Speed: %.1fx" % _overclock_multiplier

	overclock_changed.emit(_overclock_multiplier)


## Increase overclock.
func _increase_overclock() -> void:
	var new_value := minf(_overclock_multiplier + OVERCLOCK_STEP, MAX_OVERCLOCK)
	if _overclock_slider != null:
		_overclock_slider.value = new_value


## Decrease overclock.
func _decrease_overclock() -> void:
	var new_value := maxf(_overclock_multiplier - OVERCLOCK_STEP, MIN_OVERCLOCK)
	if _overclock_slider != null:
		_overclock_slider.value = new_value


## Enable/disable overclock controls.
func set_overclock_enabled(enabled: bool) -> void:
	if _overclock_slider != null:
		_overclock_slider.editable = enabled

	if _overclock_button_up != null:
		_overclock_button_up.disabled = not enabled

	if _overclock_button_down != null:
		_overclock_button_down.disabled = not enabled


## Get current heat level.
func get_heat_level() -> float:
	return _heat_level


## Get current overclock multiplier.
func get_overclock_multiplier() -> float:
	return _overclock_multiplier


## Check if overheating.
func is_overheating() -> bool:
	return _is_overheating


## Check if meltdown.
func is_meltdown() -> bool:
	return _is_meltdown


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()

	_container = null
	_heat_bar = null
	_heat_label = null
	_overclock_slider = null
	_overclock_label = null
	_warning_label = null


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"heat_level": _heat_level,
		"overclock_multiplier": _overclock_multiplier,
		"is_overheating": _is_overheating,
		"is_meltdown": _is_meltdown
	}
