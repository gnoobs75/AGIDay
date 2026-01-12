class_name AbilityConfig
extends RefCounted
## AbilityConfig defines configuration for a faction ability.

## Ability types
enum AbilityType {
	INSTANT = 0,     ## Immediate effect
	TARGETED = 1,    ## Requires target selection
	CHANNELED = 2,   ## Continuous effect over time
	FORMATION = 3,   ## Formation command
	GLOBAL = 4       ## Affects entire faction
}

## Target types
enum TargetType {
	NONE = 0,        ## No target needed
	UNIT = 1,        ## Single unit target
	POSITION = 2,    ## World position
	AREA = 3,        ## Area selection
	UNITS = 4        ## Multiple units
}

## Ability identifier
var ability_id: String = ""

## Faction that owns this ability
var faction_id: String = ""

## Display name
var display_name: String = ""

## Description
var description: String = ""

## Hotkey binding
var hotkey: String = ""

## Ability type
var ability_type: int = AbilityType.INSTANT

## Target type
var target_type: int = TargetType.NONE

## Cooldown duration (seconds)
var cooldown: float = 10.0

## Resource costs
var resource_cost: Dictionary = {
	"ree": 0.0,
	"power": 0.0
}

## Prerequisites (required unlocks)
var prerequisites: Array[String] = []

## Channel duration (for CHANNELED type)
var channel_duration: float = 0.0

## Execution parameters
var execution_params: Dictionary = {}

## Feedback configuration
var feedback: Dictionary = {
	"visual_effect": "",
	"sound_effect": "",
	"ui_notification": ""
}

## Is enabled
var is_enabled: bool = true


func _init() -> void:
	pass


## Load from dictionary (JSON).
static func from_dict(data: Dictionary) -> AbilityConfig:
	var config := AbilityConfig.new()

	config.ability_id = data.get("ability_id", "")
	config.faction_id = data.get("faction_id", "")
	config.display_name = data.get("display_name", config.ability_id)
	config.description = data.get("description", "")
	config.hotkey = data.get("hotkey", "")

	# Parse ability type
	var type_str: String = data.get("ability_type", "instant")
	config.ability_type = _parse_ability_type(type_str)

	# Parse target type
	var target_str: String = data.get("target_type", "none")
	config.target_type = _parse_target_type(target_str)

	config.cooldown = data.get("cooldown", 10.0)

	# Resource costs
	var costs: Dictionary = data.get("resource_cost", {})
	config.resource_cost["ree"] = costs.get("ree", 0.0)
	config.resource_cost["power"] = costs.get("power", 0.0)

	# Prerequisites
	config.prerequisites.clear()
	for prereq in data.get("prerequisites", []):
		config.prerequisites.append(prereq)

	config.channel_duration = data.get("channel_duration", 0.0)
	config.execution_params = data.get("execution", {}).duplicate(true)
	config.feedback = data.get("feedback", config.feedback).duplicate(true)
	config.is_enabled = data.get("is_enabled", true)

	return config


## Parse ability type string.
static func _parse_ability_type(type_str: String) -> int:
	match type_str.to_lower():
		"instant": return AbilityType.INSTANT
		"targeted": return AbilityType.TARGETED
		"channeled": return AbilityType.CHANNELED
		"formation": return AbilityType.FORMATION
		"global": return AbilityType.GLOBAL
	return AbilityType.INSTANT


## Parse target type string.
static func _parse_target_type(target_str: String) -> int:
	match target_str.to_lower():
		"none": return TargetType.NONE
		"unit": return TargetType.UNIT
		"position": return TargetType.POSITION
		"area": return TargetType.AREA
		"units": return TargetType.UNITS
	return TargetType.NONE


## Convert to dictionary.
func to_dict() -> Dictionary:
	return {
		"ability_id": ability_id,
		"faction_id": faction_id,
		"display_name": display_name,
		"description": description,
		"hotkey": hotkey,
		"ability_type": _get_ability_type_string(ability_type),
		"target_type": _get_target_type_string(target_type),
		"cooldown": cooldown,
		"resource_cost": resource_cost.duplicate(),
		"prerequisites": prerequisites.duplicate(),
		"channel_duration": channel_duration,
		"execution": execution_params.duplicate(true),
		"feedback": feedback.duplicate(true),
		"is_enabled": is_enabled
	}


## Get ability type string.
static func _get_ability_type_string(type: int) -> String:
	match type:
		AbilityType.INSTANT: return "instant"
		AbilityType.TARGETED: return "targeted"
		AbilityType.CHANNELED: return "channeled"
		AbilityType.FORMATION: return "formation"
		AbilityType.GLOBAL: return "global"
	return "instant"


## Get target type string.
static func _get_target_type_string(type: int) -> String:
	match type:
		TargetType.NONE: return "none"
		TargetType.UNIT: return "unit"
		TargetType.POSITION: return "position"
		TargetType.AREA: return "area"
		TargetType.UNITS: return "units"
	return "none"


## Check if ability requires target.
func requires_target() -> bool:
	return target_type != TargetType.NONE


## Check if ability is channeled.
func is_channeled() -> bool:
	return ability_type == AbilityType.CHANNELED


## Check if ability is formation.
func is_formation() -> bool:
	return ability_type == AbilityType.FORMATION


## Get REE cost.
func get_ree_cost() -> float:
	return resource_cost.get("ree", 0.0)


## Get power cost.
func get_power_cost() -> float:
	return resource_cost.get("power", 0.0)
