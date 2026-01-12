class_name FactoryPanel
extends RefCounted
## FactoryPanel displays individual factory status in the overview.

signal factory_selected(factory_id: int)
signal panel_updated()

## Factory data
var factory_id: int = -1
var factory_name: String = ""
var factory_type: String = ""
var faction_id: String = ""

## Status values
var _health_current: float = 100.0
var _health_max: float = 100.0
var _heat_level: float = 0.0  ## 0-100%
var _production_queue: Array = []  ## Array of {template: String, time_remaining: float}

## UI components
var _container: VBoxContainer = null
var _header_label: Label = null
var _type_label: Label = null
var _health_bar: ProgressBar = null
var _heat_bar: ProgressBar = null
var _queue_container: VBoxContainer = null
var _select_button: Button = null

## Queue item labels
var _queue_labels: Array[Label] = []


func _init() -> void:
	pass


## Initialize panel with factory data.
func initialize(p_factory_id: int, p_name: String, p_type: String, p_faction: String) -> void:
	factory_id = p_factory_id
	factory_name = p_name
	factory_type = p_type
	faction_id = p_faction


## Create UI components.
func create_ui(parent: Control) -> Control:
	# Main container with panel background
	_container = VBoxContainer.new()
	_container.name = "FactoryPanel_%d" % factory_id
	_container.custom_minimum_size = Vector2(250, 0)

	# Header with factory name
	_header_label = Label.new()
	_header_label.name = "HeaderLabel"
	_header_label.text = factory_name
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 16)
	_container.add_child(_header_label)

	# Factory type
	_type_label = Label.new()
	_type_label.name = "TypeLabel"
	_type_label.text = factory_type
	_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_container.add_child(_type_label)

	# Separator
	var sep := HSeparator.new()
	_container.add_child(sep)

	# Health bar
	var health_container := HBoxContainer.new()
	var health_label := Label.new()
	health_label.text = "Health:"
	health_label.custom_minimum_size.x = 60
	health_container.add_child(health_label)

	_health_bar = ProgressBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.min_value = 0.0
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = true
	_health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_container.add_child(_health_bar)

	_container.add_child(health_container)

	# Heat bar
	var heat_container := HBoxContainer.new()
	var heat_label := Label.new()
	heat_label.text = "Heat:"
	heat_label.custom_minimum_size.x = 60
	heat_container.add_child(heat_label)

	_heat_bar = ProgressBar.new()
	_heat_bar.name = "HeatBar"
	_heat_bar.min_value = 0.0
	_heat_bar.max_value = 100.0
	_heat_bar.value = 0.0
	_heat_bar.show_percentage = true
	_heat_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heat_container.add_child(_heat_bar)

	_container.add_child(heat_container)

	# Production queue section
	var queue_header := Label.new()
	queue_header.text = "Production Queue:"
	queue_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_container.add_child(queue_header)

	_queue_container = VBoxContainer.new()
	_queue_container.name = "QueueContainer"
	_container.add_child(_queue_container)

	# Select button
	_select_button = Button.new()
	_select_button.name = "SelectButton"
	_select_button.text = "Select Factory"
	_select_button.pressed.connect(_on_select_pressed)
	_container.add_child(_select_button)

	parent.add_child(_container)

	_update_display()

	return _container


## Update health values.
func update_health(current: float, max_health: float) -> void:
	_health_current = current
	_health_max = max_health

	if _health_bar != null and _health_max > 0:
		var percentage := (_health_current / _health_max) * 100.0
		_health_bar.value = percentage

		# Color based on health
		if percentage > 60:
			_set_bar_color(_health_bar, Color.GREEN)
		elif percentage > 30:
			_set_bar_color(_health_bar, Color.YELLOW)
		else:
			_set_bar_color(_health_bar, Color.RED)

	panel_updated.emit()


## Update heat level.
func update_heat(heat_percentage: float) -> void:
	_heat_level = clampf(heat_percentage, 0.0, 100.0)

	if _heat_bar != null:
		_heat_bar.value = _heat_level

		# Color based on heat
		if _heat_level < 50:
			_set_bar_color(_heat_bar, Color.CYAN)
		elif _heat_level < 80:
			_set_bar_color(_heat_bar, Color.YELLOW)
		else:
			_set_bar_color(_heat_bar, Color.RED)

	panel_updated.emit()


## Update production queue.
func update_production_queue(queue: Array) -> void:
	_production_queue = queue

	if _queue_container == null:
		return

	# Clear existing labels
	for label in _queue_labels:
		if is_instance_valid(label):
			label.queue_free()
	_queue_labels.clear()

	# Handle empty queue
	if _production_queue.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(Empty)"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_queue_container.add_child(empty_label)
		_queue_labels.append(empty_label)
	else:
		# Create labels for each queue item
		for item in _production_queue:
			var label := Label.new()

			var template: String = item.get("template", "Unknown")
			var time_remaining: float = item.get("time_remaining", 0.0)

			label.text = "%s (%.1fs)" % [template, time_remaining]
			label.add_theme_font_size_override("font_size", 12)

			_queue_container.add_child(label)
			_queue_labels.append(label)

	panel_updated.emit()


## Set progress bar color.
func _set_bar_color(bar: ProgressBar, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	bar.add_theme_stylebox_override("fill", style)


## Update full display.
func _update_display() -> void:
	if _header_label != null:
		_header_label.text = factory_name

	if _type_label != null:
		_type_label.text = factory_type


## Handle select button press.
func _on_select_pressed() -> void:
	factory_selected.emit(factory_id)


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Get container.
func get_container() -> Control:
	return _container


## Cleanup.
func cleanup() -> void:
	for label in _queue_labels:
		if is_instance_valid(label):
			label.queue_free()
	_queue_labels.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()

	_container = null
	_header_label = null
	_type_label = null
	_health_bar = null
	_heat_bar = null
	_queue_container = null
	_select_button = null


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"factory_id": factory_id,
		"factory_name": factory_name,
		"factory_type": factory_type,
		"faction_id": faction_id,
		"health_percent": (_health_current / _health_max * 100.0) if _health_max > 0 else 0.0,
		"heat_level": _heat_level,
		"queue_size": _production_queue.size()
	}
