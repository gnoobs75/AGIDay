class_name HotkeyBindings
extends RefCounted
## HotkeyBindings manages per-faction customizable key mappings.

signal binding_changed(faction_id: String, ability_id: String, old_key: String, new_key: String)
signal bindings_loaded(faction_id: String)
signal bindings_saved(faction_id: String)

## Default bindings by faction
const DEFAULT_BINDINGS := {
	"aether_swarm": {
		"spiral_rally": "Q",
		"hack_unit": "W",
		"swarm_attack": "E",
		"defensive_scatter": "R"
	},
	"glacius": {
		"line_formation": "Q",
		"ice_barrier": "W",
		"artillery_barrage": "E",
		"retreat_formation": "R"
	},
	"ferron_horde": {
		"charge_formation": "Q",
		"ram_attack": "W",
		"scrap_harvest": "E",
		"overclock": "R"
	},
	"human_remnant": {
		"cover_formation": "Q",
		"suppressing_fire": "W",
		"tactical_retreat": "E",
		"rally_point": "R"
	},
	"dynapods": {
		"momentum_charge": "Q",
		"acrobatic_dodge": "W",
		"bounce_attack": "E",
		"chain_dash": "R"
	}
}

## Common bindings (all factions)
const COMMON_BINDINGS := {
	"select_all": "A",
	"stop_units": "S",
	"attack_move": "D",
	"patrol": "P",
	"camera_focus": "Space"
}

## Active bindings (faction_id -> {ability_id -> key})
var _faction_bindings: Dictionary = {}

## Reverse lookup (faction_id -> {key -> ability_id})
var _key_to_ability: Dictionary = {}

## Config file path
var _config_path: String = "user://hotkey_bindings.cfg"


func _init() -> void:
	_load_defaults()


## Load default bindings.
func _load_defaults() -> void:
	for faction_id in DEFAULT_BINDINGS:
		_faction_bindings[faction_id] = DEFAULT_BINDINGS[faction_id].duplicate()
		_rebuild_reverse_lookup(faction_id)


## Rebuild reverse lookup for faction.
func _rebuild_reverse_lookup(faction_id: String) -> void:
	_key_to_ability[faction_id] = {}
	var bindings: Dictionary = _faction_bindings.get(faction_id, {})

	for ability_id in bindings:
		var key: String = bindings[ability_id]
		_key_to_ability[faction_id][key] = ability_id


## Get key binding for ability.
func get_binding(faction_id: String, ability_id: String) -> String:
	var bindings: Dictionary = _faction_bindings.get(faction_id, {})
	return bindings.get(ability_id, "")


## Get ability for key.
func get_ability_for_key(faction_id: String, key: String) -> String:
	var lookup: Dictionary = _key_to_ability.get(faction_id, {})
	return lookup.get(key.to_upper(), "")


## Get common ability for key.
func get_common_ability_for_key(key: String) -> String:
	for ability_id in COMMON_BINDINGS:
		if COMMON_BINDINGS[ability_id] == key.to_upper():
			return ability_id
	return ""


## Set key binding.
func set_binding(faction_id: String, ability_id: String, key: String) -> bool:
	key = key.to_upper()

	# Check for conflicts
	if has_conflict(faction_id, key, ability_id):
		return false

	# Get old key
	var old_key := get_binding(faction_id, ability_id)

	# Ensure faction dict exists
	if not _faction_bindings.has(faction_id):
		_faction_bindings[faction_id] = {}

	# Set new binding
	_faction_bindings[faction_id][ability_id] = key
	_rebuild_reverse_lookup(faction_id)

	binding_changed.emit(faction_id, ability_id, old_key, key)
	return true


## Check for key conflict.
func has_conflict(faction_id: String, key: String, exclude_ability: String = "") -> bool:
	key = key.to_upper()

	# Check common bindings
	for ability_id in COMMON_BINDINGS:
		if COMMON_BINDINGS[ability_id] == key:
			return true

	# Check faction bindings
	var bindings: Dictionary = _faction_bindings.get(faction_id, {})
	for ability_id in bindings:
		if ability_id != exclude_ability and bindings[ability_id] == key:
			return true

	return false


## Clear binding.
func clear_binding(faction_id: String, ability_id: String) -> void:
	if _faction_bindings.has(faction_id):
		_faction_bindings[faction_id].erase(ability_id)
		_rebuild_reverse_lookup(faction_id)


## Reset faction to defaults.
func reset_faction(faction_id: String) -> void:
	if DEFAULT_BINDINGS.has(faction_id):
		_faction_bindings[faction_id] = DEFAULT_BINDINGS[faction_id].duplicate()
		_rebuild_reverse_lookup(faction_id)


## Reset all to defaults.
func reset_all() -> void:
	_load_defaults()


## Get all bindings for faction.
func get_faction_bindings(faction_id: String) -> Dictionary:
	return _faction_bindings.get(faction_id, {}).duplicate()


## Get all bound keys for faction.
func get_bound_keys(faction_id: String) -> Array[String]:
	var keys: Array[String] = []
	var bindings: Dictionary = _faction_bindings.get(faction_id, {})

	for ability_id in bindings:
		keys.append(bindings[ability_id])

	return keys


## Save bindings to file.
func save_to_file(path: String = "") -> bool:
	var file_path := path if not path.is_empty() else _config_path

	var config := ConfigFile.new()

	for faction_id in _faction_bindings:
		var bindings: Dictionary = _faction_bindings[faction_id]
		for ability_id in bindings:
			config.set_value(faction_id, ability_id, bindings[ability_id])

	var error := config.save(file_path)
	if error == OK:
		bindings_saved.emit("")
		return true

	return false


## Load bindings from file.
func load_from_file(path: String = "") -> bool:
	var file_path := path if not path.is_empty() else _config_path

	var config := ConfigFile.new()
	var error := config.load(file_path)

	if error != OK:
		return false

	for faction_id in config.get_sections():
		if not _faction_bindings.has(faction_id):
			_faction_bindings[faction_id] = {}

		for ability_id in config.get_section_keys(faction_id):
			var key: String = config.get_value(faction_id, ability_id, "")
			if not key.is_empty():
				_faction_bindings[faction_id][ability_id] = key

		_rebuild_reverse_lookup(faction_id)
		bindings_loaded.emit(faction_id)

	return true


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"faction_bindings": _faction_bindings.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_faction_bindings = data.get("faction_bindings", {}).duplicate(true)

	for faction_id in _faction_bindings:
		_rebuild_reverse_lookup(faction_id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_counts: Dictionary = {}
	for faction_id in _faction_bindings:
		faction_counts[faction_id] = _faction_bindings[faction_id].size()

	return {
		"factions": _faction_bindings.size(),
		"bindings_per_faction": faction_counts
	}
