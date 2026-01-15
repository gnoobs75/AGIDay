class_name HotkeyManager
extends RefCounted
## HotkeyManager handles keyboard hotkey bindings with modifier support.
## Supports per-faction customization and context-sensitive bindings.

signal hotkey_triggered(action: String, modifiers: int)
signal binding_changed(action: String)
signal conflict_detected(action: String, conflicting_action: String)

## Modifier flags
const MOD_NONE := 0
const MOD_CTRL := 1
const MOD_SHIFT := 2
const MOD_ALT := 4

## Default hotkeys
const DEFAULT_BINDINGS := {
	# Faction abilities
	"ability_1": {"key": KEY_Q, "modifiers": MOD_NONE},
	"ability_2": {"key": KEY_W, "modifiers": MOD_NONE},
	"ability_3": {"key": KEY_E, "modifiers": MOD_NONE},
	"ability_4": {"key": KEY_R, "modifiers": MOD_NONE},
	"ability_5": {"key": KEY_T, "modifiers": MOD_NONE},

	# Control groups
	"control_group_1": {"key": KEY_1, "modifiers": MOD_NONE},
	"control_group_2": {"key": KEY_2, "modifiers": MOD_NONE},
	"control_group_3": {"key": KEY_3, "modifiers": MOD_NONE},
	"control_group_4": {"key": KEY_4, "modifiers": MOD_NONE},
	"control_group_5": {"key": KEY_5, "modifiers": MOD_NONE},
	"control_group_6": {"key": KEY_6, "modifiers": MOD_NONE},
	"control_group_7": {"key": KEY_7, "modifiers": MOD_NONE},
	"control_group_8": {"key": KEY_8, "modifiers": MOD_NONE},
	"control_group_9": {"key": KEY_9, "modifiers": MOD_NONE},
	"control_group_0": {"key": KEY_0, "modifiers": MOD_NONE},

	# Set control groups (with Ctrl)
	"set_control_group_1": {"key": KEY_1, "modifiers": MOD_CTRL},
	"set_control_group_2": {"key": KEY_2, "modifiers": MOD_CTRL},
	"set_control_group_3": {"key": KEY_3, "modifiers": MOD_CTRL},
	"set_control_group_4": {"key": KEY_4, "modifiers": MOD_CTRL},
	"set_control_group_5": {"key": KEY_5, "modifiers": MOD_CTRL},

	# Commands
	"attack_move": {"key": KEY_A, "modifiers": MOD_NONE},
	"stop": {"key": KEY_S, "modifiers": MOD_NONE},
	"hold_position": {"key": KEY_H, "modifiers": MOD_NONE},
	"patrol": {"key": KEY_P, "modifiers": MOD_NONE},

	# Selection
	"select_all": {"key": KEY_A, "modifiers": MOD_CTRL},
	"select_all_of_type": {"key": KEY_W, "modifiers": MOD_CTRL},

	# Camera
	"camera_center": {"key": KEY_SPACE, "modifiers": MOD_NONE},
	"camera_follow": {"key": KEY_F, "modifiers": MOD_NONE},
	"camera_zoom_in": {"key": KEY_EQUAL, "modifiers": MOD_NONE},
	"camera_zoom_out": {"key": KEY_MINUS, "modifiers": MOD_NONE},

	# UI
	"pause": {"key": KEY_SPACE, "modifiers": MOD_NONE},
	"minimap_toggle": {"key": KEY_TAB, "modifiers": MOD_NONE},
	"menu": {"key": KEY_ESCAPE, "modifiers": MOD_NONE},
	"quick_save": {"key": KEY_F5, "modifiers": MOD_NONE},
	"quick_load": {"key": KEY_F9, "modifiers": MOD_NONE},

	# Production
	"factory_cycle": {"key": KEY_COMMA, "modifiers": MOD_NONE},
	"queue_unit": {"key": KEY_PERIOD, "modifiers": MOD_NONE},
	"cancel_queue": {"key": KEY_BACKSPACE, "modifiers": MOD_NONE}
}

## Faction-specific overrides
var _faction_bindings: Dictionary = {}  ## faction_id -> action -> binding

## Current bindings
var _bindings: Dictionary = {}  ## action -> binding
var _reverse_map: Dictionary = {} ## key_hash -> action

## State
var _current_faction_id := 0
var _current_context := "default"

## Key repeat
var _key_repeat_enabled := true
var _key_repeat_delay := 0.5
var _key_repeat_rate := 0.1
var _key_states: Dictionary = {}  ## key -> {pressed, repeat_timer}

## Persistence
const SAVE_PATH := "user://hotkey_bindings.json"


func _init() -> void:
	_load_bindings()


## Initialize hotkey manager.
func initialize() -> void:
	if _bindings.is_empty():
		_apply_defaults()
	_build_reverse_map()


## Apply default bindings.
func _apply_defaults() -> void:
	_bindings = DEFAULT_BINDINGS.duplicate(true)


## Build reverse lookup map.
func _build_reverse_map() -> void:
	_reverse_map.clear()
	for action in _bindings:
		var binding: Dictionary = _bindings[action]
		var hash := _get_binding_hash(binding)
		_reverse_map[hash] = action


## Get hash for binding lookup.
func _get_binding_hash(binding: Dictionary) -> int:
	var key: int = binding.get("key", 0)
	var mods: int = binding.get("modifiers", 0)
	return (mods << 24) | key


## Process input event.
func process_input(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false

	var key_event := event as InputEventKey
	var key := key_event.keycode

	# Update key state
	_key_states[key] = {
		"pressed": key_event.pressed,
		"repeat_timer": 0.0
	}

	if not key_event.pressed:
		return false

	# Get current modifiers
	var modifiers := _get_current_modifiers(key_event)

	# Create binding to look up
	var test_binding := {"key": key, "modifiers": modifiers}
	var hash := _get_binding_hash(test_binding)

	# Check for match
	if _reverse_map.has(hash):
		var action: String = _reverse_map[hash]

		# Check context
		if _is_action_valid_in_context(action):
			hotkey_triggered.emit(action, modifiers)
			return true

	return false


## Get current modifier state.
func _get_current_modifiers(event: InputEventKey) -> int:
	var mods := MOD_NONE

	if event.ctrl_pressed:
		mods |= MOD_CTRL
	if event.shift_pressed:
		mods |= MOD_SHIFT
	if event.alt_pressed:
		mods |= MOD_ALT

	return mods


## Check if action is valid in current context.
func _is_action_valid_in_context(action: String) -> bool:
	# Context-based filtering
	match _current_context:
		"menu":
			return action in ["menu", "confirm", "cancel"]
		"pause":
			return action in ["pause", "menu"]
		"factory_view":
			return action.begins_with("factory_") or action in ["menu", "pause", "camera_center"]
	return true


## Set context.
func set_context(context: String) -> void:
	_current_context = context


## Set faction.
func set_faction(faction_id: int) -> void:
	_current_faction_id = faction_id

	# Apply faction-specific bindings
	if _faction_bindings.has(faction_id):
		for action in _faction_bindings[faction_id]:
			_bindings[action] = _faction_bindings[faction_id][action]
		_build_reverse_map()


## Rebind action.
func rebind_action(action: String, new_binding: Dictionary) -> bool:
	if not new_binding.has("key"):
		return false

	# Check for conflicts
	var hash := _get_binding_hash(new_binding)
	if _reverse_map.has(hash):
		var conflicting := _reverse_map[hash]
		if conflicting != action:
			conflict_detected.emit(action, conflicting)
			return false

	# Apply binding
	_bindings[action] = new_binding.duplicate()
	_build_reverse_map()
	_save_bindings()

	binding_changed.emit(action)
	return true


## Set faction-specific binding.
func set_faction_binding(faction_id: int, action: String, binding: Dictionary) -> void:
	if not _faction_bindings.has(faction_id):
		_faction_bindings[faction_id] = {}

	_faction_bindings[faction_id][action] = binding.duplicate()

	if faction_id == _current_faction_id:
		_bindings[action] = binding.duplicate()
		_build_reverse_map()

	_save_bindings()


## Get binding for action.
func get_binding(action: String) -> Dictionary:
	return _bindings.get(action, {})


## Get all bindings.
func get_all_bindings() -> Dictionary:
	return _bindings.duplicate(true)


## Get binding display string.
func get_binding_display(action: String) -> String:
	var binding := get_binding(action)
	if binding.is_empty():
		return "Unbound"

	var parts: Array[String] = []

	var mods: int = binding.get("modifiers", MOD_NONE)
	if mods & MOD_CTRL:
		parts.append("Ctrl")
	if mods & MOD_SHIFT:
		parts.append("Shift")
	if mods & MOD_ALT:
		parts.append("Alt")

	var key: int = binding.get("key", 0)
	parts.append(_get_key_name(key))

	return "+".join(parts)


## Get key name.
func _get_key_name(key: int) -> String:
	# Handle special keys
	match key:
		KEY_SPACE: return "Space"
		KEY_ESCAPE: return "Esc"
		KEY_TAB: return "Tab"
		KEY_BACKSPACE: return "Backspace"
		KEY_ENTER: return "Enter"
		KEY_DELETE: return "Delete"
		KEY_INSERT: return "Insert"
		KEY_HOME: return "Home"
		KEY_END: return "End"
		KEY_PAGEUP: return "Page Up"
		KEY_PAGEDOWN: return "Page Down"
		KEY_LEFT: return "Left"
		KEY_RIGHT: return "Right"
		KEY_UP: return "Up"
		KEY_DOWN: return "Down"
		KEY_F1: return "F1"
		KEY_F2: return "F2"
		KEY_F3: return "F3"
		KEY_F4: return "F4"
		KEY_F5: return "F5"
		KEY_F6: return "F6"
		KEY_F7: return "F7"
		KEY_F8: return "F8"
		KEY_F9: return "F9"
		KEY_F10: return "F10"
		KEY_F11: return "F11"
		KEY_F12: return "F12"

	# Regular keys
	return char(key).to_upper()


## Check for conflicts.
func check_for_conflict(action: String, binding: Dictionary) -> String:
	var hash := _get_binding_hash(binding)
	if _reverse_map.has(hash):
		var existing := _reverse_map[hash]
		if existing != action:
			return existing
	return ""


## Reset action to default.
func reset_action_to_default(action: String) -> void:
	if DEFAULT_BINDINGS.has(action):
		_bindings[action] = DEFAULT_BINDINGS[action].duplicate()
		_build_reverse_map()
		_save_bindings()
		binding_changed.emit(action)


## Reset all to defaults.
func reset_to_defaults() -> void:
	_apply_defaults()
	_faction_bindings.clear()
	_build_reverse_map()
	_save_bindings()


## Apply settings.
func apply_settings(settings) -> void:
	if settings == null:
		return

	_key_repeat_enabled = settings.key_repeat_enabled
	_key_repeat_delay = settings.key_repeat_delay
	_key_repeat_rate = settings.key_repeat_rate


## Validate bindings.
func validate_bindings() -> Array[String]:
	var errors: Array[String] = []

	# Check for duplicate bindings
	var hash_map: Dictionary = {}
	for action in _bindings:
		var binding: Dictionary = _bindings[action]
		var hash := _get_binding_hash(binding)

		if hash_map.has(hash):
			errors.append("Conflict: '%s' and '%s' have same binding" % [action, hash_map[hash]])
		else:
			hash_map[hash] = action

	# Check for required actions
	var required := ["pause", "menu"]
	for action in required:
		if not _bindings.has(action):
			errors.append("Required action '%s' is not bound" % action)

	return errors


## Get actions by category.
func get_actions_by_category(category: String) -> Array[String]:
	var actions: Array[String] = []

	match category:
		"abilities":
			actions.assign(["ability_1", "ability_2", "ability_3", "ability_4", "ability_5"])
		"control_groups":
			for i in 10:
				actions.append("control_group_%d" % i)
		"commands":
			actions.assign(["attack_move", "stop", "hold_position", "patrol"])
		"camera":
			actions.assign(["camera_center", "camera_follow", "camera_zoom_in", "camera_zoom_out"])
		"ui":
			actions.assign(["pause", "minimap_toggle", "menu", "quick_save", "quick_load"])

	return actions


## Get all categories.
func get_categories() -> Array[String]:
	return ["abilities", "control_groups", "commands", "camera", "ui", "production"]


## Save bindings to file.
func _save_bindings() -> void:
	var data := {
		"bindings": _bindings,
		"faction_bindings": _faction_bindings
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


## Load bindings from file.
func _load_bindings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_apply_defaults()
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_apply_defaults()
		return

	var json_string := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_string)
	if parsed is Dictionary:
		_bindings = parsed.get("bindings", {})
		_faction_bindings = parsed.get("faction_bindings", {})

		# Ensure defaults for missing actions
		for action in DEFAULT_BINDINGS:
			if not _bindings.has(action):
				_bindings[action] = DEFAULT_BINDINGS[action].duplicate()
	else:
		_apply_defaults()


## Export bindings.
func export_bindings() -> String:
	var data := {
		"bindings": _bindings,
		"faction_bindings": _faction_bindings,
		"version": 1
	}
	return JSON.stringify(data, "\t")


## Import bindings.
func import_bindings(json_string: String) -> bool:
	var parsed = JSON.parse_string(json_string)
	if not parsed is Dictionary:
		return false

	_bindings = parsed.get("bindings", {})
	_faction_bindings = parsed.get("faction_bindings", {})
	_build_reverse_map()
	_save_bindings()
	return true
