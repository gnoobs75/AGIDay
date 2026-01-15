class_name GamepadButtonMap
extends RefCounted
## GamepadButtonMap manages button-to-action mappings for each faction.
## Supports context-sensitive bindings and modifier combinations.

## Faction IDs
const FACTION_AETHER_SWARM := 0
const FACTION_OPTIFORGE_LEGION := 1
const FACTION_DYNAPODS_VANGUARD := 2
const FACTION_LOGIBOTS_COLOSSUS := 3

## Button indices matching GamepadInputHandler
const BTN_A := JOY_BUTTON_A
const BTN_B := JOY_BUTTON_B
const BTN_X := JOY_BUTTON_X
const BTN_Y := JOY_BUTTON_Y
const BTN_LB := JOY_BUTTON_LEFT_SHOULDER
const BTN_RB := JOY_BUTTON_RIGHT_SHOULDER
const BTN_BACK := JOY_BUTTON_BACK
const BTN_START := JOY_BUTTON_START
const BTN_LSTICK := JOY_BUTTON_LEFT_STICK
const BTN_RSTICK := JOY_BUTTON_RIGHT_STICK
const BTN_DPAD_UP := JOY_BUTTON_DPAD_UP
const BTN_DPAD_DOWN := JOY_BUTTON_DPAD_DOWN
const BTN_DPAD_LEFT := JOY_BUTTON_DPAD_LEFT
const BTN_DPAD_RIGHT := JOY_BUTTON_DPAD_RIGHT
const BTN_LT := 100  ## Virtual trigger buttons
const BTN_RT := 101

## Bindings storage
## Structure: faction_id -> context -> modifier_key -> button -> command
var _bindings: Dictionary = {}

## Default bindings per faction
var _default_bindings: Dictionary = {}


func _init() -> void:
	_setup_default_bindings()
	_apply_defaults()


## Setup default bindings for all factions.
func _setup_default_bindings() -> void:
	# Common bindings (same for all factions)
	var common_default := {
		BTN_A: {"type": "selection", "action": "select"},
		BTN_B: {"type": "selection", "action": "cancel"},
		BTN_X: {"type": "ability", "action": "primary_ability"},
		BTN_Y: {"type": "ability", "action": "secondary_ability"},
		BTN_RT: {"type": "command", "action": "attack_move"},
		BTN_LT: {"type": "command", "action": "stop"},
		BTN_DPAD_UP: {"type": "camera", "action": "camera_up"},
		BTN_DPAD_DOWN: {"type": "camera", "action": "camera_down"},
		BTN_DPAD_LEFT: {"type": "camera", "action": "camera_left"},
		BTN_DPAD_RIGHT: {"type": "camera", "action": "camera_right"},
		BTN_LSTICK: {"type": "camera", "action": "center_camera"},
		BTN_RSTICK: {"type": "selection", "action": "select_all"},
		BTN_START: {"type": "menu", "action": "pause"},
		BTN_BACK: {"type": "menu", "action": "menu"}
	}

	# Common modifier bindings (LB/RB held)
	var common_modifier := {
		BTN_A: {"type": "selection", "action": "add_to_selection"},
		BTN_B: {"type": "selection", "action": "remove_from_selection"},
		BTN_X: {"type": "ability", "action": "ability_3"},
		BTN_Y: {"type": "ability", "action": "ability_4"},
		BTN_DPAD_UP: {"type": "group", "action": "control_group_1"},
		BTN_DPAD_DOWN: {"type": "group", "action": "control_group_2"},
		BTN_DPAD_LEFT: {"type": "group", "action": "control_group_3"},
		BTN_DPAD_RIGHT: {"type": "group", "action": "control_group_4"}
	}

	# Aether Swarm - stealth and micro-drone focus
	_default_bindings[FACTION_AETHER_SWARM] = {
		"default": {
			"normal": common_default.duplicate(true),
			"modifier": _merge_dicts(common_modifier.duplicate(true), {
				BTN_RT: {"type": "ability", "action": "phase_shift", "ability_id": "aether_phase"},
				BTN_LT: {"type": "ability", "action": "cloak_all", "ability_id": "aether_cloak"}
			})
		},
		"combat": {
			"normal": _merge_dicts(common_default.duplicate(true), {
				BTN_X: {"type": "ability", "action": "swarm_attack", "ability_id": "aether_swarm"},
				BTN_Y: {"type": "ability", "action": "disruption_field", "ability_id": "aether_disrupt"}
			}),
			"modifier": common_modifier.duplicate(true)
		}
	}

	# OptiForge Legion - humanoid horde focus
	_default_bindings[FACTION_OPTIFORGE_LEGION] = {
		"default": {
			"normal": common_default.duplicate(true),
			"modifier": _merge_dicts(common_modifier.duplicate(true), {
				BTN_RT: {"type": "ability", "action": "charge", "ability_id": "opti_charge"},
				BTN_LT: {"type": "ability", "action": "fortify", "ability_id": "opti_fortify"}
			})
		},
		"combat": {
			"normal": _merge_dicts(common_default.duplicate(true), {
				BTN_X: {"type": "ability", "action": "mass_assault", "ability_id": "opti_assault"},
				BTN_Y: {"type": "ability", "action": "evolution_surge", "ability_id": "opti_evolve"}
			}),
			"modifier": common_modifier.duplicate(true)
		}
	}

	# Dynapods Vanguard - agile quad/humanoid focus
	_default_bindings[FACTION_DYNAPODS_VANGUARD] = {
		"default": {
			"normal": common_default.duplicate(true),
			"modifier": _merge_dicts(common_modifier.duplicate(true), {
				BTN_RT: {"type": "ability", "action": "leap", "ability_id": "dyna_leap"},
				BTN_LT: {"type": "ability", "action": "dodge", "ability_id": "dyna_dodge"}
			})
		},
		"combat": {
			"normal": _merge_dicts(common_default.duplicate(true), {
				BTN_X: {"type": "ability", "action": "acrobatic_strike", "ability_id": "dyna_acro"},
				BTN_Y: {"type": "ability", "action": "rapid_fire", "ability_id": "dyna_rapid"}
			}),
			"modifier": common_modifier.duplicate(true)
		}
	}

	# LogiBots Colossus - heavy siege focus
	_default_bindings[FACTION_LOGIBOTS_COLOSSUS] = {
		"default": {
			"normal": common_default.duplicate(true),
			"modifier": _merge_dicts(common_modifier.duplicate(true), {
				BTN_RT: {"type": "ability", "action": "artillery_barrage", "ability_id": "logi_barrage"},
				BTN_LT: {"type": "ability", "action": "shield_wall", "ability_id": "logi_shield"}
			})
		},
		"combat": {
			"normal": _merge_dicts(common_default.duplicate(true), {
				BTN_X: {"type": "ability", "action": "siege_mode", "ability_id": "logi_siege"},
				BTN_Y: {"type": "ability", "action": "industrial_devastation", "ability_id": "logi_devastate"}
			}),
			"modifier": common_modifier.duplicate(true)
		}
	}


## Apply defaults to current bindings.
func _apply_defaults() -> void:
	_bindings = _default_bindings.duplicate(true)


## Get command for button press.
func get_command_for_button(button: int, faction_id: int, context: String,
							with_modifier: bool) -> Dictionary:
	# Get faction bindings
	if not _bindings.has(faction_id):
		return {}

	var faction_bindings: Dictionary = _bindings[faction_id]

	# Get context bindings (fall back to default)
	var context_bindings: Dictionary = {}
	if faction_bindings.has(context):
		context_bindings = faction_bindings[context]
	elif faction_bindings.has("default"):
		context_bindings = faction_bindings["default"]
	else:
		return {}

	# Get modifier bindings
	var modifier_key := "modifier" if with_modifier else "normal"
	if not context_bindings.has(modifier_key):
		return {}

	var button_bindings: Dictionary = context_bindings[modifier_key]

	# Get command for button
	return button_bindings.get(button, {})


## Set a button binding.
func set_binding(button: int, action: String, faction_id: int,
				 context: String, with_modifier: bool) -> void:
	# Ensure faction exists
	if not _bindings.has(faction_id):
		_bindings[faction_id] = {}

	# Ensure context exists
	if not _bindings[faction_id].has(context):
		_bindings[faction_id][context] = {"normal": {}, "modifier": {}}

	# Set binding
	var modifier_key := "modifier" if with_modifier else "normal"
	_bindings[faction_id][context][modifier_key][button] = {
		"type": "ability",
		"action": action
	}


## Clear a button binding.
func clear_binding(button: int, faction_id: int, context: String,
				   with_modifier: bool) -> void:
	if not _bindings.has(faction_id):
		return
	if not _bindings[faction_id].has(context):
		return

	var modifier_key := "modifier" if with_modifier else "normal"
	if _bindings[faction_id][context].has(modifier_key):
		_bindings[faction_id][context][modifier_key].erase(button)


## Reset faction to defaults.
func reset_faction_to_defaults(faction_id: int) -> void:
	if _default_bindings.has(faction_id):
		_bindings[faction_id] = _default_bindings[faction_id].duplicate(true)


## Reset all to defaults.
func reset_all_to_defaults() -> void:
	_apply_defaults()


## Get all bindings for faction.
func get_faction_bindings(faction_id: int) -> Dictionary:
	return _bindings.get(faction_id, {}).duplicate(true)


## Check for binding conflicts.
func check_conflicts(button: int, faction_id: int, context: String,
					 with_modifier: bool) -> Array[String]:
	var conflicts: Array[String] = []

	# Check if button is already bound in the same context
	var existing := get_command_for_button(button, faction_id, context, with_modifier)
	if not existing.is_empty():
		conflicts.append("Button already bound to '%s'" % existing.get("action", "unknown"))

	# Check for reserved buttons
	if button == JOY_BUTTON_LEFT_SHOULDER or button == JOY_BUTTON_RIGHT_SHOULDER:
		conflicts.append("LB/RB are reserved as modifier buttons")

	return conflicts


## Validate all bindings.
func validate_all_bindings() -> Array[String]:
	var errors: Array[String] = []

	for faction_id in _bindings:
		var faction: Dictionary = _bindings[faction_id]
		for context in faction:
			var ctx: Dictionary = faction[context]
			for mod_key in ctx:
				var bindings: Dictionary = ctx[mod_key]
				for button in bindings:
					var cmd: Dictionary = bindings[button]
					if not cmd.has("action"):
						errors.append("Faction %d, context '%s', button %d: missing action" % [
							faction_id, context, button
						])

	return errors


## Get button from action (reverse lookup).
func get_button_for_action(action: String, faction_id: int, context: String = "default") -> Dictionary:
	if not _bindings.has(faction_id):
		return {}

	var faction: Dictionary = _bindings[faction_id]
	if not faction.has(context):
		context = "default"
	if not faction.has(context):
		return {}

	var ctx: Dictionary = faction[context]

	# Check normal bindings first
	for button in ctx.get("normal", {}):
		var cmd: Dictionary = ctx["normal"][button]
		if cmd.get("action", "") == action:
			return {"button": button, "modifier": false}

	# Check modifier bindings
	for button in ctx.get("modifier", {}):
		var cmd: Dictionary = ctx["modifier"][button]
		if cmd.get("action", "") == action:
			return {"button": button, "modifier": true}

	return {}


## Get all buttons for a command type.
func get_buttons_for_type(command_type: String, faction_id: int, context: String = "default") -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	if not _bindings.has(faction_id):
		return results

	var faction: Dictionary = _bindings[faction_id]
	if not faction.has(context):
		context = "default"
	if not faction.has(context):
		return results

	var ctx: Dictionary = faction[context]

	for mod_key in ["normal", "modifier"]:
		if not ctx.has(mod_key):
			continue
		for button in ctx[mod_key]:
			var cmd: Dictionary = ctx[mod_key][button]
			if cmd.get("type", "") == command_type:
				results.append({
					"button": button,
					"modifier": mod_key == "modifier",
					"action": cmd.get("action", "")
				})

	return results


## Merge two dictionaries.
func _merge_dicts(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in overlay:
		result[key] = overlay[key]
	return result


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return _bindings.duplicate(true)


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_bindings = data.duplicate(true)


## Get binding summary for UI display.
func get_binding_summary(faction_id: int, context: String = "default") -> Array[Dictionary]:
	var summary: Array[Dictionary] = []

	if not _bindings.has(faction_id):
		return summary

	var faction: Dictionary = _bindings[faction_id]
	if not faction.has(context):
		context = "default"
	if not faction.has(context):
		return summary

	var ctx: Dictionary = faction[context]

	# Normal bindings
	for button in ctx.get("normal", {}):
		var cmd: Dictionary = ctx["normal"][button]
		summary.append({
			"button": button,
			"button_name": _get_button_name(button),
			"modifier": false,
			"action": cmd.get("action", ""),
			"type": cmd.get("type", "")
		})

	# Modifier bindings
	for button in ctx.get("modifier", {}):
		var cmd: Dictionary = ctx["modifier"][button]
		summary.append({
			"button": button,
			"button_name": "LB + " + _get_button_name(button),
			"modifier": true,
			"action": cmd.get("action", ""),
			"type": cmd.get("type", "")
		})

	return summary


## Get button name string.
func _get_button_name(button: int) -> String:
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
		BTN_LT: return "LT"
		BTN_RT: return "RT"
	return "Button %d" % button


## Get faction name.
static func get_faction_name(faction_id: int) -> String:
	match faction_id:
		FACTION_AETHER_SWARM: return "Aether Swarm"
		FACTION_OPTIFORGE_LEGION: return "OptiForge Legion"
		FACTION_DYNAPODS_VANGUARD: return "Dynapods Vanguard"
		FACTION_LOGIBOTS_COLOSSUS: return "LogiBots Colossus"
	return "Unknown"
