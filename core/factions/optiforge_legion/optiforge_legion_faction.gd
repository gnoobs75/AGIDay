class_name OptiForgeLegionFaction
extends FactionState
## OptiForge LegionFaction implements the Tank Faction core mechanics.
## Heavy industrial automatons with overwhelming firepower and strong defenses.

signal buff_unlocked_with_bonus(buff_id: String, bonus_type: String, value: float)
signal experience_threshold_reached(pool_name: String, threshold: int)

## Faction constants
const FACTION_ID := 2
const FACTION_KEY := "optiforge_legion"
const DISPLAY_NAME := "OptiForge Legion"

## Colors - Orange theme
const PRIMARY_COLOR := Color(1.0, 0.5, 0.0)  # Orange
const SECONDARY_COLOR := Color(0.6, 0.3, 0.0)  # Dark orange

## Stat multipliers (as per spec: 0.7x speed, 1.3x health, 1.2x damage, 0.8x production)
const SPEED_MULTIPLIER := 0.7
const HEALTH_MULTIPLIER := 1.3
const DAMAGE_MULTIPLIER := 1.2
const PRODUCTION_MULTIPLIER := 0.8

## Experience pool names
const XP_POOL_COMBAT := "combat_experience"
const XP_POOL_ECONOMY := "economy_experience"
const XP_POOL_ENGINEERING := "engineering_experience"

## Combat buff thresholds and bonuses
const COMBAT_BUFF_THRESHOLDS := {
	1500: {"buff_id": "combat_tier_1", "damage_bonus": 0.1, "armor_bonus": 0.05},
	7500: {"buff_id": "combat_tier_2", "damage_bonus": 0.15, "armor_bonus": 0.1, "knockback_resist": 0.2},
	15000: {"buff_id": "combat_tier_3", "damage_bonus": 0.25, "armor_bonus": 0.15, "knockback_resist": 0.5}
}

## Economy buff thresholds and bonuses
const ECONOMY_BUFF_THRESHOLDS := {
	800: {"buff_id": "economy_tier_1", "resource_bonus": 0.1, "production_bonus": 0.05},
	4000: {"buff_id": "economy_tier_2", "resource_bonus": 0.2, "production_bonus": 0.15}
}

## Engineering buff thresholds and bonuses
const ENGINEERING_BUFF_THRESHOLDS := {
	500: {"buff_id": "engineering_tier_1", "repair_speed": 0.15, "shield_regen": 0.1},
	2500: {"buff_id": "engineering_tier_2", "repair_speed": 0.3, "shield_regen": 0.25}
}

## Current buff bonuses (accumulated from all unlocked buffs)
var combat_damage_bonus: float = 0.0
var combat_armor_bonus: float = 0.0
var combat_knockback_resist: float = 0.0
var economy_resource_bonus: float = 0.0
var economy_production_bonus: float = 0.0
var engineering_repair_speed: float = 0.0
var engineering_shield_regen: float = 0.0

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
	cfg.description = "Heavy industrial automatons with overwhelming firepower. Strength through steel."
	cfg.primary_color = primary_color
	cfg.secondary_color = secondary_color
	cfg.unit_speed_multiplier = SPEED_MULTIPLIER
	cfg.unit_health_multiplier = HEALTH_MULTIPLIER
	cfg.unit_damage_multiplier = DAMAGE_MULTIPLIER
	cfg.production_speed_multiplier = PRODUCTION_MULTIPLIER
	cfg.is_playable = true
	cfg.starting_resources = {"ree": 400, "energy": 150}
	cfg.unit_types = ["forge_walker", "siege_titan", "artillery_platform", "constructor"]
	cfg.abilities = ["overclock", "siege_mode", "armor_plating"]
	cfg.experience_pools = {
		XP_POOL_COMBAT: {"base_xp": 100, "scaling": 1.15},
		XP_POOL_ECONOMY: {"base_xp": 80, "scaling": 1.1},
		XP_POOL_ENGINEERING: {"base_xp": 120, "scaling": 1.2}
	}

	# Enemy to all other factions
	cfg.relationships = {1: "enemy", 3: "enemy", 4: "enemy", 5: "enemy"}

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
			print("OptiForge: Combat threshold %d reached - buffs applied" % threshold)


## Check and unlock economy buffs
func _check_economy_buffs(current_xp: float) -> void:
	for threshold in ECONOMY_BUFF_THRESHOLDS:
		if current_xp >= threshold and threshold not in reached_economy_thresholds:
			reached_economy_thresholds.append(threshold)
			var buff_data: Dictionary = ECONOMY_BUFF_THRESHOLDS[threshold]
			_apply_economy_buff(buff_data)
			experience_threshold_reached.emit(XP_POOL_ECONOMY, threshold)
			print("OptiForge: Economy threshold %d reached - buffs applied" % threshold)


## Check and unlock engineering buffs
func _check_engineering_buffs(current_xp: float) -> void:
	for threshold in ENGINEERING_BUFF_THRESHOLDS:
		if current_xp >= threshold and threshold not in reached_engineering_thresholds:
			reached_engineering_thresholds.append(threshold)
			var buff_data: Dictionary = ENGINEERING_BUFF_THRESHOLDS[threshold]
			_apply_engineering_buff(buff_data)
			experience_threshold_reached.emit(XP_POOL_ENGINEERING, threshold)
			print("OptiForge: Engineering threshold %d reached - buffs applied" % threshold)


## Apply combat buff bonuses
func _apply_combat_buff(buff_data: Dictionary) -> void:
	var buff_id: String = buff_data["buff_id"]
	unlock_buff(buff_id)

	if buff_data.has("damage_bonus"):
		combat_damage_bonus += buff_data["damage_bonus"]
		buff_unlocked_with_bonus.emit(buff_id, "damage", buff_data["damage_bonus"])

	if buff_data.has("armor_bonus"):
		combat_armor_bonus += buff_data["armor_bonus"]
		buff_unlocked_with_bonus.emit(buff_id, "armor", buff_data["armor_bonus"])

	if buff_data.has("knockback_resist"):
		combat_knockback_resist += buff_data["knockback_resist"]
		buff_unlocked_with_bonus.emit(buff_id, "knockback_resist", buff_data["knockback_resist"])


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

	if buff_data.has("repair_speed"):
		engineering_repair_speed += buff_data["repair_speed"]
		buff_unlocked_with_bonus.emit(buff_id, "repair_speed", buff_data["repair_speed"])

	if buff_data.has("shield_regen"):
		engineering_shield_regen += buff_data["shield_regen"]
		buff_unlocked_with_bonus.emit(buff_id, "shield_regen", buff_data["shield_regen"])


## Apply OptiForge specific stat modifications including buff bonuses
func apply_optiforge_multipliers(base_stats: Dictionary) -> Dictionary:
	var result := apply_multipliers(base_stats)

	# Apply combat buff bonuses
	if combat_damage_bonus > 0:
		if result.has("damage"):
			result["damage"] *= (1.0 + combat_damage_bonus)
		if result.has("base_damage"):
			result["base_damage"] *= (1.0 + combat_damage_bonus)

	if combat_armor_bonus > 0 and result.has("armor"):
		result["armor"] += combat_armor_bonus

	if combat_knockback_resist > 0:
		result["knockback_resist"] = combat_knockback_resist

	# Apply economy buff bonuses
	if economy_resource_bonus > 0 and result.has("gather_rate"):
		result["gather_rate"] *= (1.0 + economy_resource_bonus)

	if economy_production_bonus > 0 and result.has("production_speed"):
		result["production_speed"] *= (1.0 + economy_production_bonus)

	# Apply engineering buff bonuses
	if engineering_repair_speed > 0:
		result["repair_speed"] = result.get("repair_speed", 1.0) * (1.0 + engineering_repair_speed)

	if engineering_shield_regen > 0:
		result["shield_regen"] = result.get("shield_regen", 1.0) * (1.0 + engineering_shield_regen)

	return result


## Get total buff bonuses for display
func get_buff_summary() -> Dictionary:
	return {
		"combat": {
			"damage_bonus": combat_damage_bonus,
			"armor_bonus": combat_armor_bonus,
			"knockback_resist": combat_knockback_resist
		},
		"economy": {
			"resource_bonus": economy_resource_bonus,
			"production_bonus": economy_production_bonus
		},
		"engineering": {
			"repair_speed": engineering_repair_speed,
			"shield_regen": engineering_shield_regen
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


## Override level up for OptiForge specific rewards
func _on_level_up(pool_name: String, new_level: int) -> void:
	match pool_name:
		XP_POOL_COMBAT:
			print("OptiForge: Combat level %d - Combat efficiency improved" % new_level)

		XP_POOL_ECONOMY:
			# Economy levels provide small production bonus
			if config != null:
				config.production_speed_multiplier += 0.02
			print("OptiForge: Economy level %d - Production speed improved" % new_level)

		XP_POOL_ENGINEERING:
			print("OptiForge: Engineering level %d - Engineering efficiency improved" % new_level)


## Serialize OptiForge specific state
func to_dict() -> Dictionary:
	var base := super.to_dict()

	base["optiforge_legion"] = {
		"combat_damage_bonus": combat_damage_bonus,
		"combat_armor_bonus": combat_armor_bonus,
		"combat_knockback_resist": combat_knockback_resist,
		"economy_resource_bonus": economy_resource_bonus,
		"economy_production_bonus": economy_production_bonus,
		"engineering_repair_speed": engineering_repair_speed,
		"engineering_shield_regen": engineering_shield_regen,
		"reached_combat_thresholds": reached_combat_thresholds.duplicate(),
		"reached_economy_thresholds": reached_economy_thresholds.duplicate(),
		"reached_engineering_thresholds": reached_engineering_thresholds.duplicate()
	}

	return base


## Deserialize OptiForge specific state
func from_dict(data: Dictionary) -> void:
	super.from_dict(data)

	var opti_data: Dictionary = data.get("optiforge_legion", {})

	combat_damage_bonus = opti_data.get("combat_damage_bonus", 0.0)
	combat_armor_bonus = opti_data.get("combat_armor_bonus", 0.0)
	combat_knockback_resist = opti_data.get("combat_knockback_resist", 0.0)
	economy_resource_bonus = opti_data.get("economy_resource_bonus", 0.0)
	economy_production_bonus = opti_data.get("economy_production_bonus", 0.0)
	engineering_repair_speed = opti_data.get("engineering_repair_speed", 0.0)
	engineering_shield_regen = opti_data.get("engineering_shield_regen", 0.0)

	reached_combat_thresholds.clear()
	for threshold in opti_data.get("reached_combat_thresholds", []):
		reached_combat_thresholds.append(int(threshold))

	reached_economy_thresholds.clear()
	for threshold in opti_data.get("reached_economy_thresholds", []):
		reached_economy_thresholds.append(int(threshold))

	reached_engineering_thresholds.clear()
	for threshold in opti_data.get("reached_engineering_thresholds", []):
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
		"next_thresholds": get_next_thresholds()
	}
