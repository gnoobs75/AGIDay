class_name BuffIndicator
extends RefCounted
## BuffIndicator displays visual feedback for active buffs on units.

signal buff_expired(buff_type: String)

## Buff types
enum BuffType {
	COMMANDER_AURA,     ## Commander damage buff
	SHIELD_BOOST,       ## Shield enhancement
	SPEED_BOOST,        ## Movement speed increase
	DAMAGE_BOOST,       ## Damage increase
	HEALING,            ## Active healing
	HACKING_IMMUNITY    ## Immune to hacking
}

## Buff colors
const BUFF_COLORS := {
	BuffType.COMMANDER_AURA: Color(0.5, 1.0, 0.5, 0.6),    # Light green
	BuffType.SHIELD_BOOST: Color(0.5, 0.5, 1.0, 0.6),      # Light blue
	BuffType.SPEED_BOOST: Color(1.0, 1.0, 0.5, 0.6),       # Light yellow
	BuffType.DAMAGE_BOOST: Color(1.0, 0.5, 0.5, 0.6),      # Light red
	BuffType.HEALING: Color(0.5, 1.0, 0.5, 0.8),           # Green
	BuffType.HACKING_IMMUNITY: Color(1.0, 0.0, 0.0, 0.5)   # Red
}

## Buff icons (text-based for simplicity)
const BUFF_ICONS := {
	BuffType.COMMANDER_AURA: "[C]",
	BuffType.SHIELD_BOOST: "[S]",
	BuffType.SPEED_BOOST: "[>]",
	BuffType.DAMAGE_BOOST: "[!]",
	BuffType.HEALING: "[+]",
	BuffType.HACKING_IMMUNITY: "[X]"
}

## Visual settings
const INDICATOR_SIZE := Vector2(16, 16)
const PULSE_SPEED := 2.0
const GLOW_RADIUS := 24.0

## Active buffs
var _active_buffs: Dictionary = {}  ## buff_type -> {duration, max_duration, tween}

## UI components
var _container: Control = null
var _glow_ring: Control = null
var _icon_container: HBoxContainer = null
var _buff_icons: Dictionary = {}  ## buff_type -> Label
var _duration_bar: ProgressBar = null

## Parent position tracking
var _world_position := Vector3.ZERO
var _screen_position := Vector2.ZERO


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control) -> Control:
	# Main container
	_container = Control.new()
	_container.name = "BuffIndicator"
	_container.custom_minimum_size = Vector2(GLOW_RADIUS * 2, GLOW_RADIUS * 2)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Glow ring (custom draw)
	_glow_ring = Control.new()
	_glow_ring.name = "GlowRing"
	_glow_ring.set_anchors_preset(Control.PRESET_CENTER)
	_glow_ring.custom_minimum_size = Vector2(GLOW_RADIUS * 2, GLOW_RADIUS * 2)
	_glow_ring.position = -_glow_ring.custom_minimum_size / 2
	_glow_ring.draw.connect(_draw_glow_ring)
	_glow_ring.visible = false
	_container.add_child(_glow_ring)

	# Icon container (above unit)
	_icon_container = HBoxContainer.new()
	_icon_container.name = "IconContainer"
	_icon_container.add_theme_constant_override("separation", 2)
	_icon_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_icon_container.position = Vector2(-INDICATOR_SIZE.x, -INDICATOR_SIZE.y - 8)
	_container.add_child(_icon_container)

	# Duration bar (optional, shown for timed buffs)
	_duration_bar = ProgressBar.new()
	_duration_bar.name = "DurationBar"
	_duration_bar.min_value = 0.0
	_duration_bar.max_value = 100.0
	_duration_bar.value = 100.0
	_duration_bar.show_percentage = false
	_duration_bar.custom_minimum_size = Vector2(32, 3)
	_duration_bar.position = Vector2(-16, -INDICATOR_SIZE.y - 4)
	_duration_bar.visible = false

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f", 0.7)
	bar_bg.set_corner_radius_all(1)
	_duration_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.GREEN
	bar_fill.set_corner_radius_all(1)
	_duration_bar.add_theme_stylebox_override("fill", bar_fill)

	_container.add_child(_duration_bar)

	parent.add_child(_container)
	return _container


## Add a buff.
func add_buff(buff_type: BuffType, duration: float = -1.0) -> void:
	if _active_buffs.has(buff_type):
		# Refresh duration
		_active_buffs[buff_type]["duration"] = duration
		_active_buffs[buff_type]["max_duration"] = duration
		return

	_active_buffs[buff_type] = {
		"duration": duration,
		"max_duration": duration,
		"tween": null
	}

	# Create icon
	_create_buff_icon(buff_type)

	# Show glow if commander aura
	if buff_type == BuffType.COMMANDER_AURA:
		_glow_ring.visible = true
		_start_glow_pulse()

	_update_display()


## Remove a buff.
func remove_buff(buff_type: BuffType) -> void:
	if not _active_buffs.has(buff_type):
		return

	# Stop tween if exists
	var data: Dictionary = _active_buffs[buff_type]
	if data["tween"] != null and data["tween"].is_valid():
		data["tween"].kill()

	_active_buffs.erase(buff_type)

	# Remove icon
	if _buff_icons.has(buff_type):
		if is_instance_valid(_buff_icons[buff_type]):
			_buff_icons[buff_type].queue_free()
		_buff_icons.erase(buff_type)

	# Hide glow if no commander aura
	if buff_type == BuffType.COMMANDER_AURA:
		_glow_ring.visible = false

	_update_display()
	buff_expired.emit(_buff_type_to_string(buff_type))


## Create buff icon.
func _create_buff_icon(buff_type: BuffType) -> void:
	var icon := Label.new()
	icon.text = BUFF_ICONS.get(buff_type, "[?]")
	icon.add_theme_font_size_override("font_size", 10)
	icon.add_theme_color_override("font_color", BUFF_COLORS.get(buff_type, Color.WHITE))
	icon.add_theme_color_override("font_outline_color", Color.BLACK)
	icon.add_theme_constant_override("outline_size", 1)

	_icon_container.add_child(icon)
	_buff_icons[buff_type] = icon


## Draw glow ring.
func _draw_glow_ring() -> void:
	if _glow_ring == null:
		return

	var center := _glow_ring.size / 2

	# Get active glow color
	var glow_color := Color(0.5, 1.0, 0.5, 0.3)  # Default commander aura
	for buff_type in _active_buffs:
		if BUFF_COLORS.has(buff_type):
			glow_color = BUFF_COLORS[buff_type]
			break

	# Draw multiple rings for glow effect
	for i in range(3):
		var radius := GLOW_RADIUS - i * 4
		var alpha := glow_color.a * (1.0 - float(i) / 3.0)
		var ring_color := Color(glow_color, alpha)
		_glow_ring.draw_arc(center, radius, 0, TAU, 32, ring_color, 2.0)


## Start glow pulse animation.
func _start_glow_pulse() -> void:
	if _glow_ring == null:
		return

	var tween := _glow_ring.create_tween()
	tween.set_loops()
	tween.tween_property(_glow_ring, "modulate:a", 0.5, 0.5 / PULSE_SPEED)
	tween.tween_property(_glow_ring, "modulate:a", 1.0, 0.5 / PULSE_SPEED)


## Update per frame (for duration tracking).
func update(delta: float) -> void:
	var expired: Array[BuffType] = []

	for buff_type in _active_buffs:
		var data: Dictionary = _active_buffs[buff_type]
		if data["duration"] > 0:
			data["duration"] -= delta
			if data["duration"] <= 0:
				expired.append(buff_type)

	# Remove expired buffs
	for buff_type in expired:
		remove_buff(buff_type)

	_update_duration_bar()


## Update display.
func _update_display() -> void:
	# Reposition icons
	if _icon_container != null:
		var total_width := _icon_container.size.x
		_icon_container.position.x = -total_width / 2

	_glow_ring.queue_redraw()


## Update duration bar.
func _update_duration_bar() -> void:
	if _duration_bar == null:
		return

	# Find shortest timed buff
	var shortest_duration := -1.0
	var shortest_max := 1.0

	for buff_type in _active_buffs:
		var data: Dictionary = _active_buffs[buff_type]
		if data["max_duration"] > 0:
			if shortest_duration < 0 or data["duration"] < shortest_duration:
				shortest_duration = data["duration"]
				shortest_max = data["max_duration"]

	if shortest_duration >= 0:
		_duration_bar.visible = true
		_duration_bar.value = (shortest_duration / shortest_max) * 100.0
	else:
		_duration_bar.visible = false


## Set screen position.
func set_screen_position(position: Vector2) -> void:
	_screen_position = position
	if _container != null:
		_container.position = position


## Has buff.
func has_buff(buff_type: BuffType) -> bool:
	return _active_buffs.has(buff_type)


## Get active buffs.
func get_active_buffs() -> Array[BuffType]:
	var result: Array[BuffType] = []
	for buff_type in _active_buffs:
		result.append(buff_type)
	return result


## Clear all buffs.
func clear_all() -> void:
	var types: Array[BuffType] = []
	for buff_type in _active_buffs:
		types.append(buff_type)

	for buff_type in types:
		remove_buff(buff_type)


## Convert buff type to string.
func _buff_type_to_string(buff_type: BuffType) -> String:
	match buff_type:
		BuffType.COMMANDER_AURA: return "commander_aura"
		BuffType.SHIELD_BOOST: return "shield_boost"
		BuffType.SPEED_BOOST: return "speed_boost"
		BuffType.DAMAGE_BOOST: return "damage_boost"
		BuffType.HEALING: return "healing"
		BuffType.HACKING_IMMUNITY: return "hacking_immunity"
		_: return "unknown"


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	clear_all()
	_buff_icons.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
