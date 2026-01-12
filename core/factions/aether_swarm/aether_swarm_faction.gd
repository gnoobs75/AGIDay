class_name AetherSwarmFaction
extends FactionState
## AetherSwarmFaction implements the Aether Swarm faction's core mechanics.
## Swift autonomous drones with nanite-based abilities and hive mind coordination.

signal swarm_bonus_updated(bonus_multiplier: float)
signal hive_connection_changed(connected_units: int)
signal nanite_pool_changed(current: float, max_amount: float)

## Faction constants
const FACTION_ID := 1
const FACTION_KEY := "aether_swarm"
const DISPLAY_NAME := "Aether Swarm"

## Stat multipliers (as per spec: 1.5x speed, 0.6x health, 0.8x damage, 1.2x production)
const SPEED_MULTIPLIER := 1.5
const HEALTH_MULTIPLIER := 0.6
const DAMAGE_MULTIPLIER := 0.8
const PRODUCTION_MULTIPLIER := 1.2

## Experience pool names
const XP_POOL_COMBAT := "combat_experience"
const XP_POOL_ECONOMY := "economy_experience"
const XP_POOL_ENGINEERING := "engineering_experience"

## Swarm mechanics
var hive_connected_units: int = 0
var swarm_bonus_threshold: int = 10  # Units needed for swarm bonus
var max_swarm_bonus: float = 0.5  # Maximum +50% bonus at full swarm

## Nanite pool (shared resource for abilities)
var nanite_pool: float = 0.0
var nanite_pool_max: float = 100.0
var nanite_regen_rate: float = 5.0  # Per second

## Hive mind range for bonuses
var hive_mind_range: float = 50.0

## Colors
var primary_color := Color(0.0, 0.8, 1.0)  # Cyan
var secondary_color := Color(0.0, 0.4, 0.8)  # Blue


func _init(p_config: FactionConfig = null) -> void:
	super._init(p_config)

	# Set up experience pools if not already defined
	if experience_pools.is_empty():
		experience_pools[XP_POOL_COMBAT] = 0.0
		experience_pools[XP_POOL_ECONOMY] = 0.0
		experience_pools[XP_POOL_ENGINEERING] = 0.0
		experience_levels[XP_POOL_COMBAT] = 1
		experience_levels[XP_POOL_ECONOMY] = 1
		experience_levels[XP_POOL_ENGINEERING] = 1


## Initialize with default Aether Swarm configuration
func initialize_default() -> void:
	var default_config := _create_default_config()
	initialize(default_config)


func _create_default_config() -> FactionConfig:
	var cfg := FactionConfig.new()
	cfg.faction_id = FACTION_ID
	cfg.faction_key = FACTION_KEY
	cfg.display_name = DISPLAY_NAME
	cfg.description = "Swift autonomous drones with nanite-based abilities. Masters of speed and swarm tactics."
	cfg.primary_color = primary_color
	cfg.secondary_color = secondary_color
	cfg.unit_speed_multiplier = SPEED_MULTIPLIER
	cfg.unit_health_multiplier = HEALTH_MULTIPLIER
	cfg.unit_damage_multiplier = DAMAGE_MULTIPLIER
	cfg.production_speed_multiplier = PRODUCTION_MULTIPLIER
	cfg.has_hive_mind = true
	cfg.is_playable = true
	cfg.starting_resources = {"ree": 500, "energy": 100}
	cfg.unit_types = ["drone", "swarmling", "nanite_cloud", "hive_node"]
	cfg.abilities = ["nanite_repair", "swarm_surge", "phase_shift", "spiral_rally"]
	cfg.experience_pools = {
		XP_POOL_COMBAT: {"base_xp": 100, "scaling": 1.15},
		XP_POOL_ECONOMY: {"base_xp": 80, "scaling": 1.1},
		XP_POOL_ENGINEERING: {"base_xp": 120, "scaling": 1.2}
	}

	# Enemy to all other factions
	cfg.relationships = {2: "enemy", 3: "enemy", 4: "enemy", 5: "enemy"}

	return cfg


## Update hive connection count
func update_hive_connection(unit_count: int) -> void:
	var previous := hive_connected_units
	hive_connected_units = unit_count

	if previous != unit_count:
		hive_connection_changed.emit(unit_count)
		_update_swarm_bonus()


## Calculate current swarm bonus multiplier
func get_swarm_bonus() -> float:
	if hive_connected_units < swarm_bonus_threshold:
		return 0.0

	var excess_units := hive_connected_units - swarm_bonus_threshold
	var bonus := minf(float(excess_units) / 100.0, max_swarm_bonus)
	return bonus


## Update and emit swarm bonus
func _update_swarm_bonus() -> void:
	var bonus := get_swarm_bonus()
	swarm_bonus_updated.emit(bonus)


## Update nanite pool
func update_nanite_pool(delta: float) -> void:
	var old_value := nanite_pool
	nanite_pool = minf(nanite_pool + nanite_regen_rate * delta, nanite_pool_max)

	if nanite_pool != old_value:
		nanite_pool_changed.emit(nanite_pool, nanite_pool_max)


## Consume nanites for ability
func consume_nanites(amount: float) -> bool:
	if nanite_pool >= amount:
		nanite_pool -= amount
		nanite_pool_changed.emit(nanite_pool, nanite_pool_max)
		return true
	return false


## Get nanite pool percentage
func get_nanite_percentage() -> float:
	if nanite_pool_max <= 0:
		return 0.0
	return nanite_pool / nanite_pool_max


## Apply Aether Swarm specific stat modifications
func apply_aether_multipliers(base_stats: Dictionary) -> Dictionary:
	var result := apply_multipliers(base_stats)

	# Apply swarm bonus to damage
	var swarm_bonus := get_swarm_bonus()
	if swarm_bonus > 0 and result.has("damage"):
		result["damage"] *= (1.0 + swarm_bonus)
	if swarm_bonus > 0 and result.has("base_damage"):
		result["base_damage"] *= (1.0 + swarm_bonus)

	return result


## Override level up for Aether Swarm specific rewards
func _on_level_up(pool_name: String, new_level: int) -> void:
	match pool_name:
		XP_POOL_COMBAT:
			# Combat levels increase swarm efficiency
			max_swarm_bonus += 0.05
			print("AetherSwarm: Combat level %d - Swarm bonus cap increased to %.0f%%" % [new_level, max_swarm_bonus * 100])

		XP_POOL_ECONOMY:
			# Economy levels increase nanite regeneration
			nanite_regen_rate += 0.5
			print("AetherSwarm: Economy level %d - Nanite regen increased to %.1f/s" % [new_level, nanite_regen_rate])

		XP_POOL_ENGINEERING:
			# Engineering levels increase nanite pool
			nanite_pool_max += 10.0
			print("AetherSwarm: Engineering level %d - Nanite pool increased to %.0f" % [new_level, nanite_pool_max])


## Serialize Aether Swarm specific state
func to_dict() -> Dictionary:
	var base := super.to_dict()

	base["aether_swarm"] = {
		"hive_connected_units": hive_connected_units,
		"swarm_bonus_threshold": swarm_bonus_threshold,
		"max_swarm_bonus": max_swarm_bonus,
		"nanite_pool": nanite_pool,
		"nanite_pool_max": nanite_pool_max,
		"nanite_regen_rate": nanite_regen_rate,
		"hive_mind_range": hive_mind_range
	}

	return base


## Deserialize Aether Swarm specific state
func from_dict(data: Dictionary) -> void:
	super.from_dict(data)

	var aether_data: Dictionary = data.get("aether_swarm", {})
	hive_connected_units = aether_data.get("hive_connected_units", 0)
	swarm_bonus_threshold = aether_data.get("swarm_bonus_threshold", 10)
	max_swarm_bonus = aether_data.get("max_swarm_bonus", 0.5)
	nanite_pool = aether_data.get("nanite_pool", 0.0)
	nanite_pool_max = aether_data.get("nanite_pool_max", 100.0)
	nanite_regen_rate = aether_data.get("nanite_regen_rate", 5.0)
	hive_mind_range = aether_data.get("hive_mind_range", 50.0)


## Get combat experience
func get_combat_xp() -> float:
	return get_experience(XP_POOL_COMBAT)


## Get economy experience
func get_economy_xp() -> float:
	return get_experience(XP_POOL_ECONOMY)


## Get engineering experience
func get_engineering_xp() -> float:
	return get_experience(XP_POOL_ENGINEERING)


## Add combat experience
func add_combat_xp(amount: float) -> void:
	add_experience(XP_POOL_COMBAT, amount)


## Add economy experience
func add_economy_xp(amount: float) -> void:
	add_experience(XP_POOL_ECONOMY, amount)


## Add engineering experience
func add_engineering_xp(amount: float) -> void:
	add_experience(XP_POOL_ENGINEERING, amount)


## Get faction summary for UI
func get_summary() -> Dictionary:
	return {
		"faction_id": FACTION_ID,
		"faction_key": FACTION_KEY,
		"display_name": DISPLAY_NAME,
		"primary_color": primary_color,
		"secondary_color": secondary_color,
		"hive_connected": hive_connected_units,
		"swarm_bonus": get_swarm_bonus(),
		"nanite_pool": nanite_pool,
		"nanite_pool_max": nanite_pool_max,
		"combat_level": get_level(XP_POOL_COMBAT),
		"economy_level": get_level(XP_POOL_ECONOMY),
		"engineering_level": get_level(XP_POOL_ENGINEERING),
		"unlocked_buffs_count": unlocked_buffs.size()
	}
