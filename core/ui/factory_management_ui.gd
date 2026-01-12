class_name FactoryManagementUI
extends RefCounted
## FactoryManagementUI provides complete factory management interface.

signal factory_selected(factory_id: int)
signal unit_queued(factory_id: int, unit_template: String)
signal unit_cancelled(factory_id: int, queue_index: int)
signal overclock_changed(factory_id: int, multiplier: float)
signal ui_closed()

## Current state
var _current_factory_id: int = -1
var _current_faction_id: String = ""

## UI components
var _main_container: Control = null
var _overview_display: FactoryOverviewDisplay = null
var _heat_display: FactoryHeatDisplay = null
var _queue_ui: ProductionQueueUI = null
var _resource_display: Control = null
var _detail_panel: VBoxContainer = null

## Resource labels
var _ree_label: Label = null
var _power_label: Label = null

## Factory data cache
var _factory_data: Dictionary = {}  ## factory_id -> data dict


func _init() -> void:
	_overview_display = FactoryOverviewDisplay.new()
	_heat_display = FactoryHeatDisplay.new()
	_queue_ui = ProductionQueueUI.new()


## Create UI.
func create_ui(parent: Control) -> Control:
	_main_container = HBoxContainer.new()
	_main_container.name = "FactoryManagementUI"
	_main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Left panel - Overview
	var left_panel := VBoxContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.custom_minimum_size.x = 280
	_overview_display.create_ui(left_panel)
	_overview_display.factory_selected.connect(_on_factory_selected)
	_main_container.add_child(left_panel)

	# Separator
	var sep := VSeparator.new()
	_main_container.add_child(sep)

	# Right panel - Detail
	_detail_panel = VBoxContainer.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.visible = false

	# Resource display at top
	_create_resource_display()

	# Heat display
	_heat_display.create_ui(_detail_panel)
	_heat_display.overclock_changed.connect(_on_overclock_changed)

	# Separator
	var sep2 := HSeparator.new()
	_detail_panel.add_child(sep2)

	# Production queue
	_queue_ui.create_ui(_detail_panel)
	_queue_ui.unit_added.connect(_on_unit_added)
	_queue_ui.unit_cancelled.connect(_on_unit_cancelled)

	_main_container.add_child(_detail_panel)

	parent.add_child(_main_container)

	return _main_container


## Create resource display.
func _create_resource_display() -> void:
	_resource_display = HBoxContainer.new()
	_resource_display.name = "ResourceDisplay"

	# REE
	var ree_container := HBoxContainer.new()
	var ree_icon := Label.new()
	ree_icon.text = "REE:"
	ree_container.add_child(ree_icon)

	_ree_label = Label.new()
	_ree_label.text = "0"
	_ree_label.custom_minimum_size.x = 80
	ree_container.add_child(_ree_label)

	_resource_display.add_child(ree_container)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_display.add_child(spacer)

	# Power
	var power_container := HBoxContainer.new()
	var power_icon := Label.new()
	power_icon.text = "Power:"
	power_container.add_child(power_icon)

	_power_label = Label.new()
	_power_label.text = "0"
	_power_label.custom_minimum_size.x = 80
	power_container.add_child(_power_label)

	_resource_display.add_child(power_container)

	_detail_panel.add_child(_resource_display)


## Set current faction.
func set_faction(faction_id: String) -> void:
	_current_faction_id = faction_id
	_overview_display.set_faction(faction_id)
	_deselect_factory()


## Add factory to UI.
func add_factory(factory_id: int, name: String, type: String, faction_id: String) -> void:
	_overview_display.add_factory(factory_id, name, type, faction_id)

	_factory_data[factory_id] = {
		"name": name,
		"type": type,
		"faction": faction_id,
		"health": 100.0,
		"health_max": 100.0,
		"heat": 0.0,
		"overclock": 1.0,
		"queue": []
	}


## Remove factory from UI.
func remove_factory(factory_id: int) -> void:
	_overview_display.remove_factory(factory_id)
	_factory_data.erase(factory_id)

	if _current_factory_id == factory_id:
		_deselect_factory()


## Update factory data.
func update_factory(factory_id: int, data: Dictionary) -> void:
	if not _factory_data.has(factory_id):
		return

	# Merge data
	for key in data:
		_factory_data[factory_id][key] = data[key]

	# Update overview
	var fd: Dictionary = _factory_data[factory_id]
	_overview_display.update_factory(
		factory_id,
		fd.get("health", 100.0),
		fd.get("health_max", 100.0),
		fd.get("heat", 0.0),
		fd.get("queue", [])
	)

	# Update detail panel if this factory is selected
	if factory_id == _current_factory_id:
		_update_detail_panel()


## Update resources display.
func update_resources(ree: int, power: int) -> void:
	if _ree_label != null:
		_ree_label.text = str(ree)

	if _power_label != null:
		_power_label.text = str(power)


## Set available units for production.
func set_available_units(units: Array) -> void:
	_queue_ui.set_available_units(units)


## Handle factory selection from overview.
func _on_factory_selected(factory_id: int) -> void:
	_select_factory(factory_id)
	factory_selected.emit(factory_id)


## Select a factory for detail view.
func _select_factory(factory_id: int) -> void:
	_current_factory_id = factory_id
	_detail_panel.visible = true
	_update_detail_panel()


## Deselect current factory.
func _deselect_factory() -> void:
	_current_factory_id = -1
	_detail_panel.visible = false


## Update detail panel with current factory data.
func _update_detail_panel() -> void:
	if _current_factory_id < 0 or not _factory_data.has(_current_factory_id):
		return

	var data: Dictionary = _factory_data[_current_factory_id]

	# Update heat display
	_heat_display.set_heat_level(data.get("heat", 0.0))
	_heat_display.set_overclock_multiplier(data.get("overclock", 1.0))

	# Update queue
	_queue_ui.update_queue(data.get("queue", []))


## Handle overclock change.
func _on_overclock_changed(multiplier: float) -> void:
	if _current_factory_id >= 0:
		if _factory_data.has(_current_factory_id):
			_factory_data[_current_factory_id]["overclock"] = multiplier
		overclock_changed.emit(_current_factory_id, multiplier)


## Handle unit added to queue.
func _on_unit_added(template: String) -> void:
	if _current_factory_id >= 0:
		unit_queued.emit(_current_factory_id, template)


## Handle unit cancelled.
func _on_unit_cancelled(queue_index: int) -> void:
	if _current_factory_id >= 0:
		unit_cancelled.emit(_current_factory_id, queue_index)


## Get current factory ID.
func get_current_factory() -> int:
	return _current_factory_id


## Get overview display.
func get_overview_display() -> FactoryOverviewDisplay:
	return _overview_display


## Set visibility.
func set_visible(visible: bool) -> void:
	if _main_container != null:
		_main_container.visible = visible


## Check if visible.
func is_visible() -> bool:
	if _main_container != null:
		return _main_container.visible
	return false


## Cleanup.
func cleanup() -> void:
	_overview_display.cleanup()
	_heat_display.cleanup()
	_queue_ui.cleanup()

	if _main_container != null and is_instance_valid(_main_container):
		_main_container.queue_free()

	_main_container = null
	_detail_panel = null
	_resource_display = null
	_factory_data.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"current_factory": _current_factory_id,
		"current_faction": _current_faction_id,
		"factory_count": _factory_data.size(),
		"is_visible": is_visible(),
		"overview": _overview_display.get_summary(),
		"heat": _heat_display.get_summary(),
		"queue": _queue_ui.get_summary()
	}
