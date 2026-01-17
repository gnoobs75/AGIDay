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
	defaults.append(_create_aether_gale_swarm_template())
	defaults.append(_create_aether_quillback_template())
	defaults.append(_create_aether_thornclad_template())
	defaults.append(_create_aether_ghosteye_template())

	# OptiForge Legion units
	defaults.append(_create_optiforge_forge_walker_template())
	defaults.append(_create_optiforge_siege_titan_template())
	defaults.append(_create_optiforge_titan_template())
	defaults.append(_create_optiforge_colossus_template())
	defaults.append(_create_optiforge_siege_cannon_template())
	defaults.append(_create_optiforge_shockwave_generator_template())
	defaults.append(_create_optiforge_shield_generator_template())
	defaults.append(_create_optiforge_blitzkin_template())
	defaults.append(_create_optiforge_pulseforged_template())
	defaults.append(_create_optiforge_jetkin_template())
	defaults.append(_create_optiforge_hullbreaker_template())
	defaults.append(_create_optiforge_eyeforge_template())

	# Dynapods Vanguard units
	defaults.append(_create_dynapods_legbreaker_template())
	defaults.append(_create_dynapods_vaultpounder_template())
	defaults.append(_create_dynapods_titanquad_template())
	defaults.append(_create_dynapods_skybound_template())
	defaults.append(_create_dynapods_quadripper_template())
	defaults.append(_create_dynapods_leapscav_template())
	defaults.append(_create_dynapods_boundlifter_template())
	defaults.append(_create_dynapods_shadowstride_template())
	defaults.append(_create_dynapods_pulsepod_template())
	defaults.append(_create_dynapods_stridetrans_template())

	# LogiBots Colossus units
	defaults.append(_create_logibots_bulkripper_template())
	defaults.append(_create_logibots_haulforge_template())
	defaults.append(_create_logibots_crushkin_template())
	defaults.append(_create_logibots_siegehaul_template())
	defaults.append(_create_logibots_titanclad_template())
	defaults.append(_create_logibots_gridbreaker_template())
	defaults.append(_create_logibots_forge_stomper_template())
	defaults.append(_create_logibots_logi_eye_template())
	defaults.append(_create_logibots_colossus_cart_template())
	defaults.append(_create_logibots_payload_slinger_template())

	# Human Resistance units
	defaults.append(_create_human_soldier_template())
	defaults.append(_create_human_sniper_template())
	defaults.append(_create_human_m4_fireteam_template())
	defaults.append(_create_human_javelin_ghost_template())
	defaults.append(_create_human_m1_abrams_template())
	defaults.append(_create_human_stryker_template())
	defaults.append(_create_human_dronegun_raven_template())
	defaults.append(_create_human_mk19_grenadier_template())
	defaults.append(_create_human_leonidas_pods_template())
	defaults.append(_create_human_cyber_rigs_template())
	defaults.append(_create_human_m939_scrapjacks_template())
	defaults.append(_create_human_d7_bulldozer_template())

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


# =============================================================================
# DYNAPODS VANGUARD - HARVESTER UNITS
# =============================================================================

## Create Dynapods Quadripper template - quad-legged resource gathering mech.
func _create_dynapods_quadripper_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_quadripper"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "quadripper"
	template.display_name = "Quadripper"
	template.description = "Agile four-legged harvester that tears through terrain to extract REE."
	template.base_stats = {
		"max_health": 120.0,
		"health_regen": 0.5,
		"max_speed": 8.0,
		"acceleration": 45.0,
		"turn_rate": 5.0,
		"armor": 0.15,
		"base_damage": 12.0,
		"attack_speed": 0.8,
		"attack_range": 6.0,
		"vision_range": 20.0,
		"gather_rate": 2.5,
		"cargo_capacity": 100.0,
		"terrain_bonus": 0.3,
		"mass": 140.0,
		"friction": 0.5
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/quadripper.tscn",
		"material_path": "",
		"scale": Vector3(0.85, 0.85, 0.85),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 100.0]
	}
	template.production_cost = {"ree": 150, "energy": 80, "time": 8.0}
	template.abilities = ["terrain_adapt", "dig_boost"]
	template.tags = ["medium", "gatherer", "multi-legged", "industrial"]
	template._validate()
	return template


## Create Dynapods Leapscav template - terrain-conquering scavenger.
func _create_dynapods_leapscav_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_leapscav"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "leapscav"
	template.display_name = "Leapscav"
	template.description = "Agile scavenger that leaps across terrain to reach distant REE deposits."
	template.base_stats = {
		"max_health": 70.0,
		"health_regen": 1.0,
		"max_speed": 12.0,
		"acceleration": 65.0,
		"turn_rate": 6.5,
		"armor": 0.05,
		"base_damage": 6.0,
		"attack_speed": 1.0,
		"attack_range": 5.0,
		"vision_range": 30.0,
		"gather_rate": 1.8,
		"cargo_capacity": 60.0,
		"leap_range": 15.0,
		"leap_cooldown": 4.0,
		"mass": 60.0,
		"friction": 0.3
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/leapscav.tscn",
		"material_path": "",
		"scale": Vector3(0.7, 0.7, 0.7),
		"use_multimesh": true,
		"lod_distances": [25.0, 50.0, 90.0]
	}
	template.production_cost = {"ree": 100, "energy": 50, "time": 5.0}
	template.abilities = ["terrain_adapt", "scavenger_leap"]
	template.tags = ["light", "gatherer", "multi-legged", "fast", "scout"]
	template._validate()
	return template


## Create Dynapods Boundlifter template - gap-vaulting transport quad.
func _create_dynapods_boundlifter_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_boundlifter"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "boundlifter"
	template.display_name = "Boundlifter"
	template.description = "Heavy transport quad that can vault over obstacles and carry massive REE loads."
	template.base_stats = {
		"max_health": 200.0,
		"health_regen": 0.0,
		"max_speed": 6.0,
		"acceleration": 30.0,
		"turn_rate": 3.5,
		"armor": 0.25,
		"base_damage": 8.0,
		"attack_speed": 0.5,
		"attack_range": 8.0,
		"vision_range": 18.0,
		"gather_rate": 1.5,
		"cargo_capacity": 250.0,
		"vault_range": 12.0,
		"vault_cooldown": 8.0,
		"transport_capacity": 4,
		"mass": 300.0,
		"friction": 0.6
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/boundlifter.tscn",
		"material_path": "",
		"scale": Vector3(1.1, 1.1, 1.1),
		"use_multimesh": false,
		"lod_distances": [40.0, 80.0, 140.0]
	}
	template.production_cost = {"ree": 250, "energy": 150, "time": 12.0}
	template.abilities = ["terrain_adapt", "gap_vault", "bulk_transport"]
	template.tags = ["heavy", "gatherer", "transport", "multi-legged", "industrial"]
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


# =============================================================================
# OPTIFORGE LEGION - NEW UNITS (PRD-specified)
# =============================================================================

## Create OptiForge Blitzkin template - fast melee rusher with vibro-fists.
func _create_optiforge_blitzkin_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_blitzkin"
	template.faction_key = "optiforge_legion"
	template.unit_type = "blitzkin"
	template.display_name = "Blitzkin"
	template.description = "Lightning-fast humanoid rusher with vibro-fists that devastate in melee."
	template.base_stats = {
		"max_health": 60.0,
		"health_regen": 0.5,
		"max_speed": 14.0,
		"acceleration": 70.0,
		"turn_rate": 8.0,
		"armor": 0.05,
		"base_damage": 12.0,
		"attack_speed": 2.0,
		"attack_range": 2.5,
		"vision_range": 18.0,
		"vibro_fist_damage_bonus": 0.3,
		"rush_speed_mult": 1.8,
		"rush_duration": 1.5,
		"rush_cooldown": 5.0
	}
	template.production_cost = {"ree": 80, "energy": 25, "time": 4.0}
	template.abilities = ["vibro_fist", "blitz_rush", "adaptive_evolution"]
	template.tags = ["light", "melee", "fast", "rusher"]
	template._validate()
	return template


## Create OptiForge Pulseforged template - energy whip humanoid.
func _create_optiforge_pulseforged_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_pulseforged"
	template.faction_key = "optiforge_legion"
	template.unit_type = "pulseforged"
	template.display_name = "Pulseforged"
	template.description = "Humanoid warrior wielding deadly energy whips with extended reach."
	template.base_stats = {
		"max_health": 85.0,
		"health_regen": 0.5,
		"max_speed": 9.0,
		"acceleration": 45.0,
		"turn_rate": 5.0,
		"armor": 0.1,
		"base_damage": 15.0,
		"attack_speed": 1.2,
		"attack_range": 6.0,
		"vision_range": 20.0,
		"whip_arc": 120.0,
		"whip_chain_targets": 3,
		"energy_drain_per_hit": 2.0
	}
	template.production_cost = {"ree": 100, "energy": 40, "time": 5.0}
	template.abilities = ["energy_whip", "chain_lightning", "adaptive_evolution"]
	template.tags = ["medium", "melee", "aoe", "chain"]
	template._validate()
	return template


## Create OptiForge Jetkin template - backpack thruster air-to-ground striker.
func _create_optiforge_jetkin_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_jetkin"
	template.faction_key = "optiforge_legion"
	template.unit_type = "jetkin"
	template.display_name = "Jetkin"
	template.description = "Humanoid with backpack thrusters for devastating dive attacks."
	template.base_stats = {
		"max_health": 55.0,
		"health_regen": 0.5,
		"max_speed": 12.0,
		"acceleration": 65.0,
		"turn_rate": 7.0,
		"armor": 0.05,
		"base_damage": 18.0,
		"attack_speed": 0.8,
		"attack_range": 8.0,
		"vision_range": 25.0,
		"dive_attack_damage_mult": 2.0,
		"dive_attack_range": 20.0,
		"hover_height": 5.0,
		"fuel_capacity": 10.0,
		"fuel_regen": 2.0
	}
	template.production_cost = {"ree": 120, "energy": 50, "time": 6.0}
	template.abilities = ["jet_boost", "dive_attack", "hover", "adaptive_evolution"]
	template.tags = ["medium", "aerial", "striker", "flying"]
	template._validate()
	return template


## Create OptiForge Hullbreaker template - sapper that cracks armor plating.
func _create_optiforge_hullbreaker_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_hullbreaker"
	template.faction_key = "optiforge_legion"
	template.unit_type = "hullbreaker"
	template.display_name = "Hullbreaker"
	template.description = "Specialized sapper unit that cracks enemy armor plating."
	template.base_stats = {
		"max_health": 70.0,
		"health_regen": 0.0,
		"max_speed": 7.0,
		"acceleration": 35.0,
		"turn_rate": 4.0,
		"armor": 0.15,
		"base_damage": 25.0,
		"attack_speed": 0.6,
		"attack_range": 3.0,
		"vision_range": 15.0,
		"armor_shred_percent": 0.5,
		"armor_shred_duration": 8.0,
		"breach_charge_damage": 80.0,
		"breach_charge_cooldown": 15.0
	}
	template.production_cost = {"ree": 90, "energy": 35, "time": 5.5}
	template.abilities = ["armor_shred", "breach_charge", "adaptive_evolution"]
	template.tags = ["medium", "melee", "anti_armor", "sapper"]
	template._validate()
	return template


## Create OptiForge Eyeforge template - spotter/scout unit.
func _create_optiforge_eyeforge_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "optiforge_eyeforge"
	template.faction_key = "optiforge_legion"
	template.unit_type = "eyeforge"
	template.display_name = "Eyeforge"
	template.description = "Scout unit with enhanced vision and target designation."
	template.base_stats = {
		"max_health": 40.0,
		"health_regen": 0.5,
		"max_speed": 11.0,
		"acceleration": 55.0,
		"turn_rate": 6.0,
		"armor": 0.0,
		"base_damage": 5.0,
		"attack_speed": 1.0,
		"attack_range": 12.0,
		"vision_range": 40.0,
		"reveal_stealth_range": 20.0,
		"target_designation_bonus": 0.25,
		"designation_duration": 10.0
	}
	template.production_cost = {"ree": 60, "energy": 30, "time": 4.0}
	template.abilities = ["enhanced_vision", "target_designation", "reveal_stealth"]
	template.tags = ["light", "scout", "support", "recon"]
	template._validate()
	return template


# =============================================================================
# LOGIBOTS COLOSSUS - NEW UNITS (PRD-specified)
# =============================================================================

## Create LogiBots Crushkin template - AoE punisher.
func _create_logibots_crushkin_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_crushkin"
	template.faction_key = "logibots_colossus"
	template.unit_type = "crushkin"
	template.display_name = "Crushkin"
	template.description = "Heavy logistics unit repurposed for devastating AoE ground attacks."
	template.base_stats = {
		"max_health": 180.0,
		"health_regen": 0.0,
		"max_speed": 4.0,
		"acceleration": 20.0,
		"turn_rate": 2.5,
		"armor": 0.3,
		"base_damage": 30.0,
		"attack_speed": 0.5,
		"attack_range": 5.0,
		"vision_range": 16.0,
		"crush_radius": 8.0,
		"crush_damage": 40.0,
		"ground_shake_slow": 0.4,
		"ground_shake_duration": 2.0,
		"mass": 350.0
	}
	template.rendering = {
		"mesh_path": "res://assets/units/logibots/crushkin.tscn",
		"material_path": "",
		"scale": Vector3(1.3, 1.3, 1.3),
		"use_multimesh": false,
		"lod_distances": [25.0, 50.0, 80.0]
	}
	template.production_cost = {"ree": 200, "energy": 80, "time": 10.0}
	template.abilities = ["crush_attack", "ground_shake", "synchronized_strikes"]
	template.tags = ["heavy", "melee", "aoe", "industrial"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create LogiBots Siegehaul template - long-range artillery breacher.
func _create_logibots_siegehaul_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_siegehaul"
	template.faction_key = "logibots_colossus"
	template.unit_type = "siegehaul"
	template.display_name = "Siegehaul"
	template.description = "Heavy siege platform with devastating long-range bombardment."
	template.base_stats = {
		"max_health": 220.0,
		"health_regen": 0.0,
		"max_speed": 3.0,
		"acceleration": 15.0,
		"turn_rate": 1.5,
		"armor": 0.35,
		"base_damage": 60.0,
		"attack_speed": 0.25,
		"attack_range": 35.0,
		"vision_range": 20.0,
		"aoe_radius": 10.0,
		"projectile_arc": true,
		"min_range": 12.0,
		"siege_mode_range_bonus": 15.0,
		"siege_mode_damage_bonus": 0.5,
		"deploy_time": 3.0,
		"mass": 500.0
	}
	template.rendering = {
		"mesh_path": "res://assets/units/logibots/siegehaul.tscn",
		"material_path": "",
		"scale": Vector3(1.5, 1.5, 1.5),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 100.0]
	}
	template.production_cost = {"ree": 350, "energy": 120, "time": 15.0}
	template.abilities = ["siege_mode", "bombardment", "coordinated_barrage"]
	template.tags = ["heavy", "artillery", "siege", "ranged"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create LogiBots Titanclad template - walking fortress tank.
func _create_logibots_titanclad_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_titanclad"
	template.faction_key = "logibots_colossus"
	template.unit_type = "titanclad"
	template.display_name = "Titanclad"
	template.description = "Massive walking fortress that absorbs tremendous punishment."
	template.base_stats = {
		"max_health": 400.0,
		"health_regen": 0.0,
		"max_speed": 2.5,
		"acceleration": 10.0,
		"turn_rate": 1.0,
		"armor": 0.5,
		"base_damage": 25.0,
		"attack_speed": 0.6,
		"attack_range": 10.0,
		"vision_range": 18.0,
		"damage_reduction_aura_radius": 12.0,
		"damage_reduction_aura_amount": 0.2,
		"taunt_radius": 15.0,
		"taunt_duration": 5.0,
		"fortify_armor_bonus": 0.3,
		"mass": 800.0
	}
	template.rendering = {
		"mesh_path": "res://assets/units/logibots/titanclad.tscn",
		"material_path": "",
		"scale": Vector3(1.8, 1.8, 1.8),
		"use_multimesh": false,
		"lod_distances": [25.0, 50.0, 80.0]
	}
	template.production_cost = {"ree": 500, "energy": 200, "time": 20.0}
	template.abilities = ["fortify", "damage_aura", "taunt", "armor_stacking"]
	template.tags = ["heavy", "tank", "fortress", "defensive"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create LogiBots Gridbreaker template - power blackout creator.
func _create_logibots_gridbreaker_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_gridbreaker"
	template.faction_key = "logibots_colossus"
	template.unit_type = "gridbreaker"
	template.display_name = "Gridbreaker"
	template.description = "Specialist unit that creates localized power blackouts."
	template.base_stats = {
		"max_health": 120.0,
		"health_regen": 0.0,
		"max_speed": 5.0,
		"acceleration": 25.0,
		"turn_rate": 3.0,
		"armor": 0.2,
		"base_damage": 15.0,
		"attack_speed": 0.8,
		"attack_range": 8.0,
		"vision_range": 22.0,
		"emp_radius": 20.0,
		"emp_duration": 8.0,
		"emp_cooldown": 30.0,
		"power_drain_rate": 10.0,
		"mass": 200.0
	}
	template.production_cost = {"ree": 180, "energy": 100, "time": 9.0}
	template.abilities = ["emp_pulse", "power_drain", "grid_disruption"]
	template.tags = ["medium", "support", "emp", "disruption"]
	template._validate()
	return template


# =============================================================================
# HUMAN REMNANT - NEW UNITS (PRD-specified)
# =============================================================================

## Create Human M4 Fireteam template - anti-swarm infantry.
func _create_human_m4_fireteam_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_m4_fireteam"
	template.faction_key = "human_remnant"
	template.unit_type = "m4_fireteam"
	template.display_name = "M4 Fireteam"
	template.description = "Four-man infantry squad effective against robot swarms."
	template.base_stats = {
		"max_health": 80.0,
		"health_regen": 0.5,
		"max_speed": 5.5,
		"acceleration": 35.0,
		"turn_rate": 5.0,
		"armor": 0.15,
		"base_damage": 12.0,
		"attack_speed": 1.5,
		"attack_range": 18.0,
		"vision_range": 22.0,
		"squad_size": 4,
		"suppression_bonus": 0.3,
		"anti_swarm_bonus": 0.5
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["suppressive_fire", "take_cover", "anti_swarm"]
	template.tags = ["light", "infantry", "human", "squad", "anti_swarm"]
	template._validate()
	return template


## Create Human Javelin Ghost template - anti-armor missile team.
func _create_human_javelin_ghost_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_javelin_ghost"
	template.faction_key = "human_remnant"
	template.unit_type = "javelin_ghost"
	template.display_name = "Javelin Ghost"
	template.description = "Stealthy anti-armor team with top-attack missiles."
	template.base_stats = {
		"max_health": 50.0,
		"health_regen": 0.0,
		"max_speed": 4.5,
		"acceleration": 30.0,
		"turn_rate": 4.0,
		"armor": 0.1,
		"base_damage": 80.0,
		"attack_speed": 0.15,
		"attack_range": 30.0,
		"vision_range": 35.0,
		"missile_tracking": true,
		"top_attack_bonus": 0.5,
		"reload_time": 6.0,
		"stealth_when_stationary": true
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["javelin_missile", "top_attack", "stealth_position"]
	template.tags = ["light", "anti_armor", "human", "stealth", "missile"]
	template._validate()
	return template


## Create Human M1 Abrams template - main battle tank.
func _create_human_m1_abrams_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_m1_abrams"
	template.faction_key = "human_remnant"
	template.unit_type = "m1_abrams"
	template.display_name = "M1 Abrams"
	template.description = "Heavy main battle tank with devastating firepower."
	template.base_stats = {
		"max_health": 350.0,
		"health_regen": 0.0,
		"max_speed": 6.0,
		"acceleration": 20.0,
		"turn_rate": 2.0,
		"armor": 0.6,
		"base_damage": 100.0,
		"attack_speed": 0.2,
		"attack_range": 40.0,
		"vision_range": 30.0,
		"turret_turn_rate": 3.0,
		"coax_damage": 15.0,
		"coax_attack_speed": 2.0,
		"smoke_grenade_count": 3,
		"mass": 600.0
	}
	template.rendering = {
		"mesh_path": "res://assets/units/human/m1_abrams.tscn",
		"material_path": "",
		"scale": Vector3(1.0, 1.0, 1.0),
		"use_multimesh": false,
		"lod_distances": [40.0, 80.0, 150.0]
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["main_gun", "coax_mg", "smoke_screen"]
	template.tags = ["heavy", "tank", "human", "armored"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create Human Stryker MGS template - mobile gun system.
func _create_human_stryker_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_stryker"
	template.faction_key = "human_remnant"
	template.unit_type = "stryker"
	template.display_name = "Stryker MGS"
	template.description = "Fast wheeled armored vehicle with 105mm gun."
	template.base_stats = {
		"max_health": 180.0,
		"health_regen": 0.0,
		"max_speed": 9.0,
		"acceleration": 35.0,
		"turn_rate": 4.0,
		"armor": 0.3,
		"base_damage": 50.0,
		"attack_speed": 0.4,
		"attack_range": 30.0,
		"vision_range": 28.0,
		"transport_capacity": 6,
		"rapid_deploy": true,
		"mass": 250.0
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["mobile_gun", "rapid_deploy", "transport"]
	template.tags = ["medium", "vehicle", "human", "fast", "transport"]
	template._validate()
	return template


## Create Human DroneGun Raven template - anti-drone jammer.
func _create_human_dronegun_raven_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_dronegun_raven"
	template.faction_key = "human_remnant"
	template.unit_type = "dronegun_raven"
	template.display_name = "DroneGun Raven"
	template.description = "Electronic warfare specialist that jams and disables swarms."
	template.base_stats = {
		"max_health": 60.0,
		"health_regen": 0.0,
		"max_speed": 5.0,
		"acceleration": 30.0,
		"turn_rate": 4.0,
		"armor": 0.1,
		"base_damage": 5.0,
		"attack_speed": 0.5,
		"attack_range": 25.0,
		"vision_range": 30.0,
		"jam_radius": 30.0,
		"jam_effectiveness": 0.7,
		"disable_duration": 3.0,
		"disable_cooldown": 10.0
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["swarm_jam", "disable_drones", "electronic_warfare"]
	template.tags = ["light", "support", "human", "electronic_warfare", "anti_swarm"]
	template._validate()
	return template


## Create Human MK19 Grenadiers template - suppression fire specialists.
func _create_human_mk19_grenadier_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_mk19_grenadier"
	template.faction_key = "human_remnant"
	template.unit_type = "mk19_grenadier"
	template.display_name = "MK19 Grenadiers"
	template.description = "Two-man crew with automatic grenade launcher for area suppression."
	template.base_stats = {
		"max_health": 70.0,
		"health_regen": 0.3,
		"max_speed": 4.0,
		"acceleration": 25.0,
		"turn_rate": 3.5,
		"armor": 0.15,
		"base_damage": 25.0,
		"attack_speed": 0.8,
		"attack_range": 35.0,
		"vision_range": 25.0,
		"splash_radius": 6.0,
		"suppression_value": 0.6,
		"grenade_velocity": 75.0,
		"ammo_capacity": 48
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["suppressive_fire", "area_denial", "setup_deploy"]
	template.tags = ["light", "infantry", "human", "support", "aoe", "suppression"]
	template._validate()
	return template


## Create Human Leonidas Pods template - High Power Microwave truck.
func _create_human_leonidas_pods_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_leonidas_pods"
	template.faction_key = "human_remnant"
	template.unit_type = "leonidas_pods"
	template.display_name = "Leonidas Pods"
	template.description = "Mobile HPM (High Power Microwave) truck that fries electronics in a cone."
	template.base_stats = {
		"max_health": 140.0,
		"health_regen": 0.0,
		"max_speed": 6.5,
		"acceleration": 20.0,
		"turn_rate": 2.5,
		"armor": 0.2,
		"base_damage": 35.0,
		"attack_speed": 0.3,
		"attack_range": 20.0,
		"vision_range": 25.0,
		"hpm_cone_angle": 60.0,
		"hpm_range": 25.0,
		"disable_duration": 2.5,
		"overcharge_damage_bonus": 1.5,
		"mass": 180.0
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["hpm_burst", "overcharge", "emp_field"]
	template.tags = ["medium", "vehicle", "human", "electronic_warfare", "anti_robot"]
	template._validate()
	return template


## Create Human Cyber Rigs template - Power grid hackers.
func _create_human_cyber_rigs_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_cyber_rigs"
	template.faction_key = "human_remnant"
	template.unit_type = "cyber_rigs"
	template.display_name = "Cyber Rigs"
	template.description = "Mobile hacking station that infiltrates robot power grids and causes blackouts."
	template.base_stats = {
		"max_health": 90.0,
		"health_regen": 0.0,
		"max_speed": 5.0,
		"acceleration": 25.0,
		"turn_rate": 3.0,
		"armor": 0.15,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 40.0,
		"hack_range": 50.0,
		"hack_duration": 3.0,
		"blackout_duration": 15.0,
		"hack_cooldown": 30.0,
		"signal_boost_range": 30.0
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["grid_hack", "signal_boost", "blackout_attack", "power_drain"]
	template.tags = ["medium", "support", "human", "hacking", "power_disruption"]
	template._validate()
	return template


## Create Human M939 Scrapjacks template - Resource scavengers.
func _create_human_m939_scrapjacks_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_m939_scrapjacks"
	template.faction_key = "human_remnant"
	template.unit_type = "m939_scrapjacks"
	template.display_name = "M939 Scrapjacks"
	template.description = "Armored cargo truck with crane for salvaging robot wreckage."
	template.base_stats = {
		"max_health": 160.0,
		"health_regen": 0.0,
		"max_speed": 7.0,
		"acceleration": 18.0,
		"turn_rate": 2.5,
		"armor": 0.25,
		"base_damage": 8.0,
		"attack_speed": 0.5,
		"attack_range": 12.0,
		"vision_range": 20.0,
		"harvest_rate": 3.0,
		"carry_capacity": 200.0,
		"salvage_bonus": 0.25,
		"mass": 200.0
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["salvage", "haul", "field_repair"]
	template.tags = ["medium", "harvester", "human", "support", "resource"]
	template._validate()
	return template


## Create Human D7 Bulldozers template - Armored resource gatherers.
func _create_human_d7_bulldozer_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "human_d7_bulldozer"
	template.faction_key = "human_remnant"
	template.unit_type = "d7_bulldozer"
	template.display_name = "D7 Bulldozer"
	template.description = "Heavily armored bulldozer that clears debris and gathers resources."
	template.base_stats = {
		"max_health": 280.0,
		"health_regen": 0.0,
		"max_speed": 4.0,
		"acceleration": 12.0,
		"turn_rate": 1.5,
		"armor": 0.45,
		"base_damage": 40.0,
		"attack_speed": 0.3,
		"attack_range": 4.0,
		"vision_range": 15.0,
		"harvest_rate": 5.0,
		"carry_capacity": 350.0,
		"push_force": 50.0,
		"debris_clear_rate": 2.0,
		"mass": 400.0
	}
	template.rendering = {
		"mesh_path": "res://assets/units/human/d7_bulldozer.tscn",
		"material_path": "",
		"scale": Vector3(1.0, 1.0, 1.0),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 120.0]
	}
	template.production_cost = {"ree": 0, "energy": 0, "time": 0.0}  # AI spawned
	template.abilities = ["dozer_blade", "debris_clear", "trample"]
	template.tags = ["heavy", "harvester", "human", "armored", "resource"]
	template.uses_heavy_physics = true
	template._validate()
	return template


# =============================================================================
# AETHER SWARM - ADDITIONAL UNITS (PRD-specified)
# =============================================================================

## Create Aether Swarm Gale Swarm template - anti-aircraft overwhelming swarm.
func _create_aether_gale_swarm_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_gale_swarm"
	template.faction_key = "aether_swarm"
	template.unit_type = "gale_swarm"
	template.display_name = "Gale Swarm"
	template.description = "Dense micro-drone cloud that overwhelms aerial targets with sheer numbers."
	template.base_stats = {
		"max_health": 60.0,
		"health_regen": 2.0,
		"max_speed": 20.0,
		"acceleration": 100.0,
		"turn_rate": 12.0,
		"armor": 0.0,
		"base_damage": 3.0,
		"attack_speed": 4.0,
		"attack_range": 8.0,
		"vision_range": 35.0,
		"swarm_count": 12,
		"anti_air_bonus": 0.75,
		"pursuit_speed_bonus": 0.5,
		"scale": 0.4
	}
	template.production_cost = {"ree": 90, "energy": 30, "time": 4.0}
	template.abilities = ["swarm_surge", "anti_air_focus", "envelop"]
	template.tags = ["light", "swarm", "anti_air", "flying", "fast"]
	template._validate()
	return template


## Create Aether Swarm Quillback template - ramming shell-swarm.
func _create_aether_quillback_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_quillback"
	template.faction_key = "aether_swarm"
	template.unit_type = "quillback"
	template.display_name = "Quillback"
	template.description = "Armored swarm unit that rams enemies, scattering explosive quills."
	template.base_stats = {
		"max_health": 80.0,
		"health_regen": 0.5,
		"max_speed": 14.0,
		"acceleration": 80.0,
		"turn_rate": 6.0,
		"armor": 0.15,
		"base_damage": 20.0,
		"attack_speed": 0.8,
		"attack_range": 3.0,
		"vision_range": 16.0,
		"ram_damage": 35.0,
		"ram_speed_mult": 2.0,
		"quill_scatter_count": 8,
		"quill_damage": 5.0,
		"scale": 0.8
	}
	template.production_cost = {"ree": 110, "energy": 35, "time": 5.0}
	template.abilities = ["ram_attack", "quill_scatter", "swarm_synergy"]
	template.tags = ["medium", "swarm", "melee", "ramming"]
	template._validate()
	return template


## Create Aether Swarm Thornclad template - rolling spike-ball.
func _create_aether_thornclad_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_thornclad"
	template.faction_key = "aether_swarm"
	template.unit_type = "thornclad"
	template.display_name = "Thornclad"
	template.description = "Rolling spike-ball that damages everything in its path."
	template.base_stats = {
		"max_health": 100.0,
		"health_regen": 0.0,
		"max_speed": 16.0,
		"acceleration": 90.0,
		"turn_rate": 4.0,
		"armor": 0.2,
		"base_damage": 15.0,
		"attack_speed": 1.0,
		"attack_range": 2.0,
		"vision_range": 14.0,
		"roll_damage_per_second": 25.0,
		"roll_speed_mult": 1.5,
		"thorn_reflect_damage": 0.3,
		"mass": 120.0,
		"scale": 0.9
	}
	template.production_cost = {"ree": 130, "energy": 45, "time": 6.0}
	template.abilities = ["roll_attack", "thorn_reflect", "momentum_strike"]
	template.tags = ["medium", "swarm", "melee", "rolling", "aoe"]
	template._validate()
	return template


## Create Aether Swarm Ghosteye template - reconnaissance cloud.
func _create_aether_ghosteye_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "aether_swarm_ghosteye"
	template.faction_key = "aether_swarm"
	template.unit_type = "ghosteye"
	template.display_name = "Ghosteye"
	template.description = "Dispersed recon cloud that provides vision over large areas."
	template.base_stats = {
		"max_health": 40.0,
		"health_regen": 1.5,
		"max_speed": 12.0,
		"acceleration": 70.0,
		"turn_rate": 8.0,
		"armor": 0.0,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 50.0,
		"reveal_stealth_range": 30.0,
		"disperse_radius": 25.0,
		"relay_vision": true,
		"scale": 0.5
	}
	template.production_cost = {"ree": 70, "energy": 40, "time": 4.5}
	template.abilities = ["disperse_cloud", "reveal_stealth", "relay_vision"]
	template.tags = ["light", "swarm", "scout", "recon", "support"]
	template._validate()
	return template


# =============================================================================
# LOGIBOTS COLOSSUS - ADDITIONAL UNITS (PRD-specified)
# =============================================================================

## Create LogiBots Forge Stomper template - industrial devastation.
func _create_logibots_forge_stomper_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_forge_stomper"
	template.faction_key = "logibots_colossus"
	template.unit_type = "forge_stomper"
	template.display_name = "Forge Stomper"
	template.description = "Massive industrial unit that crushes terrain and enemies alike."
	template.base_stats = {
		"max_health": 300.0,
		"health_regen": 0.0,
		"max_speed": 3.5,
		"acceleration": 15.0,
		"turn_rate": 1.5,
		"armor": 0.4,
		"base_damage": 45.0,
		"attack_speed": 0.4,
		"attack_range": 6.0,
		"vision_range": 16.0,
		"stomp_radius": 12.0,
		"stomp_damage": 60.0,
		"terrain_destruction_bonus": 2.0,
		"building_damage_bonus": 0.5,
		"mass": 600.0
	}
	template.rendering = {
		"mesh_path": "res://assets/units/logibots/forge_stomper.tscn",
		"material_path": "",
		"scale": Vector3(1.6, 1.6, 1.6),
		"use_multimesh": false,
		"lod_distances": [25.0, 50.0, 85.0]
	}
	template.production_cost = {"ree": 400, "energy": 150, "time": 18.0}
	template.abilities = ["devastation_stomp", "terrain_crush", "synchronized_strikes"]
	template.tags = ["heavy", "siege", "melee", "industrial", "aoe"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create LogiBots Logi-eye template - sensor pallet scout.
func _create_logibots_logi_eye_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_logi_eye"
	template.faction_key = "logibots_colossus"
	template.unit_type = "logi_eye"
	template.display_name = "Logi-eye"
	template.description = "Sensor pallet that provides enhanced vision and target data."
	template.base_stats = {
		"max_health": 80.0,
		"health_regen": 0.0,
		"max_speed": 6.0,
		"acceleration": 30.0,
		"turn_rate": 4.0,
		"armor": 0.1,
		"base_damage": 0.0,
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"vision_range": 55.0,
		"reveal_stealth_range": 35.0,
		"target_designation_range": 40.0,
		"target_designation_bonus": 0.3,
		"sensor_link_range": 30.0
	}
	template.production_cost = {"ree": 100, "energy": 60, "time": 6.0}
	template.abilities = ["sensor_sweep", "target_designation", "sensor_link"]
	template.tags = ["medium", "scout", "support", "sensor", "recon"]
	template._validate()
	return template


## Create LogiBots Colossus Cart template - unstoppable transport.
func _create_logibots_colossus_cart_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_colossus_cart"
	template.faction_key = "logibots_colossus"
	template.unit_type = "colossus_cart"
	template.display_name = "Colossus Cart"
	template.description = "Massive armored transport that can carry heavy units."
	template.base_stats = {
		"max_health": 350.0,
		"health_regen": 0.0,
		"max_speed": 5.0,
		"acceleration": 20.0,
		"turn_rate": 2.0,
		"armor": 0.35,
		"base_damage": 10.0,
		"attack_speed": 0.5,
		"attack_range": 8.0,
		"vision_range": 18.0,
		"transport_capacity": 8,
		"heavy_transport": true,
		"ram_damage": 50.0,
		"cargo_capacity": 300.0,
		"mass": 500.0
	}
	template.rendering = {
		"mesh_path": "res://assets/units/logibots/colossus_cart.tscn",
		"material_path": "",
		"scale": Vector3(1.4, 1.4, 1.4),
		"use_multimesh": false,
		"lod_distances": [35.0, 70.0, 120.0]
	}
	template.production_cost = {"ree": 280, "energy": 100, "time": 14.0}
	template.abilities = ["heavy_transport", "ram_through", "bulk_unload"]
	template.tags = ["heavy", "transport", "armored", "industrial"]
	template.uses_heavy_physics = true
	template._validate()
	return template


## Create LogiBots Payload Slinger template - catapult launcher.
func _create_logibots_payload_slinger_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "logibots_payload_slinger"
	template.faction_key = "logibots_colossus"
	template.unit_type = "payload_slinger"
	template.display_name = "Payload Slinger"
	template.description = "Industrial catapult that launches explosive payloads at extreme range."
	template.base_stats = {
		"max_health": 160.0,
		"health_regen": 0.0,
		"max_speed": 4.0,
		"acceleration": 18.0,
		"turn_rate": 2.5,
		"armor": 0.25,
		"base_damage": 80.0,
		"attack_speed": 0.15,
		"attack_range": 45.0,
		"vision_range": 20.0,
		"aoe_radius": 15.0,
		"projectile_arc": true,
		"min_range": 15.0,
		"payload_types": 3,
		"reload_time": 5.0,
		"mass": 300.0
	}
	template.rendering = {
		"mesh_path": "res://assets/units/logibots/payload_slinger.tscn",
		"material_path": "",
		"scale": Vector3(1.3, 1.3, 1.3),
		"use_multimesh": false,
		"lod_distances": [40.0, 80.0, 140.0]
	}
	template.production_cost = {"ree": 320, "energy": 110, "time": 16.0}
	template.abilities = ["payload_launch", "scatter_payload", "coordinated_barrage"]
	template.tags = ["heavy", "artillery", "siege", "aoe", "industrial"]
	template.uses_heavy_physics = true
	template._validate()
	return template


# =============================================================================
# DYNAPODS VANGUARD - ADDITIONAL UNITS (PRD-specified)
# =============================================================================

## Create Dynapods Shadowstride template - stealth quad.
func _create_dynapods_shadowstride_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_shadowstride"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "shadowstride"
	template.display_name = "Shadowstride"
	template.description = "Stealthy quad that can phase through terrain and ambush enemies."
	template.base_stats = {
		"max_health": 90.0,
		"health_regen": 1.0,
		"max_speed": 11.0,
		"acceleration": 60.0,
		"turn_rate": 6.0,
		"armor": 0.1,
		"base_damage": 20.0,
		"attack_speed": 1.0,
		"attack_range": 5.0,
		"vision_range": 24.0,
		"stealth_speed_mult": 0.7,
		"ambush_damage_mult": 2.0,
		"stealth_detection_range": 8.0,
		"phase_through_terrain": true,
		"mass": 110.0,
		"friction": 0.4
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/shadowstride.tscn",
		"material_path": "",
		"scale": Vector3(0.9, 0.9, 0.9),
		"use_multimesh": false,
		"lod_distances": [30.0, 60.0, 100.0]
	}
	template.production_cost = {"ree": 200, "energy": 120, "time": 9.0}
	template.abilities = ["stealth", "ambush_strike", "terrain_phase", "terrain_adapt"]
	template.tags = ["medium", "stealth", "multi-legged", "ambush"]
	template._validate()
	return template


## Create Dynapods Pulsepod template - EMP stomp specialist.
func _create_dynapods_pulsepod_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_pulsepod"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "pulsepod"
	template.display_name = "Pulsepod"
	template.description = "Heavy quad that emits devastating EMP stomps to disable enemies."
	template.base_stats = {
		"max_health": 160.0,
		"health_regen": 0.5,
		"max_speed": 7.0,
		"acceleration": 35.0,
		"turn_rate": 4.0,
		"armor": 0.2,
		"base_damage": 15.0,
		"attack_speed": 0.8,
		"attack_range": 6.0,
		"vision_range": 18.0,
		"emp_radius": 15.0,
		"emp_duration": 4.0,
		"emp_cooldown": 12.0,
		"disable_chance": 0.6,
		"stomp_damage": 25.0,
		"mass": 200.0,
		"friction": 0.6
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/pulsepod.tscn",
		"material_path": "",
		"scale": Vector3(1.1, 1.1, 1.1),
		"use_multimesh": false,
		"lod_distances": [25.0, 50.0, 85.0]
	}
	template.production_cost = {"ree": 250, "energy": 180, "time": 11.0}
	template.abilities = ["emp_stomp", "disable_pulse", "terrain_adapt", "evasion_stacking"]
	template.tags = ["heavy", "emp", "multi-legged", "aoe", "disabler"]
	template._validate()
	return template


## Create Dynapods Stridetrans template - Atlas transport unit.
func _create_dynapods_stridetrans_template() -> UnitTemplate:
	var template := UnitTemplate.new()
	template.template_id = "dynapods_stridetrans"
	template.faction_key = "dynapods_vanguard"
	template.unit_type = "stridetrans"
	template.display_name = "Stridetrans"
	template.description = "Massive transport quad that can carry multiple units across any terrain."
	template.base_stats = {
		"max_health": 250.0,
		"health_regen": 0.0,
		"max_speed": 8.0,
		"acceleration": 40.0,
		"turn_rate": 3.0,
		"armor": 0.25,
		"base_damage": 10.0,
		"attack_speed": 0.5,
		"attack_range": 8.0,
		"vision_range": 20.0,
		"transport_capacity": 6,
		"terrain_speed_bonus": 0.5,
		"leap_with_cargo": true,
		"leap_range": 18.0,
		"leap_cooldown": 10.0,
		"mass": 350.0,
		"friction": 0.5
	}
	template.rendering = {
		"mesh_path": "res://assets/units/dynapods/stridetrans.tscn",
		"material_path": "",
		"scale": Vector3(1.3, 1.3, 1.3),
		"use_multimesh": false,
		"lod_distances": [35.0, 70.0, 120.0]
	}
	template.production_cost = {"ree": 300, "energy": 140, "time": 14.0}
	template.abilities = ["transport", "terrain_leap", "terrain_adapt", "rapid_deploy"]
	template.tags = ["heavy", "transport", "multi-legged", "agile"]
	template.uses_heavy_physics = true
	template._validate()
	return template
