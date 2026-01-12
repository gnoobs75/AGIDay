class_name Technology
extends Resource
## Technology defines a researchable tech in the technology tree.
## Technologies can have prerequisites, unlock abilities/units, and provide buffs.

## Technology tier levels
enum Tier {
	TIER_1 = 1,
	TIER_2 = 2,
	TIER_3 = 3
}

## Unique technology identifier
@export var tech_id: String = ""

## Faction this technology belongs to (0 for shared techs)
@export var faction_id: int = 0

## Display name for UI
@export var display_name: String = ""

## Description of what this technology does
@export var description: String = ""

## Research cost
@export var research_points_cost: float = 100.0
@export var research_time: float = 60.0  # Seconds with one facility

## Prerequisites (tech_ids that must be completed first)
@export var prerequisites: Array[String] = []

## What this technology unlocks
@export var unlocks: Dictionary = {
	"units": [],      # Unit type IDs
	"buildings": [],  # Building type IDs
	"abilities": [],  # Ability IDs
	"upgrades": []    # Upgrade IDs
}

## Buffs applied when this technology is completed
@export var buffs: Array[Dictionary] = []  # [{buff_type, value, target}]

## Technology tier (determines placement in tree)
@export var tier: int = Tier.TIER_1

## Whether this tech is available (can be hidden until conditions met)
@export var is_available: bool = true


func _init() -> void:
	pass


## Create technology from dictionary.
static func from_dict(data: Dictionary) -> Technology:
	var tech := Technology.new()
	tech.tech_id = data.get("tech_id", "")
	tech.faction_id = data.get("faction_id", 0)
	tech.display_name = data.get("display_name", "")
	tech.description = data.get("description", "")
	tech.research_points_cost = data.get("research_points_cost", data.get("research_cost", {}).get("research_points", 100.0))
	tech.research_time = data.get("research_time", data.get("research_cost", {}).get("time", 60.0))

	var prereqs = data.get("prerequisites", [])
	tech.prerequisites.clear()
	for prereq in prereqs:
		tech.prerequisites.append(str(prereq))

	tech.unlocks = data.get("unlocks", {})
	if tech.unlocks.is_empty():
		tech.unlocks = {"units": [], "buildings": [], "abilities": [], "upgrades": []}

	var buffs_data = data.get("buffs", [])
	tech.buffs.clear()
	for buff in buffs_data:
		tech.buffs.append(buff)

	tech.tier = data.get("tier", Tier.TIER_1)
	tech.is_available = data.get("is_available", true)

	return tech


## Convert to dictionary.
func to_dict() -> Dictionary:
	return {
		"tech_id": tech_id,
		"faction_id": faction_id,
		"display_name": display_name,
		"description": description,
		"research_points_cost": research_points_cost,
		"research_time": research_time,
		"prerequisites": prerequisites.duplicate(),
		"unlocks": unlocks.duplicate(true),
		"buffs": buffs.duplicate(true),
		"tier": tier,
		"is_available": is_available
	}


## Check if all prerequisites are in the completed list.
func can_research(completed_techs: Array[String]) -> bool:
	if not is_available:
		return false

	for prereq in prerequisites:
		if prereq not in completed_techs:
			return false

	return true


## Get missing prerequisites.
func get_missing_prerequisites(completed_techs: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for prereq in prerequisites:
		if prereq not in completed_techs:
			missing.append(prereq)
	return missing


## Check if tech has any unlocks.
func has_unlocks() -> bool:
	for category in unlocks:
		if not unlocks[category].is_empty():
			return true
	return false


## Check if tech provides buffs.
func has_buffs() -> bool:
	return not buffs.is_empty()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"tech_id": tech_id,
		"display_name": display_name,
		"tier": tier,
		"cost": research_points_cost,
		"time": research_time,
		"prerequisites_count": prerequisites.size(),
		"has_unlocks": has_unlocks(),
		"has_buffs": has_buffs()
	}
