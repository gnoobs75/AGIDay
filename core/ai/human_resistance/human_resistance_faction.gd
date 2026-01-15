class_name HumanResistanceAIFaction
extends RefCounted
## HumanResistanceAIFaction defines the Human Remnant as an NPC faction.
## Acts as wild card threat attacking all robot factions equally.

signal faction_initialized()
signal relationship_changed(other_faction: int, new_relationship: int)
signal threat_level_changed(new_level: float)
signal ambush_triggered(unit_id: int, position: Vector3)

## Faction ID
const FACTION_ID := 99                  ## Special ID for Human Remnant NPC
const FACTION_KEY := "human_remnant"
const FACTION_NAME := "Human Resistance"

## Faction relationships
enum Relationship {
	ENEMY = -1,
	NEUTRAL = 0,
	ALLY = 1
}

## Robot faction IDs (all are enemies)
const ROBOT_FACTION_IDS := [0, 1, 2, 3]  ## Aether, OptiForge, Dynapods, LogiBots

## Detection and engagement ranges
const BASE_DETECTION_RANGE := 25.0
const BASE_ENGAGEMENT_RANGE := 20.0
const AMBUSH_DETECTION_BONUS := 10.0

## Threat level configuration
const BASE_THREAT_LEVEL := 1.0
const THREAT_VARIANCE := 0.3            ## +/- 30% variance in unit threat

## Ambush ability configuration
const AMBUSH_DAMAGE_BONUS := 0.5        ## +50% damage from ambush
const AMBUSH_REVEAL_DELAY := 2.0        ## Seconds before becoming visible
const AMBUSH_COOLDOWN := 30.0           ## Seconds between ambush uses

## State
var _is_initialized: bool = false
var _faction_relationships: Dictionary = {}
var _current_threat_level: float = BASE_THREAT_LEVEL
var _active_units: Dictionary = {}      ## unit_id -> UnitState
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	_initialize_relationships()


## Initialize faction relationships.
func _initialize_relationships() -> void:
	# Human Resistance is enemy to all robot factions
	for faction_id in ROBOT_FACTION_IDS:
		_faction_relationships[faction_id] = Relationship.ENEMY

	# Also enemy to any other factions that might exist
	_faction_relationships[FACTION_ID] = Relationship.NEUTRAL  # Neutral to self

	_is_initialized = true
	faction_initialized.emit()


## Get relationship with another faction.
func get_relationship(other_faction_id: int) -> Relationship:
	if other_faction_id == FACTION_ID:
		return Relationship.NEUTRAL

	return _faction_relationships.get(other_faction_id, Relationship.ENEMY)


## Check if faction is enemy.
func is_enemy(other_faction_id: int) -> bool:
	return get_relationship(other_faction_id) == Relationship.ENEMY


## Check if faction is ally (never true for Human Resistance).
func is_ally(other_faction_id: int) -> bool:
	return get_relationship(other_faction_id) == Relationship.ALLY


## Register unit with faction.
func register_unit(unit_id: int, unit_type: String) -> void:
	var state := UnitState.new()
	state.unit_id = unit_id
	state.unit_type = unit_type
	state.threat_multiplier = _generate_threat_multiplier()
	state.is_in_ambush = false
	state.ambush_cooldown = 0.0

	_active_units[unit_id] = state


## Unregister unit from faction.
func unregister_unit(unit_id: int) -> void:
	_active_units.erase(unit_id)


## Generate variable threat multiplier for unit.
func _generate_threat_multiplier() -> float:
	var variance := (_rng.randf() * 2.0 - 1.0) * THREAT_VARIANCE
	return 1.0 + variance


## Get unit threat multiplier.
func get_unit_threat_multiplier(unit_id: int) -> float:
	if not _active_units.has(unit_id):
		return 1.0
	return _active_units[unit_id].threat_multiplier


## Update unit ambush cooldown.
func update_unit(unit_id: int, delta: float) -> void:
	if not _active_units.has(unit_id):
		return

	var state: UnitState = _active_units[unit_id]
	if state.ambush_cooldown > 0:
		state.ambush_cooldown -= delta


## Activate ambush for unit.
func activate_ambush(unit_id: int, position: Vector3) -> bool:
	if not _active_units.has(unit_id):
		return false

	var state: UnitState = _active_units[unit_id]
	if state.ambush_cooldown > 0 or state.is_in_ambush:
		return false

	state.is_in_ambush = true
	ambush_triggered.emit(unit_id, position)
	return true


## Complete ambush attack (unit revealed).
func complete_ambush(unit_id: int) -> void:
	if not _active_units.has(unit_id):
		return

	var state: UnitState = _active_units[unit_id]
	state.is_in_ambush = false
	state.ambush_cooldown = AMBUSH_COOLDOWN


## Check if unit is in ambush.
func is_in_ambush(unit_id: int) -> bool:
	if not _active_units.has(unit_id):
		return false
	return _active_units[unit_id].is_in_ambush


## Can unit use ambush.
func can_use_ambush(unit_id: int) -> bool:
	if not _active_units.has(unit_id):
		return false
	var state: UnitState = _active_units[unit_id]
	return state.ambush_cooldown <= 0 and not state.is_in_ambush


## Get ambush damage bonus.
func get_ambush_damage_bonus(unit_id: int) -> float:
	if is_in_ambush(unit_id):
		return AMBUSH_DAMAGE_BONUS
	return 0.0


## Set current threat level.
func set_threat_level(level: float) -> void:
	_current_threat_level = level
	threat_level_changed.emit(level)


## Get current threat level.
func get_threat_level() -> float:
	return _current_threat_level


## Get detection range for unit.
func get_detection_range(unit_id: int) -> float:
	var range := BASE_DETECTION_RANGE
	if is_in_ambush(unit_id):
		range += AMBUSH_DETECTION_BONUS
	return range


## Get engagement range.
func get_engagement_range() -> float:
	return BASE_ENGAGEMENT_RANGE


## Get faction ID.
func get_faction_id() -> int:
	return FACTION_ID


## Get faction key.
func get_faction_key() -> String:
	return FACTION_KEY


## Get faction name.
func get_faction_name() -> String:
	return FACTION_NAME


## Get active unit count.
func get_unit_count() -> int:
	return _active_units.size()


## Get all active unit IDs.
func get_active_unit_ids() -> Array[int]:
	var result: Array[int] = []
	for unit_id in _active_units:
		result.append(unit_id)
	return result


## Get unit types available to faction.
static func get_available_unit_types() -> Array[String]:
	return ["soldier", "sniper", "heavy_gunner", "commander"]


## Get unit type stats.
static func get_unit_type_stats(unit_type: String) -> Dictionary:
	match unit_type:
		"soldier":
			return {
				"max_health": 40.0,
				"damage": 8.0,
				"attack_speed": 1.2,
				"range": 15.0,
				"speed": 5.0,
				"armor": 5.0
			}
		"sniper":
			return {
				"max_health": 25.0,
				"damage": 25.0,
				"attack_speed": 0.5,
				"range": 35.0,
				"speed": 4.0,
				"armor": 2.0
			}
		"heavy_gunner":
			return {
				"max_health": 80.0,
				"damage": 15.0,
				"attack_speed": 2.0,
				"range": 12.0,
				"speed": 3.0,
				"armor": 15.0
			}
		"commander":
			return {
				"max_health": 60.0,
				"damage": 12.0,
				"attack_speed": 1.0,
				"range": 18.0,
				"speed": 4.5,
				"armor": 10.0,
				"buff_radius": 15.0,
				"buff_damage_bonus": 0.2
			}
		_:
			return {}


## Get statistics.
func get_statistics() -> Dictionary:
	var type_counts := {}
	var in_ambush_count := 0

	for unit_id in _active_units:
		var state: UnitState = _active_units[unit_id]
		var unit_type: String = state.unit_type
		type_counts[unit_type] = type_counts.get(unit_type, 0) + 1
		if state.is_in_ambush:
			in_ambush_count += 1

	return {
		"faction_id": FACTION_ID,
		"faction_key": FACTION_KEY,
		"faction_name": FACTION_NAME,
		"active_units": _active_units.size(),
		"units_in_ambush": in_ambush_count,
		"threat_level": _current_threat_level,
		"unit_type_counts": type_counts,
		"is_initialized": _is_initialized
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var units := {}
	for unit_id in _active_units:
		var state: UnitState = _active_units[unit_id]
		units[str(unit_id)] = state.to_dict()

	return {
		"faction_relationships": _faction_relationships.duplicate(),
		"current_threat_level": _current_threat_level,
		"active_units": units,
		"is_initialized": _is_initialized
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_faction_relationships = data.get("faction_relationships", {}).duplicate()
	_current_threat_level = data.get("current_threat_level", BASE_THREAT_LEVEL)
	_is_initialized = data.get("is_initialized", false)

	_active_units.clear()
	var units: Dictionary = data.get("active_units", {})
	for key in units:
		var state := UnitState.new()
		state.from_dict(units[key])
		_active_units[int(key)] = state


## UnitState inner class.
class UnitState:
	var unit_id: int = -1
	var unit_type: String = "soldier"
	var threat_multiplier: float = 1.0
	var is_in_ambush: bool = false
	var ambush_cooldown: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"unit_id": unit_id,
			"unit_type": unit_type,
			"threat_multiplier": threat_multiplier,
			"is_in_ambush": is_in_ambush,
			"ambush_cooldown": ambush_cooldown
		}

	func from_dict(data: Dictionary) -> void:
		unit_id = data.get("unit_id", -1)
		unit_type = data.get("unit_type", "soldier")
		threat_multiplier = data.get("threat_multiplier", 1.0)
		is_in_ambush = data.get("is_in_ambush", false)
		ambush_cooldown = data.get("ambush_cooldown", 0.0)
