class_name HUDSystem
extends RefCounted
## HUDSystem manages adaptive HUD layouts based on camera zoom and mode.
## Transitions smoothly between strategic, tactical, and factory views.

signal layout_changed(layout: HUDLayout)
signal panel_visibility_changed(panel_id: String, visible: bool)
signal hud_ready()

## HUD layout modes
enum HUDLayout {
	STRATEGIC,   ## God-view: full info HUD
	TACTICAL,    ## Mid-range: simplified HUD
	FACTORY      ## Close-up: minimal/production focused
}

## Zoom thresholds for layout switching
const STRATEGIC_THRESHOLD := 0.3   ## Below this = strategic
const FACTORY_THRESHOLD := 0.7     ## Above this = factory

## Animation timings
const LAYOUT_TRANSITION_TIME := 0.3
const PANEL_FADE_TIME := 0.2

## Panel styling constants
const PANEL_BG_COLOR := Color("#2d2d2d", 0.7)
const PANEL_CORNER_RADIUS := 4
const PANEL_PADDING := 8
const PANEL_MARGIN := 8

## UI Framework reference
var _ui_framework: UIFramework = null

## Panel instances
var _resource_panel: ResourcePanel = null
var _research_panel: ResearchPanel = null
var _hotkeys_panel: HotkeysPanel = null
var _objective_panel: ObjectivePanel = null
var _production_panel: ProductionQueuePanel = null

## Current state
var _current_layout := HUDLayout.STRATEGIC
var _current_zoom := 0.0
var _is_transitioning := false

## Panel containers
var _hud_container: Control = null
var _panel_nodes: Dictionary = {}  ## panel_id -> Control

## Visibility state per layout
var _layout_visibility := {
	HUDLayout.STRATEGIC: {
		"resource": true,
		"research": true,
		"hotkeys": true,
		"objective": false,
		"production": false
	},
	HUDLayout.TACTICAL: {
		"resource": true,
		"research": false,
		"hotkeys": false,
		"objective": true,
		"production": false
	},
	HUDLayout.FACTORY: {
		"resource": false,
		"research": false,
		"hotkeys": false,
		"objective": false,
		"production": true
	}
}


func _init() -> void:
	# Create panel managers
	_resource_panel = ResourcePanel.new()
	_research_panel = ResearchPanel.new()
	_hotkeys_panel = HotkeysPanel.new()
	_objective_panel = ObjectivePanel.new()
	_production_panel = ProductionQueuePanel.new()


## Initialize with UI framework.
func initialize(ui_framework: UIFramework, parent: Control) -> void:
	_ui_framework = ui_framework
	_create_hud_container(parent)
	_create_panels()
	_apply_layout(_current_layout, false)
	hud_ready.emit()


## Create the main HUD container.
func _create_hud_container(parent: Control) -> void:
	_hud_container = Control.new()
	_hud_container.name = "HUDContainer"
	_hud_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_hud_container)


## Create all panel UI nodes.
func _create_panels() -> void:
	var faction := _ui_framework.get_faction() if _ui_framework != null else "neutral"

	# Resource panel - top left
	var resource_node := _resource_panel.create_ui(_hud_container, faction)
	resource_node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	resource_node.position = Vector2(PANEL_MARGIN, PANEL_MARGIN)
	_panel_nodes["resource"] = resource_node

	# Research panel - below resource
	var research_node := _research_panel.create_ui(_hud_container, faction)
	research_node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	research_node.position = Vector2(PANEL_MARGIN, PANEL_MARGIN + 120)
	_panel_nodes["research"] = research_node

	# Hotkeys panel - bottom center
	var hotkeys_node := _hotkeys_panel.create_ui(_hud_container, faction)
	hotkeys_node.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotkeys_node.position.y = -PANEL_MARGIN - 80
	_panel_nodes["hotkeys"] = hotkeys_node

	# Objective panel - top center (for tactical view)
	var objective_node := _objective_panel.create_ui(_hud_container, faction)
	objective_node.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective_node.position.y = PANEL_MARGIN
	_panel_nodes["objective"] = objective_node

	# Production panel - right side (for factory view)
	var production_node := _production_panel.create_ui(_hud_container, faction)
	production_node.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	production_node.position.x = -PANEL_MARGIN - 280
	_panel_nodes["production"] = production_node


## Update HUD based on zoom level.
func update_zoom(zoom_level: float) -> void:
	_current_zoom = zoom_level

	var new_layout: HUDLayout
	if zoom_level < STRATEGIC_THRESHOLD:
		new_layout = HUDLayout.STRATEGIC
	elif zoom_level > FACTORY_THRESHOLD:
		new_layout = HUDLayout.FACTORY
	else:
		new_layout = HUDLayout.TACTICAL

	if new_layout != _current_layout:
		_transition_to_layout(new_layout)


## Transition to a new layout.
func _transition_to_layout(new_layout: HUDLayout) -> void:
	if _is_transitioning:
		return

	var old_layout := _current_layout
	_current_layout = new_layout
	_is_transitioning = true

	_apply_layout(new_layout, true)

	# Reset transitioning flag after animation
	var timer := Timer.new()
	timer.wait_time = LAYOUT_TRANSITION_TIME
	timer.one_shot = true
	timer.timeout.connect(func():
		_is_transitioning = false
		timer.queue_free()
	)
	_hud_container.add_child(timer)
	timer.start()

	layout_changed.emit(new_layout)


## Apply layout visibility settings.
func _apply_layout(layout: HUDLayout, animate: bool) -> void:
	var visibility: Dictionary = _layout_visibility[layout]

	for panel_id in visibility:
		var should_show: bool = visibility[panel_id]
		_set_panel_visibility(panel_id, should_show, animate)


## Set panel visibility with optional animation.
func _set_panel_visibility(panel_id: String, visible: bool, animate: bool) -> void:
	if not _panel_nodes.has(panel_id):
		return

	var panel: Control = _panel_nodes[panel_id]
	var current_visible := panel.visible and panel.modulate.a > 0.5

	if current_visible == visible:
		return

	if animate and _ui_framework != null:
		if visible:
			_ui_framework.components.fade_in(panel, PANEL_FADE_TIME)
		else:
			_ui_framework.components.fade_out(panel, PANEL_FADE_TIME, true)
	else:
		panel.visible = visible
		panel.modulate.a = 1.0 if visible else 0.0

	panel_visibility_changed.emit(panel_id, visible)


## Update resource display.
func update_resources(ree: float, power: float, power_max: float) -> void:
	_resource_panel.update_resources(ree, power, power_max)


## Update research display.
func update_research(tech_level: int, current_tech: String, progress: float) -> void:
	_research_panel.update_research(tech_level, current_tech, progress)


## Update hotkey display.
func update_hotkeys(abilities: Array[Dictionary]) -> void:
	_hotkeys_panel.update_abilities(abilities)


## Update objective display.
func update_objective(objective_text: String, progress: float = -1.0) -> void:
	_objective_panel.update_objective(objective_text, progress)


## Update production display.
func update_production(queue: Array[Dictionary], current_progress: float) -> void:
	_production_panel.update_queue(queue, current_progress)


## Force show/hide a specific panel.
func set_panel_override(panel_id: String, visible: bool) -> void:
	_set_panel_visibility(panel_id, visible, true)


## Get current layout.
func get_current_layout() -> HUDLayout:
	return _current_layout


## Get current layout name.
func get_layout_name() -> String:
	match _current_layout:
		HUDLayout.STRATEGIC: return "Strategic"
		HUDLayout.TACTICAL: return "Tactical"
		HUDLayout.FACTORY: return "Factory"
		_: return "Unknown"


## Check if panel is visible.
func is_panel_visible(panel_id: String) -> bool:
	if not _panel_nodes.has(panel_id):
		return false
	var panel: Control = _panel_nodes[panel_id]
	return panel.visible and panel.modulate.a > 0.5


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_resource_panel.apply_faction_theme(faction_id)
	_research_panel.apply_faction_theme(faction_id)
	_hotkeys_panel.apply_faction_theme(faction_id)
	_objective_panel.apply_faction_theme(faction_id)
	_production_panel.apply_faction_theme(faction_id)


## Get panel by ID.
func get_panel(panel_id: String) -> Control:
	return _panel_nodes.get(panel_id)


## Get resource panel for direct access.
func get_resource_panel() -> ResourcePanel:
	return _resource_panel


## Get production panel for direct access.
func get_production_panel() -> ProductionQueuePanel:
	return _production_panel


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"current_layout": _current_layout,
		"current_zoom": _current_zoom
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	if data.has("current_layout"):
		_current_layout = data["current_layout"] as HUDLayout
		_apply_layout(_current_layout, false)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"current_layout": get_layout_name(),
		"current_zoom": _current_zoom,
		"is_transitioning": _is_transitioning,
		"visible_panels": _get_visible_panel_count(),
		"total_panels": _panel_nodes.size()
	}


## Count visible panels.
func _get_visible_panel_count() -> int:
	var count := 0
	for panel in _panel_nodes.values():
		if panel.visible and panel.modulate.a > 0.5:
			count += 1
	return count


## Cleanup.
func cleanup() -> void:
	for panel in _panel_nodes.values():
		if is_instance_valid(panel):
			panel.queue_free()
	_panel_nodes.clear()

	if _hud_container != null and is_instance_valid(_hud_container):
		_hud_container.queue_free()
	_hud_container = null
