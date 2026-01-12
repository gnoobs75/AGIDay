class_name DynapodsVanguardTheme
extends RefCounted
## DynapodsVanguardTheme provides faction-specific UI styling for Dynapods Vanguard.

## Faction identification
const FACTION_ID := "dynapods_vanguard"
const FACTION_NAME := "Dynapods Vanguard"

## Color palette - Metallic gray/silver sleek aesthetic
const PRIMARY_COLOR := Color("#C0C0C0")  # Light gray/silver
const SECONDARY_COLOR := Color.GRAY
const ACCENT_COLOR := Color.WHITE
const TEXT_COLOR := Color.WHITE
const BACKGROUND_COLOR := Color(0.2, 0.2, 0.25, 0.8)  # Semi-transparent dark gray
const BORDER_COLOR := Color("#C0C0C0")  # Silver
const HOVER_COLOR := Color("#E0E0E0")  # Lighter silver

## Button states - Sleek modern styling
const BUTTON_NORMAL_BG := Color(0.25, 0.25, 0.3, 0.9)
const BUTTON_HOVER_BG := Color(0.35, 0.35, 0.4, 0.95)
const BUTTON_PRESSED_BG := Color(0.2, 0.2, 0.25, 1.0)
const BUTTON_DISABLED_BG := Color(0.2, 0.2, 0.2, 0.6)

## Typography
const FONT_FAMILY := "JetBrains Mono"
const FONT_SIZE_BODY := 12
const FONT_SIZE_LABEL := 10
const FONT_SIZE_HEADER := 16
const FONT_SIZE_TITLE := 24

## Animation timing - Fast, agile animations
const ANIMATION_FAST := 0.08
const ANIMATION_NORMAL := 0.15
const GLOW_PULSE_SPEED := 3.0  # Fast pulse for agile faction

## Border styling - Sleek, thin borders
const BORDER_WIDTH_NORMAL := 1
const BORDER_WIDTH_HOVER := 2
const CORNER_RADIUS := 6  # Rounded for sleek look


## Create themed panel style.
static func create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.set_content_margin_all(12)
	return style


## Create themed button styles - Sleek modern look.
static func create_button_styles() -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON_NORMAL_BG
	normal.border_color = PRIMARY_COLOR
	normal.set_border_width_all(BORDER_WIDTH_NORMAL)
	normal.set_corner_radius_all(CORNER_RADIUS)

	var hover := StyleBoxFlat.new()
	hover.bg_color = BUTTON_HOVER_BG
	hover.border_color = ACCENT_COLOR
	hover.set_border_width_all(BORDER_WIDTH_HOVER)
	hover.set_corner_radius_all(CORNER_RADIUS)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = BUTTON_PRESSED_BG
	pressed.border_color = SECONDARY_COLOR
	pressed.set_border_width_all(BORDER_WIDTH_NORMAL)
	pressed.set_corner_radius_all(CORNER_RADIUS)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = BUTTON_DISABLED_BG
	disabled.border_color = Color(0.4, 0.4, 0.4)
	disabled.set_border_width_all(1)
	disabled.set_corner_radius_all(CORNER_RADIUS)

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled
	}


## Create themed progress bar style.
static func create_progress_bar_style() -> Dictionary:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.15, 0.15, 0.18, 0.8)
	background.set_corner_radius_all(3)

	var fill := StyleBoxFlat.new()
	fill.bg_color = PRIMARY_COLOR
	fill.set_corner_radius_all(3)

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
			label.add_theme_color_override("font_color", PRIMARY_COLOR)
		"title":
			label.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
			label.add_theme_color_override("font_color", PRIMARY_COLOR)


## Apply theme to progress bar.
static func apply_to_progress_bar(bar: ProgressBar) -> void:
	if bar == null:
		return

	var styles := create_progress_bar_style()
	bar.add_theme_stylebox_override("background", styles["background"])
	bar.add_theme_stylebox_override("fill", styles["fill"])


## Apply fast sleek animation to button.
static func apply_sleek_animation(button: Button) -> Tween:
	if button == null:
		return null

	var tween := button.create_tween()
	tween.set_loops()

	var hover_style := button.get_theme_stylebox("hover") as StyleBoxFlat
	if hover_style != null:
		var original_border := hover_style.border_color
		var glow_border := ACCENT_COLOR

		# Fast, responsive pulse
		tween.tween_method(func(t: float):
			hover_style.border_color = original_border.lerp(glow_border, t)
		, 0.0, 1.0, 0.33 / GLOW_PULSE_SPEED)

		tween.tween_method(func(t: float):
			hover_style.border_color = original_border.lerp(glow_border, t)
		, 1.0, 0.0, 0.33 / GLOW_PULSE_SPEED)

	return tween


## Apply quick highlight effect.
static func apply_quick_highlight(control: Control) -> Tween:
	if control == null:
		return null

	var tween := control.create_tween()
	# Fast, snappy animation matching agile faction
	tween.tween_property(control, "modulate", Color(1.4, 1.4, 1.4), ANIMATION_FAST)
	tween.tween_property(control, "modulate", Color.WHITE, ANIMATION_FAST)
	return tween


## Apply dash effect for agile actions.
static func apply_dash_effect(control: Control, direction: Vector2 = Vector2.RIGHT) -> Tween:
	if control == null:
		return null

	var original_pos := control.position
	var offset := direction.normalized() * 10

	var tween := control.create_tween()
	tween.tween_property(control, "position", original_pos + offset, ANIMATION_FAST)
	tween.tween_property(control, "position", original_pos, ANIMATION_NORMAL)
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


## Create unit selection highlight style.
static func create_selection_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PRIMARY_COLOR, 0.15)
	style.border_color = PRIMARY_COLOR
	style.set_border_width_all(BORDER_WIDTH_HOVER)
	style.set_corner_radius_all(CORNER_RADIUS)
	return style


## Get faction icon color for minimap/indicators.
static func get_icon_color() -> Color:
	return PRIMARY_COLOR


## Get faction glow color for effects.
static func get_glow_color() -> Color:
	return ACCENT_COLOR


## Check contrast ratio for accessibility.
static func check_contrast() -> bool:
	var text_lum := TEXT_COLOR.get_luminance()
	var bg_lum := BACKGROUND_COLOR.get_luminance()
	var contrast := (maxf(text_lum, bg_lum) + 0.05) / (minf(text_lum, bg_lum) + 0.05)
	return contrast >= 4.5


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
		"animation_speed": "fast",
		"style": "sleek_metallic",
		"contrast_valid": check_contrast()
	}
