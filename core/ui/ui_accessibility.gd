class_name UIAccessibility
extends RefCounted
## UIAccessibility provides colorblind support, high-contrast mode, and text scaling.
## Ensures UI remains readable and functional across all accessibility settings.

signal colorblind_mode_changed(mode: ColorblindMode)
signal high_contrast_changed(enabled: bool)
signal text_scale_changed(scale: float)
signal accessibility_updated()

## Colorblind simulation modes
enum ColorblindMode {
	NONE,           ## No simulation
	DEUTERANOPIA,   ## Red-green (most common, ~6% males)
	PROTANOPIA,     ## Red-green (less common, ~2% males)
	TRITANOPIA,     ## Blue-yellow (rare, ~0.01%)
	MONOCHROMACY    ## Complete colorblindness (very rare)
}

## Text scale range
const MIN_TEXT_SCALE := 0.8
const MAX_TEXT_SCALE := 1.5
const TEXT_SCALE_STEP := 0.1

## High contrast settings
const HIGH_CONTRAST_BORDER_WIDTH := 3
const HIGH_CONTRAST_MIN_FONT_SIZE := 14

## Colorblind-safe palette (works for all modes)
const SAFE_COLORS := {
	"positive": Color("#2ecc71"),      ## Green (safe)
	"negative": Color("#e74c3c"),      ## Red (warning)
	"neutral": Color("#3498db"),       ## Blue (info)
	"warning": Color("#f39c12"),       ## Orange/yellow
	"critical": Color("#9b59b6")       ## Purple
}

## Alternative patterns/shapes for colorblind users
const PATTERN_ICONS := {
	"positive": "check",
	"negative": "x",
	"neutral": "circle",
	"warning": "triangle",
	"critical": "diamond"
}

## Colorblind color transformations (LMS daltonization matrices approximation)
## Simplified for real-time use
const COLORBLIND_TRANSFORMS := {
	ColorblindMode.DEUTERANOPIA: {
		"red_shift": Vector3(0.625, 0.375, 0.0),
		"green_shift": Vector3(0.7, 0.3, 0.0),
		"blue_shift": Vector3(0.0, 0.3, 0.7)
	},
	ColorblindMode.PROTANOPIA: {
		"red_shift": Vector3(0.567, 0.433, 0.0),
		"green_shift": Vector3(0.558, 0.442, 0.0),
		"blue_shift": Vector3(0.0, 0.242, 0.758)
	},
	ColorblindMode.TRITANOPIA: {
		"red_shift": Vector3(0.95, 0.05, 0.0),
		"green_shift": Vector3(0.0, 0.433, 0.567),
		"blue_shift": Vector3(0.0, 0.475, 0.525)
	}
}

## Current settings
var _colorblind_mode := ColorblindMode.NONE
var _high_contrast_enabled := false
var _text_scale := 1.0
var _reduce_motion := false
var _screen_reader_mode := false

## Cached transformed colors
var _color_cache: Dictionary = {}


func _init() -> void:
	pass


## Set colorblind mode.
func set_colorblind_mode(mode: ColorblindMode) -> void:
	if _colorblind_mode != mode:
		_colorblind_mode = mode
		_color_cache.clear()
		colorblind_mode_changed.emit(mode)
		accessibility_updated.emit()


## Get colorblind mode.
func get_colorblind_mode() -> ColorblindMode:
	return _colorblind_mode


## Get colorblind mode name.
func get_colorblind_mode_name() -> String:
	match _colorblind_mode:
		ColorblindMode.NONE: return "None"
		ColorblindMode.DEUTERANOPIA: return "Deuteranopia"
		ColorblindMode.PROTANOPIA: return "Protanopia"
		ColorblindMode.TRITANOPIA: return "Tritanopia"
		ColorblindMode.MONOCHROMACY: return "Monochromacy"
		_: return "Unknown"


## Transform color for current colorblind mode.
func transform_color(color: Color) -> Color:
	if _colorblind_mode == ColorblindMode.NONE:
		return color

	# Check cache
	var cache_key := "%s_%d" % [color.to_html(), _colorblind_mode]
	if _color_cache.has(cache_key):
		return _color_cache[cache_key]

	var transformed: Color

	if _colorblind_mode == ColorblindMode.MONOCHROMACY:
		# Convert to grayscale using luminance
		var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
		transformed = Color(luminance, luminance, luminance, color.a)
	else:
		# Apply daltonization transform
		var transform: Dictionary = COLORBLIND_TRANSFORMS.get(_colorblind_mode, {})
		if transform.is_empty():
			transformed = color
		else:
			var r: Vector3 = transform["red_shift"]
			var g: Vector3 = transform["green_shift"]
			var b: Vector3 = transform["blue_shift"]

			transformed = Color(
				color.r * r.x + color.g * r.y + color.b * r.z,
				color.r * g.x + color.g * g.y + color.b * g.z,
				color.r * b.x + color.g * b.y + color.b * b.z,
				color.a
			)

	# Cache result
	_color_cache[cache_key] = transformed
	return transformed


## Get accessible color (either transformed or safe alternative).
func get_accessible_color(semantic_type: String, original_color: Color = Color.WHITE) -> Color:
	# If we have a safe color for this type, prefer it in colorblind modes
	if _colorblind_mode != ColorblindMode.NONE and SAFE_COLORS.has(semantic_type):
		return transform_color(SAFE_COLORS[semantic_type])

	return transform_color(original_color)


## Set high contrast mode.
func set_high_contrast(enabled: bool) -> void:
	if _high_contrast_enabled != enabled:
		_high_contrast_enabled = enabled
		high_contrast_changed.emit(enabled)
		accessibility_updated.emit()


## Get high contrast mode.
func is_high_contrast() -> bool:
	return _high_contrast_enabled


## Set text scale.
func set_text_scale(scale: float) -> void:
	scale = clampf(scale, MIN_TEXT_SCALE, MAX_TEXT_SCALE)
	if not is_equal_approx(_text_scale, scale):
		_text_scale = scale
		text_scale_changed.emit(scale)
		accessibility_updated.emit()


## Get text scale.
func get_text_scale() -> float:
	return _text_scale


## Increase text scale.
func increase_text_scale() -> void:
	set_text_scale(_text_scale + TEXT_SCALE_STEP)


## Decrease text scale.
func decrease_text_scale() -> void:
	set_text_scale(_text_scale - TEXT_SCALE_STEP)


## Get scaled font size.
func get_scaled_font_size(base_size: int) -> int:
	var scaled := int(float(base_size) * _text_scale)
	if _high_contrast_enabled:
		scaled = maxi(scaled, HIGH_CONTRAST_MIN_FONT_SIZE)
	return scaled


## Set reduce motion preference.
func set_reduce_motion(enabled: bool) -> void:
	_reduce_motion = enabled
	accessibility_updated.emit()


## Get reduce motion preference.
func is_reduce_motion() -> bool:
	return _reduce_motion


## Set screen reader mode.
func set_screen_reader_mode(enabled: bool) -> void:
	_screen_reader_mode = enabled
	accessibility_updated.emit()


## Get screen reader mode.
func is_screen_reader_mode() -> bool:
	return _screen_reader_mode


## Get accessible border width.
func get_border_width() -> int:
	return HIGH_CONTRAST_BORDER_WIDTH if _high_contrast_enabled else 1


## Apply accessibility to a StyleBoxFlat.
func apply_to_stylebox(stylebox: StyleBoxFlat, accent_color: Color) -> void:
	if _high_contrast_enabled:
		# Thicker borders
		stylebox.set_border_width_all(HIGH_CONTRAST_BORDER_WIDTH)

		# Higher contrast border color
		stylebox.border_color = accent_color.lightened(0.3)

		# Solid background (no transparency)
		stylebox.bg_color.a = 1.0
	else:
		stylebox.set_border_width_all(1)

	# Apply colorblind transform
	stylebox.border_color = transform_color(stylebox.border_color)
	stylebox.bg_color = transform_color(stylebox.bg_color)


## Apply accessibility to a Label.
func apply_to_label(label: Label) -> void:
	# Scale font size
	var current_size := label.get_theme_font_size("font_size")
	label.add_theme_font_size_override("font_size", get_scaled_font_size(current_size))

	# Transform color
	var current_color := label.get_theme_color("font_color")
	label.add_theme_color_override("font_color", transform_color(current_color))

	if _high_contrast_enabled:
		# Ensure high contrast text
		label.add_theme_color_override("font_color", Color.WHITE)


## Apply accessibility to a Button.
func apply_to_button(button: Button) -> void:
	# Scale font size
	var current_size := button.get_theme_font_size("font_size")
	button.add_theme_font_size_override("font_size", get_scaled_font_size(current_size))

	if _high_contrast_enabled:
		# Increase minimum size for easier clicking
		var min_size := button.custom_minimum_size
		button.custom_minimum_size = Vector2(
			maxf(min_size.x, 100.0),
			maxf(min_size.y, 44.0)
		)


## Get pattern/icon for semantic meaning (supplements color).
func get_semantic_pattern(semantic_type: String) -> String:
	if _colorblind_mode != ColorblindMode.NONE:
		return PATTERN_ICONS.get(semantic_type, "circle")
	return ""


## Check if patterns should be shown (in addition to color).
func should_show_patterns() -> bool:
	return _colorblind_mode != ColorblindMode.NONE


## Get animation duration (respects reduce motion).
func get_animation_duration(base_duration: float) -> float:
	if _reduce_motion:
		return 0.0
	return base_duration


## Get tween transition (respects reduce motion).
func get_tween_transition() -> Tween.TransitionType:
	if _reduce_motion:
		return Tween.TRANS_LINEAR
	return Tween.TRANS_CUBIC


## Create accessible description for screen readers.
func create_aria_description(element_type: String, label: String, state: String = "") -> String:
	if not _screen_reader_mode:
		return ""

	var desc := "%s: %s" % [element_type, label]
	if not state.is_empty():
		desc += " (%s)" % state
	return desc


## Get available colorblind modes.
static func get_colorblind_modes() -> Array[Dictionary]:
	return [
		{"mode": ColorblindMode.NONE, "name": "None", "description": "No color adjustment"},
		{"mode": ColorblindMode.DEUTERANOPIA, "name": "Deuteranopia", "description": "Red-green colorblindness (common)"},
		{"mode": ColorblindMode.PROTANOPIA, "name": "Protanopia", "description": "Red-green colorblindness"},
		{"mode": ColorblindMode.TRITANOPIA, "name": "Tritanopia", "description": "Blue-yellow colorblindness"},
		{"mode": ColorblindMode.MONOCHROMACY, "name": "Monochromacy", "description": "Complete colorblindness"}
	]


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"colorblind_mode": _colorblind_mode,
		"high_contrast": _high_contrast_enabled,
		"text_scale": _text_scale,
		"reduce_motion": _reduce_motion,
		"screen_reader": _screen_reader_mode
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	if data.has("colorblind_mode"):
		set_colorblind_mode(data["colorblind_mode"] as ColorblindMode)

	if data.has("high_contrast"):
		set_high_contrast(data["high_contrast"])

	if data.has("text_scale"):
		set_text_scale(data["text_scale"])

	if data.has("reduce_motion"):
		set_reduce_motion(data["reduce_motion"])

	if data.has("screen_reader"):
		set_screen_reader_mode(data["screen_reader"])


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"colorblind_mode": get_colorblind_mode_name(),
		"high_contrast": _high_contrast_enabled,
		"text_scale": _text_scale,
		"reduce_motion": _reduce_motion,
		"screen_reader": _screen_reader_mode,
		"cached_colors": _color_cache.size()
	}
