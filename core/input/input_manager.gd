class_name InputManager
extends RefCounted
## InputManager orchestrates hybrid keyboard, mouse, and gamepad input.
## Provides context-sensitive input handling with full customization.

signal input_action_triggered(action: String, input_type: String)
signal context_changed(context: String)
signal input_mode_changed(mode: String)
signal binding_changed(action: String, binding: Dictionary)

## Input types
enum InputType {
	KEYBOARD,
	MOUSE,
	GAMEPAD,
	UNKNOWN
}

## Input modes
enum InputMode {
	HYBRID,          ## All inputs active
	KEYBOARD_MOUSE,  ## K+M only
	GAMEPAD_ONLY     ## Gamepad only
}

## Sub-systems
var _hotkey_manager: HotkeyManager = null
var _gamepad_handler: GamepadInputHandler = null
var _mouse_handler: MouseInputHandler = null
var _input_context: InputContext = null

## State
var _current_mode := InputMode.HYBRID
var _current_context := "default"
var _current_faction_id := 0
var _is_initialized := false

## Last input tracking
var _last_input_type := InputType.UNKNOWN
var _last_input_time := 0

## Input enabled state
var _keyboard_enabled := true
var _mouse_enabled := true
var _gamepad_enabled := true

## Settings
var _settings: InputSettings = null


func _init() -> void:
	_settings = InputSettings.new()


## Initialize input system.
func initialize() -> void:
	# Create sub-systems
	_hotkey_manager = HotkeyManager.new()
	_hotkey_manager.initialize()

	_gamepad_handler = GamepadInputHandler.new()
	_gamepad_handler.initialize()

	_mouse_handler = MouseInputHandler.new()
	_mouse_handler.initialize()

	_input_context = InputContext.new()
	_input_context.initialize()

	# Connect signals
	_hotkey_manager.hotkey_triggered.connect(_on_hotkey_triggered)
	_gamepad_handler.command_issued.connect(_on_gamepad_command)
	_mouse_handler.mouse_action.connect(_on_mouse_action)
	_input_context.context_changed.connect(_on_context_changed)

	# Load settings
	_settings.load_settings()
	_apply_settings()

	_is_initialized = true


## Process input event.
func process_input(event: InputEvent) -> bool:
	if not _is_initialized:
		return false

	var handled := false

	# Determine input type
	var input_type := _get_input_type(event)
	if input_type != InputType.UNKNOWN:
		_last_input_type = input_type
		_last_input_time = Time.get_ticks_msec()

	# Check if input type is enabled
	if not _is_input_type_enabled(input_type):
		return false

	# Route to appropriate handler
	match input_type:
		InputType.KEYBOARD:
			if _keyboard_enabled:
				handled = _hotkey_manager.process_input(event)
		InputType.MOUSE:
			if _mouse_enabled:
				handled = _mouse_handler.process_input(event)
		InputType.GAMEPAD:
			if _gamepad_enabled:
				handled = _gamepad_handler.process_input(event)

	return handled


## Get input type from event.
func _get_input_type(event: InputEvent) -> InputType:
	if event is InputEventKey:
		return InputType.KEYBOARD
	elif event is InputEventMouse or event is InputEventMouseButton or event is InputEventMouseMotion:
		return InputType.MOUSE
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return InputType.GAMEPAD
	return InputType.UNKNOWN


## Check if input type is enabled.
func _is_input_type_enabled(input_type: InputType) -> bool:
	match _current_mode:
		InputMode.HYBRID:
			match input_type:
				InputType.KEYBOARD: return _keyboard_enabled
				InputType.MOUSE: return _mouse_enabled
				InputType.GAMEPAD: return _gamepad_enabled
		InputMode.KEYBOARD_MOUSE:
			return input_type == InputType.KEYBOARD or input_type == InputType.MOUSE
		InputMode.GAMEPAD_ONLY:
			return input_type == InputType.GAMEPAD
	return false


## Handle hotkey triggered.
func _on_hotkey_triggered(action: String, modifiers: int) -> void:
	input_action_triggered.emit(action, "keyboard")


## Handle gamepad command.
func _on_gamepad_command(command: Dictionary) -> void:
	var action: String = command.get("action", "")
	input_action_triggered.emit(action, "gamepad")


## Handle mouse action.
func _on_mouse_action(action: String, data: Dictionary) -> void:
	input_action_triggered.emit(action, "mouse")


## Handle context change.
func _on_context_changed(context: String) -> void:
	_current_context = context
	context_changed.emit(context)

	# Update sub-systems
	_hotkey_manager.set_context(context)
	_gamepad_handler.set_context(context)


## Update (call each frame).
func update(delta: float) -> void:
	if not _is_initialized:
		return

	if _mouse_handler != null:
		_mouse_handler.update(delta)


## Set input mode.
func set_input_mode(mode: InputMode) -> void:
	_current_mode = mode
	input_mode_changed.emit(_get_mode_name(mode))


## Set current faction.
func set_faction(faction_id: int) -> void:
	_current_faction_id = faction_id

	if _hotkey_manager != null:
		_hotkey_manager.set_faction(faction_id)
	if _gamepad_handler != null:
		_gamepad_handler.set_faction(faction_id)


## Set context.
func set_context(context: String) -> void:
	if _input_context != null:
		_input_context.set_context(context)
	else:
		_current_context = context
		context_changed.emit(context)


## Enable/disable keyboard input.
func set_keyboard_enabled(enabled: bool) -> void:
	_keyboard_enabled = enabled


## Enable/disable mouse input.
func set_mouse_enabled(enabled: bool) -> void:
	_mouse_enabled = enabled


## Enable/disable gamepad input.
func set_gamepad_enabled(enabled: bool) -> void:
	_gamepad_enabled = enabled


## Get hotkey manager.
func get_hotkey_manager() -> HotkeyManager:
	return _hotkey_manager


## Get gamepad handler.
func get_gamepad_handler() -> GamepadInputHandler:
	return _gamepad_handler


## Get mouse handler.
func get_mouse_handler() -> MouseInputHandler:
	return _mouse_handler


## Get input context.
func get_input_context() -> InputContext:
	return _input_context


## Get last input type.
func get_last_input_type() -> InputType:
	return _last_input_type


## Is gamepad the primary input.
func is_gamepad_primary() -> bool:
	# Consider gamepad primary if last input was within 5 seconds
	if _last_input_type == InputType.GAMEPAD:
		var elapsed := Time.get_ticks_msec() - _last_input_time
		return elapsed < 5000
	return false


## Get mode name.
func _get_mode_name(mode: InputMode) -> String:
	match mode:
		InputMode.HYBRID: return "hybrid"
		InputMode.KEYBOARD_MOUSE: return "keyboard_mouse"
		InputMode.GAMEPAD_ONLY: return "gamepad"
	return "unknown"


## Apply settings.
func _apply_settings() -> void:
	if _settings == null:
		return

	_current_mode = _settings.input_mode

	if _hotkey_manager != null:
		_hotkey_manager.apply_settings(_settings)


## Save settings.
func save_settings() -> void:
	if _settings != null:
		_settings.save_settings()


## Get binding for action.
func get_binding_for_action(action: String, input_type: InputType = InputType.UNKNOWN) -> Dictionary:
	match input_type:
		InputType.KEYBOARD:
			if _hotkey_manager != null:
				return _hotkey_manager.get_binding(action)
		InputType.GAMEPAD:
			if _gamepad_handler != null:
				var result := _gamepad_handler.get_faction_bindings(_current_faction_id)
				# Search for action in bindings
				return result
	return {}


## Get all bindings for display.
func get_all_bindings() -> Dictionary:
	var bindings := {}

	if _hotkey_manager != null:
		bindings["keyboard"] = _hotkey_manager.get_all_bindings()

	if _gamepad_handler != null:
		bindings["gamepad"] = _gamepad_handler.get_faction_bindings(_current_faction_id)

	return bindings


## Rebind action.
func rebind_action(action: String, input_type: InputType, new_binding: Dictionary) -> bool:
	match input_type:
		InputType.KEYBOARD:
			if _hotkey_manager != null:
				return _hotkey_manager.rebind_action(action, new_binding)
		InputType.GAMEPAD:
			if _gamepad_handler != null:
				var button: int = new_binding.get("button", -1)
				if button >= 0:
					_gamepad_handler.set_binding(button, action)
					return true
	return false


## Reset to defaults.
func reset_to_defaults() -> void:
	if _hotkey_manager != null:
		_hotkey_manager.reset_to_defaults()
	if _gamepad_handler != null:
		_gamepad_handler.reset_to_defaults()


## Get status.
func get_status() -> Dictionary:
	return {
		"mode": _get_mode_name(_current_mode),
		"context": _current_context,
		"faction": _current_faction_id,
		"keyboard_enabled": _keyboard_enabled,
		"mouse_enabled": _mouse_enabled,
		"gamepad_enabled": _gamepad_enabled,
		"gamepad_connected": _gamepad_handler != null and _gamepad_handler.is_gamepad_connected(),
		"last_input": _get_input_type_name(_last_input_type)
	}


## Get input type name.
func _get_input_type_name(input_type: InputType) -> String:
	match input_type:
		InputType.KEYBOARD: return "keyboard"
		InputType.MOUSE: return "mouse"
		InputType.GAMEPAD: return "gamepad"
	return "unknown"


## Cleanup.
func cleanup() -> void:
	save_settings()


## InputSettings helper class.
class InputSettings:
	var input_mode := InputMode.HYBRID
	var key_repeat_enabled := true
	var key_repeat_delay := 0.5
	var key_repeat_rate := 0.1
	var mouse_sensitivity := 1.0
	var gamepad_sensitivity := 1.0
	var vibration_enabled := true
	var sticky_keys := false

	const SAVE_PATH := "user://input_settings.json"

	func save_settings() -> void:
		var data := {
			"input_mode": input_mode,
			"key_repeat_enabled": key_repeat_enabled,
			"key_repeat_delay": key_repeat_delay,
			"key_repeat_rate": key_repeat_rate,
			"mouse_sensitivity": mouse_sensitivity,
			"gamepad_sensitivity": gamepad_sensitivity,
			"vibration_enabled": vibration_enabled,
			"sticky_keys": sticky_keys
		}

		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(data))
			file.close()

	func load_settings() -> void:
		if not FileAccess.file_exists(SAVE_PATH):
			return

		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file == null:
			return

		var json_string := file.get_as_text()
		file.close()

		var parsed = JSON.parse_string(json_string)
		if parsed is Dictionary:
			input_mode = parsed.get("input_mode", InputMode.HYBRID)
			key_repeat_enabled = parsed.get("key_repeat_enabled", true)
			key_repeat_delay = parsed.get("key_repeat_delay", 0.5)
			key_repeat_rate = parsed.get("key_repeat_rate", 0.1)
			mouse_sensitivity = parsed.get("mouse_sensitivity", 1.0)
			gamepad_sensitivity = parsed.get("gamepad_sensitivity", 1.0)
			vibration_enabled = parsed.get("vibration_enabled", true)
			sticky_keys = parsed.get("sticky_keys", false)
