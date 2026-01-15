class_name FactionConfig
extends Resource
## FactionConfig holds all configuration data for a faction.
## Loaded from JSON files for data-driven faction management.

## Faction identifiers
@export var faction_id: int = 0
@export var faction_key: String = ""  # e.g., "aether_swarm"
@export var display_name: String = ""
@export var description: String = ""

## Visual settings
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.GRAY
@export var icon_path: String = ""

## Starting resources
@export var starting_resources: Dictionary = {}  # resource_type -> amount

## Unit types available to this faction
@export var unit_types: Array[String] = []

## Abilities available to this faction
@export var abilities: Array[String] = []

## Stat multipliers (applied to all faction units)
@export var unit_speed_multiplier: float = 1.0
@export var unit_health_multiplier: float = 1.0
@export var unit_damage_multiplier: float = 1.0
@export var production_speed_multiplier: float = 1.0
@export var resource_gather_multiplier: float = 1.0
@export var research_speed_multiplier: float = 1.0

## Faction-specific stats
@export var stats: Dictionary = {}

## Experience pools configuration
@export var experience_pools: Dictionary = {}

## Unlocked buffs at start
@export var unlocked_buffs: Array[String] = []

## Faction relationships (faction_id -> relationship)
@export var relationships: Dictionary = {}  # faction_id -> "ally", "enemy", "neutral"

## Special faction flags
@export var is_playable: bool = true
@export var is_ai_only: bool = false
@export var has_hive_mind: bool = false

## Custom data for faction-specific mechanics
@export var custom_data: Dictionary = {}


## Relationship types
enum Relationship {
	NEUTRAL = 0,
	ALLY = 1,
	ENEMY = 2
}


## Create from dictionary (JSON data)
static func from_dict(data: Dictionary) -> FactionConfig:
	var config := FactionConfig.new()

	config.faction_id = data.get("faction_id", 0)
	config.faction_key = data.get("faction_key", "")
	config.display_name = data.get("display_name", "")
	config.description = data.get("description", "")

	# Parse colors
	var primary: Variant = data.get("primary_color", "#FFFFFF")
	if primary is String:
		config.primary_color = Color.html(primary)
	elif primary is Dictionary:
		config.primary_color = Color(primary.get("r", 1), primary.get("g", 1), primary.get("b", 1))

	var secondary: Variant = data.get("secondary_color", "#808080")
	if secondary is String:
		config.secondary_color = Color.html(secondary)
	elif secondary is Dictionary:
		config.secondary_color = Color(secondary.get("r", 0.5), secondary.get("g", 0.5), secondary.get("b", 0.5))

	config.icon_path = data.get("icon_path", "")

	# Resources
	config.starting_resources = data.get("starting_resources", {}).duplicate()

	# Unit types and abilities
	var unit_types_raw = data.get("unit_types", [])
	for ut in unit_types_raw:
		config.unit_types.append(str(ut))

	var abilities_raw = data.get("abilities", [])
	for ab in abilities_raw:
		config.abilities.append(str(ab))

	# Multipliers
	config.unit_speed_multiplier = data.get("unit_speed_multiplier", 1.0)
	config.unit_health_multiplier = data.get("unit_health_multiplier", 1.0)
	config.unit_damage_multiplier = data.get("unit_damage_multiplier", 1.0)
	config.production_speed_multiplier = data.get("production_speed_multiplier", 1.0)
	config.resource_gather_multiplier = data.get("resource_gather_multiplier", 1.0)
	config.research_speed_multiplier = data.get("research_speed_multiplier", 1.0)

	# Other data
	config.stats = data.get("stats", {}).duplicate()
	config.experience_pools = data.get("experience_pools", {}).duplicate()

	var buffs_raw = data.get("unlocked_buffs", [])
	for buff in buffs_raw:
		config.unlocked_buffs.append(str(buff))

	# Relationships
	var rel_data: Dictionary = data.get("relationships", {})
	for key in rel_data:
		config.relationships[int(key)] = rel_data[key]

	# Flags
	config.is_playable = data.get("is_playable", true)
	config.is_ai_only = data.get("is_ai_only", false)
	config.has_hive_mind = data.get("has_hive_mind", false)

	config.custom_data = data.get("custom_data", {}).duplicate()

	return config


## Convert to dictionary for serialization
func to_dict() -> Dictionary:
	return {
		"faction_id": faction_id,
		"faction_key": faction_key,
		"display_name": display_name,
		"description": description,
		"primary_color": "#%s" % primary_color.to_html(false),
		"secondary_color": "#%s" % secondary_color.to_html(false),
		"icon_path": icon_path,
		"starting_resources": starting_resources.duplicate(),
		"unit_types": unit_types.duplicate(),
		"abilities": abilities.duplicate(),
		"unit_speed_multiplier": unit_speed_multiplier,
		"unit_health_multiplier": unit_health_multiplier,
		"unit_damage_multiplier": unit_damage_multiplier,
		"production_speed_multiplier": production_speed_multiplier,
		"resource_gather_multiplier": resource_gather_multiplier,
		"research_speed_multiplier": research_speed_multiplier,
		"stats": stats.duplicate(),
		"experience_pools": experience_pools.duplicate(),
		"unlocked_buffs": unlocked_buffs.duplicate(),
		"relationships": relationships.duplicate(),
		"is_playable": is_playable,
		"is_ai_only": is_ai_only,
		"has_hive_mind": has_hive_mind,
		"custom_data": custom_data.duplicate()
	}


## Get relationship with another faction
func get_relationship(other_faction_id: int) -> int:
	if other_faction_id == faction_id:
		return Relationship.ALLY  # Same faction is ally

	var rel = relationships.get(other_faction_id, "enemy")
	match rel:
		"ally": return Relationship.ALLY
		"enemy": return Relationship.ENEMY
		_: return Relationship.NEUTRAL


## Check if another faction is an enemy
func is_enemy(other_faction_id: int) -> bool:
	return get_relationship(other_faction_id) == Relationship.ENEMY


## Check if another faction is an ally
func is_ally(other_faction_id: int) -> bool:
	return get_relationship(other_faction_id) == Relationship.ALLY


## Apply stat multiplier to a base value
func apply_speed_multiplier(base_speed: float) -> float:
	return base_speed * unit_speed_multiplier


func apply_health_multiplier(base_health: float) -> float:
	return base_health * unit_health_multiplier


func apply_damage_multiplier(base_damage: float) -> float:
	return base_damage * unit_damage_multiplier


func apply_production_multiplier(base_time: float) -> float:
	return base_time / production_speed_multiplier if production_speed_multiplier > 0 else base_time


## Validate configuration
func validate() -> Dictionary:
	var result := {
		"valid": true,
		"errors": [],
		"warnings": []
	}

	# Required fields
	if faction_id <= 0:
		result["errors"].append("faction_id must be positive")
		result["valid"] = false

	if faction_key.is_empty():
		result["errors"].append("faction_key is required")
		result["valid"] = false

	if display_name.is_empty():
		result["errors"].append("display_name is required")
		result["valid"] = false

	# Multiplier ranges
	if unit_speed_multiplier <= 0 or unit_speed_multiplier > 10:
		result["warnings"].append("unit_speed_multiplier %.2f outside typical range (0-10)" % unit_speed_multiplier)

	if unit_health_multiplier <= 0 or unit_health_multiplier > 10:
		result["warnings"].append("unit_health_multiplier %.2f outside typical range (0-10)" % unit_health_multiplier)

	if unit_damage_multiplier <= 0 or unit_damage_multiplier > 10:
		result["warnings"].append("unit_damage_multiplier %.2f outside typical range (0-10)" % unit_damage_multiplier)

	if production_speed_multiplier <= 0:
		result["errors"].append("production_speed_multiplier must be positive")
		result["valid"] = false

	return result
