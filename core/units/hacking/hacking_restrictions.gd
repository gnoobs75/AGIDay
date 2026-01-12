class_name HackingRestrictions
extends RefCounted
## HackingRestrictions defines which units and factions can be hacked.

## Factions allowed to perform hacking
var _hacker_factions: Array[String] = ["aether_swarm"]

## Factions immune to hacking
var _immune_factions: Array[String] = ["human_remnant"]

## Unit types immune to hacking
var _immune_unit_types: Array[String] = ["human_soldier", "boss_unit", "structure"]

## Minimum unit level to hack (0 = all levels)
var min_hackable_level: int = 0

## Maximum unit level to hack (-1 = no limit)
var max_hackable_level: int = -1


func _init() -> void:
	pass


## Check if faction can perform hacking.
func can_faction_hack(faction_id: String) -> bool:
	return faction_id in _hacker_factions


## Check if faction is immune to hacking.
func is_faction_immune(faction_id: String) -> bool:
	return faction_id in _immune_factions


## Check if unit type is immune to hacking.
func is_unit_type_immune(unit_type: String) -> bool:
	return unit_type in _immune_unit_types


## Check if unit level is hackable.
func is_level_hackable(level: int) -> bool:
	if min_hackable_level > 0 and level < min_hackable_level:
		return false
	if max_hackable_level >= 0 and level > max_hackable_level:
		return false
	return true


## Validate if unit can be hacked.
func can_hack_unit(
	hacker_faction: String,
	target_faction: String,
	target_unit_type: String,
	target_level: int = 1,
	target_already_controlled: bool = false
) -> Dictionary:
	var result := {
		"allowed": true,
		"reason": ""
	}

	# Check if hacker faction can hack
	if not can_faction_hack(hacker_faction):
		result["allowed"] = false
		result["reason"] = "Faction cannot perform hacking"
		return result

	# Cannot hack same faction
	if hacker_faction == target_faction:
		result["allowed"] = false
		result["reason"] = "Cannot hack own faction"
		return result

	# Check if target faction is immune
	if is_faction_immune(target_faction):
		result["allowed"] = false
		result["reason"] = "Target faction is immune to hacking"
		return result

	# Check if unit type is immune
	if is_unit_type_immune(target_unit_type):
		result["allowed"] = false
		result["reason"] = "Unit type is immune to hacking"
		return result

	# Check level restrictions
	if not is_level_hackable(target_level):
		result["allowed"] = false
		result["reason"] = "Unit level outside hackable range"
		return result

	# Check if already controlled
	if target_already_controlled:
		result["allowed"] = false
		result["reason"] = "Unit already hacked or mind controlled"
		return result

	return result


## Add hacker faction.
func add_hacker_faction(faction_id: String) -> void:
	if faction_id not in _hacker_factions:
		_hacker_factions.append(faction_id)


## Remove hacker faction.
func remove_hacker_faction(faction_id: String) -> void:
	_hacker_factions.erase(faction_id)


## Add immune faction.
func add_immune_faction(faction_id: String) -> void:
	if faction_id not in _immune_factions:
		_immune_factions.append(faction_id)


## Remove immune faction.
func remove_immune_faction(faction_id: String) -> void:
	_immune_factions.erase(faction_id)


## Add immune unit type.
func add_immune_unit_type(unit_type: String) -> void:
	if unit_type not in _immune_unit_types:
		_immune_unit_types.append(unit_type)


## Remove immune unit type.
func remove_immune_unit_type(unit_type: String) -> void:
	_immune_unit_types.erase(unit_type)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"hacker_factions": _hacker_factions.duplicate(),
		"immune_factions": _immune_factions.duplicate(),
		"immune_unit_types": _immune_unit_types.duplicate(),
		"min_hackable_level": min_hackable_level,
		"max_hackable_level": max_hackable_level
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_hacker_factions.clear()
	for faction in data.get("hacker_factions", ["aether_swarm"]):
		_hacker_factions.append(faction)

	_immune_factions.clear()
	for faction in data.get("immune_factions", ["human_remnant"]):
		_immune_factions.append(faction)

	_immune_unit_types.clear()
	for unit_type in data.get("immune_unit_types", ["human_soldier", "boss_unit", "structure"]):
		_immune_unit_types.append(unit_type)

	min_hackable_level = data.get("min_hackable_level", 0)
	max_hackable_level = data.get("max_hackable_level", -1)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"hacker_factions": _hacker_factions,
		"immune_factions": _immune_factions,
		"immune_unit_types": _immune_unit_types
	}
