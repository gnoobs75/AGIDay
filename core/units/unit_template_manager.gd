class_name UnitTemplateManagerClass
extends Node
## UnitTemplateManager loads, caches, and provides access to unit templates.
## Templates are loaded from JSON files in the data/units directory.

signal template_loaded(template_id: String)
signal templates_reloaded()
signal validation_error(template_id: String, errors: Array)

## Path to unit template configuration files
const TEMPLATE_CONFIG_PATH := "res://data/units/"
const TEMPLATE_CONFIG_EXTENSION := ".json"

## All loaded templates (template_id -> UnitTemplate)
var _templates: Dictionary = {}

## Templates by faction (faction_key -> Array[template_id])
var _templates_by_faction: Dictionary = {}

## Templates by unit type (unit_type -> Array[template_id])
var _templates_by_type: Dictionary = {}

## File modification times for hot-reload
var _file_mod_times: Dictionary = {}

## Hot-reload settings
var _hot_reload_enabled: bool = false
var _hot_reload_interval: float = 2.0
var _time_since_check: float = 0.0


func _ready() -> void:
	load_all_templates()
	print("UnitTemplateManager: Initialized with %d templates" % _templates.size())


func _process(delta: float) -> void:
	if _hot_reload_enabled:
		_time_since_check += delta
		if _time_since_check >= _hot_reload_interval:
			_time_since_check = 0.0
			_check_for_changes()


## Load all templates from the template directory.
func load_all_templates() -> int:
	_templates.clear()
	_templates_by_faction.clear()
	_templates_by_type.clear()
	_file_mod_times.clear()

	var loaded := 0

	# Load from files if directory exists
	if DirAccess.dir_exists_absolute(TEMPLATE_CONFIG_PATH):
		var dir := DirAccess.open(TEMPLATE_CONFIG_PATH)
		if dir != null:
			dir.list_dir_begin()
			var file_name := dir.get_next()

			while file_name != "":
				if not dir.current_is_dir() and file_name.ends_with(TEMPLATE_CONFIG_EXTENSION):
					var file_path := TEMPLATE_CONFIG_PATH + file_name
					loaded += _load_template_file(file_path)
				file_name = dir.get_next()

			dir.list_dir_end()

	# If no files found, load defaults
	if loaded == 0:
		loaded = _load_default_templates()

	templates_reloaded.emit()
	return loaded


## Load templates from a single JSON file.
## Returns the number of templates loaded.
func _load_template_file(file_path: String) -> int:
	if not FileAccess.file_exists(file_path):
		push_error("UnitTemplateManager: File not found: %s" % file_path)
		return 0

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("UnitTemplateManager: Cannot open file: %s" % file_path)
		return 0

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("UnitTemplateManager: JSON parse error in %s: %s" % [file_path, json.get_error_message()])
		return 0

	var data = json.get_data()

	# Track file modification time
	_file_mod_times[file_path] = FileAccess.get_modified_time(file_path)

	# Handle both single template and array of templates
	var loaded := 0
	if data is Array:
		for template_data in data:
			if _load_single_template(template_data, file_path):
				loaded += 1
	elif data is Dictionary:
		if _load_single_template(data, file_path):
			loaded += 1

	return loaded


## Load a single template from dictionary data.
func _load_single_template(data: Dictionary, source_file: String) -> bool:
	var template := UnitTemplate.from_dict(data)

	if not template.is_valid:
		validation_error.emit(template.template_id, template.validation_errors)
		for err in template.validation_errors:
			push_error("UnitTemplateManager: Validation error in %s: %s" % [source_file, err])
		return false

	_register_template(template)
	print("UnitTemplateManager: Loaded template '%s' from %s" % [template.template_id, source_file])
	return true


## Register a template in all lookup dictionaries.
func _register_template(template: UnitTemplate) -> void:
	_templates[template.template_id] = template

	# Index by faction
	if not _templates_by_faction.has(template.faction_key):
		_templates_by_faction[template.faction_key] = []
	if template.template_id not in _templates_by_faction[template.faction_key]:
		_templates_by_faction[template.faction_key].append(template.template_id)

	# Index by unit type
	if not _templates_by_type.has(template.unit_type):
		_templates_by_type[template.unit_type] = []
	if template.template_id not in _templates_by_type[template.unit_type]:
		_templates_by_type[template.unit_type].append(template.template_id)

	template_loaded.emit(template.template_id)


## Load default templates if no files exist.
func _load_default_templates() -> int:
	print("UnitTemplateManager: Loading default templates...")

	var defaults: Array[UnitTemplate] = []

	# Aether Swarm units
	defaults.append(_create_aether_drone_template())
	defaults.append(_create_aether_swarmling_template())
	defaults.append(_create_aether_nano_reaplet_template())
	defaults.append(_create_aether_spikelet_template())
	defaults.append(_create_aether_buzzblade_template())
	defaults.append(_create_aether_shardling_template())
	defaults.append(_create_aether_wispfire_template())
	defaults.append(_create_aether_driftpod_template())
	defaults.append(_create_aether_shadow_relay_template())

	# OptiForge Legion units
	defaults.append(_create_optiforge_forge_walker_template())
	defaults.append(_create_optiforge_siege_titan_template())
	defaults.append(_create_optiforge_titan_template())
	defaults.append(_create_optiforge_colossus_template())
	defaults.append(_create_optiforge_siege_cannon_template())
	defaults.append(_create_optiforge_shockwave_generator_template())
	defaults.append(_create_optiforge_shield_generator_template())

	# Dynapods Vanguard units
	defaults.append(_create_dynapods_legbreaker_template())
	defaults.append(_create_dynapods_vaultpounder_template())
	defaults.append(_create_dynapods_titanquad_template())
	defaults.append(_create_dynapods_skybound_template())

	# LogiBots Colossus units
	defaults.append(_create_logibots_bulkripper_template())
	defaults.append(_create_logibots_haulforge_template())

	# Human Resistance units
	defaults.append(_create_human_soldier_template())
	defaults.append(_create_human_sniper_template())

	# Builder units for each faction
	defaults.append(_create_aether_nano_welder_template())
	defaults.append(_create_optiforge_repair_drone_template())
	defaults.append(_create_dynapods_swift_fixer_template())
	defaults.append(_create_logibots_heavy_reconstructor_template())

	for template in defaults:
		if template.is_valid:
			_register_template(template)

	return defaults.size()


## Create Aether Swarm drone template.
func _create_aether_drone_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_drone"
	template.faction_key = "aether_swarm"
	template.unit_type = "drone"
	template.display_name = "Drone"
	template.description = "Fast, agile scout unit with swarm coordination."
	template.base_stats = {
		"max_health": 40.0,
		"health_regen": 1.0,
		"max_speed": 15.0,
		"acceleration": 60.0,
		"turn_rate": 8.0,
		"armor": 0.0,
		"base_damage": 8.0,
		"attack_speed": 1.5,
		"attack_range": 10.0,
		"vision_range": 25.0
	}
	template.production_cost = {"ree": 50, "energy": 15, "time": 3.0}
	template.abilities = ["swarm_surge"]
	template.tags = ["light", "fast", "swarm"]
	template._validate()
	return template


## Create Aether Swarm swarmling template.
func _create_aether_swarmling_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_swarmling"
	template.faction_key = "aether_swarm"
	template.unit_type = "swarmling"
	template.display_name = "Swarmling"
	template.description = "Expendable melee unit that attacks in groups."
	template.base_stats = {
		"max_health": 25.0,
		"health_regen": 0.0,
		"max_speed": 18.0,
		"acceleration": 80.0,
		"turn_rate": 10.0,
		"armor": 0.0,
		"base_damage": 5.0,
		"attack_speed": 2.0,
		"attack_range": 2.0,
		"vision_range": 15.0
	}
	template.production_cost = {"ree": 25, "energy": 5, "time": 1.5}
	template.abilities = []
	template.tags = ["light", "fast", "melee", "swarm"]
	template._validate()
	return template


## Create Aether Swarm Nano-Reaplet template.
func _create_aether_nano_reaplet_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_nano_reaplet"
	template.faction_key = "aether_swarm"
	template.unit_type = "nano_reaplet"
	template.display_name = "Nano-Reaplet"
	template.description = "Tiny harvester unit specialized in REE extraction."
	template.base_stats = {
		"max_health": 15.0,
		"health_regen": 0.5,
		"max_speed": 12.0,
		"acceleration": 60.0,
		"turn_rate": 8.0,
		"armor": 0.0,
		"base_damage": 2.0,
		"attack_speed": 0.5,
		"attack_range": 1.0,
		"vision_range": 15.0,
		"extraction_rate": 5.0,
		"scale": 0.5
	}
	template.production_cost = {"ree": 50, "energy": 10, "time": 2.0}
	template.abilities = ["ree_extraction"]
	template.tags = ["light", "gatherer", "swarm"]
	template._validate()
	return template


## Create Aether Swarm Spikelet template.
func _create_aether_spikelet_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_spikelet"
	template.faction_key = "aether_swarm"
	template.unit_type = "spikelet"
	template.display_name = "Spikelet"
	template.description = "Melee swarm attacker with short-range spike attacks."
	template.base_stats = {
		"max_health": 20.0,
		"health_regen": 0.0,
		"max_speed": 16.0,
		"acceleration": 75.0,
		"turn_rate": 9.0,
		"armor": 0.0,
		"base_damage": 4.0,
		"attack_speed": 2.5,
		"attack_range": 1.5,
		"vision_range": 12.0,
		"scale": 0.6
	}
	template.production_cost = {"ree": 35, "energy": 8, "time": 1.5}
	template.abilities = ["swarm_attack"]
	template.tags = ["light", "melee", "swarm", "fast"]
	template._validate()
	return template


## Create Aether Swarm Buzzblade template.
func _create_aether_buzzblade_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_buzzblade"
	template.faction_key = "aether_swarm"
	template.unit_type = "buzzblade"
	template.display_name = "Buzzblade"
	template.description = "Hovering ranged unit with rapid fire attacks."
	template.base_stats = {
		"max_health": 25.0,
		"health_regen": 0.5,
		"max_speed": 14.0,
		"acceleration": 65.0,
		"turn_rate": 7.0,
		"armor": 0.0,
		"base_damage": 6.0,
		"attack_speed": 2.0,
		"attack_range": 5.0,
		"vision_range": 18.0,
		"scale": 0.7
	}
	template.production_cost = {"ree": 60, "energy": 15, "time": 3.0}
	template.abilities = ["hover"]
	template.tags = ["light", "ranged", "swarm", "flying"]
	template._validate()
	return template


## Create Aether Swarm Shardling template.
func _create_aether_shardling_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_shardling"
	template.faction_key = "aether_swarm"
	template.unit_type = "shardling"
	template.display_name = "Shardling"
	template.description = "Stealth unit that can dive underground for ambush attacks."
	template.base_stats = {
		"max_health": 30.0,
		"health_regen": 0.0,
		"max_speed": 10.0,
		"acceleration": 50.0,
		"turn_rate": 6.0,
		"armor": 0.05,
		"base_damage": 12.0,
		"attack_speed": 1.0,
		"attack_range": 2.0,
		"vision_range": 20.0,
		"stealth_detection_range": 5.0,
		"scale": 0.7
	}
	template.production_cost = {"ree": 80, "energy": 25, "time": 4.0}
	template.abilities = ["dive", "stealth"]
	template.tags = ["medium", "stealth", "ambush", "swarm"]
	template._validate()
	return template


## Create Aether Swarm Wispfire template.
func _create_aether_wispfire_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_wispfire"
	template.faction_key = "aether_swarm"
	template.unit_type = "wispfire"
	template.display_name = "Wispfire"
	template.description = "Ranged unit with homing missile system."
	template.base_stats = {
		"max_health": 35.0,
		"health_regen": 0.5,
		"max_speed": 11.0,
		"acceleration": 55.0,
		"turn_rate": 5.0,
		"armor": 0.0,
		"base_damage": 8.0,
		"attack_speed": 0.8,
		"attack_range": 10.0,
		"vision_range": 22.0,
		"missile_count": 3,
		"missile_speed": 15.0,
		"scale": 0.8
	}
	template.production_cost = {"ree": 100, "energy": 35, "time": 5.0}
	template.abilities = ["homing_missiles"]
	template.tags = ["medium", "ranged", "missile", "swarm"]
	template._validate()
	return template


## Create Aether Swarm Driftpod template.
func _create_aether_driftpod_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_driftpod"
	template.faction_key = "aether_swarm"
	template.unit_type = "driftpod"
	template.display_name = "Driftpod"
	template.description = "Air transport unit that can carry up to 5 units."
	template.base_stats = {
		"max_health": 60.0,
		"health_regen": 1.0,
		"max_speed": 15.0,
		"acceleration": 40.0,
		"turn_rate": 4.0,
		"armor": 0.1,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 30.0,
		"transport_capacity": 5,
		"scale": 1.0
	}
	template.production_cost = {"ree": 150, "energy": 50, "time": 7.0}
	template.abilities = ["transport", "air_movement"]
	template.tags = ["medium", "transport", "flying", "support"]
	template._validate()
	return template


## Create Aether Swarm Shadow Relay template.
func _create_aether_shadow_relay_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_shadow_relay"
	template.faction_key = "aether_swarm"
	template.unit_type = "shadow_relay"
	template.display_name = "Shadow Relay"
	template.description = "Specialist unit with teleportation ability."
	template.base_stats = {
		"max_health": 45.0,
		"health_regen": 0.5,
		"max_speed": 8.0,
		"acceleration": 45.0,
		"turn_rate": 5.0,
		"armor": 0.05,
		"base_damage": 5.0,
		"attack_speed": 1.0,
		"attack_range": 8.0,
		"vision_range": 25.0,
		"shadow_jump_range": 30.0,
		"shadow_jump_cooldown": 5.0,
		"scale": 0.9
	}
	template.production_cost = {"ree": 300, "energy": 250, "time": 10.0}
	template.abilities = ["shadow_jump", "phase_shift"]
	template.tags = ["medium", "support", "teleport", "utility"]
	template._validate()
	return template


## Create OptiForge Forge Walker template.
func _create_optiforge_forge_walker_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_forge_walker"
	template.faction_key = "optiforge_legion"
	template.unit_type = "forge_walker"
	template.display_name = "Forge Walker"
	template.description = "Heavily armored frontline unit with strong firepower."
	template.base_stats = {
		"max_health": 150.0,
		"health_regen": 0.5,
		"max_speed": 6.0,
		"acceleration": 30.0,
		"turn_rate": 3.0,
		"armor": 0.2,
		"base_damage": 20.0,
		"attack_speed": 0.8,
		"attack_range": 15.0,
		"vision_range": 20.0
	}
	template.production_cost = {"ree": 120, "energy": 40, "time": 8.0}
	template.abilities = ["armor_plating"]
	template.tags = ["heavy", "armored", "frontline"]
	template._validate()
	return template


## Create OptiForge Siege Titan template.
func _create_optiforge_siege_titan_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_siege_titan"
	template.faction_key = "optiforge_legion"
	template.unit_type = "siege_titan"
	template.display_name = "Siege Titan"
	template.description = "Massive siege unit with devastating area attacks."
	template.base_stats = {
		"max_health": 300.0,
		"health_regen": 0.0,
		"max_speed": 4.0,
		"acceleration": 20.0,
		"turn_rate": 2.0,
		"armor": 0.35,
		"base_damage": 50.0,
		"attack_speed": 0.4,
		"attack_range": 25.0,
		"vision_range": 30.0
	}
	template.production_cost = {"ree": 300, "energy": 100, "time": 15.0}
	template.abilities = ["siege_mode", "overclock"]
	template.tags = ["heavy", "armored", "siege", "aoe"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create OptiForge Titan template.
func _create_optiforge_titan_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_titan"
	template.faction_key = "optiforge_legion"
	template.unit_type = "titan"
	template.display_name = "Titan"
	template.description = "Heavy assault unit with devastating AoE ground slam."
	template.base_stats = {
		"max_health": 200.0,
		"health_regen": 0.0,
		"max_speed": 3.0,
		"acceleration": 15.0,
		"turn_rate": 2.0,
		"armor": 0.5,
		"base_damage": 25.0,
		"attack_speed": 0.6,
		"attack_range": 8.0,
		"vision_range": 18.0,
		"aoe_radius": 10.0,
		"aoe_damage": 25.0,
		"knockback_force": 20.0,
		"ground_slam_radius_mult": 1.5,
		"ground_slam_damage_mult": 1.5,
		"mass": 500.0,
		"friction": 0.8
	}
	template.rendering = {
		"mesh_path": "res://assets/units/optiforge/titan.tscn",
		"material_path": "",
		"scale": Vector3(1.2, 1.2, 1.2),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 100.0]
	}
	template.production_cost = {"ree": 250, "energy": 80, "time": 12.0}
	template.abilities = ["aoe_attack", "ground_slam"]
	template.tags = ["heavy", "armored", "melee", "aoe"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create OptiForge Colossus template.
func _create_optiforge_colossus_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_colossus"
	template.faction_key = "optiforge_legion"
	template.unit_type = "colossus"
	template.display_name = "Colossus"
	template.description = "Massive armored unit with regenerating shield."
	template.base_stats = {
		"max_health": 300.0,
		"health_regen": 0.0,
		"max_speed": 2.0,
		"acceleration": 10.0,
		"turn_rate": 1.5,
		"armor": 0.7,
		"base_damage": 15.0,
		"attack_speed": 0.5,
		"attack_range": 6.0,
		"vision_range": 15.0,
		"shield_health": 100.0,
		"shield_regen": 5.0,
		"shield_bash_damage": 30.0,
		"fortify_armor_bonus": 0.3,
		"mass": 800.0,
		"friction": 0.9
	}
	template.rendering = {
		"mesh_path": "res://assets/units/optiforge/colossus.tscn",
		"material_path": "",
		"scale": Vector3(1.5, 1.5, 1.5),
		"use_multimesh": false,
		"lod_distances": [25.0, 50.0, 80.0]
	}
	template.production_cost = {"ree": 400, "energy": 120, "time": 18.0}
	template.abilities = ["shield_system", "shield_bash", "fortify"]
	template.tags = ["heavy", "armored", "tank", "shield"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create OptiForge Siege Cannon template.
func _create_optiforge_siege_cannon_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_siege_cannon"
	template.faction_key = "optiforge_legion"
	template.unit_type = "siege_cannon"
	template.display_name = "Siege Cannon"
	template.description = "Long-range artillery unit with devastating AoE attacks."
	template.base_stats = {
		"max_health": 150.0,
		"health_regen": 0.0,
		"max_speed": 2.5,
		"acceleration": 12.0,
		"turn_rate": 2.0,
		"armor": 0.3,
		"base_damage": 40.0,
		"attack_speed": 0.3,
		"attack_range": 20.0,
		"vision_range": 25.0,
		"aoe_radius": 12.0,
		"aoe_damage": 40.0,
		"projectile_arc": true,
		"min_range": 8.0,
		"mass": 400.0,
		"friction": 0.85
	}
	template.rendering = {
		"mesh_path": "res://assets/units/optiforge/siege_cannon.tscn",
		"material_path": "",
		"scale": Vector3(1.3, 1.3, 1.3),
		"use_multimesh": false,
		"lod_distances": [35.0, 70.0, 120.0]
	}
	template.production_cost = {"ree": 350, "energy": 100, "time": 15.0}
	template.abilities = ["artillery_mode", "bombardment"]
	template.tags = ["heavy", "artillery", "ranged", "aoe"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create OptiForge Shockwave Generator template.
func _create_optiforge_shockwave_generator_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_shockwave_generator"
	template.faction_key = "optiforge_legion"
	template.unit_type = "shockwave_generator"
	template.display_name = "Shockwave Generator"
	template.description = "Support unit that generates a protective damage-reducing field."
	template.base_stats = {
		"max_health": 100.0,
		"health_regen": 1.0,
		"max_speed": 3.0,
		"acceleration": 20.0,
		"turn_rate": 3.0,
		"armor": 0.2,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 20.0,
		"field_radius": 15.0,
		"damage_reduction": 0.3,
		"mass": 250.0,
		"friction": 0.7
	}
	template.rendering = {
		"mesh_path": "res://assets/units/optiforge/shockwave_generator.tscn",
		"material_path": "",
		"scale": Vector3(1.0, 1.0, 1.0),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 100.0]
	}
	template.production_cost = {"ree": 200, "energy": 150, "time": 10.0}
	template.abilities = ["protective_field", "shockwave_pulse"]
	template.tags = ["medium", "support", "aura", "defensive"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create OptiForge Shield Generator template.
func _create_optiforge_shield_generator_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_shield_generator"
	template.faction_key = "optiforge_legion"
	template.unit_type = "shield_generator"
	template.display_name = "Shield Generator"
	template.description = "Mobile support unit that provides shields to nearby allies."
	template.base_stats = {
		"max_health": 80.0,
		"health_regen": 0.5,
		"max_speed": 4.0,
		"acceleration": 25.0,
		"turn_rate": 4.0,
		"armor": 0.15,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 22.0,
		"shield_aura_radius": 12.0,
		"shield_per_second": 3.0,
		"max_shield_granted": 50.0,
		"mass": 180.0,
		"friction": 0.7
	}
	template.rendering = {
		"mesh_path": "res://assets/units/optiforge/shield_generator.tscn",
		"material_path": "",
		"scale": Vector3(0.9, 0.9, 0.9),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 100.0]
	}
	template.production_cost = {"ree": 180, "energy": 120, "time": 8.0}
	template.abilities = ["shield_aura", "emergency_shield"]
	template.tags = ["medium", "support", "shield", "aura"]
	template._validate()
	return template


## Create Dynapods Legbreaker template.
func _create_dynapods_legbreaker_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_legbreaker"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "legbreaker"
	template.display_name = "Legbreaker"
	template.description = "Agile combat mech with devastating stomp attack."
	template.base_stats = {
		"max_health": 100.0,
		"health_regen": 1.0,
		"max_speed": 10.0,
		"acceleration": 55.0,
		"turn_rate": 6.0,
		"armor": 0.15,
		"base_damage": 18.0,
		"attack_speed": 1.0,
		"attack_range": 4.0,
		"vision_range": 22.0,
		"stomp_radius": 6.0,
		"stomp_damage": 18.0,
		"stomp_knockback": 15.0,
		"leap_strike_range": 12.0,
		"mass": 150.0,
		"friction": 0.6
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/legbreaker.tscn",
		"material_path": "",
		"scale": Vector3(1.0, 1.0, 1.0),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 100.0]
	}
	template.production_cost = {"ree": 400, "energy": 250, "time": 10.0}
	template.abilities = ["stomp_attack", "leap_strike", "terrain_adapt"]
	template.tags = ["medium", "agile", "multi-legged", "melee"]
	template._validate()
	return template


## Create Dynapods Vaultpounder template.
func _create_dynapods_vaultpounder_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_vaultpounder"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "vaultpounder"
	template.display_name = "Vaultpounder"
	template.description = "Heavy siege mech with devastating hammer slam."
	template.base_stats = {
		"max_health": 150.0,
		"health_regen": 0.5,
		"max_speed": 7.0,
		"acceleration": 35.0,
		"turn_rate": 4.0,
		"armor": 0.2,
		"base_damage": 22.0,
		"attack_speed": 0.7,
		"attack_range": 5.0,
		"vision_range": 20.0,
		"hammer_slam_radius": 8.0,
		"hammer_slam_damage": 22.0,
		"hammer_slam_knockback": 20.0,
		"vault_leap_range": 15.0,
		"vault_leap_cooldown": 8.0,
		"mass": 220.0,
		"friction": 0.65
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/vaultpounder.tscn",
		"material_path": "",
		"scale": Vector3(1.2, 1.2, 1.2),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 100.0]
	}
	template.production_cost = {"ree": 500, "energy": 300, "time": 12.0}
	template.abilities = ["hammer_slam", "vault_leap", "terrain_adapt"]
	template.tags = ["heavy", "siege", "multi-legged", "aoe"]
	template._validate()
	return template


## Create Dynapods Titanquad template.
func _create_dynapods_titanquad_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_titanquad"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "titanquad"
	template.display_name = "Titanquad"
	template.description = "Heavily armored defensive mech with fortification mode."
	template.base_stats = {
		"max_health": 200.0,
		"health_regen": 0.0,
		"max_speed": 6.0,
		"acceleration": 25.0,
		"turn_rate": 3.0,
		"armor": 0.3,
		"base_damage": 15.0,
		"attack_speed": 0.6,
		"attack_range": 6.0,
		"vision_range": 18.0,
		"fortify_armor_mult": 1.5,
		"fortify_speed_mult": 0.5,
		"ground_pound_radius": 10.0,
		"ground_pound_damage": 25.0,
		"ground_pound_knockback": 25.0,
		"mass": 300.0,
		"friction": 0.75
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/titanquad.tscn",
		"material_path": "",
		"scale": Vector3(1.4, 1.4, 1.4),
		"use_multimesh": false,
		"lod_distances": [25.0, 50.0, 80.0]
	}
	template.production_cost = {"ree": 600, "energy": 400, "time": 15.0}
	template.abilities = ["fortify", "ground_pound", "terrain_adapt"]
	template.tags = ["heavy", "tank", "multi-legged", "defensive"]
	template._validate()
	return template


## Create Dynapods Skybound template.
func _create_dynapods_skybound_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_skybound"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "skybound"
	template.display_name = "Skybound"
	template.description = "Aerial assault mech with jet boost and diving attacks."
	template.base_stats = {
		"max_health": 80.0,
		"health_regen": 1.0,
		"max_speed": 12.0,
		"acceleration": 60.0,
		"turn_rate": 7.0,
		"armor": 0.1,
		"base_damage": 16.0,
		"attack_speed": 1.2,
		"attack_range": 8.0,
		"vision_range": 28.0,
		"jet_boost_speed_mult": 1.5,
		"jet_boost_duration": 2.0,
		"jet_boost_cooldown": 6.0,
		"aerial_pounce_range": 18.0,
		"aerial_pounce_damage_mult": 1.5,
		"mass": 100.0,
		"friction": 0.4
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/skybound.tscn",
		"material_path": "",
		"scale": Vector3(0.9, 0.9, 0.9),
		"use_multimesh": false,
		"lod_distances": [35.0, 70.0, 120.0]
	}
	template.production_cost = {"ree": 450, "energy": 350, "time": 11.0}
	template.abilities = ["jet_boost", "aerial_pounce", "terrain_adapt"]
	template.tags = ["medium", "aerial", "multi-legged", "fast"]
	template._validate()
	return template


## Create LogiBots Bulkripper template.
func _create_logibots_bulkripper_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_bulkripper"
	template.faction_key = "logibots_colossus"
	template.unit_type = "bulkripper"
	template.display_name = "Bulkripper"
	template.description = "Heavy resource gatherer with defensive capabilities."
	template.base_stats = {
		"max_health": 200.0,
		"health_regen": 0.0,
		"max_speed": 5.0,
		"acceleration": 25.0,
		"turn_rate": 2.5,
		"armor": 0.25,
		"base_damage": 15.0,
		"attack_speed": 0.7,
		"attack_range": 8.0,
		"vision_range": 15.0,
		"gather_rate": 2.0
	}
	template.production_cost = {"ree": 100, "energy": 30, "time": 7.0}
	template.abilities = ["bulk_transport"]
	template.tags = ["heavy", "gatherer", "industrial"]
	template._validate()
	return template


## Create LogiBots Haulforge template.
func _create_logibots_haulforge_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_haulforge"
	template.faction_key = "logibots_colossus"
	template.unit_type = "haulforge"
	template.display_name = "Haulforge"
	template.description = "Mobile forge and transport unit."
	template.base_stats = {
		"max_health": 180.0,
		"health_regen": 0.0,
		"max_speed": 6.0,
		"acceleration": 20.0,
		"turn_rate": 3.0,
		"armor": 0.2,
		"base_damage": 10.0,
		"attack_speed": 0.5,
		"attack_range": 10.0,
		"vision_range": 18.0,
		"gather_rate": 1.5
	}
	template.production_cost = {"ree": 120, "energy": 40, "time": 8.0}
	template.abilities = ["resource_surge"]
	template.tags = ["heavy", "support", "industrial"]
	template._validate()
	return template


## Create Human Soldier template.
func _create_human_soldier_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_soldier"
	template.faction_key = "human_remnant"
	template.unit_type = "soldier"
	template.display_name = "Soldier"
	template.description = "Standard infantry unit with balanced stats."
	template.base_stats = {
		"max_health": 30.0,
		"health_regen": 0.0,
		"max_speed": 6.0,
		"acceleration": 40.0,
		"turn_rate": 5.0,
		"armor": 0.1,
		"base_damage": 8.0,
		"attack_speed": 1.2,
		"attack_range": 15.0,
		"vision_range": 20.0
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = []
	template.tags = ["light", "infantry", "human"]
	template._validate()
	return template


## Create Human Sniper template.
func _create_human_sniper_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_sniper"
	template.faction_key = "human_remnant"
	template.unit_type = "sniper"
	template.display_name = "Sniper"
	template.description = "Long-range specialist with critical hits."
	template.base_stats = {
		"max_health": 25.0,
		"health_regen": 0.0,
		"max_speed": 5.0,
		"acceleration": 35.0,
		"turn_rate": 4.0,
		"armor": 0.05,
		"base_damage": 15.0,
		"attack_speed": 0.6,
		"attack_range": 30.0,
		"vision_range": 35.0,
		"critical_chance": 0.3,
		"critical_multiplier": 2.0
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["precision_shot"]
	template.tags = ["light", "ranged", "human", "sniper"]
	template._validate()
	return template


## Create Aether Swarm Nano-Welder template.
func _create_aether_nano_welder_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_nano_welder"
	template.faction_key = "aether_swarm"
	template.unit_type = "nano_welder"
	template.display_name = "Nano-Welder"
	template.description = "Fast repair unit that can repair while moving."
	template.base_stats = {
		"max_health": 15.0,
		"health_regen": 0.5,
		"max_speed": 7.0,
		"acceleration": 50.0,
		"turn_rate": 7.0,
		"armor": 0.0,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 25.0,
		"repair_speed": 0.5,
		"scan_radius": 25.0
	}
	template.production_cost = {"ree": 40, "energy": 20, "time": 4.0}
	template.abilities = ["nanite_repair"]
	template.tags = ["light", "builder", "support"]
	template._validate()
	return template


## Create OptiForge Legion Repair Drone template.
func _create_optiforge_repair_drone_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_repair_drone"
	template.faction_key = "optiforge_legion"
	template.unit_type = "repair_drone"
	template.display_name = "Repair Drone"
	template.description = "Sturdy repair unit with bonus to infrastructure repair."
	template.base_stats = {
		"max_health": 25.0,
		"health_regen": 0.0,
		"max_speed": 5.0,
		"acceleration": 30.0,
		"turn_rate": 4.0,
		"armor": 0.1,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 20.0,
		"repair_speed": 0.75,
		"scan_radius": 20.0
	}
	template.production_cost = {"ree": 60, "energy": 25, "time": 5.0}
	template.abilities = []
	template.tags = ["medium", "builder", "support", "industrial"]
	template._validate()
	return template


## Create Dynapods Vanguard Swift Fixer template.
func _create_dynapods_swift_fixer_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_swift_fixer"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "swift_fixer"
	template.display_name = "Swift Fixer"
	template.description = "Agile repair unit that can repair while dodging."
	template.base_stats = {
		"max_health": 20.0,
		"health_regen": 0.5,
		"max_speed": 8.5,
		"acceleration": 55.0,
		"turn_rate": 6.0,
		"armor": 0.05,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 22.0,
		"repair_speed": 0.6,
		"scan_radius": 22.0
	}
	template.production_cost = {"ree": 50, "energy": 22, "time": 4.5}
	template.abilities = ["terrain_adapt"]
	template.tags = ["medium", "builder", "support", "agile"]
	template._validate()
	return template


## Create LogiBots Colossus Heavy Reconstructor template.
func _create_logibots_heavy_reconstructor_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_heavy_reconstructor"
	template.faction_key = "logibots_colossus"
	template.unit_type = "heavy_reconstructor"
	template.display_name = "Heavy Reconstructor"
	template.description = "Slow but powerful repair unit that can repair multiple voxels simultaneously."
	template.base_stats = {
		"max_health": 40.0,
		"health_regen": 0.0,
		"max_speed": 3.5,
		"acceleration": 20.0,
		"turn_rate": 2.5,
		"armor": 0.2,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 18.0,
		"repair_speed": 1.0,
		"scan_radius": 18.0
	}
	template.production_cost = {"ree": 80, "energy": 35, "time": 7.0}
	template.abilities = []
	template.tags = ["heavy", "builder", "support", "industrial"]
	template._validate()
	return template


## Get a template by ID.
func get_template(template_id: String) -> UnitTemplate:
	return _templates.get(template_id)


## Get template for a faction and unit type combination.
func get_template_for_unit(faction_key: String, unit_type: String) -> UnitTemplate:
	var template_id := "%s_%s" % [faction_key, unit_type]
	return get_template(template_id)


## Get all templates for a faction.
func get_faction_templates(faction_key: String) -> Array[UnitTemplate]:
	var result: Array[UnitTemplate] = []
	var template_ids: Array = _templates_by_faction.get(faction_key, [])

	for template_id in template_ids:
		var template := get_template(template_id)
		if template != null:
			result.append(template)

	return result


## Get all templates of a specific unit type.
func get_templates_by_type(unit_type: String) -> Array[UnitTemplate]:
	var result: Array[UnitTemplate] = []
	var template_ids: Array = _templates_by_type.get(unit_type, [])

	for template_id in template_ids:
		var template := get_template(template_id)
		if template != null:
			result.append(template)

	return result


## Get all template IDs.
func get_all_template_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _templates.keys():
		ids.append(id)
	return ids


## Get template count.
func get_template_count() -> int:
	return _templates.size()


## Check if template exists.
func has_template(template_id: String) -> bool:
	return _templates.has(template_id)


## Enable hot-reload of template files.
func enable_hot_reload(enabled: bool = true, interval: float = 2.0) -> void:
	_hot_reload_enabled = enabled
	_hot_reload_interval = interval
	print("UnitTemplateManager: Hot-reload %s" % ("enabled" if enabled else "disabled"))


## Check for template file changes.
func _check_for_changes() -> void:
	var changed := false

	for file_path in _file_mod_times:
		if FileAccess.file_exists(file_path):
			var current_mtime := FileAccess.get_modified_time(file_path)
			if current_mtime > _file_mod_times[file_path]:
				print("UnitTemplateManager: Detected change in %s, reloading..." % file_path)
				_load_template_file(file_path)
				changed = true

	if changed:
		templates_reloaded.emit()


## Save a template to JSON file.
func save_template(template: UnitTemplate) -> bool:
	var file_path := TEMPLATE_CONFIG_PATH + template.template_id + TEMPLATE_CONFIG_EXTENSION

	# Ensure directory exists
	var dir := DirAccess.open("res://")
	if dir != null and not dir.dir_exists("data/units"):
		dir.make_dir_recursive("data/units")

	var json_text := JSON.stringify(template.to_dict(), "\t")

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("UnitTemplateManager: Cannot write to %s" % file_path)
		return false

	file.store_string(json_text)
	file.close()

	print("UnitTemplateManager: Saved template to %s" % file_path)
	return true


## Export all default templates to JSON files.
func export_default_templates() -> int:
	var exported := 0

	for template_id in _templates:
		var template: UnitTemplate = _templates[template_id]
		if save_template(template):
			exported += 1

	print("UnitTemplateManager: Exported %d templates" % exported)
	return exported
