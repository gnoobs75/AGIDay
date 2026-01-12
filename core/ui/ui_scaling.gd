class_name UIScaling
extends RefCounted
## UIScaling handles resolution scaling and aspect ratio adjustments.
## Supports 1280x720 to 3840x2160 with proper letterboxing/pillarboxing.

signal resolution_changed(new_resolution: Vector2i)
signal scale_factor_changed(new_factor: float)

## Base resolution (reference design resolution)
const BASE_RESOLUTION := Vector2i(1920, 1080)

## Supported resolution limits
const MIN_RESOLUTION := Vector2i(1280, 720)
const MAX_RESOLUTION := Vector2i(3840, 2160)

## Supported aspect ratios
enum AspectRatio {
	RATIO_16_9,    ## Standard widescreen (1.778)
	RATIO_16_10,   ## Widescreen laptop (1.6)
	RATIO_21_9,    ## Ultrawide (2.333)
	RATIO_4_3,     ## Legacy (1.333)
	RATIO_CUSTOM   ## Non-standard
}

## Aspect ratio definitions
const ASPECT_RATIOS := {
	AspectRatio.RATIO_16_9: 16.0 / 9.0,
	AspectRatio.RATIO_16_10: 16.0 / 10.0,
	AspectRatio.RATIO_21_9: 21.0 / 9.0,
	AspectRatio.RATIO_4_3: 4.0 / 3.0
}

## Current state
var _current_resolution := BASE_RESOLUTION
var _current_aspect_ratio := AspectRatio.RATIO_16_9
var _scale_factor := 1.0
var _ui_scale_factor := 1.0  ## Additional UI-specific scaling

## Viewport offsets for letterboxing/pillarboxing
var _viewport_offset := Vector2i.ZERO
var _viewport_size := BASE_RESOLUTION

## Safe area margins (for notches, rounded corners)
var _safe_area_margin := Vector2i(0, 0)


func _init() -> void:
	pass


## Initialize with viewport.
func initialize(viewport_size: Vector2i) -> void:
	set_resolution(viewport_size)


## Set current resolution.
func set_resolution(resolution: Vector2i) -> void:
	# Clamp to supported range
	resolution.x = clampi(resolution.x, MIN_RESOLUTION.x, MAX_RESOLUTION.x)
	resolution.y = clampi(resolution.y, MIN_RESOLUTION.y, MAX_RESOLUTION.y)

	_current_resolution = resolution
	_calculate_scale_factor()
	_detect_aspect_ratio()
	_calculate_viewport_adjustments()

	resolution_changed.emit(_current_resolution)
	scale_factor_changed.emit(_scale_factor)


## Calculate scale factor relative to base resolution.
func _calculate_scale_factor() -> void:
	# Use height as primary scaling reference
	_scale_factor = float(_current_resolution.y) / float(BASE_RESOLUTION.y)

	# Clamp to reasonable range
	_scale_factor = clampf(_scale_factor, 0.5, 2.0)


## Detect aspect ratio from resolution.
func _detect_aspect_ratio() -> void:
	var ratio := float(_current_resolution.x) / float(_current_resolution.y)

	# Find closest matching aspect ratio
	var closest := AspectRatio.RATIO_CUSTOM
	var min_diff := 999.0

	for ar_enum in ASPECT_RATIOS:
		var ar_value: float = ASPECT_RATIOS[ar_enum]
		var diff := absf(ratio - ar_value)
		if diff < min_diff and diff < 0.1:  ## Tolerance of 0.1
			min_diff = diff
			closest = ar_enum

	_current_aspect_ratio = closest


## Calculate viewport adjustments for non-16:9 ratios.
func _calculate_viewport_adjustments() -> void:
	var target_ratio := ASPECT_RATIOS[AspectRatio.RATIO_16_9]
	var current_ratio := float(_current_resolution.x) / float(_current_resolution.y)

	_viewport_offset = Vector2i.ZERO
	_viewport_size = _current_resolution

	if _current_aspect_ratio == AspectRatio.RATIO_21_9:
		# Ultrawide - add pillarboxing (black bars on sides)
		var target_width := int(float(_current_resolution.y) * target_ratio)
		var offset_x := (_current_resolution.x - target_width) / 2
		_viewport_offset.x = offset_x
		_viewport_size.x = target_width

	elif _current_aspect_ratio == AspectRatio.RATIO_4_3:
		# Legacy 4:3 - add letterboxing (black bars top/bottom)
		var target_height := int(float(_current_resolution.x) / target_ratio)
		var offset_y := (_current_resolution.y - target_height) / 2
		_viewport_offset.y = offset_y
		_viewport_size.y = target_height


## Set UI-specific scale factor (user preference).
func set_ui_scale(scale: float) -> void:
	_ui_scale_factor = clampf(scale, 0.8, 1.5)
	scale_factor_changed.emit(get_combined_scale_factor())


## Get combined scale factor (resolution + UI preference).
func get_combined_scale_factor() -> float:
	return _scale_factor * _ui_scale_factor


## Get current scale factor.
func get_scale_factor() -> float:
	return _scale_factor


## Get UI scale factor.
func get_ui_scale_factor() -> float:
	return _ui_scale_factor


## Scale a value from base resolution.
func scale_value(base_value: float) -> float:
	return base_value * get_combined_scale_factor()


## Scale a vector from base resolution.
func scale_vector(base_vector: Vector2) -> Vector2:
	var factor := get_combined_scale_factor()
	return base_vector * factor


## Scale a size from base resolution.
func scale_size(base_size: Vector2i) -> Vector2i:
	var factor := get_combined_scale_factor()
	return Vector2i(int(base_size.x * factor), int(base_size.y * factor))


## Get current resolution.
func get_current_resolution() -> Vector2i:
	return _current_resolution


## Get current aspect ratio.
func get_aspect_ratio() -> AspectRatio:
	return _current_aspect_ratio


## Get aspect ratio name.
func get_aspect_ratio_name() -> String:
	match _current_aspect_ratio:
		AspectRatio.RATIO_16_9: return "16:9"
		AspectRatio.RATIO_16_10: return "16:10"
		AspectRatio.RATIO_21_9: return "21:9"
		AspectRatio.RATIO_4_3: return "4:3"
		_: return "Custom"


## Get viewport offset (for letterboxing/pillarboxing).
func get_viewport_offset() -> Vector2i:
	return _viewport_offset


## Get effective viewport size.
func get_viewport_size() -> Vector2i:
	return _viewport_size


## Check if using letterboxing/pillarboxing.
func is_using_boxing() -> bool:
	return _viewport_offset != Vector2i.ZERO


## Convert screen position to UI position (accounting for boxing).
func screen_to_ui_position(screen_pos: Vector2) -> Vector2:
	return screen_pos - Vector2(_viewport_offset)


## Convert UI position to screen position.
func ui_to_screen_position(ui_pos: Vector2) -> Vector2:
	return ui_pos + Vector2(_viewport_offset)


## Check if position is within UI area (not in letterbox/pillarbox).
func is_in_ui_area(screen_pos: Vector2) -> bool:
	var ui_pos := screen_to_ui_position(screen_pos)
	return ui_pos.x >= 0 and ui_pos.y >= 0 and \
		   ui_pos.x < _viewport_size.x and ui_pos.y < _viewport_size.y


## Set safe area margins (for mobile/notched displays).
func set_safe_area_margin(margin: Vector2i) -> void:
	_safe_area_margin = margin


## Get safe area margins.
func get_safe_area_margin() -> Vector2i:
	return _safe_area_margin


## Get safe area rect.
func get_safe_area_rect() -> Rect2i:
	return Rect2i(
		_viewport_offset + _safe_area_margin,
		_viewport_size - _safe_area_margin * 2
	)


## Apply scaling to a Control node.
func apply_to_control(control: Control) -> void:
	var factor := get_combined_scale_factor()

	# Scale custom minimum size
	if control.custom_minimum_size != Vector2.ZERO:
		control.custom_minimum_size *= factor

	# Scale margins if anchored
	control.offset_left *= factor
	control.offset_right *= factor
	control.offset_top *= factor
	control.offset_bottom *= factor


## Create scaling configuration for container.
func create_container_config() -> Dictionary:
	return {
		"scale_factor": get_combined_scale_factor(),
		"viewport_offset": _viewport_offset,
		"viewport_size": _viewport_size,
		"safe_area": get_safe_area_rect(),
		"aspect_ratio": _current_aspect_ratio
	}


## Get recommended minimum touch target size (for accessibility).
func get_min_touch_target_size() -> Vector2:
	# 44px is iOS minimum, scaled for resolution
	return scale_vector(Vector2(44, 44))


## Get recommended spacing.
func get_spacing(size: String = "normal") -> float:
	var base_spacing := 8.0
	match size:
		"small": base_spacing = 4.0
		"normal": base_spacing = 8.0
		"large": base_spacing = 16.0
		"xlarge": base_spacing = 24.0

	return scale_value(base_spacing)


## Get recommended margin.
func get_margin(size: String = "normal") -> float:
	var base_margin := 16.0
	match size:
		"small": base_margin = 8.0
		"normal": base_margin = 16.0
		"large": base_margin = 24.0
		"xlarge": base_margin = 32.0

	return scale_value(base_margin)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"resolution": [_current_resolution.x, _current_resolution.y],
		"ui_scale_factor": _ui_scale_factor,
		"safe_area_margin": [_safe_area_margin.x, _safe_area_margin.y]
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	if data.has("resolution"):
		var res: Array = data["resolution"]
		set_resolution(Vector2i(res[0], res[1]))

	if data.has("ui_scale_factor"):
		set_ui_scale(data["ui_scale_factor"])

	if data.has("safe_area_margin"):
		var margin: Array = data["safe_area_margin"]
		set_safe_area_margin(Vector2i(margin[0], margin[1]))


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"current_resolution": "%dx%d" % [_current_resolution.x, _current_resolution.y],
		"base_resolution": "%dx%d" % [BASE_RESOLUTION.x, BASE_RESOLUTION.y],
		"aspect_ratio": get_aspect_ratio_name(),
		"scale_factor": _scale_factor,
		"ui_scale_factor": _ui_scale_factor,
		"combined_scale": get_combined_scale_factor(),
		"using_boxing": is_using_boxing(),
		"viewport_offset": _viewport_offset,
		"viewport_size": _viewport_size
	}
