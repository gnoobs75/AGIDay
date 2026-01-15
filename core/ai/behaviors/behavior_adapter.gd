class_name BehaviorAdapter
extends RefCounted
## BehaviorAdapter modifies behaviors based on faction experience level.

signal behavior_unlocked(faction_id: String, behavior: String)
signal adaptation_applied(unit_id: int, adaptation: String, level: int)

## Experience thresholds for behavior adaptations
const XP_BASIC := 0.0
const XP_IMPROVED := 1000.0
const XP_ADVANCED := 3000.0
const XP_ELITE := 5000.0

## Adaptation levels
enum AdaptationLevel {
	BASIC,      ## 0-1000 XP
	IMPROVED,   ## 1000-3000 XP
	ADVANCED,   ## 3000-5000 XP
	ELITE       ## 5000+ XP
}

## Behavior adaptations per faction and level
const FACTION_ADAPTATIONS := {
	"aether_swarm": {
		AdaptationLevel.BASIC: {
			"attack_coordination": 0.0,
			"swarm_bonus": 0.01,
			"stealth_modifier": 0.0
		},
		AdaptationLevel.IMPROVED: {
			"attack_coordination": 0.1,
			"swarm_bonus": 0.015,
			"stealth_modifier": 0.1
		},
		AdaptationLevel.ADVANCED: {
			"attack_coordination": 0.2,
			"swarm_bonus": 0.02,
			"stealth_modifier": 0.2
		},
		AdaptationLevel.ELITE: {
			"attack_coordination": 0.3,
			"swarm_bonus": 0.025,
			"stealth_modifier": 0.3
		}
	},
	"glacius": {
		AdaptationLevel.BASIC: {
			"armor_stacking": 0.2,
			"aoe_radius": 1.0,
			"siege_damage": 1.0
		},
		AdaptationLevel.IMPROVED: {
			"armor_stacking": 0.25,
			"aoe_radius": 1.15,
			"siege_damage": 1.1
		},
		AdaptationLevel.ADVANCED: {
			"armor_stacking": 0.3,
			"aoe_radius": 1.3,
			"siege_damage": 1.2
		},
		AdaptationLevel.ELITE: {
			"armor_stacking": 0.35,
			"aoe_radius": 1.5,
			"siege_damage": 1.35
		}
	},
	"dynapods": {
		AdaptationLevel.BASIC: {
			"dodge_bonus": 0.02,
			"momentum_mult": 1.0,
			"bounce_targets": 2
		},
		AdaptationLevel.IMPROVED: {
			"dodge_bonus": 0.03,
			"momentum_mult": 1.1,
			"bounce_targets": 3
		},
		AdaptationLevel.ADVANCED: {
			"dodge_bonus": 0.04,
			"momentum_mult": 1.2,
			"bounce_targets": 4
		},
		AdaptationLevel.ELITE: {
			"dodge_bonus": 0.05,
			"momentum_mult": 1.35,
			"bounce_targets": 5
		}
	},
	"logibots": {
		AdaptationLevel.BASIC: {
			"sync_bonus": 0.1,
			"construct_speed": 1.0,
			"cargo_capacity": 1.0
		},
		AdaptationLevel.IMPROVED: {
			"sync_bonus": 0.12,
			"construct_speed": 1.15,
			"cargo_capacity": 1.2
		},
		AdaptationLevel.ADVANCED: {
			"sync_bonus": 0.15,
			"construct_speed": 1.3,
			"cargo_capacity": 1.4
		},
		AdaptationLevel.ELITE: {
			"sync_bonus": 0.18,
			"construct_speed": 1.5,
			"cargo_capacity": 1.6
		}
	},
	"human_remnant": {
		AdaptationLevel.BASIC: {
			"accuracy_bonus": 0.0,
			"ambush_damage": 1.0,
			"suppression": 0.5
		},
		AdaptationLevel.IMPROVED: {
			"accuracy_bonus": 0.1,
			"ambush_damage": 1.15,
			"suppression": 0.6
		},
		AdaptationLevel.ADVANCED: {
			"accuracy_bonus": 0.2,
			"ambush_damage": 1.3,
			"suppression": 0.7
		},
		AdaptationLevel.ELITE: {
			"accuracy_bonus": 0.3,
			"ambush_damage": 1.5,
			"suppression": 0.8
		}
	}
}

## Faction XP cache
var _faction_xp: Dictionary = {}

## Callbacks
var _get_faction_xp: Callable


func _init() -> void:
	pass


## Set callback.
func set_get_faction_xp(callback: Callable) -> void:
	_get_faction_xp = callback


## Update faction XP.
func update_faction_xp(faction_id: String, xp: float) -> void:
	var old_level := get_adaptation_level(faction_id)
	_faction_xp[faction_id] = xp
	var new_level := get_adaptation_level(faction_id)

	if new_level > old_level:
		behavior_unlocked.emit(faction_id, AdaptationLevel.keys()[new_level])


## Get adaptation level for faction.
func get_adaptation_level(faction_id: String) -> int:
	var xp: float = _faction_xp.get(faction_id, 0.0)

	if _get_faction_xp.is_valid():
		xp = _get_faction_xp.call(faction_id)

	if xp >= XP_ELITE:
		return AdaptationLevel.ELITE
	elif xp >= XP_ADVANCED:
		return AdaptationLevel.ADVANCED
	elif xp >= XP_IMPROVED:
		return AdaptationLevel.IMPROVED

	return AdaptationLevel.BASIC


## Get adaptation parameters for faction.
func get_adaptations(faction_id: String) -> Dictionary:
	var level := get_adaptation_level(faction_id)

	if not FACTION_ADAPTATIONS.has(faction_id):
		return {}

	var faction_data: Dictionary = FACTION_ADAPTATIONS[faction_id]
	return faction_data.get(level, {}).duplicate()


## Apply adaptations to action result.
func adapt_action(unit_id: int, faction_id: String, action: Dictionary) -> Dictionary:
	var adaptations := get_adaptations(faction_id)
	if adaptations.is_empty():
		return action

	var adapted := action.duplicate()

	# Apply relevant adaptations based on action type
	match action.get("action", ""):
		"attack", "coordinated_attack":
			if adaptations.has("attack_coordination"):
				var bonus: float = adaptations["attack_coordination"]
				adapted["damage_bonus"] = action.get("damage_bonus", 0.0) + bonus

		"swarm_attack":
			if adaptations.has("swarm_bonus"):
				adapted["swarm_bonus"] = adaptations["swarm_bonus"]

		"aoe_attack":
			if adaptations.has("aoe_radius"):
				var base_radius: float = action.get("radius", 10.0)
				adapted["radius"] = base_radius * adaptations["aoe_radius"]

		"acrobatic_dodge":
			if adaptations.has("dodge_bonus"):
				var base: float = action.get("dodge_bonus", 0.0)
				adapted["dodge_bonus"] = base + adaptations["dodge_bonus"]

	adaptation_applied.emit(unit_id, action.get("action", ""), get_adaptation_level(faction_id))

	return adapted


## Get summary for debugging.
func get_summary() -> Dictionary:
	var levels: Dictionary = {}
	for faction_id in _faction_xp:
		levels[faction_id] = AdaptationLevel.keys()[get_adaptation_level(faction_id)]

	return {
		"tracked_factions": _faction_xp.size(),
		"faction_levels": levels
	}
