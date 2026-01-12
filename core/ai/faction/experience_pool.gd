class_name ExperiencePool
extends RefCounted
## ExperiencePool manages faction experience accumulation and buff unlocks.
## Thread-safe design for concurrent unit updates.

signal experience_added(faction_id: String, category: String, amount: float)
signal buff_unlocked(faction_id: String, buff_name: String, tier: int)
signal buff_applied(faction_id: String, buff_name: String, value: float)

## Experience categories
enum Category {
	COMBAT,
	ECONOMY,
	ENGINEERING
}

## Tier thresholds
const TIER_THRESHOLDS := {
	1: 1000.0,
	2: 5000.0,
	3: 10000.0
}

## Buff types
enum BuffType {
	DAMAGE_MULTIPLIER,
	ATTACK_SPEED_MULTIPLIER,
	DODGE_CHANCE,
	CRITICAL_STRIKE_CHANCE
}

## Default buff configurations per tier
const DEFAULT_BUFF_CONFIG := {
	1: {
		BuffType.DAMAGE_MULTIPLIER: 0.05,
		BuffType.ATTACK_SPEED_MULTIPLIER: 0.03,
	},
	2: {
		BuffType.DAMAGE_MULTIPLIER: 0.10,
		BuffType.ATTACK_SPEED_MULTIPLIER: 0.08,
		BuffType.DODGE_CHANCE: 0.02,
	},
	3: {
		BuffType.DAMAGE_MULTIPLIER: 0.20,
		BuffType.ATTACK_SPEED_MULTIPLIER: 0.15,
		BuffType.DODGE_CHANCE: 0.05,
		BuffType.CRITICAL_STRIKE_CHANCE: 0.08,
	}
}

## Buff type names for serialization
const BUFF_NAMES := {
	BuffType.DAMAGE_MULTIPLIER: "damage_multiplier",
	BuffType.ATTACK_SPEED_MULTIPLIER: "attack_speed_multiplier",
	BuffType.DODGE_CHANCE: "dodge_chance",
	BuffType.CRITICAL_STRIKE_CHANCE: "critical_strike_chance"
}

## Experience pools (faction_id -> category -> xp)
var _pools: Dictionary = {}

## Unlocked tiers (faction_id -> category -> tier)
var _unlocked_tiers: Dictionary = {}

## Active buffs (faction_id -> buff_type -> value)
var _active_buffs: Dictionary = {}

## Mutex for thread safety (simulated with flag)
var _update_lock := false

## Pending updates queue for batch processing
var _pending_updates: Array[Dictionary] = []

## Registered units per faction (faction_id -> Array[int])
var _faction_units: Dictionary = {}


func _init() -> void:
	pass


## Register faction for experience tracking.
func register_faction(faction_id: String) -> void:
	if _pools.has(faction_id):
		return

	_pools[faction_id] = {
		Category.COMBAT: 0.0,
		Category.ECONOMY: 0.0,
		Category.ENGINEERING: 0.0
	}

	_unlocked_tiers[faction_id] = {
		Category.COMBAT: 0,
		Category.ECONOMY: 0,
		Category.ENGINEERING: 0
	}

	_active_buffs[faction_id] = {}
	_faction_units[faction_id] = []


## Register unit with faction.
func register_unit(unit_id: int, faction_id: String) -> void:
	if not _pools.has(faction_id):
		register_faction(faction_id)

	if unit_id not in _faction_units[faction_id]:
		_faction_units[faction_id].append(unit_id)


## Unregister unit.
func unregister_unit(unit_id: int, faction_id: String) -> void:
	if not _faction_units.has(faction_id):
		return

	var idx := _faction_units[faction_id].find(unit_id)
	if idx != -1:
		_faction_units[faction_id].remove_at(idx)


## Add experience to faction pool (thread-safe).
func add_experience(faction_id: String, category: int, amount: float) -> void:
	if amount <= 0:
		return

	# Queue update for batch processing
	_pending_updates.append({
		"faction_id": faction_id,
		"category": category,
		"amount": amount
	})


## Process pending experience updates (call from main thread).
func process_updates() -> void:
	if _pending_updates.is_empty():
		return

	if _update_lock:
		return

	_update_lock = true

	# Aggregate updates by faction and category
	var aggregated: Dictionary = {}

	for update in _pending_updates:
		var faction_id: String = update["faction_id"]
		var category: int = update["category"]
		var amount: float = update["amount"]

		if not aggregated.has(faction_id):
			aggregated[faction_id] = {}
		if not aggregated[faction_id].has(category):
			aggregated[faction_id][category] = 0.0

		aggregated[faction_id][category] += amount

	_pending_updates.clear()

	# Apply aggregated updates
	for faction_id in aggregated:
		for category in aggregated[faction_id]:
			var amount: float = aggregated[faction_id][category]
			_apply_experience(faction_id, category, amount)

	_update_lock = false


## Internal experience application.
func _apply_experience(faction_id: String, category: int, amount: float) -> void:
	if not _pools.has(faction_id):
		register_faction(faction_id)

	var old_xp: float = _pools[faction_id][category]
	var new_xp := old_xp + amount
	_pools[faction_id][category] = new_xp

	var category_name := _get_category_name(category)
	experience_added.emit(faction_id, category_name, amount)

	# Check for tier unlock
	_check_tier_unlock(faction_id, category, old_xp, new_xp)


## Check and apply tier unlocks.
func _check_tier_unlock(faction_id: String, category: int, old_xp: float, new_xp: float) -> void:
	var current_tier: int = _unlocked_tiers[faction_id][category]

	for tier in [1, 2, 3]:
		if tier <= current_tier:
			continue

		var threshold: float = TIER_THRESHOLDS[tier]

		if old_xp < threshold and new_xp >= threshold:
			_unlocked_tiers[faction_id][category] = tier
			_apply_tier_buffs(faction_id, category, tier)


## Apply buffs for tier unlock.
func _apply_tier_buffs(faction_id: String, category: int, tier: int) -> void:
	if not DEFAULT_BUFF_CONFIG.has(tier):
		return

	var tier_buffs: Dictionary = DEFAULT_BUFF_CONFIG[tier]

	for buff_type in tier_buffs:
		var value: float = tier_buffs[buff_type]
		var buff_name: String = BUFF_NAMES[buff_type]

		# Accumulate buff values
		var current_value: float = _active_buffs[faction_id].get(buff_type, 0.0)
		var new_value := current_value + value
		_active_buffs[faction_id][buff_type] = new_value

		buff_unlocked.emit(faction_id, buff_name, tier)
		buff_applied.emit(faction_id, buff_name, new_value)


## Get experience for faction category.
func get_experience(faction_id: String, category: int) -> float:
	if not _pools.has(faction_id):
		return 0.0
	return _pools[faction_id].get(category, 0.0)


## Get total experience for faction.
func get_total_experience(faction_id: String) -> float:
	if not _pools.has(faction_id):
		return 0.0

	var total := 0.0
	for category in Category.values():
		total += _pools[faction_id].get(category, 0.0)
	return total


## Get current tier for faction category.
func get_tier(faction_id: String, category: int) -> int:
	if not _unlocked_tiers.has(faction_id):
		return 0
	return _unlocked_tiers[faction_id].get(category, 0)


## Get buff value for faction.
func get_buff(faction_id: String, buff_type: int) -> float:
	if not _active_buffs.has(faction_id):
		return 0.0
	return _active_buffs[faction_id].get(buff_type, 0.0)


## Get all buffs for faction.
func get_all_buffs(faction_id: String) -> Dictionary:
	if not _active_buffs.has(faction_id):
		return {}

	var result: Dictionary = {}
	for buff_type in _active_buffs[faction_id]:
		result[BUFF_NAMES[buff_type]] = _active_buffs[faction_id][buff_type]
	return result


## Get damage multiplier buff.
func get_damage_multiplier(faction_id: String) -> float:
	return 1.0 + get_buff(faction_id, BuffType.DAMAGE_MULTIPLIER)


## Get attack speed multiplier buff.
func get_attack_speed_multiplier(faction_id: String) -> float:
	return 1.0 + get_buff(faction_id, BuffType.ATTACK_SPEED_MULTIPLIER)


## Get dodge chance buff.
func get_dodge_chance(faction_id: String) -> float:
	return get_buff(faction_id, BuffType.DODGE_CHANCE)


## Get critical strike chance buff.
func get_critical_strike_chance(faction_id: String) -> float:
	return get_buff(faction_id, BuffType.CRITICAL_STRIKE_CHANCE)


## Get faction unit count.
func get_unit_count(faction_id: String) -> int:
	if not _faction_units.has(faction_id):
		return 0
	return _faction_units[faction_id].size()


## Get category name string.
func _get_category_name(category: int) -> String:
	match category:
		Category.COMBAT:
			return "combat"
		Category.ECONOMY:
			return "economy"
		Category.ENGINEERING:
			return "engineering"
	return "unknown"


## Get faction status for UI.
func get_faction_status(faction_id: String) -> Dictionary:
	if not _pools.has(faction_id):
		return {}

	return {
		"faction_id": faction_id,
		"experience": {
			"combat": get_experience(faction_id, Category.COMBAT),
			"economy": get_experience(faction_id, Category.ECONOMY),
			"engineering": get_experience(faction_id, Category.ENGINEERING),
			"total": get_total_experience(faction_id)
		},
		"tiers": {
			"combat": get_tier(faction_id, Category.COMBAT),
			"economy": get_tier(faction_id, Category.ECONOMY),
			"engineering": get_tier(faction_id, Category.ENGINEERING)
		},
		"buffs": get_all_buffs(faction_id),
		"unit_count": get_unit_count(faction_id)
	}


## Serialization.
func to_dict() -> Dictionary:
	var pools_data: Dictionary = {}
	for faction_id in _pools:
		pools_data[faction_id] = {}
		for category in Category.values():
			pools_data[faction_id][str(category)] = _pools[faction_id].get(category, 0.0)

	var tiers_data: Dictionary = {}
	for faction_id in _unlocked_tiers:
		tiers_data[faction_id] = {}
		for category in Category.values():
			tiers_data[faction_id][str(category)] = _unlocked_tiers[faction_id].get(category, 0)

	var buffs_data: Dictionary = {}
	for faction_id in _active_buffs:
		buffs_data[faction_id] = {}
		for buff_type in _active_buffs[faction_id]:
			buffs_data[faction_id][str(buff_type)] = _active_buffs[faction_id][buff_type]

	var units_data: Dictionary = {}
	for faction_id in _faction_units:
		units_data[faction_id] = _faction_units[faction_id].duplicate()

	return {
		"pools": pools_data,
		"unlocked_tiers": tiers_data,
		"active_buffs": buffs_data,
		"faction_units": units_data
	}


func from_dict(data: Dictionary) -> void:
	_pools.clear()
	var pools_data: Dictionary = data.get("pools", {})
	for faction_id in pools_data:
		_pools[faction_id] = {}
		for category_str in pools_data[faction_id]:
			_pools[faction_id][int(category_str)] = pools_data[faction_id][category_str]

	_unlocked_tiers.clear()
	var tiers_data: Dictionary = data.get("unlocked_tiers", {})
	for faction_id in tiers_data:
		_unlocked_tiers[faction_id] = {}
		for category_str in tiers_data[faction_id]:
			_unlocked_tiers[faction_id][int(category_str)] = tiers_data[faction_id][category_str]

	_active_buffs.clear()
	var buffs_data: Dictionary = data.get("active_buffs", {})
	for faction_id in buffs_data:
		_active_buffs[faction_id] = {}
		for buff_type_str in buffs_data[faction_id]:
			_active_buffs[faction_id][int(buff_type_str)] = buffs_data[faction_id][buff_type_str]

	_faction_units.clear()
	var units_data: Dictionary = data.get("faction_units", {})
	for faction_id in units_data:
		_faction_units[faction_id] = units_data[faction_id].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_count := _pools.size()
	var total_units := 0

	for faction_id in _faction_units:
		total_units += _faction_units[faction_id].size()

	return {
		"factions_registered": faction_count,
		"total_units": total_units,
		"pending_updates": _pending_updates.size(),
		"tier_thresholds": TIER_THRESHOLDS.duplicate()
	}
