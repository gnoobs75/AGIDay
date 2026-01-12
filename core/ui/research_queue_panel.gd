class_name ResearchQueuePanel
extends RefCounted
## ResearchQueuePanel displays and manages the research queue.

signal research_cancelled(tech_id: String)
signal research_reordered(from_index: int, to_index: int)
signal queue_cleared()

## Panel sizing
const PANEL_WIDTH := 280
const PANEL_HEIGHT := 400
const ITEM_HEIGHT := 60
const MAX_VISIBLE_ITEMS := 5

## Queue data
var _queue: Array[Dictionary] = []  ## [{tech_id, name, progress, eta}]
var _current_research: Dictionary = {}

## UI components
var _container: PanelContainer = null
var _header_label: Label = null
var _current_panel: PanelContainer = null
var _current_name: Label = null
var _current_progress: ProgressBar = null
var _current_eta: Label = null
var _queue_scroll: ScrollContainer = null
var _queue_container: VBoxContainer = null
var _queue_items: Array[Control] = []
var _empty_label: Label = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "ResearchQueuePanel"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a", 0.95)
	style.border_color = _faction_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	_container.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_container.add_child(vbox)

	# Header
	_header_label = Label.new()
	_header_label.text = "Research Queue"
	_header_label.add_theme_font_size_override("font_size", 16)
	_header_label.add_theme_color_override("font_color", Color.WHITE)
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_header_label)

	vbox.add_child(HSeparator.new())

	# Current research panel
	_current_panel = _create_current_research_panel()
	vbox.add_child(_current_panel)

	vbox.add_child(HSeparator.new())

	# Queue header
	var queue_header := HBoxContainer.new()
	queue_header.add_theme_constant_override("separation", 8)

	var queue_title := Label.new()
	queue_title.text = "Queued:"
	queue_title.add_theme_font_size_override("font_size", 12)
	queue_title.add_theme_color_override("font_color", Color("#888888"))
	queue_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_header.add_child(queue_title)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.add_theme_font_size_override("font_size", 10)
	clear_btn.custom_minimum_size = Vector2(50, 24)
	clear_btn.pressed.connect(_on_clear_pressed)
	queue_header.add_child(clear_btn)

	vbox.add_child(queue_header)

	# Queue scroll area
	_queue_scroll = ScrollContainer.new()
	_queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_queue_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_queue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_queue_container = VBoxContainer.new()
	_queue_container.add_theme_constant_override("separation", 8)
	_queue_scroll.add_child(_queue_container)

	vbox.add_child(_queue_scroll)

	# Empty queue label
	_empty_label = Label.new()
	_empty_label.text = "No research queued"
	_empty_label.add_theme_font_size_override("font_size", 11)
	_empty_label.add_theme_color_override("font_color", Color("#666666"))
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_queue_container.add_child(_empty_label)

	parent.add_child(_container)
	return _container


## Create current research panel.
func _create_current_research_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "CurrentResearch"
	panel.custom_minimum_size.y = 80

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d")
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Currently Researching"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(header)

	_current_name = Label.new()
	_current_name.text = "None"
	_current_name.add_theme_font_size_override("font_size", 14)
	_current_name.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_current_name)

	# Progress row
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 8)

	_current_progress = ProgressBar.new()
	_current_progress.min_value = 0.0
	_current_progress.max_value = 100.0
	_current_progress.value = 0.0
	_current_progress.show_percentage = false
	_current_progress.custom_minimum_size = Vector2(150, 10)
	_current_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#1f1f1f")
	bar_bg.set_corner_radius_all(2)
	_current_progress.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color.CYAN
	bar_fill.set_corner_radius_all(2)
	_current_progress.add_theme_stylebox_override("fill", bar_fill)

	progress_row.add_child(_current_progress)

	_current_eta = Label.new()
	_current_eta.text = "--:--"
	_current_eta.add_theme_font_size_override("font_size", 11)
	_current_eta.add_theme_color_override("font_color", Color("#aaaaaa"))
	_current_eta.custom_minimum_size.x = 50
	_current_eta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_row.add_child(_current_eta)

	vbox.add_child(progress_row)

	return panel


## Create a queue item.
func _create_queue_item(index: int, data: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = ITEM_HEIGHT

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#252525")
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Index label
	var idx_label := Label.new()
	idx_label.text = str(index + 1)
	idx_label.add_theme_font_size_override("font_size", 14)
	idx_label.add_theme_color_override("font_color", Color("#666666"))
	idx_label.custom_minimum_size.x = 20
	hbox.add_child(idx_label)

	# Info container
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = data.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(name_label)

	var eta_label := Label.new()
	eta_label.name = "ETALabel"
	var eta: float = data.get("eta", 0.0)
	eta_label.text = "ETA: %s" % _format_time(eta)
	eta_label.add_theme_font_size_override("font_size", 10)
	eta_label.add_theme_color_override("font_color", Color("#888888"))
	info.add_child(eta_label)

	hbox.add_child(info)

	# Cancel button
	var cancel_btn := Button.new()
	cancel_btn.text = "X"
	cancel_btn.custom_minimum_size = Vector2(28, 28)
	cancel_btn.add_theme_font_size_override("font_size", 12)
	var tech_id: String = data.get("tech_id", "")
	cancel_btn.pressed.connect(func(): _on_cancel_pressed(tech_id))
	hbox.add_child(cancel_btn)

	return panel


## Format time as MM:SS.
func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%02d:%02d" % [mins, secs]


## Set current research.
func set_current_research(tech_id: String, name: String, progress: float, eta: float) -> void:
	_current_research = {
		"tech_id": tech_id,
		"name": name,
		"progress": progress,
		"eta": eta
	}

	if _current_name != null:
		_current_name.text = name if not name.is_empty() else "None"

	if _current_progress != null:
		_current_progress.value = progress * 100.0

	if _current_eta != null:
		if eta > 0:
			_current_eta.text = _format_time(eta)
		else:
			_current_eta.text = "--:--"


## Update current research progress.
func update_progress(progress: float, eta: float) -> void:
	if _current_progress != null:
		_current_progress.value = progress * 100.0

	if _current_eta != null:
		if eta > 0:
			_current_eta.text = _format_time(eta)
		else:
			_current_eta.text = "--:--"


## Set research queue.
func set_queue(queue: Array[Dictionary]) -> void:
	_queue = queue
	_rebuild_queue_display()


## Add to queue.
func add_to_queue(tech_id: String, name: String, eta: float) -> void:
	_queue.append({
		"tech_id": tech_id,
		"name": name,
		"eta": eta
	})
	_rebuild_queue_display()


## Remove from queue.
func remove_from_queue(tech_id: String) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i].get("tech_id", "") == tech_id:
			_queue.remove_at(i)
			break
	_rebuild_queue_display()


## Rebuild queue display.
func _rebuild_queue_display() -> void:
	# Clear existing items
	for item in _queue_items:
		if is_instance_valid(item):
			item.queue_free()
	_queue_items.clear()

	# Show/hide empty label
	if _empty_label != null:
		_empty_label.visible = _queue.is_empty()

	# Create new items
	for i in range(_queue.size()):
		var item := _create_queue_item(i, _queue[i])
		_queue_container.add_child(item)
		_queue_items.append(item)


## Handle cancel button pressed.
func _on_cancel_pressed(tech_id: String) -> void:
	research_cancelled.emit(tech_id)


## Handle clear button pressed.
func _on_clear_pressed() -> void:
	queue_cleared.emit()


## Clear all queued research.
func clear_queue() -> void:
	_queue.clear()
	_rebuild_queue_display()


## Get queue size.
func get_queue_size() -> int:
	return _queue.size()


## Is queue empty.
func is_queue_empty() -> bool:
	return _queue.is_empty()


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _container != null:
		var style := _container.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = _faction_color


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	_queue_items.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
