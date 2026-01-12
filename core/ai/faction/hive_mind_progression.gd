class_name HiveMindProgression
extends RefCounted
## HiveMindProgression manages faction-wide buff unlocks and applies them to units.
## Part of the Hive Mind Progression System for emergent swarm intelligence.

signal buff_unlocked(faction_id: String, buff_id: String)
signal behavior_unlocked(faction_id: String, behavior_id: String)
signal progression_applied(faction_id: String, unit_id: int, buffs: Array)

## Buff types
enum BuffType {
	DAMAGE,
	ARMOR,
	SPEED,
	ATTACK_SPEED,
	RANGE,
	HEALTH,
	REGENERATION,
	COORDINATION
}

## Progression unlocks by faction and level
const PROGRESSION_UNLOCKS := {
	"AETHER_SWARM": {
		## Combat unlocks
		"combat_1": {"type": "buff", "buff": BuffType.COORDINATION, "value": 0.05},
		"combat_2": {"type": "behavior", "behavior": "swarm_flank"},
		"combat_3": {"type": "buff", "buff": BuffType.DAMAGE, "value": 0.10},
		"combat_5": {"type": "behavior", "behavior": "stealth_ambush"},
		"combat_7": {"type": "buff", "buff": BuffType.ATTACK_SPEED, "value": 0.15},
		## Economy unlocks
		"economy_2": {"type": "buff", "buff": BuffType.SPEED, "value": 0.05},
		"economy_4": {"type": "behavior", "behavior": "resource_scent"},
		## Engineering unlocks
		"engineering_3": {"type": "buff", "buff": BuffType.REGENERATION, "value": 0.02}
	},
	"GLACIUS": {
		"combat_1": {"type": "buff", "buff": BuffType.ARMOR, "value": 0.10},
		"combat_2": {"type": "behavior", "behavior": "defensive_formation"},
		"combat_3": {"type": "buff", "buff": BuffType.HEALTH, "value": 0.15},
		"combat_5": {"type": "behavior", "behavior": "siege_mode"},
		"combat_7": {"type": "buff", "buff": BuffType.DAMAGE, "value": 0.20},
		"economy_2": {"type": "buff", "buff": BuffType.REGENERATION, "value": 0.01},
		"engineering_3": {"type": "behavior", "behavior": "construct_barrier"}
	},
	"DYNAPODS": {
		"combat_1": {"type": "buff", "buff": BuffType.SPEED, "value": 0.10},
		"combat_2": {"type": "behavior", "behavior": "acrobatic_dodge"},
		"combat_3": {"type": "buff", "buff": BuffType.ATTACK_SPEED, "value": 0.10},
		"combat_5": {"type": "behavior", "behavior": "momentum_chain"},
		"combat_7": {"type": "buff", "buff": BuffType.DAMAGE, "value": 0.15},
		"economy_2": {"type": "buff", "buff": BuffType.SPEED, "value": 0.05},
		"engineering_3": {"type": "behavior", "behavior": "terrain_leap"}
	},
	"LOGIBOTS": {
		"combat_1": {"type": "buff", "buff": BuffType.COORDINATION, "value": 0.10},
		"combat_2": {"type": "behavior", "behavior": "synchronized_strike"},
		"combat_3": {"type": "buff", "buff": BuffType.RANGE, "value": 0.10},
		"economy_2": {"type": "buff", "buff": BuffType.SPEED, "value": 0.10},
		"economy_4": {"type": "behavior", "behavior": "cargo_priority"},
		"engineering_3": {"type": "behavior", "behavior": "rapid_construct"},
		"engineering_5": {"type": "buff", "buff": BuffType.HEALTH, "value": 0.10}
	},
	"HUMAN_REMNANT": {
		"combat_1": {"type": "buff", "buff": BuffType.RANGE, "value": 0.05},
		"combat_2": {"type": "behavior", "behavior": "tactical_cover"},
		"combat_3": {"type": "buff", "buff": BuffType.DAMAGE, "value": 0.10},
		"combat_5": {"type": "behavior", "behavior": "coordinated_fire"},
		"combat_7": {"type": "buff", "buff": BuffType.ARMOR, "value": 0.15},
		"economy_2": {"type": "behavior", "behavior": "scavenge_priority"},
		"engineering_3": {"type": "behavior", "behavior": "fortify_position"}
	},
	"OPTIFORGE_LEGION": {
		"combat_1": {"type": "buff", "buff": BuffType.ARMOR, "value": 0.05},
		"combat_2": {"type": "behavior", "behavior": "adaptive_targeting"},
		"combat_3": {"type": "buff", "buff": BuffType.DAMAGE, "value": 0.08},
		"engineering_2": {"type": "buff", "buff": BuffType.HEALTH, "value": 0.10},
		"engineering_4": {"type": "behavior", "behavior": "self_repair"},
		"engineering_6": {"type": "buff", "buff": BuffType.REGENERATION, "value": 0.03}
	}
}

## Reference to faction knowledge
var _faction_knowledge: FactionKnowledge = null

## Unlocked items per faction (faction_id -> Array of unlock_ids)
var _unlocked: Dictionary = {}

## Applied buffs per unit (unit_id -> Array of buff data)
var _unit_buffs: Dictionary = {}


func _init() -> void:
	pass


## Set faction knowledge reference.
func set_faction_knowledge(knowledge: FactionKnowledge) -> void:
	_faction_knowledge = knowledge

	if _faction_knowledge != null:
		_faction_knowledge.level_up.connect(_on_faction_level_up)


## Check and apply unlocks for faction level.
func _on_faction_level_up(faction_id: String, category: String, new_level: int) -> void:
	_check_unlocks(faction_id, category, new_level)


## Check for new unlocks.
func _check_unlocks(faction_id: String, category: String, level: int) -> void:
	if not PROGRESSION_UNLOCKS.has(faction_id):
		return

	var faction_unlocks: Dictionary = PROGRESSION_UNLOCKS[faction_id]
	var unlock_key := category + "_" + str(level)

	if not faction_unlocks.has(unlock_key):
		return

	if not _unlocked.has(faction_id):
		_unlocked[faction_id] = []

	if unlock_key in _unlocked[faction_id]:
		return  ## Already unlocked

	_unlocked[faction_id].append(unlock_key)

	var unlock_data: Dictionary = faction_unlocks[unlock_key]

	if unlock_data["type"] == "buff":
		buff_unlocked.emit(faction_id, unlock_key)
	else:
		behavior_unlocked.emit(faction_id, unlock_data["behavior"])


## Get all active buffs for faction.
func get_faction_buffs(faction_id: String) -> Array[Dictionary]:
	var buffs: Array[Dictionary] = []

	if not PROGRESSION_UNLOCKS.has(faction_id):
		return buffs

	if not _unlocked.has(faction_id):
		return buffs

	var faction_unlocks: Dictionary = PROGRESSION_UNLOCKS[faction_id]

	for unlock_key in _unlocked[faction_id]:
		if faction_unlocks.has(unlock_key):
			var data: Dictionary = faction_unlocks[unlock_key]
			if data["type"] == "buff":
				buffs.append({
					"buff_type": data["buff"],
					"value": data["value"],
					"source": unlock_key
				})

	return buffs


## Get all unlocked behaviors for faction.
func get_faction_behaviors(faction_id: String) -> Array[String]:
	var behaviors: Array[String] = []

	if not PROGRESSION_UNLOCKS.has(faction_id):
		return behaviors

	if not _unlocked.has(faction_id):
		return behaviors

	var faction_unlocks: Dictionary = PROGRESSION_UNLOCKS[faction_id]

	for unlock_key in _unlocked[faction_id]:
		if faction_unlocks.has(unlock_key):
			var data: Dictionary = faction_unlocks[unlock_key]
			if data["type"] == "behavior":
				behaviors.append(data["behavior"])

	return behaviors


## Apply faction buffs to unit.
func apply_to_unit(unit_id: int, faction_id: String) -> Dictionary:
	var buffs := get_faction_buffs(faction_id)
	var behaviors := get_faction_behaviors(faction_id)

	# Aggregate buffs by type
	var aggregated: Dictionary = {}
	for buff in buffs:
		var buff_type: int = buff["buff_type"]
		if not aggregated.has(buff_type):
			aggregated[buff_type] = 0.0
		aggregated[buff_type] += buff["value"]

	_unit_buffs[unit_id] = {
		"faction_id": faction_id,
		"buffs": aggregated,
		"behaviors": behaviors
	}

	var buff_names: Array = []
	for buff in buffs:
		buff_names.append(buff["source"])

	progression_applied.emit(faction_id, unit_id, buff_names)

	return _unit_buffs[unit_id]


## Get unit buff value.
func get_unit_buff(unit_id: int, buff_type: int) -> float:
	if not _unit_buffs.has(unit_id):
		return 0.0

	return _unit_buffs[unit_id]["buffs"].get(buff_type, 0.0)


## Check if unit has unlocked behavior.
func unit_has_behavior(unit_id: int, behavior: String) -> bool:
	if not _unit_buffs.has(unit_id):
		return false

	return behavior in _unit_buffs[unit_id]["behaviors"]


## Remove unit.
func remove_unit(unit_id: int) -> void:
	_unit_buffs.erase(unit_id)


## Refresh all units for faction (call after new unlocks).
func refresh_faction_units(faction_id: String, unit_ids: Array) -> void:
	for unit_id in unit_ids:
		apply_to_unit(unit_id, faction_id)


## Serialization.
func to_dict() -> Dictionary:
	var buffs_data: Dictionary = {}
	for unit_id in _unit_buffs:
		buffs_data[str(unit_id)] = _unit_buffs[unit_id].duplicate(true)

	return {
		"unlocked": _unlocked.duplicate(true),
		"unit_buffs": buffs_data
	}


func from_dict(data: Dictionary) -> void:
	_unlocked = data.get("unlocked", {}).duplicate(true)

	_unit_buffs.clear()
	var buffs_data: Dictionary = data.get("unit_buffs", {})
	for unit_id_str in buffs_data:
		_unit_buffs[int(unit_id_str)] = buffs_data[unit_id_str].duplicate(true)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_unlocks: Dictionary = {}

	for faction_id in _unlocked:
		faction_unlocks[faction_id] = {
			"unlock_count": _unlocked[faction_id].size(),
			"buffs": get_faction_buffs(faction_id).size(),
			"behaviors": get_faction_behaviors(faction_id)
		}

	return {
		"factions_with_unlocks": _unlocked.size(),
		"units_with_buffs": _unit_buffs.size(),
		"faction_details": faction_unlocks
	}
