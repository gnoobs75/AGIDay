class_name AetherSwarmProgression
extends RefCounted
## AetherSwarmProgression manages the three experience pools and tiered buff unlocks.
## Tracks combat, economy, and engineering XP with automatic buff threshold checks.

signal buff_unlocked(buff_id: String, tier: int, effects: Dictionary)
signal combat_threshold_reached(threshold: int, tier: int)
signal economy_threshold_reached(threshold: int, tier: int)
signal engineering_threshold_reached(threshold: int, tier: int)
signal progression_updated(pool: String, xp: float, tier: int)

## Experience pool types
enum XPPool {
	COMBAT,
	ECONOMY,
	ENGINEERING
}

## Combat buff thresholds and effects
const COMBAT_THRESHOLDS := {
	1000: {
		"tier": 1,
		"buff_id": "combat_tier_1",
		"effects": {
			"damage_multiplier": 1.1,
			"attack_speed_multiplier": 1.05
		}
	},
	5000: {
		"tier": 2,
		"buff_id": "combat_tier_2",
		"effects": {
			"damage_multiplier": 1.2,
			"dodge_chance": 0.10
		}
	},
	10000: {
		"tier": 3,
		"buff_id": "combat_tier_3",
		"effects": {
			"damage_multiplier": 1.3,
			"crit_chance": 0.15
		}
	}
}

## Economy buff thresholds and effects
const ECONOMY_THRESHOLDS := {
	500: {
		"tier": 1,
		"buff_id": "economy_tier_1",
		"effects": {
			"ree_generation_multiplier": 1.1,
			"production_multiplier": 1.05
		}
	},
	2500: {
		"tier": 2,
		"buff_id": "economy_tier_2",
		"effects": {
			"ree_generation_multiplier": 1.2,
			"production_multiplier": 1.1
		}
	}
}

## Engineering buff thresholds and effects
const ENGINEERING_THRESHOLDS := {
	300: {
		"tier": 1,
		"buff_id": "engineering_tier_1",
		"effects": {
			"repair_speed_multiplier": 1.1,
			"health_regen": 0.5
		}
	},
	1500: {
		"tier": 2,
		"buff_id": "engineering_tier_2",
		"effects": {
			"repair_speed_multiplier": 1.2,
			"armor_multiplier": 1.1
		}
	}
}

## Current experience values
var _combat_xp: float = 0.0
var _economy_xp: float = 0.0
var _engineering_xp: float = 0.0

## Current tier levels
var _combat_tier: int = 0
var _economy_tier: int = 0
var _engineering_tier: int = 0

## Unlocked buff IDs
var _unlocked_buffs: Array[String] = []

## Cached combined buff effects
var _combined_effects: Dictionary = {}
var _effects_dirty: bool = true

## Reference to faction (optional)
var _faction: AetherSwarmFaction = null


func _init() -> void:
	_recalculate_combined_effects()


## Set faction reference for integration.
func set_faction(faction: AetherSwarmFaction) -> void:
	_faction = faction
	_sync_from_faction()


## Sync XP from faction state.
func _sync_from_faction() -> void:
	if _faction == null:
		return

	_combat_xp = _faction.get_combat_xp()
	_economy_xp = _faction.get_economy_xp()
	_engineering_xp = _faction.get_engineering_xp()

	_check_all_thresholds()


## Add combat experience.
func add_combat_xp(amount: float) -> void:
	if amount <= 0:
		return

	_combat_xp += amount

	# Sync to faction if connected
	if _faction != null:
		_faction.add_combat_xp(amount)

	_check_combat_thresholds()
	progression_updated.emit("combat", _combat_xp, _combat_tier)


## Add economy experience.
func add_economy_xp(amount: float) -> void:
	if amount <= 0:
		return

	_economy_xp += amount

	# Sync to faction if connected
	if _faction != null:
		_faction.add_economy_xp(amount)

	_check_economy_thresholds()
	progression_updated.emit("economy", _economy_xp, _economy_tier)


## Add engineering experience.
func add_engineering_xp(amount: float) -> void:
	if amount <= 0:
		return

	_engineering_xp += amount

	# Sync to faction if connected
	if _faction != null:
		_faction.add_engineering_xp(amount)

	_check_engineering_thresholds()
	progression_updated.emit("engineering", _engineering_xp, _engineering_tier)


## Check all thresholds.
func _check_all_thresholds() -> void:
	_check_combat_thresholds()
	_check_economy_thresholds()
	_check_engineering_thresholds()


## Check combat XP thresholds.
func _check_combat_thresholds() -> void:
	for threshold in COMBAT_THRESHOLDS:
		if _combat_xp >= threshold:
			var data: Dictionary = COMBAT_THRESHOLDS[threshold]
			var buff_id: String = data["buff_id"]

			if buff_id not in _unlocked_buffs:
				_unlock_buff(buff_id, data)
				_combat_tier = maxi(_combat_tier, data["tier"])
				combat_threshold_reached.emit(threshold, data["tier"])


## Check economy XP thresholds.
func _check_economy_thresholds() -> void:
	for threshold in ECONOMY_THRESHOLDS:
		if _economy_xp >= threshold:
			var data: Dictionary = ECONOMY_THRESHOLDS[threshold]
			var buff_id: String = data["buff_id"]

			if buff_id not in _unlocked_buffs:
				_unlock_buff(buff_id, data)
				_economy_tier = maxi(_economy_tier, data["tier"])
				economy_threshold_reached.emit(threshold, data["tier"])


## Check engineering XP thresholds.
func _check_engineering_thresholds() -> void:
	for threshold in ENGINEERING_THRESHOLDS:
		if _engineering_xp >= threshold:
			var data: Dictionary = ENGINEERING_THRESHOLDS[threshold]
			var buff_id: String = data["buff_id"]

			if buff_id not in _unlocked_buffs:
				_unlock_buff(buff_id, data)
				_engineering_tier = maxi(_engineering_tier, data["tier"])
				engineering_threshold_reached.emit(threshold, data["tier"])


## Unlock a buff.
func _unlock_buff(buff_id: String, data: Dictionary) -> void:
	if buff_id in _unlocked_buffs:
		return

	_unlocked_buffs.append(buff_id)
	_effects_dirty = true

	# Sync to faction if connected
	if _faction != null:
		_faction.unlock_buff(buff_id)

	buff_unlocked.emit(buff_id, data["tier"], data["effects"])


## Recalculate combined effects from all unlocked buffs.
func _recalculate_combined_effects() -> void:
	_combined_effects = {
		# Combat effects
		"damage_multiplier": 1.0,
		"attack_speed_multiplier": 1.0,
		"dodge_chance": 0.0,
		"crit_chance": 0.0,
		# Economy effects
		"ree_generation_multiplier": 1.0,
		"production_multiplier": 1.0,
		# Engineering effects
		"repair_speed_multiplier": 1.0,
		"health_regen": 0.0,
		"armor_multiplier": 1.0
	}

	# Apply combat buffs (use highest tier's multipliers)
	var combat_buffs := _get_unlocked_combat_buffs()
	for buff_data in combat_buffs:
		var effects: Dictionary = buff_data["effects"]
		for key in effects:
			if key.ends_with("_multiplier"):
				_combined_effects[key] = maxf(_combined_effects.get(key, 1.0), effects[key])
			else:
				_combined_effects[key] = maxf(_combined_effects.get(key, 0.0), effects[key])

	# Apply economy buffs
	var economy_buffs := _get_unlocked_economy_buffs()
	for buff_data in economy_buffs:
		var effects: Dictionary = buff_data["effects"]
		for key in effects:
			if key.ends_with("_multiplier"):
				_combined_effects[key] = maxf(_combined_effects.get(key, 1.0), effects[key])
			else:
				_combined_effects[key] = maxf(_combined_effects.get(key, 0.0), effects[key])

	# Apply engineering buffs
	var engineering_buffs := _get_unlocked_engineering_buffs()
	for buff_data in engineering_buffs:
		var effects: Dictionary = buff_data["effects"]
		for key in effects:
			if key.ends_with("_multiplier"):
				_combined_effects[key] = maxf(_combined_effects.get(key, 1.0), effects[key])
			else:
				_combined_effects[key] = maxf(_combined_effects.get(key, 0.0), effects[key])

	_effects_dirty = false


## Get unlocked combat buffs.
func _get_unlocked_combat_buffs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for threshold in COMBAT_THRESHOLDS:
		var data: Dictionary = COMBAT_THRESHOLDS[threshold]
		if data["buff_id"] in _unlocked_buffs:
			result.append(data)
	return result


## Get unlocked economy buffs.
func _get_unlocked_economy_buffs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for threshold in ECONOMY_THRESHOLDS:
		var data: Dictionary = ECONOMY_THRESHOLDS[threshold]
		if data["buff_id"] in _unlocked_buffs:
			result.append(data)
	return result


## Get unlocked engineering buffs.
func _get_unlocked_engineering_buffs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for threshold in ENGINEERING_THRESHOLDS:
		var data: Dictionary = ENGINEERING_THRESHOLDS[threshold]
		if data["buff_id"] in _unlocked_buffs:
			result.append(data)
	return result


## Get combined buff effects.
func get_combined_effects() -> Dictionary:
	if _effects_dirty:
		_recalculate_combined_effects()
	return _combined_effects.duplicate()


## Apply progression buffs to unit stats.
func apply_buffs_to_stats(base_stats: Dictionary) -> Dictionary:
	if _effects_dirty:
		_recalculate_combined_effects()

	var result := base_stats.duplicate()

	# Apply damage multiplier
	if result.has("damage"):
		result["damage"] *= _combined_effects.get("damage_multiplier", 1.0)
	if result.has("base_damage"):
		result["base_damage"] *= _combined_effects.get("damage_multiplier", 1.0)

	# Apply attack speed multiplier
	if result.has("attack_speed"):
		result["attack_speed"] *= _combined_effects.get("attack_speed_multiplier", 1.0)
	if result.has("fire_rate"):
		result["fire_rate"] *= _combined_effects.get("attack_speed_multiplier", 1.0)

	# Apply dodge chance
	if _combined_effects.get("dodge_chance", 0.0) > 0:
		result["dodge_chance"] = result.get("dodge_chance", 0.0) + _combined_effects["dodge_chance"]

	# Apply crit chance
	if _combined_effects.get("crit_chance", 0.0) > 0:
		result["crit_chance"] = result.get("crit_chance", 0.0) + _combined_effects["crit_chance"]

	# Apply armor multiplier
	if result.has("armor"):
		result["armor"] *= _combined_effects.get("armor_multiplier", 1.0)

	# Apply health regen
	if _combined_effects.get("health_regen", 0.0) > 0:
		result["health_regen"] = result.get("health_regen", 0.0) + _combined_effects["health_regen"]

	return result


## Get REE generation multiplier.
func get_ree_multiplier() -> float:
	if _effects_dirty:
		_recalculate_combined_effects()
	return _combined_effects.get("ree_generation_multiplier", 1.0)


## Get production multiplier.
func get_production_multiplier() -> float:
	if _effects_dirty:
		_recalculate_combined_effects()
	return _combined_effects.get("production_multiplier", 1.0)


## Get repair speed multiplier.
func get_repair_multiplier() -> float:
	if _effects_dirty:
		_recalculate_combined_effects()
	return _combined_effects.get("repair_speed_multiplier", 1.0)


## Get damage multiplier.
func get_damage_multiplier() -> float:
	if _effects_dirty:
		_recalculate_combined_effects()
	return _combined_effects.get("damage_multiplier", 1.0)


## Get current tier for a pool.
func get_tier(pool: XPPool) -> int:
	match pool:
		XPPool.COMBAT:
			return _combat_tier
		XPPool.ECONOMY:
			return _economy_tier
		XPPool.ENGINEERING:
			return _engineering_tier
	return 0


## Get current XP for a pool.
func get_xp(pool: XPPool) -> float:
	match pool:
		XPPool.COMBAT:
			return _combat_xp
		XPPool.ECONOMY:
			return _economy_xp
		XPPool.ENGINEERING:
			return _engineering_xp
	return 0.0


## Get progress to next threshold (0.0 - 1.0).
func get_progress_to_next(pool: XPPool) -> float:
	var current_xp := get_xp(pool)
	var thresholds: Dictionary

	match pool:
		XPPool.COMBAT:
			thresholds = COMBAT_THRESHOLDS
		XPPool.ECONOMY:
			thresholds = ECONOMY_THRESHOLDS
		XPPool.ENGINEERING:
			thresholds = ENGINEERING_THRESHOLDS
		_:
			return 1.0

	# Find current and next threshold
	var sorted_thresholds := thresholds.keys()
	sorted_thresholds.sort()

	var current_threshold := 0
	var next_threshold := 0

	for threshold in sorted_thresholds:
		if current_xp < threshold:
			next_threshold = threshold
			break
		current_threshold = threshold

	if next_threshold == 0:
		return 1.0  # Max tier reached

	var progress_xp := current_xp - current_threshold
	var needed_xp := next_threshold - current_threshold

	return clampf(progress_xp / needed_xp, 0.0, 1.0)


## Get next threshold for pool.
func get_next_threshold(pool: XPPool) -> int:
	var current_xp := get_xp(pool)
	var thresholds: Dictionary

	match pool:
		XPPool.COMBAT:
			thresholds = COMBAT_THRESHOLDS
		XPPool.ECONOMY:
			thresholds = ECONOMY_THRESHOLDS
		XPPool.ENGINEERING:
			thresholds = ENGINEERING_THRESHOLDS
		_:
			return 0

	var sorted_thresholds := thresholds.keys()
	sorted_thresholds.sort()

	for threshold in sorted_thresholds:
		if current_xp < threshold:
			return threshold

	return 0  # Max tier reached


## Check if buff is unlocked.
func is_buff_unlocked(buff_id: String) -> bool:
	return buff_id in _unlocked_buffs


## Get all unlocked buff IDs.
func get_unlocked_buffs() -> Array[String]:
	return _unlocked_buffs.duplicate()


## Get statistics summary.
func get_statistics() -> Dictionary:
	return {
		"combat_xp": _combat_xp,
		"combat_tier": _combat_tier,
		"combat_progress": get_progress_to_next(XPPool.COMBAT),
		"economy_xp": _economy_xp,
		"economy_tier": _economy_tier,
		"economy_progress": get_progress_to_next(XPPool.ECONOMY),
		"engineering_xp": _engineering_xp,
		"engineering_tier": _engineering_tier,
		"engineering_progress": get_progress_to_next(XPPool.ENGINEERING),
		"total_buffs_unlocked": _unlocked_buffs.size(),
		"damage_multiplier": get_damage_multiplier(),
		"ree_multiplier": get_ree_multiplier(),
		"production_multiplier": get_production_multiplier()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"combat_xp": _combat_xp,
		"economy_xp": _economy_xp,
		"engineering_xp": _engineering_xp,
		"combat_tier": _combat_tier,
		"economy_tier": _economy_tier,
		"engineering_tier": _engineering_tier,
		"unlocked_buffs": _unlocked_buffs.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_combat_xp = data.get("combat_xp", 0.0)
	_economy_xp = data.get("economy_xp", 0.0)
	_engineering_xp = data.get("engineering_xp", 0.0)
	_combat_tier = data.get("combat_tier", 0)
	_economy_tier = data.get("economy_tier", 0)
	_engineering_tier = data.get("engineering_tier", 0)

	_unlocked_buffs.clear()
	var buffs: Array = data.get("unlocked_buffs", [])
	for buff_id in buffs:
		_unlocked_buffs.append(str(buff_id))

	_effects_dirty = true
	_recalculate_combined_effects()
