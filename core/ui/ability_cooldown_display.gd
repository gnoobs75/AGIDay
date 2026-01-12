class_name AbilityCooldownDisplay
extends RefCounted
## AbilityCooldownDisplay shows real-time cooldown timers for faction abilities.

signal ability_clicked(slot_index: int, hotkey: String)
signal ability_ready(slot_index: int, hotkey: String)
signal ability_used(slot_index: int, hotkey: String)

## Default hotkeys by slot
const DEFAULT_HOTKEYS := ["Q", "W", "E", "R"]
const MAX_SLOTS := 4

## Visual sizing
const SLOT_SIZE := Vector2(64, 72)
const ICON_SIZE := Vector2(48, 48)
const SLOT_SPACING := 8
const PROGRESS_HEIGHT := 6

## State for each slot
## {icon, name, cooldown, max_cooldown, ready, hotkey}
var _slots: Array[Dictionary] = []

## UI components
var _container: HBoxContainer = null
var _slot_containers: Array[Control] = []
var _icon_rects: Array[TextureRect] = []
var _cooldown_overlays: Array[ColorRect] = []
var _progress_bars: Array[ProgressBar] = []
var _timer_labels: Array[Label] = []
var _hotkey_labels: Array[Label] = []

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	# Initialize default slots
	for i in MAX_SLOTS:
		_slots.append({
			"icon": null,
			"name": "",
			"cooldown": 0.0,
			"max_cooldown": 0.0,
			"ready": true,
			"hotkey": DEFAULT_HOTKEYS[i] if i < DEFAULT_HOTKEYS.size() else ""
		})


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = HBoxContainer.new()
	_container.name = "AbilityCooldownDisplay"
	_container.add_theme_constant_override("separation", SLOT_SPACING)
	_container.alignment = BoxContainer.ALIGNMENT_CENTER

	# Create slots
	for i in MAX_SLOTS:
		var slot := _create_slot(i)
		_slot_containers.append(slot)
		_container.add_child(slot)

	parent.add_child(_container)
	return _container


## Create a single ability slot.
func _create_slot(index: int) -> Control:
	var container := Control.new()
	container.name = "AbilitySlot_%d" % index
	container.custom_minimum_size = SLOT_SIZE

	# Background panel
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("#2d2d2d", 0.9)
	bg_style.border_color = _faction_color.darkened(0.3)
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(4)
	bg.add_theme_stylebox_override("panel", bg_style)
	container.add_child(bg)

	# Icon area
	var icon_container := Control.new()
	icon_container.custom_minimum_size = ICON_SIZE
	icon_container.position = Vector2((SLOT_SIZE.x - ICON_SIZE.x) / 2, 4)
	container.add_child(icon_container)

	# Icon texture
	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color.WHITE
	icon_container.add_child(icon)
	_icon_rects.append(icon)

	# Hotkey label (top-left corner of icon)
	var hotkey_label := Label.new()
	hotkey_label.text = _slots[index]["hotkey"]
	hotkey_label.position = Vector2(2, 2)
	hotkey_label.add_theme_font_size_override("font_size", 12)
	hotkey_label.add_theme_color_override("font_color", Color.WHITE)
	hotkey_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hotkey_label.add_theme_constant_override("outline_size", 2)
	icon_container.add_child(hotkey_label)
	_hotkey_labels.append(hotkey_label)

	# Cooldown overlay (darkens icon when on cooldown)
	var overlay := ColorRect.new()
	overlay.custom_minimum_size = ICON_SIZE
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.visible = false
	icon_container.add_child(overlay)
	_cooldown_overlays.append(overlay)

	# Timer label (center of icon)
	var timer := Label.new()
	timer.set_anchors_preset(Control.PRESET_CENTER)
	timer.position = Vector2(ICON_SIZE.x / 2, ICON_SIZE.y / 2)
	timer.text = ""
	timer.add_theme_font_size_override("font_size", 14)
	timer.add_theme_color_override("font_color", Color.WHITE)
	timer.add_theme_color_override("font_outline_color", Color.BLACK)
	timer.add_theme_constant_override("outline_size", 2)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer.visible = false
	icon_container.add_child(timer)
	_timer_labels.append(timer)

	# Progress bar (bottom of slot)
	var progress := ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = 100.0
	progress.value = 100.0
	progress.show_percentage = false
	progress.position = Vector2(4, SLOT_SIZE.y - PROGRESS_HEIGHT - 4)
	progress.custom_minimum_size = Vector2(SLOT_SIZE.x - 8, PROGRESS_HEIGHT)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	progress.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = _faction_color
	bar_fill.set_corner_radius_all(2)
	progress.add_theme_stylebox_override("fill", bar_fill)

	container.add_child(progress)
	_progress_bars.append(progress)

	# Make clickable
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func(): _on_slot_pressed(index))
	container.add_child(button)

	return container


## Update ability at slot.
func set_ability(slot_index: int, data: Dictionary) -> void:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return

	var was_ready: bool = _slots[slot_index]["ready"]

	_slots[slot_index] = {
		"icon": data.get("icon"),
		"name": data.get("name", ""),
		"cooldown": data.get("cooldown", 0.0),
		"max_cooldown": data.get("max_cooldown", 0.0),
		"ready": data.get("ready", true),
		"hotkey": data.get("hotkey", _slots[slot_index]["hotkey"])
	}

	_update_slot_display(slot_index)

	# Emit ready signal when cooldown finishes
	var is_ready: bool = _slots[slot_index]["ready"]
	if is_ready and not was_ready:
		ability_ready.emit(slot_index, _slots[slot_index]["hotkey"])


## Update cooldown for slot (call each frame).
func update_cooldown(slot_index: int, cooldown: float, max_cooldown: float) -> void:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return

	var was_ready: bool = _slots[slot_index]["ready"]

	_slots[slot_index]["cooldown"] = cooldown
	_slots[slot_index]["max_cooldown"] = max_cooldown
	_slots[slot_index]["ready"] = cooldown <= 0

	_update_slot_display(slot_index)

	# Emit ready signal
	var is_ready: bool = _slots[slot_index]["ready"]
	if is_ready and not was_ready:
		ability_ready.emit(slot_index, _slots[slot_index]["hotkey"])


## Set hotkey for slot.
func set_hotkey(slot_index: int, hotkey: String) -> void:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return

	_slots[slot_index]["hotkey"] = hotkey

	if slot_index < _hotkey_labels.size():
		_hotkey_labels[slot_index].text = hotkey


## Set icon for slot.
func set_icon(slot_index: int, texture: Texture2D) -> void:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return

	_slots[slot_index]["icon"] = texture

	if slot_index < _icon_rects.size():
		_icon_rects[slot_index].texture = texture


## Update slot display.
func _update_slot_display(index: int) -> void:
	if index >= _slots.size():
		return

	var data: Dictionary = _slots[index]
	var cooldown: float = data["cooldown"]
	var max_cooldown: float = data["max_cooldown"]
	var is_ready: bool = data["ready"]

	# Update icon
	if index < _icon_rects.size():
		var icon := _icon_rects[index]
		icon.texture = data["icon"]
		# Dim when on cooldown
		icon.modulate = Color.WHITE if is_ready else Color(0.5, 0.5, 0.5)

	# Update overlay
	if index < _cooldown_overlays.size():
		_cooldown_overlays[index].visible = not is_ready

	# Update timer label
	if index < _timer_labels.size():
		var timer := _timer_labels[index]
		if cooldown > 0:
			timer.text = "%.1f" % cooldown
			timer.visible = true
		else:
			timer.visible = false

	# Update progress bar
	if index < _progress_bars.size():
		var progress := _progress_bars[index]
		if max_cooldown > 0:
			var percent := ((max_cooldown - cooldown) / max_cooldown) * 100.0
			progress.value = percent
		else:
			progress.value = 100.0

		# Color based on ready state
		var bar_fill := progress.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			if is_ready:
				bar_fill.bg_color = _faction_color
			else:
				bar_fill.bg_color = Color.ORANGE

	# Update hotkey label
	if index < _hotkey_labels.size():
		_hotkey_labels[index].text = data["hotkey"]


## Handle slot pressed.
func _on_slot_pressed(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return

	ability_clicked.emit(index, _slots[index]["hotkey"])


## Trigger ability used feedback.
func on_ability_used(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_containers.size():
		return

	var container := _slot_containers[slot_index]
	if container == null or not is_instance_valid(container):
		return

	# Flash feedback
	var tween := container.create_tween()
	tween.tween_property(container, "modulate", Color(1.5, 1.5, 1.5), 0.05)
	tween.tween_property(container, "modulate", Color.WHITE, 0.15)

	ability_used.emit(slot_index, _slots[slot_index]["hotkey"])


## Update all slots (call each frame for smooth updates).
func update(delta: float) -> void:
	for i in _slots.size():
		var cooldown: float = _slots[i]["cooldown"]
		if cooldown > 0:
			# Note: actual cooldown reduction should happen in ability manager
			# This just refreshes display
			_update_slot_display(i)


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	for i in _slot_containers.size():
		if i < _progress_bars.size():
			var bar_fill := _progress_bars[i].get_theme_stylebox("fill") as StyleBoxFlat
			if bar_fill != null and _slots[i]["ready"]:
				bar_fill.bg_color = _faction_color


## Get ability state.
func get_ability_state(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _slots.size():
		return {}
	return _slots[slot_index].duplicate()


## Is ability ready.
func is_ability_ready(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _slots.size():
		return false
	return _slots[slot_index]["ready"]


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	_slot_containers.clear()
	_icon_rects.clear()
	_cooldown_overlays.clear()
	_progress_bars.clear()
	_timer_labels.clear()
	_hotkey_labels.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
