class_name HumanResistanceConfig
extends RefCounted
## HumanResistanceConfig stores unit type configurations for Human Resistance AI.

## Unit type configurations
const UNIT_CONFIGS := {
	"soldier": {
		"detection_range": 20.0,
		"patrol_radius": 30.0,
		"aggression": 0.7,
		"attack_range": 15.0,
		"special_behavior": "none"
	},
	"sniper": {
		"detection_range": 35.0,
		"patrol_radius": 50.0,
		"aggression": 0.5,
		"attack_range": 40.0,
		"special_behavior": "prefer_high_ground"
	},
	"heavy_gunner": {
		"detection_range": 25.0,
		"patrol_radius": 25.0,
		"aggression": 0.9,
		"attack_range": 18.0,
		"special_behavior": "prefer_cover"
	},
	"commander": {
		"detection_range": 30.0,
		"patrol_radius": 40.0,
		"aggression": 0.6,
		"attack_range": 20.0,
		"special_behavior": "lead_from_back"
	},
	"default": {
		"detection_range": 20.0,
		"patrol_radius": 30.0,
		"aggression": 0.6,
		"attack_range": 15.0,
		"special_behavior": "none"
	}
}

## Commander buff values
const COMMANDER_BUFF := {
	"radius": 20.0,
	"damage_bonus": 0.20,  ## 20%
	"speed_bonus": 0.15,   ## 15%
	"armor_bonus": 0.10    ## 10%
}


## Get config for unit type.
static func get_config(unit_type: String) -> Dictionary:
	return UNIT_CONFIGS.get(unit_type.to_lower(), UNIT_CONFIGS["default"]).duplicate()


## Get detection range for unit type.
static func get_detection_range(unit_type: String) -> float:
	var config := get_config(unit_type)
	return config["detection_range"]


## Get patrol radius for unit type.
static func get_patrol_radius(unit_type: String) -> float:
	var config := get_config(unit_type)
	return config["patrol_radius"]


## Get aggression level for unit type.
static func get_aggression(unit_type: String) -> float:
	var config := get_config(unit_type)
	return config["aggression"]


## Get attack range for unit type.
static func get_attack_range(unit_type: String) -> float:
	var config := get_config(unit_type)
	return config["attack_range"]


## Get special behavior for unit type.
static func get_special_behavior(unit_type: String) -> String:
	var config := get_config(unit_type)
	return config["special_behavior"]


## Get commander buff config.
static func get_commander_buff() -> Dictionary:
	return COMMANDER_BUFF.duplicate()
