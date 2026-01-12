class_name AetherSwarmTheme
extends RefCounted
## AetherSwarmTheme provides faction-specific UI styling for Aether Swarm.

## Faction identification
const FACTION_ID := "aether_swarm"
const FACTION_NAME := "Aether Swarm"

## Color palette
const PRIMARY_COLOR := Color.CYAN
const SECONDARY_COLOR := Color.BLUE
const ACCENT_COLOR := Color("#80FFFF")  # Light cyan
const TEXT_COLOR := Color.WHITE
const BACKGROUND_COLOR := Color(0.0, 0.2, 0.3, 0.8)  # Semi-transparent dark blue
const BORDER_COLOR := Color.CYAN
const HOVER_COLOR := Color("#40E0FF")  # Brighter cyan

## Button states
const BUTTON_NORMAL_BG := Color(0.0, 0.3, 0.4, 0.9)
const BUTTON_HOVER_BG := Color(0.0, 0.4, 0.5, 0.95)
const BUTTON_PRESSED_BG := Color(0.0, 0.2, 0.3, 1.0)
const BUTTON_DISABLED_BG := Color(0.1, 0.2, 0.25, 0.6)

## Typography
const FONT_FAMILY := "JetBrains Mono"
const FONT_SIZE_BODY := 12
const FONT_SIZE_LABEL := 10
const FONT_SIZE_HEADER := 16
const FONT_SIZE_TITLE := 24

## Animation timing
const ANIMATION_FAST := 0.1
const ANIMATION_NORMAL := 0.2
const GLOW_PULSE_SPEED := 2.0

## Performance limits
const MAX_EFFECT_TIME_MS := 1.0


## Create themed panel style.
static func create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	return style


## Create themed button styles.
static func create_button_styles() -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON_NORMAL_BG
	normal.border_color = PRIMARY_COLOR
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)

	var hover := StyleBoxFlat.new()
	hover.bg_color = BUTTON_HOVER_BG
	hover.border_color = ACCENT_COLOR
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(4)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = BUTTON_PRESSED_BG
	pressed.border_color = SECONDARY_COLOR
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(4)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = BUTTON_DISABLED_BG
	disabled.border_color = Color(0.3, 0.4, 0.5)
	disabled.set_border_width_all(1)
	disabled.set_corner_radius_all(4)

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled
	}


## Create themed progress bar style.
static func create_progress_bar_style() -> Dictionary:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.1, 0.15, 0.8)
	background.set_corner_radius_all(2)

	var fill := StyleBoxFlat.new()
	fill.bg_color = PRIMARY_COLOR
	fill.set_corner_radius_all(2)

	return {
		"background": background,
		"fill": fill
	}


## Apply theme to panel container.
static func apply_to_panel(panel: PanelContainer) -> void:
	if panel == null:
		return

	var style := create_panel_style()
	panel.add_theme_stylebox_override("panel", style)


## Apply theme to button.
static func apply_to_button(button: Button) -> void:
	if button == null:
		return

	var styles := create_button_styles()
	button.add_theme_stylebox_override("normal", styles["normal"])
	button.add_theme_stylebox_override("hover", styles["hover"])
	button.add_theme_stylebox_override("pressed", styles["pressed"])
	button.add_theme_stylebox_override("disabled", styles["disabled"])
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", ACCENT_COLOR)
	button.add_theme_color_override("font_pressed_color", PRIMARY_COLOR)
	button.add_theme_font_size_override("font_size", FONT_SIZE_BODY)


## Apply theme to label.
static func apply_to_label(label: Label, size_type: String = "body") -> void:
	if label == null:
		return

	label.add_theme_color_override("font_color", TEXT_COLOR)

	match size_type:
		"body":
			label.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
		"label":
			label.add_theme_font_size_override("font_size", FONT_SIZE_LABEL)
		"header":
			label.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
		"title":
			label.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)


## Apply theme to progress bar.
static func apply_to_progress_bar(bar: ProgressBar) -> void:
	if bar == null:
		return

	var styles := create_progress_bar_style()
	bar.add_theme_stylebox_override("background", styles["background"])
	bar.add_theme_stylebox_override("fill", styles["fill"])


## Apply glowing effect to button (hover animation).
static func apply_glow_effect(button: Button) -> Tween:
	if button == null:
		return null

	var tween := button.create_tween()
	tween.set_loops()

	var hover_style := button.get_theme_stylebox("hover") as StyleBoxFlat
	if hover_style != null:
		var original_border := hover_style.border_color
		var glow_border := ACCENT_COLOR.lightened(0.3)

		tween.tween_method(func(t: float):
			hover_style.border_color = original_border.lerp(glow_border, t)
		, 0.0, 1.0, 0.5 / GLOW_PULSE_SPEED)

		tween.tween_method(func(t: float):
			hover_style.border_color = original_border.lerp(glow_border, t)
		, 1.0, 0.0, 0.5 / GLOW_PULSE_SPEED)

	return tween


## Apply highlight pulse to control.
static func apply_highlight_pulse(control: Control, color: Color = ACCENT_COLOR) -> Tween:
	if control == null:
		return null

	var tween := control.create_tween()
	tween.tween_property(control, "modulate", Color(1.3, 1.3, 1.3), ANIMATION_FAST)
	tween.tween_property(control, "modulate", Color.WHITE, ANIMATION_FAST)
	return tween


## Create themed header label.
static func create_header_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
	label.add_theme_color_override("font_color", PRIMARY_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Create themed body label.
static func create_body_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label


## Create themed button.
static func create_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	apply_to_button(button)
	return button


## Create themed separator.
static func create_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", BORDER_COLOR.darkened(0.3))
	return sep


## Get faction icon color for minimap/indicators.
static func get_icon_color() -> Color:
	return PRIMARY_COLOR


## Get faction glow color for effects.
static func get_glow_color() -> Color:
	return ACCENT_COLOR


## Check contrast ratio for accessibility.
static func check_contrast() -> bool:
	# Simple luminance check for text readability
	var text_lum := TEXT_COLOR.get_luminance()
	var bg_lum := BACKGROUND_COLOR.get_luminance()
	var contrast := (maxf(text_lum, bg_lum) + 0.05) / (minf(text_lum, bg_lum) + 0.05)
	return contrast >= 4.5  # WCAG AA standard


## Get theme summary for debugging.
static func get_summary() -> Dictionary:
	return {
		"faction_id": FACTION_ID,
		"faction_name": FACTION_NAME,
		"primary_color": PRIMARY_COLOR,
		"secondary_color": SECONDARY_COLOR,
		"accent_color": ACCENT_COLOR,
		"text_color": TEXT_COLOR,
		"background_color": BACKGROUND_COLOR,
		"font_size": FONT_SIZE_BODY,
		"contrast_valid": check_contrast()
	}
