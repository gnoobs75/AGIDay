class_name InputContext
extends RefCounted
## InputContext manages context-sensitive input behavior based on game state.
## Adapts input handling to zoom level, camera mode, and UI state.

signal context_changed(context: String)
signal context_stack_changed(stack: Array)

## Context types
enum Context {
	DEFAULT,
	MENU,
	PAUSE,
	STRATEGIC_VIEW,
	TACTICAL_VIEW,
	FACTORY_VIEW,
	BUILDING_PLACEMENT,
	ABILITY_TARGETING,
	CINEMATIC
}

## Context stack (for nested contexts)
var _context_stack: Array[Context] = []
var _current_context := Context.DEFAULT

## Context properties
var _context_properties: Dictionary = {}

## Zoom level thresholds
const ZOOM_STRATEGIC := 0.5   ## Zoomed out - strategic view
const ZOOM_TACTICAL := 1.5    ## Normal - tactical view
## Above 1.5 - close up view

## State references
var _current_zoom := 1.0
var _camera_mode := "free"
var _is_ui_focused := false
var _active_panel := ""


func _init() -> void:
	_setup_context_properties()


## Initialize context manager.
func initialize() -> void:
	_context_stack.append(Context.DEFAULT)
	_current_context = Context.DEFAULT


## Setup properties for each context.
func _setup_context_properties() -> void:
	_context_properties = {
		Context.DEFAULT: {
			"allow_selection": true,
			"allow_commands": true,
			"allow_abilities": true,
			"allow_camera_control": true,
			"allow_hotkeys": true,
			"cursor_mode": "default"
		},
		Context.MENU: {
			"allow_selection": false,
			"allow_commands": false,
			"allow_abilities": false,
			"allow_camera_control": false,
			"allow_hotkeys": false,
			"cursor_mode": "pointer"
		},
		Context.PAUSE: {
			"allow_selection": false,
			"allow_commands": false,
			"allow_abilities": false,
			"allow_camera_control": false,
			"allow_hotkeys": true,  ## Allow unpause hotkey
			"cursor_mode": "pointer"
		},
		Context.STRATEGIC_VIEW: {
			"allow_selection": true,
			"allow_commands": true,
			"allow_abilities": false,  ## No micro at strategic level
			"allow_camera_control": true,
			"allow_hotkeys": true,
			"selection_mode": "group",
			"cursor_mode": "strategic"
		},
		Context.TACTICAL_VIEW: {
			"allow_selection": true,
			"allow_commands": true,
			"allow_abilities": true,
			"allow_camera_control": true,
			"allow_hotkeys": true,
			"selection_mode": "individual",
			"cursor_mode": "tactical"
		},
		Context.FACTORY_VIEW: {
			"allow_selection": false,
			"allow_commands": false,
			"allow_abilities": false,
			"allow_camera_control": false,
			"allow_hotkeys": true,
			"cursor_mode": "factory"
		},
		Context.BUILDING_PLACEMENT: {
			"allow_selection": false,
			"allow_commands": false,
			"allow_abilities": false,
			"allow_camera_control": true,
			"allow_hotkeys": true,
			"cursor_mode": "placement"
		},
		Context.ABILITY_TARGETING: {
			"allow_selection": false,
			"allow_commands": false,
			"allow_abilities": true,
			"allow_camera_control": true,
			"allow_hotkeys": true,
			"cursor_mode": "targeting"
		},
		Context.CINEMATIC: {
			"allow_selection": false,
			"allow_commands": false,
			"allow_abilities": false,
			"allow_camera_control": false,
			"allow_hotkeys": false,
			"cursor_mode": "hidden"
		}
	}


## Push context onto stack.
func push_context(context: Context) -> void:
	_context_stack.append(context)
	_current_context = context
	context_changed.emit(_get_context_name(context))
	context_stack_changed.emit(_get_stack_names())


## Pop context from stack.
func pop_context() -> Context:
	if _context_stack.size() <= 1:
		return _current_context  ## Can't pop default

	var popped := _context_stack.pop_back()
	_current_context = _context_stack.back()
	context_changed.emit(_get_context_name(_current_context))
	context_stack_changed.emit(_get_stack_names())
	return popped


## Set context directly (clears stack).
func set_context(context_name: String) -> void:
	var context := _get_context_from_name(context_name)
	_context_stack.clear()
	_context_stack.append(context)
	_current_context = context
	context_changed.emit(context_name)


## Get current context.
func get_current_context() -> Context:
	return _current_context


## Get current context name.
func get_current_context_name() -> String:
	return _get_context_name(_current_context)


## Update context based on game state.
func update_from_game_state(zoom: float, camera_mode: String, is_paused: bool,
							is_in_menu: bool, active_panel: String) -> void:
	_current_zoom = zoom
	_camera_mode = camera_mode
	_active_panel = active_panel

	# Determine appropriate context
	var new_context := _determine_context(zoom, camera_mode, is_paused, is_in_menu, active_panel)

	if new_context != _current_context:
		# Only auto-switch for non-modal contexts
		if not _is_modal_context(_current_context):
			_context_stack.clear()
			_context_stack.append(new_context)
			_current_context = new_context
			context_changed.emit(_get_context_name(new_context))


## Determine context from game state.
func _determine_context(zoom: float, camera_mode: String, is_paused: bool,
						is_in_menu: bool, active_panel: String) -> Context:
	if is_in_menu:
		return Context.MENU
	if is_paused:
		return Context.PAUSE

	if camera_mode == "factory":
		return Context.FACTORY_VIEW

	if not active_panel.is_empty():
		return Context.MENU

	# Zoom-based context
	if zoom < ZOOM_STRATEGIC:
		return Context.STRATEGIC_VIEW
	elif zoom > ZOOM_TACTICAL:
		return Context.TACTICAL_VIEW

	return Context.DEFAULT


## Check if context is modal (blocks auto-switching).
func _is_modal_context(context: Context) -> bool:
	return context in [
		Context.BUILDING_PLACEMENT,
		Context.ABILITY_TARGETING,
		Context.CINEMATIC
	]


## Get context property.
func get_property(property: String) -> Variant:
	var props: Dictionary = _context_properties.get(_current_context, {})
	return props.get(property, null)


## Is action allowed in current context.
func is_action_allowed(action_type: String) -> bool:
	var props: Dictionary = _context_properties.get(_current_context, {})

	match action_type:
		"selection":
			return props.get("allow_selection", true)
		"command":
			return props.get("allow_commands", true)
		"ability":
			return props.get("allow_abilities", true)
		"camera":
			return props.get("allow_camera_control", true)
		"hotkey":
			return props.get("allow_hotkeys", true)

	return true


## Get cursor mode for current context.
func get_cursor_mode() -> String:
	var props: Dictionary = _context_properties.get(_current_context, {})
	return props.get("cursor_mode", "default")


## Get selection mode for current context.
func get_selection_mode() -> String:
	var props: Dictionary = _context_properties.get(_current_context, {})
	return props.get("selection_mode", "individual")


## Enter building placement mode.
func enter_building_placement() -> void:
	push_context(Context.BUILDING_PLACEMENT)


## Exit building placement mode.
func exit_building_placement() -> void:
	if _current_context == Context.BUILDING_PLACEMENT:
		pop_context()


## Enter ability targeting mode.
func enter_ability_targeting() -> void:
	push_context(Context.ABILITY_TARGETING)


## Exit ability targeting mode.
func exit_ability_targeting() -> void:
	if _current_context == Context.ABILITY_TARGETING:
		pop_context()


## Enter cinematic mode.
func enter_cinematic() -> void:
	push_context(Context.CINEMATIC)


## Exit cinematic mode.
func exit_cinematic() -> void:
	if _current_context == Context.CINEMATIC:
		pop_context()


## Get context name.
func _get_context_name(context: Context) -> String:
	match context:
		Context.DEFAULT: return "default"
		Context.MENU: return "menu"
		Context.PAUSE: return "pause"
		Context.STRATEGIC_VIEW: return "strategic"
		Context.TACTICAL_VIEW: return "tactical"
		Context.FACTORY_VIEW: return "factory"
		Context.BUILDING_PLACEMENT: return "building_placement"
		Context.ABILITY_TARGETING: return "ability_targeting"
		Context.CINEMATIC: return "cinematic"
	return "unknown"


## Get context from name.
func _get_context_from_name(name: String) -> Context:
	match name:
		"default": return Context.DEFAULT
		"menu": return Context.MENU
		"pause": return Context.PAUSE
		"strategic": return Context.STRATEGIC_VIEW
		"tactical": return Context.TACTICAL_VIEW
		"factory": return Context.FACTORY_VIEW
		"building_placement": return Context.BUILDING_PLACEMENT
		"ability_targeting": return Context.ABILITY_TARGETING
		"cinematic": return Context.CINEMATIC
	return Context.DEFAULT


## Get stack names.
func _get_stack_names() -> Array[String]:
	var names: Array[String] = []
	for context in _context_stack:
		names.append(_get_context_name(context))
	return names


## Get all context properties for display.
func get_all_properties() -> Dictionary:
	return _context_properties.get(_current_context, {})


## Get status.
func get_status() -> Dictionary:
	return {
		"current_context": _get_context_name(_current_context),
		"context_stack": _get_stack_names(),
		"zoom": _current_zoom,
		"camera_mode": _camera_mode,
		"active_panel": _active_panel,
		"allow_selection": is_action_allowed("selection"),
		"allow_commands": is_action_allowed("command"),
		"allow_abilities": is_action_allowed("ability"),
		"cursor_mode": get_cursor_mode()
	}
