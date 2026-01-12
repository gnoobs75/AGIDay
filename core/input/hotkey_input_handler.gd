class_name HotkeyInputHandler
extends RefCounted
## HotkeyInputHandler captures keyboard input and creates commands.

signal hotkey_pressed(faction_id: String, ability_id: String, key: String)
signal command_created(command: Command)
signal targeting_started(ability_id: String)
signal targeting_cancelled()
signal target_selected(position: Vector3)

## Hotkey bindings
var _bindings: HotkeyBindings = null

## Command queue reference
var _command_queue: CommandQueue = null

## Active faction
var active_faction: String = ""

## Current frame number
var _current_frame: int = 0

## Targeting mode
var _targeting_ability: String = ""
var _is_targeting: bool = false

## Input buffer (for rapid inputs)
var _input_buffer: Array[Dictionary] = []
var _buffer_window: float = 0.05  ## 50ms buffer

## Key states for detecting press vs hold
var _key_states: Dictionary = {}

## Selected units callback () -> Array[int]
var _selected_units_callback: Callable

## Mouse world position callback () -> Vector3
var _mouse_position_callback: Callable


func _init() -> void:
	_bindings = HotkeyBindings.new()


## Set command queue.
func set_command_queue(queue: CommandQueue) -> void:
	_command_queue = queue


## Get bindings.
func get_bindings() -> HotkeyBindings:
	return _bindings


## Set selected units callback.
func set_selected_units_callback(callback: Callable) -> void:
	_selected_units_callback = callback


## Set mouse position callback.
func set_mouse_position_callback(callback: Callable) -> void:
	_mouse_position_callback = callback


## Process key input event.
func process_key_input(keycode: int, pressed: bool) -> bool:
	var key := _keycode_to_string(keycode)
	if key.is_empty():
		return false

	# Track key state
	var was_pressed: bool = _key_states.get(key, false)
	_key_states[key] = pressed

	# Only process on key down (not repeat or release)
	if not pressed or was_pressed:
		return false

	return _handle_key_press(key)


## Handle key press.
func _handle_key_press(key: String) -> bool:
	# Check if in targeting mode
	if _is_targeting:
		if key == "Escape":
			_cancel_targeting()
			return true
		return false

	# Check common bindings first
	var common_ability := _bindings.get_common_ability_for_key(key)
	if not common_ability.is_empty():
		return _execute_common_ability(common_ability)

	# Check faction bindings
	if active_faction.is_empty():
		return false

	var ability_id := _bindings.get_ability_for_key(active_faction, key)
	if ability_id.is_empty():
		return false

	hotkey_pressed.emit(active_faction, ability_id, key)

	# Add to input buffer
	_input_buffer.append({
		"ability_id": ability_id,
		"timestamp": Time.get_ticks_msec()
	})

	# Create command or start targeting
	return _process_ability(ability_id)


## Process ability activation.
func _process_ability(ability_id: String) -> bool:
	# Check if ability requires targeting
	if _requires_targeting(ability_id):
		_start_targeting(ability_id)
		return true

	# Create immediate command
	var command := Command.create_ability(
		-1,  # ID assigned by queue
		ability_id,
		active_faction,
		_current_frame
	)

	# Add selected units
	command.selected_units = _get_selected_units()

	return _queue_command(command)


## Execute common ability.
func _execute_common_ability(ability_id: String) -> bool:
	var command := Command.new()
	command.faction_id = active_faction
	command.frame_number = _current_frame

	match ability_id:
		"stop_units":
			command.command_type = Command.CommandType.STOP
			command.selected_units = _get_selected_units()
		"select_all":
			# Handled by selection system, not command queue
			return false
		"attack_move":
			_start_targeting("attack_move")
			return true
		_:
			return false

	return _queue_command(command)


## Start targeting mode.
func _start_targeting(ability_id: String) -> void:
	_is_targeting = true
	_targeting_ability = ability_id
	targeting_started.emit(ability_id)


## Cancel targeting mode.
func _cancel_targeting() -> void:
	_is_targeting = false
	_targeting_ability = ""
	targeting_cancelled.emit()


## Process mouse click for targeting.
func process_mouse_click(button: int, pressed: bool) -> bool:
	if not _is_targeting or not pressed:
		return false

	if button == 1:  # Left click - confirm target
		var world_pos := _get_mouse_world_position()
		if world_pos != Vector3.INF:
			_confirm_target(world_pos)
			return true

	elif button == 2:  # Right click - cancel
		_cancel_targeting()
		return true

	return false


## Confirm target position.
func _confirm_target(position: Vector3) -> void:
	var ability_id := _targeting_ability
	_cancel_targeting()

	target_selected.emit(position)

	# Create targeted command
	var command: Command

	if ability_id == "attack_move":
		command = Command.create_movement(
			-1,
			active_faction,
			_current_frame,
			position,
			_get_selected_units()
		)
		command.parameters["attack_move"] = true
	else:
		command = Command.create_ability(
			-1,
			ability_id,
			active_faction,
			_current_frame,
			position
		)
		command.selected_units = _get_selected_units()

	_queue_command(command)


## Queue command.
func _queue_command(command: Command) -> bool:
	if _command_queue != null:
		_command_queue.queue_command(command)
		command_created.emit(command)
		return true
	return false


## Check if ability requires targeting.
func _requires_targeting(ability_id: String) -> bool:
	# TODO: Check ability config for target requirement
	var targeting_abilities := [
		"spiral_rally", "line_formation", "charge_formation",
		"cover_formation", "momentum_charge", "attack_move"
	]
	return ability_id in targeting_abilities


## Get selected units via callback.
func _get_selected_units() -> Array[int]:
	if _selected_units_callback.is_valid():
		return _selected_units_callback.call()
	return []


## Get mouse world position via callback.
func _get_mouse_world_position() -> Vector3:
	if _mouse_position_callback.is_valid():
		return _mouse_position_callback.call()
	return Vector3.INF


## Convert keycode to string.
func _keycode_to_string(keycode: int) -> String:
	# Handle letter keys (A-Z)
	if keycode >= 65 and keycode <= 90:
		return char(keycode)

	# Handle number keys (0-9)
	if keycode >= 48 and keycode <= 57:
		return char(keycode)

	# Handle special keys
	match keycode:
		32: return "Space"
		16777217: return "Escape"
		16777218: return "Tab"
		16777220: return "Enter"
		16777221: return "Insert"
		16777222: return "Delete"

	return ""


## Update frame.
func update(frame: int, delta: float) -> void:
	_current_frame = frame

	# Clear old input buffer entries
	var current_time := Time.get_ticks_msec()
	var buffer_ms := int(_buffer_window * 1000)

	while not _input_buffer.is_empty():
		if current_time - _input_buffer[0]["timestamp"] > buffer_ms:
			_input_buffer.pop_front()
		else:
			break


## Check if in targeting mode.
func is_targeting() -> bool:
	return _is_targeting


## Get targeting ability.
func get_targeting_ability() -> String:
	return _targeting_ability


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"active_faction": active_faction,
		"is_targeting": _is_targeting,
		"targeting_ability": _targeting_ability,
		"input_buffer_size": _input_buffer.size(),
		"bindings": _bindings.get_summary()
	}
