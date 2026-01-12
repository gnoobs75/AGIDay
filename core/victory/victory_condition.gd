class_name VictoryCondition
extends RefCounted
## VictoryCondition defines win/loss conditions for a game.

## Victory types
enum VictoryType {
	DISTRICT_DOMINATION = 0,  ## Control all districts
	FACTORY_DESTRUCTION = 1,  ## Destroy all enemy factories
	DUAL_CONDITION = 2,       ## Both district + factory
	TIME_LIMIT = 3,           ## Most districts at time limit
	WAVE_LIMIT = 4,           ## Survive waves
	ELIMINATION = 5           ## Last faction standing
}

## Victory type
var victory_type: int = VictoryType.DUAL_CONDITION

## Required districts for district-based victory
var required_districts: int = -1  # -1 means all

## Required factories destroyed for factory victory
var required_factories: int = -1  # -1 means all

## Time limit in seconds (0 = no limit)
var time_limit: float = 0.0

## Wave limit (0 = no limit)
var wave_limit: int = 0

## Whether survival mode continues after victory
var survival_mode: bool = true

## Custom conditions
var custom_conditions: Dictionary = {}


func _init() -> void:
	pass


## Initialize with type.
func initialize(type: int) -> void:
	victory_type = type

	match type:
		VictoryType.DISTRICT_DOMINATION:
			required_districts = -1
			required_factories = 0

		VictoryType.FACTORY_DESTRUCTION:
			required_districts = 0
			required_factories = -1

		VictoryType.DUAL_CONDITION:
			required_districts = -1
			required_factories = -1

		VictoryType.ELIMINATION:
			required_districts = 0
			required_factories = -1


## Check if victory is achieved.
func check_victory(
	faction_districts: int,
	total_districts: int,
	enemy_factories_destroyed: int,
	total_enemy_factories: int,
	current_time: float,
	current_wave: int
) -> bool:
	match victory_type:
		VictoryType.DISTRICT_DOMINATION:
			return _check_district_domination(faction_districts, total_districts)

		VictoryType.FACTORY_DESTRUCTION:
			return _check_factory_destruction(enemy_factories_destroyed, total_enemy_factories)

		VictoryType.DUAL_CONDITION:
			return (_check_district_domination(faction_districts, total_districts) and
					_check_factory_destruction(enemy_factories_destroyed, total_enemy_factories))

		VictoryType.TIME_LIMIT:
			return time_limit > 0 and current_time >= time_limit

		VictoryType.WAVE_LIMIT:
			return wave_limit > 0 and current_wave >= wave_limit

		VictoryType.ELIMINATION:
			return _check_factory_destruction(enemy_factories_destroyed, total_enemy_factories)

	return false


## Check district domination.
func _check_district_domination(faction_districts: int, total_districts: int) -> bool:
	if required_districts < 0:
		# All districts required
		return faction_districts >= total_districts
	else:
		return faction_districts >= required_districts


## Check factory destruction.
func _check_factory_destruction(destroyed: int, total: int) -> bool:
	if required_factories < 0:
		# All factories required
		return destroyed >= total
	else:
		return destroyed >= required_factories


## Get victory type name.
func get_type_name() -> String:
	match victory_type:
		VictoryType.DISTRICT_DOMINATION: return "District Domination"
		VictoryType.FACTORY_DESTRUCTION: return "Factory Destruction"
		VictoryType.DUAL_CONDITION: return "Dual Condition"
		VictoryType.TIME_LIMIT: return "Time Limit"
		VictoryType.WAVE_LIMIT: return "Wave Limit"
		VictoryType.ELIMINATION: return "Elimination"
	return "Unknown"


## Get victory description.
func get_description() -> String:
	match victory_type:
		VictoryType.DISTRICT_DOMINATION:
			if required_districts < 0:
				return "Control all districts"
			return "Control %d districts" % required_districts

		VictoryType.FACTORY_DESTRUCTION:
			if required_factories < 0:
				return "Destroy all enemy factories"
			return "Destroy %d enemy factories" % required_factories

		VictoryType.DUAL_CONDITION:
			return "Control all districts AND destroy all enemy factories"

		VictoryType.TIME_LIMIT:
			return "Control most districts when time runs out"

		VictoryType.WAVE_LIMIT:
			return "Survive %d waves" % wave_limit

		VictoryType.ELIMINATION:
			return "Be the last faction standing"

	return ""


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"victory_type": victory_type,
		"required_districts": required_districts,
		"required_factories": required_factories,
		"time_limit": time_limit,
		"wave_limit": wave_limit,
		"survival_mode": survival_mode,
		"custom_conditions": custom_conditions.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> VictoryCondition:
	var condition := VictoryCondition.new()
	condition.victory_type = data.get("victory_type", VictoryType.DUAL_CONDITION)
	condition.required_districts = data.get("required_districts", -1)
	condition.required_factories = data.get("required_factories", -1)
	condition.time_limit = data.get("time_limit", 0.0)
	condition.wave_limit = data.get("wave_limit", 0)
	condition.survival_mode = data.get("survival_mode", true)
	condition.custom_conditions = data.get("custom_conditions", {}).duplicate()
	return condition
