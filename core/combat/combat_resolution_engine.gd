class_name CombatResolutionEngine
extends RefCounted
## CombatResolutionEngine calculates damage using hybrid damage model.
## Supports damage types, armor, crits, and faction learning scaling.

signal damage_dealt(attacker_id: int, target_id: int, damage: float, is_critical: bool)
signal critical_strike(attacker_id: int, target_id: int, damage: float)
signal knockback_applied(target_id: int, distance: float, direction: Vector3)
signal unit_killed(unit_id: int, killer_id: int)

## Base critical strike chance
const BASE_CRIT_CHANCE := 0.05

## Critical strike damage multiplier
const CRIT_MULTIPLIER := 1.5

## Critical chance per combat XP tier
const CRIT_CHANCE_PER_TIER := 0.001

## Knockback calculation constants
const KNOCKBACK_BASE_DISTANCE := 5.0
const KNOCKBACK_MIN := 2.0
const KNOCKBACK_MAX := 5.0

## Faction buff multiplier range
const BUFF_MIN := 1.0
const BUFF_MAX := 1.3

## Frame budget for combat (ms)
const FRAME_BUDGET_MS := 2.0

## Faction resistance profiles (faction -> {damage_type -> multiplier})
var faction_resistances: Dictionary = {
	"swarm": {
		DamageType.Type.KINETIC: 0.8,
		DamageType.Type.ENERGY: 1.2,
		DamageType.Type.EXPLOSIVE: 1.0,
		DamageType.Type.NANO_SHRED: 1.1
	},
	"legion": {
		DamageType.Type.KINETIC: 0.6,
		DamageType.Type.ENERGY: 0.9,
		DamageType.Type.EXPLOSIVE: 0.7,
		DamageType.Type.NANO_SHRED: 1.3
	},
	"nexus": {
		DamageType.Type.KINETIC: 1.0,
		DamageType.Type.ENERGY: 0.7,
		DamageType.Type.EXPLOSIVE: 1.1,
		DamageType.Type.NANO_SHRED: 0.8
	}
}

## Faction damage emphasis (faction -> {damage_type -> multiplier})
var faction_damage_emphasis: Dictionary = {
	"swarm": {
		DamageType.Type.KINETIC: 1.2,
		DamageType.Type.ENERGY: 0.8,
		DamageType.Type.EXPLOSIVE: 0.9,
		DamageType.Type.NANO_SHRED: 1.1
	},
	"legion": {
		DamageType.Type.KINETIC: 1.0,
		DamageType.Type.ENERGY: 0.9,
		DamageType.Type.EXPLOSIVE: 1.3,
		DamageType.Type.NANO_SHRED: 0.8
	},
	"nexus": {
		DamageType.Type.KINETIC: 0.8,
		DamageType.Type.ENERGY: 1.4,
		DamageType.Type.EXPLOSIVE: 0.7,
		DamageType.Type.NANO_SHRED: 1.1
	}
}

## Faction base armor values
var faction_base_armor: Dictionary = {
	"swarm": 10.0,
	"legion": 25.0,
	"nexus": 15.0
}

## RNG for combat calculations
var _rng: RandomNumberGenerator = null

## Combat statistics
var stats: Dictionary = {
	"total_damage_dealt": 0.0,
	"total_hits": 0,
	"total_crits": 0,
	"total_kills": 0,
	"knockbacks_applied": 0
}


func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()


## Calculate damage using hybrid formula.
func calculate_damage(
	base_damage: float,
	damage_type: int,
	attacker_faction: String,
	target_faction: String,
	target_armor: float,
	attacker_xp_tier: int = 0,
	attacker_buff_mult: float = 1.0
) -> Dictionary:
	# Get damage type multiplier (attacker emphasis vs target resistance)
	var attack_emphasis := _get_damage_emphasis(attacker_faction, damage_type)
	var target_resistance := _get_damage_resistance(target_faction, damage_type)
	var damage_type_mult := attack_emphasis / maxf(target_resistance, 0.1)

	# Calculate armor reduction
	var armor_reduction := _calculate_armor_reduction(target_armor, damage_type)

	# Check for critical strike
	var crit_chance := BASE_CRIT_CHANCE + (attacker_xp_tier * CRIT_CHANCE_PER_TIER)
	var is_critical := _rng.randf() < crit_chance
	var crit_mult := CRIT_MULTIPLIER if is_critical else 1.0

	# Clamp faction buff multiplier
	var faction_buff := clampf(attacker_buff_mult, BUFF_MIN, BUFF_MAX)

	# Final damage formula
	var final_damage := base_damage * (1.0 - armor_reduction) * damage_type_mult * faction_buff * crit_mult

	return {
		"damage": maxf(0.0, final_damage),
		"base_damage": base_damage,
		"armor_reduction": armor_reduction,
		"damage_type_mult": damage_type_mult,
		"faction_buff": faction_buff,
		"crit_mult": crit_mult,
		"is_critical": is_critical
	}


## Apply damage to target and handle effects.
func resolve_combat(
	attacker_id: int,
	target_id: int,
	attacker_position: Vector3,
	target_position: Vector3,
	base_damage: float,
	damage_type: int,
	attacker_faction: String,
	target_faction: String,
	target_armor: float,
	target_health: float,
	target_max_health: float,
	attacker_xp_tier: int = 0,
	attacker_buff_mult: float = 1.0
) -> Dictionary:
	# Calculate damage
	var damage_result := calculate_damage(
		base_damage,
		damage_type,
		attacker_faction,
		target_faction,
		target_armor,
		attacker_xp_tier,
		attacker_buff_mult
	)

	var final_damage: float = damage_result["damage"]
	var is_critical: bool = damage_result["is_critical"]

	# Emit damage event
	damage_dealt.emit(attacker_id, target_id, final_damage, is_critical)

	if is_critical:
		critical_strike.emit(attacker_id, target_id, final_damage)
		stats["total_crits"] += 1

	stats["total_damage_dealt"] += final_damage
	stats["total_hits"] += 1

	# Check for kill
	var new_health := target_health - final_damage
	var killed := new_health <= 0

	if killed:
		unit_killed.emit(target_id, attacker_id)
		stats["total_kills"] += 1

	# Calculate knockback if applicable
	var knockback_distance := 0.0
	var knockback_direction := Vector3.ZERO

	if DamageType.causes_knockback(damage_type) and not killed:
		knockback_distance = _calculate_knockback(final_damage, target_max_health)
		knockback_direction = (target_position - attacker_position).normalized()

		if knockback_distance > 0:
			knockback_applied.emit(target_id, knockback_distance, knockback_direction)
			stats["knockbacks_applied"] += 1

	return {
		"damage": final_damage,
		"is_critical": is_critical,
		"killed": killed,
		"new_health": maxf(0.0, new_health),
		"knockback_distance": knockback_distance,
		"knockback_direction": knockback_direction,
		"damage_breakdown": damage_result
	}


## Calculate armor reduction.
func _calculate_armor_reduction(armor: float, damage_type: int) -> float:
	# Nano-shred bypasses armor
	if damage_type == DamageType.Type.NANO_SHRED:
		return 0.0

	# Armor reduction formula: diminishing returns
	# 100 armor = 50% reduction, 200 armor = 66% reduction
	if armor <= 0:
		return 0.0

	return armor / (armor + 100.0)


## Calculate knockback distance.
func _calculate_knockback(damage_dealt: float, target_max_health: float) -> float:
	if target_max_health <= 0:
		return 0.0

	var ratio := damage_dealt / target_max_health
	var distance := ratio * KNOCKBACK_BASE_DISTANCE

	return clampf(distance, KNOCKBACK_MIN, KNOCKBACK_MAX)


## Get damage emphasis for faction.
func _get_damage_emphasis(faction: String, damage_type: int) -> float:
	var faction_data: Dictionary = faction_damage_emphasis.get(faction, {})
	return faction_data.get(damage_type, 1.0)


## Get damage resistance for faction.
func _get_damage_resistance(faction: String, damage_type: int) -> float:
	var faction_data: Dictionary = faction_resistances.get(faction, {})
	return faction_data.get(damage_type, 1.0)


## Get base armor for faction.
func get_faction_base_armor(faction: String) -> float:
	return faction_base_armor.get(faction, 15.0)


## Calculate effective armor with buffs.
func calculate_effective_armor(base_armor: float, armor_buff: float = 0.0) -> float:
	return base_armor * (1.0 + armor_buff)


## Batch process damage calculations (for performance).
func batch_calculate_damage(attacks: Array) -> Array:
	var start_time := Time.get_ticks_usec()
	var results: Array = []

	for attack in attacks:
		var result := calculate_damage(
			attack.get("base_damage", 0.0),
			attack.get("damage_type", DamageType.Type.KINETIC),
			attack.get("attacker_faction", ""),
			attack.get("target_faction", ""),
			attack.get("target_armor", 0.0),
			attack.get("attacker_xp_tier", 0),
			attack.get("attacker_buff_mult", 1.0)
		)
		results.append(result)

		# Check frame budget
		var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed > FRAME_BUDGET_MS:
			break

	return results


## Set faction resistance profile.
func set_faction_resistance(faction: String, resistances: Dictionary) -> void:
	faction_resistances[faction] = resistances.duplicate()


## Set faction damage emphasis.
func set_faction_damage_emphasis(faction: String, emphasis: Dictionary) -> void:
	faction_damage_emphasis[faction] = emphasis.duplicate()


## Get statistics.
func get_statistics() -> Dictionary:
	var crit_rate := 0.0
	if stats["total_hits"] > 0:
		crit_rate = float(stats["total_crits"]) / float(stats["total_hits"])

	return {
		"total_damage": stats["total_damage_dealt"],
		"total_hits": stats["total_hits"],
		"total_crits": stats["total_crits"],
		"crit_rate": crit_rate,
		"total_kills": stats["total_kills"],
		"knockbacks": stats["knockbacks_applied"]
	}


## Reset statistics.
func reset_statistics() -> void:
	stats = {
		"total_damage_dealt": 0.0,
		"total_hits": 0,
		"total_crits": 0,
		"total_kills": 0,
		"knockbacks_applied": 0
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"faction_resistances": faction_resistances.duplicate(true),
		"faction_damage_emphasis": faction_damage_emphasis.duplicate(true),
		"faction_base_armor": faction_base_armor.duplicate(),
		"stats": stats.duplicate(),
		"rng_seed": _rng.seed
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	faction_resistances = data.get("faction_resistances", faction_resistances).duplicate(true)
	faction_damage_emphasis = data.get("faction_damage_emphasis", faction_damage_emphasis).duplicate(true)
	faction_base_armor = data.get("faction_base_armor", faction_base_armor).duplicate()
	stats = data.get("stats", stats).duplicate()
	_rng.seed = data.get("rng_seed", _rng.seed)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var statistics := get_statistics()
	return {
		"hits": stats["total_hits"],
		"crits": stats["total_crits"],
		"crit_rate": "%.1f%%" % (statistics["crit_rate"] * 100),
		"kills": stats["total_kills"],
		"total_damage": "%.0f" % stats["total_damage_dealt"]
	}
