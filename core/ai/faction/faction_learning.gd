class_name FactionLearning
extends Resource
## FactionLearning is a persistent resource tracking faction progression.
## Implements 11-tier (0-10) hive mind progression with behavior/buff unlocks.

signal experience_gained(faction_id: String, category: String, amount: float, new_total: float)
signal tier_advanced(faction_id: String, old_tier: int, new_tier: int)
signal behavior_unlocked(faction_id: String, behavior: String, tier: int)
signal buff_unlocked(faction_id: String, buff: String, tier: int)

## Experience categories
enum Category {
	COMBAT = 0,
	ECONOMY = 1,
	ENGINEERING = 2
}

## Category string names
const CATEGORY_NAMES := ["combat", "economy", "engineering"]

## Progression tiers (0-10)
const MAX_TIER := 10
const TIER_COUNT := 11

## XP thresholds for each tier (cumulative total XP)
const TIER_THRESHOLDS := [
	0,      ## Tier 0: Starting
	500,    ## Tier 1
	1500,   ## Tier 2
	3000,   ## Tier 3
	5500,   ## Tier 4
	9000,   ## Tier 5
	14000,  ## Tier 6
	21000,  ## Tier 7
	30000,  ## Tier 8
	42000,  ## Tier 9
	58000   ## Tier 10: Maximum
]

## Faction identifiers
const FACTIONS := [
	"AETHER_SWARM",
	"OPTIFORGE_LEGION",
	"GLACIUS",
	"DYNAPODS",
	"LOGIBOTS",
	"HUMAN_REMNANT"
]

## Behavior unlocks per faction and tier
const BEHAVIOR_UNLOCKS := {
	"AETHER_SWARM": {
		1: ["swarm_coordination"],
		2: ["stealth_approach"],
		3: ["pheromone_trail"],
		5: ["hive_mind_sync"],
		7: ["mass_assault"],
		9: ["swarm_intelligence"],
		10: ["perfect_coordination"]
	},
	"GLACIUS": {
		1: ["defensive_stance"],
		2: ["armor_lock"],
		3: ["siege_preparation"],
		5: ["artillery_barrage"],
		7: ["shield_wall"],
		9: ["fortress_mode"],
		10: ["immovable_object"]
	},
	"DYNAPODS": {
		1: ["quick_dodge"],
		2: ["vault_terrain"],
		3: ["momentum_chain"],
		5: ["acrobatic_assault"],
		7: ["aerial_maneuver"],
		9: ["parkour_master"],
		10: ["unstoppable_motion"]
	},
	"LOGIBOTS": {
		1: ["basic_sync"],
		2: ["cargo_priority"],
		3: ["construct_boost"],
		5: ["coordinated_strike"],
		7: ["rapid_deploy"],
		9: ["perfect_logistics"],
		10: ["factory_efficiency"]
	},
	"HUMAN_REMNANT": {
		1: ["basic_tactics"],
		2: ["cover_usage"],
		3: ["coordinated_fire"],
		5: ["ambush_setup"],
		7: ["guerrilla_warfare"],
		9: ["tactical_mastery"],
		10: ["elite_training"]
	},
	"OPTIFORGE_LEGION": {
		1: ["adaptive_aim"],
		2: ["threat_analysis"],
		3: ["target_priority"],
		5: ["predictive_combat"],
		7: ["self_optimization"],
		9: ["combat_evolution"],
		10: ["perfect_efficiency"]
	}
}

## Buff unlocks per faction and tier
const BUFF_UNLOCKS := {
	"AETHER_SWARM": {
		1: {"swarm_damage": 0.02},
		3: {"attack_speed": 0.05},
		5: {"swarm_damage": 0.05},
		7: {"stealth": 0.10},
		10: {"swarm_damage": 0.10, "attack_speed": 0.10}
	},
	"GLACIUS": {
		1: {"armor": 0.05},
		3: {"health": 0.05},
		5: {"armor": 0.10},
		7: {"siege_damage": 0.15},
		10: {"armor": 0.15, "health": 0.10}
	},
	"DYNAPODS": {
		1: {"speed": 0.05},
		3: {"dodge": 0.03},
		5: {"speed": 0.10},
		7: {"impact_damage": 0.15},
		10: {"speed": 0.15, "dodge": 0.08}
	},
	"LOGIBOTS": {
		1: {"sync_bonus": 0.05},
		3: {"build_speed": 0.10},
		5: {"cargo_capacity": 0.20},
		7: {"sync_bonus": 0.10},
		10: {"sync_bonus": 0.15, "build_speed": 0.20}
	},
	"HUMAN_REMNANT": {
		1: {"accuracy": 0.03},
		3: {"range": 0.05},
		5: {"damage": 0.08},
		7: {"ambush_damage": 0.15},
		10: {"accuracy": 0.10, "damage": 0.12}
	},
	"OPTIFORGE_LEGION": {
		1: {"efficiency": 0.05},
		3: {"adaptation_rate": 0.10},
		5: {"damage": 0.08},
		7: {"armor": 0.08},
		10: {"efficiency": 0.15, "damage": 0.12}
	}
}

## Exported faction XP data for persistence
@export var faction_xp: Dictionary = {}

## Unlocked behaviors (faction_id -> Array[String])
var _unlocked_behaviors: Dictionary = {}

## Unlocked buffs (faction_id -> Dictionary)
var _unlocked_buffs: Dictionary = {}

## Current tiers (faction_id -> int)
var _faction_tiers: Dictionary = {}


func _init() -> void:
	_initialize_factions()


## Initialize all factions.
func _initialize_factions() -> void:
	for faction in FACTIONS:
		if not faction_xp.has(faction):
			faction_xp[faction] = {
				Category.COMBAT: 0.0,
				Category.ECONOMY: 0.0,
				Category.ENGINEERING: 0.0
			}
		_unlocked_behaviors[faction] = []
		_unlocked_buffs[faction] = {}
		_faction_tiers[faction] = 0

	# Recalculate unlocks from existing XP
	for faction in FACTIONS:
		_recalculate_unlocks(faction)


## Add combat experience.
func add_combat_xp(faction_id: String, amount: float) -> void:
	_add_xp(faction_id, Category.COMBAT, amount)


## Add economy experience.
func add_economy_xp(faction_id: String, amount: float) -> void:
	_add_xp(faction_id, Category.ECONOMY, amount)


## Add engineering experience.
func add_engineering_xp(faction_id: String, amount: float) -> void:
	_add_xp(faction_id, Category.ENGINEERING, amount)


## Internal XP addition.
func _add_xp(faction_id: String, category: int, amount: float) -> void:
	if not faction_xp.has(faction_id):
		return

	if amount <= 0:
		return

	var old_tier := get_tier(faction_id)
	faction_xp[faction_id][category] += amount
	var new_total: float = faction_xp[faction_id][category]

	experience_gained.emit(faction_id, CATEGORY_NAMES[category], amount, new_total)

	var new_tier := get_tier(faction_id)
	if new_tier > old_tier:
		_faction_tiers[faction_id] = new_tier
		_check_unlocks(faction_id, old_tier, new_tier)
		tier_advanced.emit(faction_id, old_tier, new_tier)


## Get total XP for faction across all categories.
func get_total_xp(faction_id: String) -> float:
	if not faction_xp.has(faction_id):
		return 0.0

	var total := 0.0
	for category in Category.values():
		total += faction_xp[faction_id].get(category, 0.0)
	return total


## Get XP for specific category.
func get_category_xp(faction_id: String, category: int) -> float:
	if not faction_xp.has(faction_id):
		return 0.0
	return faction_xp[faction_id].get(category, 0.0)


## Get current tier for faction.
func get_tier(faction_id: String) -> int:
	var total := get_total_xp(faction_id)

	for tier in range(MAX_TIER, -1, -1):
		if total >= TIER_THRESHOLDS[tier]:
			return tier

	return 0


## Get XP needed for next tier.
func get_xp_to_next_tier(faction_id: String) -> float:
	var current_tier := get_tier(faction_id)

	if current_tier >= MAX_TIER:
		return 0.0

	var total := get_total_xp(faction_id)
	return TIER_THRESHOLDS[current_tier + 1] - total


## Get progress to next tier (0.0 - 1.0).
func get_tier_progress(faction_id: String) -> float:
	var current_tier := get_tier(faction_id)

	if current_tier >= MAX_TIER:
		return 1.0

	var total := get_total_xp(faction_id)
	var tier_start := float(TIER_THRESHOLDS[current_tier])
	var tier_end := float(TIER_THRESHOLDS[current_tier + 1])

	return (total - tier_start) / (tier_end - tier_start)


## Check and apply unlocks for tier advancement.
func _check_unlocks(faction_id: String, old_tier: int, new_tier: int) -> void:
	# Unlock behaviors
	if BEHAVIOR_UNLOCKS.has(faction_id):
		var faction_behaviors: Dictionary = BEHAVIOR_UNLOCKS[faction_id]
		for tier in range(old_tier + 1, new_tier + 1):
			if faction_behaviors.has(tier):
				for behavior in faction_behaviors[tier]:
					if behavior not in _unlocked_behaviors[faction_id]:
						_unlocked_behaviors[faction_id].append(behavior)
						behavior_unlocked.emit(faction_id, behavior, tier)

	# Unlock buffs
	if BUFF_UNLOCKS.has(faction_id):
		var faction_buffs: Dictionary = BUFF_UNLOCKS[faction_id]
		for tier in range(old_tier + 1, new_tier + 1):
			if faction_buffs.has(tier):
				var tier_buffs: Dictionary = faction_buffs[tier]
				for buff_name in tier_buffs:
					var value: float = tier_buffs[buff_name]
					_unlocked_buffs[faction_id][buff_name] = _unlocked_buffs[faction_id].get(buff_name, 0.0) + value
					buff_unlocked.emit(faction_id, buff_name, tier)


## Recalculate all unlocks from current XP.
func _recalculate_unlocks(faction_id: String) -> void:
	var tier := get_tier(faction_id)
	_faction_tiers[faction_id] = tier
	_unlocked_behaviors[faction_id] = []
	_unlocked_buffs[faction_id] = {}

	# Apply all unlocks up to current tier
	if tier > 0:
		_check_unlocks(faction_id, 0, tier)


## Get all unlocked behaviors for faction.
func get_unlocked_behaviors(faction_id: String) -> Array:
	return _unlocked_behaviors.get(faction_id, []).duplicate()


## Get all unlocked buffs for faction.
func get_unlocked_buffs(faction_id: String) -> Dictionary:
	return _unlocked_buffs.get(faction_id, {}).duplicate()


## Check if behavior is unlocked.
func has_behavior(faction_id: String, behavior: String) -> bool:
	if not _unlocked_behaviors.has(faction_id):
		return false
	return behavior in _unlocked_behaviors[faction_id]


## Get buff value (returns 0 if not unlocked).
func get_buff_value(faction_id: String, buff_name: String) -> float:
	if not _unlocked_buffs.has(faction_id):
		return 0.0
	return _unlocked_buffs[faction_id].get(buff_name, 0.0)


## Get progression state for faction.
func get_progression_state(faction_id: String) -> Dictionary:
	return {
		"faction_id": faction_id,
		"tier": get_tier(faction_id),
		"total_xp": get_total_xp(faction_id),
		"combat_xp": get_category_xp(faction_id, Category.COMBAT),
		"economy_xp": get_category_xp(faction_id, Category.ECONOMY),
		"engineering_xp": get_category_xp(faction_id, Category.ENGINEERING),
		"xp_to_next_tier": get_xp_to_next_tier(faction_id),
		"tier_progress": get_tier_progress(faction_id),
		"unlocked_behaviors": get_unlocked_behaviors(faction_id),
		"unlocked_buffs": get_unlocked_buffs(faction_id)
	}


## Get all progression states.
func get_all_progression_states() -> Dictionary:
	var states: Dictionary = {}
	for faction in FACTIONS:
		states[faction] = get_progression_state(faction)
	return states


## Reset faction progression (for testing).
func reset_faction(faction_id: String) -> void:
	if not faction_xp.has(faction_id):
		return

	faction_xp[faction_id] = {
		Category.COMBAT: 0.0,
		Category.ECONOMY: 0.0,
		Category.ENGINEERING: 0.0
	}
	_unlocked_behaviors[faction_id] = []
	_unlocked_buffs[faction_id] = {}
	_faction_tiers[faction_id] = 0


## Serialization for save/load.
func save_to_dict() -> Dictionary:
	var behaviors_data: Dictionary = {}
	for faction in _unlocked_behaviors:
		behaviors_data[faction] = _unlocked_behaviors[faction].duplicate()

	var buffs_data: Dictionary = {}
	for faction in _unlocked_buffs:
		buffs_data[faction] = _unlocked_buffs[faction].duplicate()

	return {
		"faction_xp": faction_xp.duplicate(true),
		"unlocked_behaviors": behaviors_data,
		"unlocked_buffs": buffs_data,
		"faction_tiers": _faction_tiers.duplicate()
	}


func load_from_dict(data: Dictionary) -> void:
	faction_xp = data.get("faction_xp", {}).duplicate(true)

	_unlocked_behaviors.clear()
	var behaviors_data: Dictionary = data.get("unlocked_behaviors", {})
	for faction in behaviors_data:
		_unlocked_behaviors[faction] = behaviors_data[faction].duplicate()

	_unlocked_buffs.clear()
	var buffs_data: Dictionary = data.get("unlocked_buffs", {})
	for faction in buffs_data:
		_unlocked_buffs[faction] = buffs_data[faction].duplicate()

	_faction_tiers = data.get("faction_tiers", {}).duplicate()

	# Initialize any missing factions
	_initialize_factions()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_summaries: Dictionary = {}

	for faction in FACTIONS:
		faction_summaries[faction] = {
			"tier": get_tier(faction),
			"total_xp": get_total_xp(faction),
			"behaviors_unlocked": get_unlocked_behaviors(faction).size(),
			"buffs_unlocked": get_unlocked_buffs(faction).size()
		}

	return {
		"max_tier": MAX_TIER,
		"tier_count": TIER_COUNT,
		"factions": faction_summaries
	}
