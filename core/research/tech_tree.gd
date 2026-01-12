class_name TechTree
extends RefCounted
## TechTree manages branching technology progression for factions.

signal tier_unlocked(faction_id: String, tier: int)
signal tech_available(faction_id: String, tech_id: String)
signal tech_research_started(faction_id: String, tech_id: String)
signal tech_research_completed(faction_id: String, tech_id: String)
signal tech_research_cancelled(faction_id: String, tech_id: String, refund: Dictionary)
signal unit_type_unlocked(faction_id: String, unit_type: String)
signal capability_unlocked(faction_id: String, capability_id: String)

## Tier unlock times (in seconds)
const TIER_1_UNLOCK_TIME := 0.0      ## Available at start
const TIER_2_UNLOCK_TIME := 300.0    ## 5 minutes
const TIER_3_UNLOCK_TIME := 900.0    ## 15 minutes

## Tiers
enum Tier {
	TIER_1 = 1,
	TIER_2 = 2,
	TIER_3 = 3
}

## Technology data class
class Technology:
	var tech_id: String = ""
	var tech_name: String = ""
	var tier: int = Tier.TIER_1
	var research_time: float = 60.0  ## Seconds
	var resource_cost: Dictionary = {}  ## {"ree": 100, "energy": 50}
	var prerequisites: Array[String] = []
	var unlocks_units: Array[String] = []
	var unlocks_capabilities: Array[String] = []
	var unlock_bonuses: Dictionary = {}  ## {"harvester_efficiency": 1.25}

	func to_dict() -> Dictionary:
		return {
			"tech_id": tech_id,
			"tech_name": tech_name,
			"tier": tier,
			"research_time": research_time,
			"resource_cost": resource_cost.duplicate(),
			"prerequisites": prerequisites.duplicate(),
			"unlocks_units": unlocks_units.duplicate(),
			"unlocks_capabilities": unlocks_capabilities.duplicate(),
			"unlock_bonuses": unlock_bonuses.duplicate()
		}

	static func from_dict(data: Dictionary) -> Technology:
		var tech := Technology.new()
		tech.tech_id = data.get("tech_id", "")
		tech.tech_name = data.get("tech_name", "")
		tech.tier = data.get("tier", Tier.TIER_1)
		tech.research_time = data.get("research_time", 60.0)
		tech.resource_cost = data.get("resource_cost", {}).duplicate()
		for prereq in data.get("prerequisites", []):
			tech.prerequisites.append(prereq)
		for unit in data.get("unlocks_units", []):
			tech.unlocks_units.append(unit)
		for cap in data.get("unlocks_capabilities", []):
			tech.unlocks_capabilities.append(cap)
		tech.unlock_bonuses = data.get("unlock_bonuses", {}).duplicate()
		return tech


## All technologies (tech_id -> Technology)
var _technologies: Dictionary = {}

## Technologies by tier (tier -> Array[String])
var _tier_techs: Dictionary = {}

## Faction states (faction_id -> faction_state)
var _faction_states: Dictionary = {}

## Game time reference
var _game_time: float = 0.0

## Cancel refund percentage
const CANCEL_REFUND_PERCENT := 0.5


func _init() -> void:
	_tier_techs[Tier.TIER_1] = []
	_tier_techs[Tier.TIER_2] = []
	_tier_techs[Tier.TIER_3] = []

	_register_default_technologies()


## Register default technology tree.
func _register_default_technologies() -> void:
	# Tier 1 - Available at start
	_register_tech("basic_combat", "Basic Combat Training", Tier.TIER_1, 60.0,
		{"ree": 100}, [], ["nano_reaplet", "spikelet"], [], {})

	_register_tech("basic_harvesting", "Basic Harvesting", Tier.TIER_1, 45.0,
		{"ree": 75}, [], [], ["basic_harvester"], {"harvester_speed": 1.1})

	_register_tech("basic_defense", "Basic Defenses", Tier.TIER_1, 90.0,
		{"ree": 150}, [], [], ["basic_turret"], {})

	# Tier 2 - Available at 5 minutes
	_register_tech("advanced_combat", "Advanced Combat", Tier.TIER_2, 120.0,
		{"ree": 250}, ["basic_combat"], ["buzzblade", "shardling"], [], {"damage_bonus": 1.15})

	_register_tech("harvester_upgrade", "Harvester Upgrade", Tier.TIER_2, 90.0,
		{"ree": 200}, ["basic_harvesting"], ["elite_harvester"], [], {"harvester_efficiency": 1.25})

	_register_tech("advanced_defense", "Advanced Defenses", Tier.TIER_2, 150.0,
		{"ree": 300}, ["basic_defense"], [], ["advanced_turret", "shield_generator"], {})

	# Tier 3 - Available at 15 minutes
	_register_tech("elite_units", "Elite Units", Tier.TIER_3, 180.0,
		{"ree": 500}, ["advanced_combat"], ["wispfire", "elite_warrior"], [], {"elite_damage": 1.3})

	_register_tech("super_harvester", "Super Harvester", Tier.TIER_3, 120.0,
		{"ree": 400}, ["harvester_upgrade"], ["super_harvester"], [], {"harvester_efficiency": 1.5})

	_register_tech("ultimate_defense", "Ultimate Defense", Tier.TIER_3, 240.0,
		{"ree": 600}, ["advanced_defense"], [], ["ultimate_turret"], {"defense_bonus": 1.5})


## Register a technology.
func _register_tech(tech_id: String, name: String, tier: int, time: float,
		cost: Dictionary, prereqs: Array, units: Array, capabilities: Array, bonuses: Dictionary) -> void:
	var tech := Technology.new()
	tech.tech_id = tech_id
	tech.tech_name = name
	tech.tier = tier
	tech.research_time = time
	tech.resource_cost = cost

	for prereq in prereqs:
		tech.prerequisites.append(prereq)
	for unit in units:
		tech.unlocks_units.append(unit)
	for cap in capabilities:
		tech.unlocks_capabilities.append(cap)
	tech.unlock_bonuses = bonuses

	_technologies[tech_id] = tech
	_tier_techs[tier].append(tech_id)


## Get technology by ID.
func get_technology(tech_id: String) -> Technology:
	return _technologies.get(tech_id)


## Get technologies in tier.
func get_tier_technologies(tier: int) -> Array[Technology]:
	var techs: Array[Technology] = []
	for tech_id in _tier_techs.get(tier, []):
		var tech: Technology = _technologies.get(tech_id)
		if tech != null:
			techs.append(tech)
	return techs


# ============================================
# FACTION STATE
# ============================================

## Initialize faction state.
func init_faction(faction_id: String) -> void:
	if _faction_states.has(faction_id):
		return

	_faction_states[faction_id] = {
		"unlocked_tiers": [Tier.TIER_1],
		"current_research": "",
		"research_progress": 0.0,
		"completed_techs": [],
		"unlocked_units": [],
		"unlocked_capabilities": [],
		"active_bonuses": {}
	}

	# Emit tier 1 available
	for tech_id in _tier_techs[Tier.TIER_1]:
		tech_available.emit(faction_id, tech_id)


## Get faction state.
func get_faction_state(faction_id: String) -> Dictionary:
	return _faction_states.get(faction_id, {})


## Check if tier is unlocked for faction.
func is_tier_unlocked(faction_id: String, tier: int) -> bool:
	var state: Dictionary = _faction_states.get(faction_id, {})
	return state.get("unlocked_tiers", []).has(tier)


## Get available technologies for faction.
func get_available_technologies(faction_id: String) -> Array[Technology]:
	var state: Dictionary = _faction_states.get(faction_id, {})
	if state.is_empty():
		return []

	var completed: Array = state.get("completed_techs", [])
	var unlocked_tiers: Array = state.get("unlocked_tiers", [])
	var available: Array[Technology] = []

	for tech_id in _technologies:
		var tech: Technology = _technologies[tech_id]

		# Skip if already completed
		if completed.has(tech_id):
			continue

		# Skip if tier not unlocked
		if not unlocked_tiers.has(tech.tier):
			continue

		# Check prerequisites
		var prereqs_met := true
		for prereq in tech.prerequisites:
			if not completed.has(prereq):
				prereqs_met = false
				break

		if prereqs_met:
			available.append(tech)

	return available


# ============================================
# RESEARCH MANAGEMENT
# ============================================

## Start researching a technology.
func start_research(faction_id: String, tech_id: String, deduct_resources_callback: Callable) -> bool:
	init_faction(faction_id)

	var state: Dictionary = _faction_states[faction_id]

	# Check if already researching
	if not state["current_research"].is_empty():
		return false

	var tech := get_technology(tech_id)
	if tech == null:
		return false

	# Check if available
	var available := get_available_technologies(faction_id)
	var is_available := false
	for avail_tech in available:
		if avail_tech.tech_id == tech_id:
			is_available = true
			break

	if not is_available:
		return false

	# Deduct resources
	if deduct_resources_callback.is_valid():
		if not deduct_resources_callback.call(faction_id, tech.resource_cost):
			return false

	state["current_research"] = tech_id
	state["research_progress"] = 0.0

	tech_research_started.emit(faction_id, tech_id)
	return true


## Cancel current research.
func cancel_research(faction_id: String, refund_resources_callback: Callable) -> Dictionary:
	var state: Dictionary = _faction_states.get(faction_id, {})
	if state.is_empty():
		return {}

	var tech_id: String = state.get("current_research", "")
	if tech_id.is_empty():
		return {}

	var tech := get_technology(tech_id)
	if tech == null:
		return {}

	# Calculate refund
	var refund: Dictionary = {}
	for resource in tech.resource_cost:
		refund[resource] = tech.resource_cost[resource] * CANCEL_REFUND_PERCENT

	# Apply refund
	if refund_resources_callback.is_valid():
		refund_resources_callback.call(faction_id, refund)

	state["current_research"] = ""
	state["research_progress"] = 0.0

	tech_research_cancelled.emit(faction_id, tech_id, refund)

	return refund


## Update research progress (call each frame).
func update(delta: float) -> void:
	_game_time += delta

	# Check tier unlocks
	_check_tier_unlocks()

	# Update faction research
	for faction_id in _faction_states:
		_update_faction_research(faction_id, delta)


## Check and unlock new tiers.
func _check_tier_unlocks() -> void:
	for faction_id in _faction_states:
		var state: Dictionary = _faction_states[faction_id]
		var unlocked: Array = state["unlocked_tiers"]

		# Check Tier 2
		if not unlocked.has(Tier.TIER_2) and _game_time >= TIER_2_UNLOCK_TIME:
			unlocked.append(Tier.TIER_2)
			tier_unlocked.emit(faction_id, Tier.TIER_2)

			for tech_id in _tier_techs[Tier.TIER_2]:
				tech_available.emit(faction_id, tech_id)

		# Check Tier 3
		if not unlocked.has(Tier.TIER_3) and _game_time >= TIER_3_UNLOCK_TIME:
			unlocked.append(Tier.TIER_3)
			tier_unlocked.emit(faction_id, Tier.TIER_3)

			for tech_id in _tier_techs[Tier.TIER_3]:
				tech_available.emit(faction_id, tech_id)


## Update research for a faction.
func _update_faction_research(faction_id: String, delta: float) -> void:
	var state: Dictionary = _faction_states[faction_id]
	var tech_id: String = state.get("current_research", "")

	if tech_id.is_empty():
		return

	var tech := get_technology(tech_id)
	if tech == null:
		return

	state["research_progress"] += delta

	if state["research_progress"] >= tech.research_time:
		_complete_research(faction_id, tech)


## Complete research.
func _complete_research(faction_id: String, tech: Technology) -> void:
	var state: Dictionary = _faction_states[faction_id]

	# Add to completed
	state["completed_techs"].append(tech.tech_id)

	# Unlock units
	for unit_type in tech.unlocks_units:
		if not state["unlocked_units"].has(unit_type):
			state["unlocked_units"].append(unit_type)
			unit_type_unlocked.emit(faction_id, unit_type)

	# Unlock capabilities
	for capability in tech.unlocks_capabilities:
		if not state["unlocked_capabilities"].has(capability):
			state["unlocked_capabilities"].append(capability)
			capability_unlocked.emit(faction_id, capability)

	# Apply bonuses
	for bonus_id in tech.unlock_bonuses:
		state["active_bonuses"][bonus_id] = tech.unlock_bonuses[bonus_id]

	# Clear current research
	state["current_research"] = ""
	state["research_progress"] = 0.0

	tech_research_completed.emit(faction_id, tech.tech_id)


# ============================================
# QUERIES
# ============================================

## Get current research for faction.
func get_current_research(faction_id: String) -> String:
	return _faction_states.get(faction_id, {}).get("current_research", "")


## Get research progress (0.0 to 1.0).
func get_research_progress(faction_id: String) -> float:
	var state: Dictionary = _faction_states.get(faction_id, {})
	var tech_id: String = state.get("current_research", "")
	if tech_id.is_empty():
		return 0.0

	var tech := get_technology(tech_id)
	if tech == null:
		return 0.0

	var progress: float = state.get("research_progress", 0.0)
	return minf(progress / tech.research_time, 1.0)


## Get completed technologies.
func get_completed_technologies(faction_id: String) -> Array:
	return _faction_states.get(faction_id, {}).get("completed_techs", [])


## Check if technology is completed.
func is_technology_completed(faction_id: String, tech_id: String) -> bool:
	return get_completed_technologies(faction_id).has(tech_id)


## Get unlocked units.
func get_unlocked_units(faction_id: String) -> Array:
	return _faction_states.get(faction_id, {}).get("unlocked_units", [])


## Check if unit is unlocked.
func is_unit_unlocked(faction_id: String, unit_type: String) -> bool:
	return get_unlocked_units(faction_id).has(unit_type)


## Get active bonuses.
func get_active_bonuses(faction_id: String) -> Dictionary:
	return _faction_states.get(faction_id, {}).get("active_bonuses", {})


## Get specific bonus value.
func get_bonus_value(faction_id: String, bonus_id: String, default: float = 1.0) -> float:
	return get_active_bonuses(faction_id).get(bonus_id, default)


# ============================================
# SERIALIZATION
# ============================================

func to_dict() -> Dictionary:
	var techs_data: Dictionary = {}
	for tech_id in _technologies:
		techs_data[tech_id] = _technologies[tech_id].to_dict()

	return {
		"technologies": techs_data,
		"faction_states": _faction_states.duplicate(true),
		"game_time": _game_time
	}


func from_dict(data: Dictionary) -> void:
	# Load technologies
	_technologies.clear()
	_tier_techs[Tier.TIER_1] = []
	_tier_techs[Tier.TIER_2] = []
	_tier_techs[Tier.TIER_3] = []

	var techs_data: Dictionary = data.get("technologies", {})
	for tech_id in techs_data:
		var tech := Technology.from_dict(techs_data[tech_id])
		_technologies[tech_id] = tech
		_tier_techs[tech.tier].append(tech_id)

	# Load faction states
	_faction_states = data.get("faction_states", {}).duplicate(true)

	_game_time = data.get("game_time", 0.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var tier_counts: Dictionary = {}
	for tier in [Tier.TIER_1, Tier.TIER_2, Tier.TIER_3]:
		tier_counts["tier_%d" % tier] = _tier_techs[tier].size()

	return {
		"total_technologies": _technologies.size(),
		"tier_counts": tier_counts,
		"factions": _faction_states.size(),
		"game_time": _game_time,
		"tier_2_unlocked": _game_time >= TIER_2_UNLOCK_TIME,
		"tier_3_unlocked": _game_time >= TIER_3_UNLOCK_TIME
	}
