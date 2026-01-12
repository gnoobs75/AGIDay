class_name VoxelStage
extends RefCounted
## VoxelStage defines destruction stages for voxels.

## Destruction stages
enum Stage {
	INTACT = 0,    ## Full health, undamaged
	CRACKED = 1,   ## Damaged but functional
	RUBBLE = 2,    ## Destroyed, generates resources
	CRATER = 3     ## Fully destroyed, impassable
}

## Stage damage multipliers
const DAMAGE_MULTIPLIERS := {
	Stage.INTACT: 1.0,
	Stage.CRACKED: 1.0,
	Stage.RUBBLE: 1.5,   ## Rubble takes more damage to clear
	Stage.CRATER: 0.0    ## No more damage possible
}

## Harvester disassembly times (seconds)
const DISASSEMBLY_TIMES := {
	Stage.INTACT: 10.0,
	Stage.CRACKED: 5.0,
	Stage.RUBBLE: 2.0,
	Stage.CRATER: 0.0
}

## Stage health thresholds (percentage of max health)
const HEALTH_THRESHOLDS := {
	Stage.INTACT: 1.0,
	Stage.CRACKED: 0.5,
	Stage.RUBBLE: 0.1,
	Stage.CRATER: 0.0
}


## Get stage from health percentage.
static func get_stage_from_health(health_percent: float) -> int:
	if health_percent <= 0:
		return Stage.CRATER
	elif health_percent <= HEALTH_THRESHOLDS[Stage.RUBBLE]:
		return Stage.RUBBLE
	elif health_percent <= HEALTH_THRESHOLDS[Stage.CRACKED]:
		return Stage.CRACKED
	else:
		return Stage.INTACT


## Get damage multiplier for stage.
static func get_damage_multiplier(stage: int) -> float:
	return DAMAGE_MULTIPLIERS.get(stage, 1.0)


## Get disassembly time for stage.
static func get_disassembly_time(stage: int) -> float:
	return DISASSEMBLY_TIMES.get(stage, 10.0)


## Get stage name.
static func get_name(stage: int) -> String:
	match stage:
		Stage.INTACT: return "Intact"
		Stage.CRACKED: return "Cracked"
		Stage.RUBBLE: return "Rubble"
		Stage.CRATER: return "Crater"
	return "Unknown"


## Check if stage is traversable.
static func is_traversable(stage: int) -> bool:
	return stage != Stage.CRATER


## Check if stage can take damage.
static func can_take_damage(stage: int) -> bool:
	return stage != Stage.CRATER


## Get all stages.
static func get_all_stages() -> Array[int]:
	return [Stage.INTACT, Stage.CRACKED, Stage.RUBBLE, Stage.CRATER]
