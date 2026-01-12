class_name ProductionQueueUI
extends RefCounted
## ProductionQueueUI displays and manages factory production queue.

signal unit_added(unit_template: String)
signal unit_cancelled(queue_index: int)
signal unit_reordered(from_index: int, to_index: int)
signal queue_updated()

## Queue data
var _queue_items: Array = []  ## Array of {template, time_remaining, cost, can_afford}
var _available_units: Array = []  ## Array of {template, name, cost, unlocked}

## UI components
var _container: VBoxContainer = null
var _queue_list: VBoxContainer = null
var _unit_buttons: VBoxContainer = null
var _empty_label: Label = null
var _add_unit_popup: PopupMenu = null

## Queue item controls
var _queue_item_controls: Array = []  ## Array of HBoxContainer


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control) -> Control:
	_container = VBoxContainer.new()
	_container.name = "ProductionQueueUI"

	# Header
	var header := Label.new()
	header.text = "Production Queue"
	header.add_theme_font_size_override("font_size", 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_container.add_child(header)

	# Separator
	var sep1 := HSeparator.new()
	_container.add_child(sep1)

	# Queue list
	_queue_list = VBoxContainer.new()
	_queue_list.name = "QueueList"
	_container.add_child(_queue_list)

	# Empty label
	_empty_label = Label.new()
	_empty_label.text = "Queue is empty"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_queue_list.add_child(_empty_label)

	# Separator
	var sep2 := HSeparator.new()
	_container.add_child(sep2)

	# Add unit section
	var add_header := Label.new()
	add_header.text = "Add Unit"
	add_header.add_theme_font_size_override("font_size", 14)
	_container.add_child(add_header)

	_unit_buttons = VBoxContainer.new()
	_unit_buttons.name = "UnitButtons"
	_container.add_child(_unit_buttons)

	parent.add_child(_container)

	return _container


## Set available units for production.
func set_available_units(units: Array) -> void:
	_available_units = units
	_update_unit_buttons()


## Update unit buttons.
func _update_unit_buttons() -> void:
	if _unit_buttons == null:
		return

	# Clear existing buttons
	for child in _unit_buttons.get_children():
		child.queue_free()

	# Create buttons for each available unit
	for unit in _available_units:
		var template: String = unit.get("template", "")
		var name: String = unit.get("name", template)
		var cost: Dictionary = unit.get("cost", {})
		var unlocked: bool = unit.get("unlocked", true)
		var can_afford: bool = unit.get("can_afford", true)

		var button_container := HBoxContainer.new()

		var button := Button.new()
		button.text = name
		button.disabled = not unlocked or not can_afford
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_add_unit.bind(template))
		button_container.add_child(button)

		# Cost label
		var cost_label := Label.new()
		var cost_text := ""
		if cost.has("ree"):
			cost_text += "%d REE" % cost["ree"]
		if cost.has("power"):
			if not cost_text.is_empty():
				cost_text += " "
			cost_text += "%d PWR" % cost["power"]

		cost_label.text = cost_text
		cost_label.custom_minimum_size.x = 80
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		if not can_afford:
			cost_label.add_theme_color_override("font_color", Color.RED)

		button_container.add_child(cost_label)

		_unit_buttons.add_child(button_container)


## Update queue display.
func update_queue(items: Array) -> void:
	_queue_items = items
	_refresh_queue_display()
	queue_updated.emit()


## Refresh queue display.
func _refresh_queue_display() -> void:
	if _queue_list == null:
		return

	# Clear existing items (except empty label)
	for control in _queue_item_controls:
		if is_instance_valid(control):
			control.queue_free()
	_queue_item_controls.clear()

	# Show/hide empty label
	_empty_label.visible = _queue_items.is_empty()

	# Create items
	for i in _queue_items.size():
		var item: Dictionary = _queue_items[i]
		var control := _create_queue_item(i, item)
		_queue_list.add_child(control)
		_queue_item_controls.append(control)


## Create queue item control.
func _create_queue_item(index: int, item: Dictionary) -> Control:
	var container := HBoxContainer.new()

	# Index label
	var index_label := Label.new()
	index_label.text = "%d." % (index + 1)
	index_label.custom_minimum_size.x = 25
	container.add_child(index_label)

	# Unit name
	var name_label := Label.new()
	name_label.text = item.get("template", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(name_label)

	# Time remaining
	var time_label := Label.new()
	var time_remaining: float = item.get("time_remaining", 0.0)
	time_label.text = "%.1fs" % time_remaining
	time_label.custom_minimum_size.x = 50
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	container.add_child(time_label)

	# Progress for first item
	if index == 0:
		var progress: float = item.get("progress", 0.0)
		var progress_bar := ProgressBar.new()
		progress_bar.min_value = 0.0
		progress_bar.max_value = 100.0
		progress_bar.value = progress * 100.0
		progress_bar.show_percentage = false
		progress_bar.custom_minimum_size = Vector2(60, 15)
		container.add_child(progress_bar)
	else:
		# Reorder buttons
		var up_button := Button.new()
		up_button.text = "^"
		up_button.custom_minimum_size = Vector2(25, 25)
		up_button.disabled = index <= 1
		up_button.pressed.connect(_on_reorder.bind(index, index - 1))
		container.add_child(up_button)

		var down_button := Button.new()
		down_button.text = "v"
		down_button.custom_minimum_size = Vector2(25, 25)
		down_button.disabled = index >= _queue_items.size() - 1
		down_button.pressed.connect(_on_reorder.bind(index, index + 1))
		container.add_child(down_button)

	# Cancel button (not for first item in progress)
	var cancel_button := Button.new()
	cancel_button.text = "X"
	cancel_button.custom_minimum_size = Vector2(25, 25)
	cancel_button.pressed.connect(_on_cancel.bind(index))
	container.add_child(cancel_button)

	return container


## Handle add unit button.
func _on_add_unit(template: String) -> void:
	unit_added.emit(template)


## Handle cancel button.
func _on_cancel(index: int) -> void:
	unit_cancelled.emit(index)


## Handle reorder.
func _on_reorder(from_index: int, to_index: int) -> void:
	unit_reordered.emit(from_index, to_index)


## Get queue size.
func get_queue_size() -> int:
	return _queue_items.size()


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	for control in _queue_item_controls:
		if is_instance_valid(control):
			control.queue_free()
	_queue_item_controls.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()

	_container = null
	_queue_list = null
	_unit_buttons = null
	_empty_label = null


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"queue_size": _queue_items.size(),
		"available_units": _available_units.size()
	}
