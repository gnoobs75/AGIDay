class_name DistrictTypeConfig
extends Resource
## DistrictTypeConfig defines resource generation rates for a district type.

## District type this config applies to
@export var district_type: int = DistrictType.Type.MIXED

## Power generation rate per second
@export var power_rate: float = 1.0

## REE generation rate per second
@export var ree_rate: float = 1.0

## Research generation rate per second
@export var research_rate: float = 1.0

## Unit production speed modifier (1.0 = normal)
@export var production_modifier: float = 1.0

## Defense bonus modifier (1.0 = normal)
@export var defense_modifier: float = 1.0

## Capture difficulty modifier (1.0 = normal, higher = harder)
@export var capture_difficulty: float = 1.0


func _init() -> void:
	pass


## Initialize with type-specific defaults.
func initialize_for_type(type: int) -> void:
	district_type = type
	match type:
		DistrictType.Type.POWER_HUB:
			power_rate = 3.0
			ree_rate = 0.5
			research_rate = 0.5
			production_modifier = 0.8
			defense_modifier = 1.2
			capture_difficulty = 1.2
		DistrictType.Type.INDUSTRIAL:
			power_rate = 1.0
			ree_rate = 3.0
			research_rate = 0.5
			production_modifier = 1.5
			defense_modifier = 1.0
			capture_difficulty = 1.0
		DistrictType.Type.RESEARCH:
			power_rate = 0.5
			ree_rate = 0.5
			research_rate = 3.0
			production_modifier = 0.8
			defense_modifier = 0.8
			capture_difficulty = 0.9
		DistrictType.Type.RESIDENTIAL:
			power_rate = 1.0
			ree_rate = 1.0
			research_rate = 1.0
			production_modifier = 1.2
			defense_modifier = 1.0
			capture_difficulty = 0.8
		DistrictType.Type.MIXED:
			power_rate = 1.0
			ree_rate = 1.0
			research_rate = 1.0
			production_modifier = 1.0
			defense_modifier = 1.0
			capture_difficulty = 1.0


## Get total resource value (for comparison).
func get_total_resource_value() -> float:
	return power_rate + ree_rate + research_rate


## Apply faction modifier to rates.
func apply_faction_modifier(modifier: float) -> void:
	power_rate *= modifier
	ree_rate *= modifier
	research_rate *= modifier


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"district_type": district_type,
		"power_rate": power_rate,
		"ree_rate": ree_rate,
		"research_rate": research_rate,
		"production_modifier": production_modifier,
		"defense_modifier": defense_modifier,
		"capture_difficulty": capture_difficulty
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> DistrictTypeConfig:
	var config := DistrictTypeConfig.new()
	config.district_type = data.get("district_type", DistrictType.Type.MIXED)
	config.power_rate = data.get("power_rate", 1.0)
	config.ree_rate = data.get("ree_rate", 1.0)
	config.research_rate = data.get("research_rate", 1.0)
	config.production_modifier = data.get("production_modifier", 1.0)
	config.defense_modifier = data.get("defense_modifier", 1.0)
	config.capture_difficulty = data.get("capture_difficulty", 1.0)
	return config


## Create default configs for all types.
static func create_all_configs() -> Dictionary:
	var configs := {}
	for type in [DistrictType.Type.POWER_HUB, DistrictType.Type.INDUSTRIAL,
				 DistrictType.Type.RESEARCH, DistrictType.Type.RESIDENTIAL,
				 DistrictType.Type.MIXED]:
		var config := DistrictTypeConfig.new()
		config.initialize_for_type(type)
		configs[type] = config
	return configs
