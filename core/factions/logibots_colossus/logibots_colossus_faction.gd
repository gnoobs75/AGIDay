class_name LogiBotsColossusFaction
extends FactionState
## LogiBotsColossusFaction implements the LogiBots Colossus faction mechanics.
## Heavy-lifter siege warfare focused on industrial devastation and coordinated logistics.

signal tier_unlocked(tier: int)
signal siege_coordination_started(squad_id: int, unit_count: int)
signal siege_coordination_completed(squad_id: int, damage_bonus: float)
signal armor_stage_changed(unit_id: String, stage: int)

## Faction constants
const FACTION_ID := 4
const FACTION_KEY := "logibots_colossus"
const DISPLAY_NAME := "LogiBots Colossus"

## Colors - Industrial theme
const COLOR_GOLD := Color(0.831, 0.686, 0.216)  # #d4af37
const COLOR_BROWN := Color(0.545, 0.451, 0.333)  # #8b7355
const COLOR_DARK_GRAY := Color(0.412, 0.412, 0.412)  # #696969

## Stat multipliers - Heavy and slow, focused on resource gathering
const SPEED_MULTIPLIER := 0.7
const HEALTH_MULTIPLIER := 1.6
const DAMAGE_MULTIPLIER := 0.8
const RESOURCE_GATHER_MULTIPLIER := 1.5
const PRODUCTION_MULTIPLIER := 0.9

## Tier progression
enum Tier {
	TIER_1 = 1,  # Waves 1-5
	TIER_2 = 2,  # Waves 6-15
	TIER_3 = 3   # Waves 16+
}

const TIER_WAVE_THRESHOLDS := {
	Tier.TIER_1: 1,
	Tier.TIER_2: 6,
	Tier.TIER_3: 16
}

## Armor damage stages
enum ArmorStage {
	INTACT = 0,
	DENTED = 1,
	CRACKED = 2,
	DESTROYED = 3
}

## Experience pool names
const XP_POOL_LOGISTICS := "logistics_experience"
const XP_POOL_SIEGE := "siege_experience"
const XP_POOL_ENGINEERING := "engineering_experience"

## Current unlocked tier
var current_tier: int = Tier.TIER_1

## Tier-specific unit unlocks
var tier_units: Dictionary = {
	Tier.TIER_1: ["bulkripper", "haulforge"],
	Tier.TIER_2: ["crushkin", "forge_stomper", "ore_refiner"],
	Tier.TIER_3: ["titanclad", "siegehaul", "mobile_foundry"]
}

## Squad coordination system
var active_squads: Dictionary = {}  # squad_id -> {units: [], coordination_bonus: float}
var next_squad_id: int = 1

## Siege coordination bonuses
var base_siege_bonus: float = 0.2  # 20% damage bonus per coordinating unit
var max_siege_bonus: float = 2.0  # Maximum 200% bonus

## Heavy unit physics tracking
var heavy_units: Array[String] = ["titanclad", "siegehaul"]

## Colors for UI
var primary_color := COLOR_GOLD
var secondary_color := COLOR_BROWN
var tertiary_color := COLOR_DARK_GRAY


func _init(p_config: FactionConfig = null) -> void:
	super._init(p_config)

	# Set up experience pools
	if experience_pools.is_empty():
		experience_pools[XP_POOL_LOGISTICS] = 0.0
		experience_pools[XP_POOL_SIEGE] = 0.0
		experience_pools[XP_POOL_ENGINEERING] = 0.0
		experience_levels[XP_POOL_LOGISTICS] = 1
		experience_levels[XP_POOL_SIEGE] = 1
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
	cfg.description = "Massive resource-processing giants. Economy is the foundation of war."
	cfg.primary_color = primary_color
	cfg.secondary_color = secondary_color
	cfg.unit_speed_multiplier = SPEED_MULTIPLIER
	cfg.unit_health_multiplier = HEALTH_MULTIPLIER
	cfg.unit_damage_multiplier = DAMAGE_MULTIPLIER
	cfg.resource_gather_multiplier = RESOURCE_GATHER_MULTIPLIER
	cfg.production_speed_multiplier = PRODUCTION_MULTIPLIER
	cfg.is_playable = true
	cfg.starting_resources = {"ree": 600, "energy": 80}
	cfg.unit_types = ["bulkripper", "haulforge", "crushkin", "forge_stomper", "titanclad", "siegehaul"]
	cfg.abilities = ["siege_mode", "coordinated_strike", "bulk_transport", "resource_surge"]
	cfg.experience_pools = {
		XP_POOL_LOGISTICS: {"base_xp": 80, "scaling": 1.1},
		XP_POOL_SIEGE: {"base_xp": 120, "scaling": 1.2},
		XP_POOL_ENGINEERING: {"base_xp": 100, "scaling": 1.15}
	}

	# Enemy to all other factions
	cfg.relationships = {1: "enemy", 2: "enemy", 3: "enemy", 5: "enemy"}

	return cfg


## Check and unlock tiers based on wave number
func check_tier_unlock(wave_number: int) -> bool:
	var new_tier := Tier.TIER_1

	if wave_number >= TIER_WAVE_THRESHOLDS[Tier.TIER_3]:
		new_tier = Tier.TIER_3
	elif wave_number >= TIER_WAVE_THRESHOLDS[Tier.TIER_2]:
		new_tier = Tier.TIER_2

	if new_tier > current_tier:
		current_tier = new_tier
		tier_unlocked.emit(current_tier)
		print("LogiBots: Tier %d unlocked at wave %d" % [current_tier, wave_number])
		return true

	return false


## Get units available at current tier
func get_available_units() -> Array[String]:
	var available: Array[String] = []

	for tier in range(1, current_tier + 1):
		for unit_type in tier_units.get(tier, []):
			available.append(unit_type)

	return available


## Check if unit type is available at current tier
func is_unit_available(unit_type: String) -> bool:
	return unit_type in get_available_units()


## Check if unit type uses heavy physics (RigidBody3D)
func uses_heavy_physics(unit_type: String) -> bool:
	return unit_type in heavy_units


## Create a new siege coordination squad
func create_siege_squad(unit_ids: Array[String]) -> int:
	var squad_id := next_squad_id
	next_squad_id += 1

	active_squads[squad_id] = {
		"units": unit_ids.duplicate(),
		"coordination_bonus": 0.0,
		"start_time": Time.get_ticks_msec()
	}

	siege_coordination_started.emit(squad_id, unit_ids.size())
	return squad_id


## Calculate siege coordination bonus for a squad
func calculate_siege_bonus(squad_id: int) -> float:
	if not active_squads.has(squad_id):
		return 0.0

	var squad: Dictionary = active_squads[squad_id]
	var unit_count: int = squad["units"].size()

	# Bonus increases with number of coordinating units
	var bonus := base_siege_bonus * (unit_count - 1)  # -1 because first unit gets no bonus
	bonus = minf(bonus, max_siege_bonus)

	squad["coordination_bonus"] = bonus
	return bonus


## Complete siege coordination and apply damage bonus
func complete_siege_coordination(squad_id: int) -> float:
	if not active_squads.has(squad_id):
		return 0.0

	var bonus := calculate_siege_bonus(squad_id)
	siege_coordination_completed.emit(squad_id, bonus)

	active_squads.erase(squad_id)
	return bonus


## Disband a siege squad
func disband_siege_squad(squad_id: int) -> void:
	active_squads.erase(squad_id)


## Get armor stage threshold percentages
func get_armor_stage_thresholds() -> Dictionary:
	return {
		ArmorStage.INTACT: 1.0,     # 100%+
		ArmorStage.DENTED: 0.75,    # 75-99%
		ArmorStage.CRACKED: 0.5,    # 50-74%
		ArmorStage.DESTROYED: 0.0   # <50%
	}


## Calculate armor stage from health percentage
func get_armor_stage(health_percent: float) -> int:
	if health_percent >= 0.75:
		return ArmorStage.INTACT if health_percent >= 1.0 else ArmorStage.DENTED
	elif health_percent >= 0.5:
		return ArmorStage.CRACKED
	else:
		return ArmorStage.DESTROYED


## Get damage reduction for armor stage
func get_armor_reduction(stage: int) -> float:
	match stage:
		ArmorStage.INTACT: return 0.3  # 30% damage reduction
		ArmorStage.DENTED: return 0.2  # 20% damage reduction
		ArmorStage.CRACKED: return 0.1  # 10% damage reduction
		ArmorStage.DESTROYED: return 0.0  # No reduction
		_: return 0.0


## Override level up for LogiBots specific rewards
func _on_level_up(pool_name: String, new_level: int) -> void:
	match pool_name:
		XP_POOL_LOGISTICS:
			# Logistics levels improve resource gathering
			if config != null:
				config.resource_gather_multiplier += 0.05
			print("LogiBots: Logistics level %d - Resource gathering improved" % new_level)

		XP_POOL_SIEGE:
			# Siege levels improve coordination bonuses
			base_siege_bonus += 0.02
			max_siege_bonus += 0.1
			print("LogiBots: Siege level %d - Coordination bonus improved" % new_level)

		XP_POOL_ENGINEERING:
			# Engineering levels improve armor
			print("LogiBots: Engineering level %d - Armor efficiency improved" % new_level)


## Apply LogiBots specific stat modifications
func apply_logibots_multipliers(base_stats: Dictionary) -> Dictionary:
	var result := apply_multipliers(base_stats)

	# Apply resource gathering bonus
	if result.has("gather_rate") and config != null:
		result["gather_rate"] *= config.resource_gather_multiplier

	return result


## Serialize LogiBots specific state
func to_dict() -> Dictionary:
	var base := super.to_dict()

	var squads_data := {}
	for squad_id in active_squads:
		squads_data[squad_id] = active_squads[squad_id].duplicate()

	base["logibots"] = {
		"current_tier": current_tier,
		"base_siege_bonus": base_siege_bonus,
		"max_siege_bonus": max_siege_bonus,
		"active_squads": squads_data
	}

	return base


## Deserialize LogiBots specific state
func from_dict(data: Dictionary) -> void:
	super.from_dict(data)

	var logibots_data: Dictionary = data.get("logibots", {})
	current_tier = logibots_data.get("current_tier", Tier.TIER_1)
	base_siege_bonus = logibots_data.get("base_siege_bonus", 0.2)
	max_siege_bonus = logibots_data.get("max_siege_bonus", 2.0)

	active_squads.clear()
	var squads_data: Dictionary = logibots_data.get("active_squads", {})
	for squad_id in squads_data:
		active_squads[int(squad_id)] = squads_data[squad_id].duplicate()


## Get faction summary for UI
func get_summary() -> Dictionary:
	return {
		"faction_id": FACTION_ID,
		"faction_key": FACTION_KEY,
		"display_name": DISPLAY_NAME,
		"primary_color": primary_color,
		"secondary_color": secondary_color,
		"current_tier": current_tier,
		"available_units": get_available_units(),
		"active_squads": active_squads.size(),
		"logistics_level": get_level(XP_POOL_LOGISTICS),
		"siege_level": get_level(XP_POOL_SIEGE),
		"engineering_level": get_level(XP_POOL_ENGINEERING),
		"unlocked_buffs_count": unlocked_buffs.size()
	}
