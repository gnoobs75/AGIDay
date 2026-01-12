class_name CombatBuffIntegration
extends RefCounted
## CombatBuffIntegration integrates faction buffs with combat resolution.
## Applies damage multipliers and other buffs to combat calculations.

signal buff_applied(attacker_id: int, buff_type: String, value: float)
signal damage_modified(attacker_id: int, base_damage: float, modified_damage: float)
signal critical_triggered(attacker_id: int, damage: float)

## Reference to combat experience system
var _combat_experience: CombatExperience = null

## Reference to faction learning
var _faction_learning: FactionLearning = null

## Unit faction cache (unit_id -> faction_id)
var _unit_factions: Dictionary = {}

## Retroactive buff queue (when units exist before buffs unlocked)
var _pending_buff_applications: Array[Dictionary] = []


func _init() -> void:
	pass


## Set combat experience reference.
func set_combat_experience(experience: CombatExperience) -> void:
	_combat_experience = experience

	if _combat_experience != null:
		_combat_experience.tier_reached.connect(_on_tier_reached)


## Set faction learning reference.
func set_faction_learning(learning: FactionLearning) -> void:
	_faction_learning = learning


## Register unit with faction.
func register_unit(unit_id: int, faction_id: String) -> void:
	_unit_factions[unit_id] = faction_id


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_factions.erase(unit_id)


## Get unit faction.
func get_unit_faction(unit_id: int) -> String:
	return _unit_factions.get(unit_id, "")


## Calculate modified damage with faction buffs.
func calculate_damage(attacker_id: int, base_damage: float) -> float:
	var faction_id := get_unit_faction(attacker_id)

	if faction_id == "":
		return base_damage

	var multiplier := get_faction_buff_multiplier(faction_id)
	var modified_damage := base_damage * multiplier

	# Check for critical strike
	var crit_chance := get_critical_chance(faction_id)
	if crit_chance > 0 and randf() < crit_chance:
		modified_damage *= 2.0
		critical_triggered.emit(attacker_id, modified_damage)

	if modified_damage != base_damage:
		damage_modified.emit(attacker_id, base_damage, modified_damage)

	return modified_damage


## Get faction buff multiplier (damage).
func get_faction_buff_multiplier(faction_id: String) -> float:
	if _combat_experience == null:
		return 1.0

	return _combat_experience.get_damage_multiplier(faction_id)


## Get faction attack speed multiplier.
func get_attack_speed_multiplier(faction_id: String) -> float:
	if _combat_experience == null:
		return 1.0

	return _combat_experience.get_attack_speed_multiplier(faction_id)


## Get faction armor bonus.
func get_armor_bonus(faction_id: String) -> float:
	if _combat_experience == null:
		return 0.0

	return _combat_experience.get_armor_bonus(faction_id)


## Get critical strike chance.
func get_critical_chance(faction_id: String) -> float:
	if _combat_experience == null:
		return 0.0

	return _combat_experience.get_critical_strike_chance(faction_id)


## Apply all buffs to damage calculation.
func apply_combat_buffs(attacker_id: int, base_damage: float, attack_context: Dictionary) -> Dictionary:
	var faction_id := get_unit_faction(attacker_id)

	if faction_id == "":
		return {
			"damage": base_damage,
			"critical": false,
			"buffs_applied": []
		}

	var buffs_applied: Array[String] = []
	var damage := base_damage
	var is_critical := false

	# Apply damage multiplier
	var damage_mult := get_faction_buff_multiplier(faction_id)
	if damage_mult != 1.0:
		damage *= damage_mult
		buffs_applied.append("damage_multiplier")
		buff_applied.emit(attacker_id, "damage_multiplier", damage_mult)

	# Check critical strike
	var crit_chance := get_critical_chance(faction_id)
	if crit_chance > 0:
		var roll := randf()
		if roll < crit_chance:
			damage *= 2.0
			is_critical = true
			buffs_applied.append("critical_strike")
			critical_triggered.emit(attacker_id, damage)

	return {
		"damage": damage,
		"critical": is_critical,
		"buffs_applied": buffs_applied
	}


## Handle tier reached - apply buffs to all faction units.
func _on_tier_reached(faction_id: String, tier: int, buffs: Dictionary) -> void:
	# Queue retroactive buff application
	for unit_id in _unit_factions:
		if _unit_factions[unit_id] == faction_id:
			_pending_buff_applications.append({
				"unit_id": unit_id,
				"faction_id": faction_id,
				"tier": tier,
				"buffs": buffs
			})


## Process pending buff applications.
func process_pending_buffs() -> int:
	var count := _pending_buff_applications.size()
	_pending_buff_applications.clear()
	return count


## Get units by faction.
func get_faction_units(faction_id: String) -> Array[int]:
	var units: Array[int] = []

	for unit_id in _unit_factions:
		if _unit_factions[unit_id] == faction_id:
			units.append(unit_id)

	return units


## Get buff status for unit.
func get_unit_buff_status(unit_id: int) -> Dictionary:
	var faction_id := get_unit_faction(unit_id)

	if faction_id == "":
		return {}

	return {
		"faction_id": faction_id,
		"damage_multiplier": get_faction_buff_multiplier(faction_id),
		"attack_speed_multiplier": get_attack_speed_multiplier(faction_id),
		"armor_bonus": get_armor_bonus(faction_id),
		"critical_chance": get_critical_chance(faction_id)
	}


## Serialization.
func to_dict() -> Dictionary:
	var factions_data: Dictionary = {}
	for unit_id in _unit_factions:
		factions_data[str(unit_id)] = _unit_factions[unit_id]

	return {
		"unit_factions": factions_data
	}


func from_dict(data: Dictionary) -> void:
	_unit_factions.clear()
	var factions_data: Dictionary = data.get("unit_factions", {})
	for unit_id_str in factions_data:
		_unit_factions[int(unit_id_str)] = factions_data[unit_id_str]


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_counts: Dictionary = {}

	for unit_id in _unit_factions:
		var faction_id: String = _unit_factions[unit_id]
		faction_counts[faction_id] = faction_counts.get(faction_id, 0) + 1

	return {
		"registered_units": _unit_factions.size(),
		"pending_buff_applications": _pending_buff_applications.size(),
		"units_by_faction": faction_counts
	}
