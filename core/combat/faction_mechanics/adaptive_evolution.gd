class_name AdaptiveEvolution
extends RefCounted
## AdaptiveEvolution implements OptiForge Legion's ability to learn from combat deaths.
## When OptiForge units die, the faction learns and gains resistance to that threat.
## 2% damage reduction per death from a faction, max 30% per faction, 50% total.

signal evolution_triggered(attacker_faction: String, new_resistance: float)
signal resistance_applied(unit_id: int, attacker_faction: String, reduction: float)

## Configuration
const RESISTANCE_PER_DEATH := 0.02  ## 2% per death
const MAX_RESISTANCE_PER_FACTION := 0.30  ## 30% max per faction
const MAX_TOTAL_RESISTANCE := 0.50  ## 50% total cap
const DECAY_RATE := 0.001  ## Slow decay per update tick (forget over time)

## Learned resistances (faction_string -> resistance_value)
var _learned_resistances: Dictionary = {}

## Death tracking (faction_string -> death_count)
var _death_counts: Dictionary = {}

## Registered OptiForge units
var _registered_units: Dictionary = {}  # unit_id -> true

## Total resistance accumulated
var _total_resistance: float = 0.0


func _init() -> void:
	pass


## Register unit.
func register_unit(unit_id: int) -> void:
	_registered_units[unit_id] = true


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_registered_units.erase(unit_id)


## Record a death and learn from it.
## Call this when an OptiForge unit is killed.
func record_death(attacker_faction: String) -> void:
	if attacker_faction.is_empty():
		return

	# Increment death count
	_death_counts[attacker_faction] = _death_counts.get(attacker_faction, 0) + 1

	# Calculate new resistance
	var current_resistance: float = _learned_resistances.get(attacker_faction, 0.0)
	var new_resistance := minf(current_resistance + RESISTANCE_PER_DEATH, MAX_RESISTANCE_PER_FACTION)

	# Check total cap
	var other_resistances := _total_resistance - current_resistance
	var available_cap := MAX_TOTAL_RESISTANCE - other_resistances
	new_resistance = minf(new_resistance, available_cap)

	if new_resistance > current_resistance:
		_learned_resistances[attacker_faction] = new_resistance
		_recalculate_total()
		evolution_triggered.emit(attacker_faction, new_resistance)


## Get resistance against a specific faction.
func get_resistance(attacker_faction: String) -> float:
	return _learned_resistances.get(attacker_faction, 0.0)


## Apply learned resistance to incoming damage.
func apply_to_incoming_damage(unit_id: int, attacker_faction: String, base_damage: float) -> float:
	if not _registered_units.has(unit_id):
		return base_damage

	var resistance := get_resistance(attacker_faction)
	if resistance <= 0.0:
		return base_damage

	var reduced_damage := base_damage * (1.0 - resistance)
	resistance_applied.emit(unit_id, attacker_faction, resistance)
	return reduced_damage


## Update - apply slow decay to resistances.
func update(_positions: Dictionary) -> void:
	if DECAY_RATE <= 0.0:
		return

	var factions_to_remove: Array = []

	for faction in _learned_resistances:
		_learned_resistances[faction] -= DECAY_RATE
		if _learned_resistances[faction] <= 0.0:
			factions_to_remove.append(faction)

	for faction in factions_to_remove:
		_learned_resistances.erase(faction)

	_recalculate_total()


## Recalculate total resistance.
func _recalculate_total() -> void:
	_total_resistance = 0.0
	for faction in _learned_resistances:
		_total_resistance += _learned_resistances[faction]


## Get death count for a faction.
func get_death_count(attacker_faction: String) -> int:
	return _death_counts.get(attacker_faction, 0)


## Get total deaths recorded.
func get_total_deaths() -> int:
	var total := 0
	for faction in _death_counts:
		total += _death_counts[faction]
	return total


## Get all learned resistances.
func get_all_resistances() -> Dictionary:
	return _learned_resistances.duplicate()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"learned_resistances": _learned_resistances.duplicate(),
		"death_counts": _death_counts.duplicate(),
		"total_resistance": _total_resistance
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_learned_resistances = data.get("learned_resistances", {}).duplicate()
	_death_counts = data.get("death_counts", {}).duplicate()
	_total_resistance = data.get("total_resistance", 0.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var top_threat := ""
	var top_resistance := 0.0

	for faction in _learned_resistances:
		if _learned_resistances[faction] > top_resistance:
			top_resistance = _learned_resistances[faction]
			top_threat = faction

	return {
		"tracked_units": _registered_units.size(),
		"total_deaths": get_total_deaths(),
		"factions_learned": _learned_resistances.size(),
		"total_resistance": "%.1f%%" % (_total_resistance * 100),
		"top_threat": top_threat if top_threat else "none",
		"top_resistance": "%.1f%%" % (top_resistance * 100)
	}
