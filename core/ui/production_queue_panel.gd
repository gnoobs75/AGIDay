class_name ProductionQueuePanel
extends RefCounted
## ProductionQueuePanel displays factory assembly progress and queued items.

signal production_item_clicked(item_index: int)
signal production_complete(unit_type: String)
signal queue_cancel_requested(item_index: int)

## Panel sizing
const PANEL_WIDTH := 280
const PANEL_HEIGHT := 200
const QUEUE_ITEM_HEIGHT := 32
const MAX_VISIBLE_ITEMS := 5

## Current production data
var _current_item := ""
var _current_progress := 0.0
var _queue: Array[Dictionary] = []  ## [{type, time_remaining, icon}]

## UI components
var _container: PanelContainer = null
var _current_label: Label = null
var _current_progress_bar: ProgressBar = null
var _progress_label: Label = null
var _queue_vbox: VBoxContainer = null
var _queue_items: Array[Control] = []

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "ProductionQueuePanel"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d", 0.7)
	style.border_color = _faction_color.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_container.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_container.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var icon := Label.new()
	icon.text = "[PROD]"
	icon.add_theme_color_override("font_color", Color.ORANGE)
	icon.add_theme_font_size_override("font_size", 12)
	header.add_child(icon)

	var title := Label.new()
	title.text = "Production Queue"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	vbox.add_child(header)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Current production item
	var current_container := VBoxContainer.new()
	current_container.add_theme_constant_override("separation", 4)

	_current_label = Label.new()
	_current_label.text = "Building: None"
	_current_label.add_theme_font_size_override("font_size", 12)
	_current_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	current_container.add_child(_current_label)

	# Progress bar for current item
	var progress_hbox := HBoxContainer.new()
	progress_hbox.add_theme_constant_override("separation", 8)

	_current_progress_bar = ProgressBar.new()
	_current_progress_bar.min_value = 0.0
	_current_progress_bar.max_value = 100.0
	_current_progress_bar.value = 0.0
	_current_progress_bar.show_percentage = false
	_current_progress_bar.custom_minimum_size = Vector2(0, 16)
	_current_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(4)
	_current_progress_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = _faction_color
	bar_fill.set_corner_radius_all(4)
	_current_progress_bar.add_theme_stylebox_override("fill", bar_fill)

	progress_hbox.add_child(_current_progress_bar)

	_progress_label = Label.new()
	_progress_label.text = "0%"
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override("font_color", Color.WHITE)
	_progress_label.custom_minimum_size.x = 40
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_hbox.add_child(_progress_label)

	current_container.add_child(progress_hbox)
	vbox.add_child(current_container)

	# Queue label
	var queue_label := Label.new()
	queue_label.text = "Queue:"
	queue_label.add_theme_font_size_override("font_size", 11)
	queue_label.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(queue_label)

	# Queue items container with scroll
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size.y = QUEUE_ITEM_HEIGHT * 3
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_queue_vbox = VBoxContainer.new()
	_queue_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(_queue_vbox)

	vbox.add_child(scroll)

	parent.add_child(_container)
	return _container


## Update queue display.
func update_queue(queue: Array[Dictionary], current_progress: float) -> void:
	var old_item := _current_item
	var old_progress := _current_progress

	_current_progress = clampf(current_progress, 0.0, 100.0)
	_queue = queue

	# Get current item from queue
	if queue.size() > 0:
		_current_item = queue[0].get("type", "Unknown")
	else:
		_current_item = ""

	_update_display()

	# Check for completion
	if current_progress >= 100.0 and old_progress < 100.0 and not old_item.is_empty():
		production_complete.emit(old_item)


## Update display elements.
func _update_display() -> void:
	# Update current production
	if _current_label != null:
		if _current_item.is_empty():
			_current_label.text = "Building: None"
			_current_label.add_theme_color_override("font_color", Color("#666666"))
		else:
			_current_label.text = "Building: %s" % _current_item
			_current_label.add_theme_color_override("font_color", Color.WHITE)

	if _current_progress_bar != null:
		_current_progress_bar.value = _current_progress
		_current_progress_bar.visible = not _current_item.is_empty()

	if _progress_label != null:
		if _current_item.is_empty():
			_progress_label.text = ""
		else:
			_progress_label.text = "%.0f%%" % _current_progress

	# Update queue list
	_update_queue_items()


## Update queue item displays.
func _update_queue_items() -> void:
	# Clear old items
	for item in _queue_items:
		if is_instance_valid(item):
			item.queue_free()
	_queue_items.clear()

	if _queue_vbox == null:
		return

	# Skip first item (it's the current production)
	for i in range(1, mini(_queue.size(), MAX_VISIBLE_ITEMS + 1)):
		var queue_item: Dictionary = _queue[i]
		var item_node := _create_queue_item(i, queue_item)
		_queue_vbox.add_child(item_node)
		_queue_items.append(item_node)

	# Show remaining count if more items
	if _queue.size() > MAX_VISIBLE_ITEMS + 1:
		var remaining := _queue.size() - MAX_VISIBLE_ITEMS - 1
		var more_label := Label.new()
		more_label.text = "+%d more..." % remaining
		more_label.add_theme_font_size_override("font_size", 10)
		more_label.add_theme_color_override("font_color", Color("#666666"))
		more_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_queue_vbox.add_child(more_label)
		_queue_items.append(more_label)

	# Show empty message if no queue
	if _queue.size() <= 1:
		var empty_label := Label.new()
		empty_label.text = "(Queue empty)"
		empty_label.add_theme_font_size_override("font_size", 10)
		empty_label.add_theme_color_override("font_color", Color("#555555"))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_queue_vbox.add_child(empty_label)
		_queue_items.append(empty_label)


## Create a queue item display.
func _create_queue_item(index: int, data: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	# Index number
	var num_label := Label.new()
	num_label.text = "%d." % index
	num_label.add_theme_font_size_override("font_size", 11)
	num_label.add_theme_color_override("font_color", Color("#888888"))
	num_label.custom_minimum_size.x = 20
	hbox.add_child(num_label)

	# Unit type
	var type_label := Label.new()
	type_label.text = data.get("type", "Unknown")
	type_label.add_theme_font_size_override("font_size", 11)
	type_label.add_theme_color_override("font_color", Color("#cccccc"))
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(type_label)

	# Time remaining
	var time_remaining: float = data.get("time_remaining", 0.0)
	var time_label := Label.new()
	time_label.text = "%.1fs" % time_remaining
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.add_theme_color_override("font_color", Color("#666666"))
	time_label.custom_minimum_size.x = 40
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(time_label)

	# Cancel button
	var cancel_btn := Button.new()
	cancel_btn.text = "X"
	cancel_btn.custom_minimum_size = Vector2(20, 20)
	cancel_btn.add_theme_font_size_override("font_size", 10)
	cancel_btn.pressed.connect(func(): queue_cancel_requested.emit(index))
	hbox.add_child(cancel_btn)

	return hbox


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _container != null:
		var style := _container.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = _faction_color.darkened(0.3)

	if _current_progress_bar != null:
		var bar_fill := _current_progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_fill != null:
			bar_fill.bg_color = _faction_color


## Get container.
func get_container() -> Control:
	return _container


## Get queue state.
func get_queue_state() -> Dictionary:
	return {
		"current_item": _current_item,
		"current_progress": _current_progress,
		"queue_size": _queue.size()
	}


## Get full queue.
func get_queue() -> Array[Dictionary]:
	return _queue.duplicate()


## Cleanup.
func cleanup() -> void:
	for item in _queue_items:
		if is_instance_valid(item):
			item.queue_free()
	_queue_items.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_current_label = null
	_current_progress_bar = null
	_progress_label = null
	_queue_vbox = null
