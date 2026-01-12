class_name DynapodsVanguardFaction
extends FactionState
## DynapodsVanguardFaction implements the Dynapods Vanguard faction mechanics.
## Adaptive multi-legged mechs with modular loadouts and acrobatic maneuvers.

signal buff_unlocked_with_bonus(buff_id: String, bonus_type: String, value: float)
signal experience_threshold_reached(pool_name: String, threshold: int)
signal dodge_triggered(unit_id: String, damage_avoided: float)

## Faction constants
const FACTION_ID := 3
const FACTION_KEY := "dynapods_vanguard"
const DISPLAY_NAME := "Dynapods Vanguard"

## Colors - Light gray theme
const PRIMARY_COLOR := Color(0.7, 0.7, 0.75)  # Light gray
const SECONDARY_COLOR := Color(0.5, 0.5, 0.55)  # Medium gray

## Stat multipliers (as per spec: 1.2x speed, 0.9x health, 1.1x damage, 0.9x production)
const SPEED_MULTIPLIER := 1.2
const HEALTH_MULTIPLIER := 0.9
const DAMAGE_MULTIPLIER := 1.1
const PRODUCTION_MULTIPLIER := 0.9

## Experience pool names
const XP_POOL_COMBAT := "combat_experience"
const XP_POOL_ECONOMY := "economy_experience"
const XP_POOL_ENGINEERING := "engineering_experience"

## Combat buff thresholds (damage and speed bonuses)
const COMBAT_BUFF_THRESHOLDS := {
	1000: {"buff_id": "combat_tier_1", "damage_bonus": 0.1, "speed_bonus": 0.05},
	5000: {"buff_id": "combat_tier_2", "damage_bonus": 0.15, "speed_bonus": 0.1, "dodge_chance": 0.05},
	12000: {"buff_id": "combat_tier_3", "damage_bonus": 0.25, "speed_bonus": 0.15, "dodge_chance": 0.1}
}

## Economy buff thresholds (resource generation bonuses)
const ECONOMY_BUFF_THRESHOLDS := {
	600: {"buff_id": "economy_tier_1", "resource_bonus": 0.1},
	3000: {"buff_id": "economy_tier_2", "resource_bonus": 0.2, "production_bonus": 0.1}
}

## Engineering buff thresholds (module efficiency bonuses)
const ENGINEERING_BUFF_THRESHOLDS := {
	400: {"buff_id": "engineering_tier_1", "module_swap_speed": 0.2},
	2000: {"buff_id": "engineering_tier_2", "module_swap_speed": 0.4, "module_efficiency": 0.15}
}

## Core unit types
const CORE_UNITS := ["legbreaker", "vaultpounder", "titanquad", "skybound"]
## Support unit types
const SUPPORT_UNITS := ["quadripper", "leapscav", "shadowstride"]

## Current buff bonuses (accumulated from all unlocked buffs)
var combat_damage_bonus: float = 0.0
var combat_speed_bonus: float = 0.0
var combat_dodge_chance: float = 0.0
var economy_resource_bonus: float = 0.0
var economy_production_bonus: float = 0.0
var engineering_module_swap_speed: float = 0.0
var engineering_module_efficiency: float = 0.0

## Track which thresholds have been reached
var reached_combat_thresholds: Array[int] = []
var reached_economy_thresholds: Array[int] = []
var reached_engineering_thresholds: Array[int] = []

## Colors for UI
var primary_color := PRIMARY_COLOR
var secondary_color := SECONDARY_COLOR


func _init(p_config: FactionConfig = null) -> void:
	super._init(p_config)

	# Set up experience pools
	if experience_pools.is_empty():
		experience_pools[XP_POOL_COMBAT] = 0.0
		experience_pools[XP_POOL_ECONOMY] = 0.0
		experience_pools[XP_POOL_ENGINEERING] = 0.0
		experience_levels[XP_POOL_COMBAT] = 1
		experience_levels[XP_POOL_ECONOMY] = 1
		experience_levels[XP_POOL_ENGINEERING] = 1


## Initialize with default configuration
func initialize_default() -> void:
	var default_config := _create_default_config()
	initialize(default_config)


func _create_default_config() -> FactionConfig:
	var cfg := FactionConfig.new()
	cfg.faction_id = FACTION_ID
	cfg.faction_key = FACTION_KEY
	cfg.display_name = DISPLAY_NAME
	cfg.description = "Adaptive multi-legged mechs with modular loadouts. Versatility is victory."
	cfg.primary_color = primary_color
	cfg.secondary_color = secondary_color
	cfg.unit_speed_multiplier = SPEED_MULTIPLIER
	cfg.unit_health_multiplier = HEALTH_MULTIPLIER
	cfg.unit_damage_multiplier = DAMAGE_MULTIPLIER
	cfg.production_speed_multiplier = PRODUCTION_MULTIPLIER
	cfg.is_playable = true
	cfg.starting_resources = {"ree": 450, "energy": 120}
	cfg.unit_types = CORE_UNITS + SUPPORT_UNITS
	cfg.abilities = ["terrain_adapt", "module_swap", "rapid_deploy", "acrobatic_maneuver"]
	cfg.experience_pools = {
		XP_POOL_COMBAT: {"base_xp": 100, "scaling": 1.15},
		XP_POOL_ECONOMY: {"base_xp": 80, "scaling": 1.1},
		XP_POOL_ENGINEERING: {"base_xp": 90, "scaling": 1.12}
	}

	# Enemy to all other factions
	cfg.relationships = {1: "enemy", 2: "enemy", 4: "enemy", 5: "enemy"}

	return cfg


## Override add_experience to check buff thresholds
func add_experience(pool_name: String, amount: float) -> void:
	super.add_experience(pool_name, amount)
	_check_buff_thresholds(pool_name)


## Check and unlock buffs based on experience thresholds
func _check_buff_thresholds(pool_name: String) -> void:
	var current_xp := get_experience(pool_name)

	match pool_name:
		XP_POOL_COMBAT:
			_check_combat_buffs(current_xp)
		XP_POOL_ECONOMY:
			_check_economy_buffs(current_xp)
		XP_POOL_ENGINEERING:
			_check_engineering_buffs(current_xp)


## Check and unlock combat buffs
func _check_combat_buffs(current_xp: float) -> void:
	for threshold in COMBAT_BUFF_THRESHOLDS:
		if current_xp >= threshold and threshold not in reached_combat_thresholds:
			reached_combat_thresholds.append(threshold)
			var buff_data: Dictionary = COMBAT_BUFF_THRESHOLDS[threshold]
			_apply_combat_buff(buff_data)
			experience_threshold_reached.emit(XP_POOL_COMBAT, threshold)
			print("Dynapods: Combat threshold %d reached - buffs applied" % threshold)


## Check and unlock economy buffs
func _check_economy_buffs(current_xp: float) -> void:
	for threshold in ECONOMY_BUFF_THRESHOLDS:
		if current_xp >= threshold and threshold not in reached_economy_thresholds:
			reached_economy_thresholds.append(threshold)
			var buff_data: Dictionary = ECONOMY_BUFF_THRESHOLDS[threshold]
			_apply_economy_buff(buff_data)
			experience_threshold_reached.emit(XP_POOL_ECONOMY, threshold)
			print("Dynapods: Economy threshold %d reached - buffs applied" % threshold)


## Check and unlock engineering buffs
func _check_engineering_buffs(current_xp: float) -> void:
	for threshold in ENGINEERING_BUFF_THRESHOLDS:
		if current_xp >= threshold and threshold not in reached_engineering_thresholds:
			reached_engineering_thresholds.append(threshold)
			var buff_data: Dictionary = ENGINEERING_BUFF_THRESHOLDS[threshold]
			_apply_engineering_buff(buff_data)
			experience_threshold_reached.emit(XP_POOL_ENGINEERING, threshold)
			print("Dynapods: Engineering threshold %d reached - buffs applied" % threshold)


## Apply combat buff bonuses
func _apply_combat_buff(buff_data: Dictionary) -> void:
	var buff_id: String = buff_data["buff_id"]
	unlock_buff(buff_id)

	if buff_data.has("damage_bonus"):
		combat_damage_bonus += buff_data["damage_bonus"]
		buff_unlocked_with_bonus.emit(buff_id, "damage", buff_data["damage_bonus"])

	if buff_data.has("speed_bonus"):
		combat_speed_bonus += buff_data["speed_bonus"]
		buff_unlocked_with_bonus.emit(buff_id, "speed", buff_data["speed_bonus"])

	if buff_data.has("dodge_chance"):
		combat_dodge_chance += buff_data["dodge_chance"]
		buff_unlocked_with_bonus.emit(buff_id, "dodge_chance", buff_data["dodge_chance"])


## Apply economy buff bonuses
func _apply_economy_buff(buff_data: Dictionary) -> void:
	var buff_id: String = buff_data["buff_id"]
	unlock_buff(buff_id)

	if buff_data.has("resource_bonus"):
		economy_resource_bonus += buff_data["resource_bonus"]
		buff_unlocked_with_bonus.emit(buff_id, "resource", buff_data["resource_bonus"])

	if buff_data.has("production_bonus"):
		economy_production_bonus += buff_data["production_bonus"]
		buff_unlocked_with_bonus.emit(buff_id, "production", buff_data["production_bonus"])


## Apply engineering buff bonuses
func _apply_engineering_buff(buff_data: Dictionary) -> void:
	var buff_id: String = buff_data["buff_id"]
	unlock_buff(buff_id)

	if buff_data.has("module_swap_speed"):
		engineering_module_swap_speed += buff_data["module_swap_speed"]
		buff_unlocked_with_bonus.emit(buff_id, "module_swap_speed", buff_data["module_swap_speed"])

	if buff_data.has("module_efficiency"):
		engineering_module_efficiency += buff_data["module_efficiency"]
		buff_unlocked_with_bonus.emit(buff_id, "module_efficiency", buff_data["module_efficiency"])


## Check if a dodge occurs based on current dodge chance
func try_dodge() -> bool:
	if combat_dodge_chance <= 0:
		return false
	return randf() < combat_dodge_chance


## Apply Dynapods specific stat modifications including buff bonuses
func apply_dynapods_multipliers(base_stats: Dictionary) -> Dictionary:
	var result := apply_multipliers(base_stats)

	# Apply combat buff bonuses
	if combat_damage_bonus > 0:
		if result.has("damage"):
			result["damage"] *= (1.0 + combat_damage_bonus)
		if result.has("base_damage"):
			result["base_damage"] *= (1.0 + combat_damage_bonus)

	if combat_speed_bonus > 0:
		if result.has("speed"):
			result["speed"] *= (1.0 + combat_speed_bonus)
		if result.has("max_speed"):
			result["max_speed"] *= (1.0 + combat_speed_bonus)

	if combat_dodge_chance > 0:
		result["dodge_chance"] = combat_dodge_chance

	# Apply economy buff bonuses
	if economy_resource_bonus > 0 and result.has("gather_rate"):
		result["gather_rate"] *= (1.0 + economy_resource_bonus)

	if economy_production_bonus > 0 and result.has("production_speed"):
		result["production_speed"] *= (1.0 + economy_production_bonus)

	# Apply engineering buff bonuses
	if engineering_module_swap_speed > 0:
		result["module_swap_speed"] = 1.0 + engineering_module_swap_speed

	if engineering_module_efficiency > 0:
		result["module_efficiency"] = 1.0 + engineering_module_efficiency

	return result


## Get all unit types (core + support)
func get_all_unit_types() -> Array[String]:
	var all_units: Array[String] = []
	all_units.append_array(CORE_UNITS)
	all_units.append_array(SUPPORT_UNITS)
	return all_units


## Check if unit is a core unit
func is_core_unit(unit_type: String) -> bool:
	return unit_type in CORE_UNITS


## Check if unit is a support unit
func is_support_unit(unit_type: String) -> bool:
	return unit_type in SUPPORT_UNITS


## Get total buff bonuses for display
func get_buff_summary() -> Dictionary:
	return {
		"combat": {
			"damage_bonus": combat_damage_bonus,
			"speed_bonus": combat_speed_bonus,
			"dodge_chance": combat_dodge_chance
		},
		"economy": {
			"resource_bonus": economy_resource_bonus,
			"production_bonus": economy_production_bonus
		},
		"engineering": {
			"module_swap_speed": engineering_module_swap_speed,
			"module_efficiency": engineering_module_efficiency
		}
	}


## Get next buff thresholds for each pool
func get_next_thresholds() -> Dictionary:
	var result := {}

	# Combat next threshold
	var combat_xp := get_experience(XP_POOL_COMBAT)
	for threshold in COMBAT_BUFF_THRESHOLDS:
		if threshold not in reached_combat_thresholds:
			result["combat"] = {"threshold": threshold, "current": combat_xp, "progress": combat_xp / threshold}
			break

	# Economy next threshold
	var economy_xp := get_experience(XP_POOL_ECONOMY)
	for threshold in ECONOMY_BUFF_THRESHOLDS:
		if threshold not in reached_economy_thresholds:
			result["economy"] = {"threshold": threshold, "current": economy_xp, "progress": economy_xp / threshold}
			break

	# Engineering next threshold
	var engineering_xp := get_experience(XP_POOL_ENGINEERING)
	for threshold in ENGINEERING_BUFF_THRESHOLDS:
		if threshold not in reached_engineering_thresholds:
			result["engineering"] = {"threshold": threshold, "current": engineering_xp, "progress": engineering_xp / threshold}
			break

	return result


## Override level up for Dynapods specific rewards
func _on_level_up(pool_name: String, new_level: int) -> void:
	match pool_name:
		XP_POOL_COMBAT:
			# Combat levels increase dodge efficiency
			print("Dynapods: Combat level %d - Combat efficiency improved" % new_level)

		XP_POOL_ECONOMY:
			# Economy levels provide small resource bonus
			print("Dynapods: Economy level %d - Resource efficiency improved" % new_level)

		XP_POOL_ENGINEERING:
			# Engineering levels improve module capabilities
			print("Dynapods: Engineering level %d - Module efficiency improved" % new_level)


## Serialize Dynapods specific state
func to_dict() -> Dictionary:
	var base := super.to_dict()

	base["dynapods_vanguard"] = {
		"combat_damage_bonus": combat_damage_bonus,
		"combat_speed_bonus": combat_speed_bonus,
		"combat_dodge_chance": combat_dodge_chance,
		"economy_resource_bonus": economy_resource_bonus,
		"economy_production_bonus": economy_production_bonus,
		"engineering_module_swap_speed": engineering_module_swap_speed,
		"engineering_module_efficiency": engineering_module_efficiency,
		"reached_combat_thresholds": reached_combat_thresholds.duplicate(),
		"reached_economy_thresholds": reached_economy_thresholds.duplicate(),
		"reached_engineering_thresholds": reached_engineering_thresholds.duplicate()
	}

	return base


## Deserialize Dynapods specific state
func from_dict(data: Dictionary) -> void:
	super.from_dict(data)

	var dyna_data: Dictionary = data.get("dynapods_vanguard", {})

	combat_damage_bonus = dyna_data.get("combat_damage_bonus", 0.0)
	combat_speed_bonus = dyna_data.get("combat_speed_bonus", 0.0)
	combat_dodge_chance = dyna_data.get("combat_dodge_chance", 0.0)
	economy_resource_bonus = dyna_data.get("economy_resource_bonus", 0.0)
	economy_production_bonus = dyna_data.get("economy_production_bonus", 0.0)
	engineering_module_swap_speed = dyna_data.get("engineering_module_swap_speed", 0.0)
	engineering_module_efficiency = dyna_data.get("engineering_module_efficiency", 0.0)

	reached_combat_thresholds.clear()
	for threshold in dyna_data.get("reached_combat_thresholds", []):
		reached_combat_thresholds.append(int(threshold))

	reached_economy_thresholds.clear()
	for threshold in dyna_data.get("reached_economy_thresholds", []):
		reached_economy_thresholds.append(int(threshold))

	reached_engineering_thresholds.clear()
	for threshold in dyna_data.get("reached_engineering_thresholds", []):
		reached_engineering_thresholds.append(int(threshold))


## Get faction summary for UI
func get_summary() -> Dictionary:
	return {
		"faction_id": FACTION_ID,
		"faction_key": FACTION_KEY,
		"display_name": DISPLAY_NAME,
		"primary_color": primary_color,
		"secondary_color": secondary_color,
		"combat_level": get_level(XP_POOL_COMBAT),
		"economy_level": get_level(XP_POOL_ECONOMY),
		"engineering_level": get_level(XP_POOL_ENGINEERING),
		"combat_xp": get_experience(XP_POOL_COMBAT),
		"economy_xp": get_experience(XP_POOL_ECONOMY),
		"engineering_xp": get_experience(XP_POOL_ENGINEERING),
		"unlocked_buffs_count": unlocked_buffs.size(),
		"buff_bonuses": get_buff_summary(),
		"next_thresholds": get_next_thresholds(),
		"core_units": CORE_UNITS,
		"support_units": SUPPORT_UNITS
	}
