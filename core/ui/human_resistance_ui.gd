class_name HumanResistanceUI
extends RefCounted
## HumanResistanceUI manages visual elements for Human Resistance faction.

signal unit_selected(unit_id: int)
signal hack_immunity_shown(unit_id: int)

## Faction color
const FACTION_COLOR := Color.DARK_GREEN
const FACTION_ID := "human_remnant"

## Unit type scales
const UNIT_SCALES := {
	"soldier": 0.8,
	"sniper": 0.7,
	"heavy_gunner": 1.0,
	"commander": 0.9
}

## Performance limits
const MAX_UNITS := 500
const HEALTH_BAR_UPDATE_RATE := 0.05  ## 20 updates per second

## UI components
var _minimap_layer: Control = null
var _unit_indicators: Dictionary = {}  ## unit_id -> Control
var _health_bars: Dictionary = {}      ## unit_id -> ProgressBar
var _buff_indicators: Dictionary = {}  ## unit_id -> Control
var _immunity_popups: Dictionary = {}  ## unit_id -> Control

## State
var _last_update_time := 0.0
var _active_units: Dictionary = {}  ## unit_id -> {position, health, type, has_buff}


func _init() -> void:
	pass


## Create UI layer for minimap.
func create_minimap_layer(minimap_container: Control) -> Control:
	_minimap_layer = Control.new()
	_minimap_layer.name = "HumanResistanceLayer"
	_minimap_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_container.add_child(_minimap_layer)
	return _minimap_layer


## Register a unit.
func register_unit(unit_id: int, unit_type: String, position: Vector2) -> void:
	if _active_units.size() >= MAX_UNITS:
		return

	_active_units[unit_id] = {
		"position": position,
		"health": 1.0,
		"type": unit_type,
		"has_buff": false
	}

	_create_unit_indicator(unit_id, unit_type)


## Unregister a unit.
func unregister_unit(unit_id: int) -> void:
	_active_units.erase(unit_id)

	# Clean up UI elements
	if _unit_indicators.has(unit_id):
		if is_instance_valid(_unit_indicators[unit_id]):
			_unit_indicators[unit_id].queue_free()
		_unit_indicators.erase(unit_id)

	if _health_bars.has(unit_id):
		if is_instance_valid(_health_bars[unit_id]):
			_health_bars[unit_id].queue_free()
		_health_bars.erase(unit_id)

	if _buff_indicators.has(unit_id):
		if is_instance_valid(_buff_indicators[unit_id]):
			_buff_indicators[unit_id].queue_free()
		_buff_indicators.erase(unit_id)


## Update unit position.
func update_unit_position(unit_id: int, minimap_position: Vector2) -> void:
	if _active_units.has(unit_id):
		_active_units[unit_id]["position"] = minimap_position

	if _unit_indicators.has(unit_id):
		_unit_indicators[unit_id].position = minimap_position


## Update unit health.
func update_unit_health(unit_id: int, health_ratio: float) -> void:
	if _active_units.has(unit_id):
		_active_units[unit_id]["health"] = health_ratio

	if _health_bars.has(unit_id):
		var bar: ProgressBar = _health_bars[unit_id]
		bar.value = health_ratio * 100.0

		# Color based on health
		var bar_fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			if health_ratio > 0.6:
				bar_fill.bg_color = FACTION_COLOR
			elif health_ratio > 0.3:
				bar_fill.bg_color = Color.YELLOW
			else:
				bar_fill.bg_color = Color.RED


## Create unit indicator on minimap.
func _create_unit_indicator(unit_id: int, unit_type: String) -> void:
	if _minimap_layer == null:
		return

	var indicator := Control.new()
	indicator.name = "Unit_%d" % unit_id
	indicator.custom_minimum_size = Vector2(6, 6)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Unit icon (simple colored rect)
	var icon := ColorRect.new()
	icon.color = FACTION_COLOR
	icon.custom_minimum_size = _get_unit_icon_size(unit_type)
	indicator.add_child(icon)

	_minimap_layer.add_child(indicator)
	_unit_indicators[unit_id] = indicator


## Get unit icon size based on type.
func _get_unit_icon_size(unit_type: String) -> Vector2:
	var scale: float = UNIT_SCALES.get(unit_type, 0.8)
	var base_size := 6.0
	return Vector2(base_size * scale, base_size * scale)


## Create health bar for unit (for world display).
func create_health_bar(parent: Control, unit_id: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = "HealthBar_%d" % unit_id
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(40, 4)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("#1f1f1f")
	bg_style.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = FACTION_COLOR
	fill_style.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("fill", fill_style)

	parent.add_child(bar)
	_health_bars[unit_id] = bar

	return bar


## Show hacking immunity popup.
func show_hack_immunity(unit_id: int, position: Vector2, parent: Control) -> void:
	if _immunity_popups.has(unit_id):
		return  # Already showing

	var popup := Label.new()
	popup.text = "IMMUNE"
	popup.add_theme_font_size_override("font_size", 14)
	popup.add_theme_color_override("font_color", Color.RED)
	popup.add_theme_color_override("font_outline_color", Color.BLACK)
	popup.add_theme_constant_override("outline_size", 2)
	popup.position = position - Vector2(25, 20)
	popup.modulate.a = 1.0

	parent.add_child(popup)
	_immunity_popups[unit_id] = popup

	# Animate and remove
	var tween := popup.create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - 30, 1.0)
	tween.parallel().tween_property(popup, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func():
		if is_instance_valid(popup):
			popup.queue_free()
		_immunity_popups.erase(unit_id)
	)

	hack_immunity_shown.emit(unit_id)


## Show commander buff indicator.
func show_buff_indicator(unit_id: int, parent: Control) -> void:
	if _buff_indicators.has(unit_id):
		return

	if _active_units.has(unit_id):
		_active_units[unit_id]["has_buff"] = true

	var indicator := ColorRect.new()
	indicator.name = "BuffIndicator_%d" % unit_id
	indicator.color = Color(0.5, 1.0, 0.5, 0.3)  # Light green glow
	indicator.custom_minimum_size = Vector2(8, 8)
	indicator.position = Vector2(-4, -4)

	parent.add_child(indicator)
	_buff_indicators[unit_id] = indicator

	# Pulse animation
	var tween := indicator.create_tween()
	tween.set_loops()
	tween.tween_property(indicator, "modulate:a", 0.5, 0.5)
	tween.tween_property(indicator, "modulate:a", 1.0, 0.5)


## Hide commander buff indicator.
func hide_buff_indicator(unit_id: int) -> void:
	if _active_units.has(unit_id):
		_active_units[unit_id]["has_buff"] = false

	if _buff_indicators.has(unit_id):
		if is_instance_valid(_buff_indicators[unit_id]):
			_buff_indicators[unit_id].queue_free()
		_buff_indicators.erase(unit_id)


## Show resource drop effect.
func show_resource_drop(position: Vector2, amount: int, parent: Control) -> void:
	var popup := Label.new()
	popup.text = "+%d REE" % amount
	popup.add_theme_font_size_override("font_size", 12)
	popup.add_theme_color_override("font_color", Color.CYAN)
	popup.add_theme_color_override("font_outline_color", Color.BLACK)
	popup.add_theme_constant_override("outline_size", 1)
	popup.position = position - Vector2(20, 10)
	popup.modulate.a = 1.0

	parent.add_child(popup)

	# Float up and fade
	var tween := popup.create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - 40, 1.5)
	tween.parallel().tween_property(popup, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.tween_callback(popup.queue_free)


## Batch update for performance.
func batch_update(delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_update_time < HEALTH_BAR_UPDATE_RATE:
		return

	_last_update_time = current_time

	# Update minimap indicators
	for unit_id in _active_units:
		var data: Dictionary = _active_units[unit_id]
		if _unit_indicators.has(unit_id):
			_unit_indicators[unit_id].position = data["position"]


## Get active unit count.
func get_unit_count() -> int:
	return _active_units.size()


## Get faction color.
func get_faction_color() -> Color:
	return FACTION_COLOR


## Clear all units.
func clear_all() -> void:
	for indicator in _unit_indicators.values():
		if is_instance_valid(indicator):
			indicator.queue_free()
	_unit_indicators.clear()

	for bar in _health_bars.values():
		if is_instance_valid(bar):
			bar.queue_free()
	_health_bars.clear()

	for indicator in _buff_indicators.values():
		if is_instance_valid(indicator):
			indicator.queue_free()
	_buff_indicators.clear()

	for popup in _immunity_popups.values():
		if is_instance_valid(popup):
			popup.queue_free()
	_immunity_popups.clear()

	_active_units.clear()


## Cleanup.
func cleanup() -> void:
	clear_all()
	if _minimap_layer != null and is_instance_valid(_minimap_layer):
		_minimap_layer.queue_free()
	_minimap_layer = null
