class_name FactoryOverviewDisplay
extends RefCounted
## FactoryOverviewDisplay shows all faction factories in a scrollable list.

signal factory_selected(factory_id: int)
signal display_updated()

## Current faction
var _current_faction_id: String = ""

## Factory panels
var _panels: Dictionary = {}  ## factory_id -> FactoryPanel

## UI components
var _scroll_container: ScrollContainer = null
var _panel_container: VBoxContainer = null
var _header_label: Label = null
var _empty_label: Label = null

## Parent reference
var _parent_node: Control = null


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control) -> Control:
	_parent_node = parent

	# Main scroll container
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "FactoryOverviewScroll"
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Panel container (VBoxContainer for vertical stacking)
	_panel_container = VBoxContainer.new()
	_panel_container.name = "PanelContainer"
	_panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Header
	_header_label = Label.new()
	_header_label.name = "HeaderLabel"
	_header_label.text = "Factory Overview"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 20)
	_panel_container.add_child(_header_label)

	# Separator
	var sep := HSeparator.new()
	_panel_container.add_child(sep)

	# Empty state label
	_empty_label = Label.new()
	_empty_label.name = "EmptyLabel"
	_empty_label.text = "No factories"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_empty_label.visible = true
	_panel_container.add_child(_empty_label)

	_scroll_container.add_child(_panel_container)
	parent.add_child(_scroll_container)

	return _scroll_container


## Set current faction and refresh display.
func set_faction(faction_id: String) -> void:
	if _current_faction_id == faction_id:
		return

	# Clear existing panels
	_clear_all_panels()

	_current_faction_id = faction_id

	if _header_label != null:
		_header_label.text = "Factory Overview - %s" % faction_id

	_update_empty_state()


## Add a factory to the display.
func add_factory(factory_id: int, factory_name: String, factory_type: String, faction_id: String) -> FactoryPanel:
	if faction_id != _current_faction_id:
		return null

	if _panels.has(factory_id):
		return _panels[factory_id]

	var panel := FactoryPanel.new()
	panel.initialize(factory_id, factory_name, factory_type, faction_id)
	panel.create_ui(_panel_container)

	# Connect selection signal
	panel.factory_selected.connect(_on_factory_selected)

	_panels[factory_id] = panel

	_update_empty_state()

	return panel


## Remove a factory from the display.
func remove_factory(factory_id: int) -> void:
	if not _panels.has(factory_id):
		return

	var panel: FactoryPanel = _panels[factory_id]
	panel.cleanup()

	_panels.erase(factory_id)

	_update_empty_state()


## Update factory health.
func update_factory_health(factory_id: int, current: float, max_health: float) -> void:
	if _panels.has(factory_id):
		_panels[factory_id].update_health(current, max_health)


## Update factory heat.
func update_factory_heat(factory_id: int, heat_percentage: float) -> void:
	if _panels.has(factory_id):
		_panels[factory_id].update_heat(heat_percentage)


## Update factory production queue.
func update_factory_queue(factory_id: int, queue: Array) -> void:
	if _panels.has(factory_id):
		_panels[factory_id].update_production_queue(queue)


## Update all factory data at once.
func update_factory(factory_id: int, health_current: float, health_max: float, heat: float, queue: Array) -> void:
	if not _panels.has(factory_id):
		return

	var panel: FactoryPanel = _panels[factory_id]
	panel.update_health(health_current, health_max)
	panel.update_heat(heat)
	panel.update_production_queue(queue)

	display_updated.emit()


## Populate from factory manager data.
func populate_from_data(factories: Array) -> void:
	# factories: Array of {id, name, type, faction, health, health_max, heat, queue}

	for factory_data in factories:
		var factory_id: int = factory_data.get("id", -1)
		var faction: String = factory_data.get("faction", "")

		if faction != _current_faction_id:
			continue

		if not _panels.has(factory_id):
			add_factory(
				factory_id,
				factory_data.get("name", "Factory %d" % factory_id),
				factory_data.get("type", "Standard"),
				faction
			)

		update_factory(
			factory_id,
			factory_data.get("health", 100.0),
			factory_data.get("health_max", 100.0),
			factory_data.get("heat", 0.0),
			factory_data.get("queue", [])
		)


## Clear all panels for faction switch.
func _clear_all_panels() -> void:
	for factory_id in _panels.keys():
		var panel: FactoryPanel = _panels[factory_id]
		panel.cleanup()

	_panels.clear()


## Update empty state visibility.
func _update_empty_state() -> void:
	if _empty_label != null:
		_empty_label.visible = _panels.is_empty()


## Handle factory selection from panel.
func _on_factory_selected(factory_id: int) -> void:
	factory_selected.emit(factory_id)


## Get panel for factory.
func get_panel(factory_id: int) -> FactoryPanel:
	return _panels.get(factory_id)


## Get all factory IDs in display.
func get_displayed_factory_ids() -> Array[int]:
	var ids: Array[int] = []
	for factory_id in _panels:
		ids.append(factory_id)
	return ids


## Get factory count.
func get_factory_count() -> int:
	return _panels.size()


## Get current faction.
func get_current_faction() -> String:
	return _current_faction_id


## Set display visibility.
func set_visible(visible: bool) -> void:
	if _scroll_container != null:
		_scroll_container.visible = visible


## Check if visible.
func is_visible() -> bool:
	if _scroll_container != null:
		return _scroll_container.visible
	return false


## Cleanup all resources.
func cleanup() -> void:
	_clear_all_panels()

	if _scroll_container != null and is_instance_valid(_scroll_container):
		_scroll_container.queue_free()

	_scroll_container = null
	_panel_container = null
	_header_label = null
	_empty_label = null


## Get summary for debugging.
func get_summary() -> Dictionary:
	var panel_summaries: Array = []
	for factory_id in _panels:
		panel_summaries.append(_panels[factory_id].get_summary())

	return {
		"current_faction": _current_faction_id,
		"factory_count": _panels.size(),
		"is_visible": is_visible(),
		"panels": panel_summaries
	}
