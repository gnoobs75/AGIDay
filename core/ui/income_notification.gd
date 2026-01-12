class_name IncomeNotification
extends RefCounted
## IncomeNotification displays income popups in top-right corner with stacking.

signal notification_clicked(notification_id: int)

## Display settings
const NOTIFICATION_WIDTH := 200
const NOTIFICATION_HEIGHT := 40
const NOTIFICATION_MARGIN := 10
const MAX_NOTIFICATIONS := 5
const DISPLAY_DURATION := 3.0
const FADE_DURATION := 0.3
const STACK_OFFSET := 50

## Notification types
enum NotificationType {
	REE_INCOME,
	POWER_INCOME,
	RESEARCH_INCOME,
	DISTRICT_CAPTURED,
	DISTRICT_LOST
}

## Active notifications
var _notifications: Array[Dictionary] = []  ## [{id, type, text, value, node, timer}]
var _next_id := 0

## Container
var _container: Control = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Initialize with parent.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Container anchored to top-right
	_container = Control.new()
	_container.name = "IncomeNotificationContainer"
	_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_container.position = Vector2(-NOTIFICATION_WIDTH - NOTIFICATION_MARGIN, NOTIFICATION_MARGIN)
	_container.size = Vector2(NOTIFICATION_WIDTH, NOTIFICATION_HEIGHT * MAX_NOTIFICATIONS + STACK_OFFSET * MAX_NOTIFICATIONS)

	parent.add_child(_container)
	return _container


## Show income notification.
func show_income(type: NotificationType, value: float, source: String = "") -> int:
	var text: String
	var color: Color
	var icon: String

	match type:
		NotificationType.REE_INCOME:
			text = "+%.0f REE" % value
			if not source.is_empty():
				text += " (%s)" % source
			color = Color.CYAN
			icon = "[REE]"

		NotificationType.POWER_INCOME:
			text = "+%.0f Power" % value
			if not source.is_empty():
				text += " (%s)" % source
			color = Color.YELLOW
			icon = "[PWR]"

		NotificationType.RESEARCH_INCOME:
			text = "+%.0f Research" % value
			if not source.is_empty():
				text += " (%s)" % source
			color = Color.MAGENTA
			icon = "[RES]"

		NotificationType.DISTRICT_CAPTURED:
			text = "District Captured!"
			if not source.is_empty():
				text = "Captured: %s" % source
			color = Color.GREEN
			icon = "[+]"

		NotificationType.DISTRICT_LOST:
			text = "District Lost!"
			if not source.is_empty():
				text = "Lost: %s" % source
			color = Color.RED
			icon = "[-]"

		_:
			text = "+%.0f" % value
			color = Color.WHITE
			icon = ""

	return _add_notification(type, text, icon, color, value)


## Add a notification.
func _add_notification(type: NotificationType, text: String, icon: String, color: Color, value: float) -> int:
	var notification_id := _next_id
	_next_id += 1

	# Remove oldest if at max
	while _notifications.size() >= MAX_NOTIFICATIONS:
		_remove_notification(0)

	# Create notification panel
	var node := _create_notification_node(notification_id, text, icon, color)
	_container.add_child(node)

	# Add to list
	_notifications.append({
		"id": notification_id,
		"type": type,
		"text": text,
		"value": value,
		"node": node,
		"timer": DISPLAY_DURATION,
		"fading": false
	})

	# Reposition all
	_reposition_notifications()

	# Fade in
	node.modulate.a = 0.0
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, FADE_DURATION)

	return notification_id


## Create notification node.
func _create_notification_node(notification_id: int, text: String, icon: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Notification_%d" % notification_id
	panel.custom_minimum_size = Vector2(NOTIFICATION_WIDTH, NOTIFICATION_HEIGHT)

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d", 0.9)
	style.border_color = color.darkened(0.3)
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.border_color = color
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	# Content
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Icon
	if not icon.is_empty():
		var icon_label := Label.new()
		icon_label.text = icon
		icon_label.add_theme_font_size_override("font_size", 12)
		icon_label.add_theme_color_override("font_color", color)
		hbox.add_child(icon_label)

	# Text
	var text_label := Label.new()
	text_label.text = text
	text_label.add_theme_font_size_override("font_size", 12)
	text_label.add_theme_color_override("font_color", Color.WHITE)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(text_label)

	# Make clickable
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			notification_clicked.emit(notification_id)
	)

	return panel


## Reposition notifications.
func _reposition_notifications() -> void:
	var y := 0.0
	for i in _notifications.size():
		var data: Dictionary = _notifications[i]
		var node: Control = data["node"]
		if node != null and is_instance_valid(node):
			node.position.y = y
			y += NOTIFICATION_HEIGHT + NOTIFICATION_MARGIN


## Update notifications (call each frame).
func update(delta: float) -> void:
	var to_remove: Array[int] = []

	for i in _notifications.size():
		var data: Dictionary = _notifications[i]
		data["timer"] -= delta

		if data["timer"] <= 0 and not data["fading"]:
			# Start fade out
			data["fading"] = true
			var node: Control = data["node"]
			if node != null and is_instance_valid(node):
				var tween := node.create_tween()
				tween.tween_property(node, "modulate:a", 0.0, FADE_DURATION)
				tween.finished.connect(func(): to_remove.append(i))

	# Remove faded notifications (in reverse order)
	to_remove.reverse()
	for i in to_remove:
		_remove_notification(i)


## Remove notification by index.
func _remove_notification(index: int) -> void:
	if index < 0 or index >= _notifications.size():
		return

	var data: Dictionary = _notifications[index]
	var node: Control = data["node"]
	if node != null and is_instance_valid(node):
		node.queue_free()

	_notifications.remove_at(index)
	_reposition_notifications()


## Clear all notifications.
func clear_all() -> void:
	for data in _notifications:
		var node: Control = data["node"]
		if node != null and is_instance_valid(node):
			node.queue_free()

	_notifications.clear()


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])


## Get container.
func get_container() -> Control:
	return _container


## Get notification count.
func get_notification_count() -> int:
	return _notifications.size()


## Cleanup.
func cleanup() -> void:
	clear_all()
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
