class_name DifficultyIndicator
extends RefCounted
## DifficultyIndicator displays wave difficulty with visual bar and color coding.

signal difficulty_changed(new_difficulty: float)

## Difficulty thresholds
const EASY_THRESHOLD := 0.3
const MEDIUM_THRESHOLD := 0.6
const HARD_THRESHOLD := 0.85

## Colors
const EASY_COLOR := Color.GREEN
const MEDIUM_COLOR := Color.YELLOW
const HARD_COLOR := Color.ORANGE
const EXTREME_COLOR := Color.RED

## UI sizing
const BAR_WIDTH := 100
const BAR_HEIGHT := 12

## Current state
var _difficulty := 0.0          ## 0.0 to 1.0
var _previous_difficulty := 0.0
var _wave_number := 0

## UI components
var _container: HBoxContainer = null
var _label: Label = null
var _bar: ProgressBar = null
var _difficulty_label: Label = null


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control) -> Control:
	# Container
	_container = HBoxContainer.new()
	_container.name = "DifficultyIndicator"
	_container.add_theme_constant_override("separation", 8)

	# Label
	_label = Label.new()
	_label.text = "Difficulty:"
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color("#888888"))
	_container.add_child(_label)

	# Progress bar
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = EASY_COLOR
	bar_fill.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("fill", bar_fill)

	_container.add_child(_bar)

	# Difficulty text label
	_difficulty_label = Label.new()
	_difficulty_label.text = "Easy"
	_difficulty_label.add_theme_font_size_override("font_size", 11)
	_difficulty_label.add_theme_color_override("font_color", EASY_COLOR)
	_difficulty_label.custom_minimum_size.x = 60
	_container.add_child(_difficulty_label)

	parent.add_child(_container)
	return _container


## Set difficulty value (0.0 to 1.0).
func set_difficulty(difficulty: float, wave_number: int = 0) -> void:
	_previous_difficulty = _difficulty
	_difficulty = clampf(difficulty, 0.0, 1.0)
	_wave_number = wave_number
	_update_display()

	if not is_equal_approx(_previous_difficulty, _difficulty):
		difficulty_changed.emit(_difficulty)


## Update display.
func _update_display() -> void:
	if _bar != null:
		_bar.value = _difficulty * 100.0

		# Update bar color
		var bar_fill := _bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			bar_fill.bg_color = _get_difficulty_color()

	if _difficulty_label != null:
		_difficulty_label.text = _get_difficulty_text()
		_difficulty_label.add_theme_color_override("font_color", _get_difficulty_color())


## Get difficulty color.
func _get_difficulty_color() -> Color:
	if _difficulty < EASY_THRESHOLD:
		return EASY_COLOR
	elif _difficulty < MEDIUM_THRESHOLD:
		return EASY_COLOR.lerp(MEDIUM_COLOR, (_difficulty - EASY_THRESHOLD) / (MEDIUM_THRESHOLD - EASY_THRESHOLD))
	elif _difficulty < HARD_THRESHOLD:
		return MEDIUM_COLOR.lerp(HARD_COLOR, (_difficulty - MEDIUM_THRESHOLD) / (HARD_THRESHOLD - MEDIUM_THRESHOLD))
	else:
		return HARD_COLOR.lerp(EXTREME_COLOR, (_difficulty - HARD_THRESHOLD) / (1.0 - HARD_THRESHOLD))


## Get difficulty text.
func _get_difficulty_text() -> String:
	if _difficulty < EASY_THRESHOLD:
		return "Easy"
	elif _difficulty < MEDIUM_THRESHOLD:
		return "Medium"
	elif _difficulty < HARD_THRESHOLD:
		return "Hard"
	else:
		return "EXTREME"


## Get difficulty level (0-3).
func get_difficulty_level() -> int:
	if _difficulty < EASY_THRESHOLD:
		return 0
	elif _difficulty < MEDIUM_THRESHOLD:
		return 1
	elif _difficulty < HARD_THRESHOLD:
		return 2
	else:
		return 3


## Calculate difficulty from wave number (default formula).
func calculate_from_wave(wave_number: int, max_waves: int = 100) -> float:
	# Logarithmic scaling for smooth progression
	var base := log(float(wave_number) + 1) / log(float(max_waves) + 1)
	# Add some variance based on wave number
	var variance := sin(float(wave_number) * 0.5) * 0.05
	return clampf(base + variance, 0.0, 1.0)


## Compare to previous difficulty.
func get_difficulty_change() -> float:
	return _difficulty - _previous_difficulty


## Is difficulty increasing.
func is_increasing() -> bool:
	return _difficulty > _previous_difficulty


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Get current difficulty.
func get_difficulty() -> float:
	return _difficulty


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
