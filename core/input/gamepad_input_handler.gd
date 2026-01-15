class_name GamepadInputHandler
extends RefCounted
## GamepadInputHandler captures joypad events and converts to game commands.
## Supports multiple gamepads with context-sensitive button mapping.

signal command_issued(command: Dictionary)
signal gamepad_connected(device_id: int)
signal gamepad_disconnected(device_id: int)
signal button_pressed(device_id: int, button: int)
signal button_released(device_id: int, button: int)
signal bindings_changed(faction_id: int)

## Button constants (JOY_BUTTON enum values)
const BTN_A := JOY_BUTTON_A
const BTN_B := JOY_BUTTON_B
const BTN_X := JOY_BUTTON_X
const BTN_Y := JOY_BUTTON_Y
const BTN_LB := JOY_BUTTON_LEFT_SHOULDER
const BTN_RB := JOY_BUTTON_RIGHT_SHOULDER
const BTN_LT := JOY_BUTTON_INVALID  ## Triggers handled as axes
const BTN_RT := JOY_BUTTON_INVALID
const BTN_BACK := JOY_BUTTON_BACK
const BTN_START := JOY_BUTTON_START
const BTN_LSTICK := JOY_BUTTON_LEFT_STICK
const BTN_RSTICK := JOY_BUTTON_RIGHT_STICK
const BTN_DPAD_UP := JOY_BUTTON_DPAD_UP
const BTN_DPAD_DOWN := JOY_BUTTON_DPAD_DOWN
const BTN_DPAD_LEFT := JOY_BUTTON_DPAD_LEFT
const BTN_DPAD_RIGHT := JOY_BUTTON_DPAD_RIGHT

## Trigger axes
const AXIS_LT := JOY_AXIS_TRIGGER_LEFT
const AXIS_RT := JOY_AXIS_TRIGGER_RIGHT
const TRIGGER_THRESHOLD := 0.5

## Configuration
const INPUT_BUFFER_TIME := 0.1       ## 100ms buffer for rapid inputs
const RAPID_INPUT_THRESHOLD := 0.05  ## 50ms for rapid fire detection
const MAX_CONNECTED_GAMEPADS := 4

## Connected gamepads
var _connected_gamepads: Dictionary = {}  ## device_id -> {name, guid, player_idx}
var _primary_gamepad := -1

## Button mappings
var _button_map: GamepadButtonMap = null
var _current_faction_id := 0

## Input state
var _button_states: Dictionary = {}       ## device_id -> {button -> is_pressed}
var _button_press_times: Dictionary = {}  ## device_id -> {button -> press_time}
var _trigger_states: Dictionary = {}      ## device_id -> {axis -> value}

## Context
var _current_context := "default"
var _modifier_held := false  ## LB/RB held for modifier combos

## Command queue reference
var _command_queue = null

## Persistence
const SAVE_PATH := "user://gamepad_bindings.json"


func _init() -> void:
	_button_map = GamepadButtonMap.new()
	_load_bindings()


## Initialize with command queue.
func initialize(command_queue = null) -> void:
	_command_queue = command_queue
	_scan_connected_gamepads()


## Scan for connected gamepads.
func _scan_connected_gamepads() -> void:
	_connected_gamepads.clear()

	for device_id in Input.get_connected_joypads():
		_register_gamepad(device_id)

	# Set primary gamepad
	if not _connected_gamepads.is_empty():
		_primary_gamepad = _connected_gamepads.keys()[0]


## Register a gamepad.
func _register_gamepad(device_id: int) -> void:
	_connected_gamepads[device_id] = {
		"name": Input.get_joy_name(device_id),
		"guid": Input.get_joy_guid(device_id),
		"player_idx": _connected_gamepads.size()
	}

	_button_states[device_id] = {}
	_button_press_times[device_id] = {}
	_trigger_states[device_id] = {AXIS_LT: 0.0, AXIS_RT: 0.0}

	if _primary_gamepad < 0:
		_primary_gamepad = device_id

	gamepad_connected.emit(device_id)


## Handle gamepad connection.
func on_gamepad_connected(device_id: int) -> void:
	if not _connected_gamepads.has(device_id):
		_register_gamepad(device_id)


## Handle gamepad disconnection.
func on_gamepad_disconnected(device_id: int) -> void:
	if _connected_gamepads.has(device_id):
		_connected_gamepads.erase(device_id)
		_button_states.erase(device_id)
		_button_press_times.erase(device_id)
		_trigger_states.erase(device_id)

		# Update primary if needed
		if device_id == _primary_gamepad:
			if not _connected_gamepads.is_empty():
				_primary_gamepad = _connected_gamepads.keys()[0]
			else:
				_primary_gamepad = -1

		gamepad_disconnected.emit(device_id)


## Process input event.
func process_input(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return _handle_button_event(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		return _handle_axis_event(event as InputEventJoypadMotion)
	return false


## Handle button event.
func _handle_button_event(event: InputEventJoypadButton) -> bool:
	var device_id := event.device
	var button := event.button_index
	var pressed := event.pressed

	# Ensure device is registered
	if not _connected_gamepads.has(device_id):
		_register_gamepad(device_id)

	# Update button state
	if not _button_states.has(device_id):
		_button_states[device_id] = {}
	_button_states[device_id][button] = pressed

	# Track press time for rapid input
	if pressed:
		if not _button_press_times.has(device_id):
			_button_press_times[device_id] = {}
		_button_press_times[device_id][button] = Time.get_ticks_msec()
		button_pressed.emit(device_id, button)
	else:
		button_released.emit(device_id, button)

	# Check for modifier buttons
	if button == BTN_LB or button == BTN_RB:
		_modifier_held = pressed
		return true  ## Consume modifier buttons

	# Convert to command
	if pressed:
		return _process_button_press(device_id, button)

	return false


## Handle axis event (triggers).
func _handle_axis_event(event: InputEventJoypadMotion) -> bool:
	var device_id := event.device
	var axis := event.axis
	var value := event.axis_value

	if axis != AXIS_LT and axis != AXIS_RT:
		return false  ## Only handle triggers here

	if not _trigger_states.has(device_id):
		_trigger_states[device_id] = {}

	var prev_value: float = _trigger_states[device_id].get(axis, 0.0)
	_trigger_states[device_id][axis] = value

	# Check for trigger press (crossed threshold)
	var was_pressed := prev_value >= TRIGGER_THRESHOLD
	var is_pressed := value >= TRIGGER_THRESHOLD

	if is_pressed and not was_pressed:
		return _process_trigger_press(device_id, axis)

	return false


## Process button press and generate command.
func _process_button_press(device_id: int, button: int) -> bool:
	# Get command for this button in current context
	var command := _button_map.get_command_for_button(
		button,
		_current_faction_id,
		_current_context,
		_modifier_held
	)

	if command.is_empty():
		return false

	# Check for rapid input
	var is_rapid := _check_rapid_input(device_id, button)

	# Build command data
	var command_data := {
		"type": command.get("type", "ability"),
		"action": command.get("action", ""),
		"faction_id": _current_faction_id,
		"source": "gamepad",
		"device_id": device_id,
		"is_rapid": is_rapid,
		"timestamp": Time.get_ticks_msec()
	}

	# Add optional parameters
	if command.has("ability_id"):
		command_data["ability_id"] = command["ability_id"]
	if command.has("target_type"):
		command_data["target_type"] = command["target_type"]

	# Issue command
	command_issued.emit(command_data)

	# Send to command queue if available
	if _command_queue != null:
		_command_queue.queue_command(command_data)

	return true


## Process trigger press.
func _process_trigger_press(device_id: int, axis: int) -> bool:
	# Map trigger to virtual button
	var virtual_button := -1
	if axis == AXIS_LT:
		virtual_button = 100  ## Virtual LT button
	elif axis == AXIS_RT:
		virtual_button = 101  ## Virtual RT button

	if virtual_button >= 0:
		return _process_button_press(device_id, virtual_button)

	return false


## Check for rapid input.
func _check_rapid_input(device_id: int, button: int) -> bool:
	if not _button_press_times.has(device_id):
		return false

	var press_times: Dictionary = _button_press_times[device_id]
	if not press_times.has(button):
		return false

	var last_press: int = press_times[button]
	var current_time := Time.get_ticks_msec()
	var delta := (current_time - last_press) / 1000.0

	return delta < RAPID_INPUT_THRESHOLD


## Set current faction.
func set_faction(faction_id: int) -> void:
	if faction_id != _current_faction_id:
		_current_faction_id = faction_id
		bindings_changed.emit(faction_id)


## Set current context.
func set_context(context: String) -> void:
	_current_context = context


## Get available contexts.
func get_contexts() -> Array[String]:
	return ["default", "combat", "building", "menu", "pause"]


## Set button binding.
func set_binding(button: int, action: String, faction_id: int = -1,
				 context: String = "default", with_modifier: bool = false) -> void:
	if faction_id < 0:
		faction_id = _current_faction_id

	_button_map.set_binding(button, action, faction_id, context, with_modifier)
	_save_bindings()


## Clear button binding.
func clear_binding(button: int, faction_id: int = -1,
				   context: String = "default", with_modifier: bool = false) -> void:
	if faction_id < 0:
		faction_id = _current_faction_id

	_button_map.clear_binding(button, faction_id, context, with_modifier)
	_save_bindings()


## Reset to default bindings.
func reset_to_defaults(faction_id: int = -1) -> void:
	if faction_id < 0:
		_button_map.reset_all_to_defaults()
	else:
		_button_map.reset_faction_to_defaults(faction_id)
	_save_bindings()


## Get all bindings for faction.
func get_faction_bindings(faction_id: int) -> Dictionary:
	return _button_map.get_faction_bindings(faction_id)


## Check for binding conflicts.
func check_for_conflicts(button: int, faction_id: int, context: String,
						 with_modifier: bool) -> Array[String]:
	return _button_map.check_conflicts(button, faction_id, context, with_modifier)


## Validate bindings.
func validate_bindings() -> Array[String]:
	return _button_map.validate_all_bindings()


## Get button name for display.
static func get_button_name(button: int) -> String:
	match button:
		BTN_A: return "A"
		BTN_B: return "B"
		BTN_X: return "X"
		BTN_Y: return "Y"
		BTN_LB: return "LB"
		BTN_RB: return "RB"
		BTN_BACK: return "Back"
		BTN_START: return "Start"
		BTN_LSTICK: return "L3"
		BTN_RSTICK: return "R3"
		BTN_DPAD_UP: return "D-Up"
		BTN_DPAD_DOWN: return "D-Down"
		BTN_DPAD_LEFT: return "D-Left"
		BTN_DPAD_RIGHT: return "D-Right"
		100: return "LT"
		101: return "RT"
	return "Unknown"


## Is gamepad connected.
func is_gamepad_connected() -> bool:
	return not _connected_gamepads.is_empty()


## Get connected gamepad count.
func get_connected_count() -> int:
	return _connected_gamepads.size()


## Get primary gamepad device ID.
func get_primary_gamepad() -> int:
	return _primary_gamepad


## Set primary gamepad.
func set_primary_gamepad(device_id: int) -> void:
	if _connected_gamepads.has(device_id):
		_primary_gamepad = device_id


## Get gamepad info.
func get_gamepad_info(device_id: int) -> Dictionary:
	return _connected_gamepads.get(device_id, {})


## Get all connected gamepads.
func get_connected_gamepads() -> Array[int]:
	var result: Array[int] = []
	for id in _connected_gamepads:
		result.append(id)
	return result


## Is button pressed.
func is_button_pressed(device_id: int, button: int) -> bool:
	if not _button_states.has(device_id):
		return false
	return _button_states[device_id].get(button, false)


## Is trigger pressed.
func is_trigger_pressed(device_id: int, axis: int) -> bool:
	if not _trigger_states.has(device_id):
		return false
	return _trigger_states[device_id].get(axis, 0.0) >= TRIGGER_THRESHOLD


## Get trigger value.
func get_trigger_value(device_id: int, axis: int) -> float:
	if not _trigger_states.has(device_id):
		return 0.0
	return _trigger_states[device_id].get(axis, 0.0)


## Save bindings to file.
func _save_bindings() -> void:
	var data := _button_map.to_dict()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


## Load bindings from file.
func _load_bindings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var json_string := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_string)
	if parsed is Dictionary:
		_button_map.from_dict(parsed)


## Get status.
func get_status() -> Dictionary:
	return {
		"connected_gamepads": _connected_gamepads.size(),
		"primary_gamepad": _primary_gamepad,
		"current_faction": _current_faction_id,
		"current_context": _current_context,
		"modifier_held": _modifier_held
	}
