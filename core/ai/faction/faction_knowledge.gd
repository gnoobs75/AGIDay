class_name FactionKnowledge
extends RefCounted
## FactionKnowledge tracks shared faction-level experience and unlocks.
## Supports Combat, Economy, and Engineering experience categories.

signal xp_gained(faction_id: String, category: String, amount: float)
signal level_up(faction_id: String, category: String, new_level: int)
signal knowledge_shared(from_faction: String, to_faction: String, knowledge_type: String)

## XP Categories
enum Category {
	COMBAT,
	ECONOMY,
	ENGINEERING
}

## Category names
const CATEGORY_NAMES := {
	Category.COMBAT: "combat",
	Category.ECONOMY: "economy",
	Category.ENGINEERING: "engineering"
}

## XP thresholds per level (cumulative)
const LEVEL_THRESHOLDS := [0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5200, 6500]

## Faction identifiers
const FACTION_AETHER_SWARM := "AETHER_SWARM"
const FACTION_OPTIFORGE_LEGION := "OPTIFORGE_LEGION"
const FACTION_GLACIUS := "GLACIUS"
const FACTION_DYNAPODS := "DYNAPODS"
const FACTION_LOGIBOTS := "LOGIBOTS"
const FACTION_HUMAN_REMNANT := "HUMAN_REMNANT"

## All factions
const ALL_FACTIONS := [
	FACTION_AETHER_SWARM,
	FACTION_OPTIFORGE_LEGION,
	FACTION_GLACIUS,
	FACTION_DYNAPODS,
	FACTION_LOGIBOTS,
	FACTION_HUMAN_REMNANT
]

## Faction knowledge storage (faction_id -> category -> xp)
var _faction_xp: Dictionary = {}

## Cached levels (faction_id -> category -> level)
var _faction_levels: Dictionary = {}

## Knowledge multipliers per faction (faction specialties)
var _faction_multipliers: Dictionary = {
	FACTION_AETHER_SWARM: {Category.COMBAT: 1.2, Category.ECONOMY: 0.8, Category.ENGINEERING: 1.0},
	FACTION_OPTIFORGE_LEGION: {Category.COMBAT: 1.0, Category.ECONOMY: 1.0, Category.ENGINEERING: 1.3},
	FACTION_GLACIUS: {Category.COMBAT: 1.3, Category.ECONOMY: 0.9, Category.ENGINEERING: 0.9},
	FACTION_DYNAPODS: {Category.COMBAT: 1.1, Category.ECONOMY: 1.1, Category.ENGINEERING: 0.9},
	FACTION_LOGIBOTS: {Category.COMBAT: 0.8, Category.ECONOMY: 1.3, Category.ENGINEERING: 1.1},
	FACTION_HUMAN_REMNANT: {Category.COMBAT: 1.0, Category.ECONOMY: 1.0, Category.ENGINEERING: 1.0}
}


func _init() -> void:
	_initialize_factions()


func _initialize_factions() -> void:
	for faction_id in ALL_FACTIONS:
		_faction_xp[faction_id] = {
			Category.COMBAT: 0.0,
			Category.ECONOMY: 0.0,
			Category.ENGINEERING: 0.0
		}
		_faction_levels[faction_id] = {
			Category.COMBAT: 0,
			Category.ECONOMY: 0,
			Category.ENGINEERING: 0
		}


## Add XP to faction category.
func add_xp(faction_id: String, category: int, base_amount: float) -> void:
	if not _faction_xp.has(faction_id):
		return

	var multiplier := 1.0
	if _faction_multipliers.has(faction_id):
		multiplier = _faction_multipliers[faction_id].get(category, 1.0)

	var amount := base_amount * multiplier
	var old_xp: float = _faction_xp[faction_id][category]
	var new_xp := old_xp + amount
	_faction_xp[faction_id][category] = new_xp

	xp_gained.emit(faction_id, CATEGORY_NAMES[category], amount)

	# Check for level up
	var old_level := _get_level_for_xp(old_xp)
	var new_level := _get_level_for_xp(new_xp)

	if new_level > old_level:
		_faction_levels[faction_id][category] = new_level
		level_up.emit(faction_id, CATEGORY_NAMES[category], new_level)


## Get XP for faction category.
func get_xp(faction_id: String, category: int) -> float:
	if not _faction_xp.has(faction_id):
		return 0.0
	return _faction_xp[faction_id].get(category, 0.0)


## Get level for faction category.
func get_level(faction_id: String, category: int) -> int:
	if not _faction_levels.has(faction_id):
		return 0
	return _faction_levels[faction_id].get(category, 0)


## Get total faction XP across all categories.
func get_total_xp(faction_id: String) -> float:
	if not _faction_xp.has(faction_id):
		return 0.0

	var total := 0.0
	for category in Category.values():
		total += _faction_xp[faction_id].get(category, 0.0)
	return total


## Get average faction level.
func get_average_level(faction_id: String) -> float:
	if not _faction_levels.has(faction_id):
		return 0.0

	var total := 0.0
	for category in Category.values():
		total += float(_faction_levels[faction_id].get(category, 0))
	return total / float(Category.size())


## Calculate level from XP.
func _get_level_for_xp(xp: float) -> int:
	for i in range(LEVEL_THRESHOLDS.size() - 1, -1, -1):
		if xp >= LEVEL_THRESHOLDS[i]:
			return i
	return 0


## Get XP needed for next level.
func get_xp_to_next_level(faction_id: String, category: int) -> float:
	var current_xp := get_xp(faction_id, category)
	var current_level := get_level(faction_id, category)

	if current_level >= LEVEL_THRESHOLDS.size() - 1:
		return 0.0  ## Max level

	return LEVEL_THRESHOLDS[current_level + 1] - current_xp


## Get progress to next level (0.0 - 1.0).
func get_level_progress(faction_id: String, category: int) -> float:
	var current_xp := get_xp(faction_id, category)
	var current_level := get_level(faction_id, category)

	if current_level >= LEVEL_THRESHOLDS.size() - 1:
		return 1.0

	var level_start := float(LEVEL_THRESHOLDS[current_level])
	var level_end := float(LEVEL_THRESHOLDS[current_level + 1])

	return (current_xp - level_start) / (level_end - level_start)


## Get faction combat XP (convenience method).
func get_combat_xp(faction_id: String) -> float:
	return get_xp(faction_id, Category.COMBAT)


## Get faction economy XP (convenience method).
func get_economy_xp(faction_id: String) -> float:
	return get_xp(faction_id, Category.ECONOMY)


## Get faction engineering XP (convenience method).
func get_engineering_xp(faction_id: String) -> float:
	return get_xp(faction_id, Category.ENGINEERING)


## Serialization.
func to_dict() -> Dictionary:
	var xp_data: Dictionary = {}
	var level_data: Dictionary = {}

	for faction_id in _faction_xp:
		xp_data[faction_id] = {}
		for category in Category.values():
			xp_data[faction_id][str(category)] = _faction_xp[faction_id].get(category, 0.0)

	for faction_id in _faction_levels:
		level_data[faction_id] = {}
		for category in Category.values():
			level_data[faction_id][str(category)] = _faction_levels[faction_id].get(category, 0)

	return {
		"faction_xp": xp_data,
		"faction_levels": level_data
	}


func from_dict(data: Dictionary) -> void:
	_initialize_factions()

	var xp_data: Dictionary = data.get("faction_xp", {})
	for faction_id in xp_data:
		if _faction_xp.has(faction_id):
			for category_str in xp_data[faction_id]:
				var category := int(category_str)
				_faction_xp[faction_id][category] = xp_data[faction_id][category_str]

	var level_data: Dictionary = data.get("faction_levels", {})
	for faction_id in level_data:
		if _faction_levels.has(faction_id):
			for category_str in level_data[faction_id]:
				var category := int(category_str)
				_faction_levels[faction_id][category] = level_data[faction_id][category_str]


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_summaries: Dictionary = {}

	for faction_id in ALL_FACTIONS:
		faction_summaries[faction_id] = {
			"combat": {"xp": get_combat_xp(faction_id), "level": get_level(faction_id, Category.COMBAT)},
			"economy": {"xp": get_economy_xp(faction_id), "level": get_level(faction_id, Category.ECONOMY)},
			"engineering": {"xp": get_engineering_xp(faction_id), "level": get_level(faction_id, Category.ENGINEERING)},
			"total_xp": get_total_xp(faction_id),
			"avg_level": get_average_level(faction_id)
		}

	return {
		"factions": faction_summaries,
		"max_level": LEVEL_THRESHOLDS.size() - 1
	}
