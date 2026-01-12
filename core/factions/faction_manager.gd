class_name FactionManagerClass
extends Node
## FactionManager is the central authority for faction data and state.
## Loads configurations from JSON and provides faction data access.

signal faction_loaded(faction_id: int)
signal faction_config_changed(faction_id: int)
signal factions_reloaded()
signal validation_error(faction_key: String, errors: Array)

## Path to faction configuration files
const FACTION_CONFIG_PATH := "res://data/factions/"
const FACTION_CONFIG_EXTENSION := ".json"

## All loaded faction configurations (faction_id -> FactionConfig)
var _factions: Dictionary = {}

## Faction lookup by key (faction_key -> FactionConfig)
var _factions_by_key: Dictionary = {}

## File modification times for hot-reload (file_path -> mtime)
var _file_mod_times: Dictionary = {}

## Hot-reload enabled flag
var _hot_reload_enabled: bool = false

## Hot-reload check interval
var _hot_reload_interval: float = 2.0
var _time_since_check: float = 0.0


func _ready() -> void:
	load_all_factions()
	print("FactionManager: Initialized with %d factions" % _factions.size())


func _process(delta: float) -> void:
	if _hot_reload_enabled:
		_time_since_check += delta
		if _time_since_check >= _hot_reload_interval:
			_time_since_check = 0.0
			_check_for_changes()


## Load all faction configurations from the config directory
func load_all_factions() -> int:
	_factions.clear()
	_factions_by_key.clear()
	_file_mod_times.clear()

	var loaded := 0

	# First try loading from files
	if DirAccess.dir_exists_absolute(FACTION_CONFIG_PATH):
		var dir := DirAccess.open(FACTION_CONFIG_PATH)
		if dir != null:
			dir.list_dir_begin()
			var file_name := dir.get_next()

			while file_name != "":
				if not dir.current_is_dir() and file_name.ends_with(FACTION_CONFIG_EXTENSION):
					var file_path := FACTION_CONFIG_PATH + file_name
					if _load_faction_file(file_path):
						loaded += 1
				file_name = dir.get_next()

			dir.list_dir_end()

	# If no files found, load default factions
	if loaded == 0:
		loaded = _load_default_factions()

	factions_reloaded.emit()
	return loaded


## Load a single faction configuration file
func _load_faction_file(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path):
		push_error("FactionManager: File not found: %s" % file_path)
		return false

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("FactionManager: Cannot open file: %s" % file_path)
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("FactionManager: JSON parse error in %s: %s" % [file_path, json.get_error_message()])
		return false

	var data = json.get_data()
	if not data is Dictionary:
		push_error("FactionManager: Invalid faction data in %s" % file_path)
		return false

	var config := FactionConfig.from_dict(data)

	# Validate
	var validation := config.validate()
	if not validation["valid"]:
		validation_error.emit(config.faction_key, validation["errors"])
		for err in validation["errors"]:
			push_error("FactionManager: Validation error in %s: %s" % [file_path, err])
		return false

	for warning in validation.get("warnings", []):
		push_warning("FactionManager: %s: %s" % [file_path, warning])

	# Register faction
	_register_faction(config)

	# Track file modification time
	_file_mod_times[file_path] = FileAccess.get_modified_time(file_path)

	print("FactionManager: Loaded faction '%s' (ID: %d) from %s" % [config.display_name, config.faction_id, file_path])
	return true


## Register a faction configuration
func _register_faction(config: FactionConfig) -> void:
	_factions[config.faction_id] = config
	_factions_by_key[config.faction_key] = config
	faction_loaded.emit(config.faction_id)


## Load default factions if no config files exist
func _load_default_factions() -> int:
	print("FactionManager: Loading default faction configurations...")

	var defaults := [
		_create_aether_swarm_default(),
		_create_optiforge_legion_default(),
		_create_dynapods_vanguard_default(),
		_create_logibots_colossus_default(),
		_create_human_remnant_default()
	]

	for config in defaults:
		_register_faction(config)

	return defaults.size()


func _create_aether_swarm_default() -> FactionConfig:
	var config := FactionConfig.new()
	config.faction_id = 1
	config.faction_key = "aether_swarm"
	config.display_name = "Aether Swarm"
	config.description = "Swift autonomous drones with nanite-based abilities. Masters of speed and swarm tactics."
	config.primary_color = Color(0.0, 0.8, 1.0)  # Cyan
	config.secondary_color = Color(0.0, 0.4, 0.8)  # Blue
	# Stat multipliers: 1.5x speed, 0.6x health, 0.8x damage, 1.2x production
	config.unit_speed_multiplier = 1.5
	config.unit_health_multiplier = 0.6
	config.unit_damage_multiplier = 0.8
	config.production_speed_multiplier = 1.2
	config.has_hive_mind = true
	config.is_playable = true
	config.starting_resources = {"ree": 500, "energy": 100}
	config.unit_types = ["drone", "swarmling", "nanite_cloud", "hive_node"]
	config.abilities = ["nanite_repair", "swarm_surge", "phase_shift", "spiral_rally"]
	config.experience_pools = {
		"combat_experience": {"base_xp": 100, "scaling": 1.15},
		"economy_experience": {"base_xp": 80, "scaling": 1.1},
		"engineering_experience": {"base_xp": 120, "scaling": 1.2}
	}
	_setup_robot_relationships(config)
	return config


func _create_optiforge_legion_default() -> FactionConfig:
	var config := FactionConfig.new()
	config.faction_id = 2
	config.faction_key = "optiforge_legion"
	config.display_name = "OptiForge Legion"
	config.description = "Heavy industrial automatons with overwhelming firepower. Strength through steel."
	config.primary_color = Color(1.0, 0.5, 0.0)  # Orange
	config.secondary_color = Color(0.6, 0.3, 0.0)
	config.unit_speed_multiplier = 0.7
	config.unit_health_multiplier = 1.3
	config.unit_damage_multiplier = 1.2
	config.production_speed_multiplier = 0.8
	config.is_playable = true
	config.starting_resources = {"ree": 400, "energy": 150}
	config.unit_types = ["forge_walker", "siege_titan", "artillery_platform", "constructor"]
	config.abilities = ["overclock", "siege_mode", "armor_plating"]
	config.experience_pools = {
		"combat_experience": {"base_xp": 100, "scaling": 1.15},
		"economy_experience": {"base_xp": 80, "scaling": 1.1},
		"engineering_experience": {"base_xp": 120, "scaling": 1.2}
	}
	_setup_robot_relationships(config)
	return config


func _create_dynapods_vanguard_default() -> FactionConfig:
	var config := FactionConfig.new()
	config.faction_id = 3
	config.faction_key = "dynapods_vanguard"
	config.display_name = "Dynapods Vanguard"
	config.description = "Adaptive multi-legged mechs with modular loadouts. Versatility is victory."
	config.primary_color = Color(0.7, 0.7, 0.75)  # Light gray
	config.secondary_color = Color(0.5, 0.5, 0.55)  # Medium gray
	config.unit_speed_multiplier = 1.2
	config.unit_health_multiplier = 0.9
	config.unit_damage_multiplier = 1.1
	config.production_speed_multiplier = 0.9
	config.is_playable = true
	config.starting_resources = {"ree": 450, "energy": 120}
	config.unit_types = ["legbreaker", "vaultpounder", "titanquad", "skybound", "quadripper", "leapscav", "shadowstride"]
	config.abilities = ["terrain_adapt", "module_swap", "rapid_deploy", "acrobatic_maneuver"]
	config.experience_pools = {
		"combat_experience": {"base_xp": 100, "scaling": 1.15},
		"economy_experience": {"base_xp": 80, "scaling": 1.1},
		"engineering_experience": {"base_xp": 90, "scaling": 1.12}
	}
	_setup_robot_relationships(config)
	return config


func _create_logibots_colossus_default() -> FactionConfig:
	var config := FactionConfig.new()
	config.faction_id = 4
	config.faction_key = "logibots_colossus"
	config.display_name = "LogiBots Colossus"
	config.description = "Massive resource-processing giants. Economy is the foundation of war."
	# Industrial color scheme: gold, brown, dark gray
	config.primary_color = Color(0.831, 0.686, 0.216)  # #d4af37 Gold
	config.secondary_color = Color(0.545, 0.451, 0.333)  # #8b7355 Brown
	config.unit_speed_multiplier = 0.7
	config.unit_health_multiplier = 1.6
	config.unit_damage_multiplier = 0.8
	config.resource_gather_multiplier = 1.5
	config.production_speed_multiplier = 0.9
	config.is_playable = true
	config.starting_resources = {"ree": 600, "energy": 80}
	config.unit_types = ["bulkripper", "haulforge", "crushkin", "forge_stomper", "titanclad", "siegehaul"]
	config.abilities = ["siege_mode", "coordinated_strike", "bulk_transport", "resource_surge"]
	config.experience_pools = {
		"logistics_experience": {"base_xp": 80, "scaling": 1.1},
		"siege_experience": {"base_xp": 120, "scaling": 1.2},
		"engineering_experience": {"base_xp": 100, "scaling": 1.15}
	}
	_setup_robot_relationships(config)
	return config


func _create_human_remnant_default() -> FactionConfig:
	var config := FactionConfig.new()
	config.faction_id = 5
	config.faction_key = "human_remnant"
	config.display_name = "Human Remnant"
	config.description = "Desperate survivors fighting to reclaim their world. The last hope of humanity."
	config.primary_color = Color(0.8, 0.2, 0.2)  # Red
	config.secondary_color = Color(0.4, 0.1, 0.1)
	config.unit_speed_multiplier = 1.0
	config.unit_health_multiplier = 0.9
	config.unit_damage_multiplier = 1.1
	config.is_playable = false
	config.is_ai_only = true
	config.starting_resources = {"ree": 300, "energy": 50}
	config.unit_types = ["soldier", "engineer", "mech_pilot", "resistance_leader"]
	config.abilities = ["guerrilla_tactics", "emp_burst", "rally"]
	# Human Remnant is enemy to all robot factions
	config.relationships = {1: "enemy", 2: "enemy", 3: "enemy", 4: "enemy"}
	return config


func _setup_robot_relationships(config: FactionConfig) -> void:
	# All robot factions are enemies to each other and to humans
	config.relationships = {}
	for i in range(1, 6):
		if i != config.faction_id:
			config.relationships[i] = "enemy"


## Get faction configuration by ID
func get_faction(faction_id: int) -> FactionConfig:
	return _factions.get(faction_id)


## Get faction configuration by key
func get_faction_by_key(faction_key: String) -> FactionConfig:
	return _factions_by_key.get(faction_key)


## Get all faction configurations
func get_all_factions() -> Array[FactionConfig]:
	var result: Array[FactionConfig] = []
	for id in _factions:
		result.append(_factions[id])
	return result


## Get all playable factions
func get_playable_factions() -> Array[FactionConfig]:
	var result: Array[FactionConfig] = []
	for id in _factions:
		var config: FactionConfig = _factions[id]
		if config.is_playable:
			result.append(config)
	return result


## Get faction count
func get_faction_count() -> int:
	return _factions.size()


## Check if faction exists
func has_faction(faction_id: int) -> bool:
	return _factions.has(faction_id)


## Get relationship between two factions
func get_relationship(faction_a: int, faction_b: int) -> int:
	if faction_a == faction_b:
		return FactionConfig.Relationship.ALLY

	var config := get_faction(faction_a)
	if config == null:
		return FactionConfig.Relationship.NEUTRAL

	return config.get_relationship(faction_b)


## Check if two factions are enemies
func are_enemies(faction_a: int, faction_b: int) -> bool:
	return get_relationship(faction_a, faction_b) == FactionConfig.Relationship.ENEMY


## Check if two factions are allies
func are_allies(faction_a: int, faction_b: int) -> bool:
	return get_relationship(faction_a, faction_b) == FactionConfig.Relationship.ALLY


## Enable hot-reload of configuration files
func enable_hot_reload(enabled: bool = true, interval: float = 2.0) -> void:
	_hot_reload_enabled = enabled
	_hot_reload_interval = interval
	print("FactionManager: Hot-reload %s" % ("enabled" if enabled else "disabled"))


## Check for configuration file changes
func _check_for_changes() -> void:
	var changed := false

	for file_path in _file_mod_times:
		if FileAccess.file_exists(file_path):
			var current_mtime := FileAccess.get_modified_time(file_path)
			if current_mtime > _file_mod_times[file_path]:
				print("FactionManager: Detected change in %s, reloading..." % file_path)
				if _load_faction_file(file_path):
					changed = true

	if changed:
		factions_reloaded.emit()


## Reload a specific faction
func reload_faction(faction_key: String) -> bool:
	var file_path := FACTION_CONFIG_PATH + faction_key + FACTION_CONFIG_EXTENSION
	return _load_faction_file(file_path)


## Save faction configuration to JSON file
func save_faction_config(config: FactionConfig) -> bool:
	var file_path := FACTION_CONFIG_PATH + config.faction_key + FACTION_CONFIG_EXTENSION

	# Ensure directory exists
	var dir := DirAccess.open("res://")
	if dir != null and not dir.dir_exists("data/factions"):
		dir.make_dir_recursive("data/factions")

	var json_text := JSON.stringify(config.to_dict(), "\t")

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("FactionManager: Cannot write to %s" % file_path)
		return false

	file.store_string(json_text)
	file.close()

	print("FactionManager: Saved faction config to %s" % file_path)
	return true


## Export all default faction configurations to JSON files
func export_default_configs() -> int:
	var exported := 0

	for id in _factions:
		var config: FactionConfig = _factions[id]
		if save_faction_config(config):
			exported += 1

	print("FactionManager: Exported %d faction configurations" % exported)
	return exported
