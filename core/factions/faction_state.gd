class_name FactionState
extends RefCounted
## FactionState tracks runtime state for a faction during gameplay.
## Base class for faction-specific state implementations.

signal experience_gained(pool_name: String, amount: float)
signal buff_unlocked(buff_id: String)
signal level_up(pool_name: String, new_level: int)

## Reference to faction configuration
var config: FactionConfig = null

## Faction ID
var faction_id: int = 0

## Experience pools (pool_name -> current_xp)
var experience_pools: Dictionary = {}

## Experience levels (pool_name -> current_level)
var experience_levels: Dictionary = {}

## Unlocked buffs
var unlocked_buffs: Array[String] = []

## Active buffs with durations (buff_id -> time_remaining)
var active_buffs: Dictionary = {}

## Faction statistics
var stats: Dictionary = {
	"units_created": 0,
	"units_lost": 0,
	"units_killed": 0,
	"resources_gathered": 0.0,
	"resources_spent": 0.0,
	"damage_dealt": 0.0,
	"damage_taken": 0.0,
	"districts_captured": 0,
	"districts_lost": 0,
	"factories_built": 0,
	"factories_destroyed": 0
}

## XP required per level (can be overridden)
var xp_per_level: float = 100.0

## XP scaling per level
var xp_scaling: float = 1.2


func _init(p_config: FactionConfig = null) -> void:
	if p_config != null:
		initialize(p_config)


## Initialize state from configuration
func initialize(p_config: FactionConfig) -> void:
	config = p_config
	faction_id = config.faction_id

	# Initialize experience pools from config
	experience_pools.clear()
	experience_levels.clear()

	for pool_name in config.experience_pools:
		experience_pools[pool_name] = 0.0
		experience_levels[pool_name] = 1

	# Copy starting buffs
	unlocked_buffs = config.unlocked_buffs.duplicate()


## Add experience to a pool
func add_experience(pool_name: String, amount: float) -> void:
	if not experience_pools.has(pool_name):
		experience_pools[pool_name] = 0.0
		experience_levels[pool_name] = 1

	experience_pools[pool_name] += amount
	experience_gained.emit(pool_name, amount)

	# Check for level up
	_check_level_up(pool_name)


## Get experience in a pool
func get_experience(pool_name: String) -> float:
	return experience_pools.get(pool_name, 0.0)


## Get level for a pool
func get_level(pool_name: String) -> int:
	return experience_levels.get(pool_name, 1)


## Get XP required for next level
func get_xp_for_level(level: int) -> float:
	return xp_per_level * pow(xp_scaling, level - 1)


## Get progress to next level (0.0 - 1.0)
func get_level_progress(pool_name: String) -> float:
	var current_xp := get_experience(pool_name)
	var current_level := get_level(pool_name)
	var xp_for_current := get_xp_for_level(current_level)
	var xp_for_next := get_xp_for_level(current_level + 1)

	var xp_in_level := current_xp - xp_for_current
	var xp_needed := xp_for_next - xp_for_current

	if xp_needed <= 0:
		return 1.0

	return clampf(xp_in_level / xp_needed, 0.0, 1.0)


## Check and process level up
func _check_level_up(pool_name: String) -> void:
	var current_xp: float = experience_pools.get(pool_name, 0.0)
	var current_level: int = experience_levels.get(pool_name, 1)
	var xp_for_next := get_xp_for_level(current_level + 1)

	while current_xp >= xp_for_next:
		current_level += 1
		experience_levels[pool_name] = current_level
		level_up.emit(pool_name, current_level)
		_on_level_up(pool_name, current_level)
		xp_for_next = get_xp_for_level(current_level + 1)


## Override in subclasses for level up rewards
func _on_level_up(_pool_name: String, _new_level: int) -> void:
	pass


## Unlock a buff
func unlock_buff(buff_id: String) -> bool:
	if buff_id in unlocked_buffs:
		return false

	unlocked_buffs.append(buff_id)
	buff_unlocked.emit(buff_id)
	return true


## Check if buff is unlocked
func has_buff(buff_id: String) -> bool:
	return buff_id in unlocked_buffs


## Activate a timed buff
func activate_buff(buff_id: String, duration: float) -> void:
	if buff_id in unlocked_buffs:
		active_buffs[buff_id] = duration


## Update active buff timers
func update_buffs(delta: float) -> void:
	var expired: Array[String] = []

	for buff_id in active_buffs:
		active_buffs[buff_id] -= delta
		if active_buffs[buff_id] <= 0:
			expired.append(buff_id)

	for buff_id in expired:
		active_buffs.erase(buff_id)


## Check if buff is currently active
func is_buff_active(buff_id: String) -> bool:
	return active_buffs.has(buff_id) and active_buffs[buff_id] > 0


## Record a statistic
func record_stat(stat_name: String, value: float = 1.0) -> void:
	if stats.has(stat_name):
		stats[stat_name] += value
	else:
		stats[stat_name] = value


## Get a statistic value
func get_stat(stat_name: String) -> float:
	return stats.get(stat_name, 0.0)


## Apply faction multipliers to base stats
func apply_multipliers(base_stats: Dictionary) -> Dictionary:
	var result := base_stats.duplicate()

	if config != null:
		if result.has("speed"):
			result["speed"] *= config.unit_speed_multiplier
		if result.has("max_speed"):
			result["max_speed"] *= config.unit_speed_multiplier
		if result.has("health"):
			result["health"] *= config.unit_health_multiplier
		if result.has("max_health"):
			result["max_health"] *= config.unit_health_multiplier
		if result.has("damage"):
			result["damage"] *= config.unit_damage_multiplier
		if result.has("base_damage"):
			result["base_damage"] *= config.unit_damage_multiplier

	return result


## Serialize state for saving
func to_dict() -> Dictionary:
	return {
		"faction_id": faction_id,
		"experience_pools": experience_pools.duplicate(),
		"experience_levels": experience_levels.duplicate(),
		"unlocked_buffs": unlocked_buffs.duplicate(),
		"active_buffs": active_buffs.duplicate(),
		"stats": stats.duplicate()
	}


## Deserialize state from save data
func from_dict(data: Dictionary) -> void:
	faction_id = data.get("faction_id", faction_id)
	experience_pools = data.get("experience_pools", {}).duplicate()
	experience_levels = data.get("experience_levels", {}).duplicate()

	unlocked_buffs.clear()
	for buff in data.get("unlocked_buffs", []):
		unlocked_buffs.append(str(buff))

	active_buffs = data.get("active_buffs", {}).duplicate()
	stats = data.get("stats", stats).duplicate()
