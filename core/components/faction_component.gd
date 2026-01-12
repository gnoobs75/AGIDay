class_name FactionComponent
extends Component
## FactionComponent identifies which faction an entity belongs to.

const COMPONENT_TYPE := "FactionComponent"

## Faction IDs matching game factions
enum Faction {
	NONE = 0,
	AETHER_SWARM = 1,
	OPTIFORGE_LEGION = 2,
	DYNAPODS_VANGUARD = 3,
	LOGIBOTS_COLOSSUS = 4,
	HUMAN_REMNANT = 5
}


func _init() -> void:
	component_type = COMPONENT_TYPE
	version = 1
	data = {
		"faction_id": Faction.NONE,
		"faction_name": "None",
		"is_player_controlled": false,
		"ally_faction_ids": [],
		"enemy_faction_ids": []
	}


## Get the component schema for validation.
static func get_schema() -> ComponentSchema:
	var schema := ComponentSchema.new(COMPONENT_TYPE)

	schema.int_field("faction_id").set_range(0, 5).set_default(0)
	schema.string_field("faction_name").set_default("None")
	schema.bool_field("is_player_controlled").set_default(false)
	schema.array_field("ally_faction_ids").set_default([])
	schema.array_field("enemy_faction_ids").set_default([])

	return schema


## Set faction.
func set_faction(faction: Faction) -> void:
	data["faction_id"] = faction
	data["faction_name"] = get_faction_name_for_id(faction)
	_setup_default_relations(faction)


## Get faction ID.
func get_faction_id() -> int:
	return data.get("faction_id", Faction.NONE)


## Get faction name.
func get_faction_name() -> String:
	return data.get("faction_name", "None")


## Check if player controlled.
func is_player_controlled() -> bool:
	return data.get("is_player_controlled", false)


## Set player controlled.
func set_player_controlled(controlled: bool) -> void:
	data["is_player_controlled"] = controlled


## Check if another faction is an ally.
func is_ally(other_faction_id: int) -> bool:
	if other_faction_id == get_faction_id():
		return true  # Same faction is ally
	var allies: Array = data.get("ally_faction_ids", [])
	return other_faction_id in allies


## Check if another faction is an enemy.
func is_enemy(other_faction_id: int) -> bool:
	var enemies: Array = data.get("enemy_faction_ids", [])
	return other_faction_id in enemies


## Get faction name from ID.
static func get_faction_name_for_id(faction: Faction) -> String:
	match faction:
		Faction.NONE: return "None"
		Faction.AETHER_SWARM: return "Aether Swarm"
		Faction.OPTIFORGE_LEGION: return "OptiForge Legion"
		Faction.DYNAPODS_VANGUARD: return "Dynapods Vanguard"
		Faction.LOGIBOTS_COLOSSUS: return "LogiBots Colossus"
		Faction.HUMAN_REMNANT: return "Human Remnant"
		_: return "Unknown"


## Setup default faction relations.
func _setup_default_relations(faction: Faction) -> void:
	# Human Remnant is enemy to all robot factions
	# Robot factions are enemies to each other
	match faction:
		Faction.AETHER_SWARM:
			data["enemy_faction_ids"] = [
				Faction.OPTIFORGE_LEGION,
				Faction.DYNAPODS_VANGUARD,
				Faction.LOGIBOTS_COLOSSUS,
				Faction.HUMAN_REMNANT
			]
		Faction.OPTIFORGE_LEGION:
			data["enemy_faction_ids"] = [
				Faction.AETHER_SWARM,
				Faction.DYNAPODS_VANGUARD,
				Faction.LOGIBOTS_COLOSSUS,
				Faction.HUMAN_REMNANT
			]
		Faction.DYNAPODS_VANGUARD:
			data["enemy_faction_ids"] = [
				Faction.AETHER_SWARM,
				Faction.OPTIFORGE_LEGION,
				Faction.LOGIBOTS_COLOSSUS,
				Faction.HUMAN_REMNANT
			]
		Faction.LOGIBOTS_COLOSSUS:
			data["enemy_faction_ids"] = [
				Faction.AETHER_SWARM,
				Faction.OPTIFORGE_LEGION,
				Faction.DYNAPODS_VANGUARD,
				Faction.HUMAN_REMNANT
			]
		Faction.HUMAN_REMNANT:
			data["enemy_faction_ids"] = [
				Faction.AETHER_SWARM,
				Faction.OPTIFORGE_LEGION,
				Faction.DYNAPODS_VANGUARD,
				Faction.LOGIBOTS_COLOSSUS
			]
