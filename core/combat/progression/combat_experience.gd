class_name CombatExperience
extends RefCounted
## CombatExperience tracks combat XP sources and faction progression.
## Manages XP accumulation from kills, damage, survival, and assists.

signal xp_gained(faction_id: String, source: String, amount: float)
signal tier_reached(faction_id: String, tier: int, buffs: Dictionary)
signal targeting_mode_evolved(faction_id: String, old_mode: String, new_mode: String)

## XP sources
const XP_UNIT_KILL := 50.0
const XP_PER_100_DAMAGE := 1.0
const XP_SURVIVAL_PER_30S := 10.0
const XP_KILL_ASSIST := 25.0

## Tier thresholds
const TIER_1_THRESHOLD := 1000.0
const TIER_2_THRESHOLD := 5000.0
const TIER_3_THRESHOLD := 10000.0

## Targeting mode thresholds
const TARGET_NEAREST_MAX := 2000.0
const TARGET_THREAT_MIN := 2000.0
const TARGET_THREAT_MAX := 7000.0
const TARGET_PRIORITY_MIN := 7000.0

## Targeting modes
enum TargetingMode {
	NEAREST,
	THREAT_BASED,
	PRIORITY
}

## Damage multipliers per tier
const DAMAGE_MULTIPLIERS := {
	0: 1.0,
	1: 1.1,
	2: 1.2,
	3: 1.3
}

## Additional buff values per tier
const TIER_BUFFS := {
	1: {
		"damage_multiplier": 1.1,
		"attack_speed_multiplier": 1.05,
		"armor_bonus": 0.03,
		"critical_strike_chance": 0.02
	},
	2: {
		"damage_multiplier": 1.2,
		"attack_speed_multiplier": 1.10,
		"armor_bonus": 0.06,
		"critical_strike_chance": 0.05
	},
	3: {
		"damage_multiplier": 1.3,
		"attack_speed_multiplier": 1.15,
		"armor_bonus": 0.10,
		"critical_strike_chance": 0.08
	}
}

## Faction combat XP (faction_id -> xp)
var _faction_xp: Dictionary = {}

## Faction tiers (faction_id -> tier)
var _faction_tiers: Dictionary = {}

## Faction targeting modes (faction_id -> mode)
var _faction_targeting: Dictionary = {}

## Unit survival tracking (unit_id -> start_time)
var _unit_survival_starts: Dictionary = {}

## Recent damage tracking for survival XP (unit_id -> last_xp_time)
var _unit_survival_last_xp: Dictionary = {}

## Callbacks
var _add_faction_xp: Callable  ## (category: String, amount: float) -> void


func _init() -> void:
	pass


## Set faction XP callback.
func set_add_faction_xp_callback(callback: Callable) -> void:
	_add_faction_xp = callback


## Initialize faction.
func initialize_faction(faction_id: String) -> void:
	if not _faction_xp.has(faction_id):
		_faction_xp[faction_id] = 0.0
		_faction_tiers[faction_id] = 0
		_faction_targeting[faction_id] = TargetingMode.NEAREST


## Record unit kill.
func record_kill(killer_faction: String, victim_faction: String) -> float:
	initialize_faction(killer_faction)

	_add_xp(killer_faction, XP_UNIT_KILL, "unit_kill")
	return XP_UNIT_KILL


## Record damage dealt.
func record_damage(attacker_faction: String, damage_amount: float) -> float:
	if damage_amount <= 0:
		return 0.0

	initialize_faction(attacker_faction)

	var xp := (damage_amount / 100.0) * XP_PER_100_DAMAGE
	_add_xp(attacker_faction, xp, "damage_dealt")
	return xp


## Record kill assist.
func record_assist(assist_faction: String) -> float:
	initialize_faction(assist_faction)

	_add_xp(assist_faction, XP_KILL_ASSIST, "kill_assist")
	return XP_KILL_ASSIST


## Start survival tracking for unit.
func start_survival_tracking(unit_id: int, faction_id: String) -> void:
	initialize_faction(faction_id)

	var current_time := Time.get_ticks_msec() / 1000.0
	_unit_survival_starts[unit_id] = {
		"faction_id": faction_id,
		"start_time": current_time
	}
	_unit_survival_last_xp[unit_id] = current_time


## Update survival XP for unit.
func update_survival_xp(unit_id: int) -> float:
	if not _unit_survival_starts.has(unit_id):
		return 0.0

	var data: Dictionary = _unit_survival_starts[unit_id]
	var faction_id: String = data["faction_id"]
	var current_time := Time.get_ticks_msec() / 1000.0
	var last_xp_time: float = _unit_survival_last_xp.get(unit_id, current_time)

	var elapsed := current_time - last_xp_time
	var intervals := int(elapsed / 30.0)

	if intervals > 0:
		var xp := float(intervals) * XP_SURVIVAL_PER_30S
		_add_xp(faction_id, xp, "survival")
		_unit_survival_last_xp[unit_id] = last_xp_time + (float(intervals) * 30.0)
		return xp

	return 0.0


## Stop survival tracking for unit.
func stop_survival_tracking(unit_id: int) -> float:
	# Award any remaining survival XP
	var final_xp := update_survival_xp(unit_id)

	_unit_survival_starts.erase(unit_id)
	_unit_survival_last_xp.erase(unit_id)

	return final_xp


## Internal XP addition.
func _add_xp(faction_id: String, amount: float, source: String) -> void:
	if amount <= 0:
		return

	var old_xp: float = _faction_xp.get(faction_id, 0.0)
	var new_xp := old_xp + amount
	_faction_xp[faction_id] = new_xp

	xp_gained.emit(faction_id, source, amount)

	# Also update faction manager if callback set
	if _add_faction_xp.is_valid():
		_add_faction_xp.call("combat", amount)

	# Check tier progression
	_check_tier_progression(faction_id, old_xp, new_xp)

	# Check targeting evolution
	_check_targeting_evolution(faction_id, old_xp, new_xp)


## Check and apply tier progression.
func _check_tier_progression(faction_id: String, old_xp: float, new_xp: float) -> void:
	var old_tier := _get_tier_for_xp(old_xp)
	var new_tier := _get_tier_for_xp(new_xp)

	if new_tier > old_tier:
		_faction_tiers[faction_id] = new_tier

		var buffs := get_tier_buffs(new_tier)
		tier_reached.emit(faction_id, new_tier, buffs)


## Get tier for XP amount.
func _get_tier_for_xp(xp: float) -> int:
	if xp >= TIER_3_THRESHOLD:
		return 3
	elif xp >= TIER_2_THRESHOLD:
		return 2
	elif xp >= TIER_1_THRESHOLD:
		return 1
	return 0


## Check targeting mode evolution.
func _check_targeting_evolution(faction_id: String, old_xp: float, new_xp: float) -> void:
	var old_mode := _get_targeting_mode_for_xp(old_xp)
	var new_mode := _get_targeting_mode_for_xp(new_xp)

	if new_mode != old_mode:
		_faction_targeting[faction_id] = new_mode

		var old_name := _get_targeting_mode_name(old_mode)
		var new_name := _get_targeting_mode_name(new_mode)
		targeting_mode_evolved.emit(faction_id, old_name, new_name)


## Get targeting mode for XP.
func _get_targeting_mode_for_xp(xp: float) -> int:
	if xp >= TARGET_PRIORITY_MIN:
		return TargetingMode.PRIORITY
	elif xp >= TARGET_THREAT_MIN:
		return TargetingMode.THREAT_BASED
	return TargetingMode.NEAREST


## Get targeting mode name.
func _get_targeting_mode_name(mode: int) -> String:
	match mode:
		TargetingMode.NEAREST:
			return "NEAREST"
		TargetingMode.THREAT_BASED:
			return "THREAT_BASED"
		TargetingMode.PRIORITY:
			return "PRIORITY"
	return "UNKNOWN"


## Calculate blend progress for targeting transitions.
func calculate_blend_progress(faction_id: String) -> float:
	var xp: float = _faction_xp.get(faction_id, 0.0)

	# Between NEAREST and THREAT_BASED
	if xp < TARGET_THREAT_MIN:
		return 0.0

	if xp >= TARGET_PRIORITY_MIN:
		return 1.0

	# In transition zone
	var progress := (xp - TARGET_THREAT_MIN) / (TARGET_PRIORITY_MIN - TARGET_THREAT_MIN)
	return clampf(progress, 0.0, 1.0)


## Get faction combat XP.
func get_faction_xp(faction_id: String) -> float:
	return _faction_xp.get(faction_id, 0.0)


## Get faction tier.
func get_faction_tier(faction_id: String) -> int:
	return _faction_tiers.get(faction_id, 0)


## Get faction targeting mode.
func get_targeting_mode(faction_id: String) -> int:
	return _faction_targeting.get(faction_id, TargetingMode.NEAREST)


## Get tier buffs.
func get_tier_buffs(tier: int) -> Dictionary:
	return TIER_BUFFS.get(tier, {}).duplicate()


## Get damage multiplier for faction.
func get_damage_multiplier(faction_id: String) -> float:
	var tier := get_faction_tier(faction_id)
	return DAMAGE_MULTIPLIERS.get(tier, 1.0)


## Get attack speed multiplier for faction.
func get_attack_speed_multiplier(faction_id: String) -> float:
	var tier := get_faction_tier(faction_id)
	var buffs := get_tier_buffs(tier)
	return buffs.get("attack_speed_multiplier", 1.0)


## Get armor bonus for faction.
func get_armor_bonus(faction_id: String) -> float:
	var tier := get_faction_tier(faction_id)
	var buffs := get_tier_buffs(tier)
	return buffs.get("armor_bonus", 0.0)


## Get critical strike chance for faction.
func get_critical_strike_chance(faction_id: String) -> float:
	var tier := get_faction_tier(faction_id)
	var buffs := get_tier_buffs(tier)
	return buffs.get("critical_strike_chance", 0.0)


## Serialization.
func to_dict() -> Dictionary:
	var survival_data: Dictionary = {}
	for unit_id in _unit_survival_starts:
		survival_data[str(unit_id)] = _unit_survival_starts[unit_id].duplicate()

	return {
		"faction_xp": _faction_xp.duplicate(),
		"faction_tiers": _faction_tiers.duplicate(),
		"faction_targeting": _faction_targeting.duplicate(),
		"unit_survival_starts": survival_data
	}


func from_dict(data: Dictionary) -> void:
	_faction_xp = data.get("faction_xp", {}).duplicate()
	_faction_tiers = data.get("faction_tiers", {}).duplicate()
	_faction_targeting = data.get("faction_targeting", {}).duplicate()

	_unit_survival_starts.clear()
	var survival_data: Dictionary = data.get("unit_survival_starts", {})
	for unit_id_str in survival_data:
		_unit_survival_starts[int(unit_id_str)] = survival_data[unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_summaries: Dictionary = {}

	for faction_id in _faction_xp:
		faction_summaries[faction_id] = {
			"xp": _faction_xp[faction_id],
			"tier": get_faction_tier(faction_id),
			"targeting_mode": _get_targeting_mode_name(get_targeting_mode(faction_id)),
			"damage_multiplier": get_damage_multiplier(faction_id),
			"blend_progress": calculate_blend_progress(faction_id)
		}

	return {
		"factions_tracked": _faction_xp.size(),
		"units_with_survival_tracking": _unit_survival_starts.size(),
		"faction_details": faction_summaries
	}
