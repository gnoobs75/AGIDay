class_name FactionLearningIntegration
extends RefCounted
## FactionLearningIntegration provides integration points for experience events.
## Connects game systems to faction learning for XP gain.

signal xp_awarded(faction_id: String, category: String, amount: float, source: String)

## Experience multipliers for different event types
const XP_MULTIPLIERS := {
	## Combat events
	"unit_killed": 10.0,
	"building_destroyed": 50.0,
	"damage_dealt": 0.1,
	"damage_blocked": 0.05,
	"unit_healed": 0.2,
	"ability_used": 2.0,
	"critical_hit": 5.0,
	"kill_streak": 25.0,

	## Economy events
	"resource_gathered": 0.5,
	"resource_traded": 0.3,
	"building_completed": 20.0,
	"upgrade_completed": 15.0,
	"unit_produced": 5.0,

	## Engineering events
	"structure_built": 25.0,
	"structure_repaired": 0.3,
	"tech_researched": 100.0,
	"siege_deployed": 30.0,
	"hack_completed": 50.0
}

## Reference to faction learning system
var _faction_learning: FactionLearning = null

## XP multiplier per faction (for bonuses)
var _faction_multipliers: Dictionary = {}

## Recent XP gains for rate limiting (faction_id -> {category -> last_time})
var _recent_gains: Dictionary = {}
const XP_COOLDOWN := 0.1  ## Minimum seconds between XP gains per category


func _init() -> void:
	pass


## Set faction learning reference.
func set_faction_learning(learning: FactionLearning) -> void:
	_faction_learning = learning


## Set faction XP multiplier.
func set_faction_multiplier(faction_id: String, multiplier: float) -> void:
	_faction_multipliers[faction_id] = multiplier


## Get effective multiplier for faction.
func _get_multiplier(faction_id: String) -> float:
	return _faction_multipliers.get(faction_id, 1.0)


## Award combat XP for event.
func award_combat_xp(faction_id: String, event_type: String, count: int = 1) -> float:
	return _award_xp(faction_id, FactionLearning.Category.COMBAT, event_type, count)


## Award economy XP for event.
func award_economy_xp(faction_id: String, event_type: String, count: int = 1) -> float:
	return _award_xp(faction_id, FactionLearning.Category.ECONOMY, event_type, count)


## Award engineering XP for event.
func award_engineering_xp(faction_id: String, event_type: String, count: int = 1) -> float:
	return _award_xp(faction_id, FactionLearning.Category.ENGINEERING, event_type, count)


## Internal XP award.
func _award_xp(faction_id: String, category: int, event_type: String, count: int) -> float:
	if _faction_learning == null:
		return 0.0

	if not XP_MULTIPLIERS.has(event_type):
		return 0.0

	# Rate limiting check
	if not _check_cooldown(faction_id, category):
		return 0.0

	var base_xp: float = XP_MULTIPLIERS[event_type] * float(count)
	var multiplier := _get_multiplier(faction_id)
	var final_xp := base_xp * multiplier

	match category:
		FactionLearning.Category.COMBAT:
			_faction_learning.add_combat_xp(faction_id, final_xp)
		FactionLearning.Category.ECONOMY:
			_faction_learning.add_economy_xp(faction_id, final_xp)
		FactionLearning.Category.ENGINEERING:
			_faction_learning.add_engineering_xp(faction_id, final_xp)

	var category_name: String = FactionLearning.CATEGORY_NAMES[category]
	xp_awarded.emit(faction_id, category_name, final_xp, event_type)

	return final_xp


## Check if XP can be awarded (rate limiting).
func _check_cooldown(faction_id: String, category: int) -> bool:
	var current_time := Time.get_ticks_msec() / 1000.0

	if not _recent_gains.has(faction_id):
		_recent_gains[faction_id] = {}

	var faction_gains: Dictionary = _recent_gains[faction_id]
	var last_time: float = faction_gains.get(category, 0.0)

	if current_time - last_time < XP_COOLDOWN:
		return false

	faction_gains[category] = current_time
	return true


## Combat event handlers.
func on_unit_killed(killer_faction: String) -> void:
	award_combat_xp(killer_faction, "unit_killed")


func on_building_destroyed(destroyer_faction: String) -> void:
	award_combat_xp(destroyer_faction, "building_destroyed")


func on_damage_dealt(faction_id: String, amount: float) -> void:
	if amount > 0:
		award_combat_xp(faction_id, "damage_dealt", int(amount))


func on_damage_blocked(faction_id: String, amount: float) -> void:
	if amount > 0:
		award_combat_xp(faction_id, "damage_blocked", int(amount))


func on_unit_healed(faction_id: String, amount: float) -> void:
	if amount > 0:
		award_combat_xp(faction_id, "unit_healed", int(amount))


func on_ability_used(faction_id: String) -> void:
	award_combat_xp(faction_id, "ability_used")


func on_critical_hit(faction_id: String) -> void:
	award_combat_xp(faction_id, "critical_hit")


func on_kill_streak(faction_id: String, streak: int) -> void:
	if streak >= 3:
		award_combat_xp(faction_id, "kill_streak", streak - 2)


## Economy event handlers.
func on_resource_gathered(faction_id: String, amount: float) -> void:
	if amount > 0:
		award_economy_xp(faction_id, "resource_gathered", int(amount))


func on_resource_traded(faction_id: String, amount: float) -> void:
	if amount > 0:
		award_economy_xp(faction_id, "resource_traded", int(amount))


func on_building_completed(faction_id: String) -> void:
	award_economy_xp(faction_id, "building_completed")


func on_upgrade_completed(faction_id: String) -> void:
	award_economy_xp(faction_id, "upgrade_completed")


func on_unit_produced(faction_id: String) -> void:
	award_economy_xp(faction_id, "unit_produced")


## Engineering event handlers.
func on_structure_built(faction_id: String) -> void:
	award_engineering_xp(faction_id, "structure_built")


func on_structure_repaired(faction_id: String, amount: float) -> void:
	if amount > 0:
		award_engineering_xp(faction_id, "structure_repaired", int(amount))


func on_tech_researched(faction_id: String) -> void:
	award_engineering_xp(faction_id, "tech_researched")


func on_siege_deployed(faction_id: String) -> void:
	award_engineering_xp(faction_id, "siege_deployed")


func on_hack_completed(faction_id: String) -> void:
	award_engineering_xp(faction_id, "hack_completed")


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"event_types": XP_MULTIPLIERS.size(),
		"faction_multipliers": _faction_multipliers.duplicate(),
		"cooldown_seconds": XP_COOLDOWN
	}
