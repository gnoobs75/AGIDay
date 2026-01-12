class_name HumanResistanceFaction
extends FactionState
## HumanResistanceFaction implements the Human Resistance NPC faction.
## AI-controlled hostile faction that attacks all robot factions.

signal unit_spawned(unit_type: String, unit_id: String)
signal unit_defeated(unit_type: String, resources_dropped: float)
signal wave_difficulty_changed(multiplier: float)
signal commander_buff_applied(commander_id: String, affected_units: int)

## Faction constants
const FACTION_ID := 5
const FACTION_KEY := "human_remnant"
const DISPLAY_NAME := "Human Resistance"

## Faction stat multipliers
const HEALTH_MULTIPLIER := 0.8
const DAMAGE_MULTIPLIER := 1.0
const ARMOR_MULTIPLIER := 0.6

## Colors
const PRIMARY_COLOR := Color(0.8, 0.2, 0.2)  # Red
const SECONDARY_COLOR := Color(0.4, 0.1, 0.1)  # Dark red

## Unit type definitions
enum UnitType {
	SOLDIER = 0,
	SNIPER = 1,
	HEAVY_GUNNER = 2,
	COMMANDER = 3
}

## Unit template data
const UNIT_TEMPLATES := {
	"soldier": {
		"type": UnitType.SOLDIER,
		"display_name": "Soldier",
		"base_health": 30.0,
		"base_damage": 8.0,
		"base_armor": 0.1,
		"attack_range": 15.0,
		"resource_drop": 25.0,
		"movement_speed": 6.0,
		"attack_speed": 1.2,
		"special_abilities": []
	},
	"sniper": {
		"type": UnitType.SNIPER,
		"display_name": "Sniper",
		"base_health": 25.0,
		"base_damage": 15.0,
		"base_armor": 0.05,
		"attack_range": 30.0,
		"resource_drop": 40.0,
		"movement_speed": 5.0,
		"attack_speed": 0.6,
		"critical_chance": 0.3,
		"critical_multiplier": 2.0,
		"special_abilities": ["precision_shot"]
	},
	"heavy_gunner": {
		"type": UnitType.HEAVY_GUNNER,
		"display_name": "Heavy Gunner",
		"base_health": 50.0,
		"base_damage": 12.0,
		"base_armor": 0.3,
		"attack_range": 20.0,
		"resource_drop": 50.0,
		"movement_speed": 4.0,
		"attack_speed": 0.8,
		"aoe_radius": 5.0,
		"special_abilities": ["suppressing_fire"]
	},
	"commander": {
		"type": UnitType.COMMANDER,
		"display_name": "Commander",
		"base_health": 80.0,
		"base_damage": 10.0,
		"base_armor": 0.2,
		"attack_range": 15.0,
		"resource_drop": 100.0,
		"movement_speed": 5.0,
		"attack_speed": 1.0,
		"buff_radius": 20.0,
		"buff_damage_bonus": 0.2,
		"buff_armor_bonus": 0.1,
		"special_abilities": ["rally", "tactical_command"]
	}
}

## Current state
var current_wave: int = 0
var difficulty_multiplier: float = 1.0
var total_units_spawned: int = 0
var total_resources_dropped: float = 0.0

## Unit tracking
var active_units: Dictionary = {}  # unit_id -> unit_data
var unit_count_by_type: Dictionary = {}  # unit_type -> count

## Commander buffs tracking
var active_commander_buffs: Dictionary = {}  # commander_id -> {affected_units: [], radius: float}

## Hacking immunity flag (always true for Human Resistance)
var immune_to_hacking := true

## Performance limits
const MAX_UNITS := 500
const MAX_MEMORY_MB := 50.0


func _init(p_config: FactionConfig = null) -> void:
	super._init(p_config)

	# Initialize unit counts
	for unit_key in UNIT_TEMPLATES:
		unit_count_by_type[unit_key] = 0


## Initialize with default configuration
func initialize_default() -> void:
	var default_config := _create_default_config()
	initialize(default_config)


func _create_default_config() -> FactionConfig:
	var cfg := FactionConfig.new()
	cfg.faction_id = FACTION_ID
	cfg.faction_key = FACTION_KEY
	cfg.display_name = DISPLAY_NAME
	cfg.description = "Desperate survivors fighting to reclaim their world. The last hope of humanity."
	cfg.primary_color = PRIMARY_COLOR
	cfg.secondary_color = SECONDARY_COLOR
	cfg.unit_health_multiplier = HEALTH_MULTIPLIER
	cfg.unit_damage_multiplier = DAMAGE_MULTIPLIER
	cfg.is_playable = false
	cfg.is_ai_only = true
	cfg.starting_resources = {"ree": 0, "energy": 0}  # AI doesn't use resources
	cfg.unit_types = ["soldier", "sniper", "heavy_gunner", "commander"]
	cfg.abilities = ["guerrilla_tactics", "emp_burst", "rally", "tactical_command"]

	# Enemy to all robot factions
	cfg.relationships = {1: "enemy", 2: "enemy", 3: "enemy", 4: "enemy"}

	return cfg


## Get unit template with faction multipliers applied
func get_unit_template(unit_type: String) -> Dictionary:
	if not UNIT_TEMPLATES.has(unit_type):
		return {}

	var base := UNIT_TEMPLATES[unit_type].duplicate(true)

	# Apply faction multipliers
	base["health"] = base["base_health"] * HEALTH_MULTIPLIER * difficulty_multiplier
	base["damage"] = base["base_damage"] * DAMAGE_MULTIPLIER * difficulty_multiplier
	base["armor"] = base["base_armor"] * ARMOR_MULTIPLIER

	# Scale resource drops with difficulty
	base["resource_drop"] = base["resource_drop"] * (1.0 + (difficulty_multiplier - 1.0) * 0.5)

	return base


## Check if can spawn more units
func can_spawn_unit() -> bool:
	return get_total_unit_count() < MAX_UNITS


## Get total unit count
func get_total_unit_count() -> int:
	var total := 0
	for unit_type in unit_count_by_type:
		total += unit_count_by_type[unit_type]
	return total


## Register a spawned unit
func register_unit(unit_id: String, unit_type: String, position: Vector3) -> Dictionary:
	if not can_spawn_unit():
		return {}

	var template := get_unit_template(unit_type)
	if template.is_empty():
		return {}

	var unit_data := {
		"unit_id": unit_id,
		"unit_type": unit_type,
		"position": position,
		"health": template["health"],
		"max_health": template["health"],
		"damage": template["damage"],
		"armor": template["armor"],
		"resource_drop": template["resource_drop"],
		"is_alive": true,
		"spawn_time": Time.get_ticks_msec(),
		"immune_to_hacking": immune_to_hacking
	}

	active_units[unit_id] = unit_data
	unit_count_by_type[unit_type] = unit_count_by_type.get(unit_type, 0) + 1
	total_units_spawned += 1

	unit_spawned.emit(unit_type, unit_id)
	return unit_data


## Handle unit defeat
func defeat_unit(unit_id: String) -> float:
	if not active_units.has(unit_id):
		return 0.0

	var unit_data: Dictionary = active_units[unit_id]
	var unit_type: String = unit_data["unit_type"]
	var resources := float(unit_data["resource_drop"])

	# Update tracking
	unit_data["is_alive"] = false
	unit_count_by_type[unit_type] = maxi(0, unit_count_by_type.get(unit_type, 0) - 1)
	total_resources_dropped += resources

	# Remove from active
	active_units.erase(unit_id)

	# Handle commander death (remove buffs)
	if unit_type == "commander" and active_commander_buffs.has(unit_id):
		active_commander_buffs.erase(unit_id)

	unit_defeated.emit(unit_type, resources)
	record_stat("units_lost", 1)

	return resources


## Set wave and update difficulty
func set_wave(wave_number: int) -> void:
	current_wave = wave_number
	_update_difficulty()


## Update difficulty multiplier based on wave
func _update_difficulty() -> void:
	# Difficulty scales with wave number
	# Wave 1: 1.0, Wave 10: 1.5, Wave 20: 2.0, etc.
	var new_multiplier := 1.0 + (current_wave - 1) * 0.05
	new_multiplier = clampf(new_multiplier, 1.0, 5.0)

	if new_multiplier != difficulty_multiplier:
		difficulty_multiplier = new_multiplier
		wave_difficulty_changed.emit(difficulty_multiplier)


## Apply commander buff to nearby units
func apply_commander_buff(commander_id: String, nearby_unit_ids: Array[String]) -> void:
	if not active_units.has(commander_id):
		return

	var commander_data: Dictionary = active_units[commander_id]
	if commander_data["unit_type"] != "commander":
		return

	var template := UNIT_TEMPLATES["commander"]
	var damage_bonus: float = template.get("buff_damage_bonus", 0.2)
	var armor_bonus: float = template.get("buff_armor_bonus", 0.1)

	active_commander_buffs[commander_id] = {
		"affected_units": nearby_unit_ids.duplicate(),
		"damage_bonus": damage_bonus,
		"armor_bonus": armor_bonus
	}

	commander_buff_applied.emit(commander_id, nearby_unit_ids.size())


## Check if unit is buffed by a commander
func get_commander_buff(unit_id: String) -> Dictionary:
	for commander_id in active_commander_buffs:
		var buff_data: Dictionary = active_commander_buffs[commander_id]
		if unit_id in buff_data["affected_units"]:
			return {
				"damage_bonus": buff_data["damage_bonus"],
				"armor_bonus": buff_data["armor_bonus"]
			}
	return {}


## Check if unit is immune to hacking
func is_immune_to_hacking(_unit_id: String) -> bool:
	return immune_to_hacking  # All human units are immune


## Get unit count by type
func get_unit_count(unit_type: String) -> int:
	return unit_count_by_type.get(unit_type, 0)


## Get estimated memory usage in MB
func get_memory_usage_mb() -> float:
	# Rough estimate: ~100 bytes per unit data
	var unit_memory := get_total_unit_count() * 100
	return float(unit_memory) / (1024 * 1024)


## Clear all units (for reset)
func clear_all_units() -> void:
	active_units.clear()
	active_commander_buffs.clear()

	for unit_type in unit_count_by_type:
		unit_count_by_type[unit_type] = 0


## Serialize faction state
func to_dict() -> Dictionary:
	var base := super.to_dict()

	base["human_resistance"] = {
		"current_wave": current_wave,
		"difficulty_multiplier": difficulty_multiplier,
		"total_units_spawned": total_units_spawned,
		"total_resources_dropped": total_resources_dropped,
		"unit_count_by_type": unit_count_by_type.duplicate(),
		"immune_to_hacking": immune_to_hacking
	}

	return base


## Deserialize faction state
func from_dict(data: Dictionary) -> void:
	super.from_dict(data)

	var hr_data: Dictionary = data.get("human_resistance", {})
	current_wave = hr_data.get("current_wave", 0)
	difficulty_multiplier = hr_data.get("difficulty_multiplier", 1.0)
	total_units_spawned = hr_data.get("total_units_spawned", 0)
	total_resources_dropped = hr_data.get("total_resources_dropped", 0.0)
	unit_count_by_type = hr_data.get("unit_count_by_type", {}).duplicate()
	immune_to_hacking = hr_data.get("immune_to_hacking", true)


## Get faction summary
func get_summary() -> Dictionary:
	return {
		"faction_id": FACTION_ID,
		"faction_key": FACTION_KEY,
		"display_name": DISPLAY_NAME,
		"primary_color": PRIMARY_COLOR,
		"secondary_color": SECONDARY_COLOR,
		"current_wave": current_wave,
		"difficulty_multiplier": difficulty_multiplier,
		"total_units": get_total_unit_count(),
		"soldiers": get_unit_count("soldier"),
		"snipers": get_unit_count("sniper"),
		"heavy_gunners": get_unit_count("heavy_gunner"),
		"commanders": get_unit_count("commander"),
		"total_spawned": total_units_spawned,
		"total_resources_dropped": total_resources_dropped,
		"memory_usage_mb": get_memory_usage_mb()
	}
