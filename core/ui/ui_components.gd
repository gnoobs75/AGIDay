class_name UIComponents
extends RefCounted
## UIComponents provides a factory for creating styled UI elements.
## Integrates with UITheme, UIScaling, and UIAccessibility for consistent styling.

signal component_created(component: Control, component_type: String)

## Component types for tracking
enum ComponentType {
	PANEL,
	BUTTON,
	LABEL,
	HEADER,
	PROGRESS_BAR,
	ICON_BUTTON,
	TEXT_INPUT,
	DROPDOWN,
	TOGGLE,
	SLIDER,
	SEPARATOR
}

## References to other UI systems
var _theme: UITheme = null
var _scaling: UIScaling = null
var _accessibility: UIAccessibility = null

## Performance mode
var _performance_mode := false

## Component pool for recycling
var _component_pools: Dictionary = {}  ## ComponentType -> Array[Control]

## Active components for cleanup
var _active_components: Array[WeakRef] = []


func _init() -> void:
	pass


## Initialize with UI systems.
func initialize(theme: UITheme, scaling: UIScaling, accessibility: UIAccessibility) -> void:
	_theme = theme
	_scaling = scaling
	_accessibility = accessibility


## Set performance mode (reduced animations/effects).
func set_performance_mode(enabled: bool) -> void:
	_performance_mode = enabled


## Create a styled panel.
func create_panel(faction_id: String = "", transparent: bool = true) -> PanelContainer:
	var panel := PanelContainer.new()

	# Apply theme
	if _theme != null:
		panel.theme = _theme.get_faction_theme(faction_id)

		var style := _theme.create_panel_style(faction_id, transparent)
		if _accessibility != null:
			_accessibility.apply_to_stylebox(style, _theme.get_faction_color(faction_id))
		panel.add_theme_stylebox_override("panel", style)

	_track_component(panel)
	component_created.emit(panel, "panel")
	return panel


## Create a styled header panel.
func create_header_panel(title: String, faction_id: String = "") -> PanelContainer:
	var panel := PanelContainer.new()

	if _theme != null:
		panel.theme = _theme.get_faction_theme(faction_id)
		var style := _theme.create_header_style(faction_id)
		if _accessibility != null:
			_accessibility.apply_to_stylebox(style, _theme.get_faction_color(faction_id))
		panel.add_theme_stylebox_override("panel", style)

	# Add title label
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var font_size := UITheme.FONT_SIZE_HEADER
	if _accessibility != null:
		font_size = _accessibility.get_scaled_font_size(font_size)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)

	panel.add_child(label)

	_track_component(panel)
	component_created.emit(panel, "header_panel")
	return panel


## Create a styled button.
func create_button(text: String, faction_id: String = "") -> Button:
	var button := Button.new()
	button.text = text

	if _theme != null:
		button.theme = _theme.get_faction_theme(faction_id)

	if _accessibility != null:
		_accessibility.apply_to_button(button)

	# Minimum touch target size
	if _scaling != null:
		var min_size := _scaling.get_min_touch_target_size()
		button.custom_minimum_size = min_size

	_track_component(button)
	component_created.emit(button, "button")
	return button


## Create an icon button.
func create_icon_button(icon_texture: Texture2D, tooltip: String = "", faction_id: String = "") -> Button:
	var button := Button.new()
	button.icon = icon_texture
	button.tooltip_text = tooltip
	button.expand_icon = true

	if _theme != null:
		button.theme = _theme.get_faction_theme(faction_id)

	# Square button for icon
	var size := 44.0
	if _scaling != null:
		size = _scaling.scale_value(44.0)
	button.custom_minimum_size = Vector2(size, size)

	if _accessibility != null:
		_accessibility.apply_to_button(button)

	_track_component(button)
	component_created.emit(button, "icon_button")
	return button


## Create a styled label.
func create_label(text: String, size: String = "body", color: Color = UITheme.TEXT_COLOR) -> Label:
	var label := Label.new()
	label.text = text

	# Determine font size
	var font_size: int
	match size:
		"body": font_size = UITheme.FONT_SIZE_BODY
		"label": font_size = UITheme.FONT_SIZE_LABEL
		"header": font_size = UITheme.FONT_SIZE_HEADER
		"title": font_size = UITheme.FONT_SIZE_TITLE
		"large_title": font_size = UITheme.FONT_SIZE_LARGE_TITLE
		_: font_size = UITheme.FONT_SIZE_BODY

	if _accessibility != null:
		font_size = _accessibility.get_scaled_font_size(font_size)
		color = _accessibility.transform_color(color)

	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)

	_track_component(label)
	component_created.emit(label, "label")
	return label


## Create a styled progress bar.
func create_progress_bar(faction_id: String = "", show_percentage: bool = true) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = show_percentage

	if _theme != null:
		bar.theme = _theme.get_faction_theme(faction_id)

	# Default size
	var height := 20.0
	if _scaling != null:
		height = _scaling.scale_value(20.0)
	bar.custom_minimum_size.y = height

	_track_component(bar)
	component_created.emit(bar, "progress_bar")
	return bar


## Create a styled text input.
func create_text_input(placeholder: String = "", faction_id: String = "") -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder

	if _theme != null:
		input.theme = _theme.get_faction_theme(faction_id)

	var font_size := UITheme.FONT_SIZE_BODY
	if _accessibility != null:
		font_size = _accessibility.get_scaled_font_size(font_size)
	input.add_theme_font_size_override("font_size", font_size)

	_track_component(input)
	component_created.emit(input, "text_input")
	return input


## Create a styled dropdown.
func create_dropdown(items: Array[String], faction_id: String = "") -> OptionButton:
	var dropdown := OptionButton.new()

	for item in items:
		dropdown.add_item(item)

	if _theme != null:
		dropdown.theme = _theme.get_faction_theme(faction_id)

	if _scaling != null:
		var min_size := _scaling.get_min_touch_target_size()
		dropdown.custom_minimum_size.y = min_size.y

	_track_component(dropdown)
	component_created.emit(dropdown, "dropdown")
	return dropdown


## Create a styled toggle button.
func create_toggle(text: String, faction_id: String = "") -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text

	if _theme != null:
		toggle.theme = _theme.get_faction_theme(faction_id)

	if _accessibility != null:
		var font_size := _accessibility.get_scaled_font_size(UITheme.FONT_SIZE_LABEL)
		toggle.add_theme_font_size_override("font_size", font_size)

	_track_component(toggle)
	component_created.emit(toggle, "toggle")
	return toggle


## Create a styled slider.
func create_slider(min_val: float, max_val: float, step: float = 1.0, faction_id: String = "") -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step

	if _theme != null:
		slider.theme = _theme.get_faction_theme(faction_id)

	var height := 24.0
	if _scaling != null:
		height = _scaling.scale_value(24.0)
	slider.custom_minimum_size.y = height

	_track_component(slider)
	component_created.emit(slider, "slider")
	return slider


## Create a horizontal separator.
func create_separator_h() -> HSeparator:
	var sep := HSeparator.new()

	if _theme != null:
		sep.theme = _theme.get_base_theme()

	_track_component(sep)
	return sep


## Create a vertical separator.
func create_separator_v() -> VSeparator:
	var sep := VSeparator.new()

	if _theme != null:
		sep.theme = _theme.get_base_theme()

	_track_component(sep)
	return sep


## Create a horizontal container with spacing.
func create_hbox(spacing: String = "normal") -> HBoxContainer:
	var container := HBoxContainer.new()

	var gap := 8
	if _scaling != null:
		gap = int(_scaling.get_spacing(spacing))
	container.add_theme_constant_override("separation", gap)

	_track_component(container)
	return container


## Create a vertical container with spacing.
func create_vbox(spacing: String = "normal") -> VBoxContainer:
	var container := VBoxContainer.new()

	var gap := 8
	if _scaling != null:
		gap = int(_scaling.get_spacing(spacing))
	container.add_theme_constant_override("separation", gap)

	_track_component(container)
	return container


## Create a grid container.
func create_grid(columns: int, spacing: String = "normal") -> GridContainer:
	var container := GridContainer.new()
	container.columns = columns

	var gap := 8
	if _scaling != null:
		gap = int(_scaling.get_spacing(spacing))
	container.add_theme_constant_override("h_separation", gap)
	container.add_theme_constant_override("v_separation", gap)

	_track_component(container)
	return container


## Create a margin container with padding.
func create_margin(margin_size: String = "normal") -> MarginContainer:
	var container := MarginContainer.new()

	var margin := 16
	if _scaling != null:
		margin = int(_scaling.get_margin(margin_size))

	container.add_theme_constant_override("margin_left", margin)
	container.add_theme_constant_override("margin_right", margin)
	container.add_theme_constant_override("margin_top", margin)
	container.add_theme_constant_override("margin_bottom", margin)

	_track_component(container)
	return container


## Create a scroll container.
func create_scroll(horizontal: bool = false, vertical: bool = true) -> ScrollContainer:
	var container := ScrollContainer.new()
	container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if vertical else ScrollContainer.SCROLL_MODE_DISABLED

	if _theme != null:
		container.theme = _theme.get_base_theme()

	_track_component(container)
	return container


## Animate a control with a tween (respects performance/accessibility).
func animate_control(control: Control, property: String, target_value: Variant, duration: float = 0.2) -> Tween:
	# Check if animations should be skipped
	if _performance_mode:
		control.set(property, target_value)
		return null

	var actual_duration := duration
	var transition := Tween.TRANS_CUBIC

	if _accessibility != null:
		actual_duration = _accessibility.get_animation_duration(duration)
		transition = _accessibility.get_tween_transition()

	if actual_duration <= 0:
		control.set(property, target_value)
		return null

	var tween := control.create_tween()
	tween.set_trans(transition)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(control, property, target_value, actual_duration)
	return tween


## Animate fade in.
func fade_in(control: Control, duration: float = 0.2) -> Tween:
	control.modulate.a = 0.0
	control.visible = true
	return animate_control(control, "modulate:a", 1.0, duration)


## Animate fade out.
func fade_out(control: Control, duration: float = 0.2, hide_after: bool = true) -> Tween:
	var tween := animate_control(control, "modulate:a", 0.0, duration)
	if tween != null and hide_after:
		tween.finished.connect(func(): control.visible = false)
	elif tween == null and hide_after:
		control.visible = false
	return tween


## Track a component for cleanup.
func _track_component(control: Control) -> void:
	_active_components.append(weakref(control))


## Clean up dead references.
func cleanup_dead_references() -> void:
	var alive: Array[WeakRef] = []
	for ref in _active_components:
		if ref.get_ref() != null:
			alive.append(ref)
	_active_components = alive


## Get active component count.
func get_active_count() -> int:
	cleanup_dead_references()
	return _active_components.size()


## Get statistics.
func get_statistics() -> Dictionary:
	cleanup_dead_references()
	return {
		"active_components": _active_components.size(),
		"performance_mode": _performance_mode,
		"has_theme": _theme != null,
		"has_scaling": _scaling != null,
		"has_accessibility": _accessibility != null
	}
