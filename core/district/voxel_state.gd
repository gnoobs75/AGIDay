class_name VoxelState
extends RefCounted
## VoxelState represents the state of a single voxel in the destruction system.
## Tracks HP, damage stage, and property flags.

## Damage stages
enum DamageStage {
	INTACT,      ## 0 - Full health, normal appearance
	CRACKED,     ## 1 - Visible damage, 50-75% HP
	RUBBLE,      ## 2 - Heavily damaged, 25-50% HP
	CRATER       ## 3 - Destroyed, 0% HP
}

## Default values
const DEFAULT_MAX_HP := 100.0
const CRACKED_THRESHOLD := 0.75   ## Below 75% HP
const RUBBLE_THRESHOLD := 0.50    ## Below 50% HP
const CRATER_THRESHOLD := 0.25    ## Below 25% HP

## State data
var stage: DamageStage = DamageStage.INTACT
var current_hp: float = DEFAULT_MAX_HP
var max_hp: float = DEFAULT_MAX_HP

## Property flags
var is_power_node: bool = false       ## Part of power infrastructure
var is_industrial: bool = false        ## Factory/industrial building
var is_structural: bool = false        ## Load-bearing element
var is_occupied: bool = true           ## Has voxel content

## Building reference
var building_type: int = 0
var building_id: int = -1

## Position (for reference)
var grid_x: int = 0
var grid_y: int = 0
var grid_z: int = 0


func _init() -> void:
	pass


## Initialize voxel state.
func initialize(hp: float = DEFAULT_MAX_HP, building: int = 0,
				power_node: bool = false, industrial: bool = false) -> void:
	max_hp = hp
	current_hp = hp
	building_type = building
	is_power_node = power_node
	is_industrial = industrial
	is_occupied = true
	stage = DamageStage.INTACT


## Apply damage to voxel.
func apply_damage(amount: float) -> bool:
	if not is_occupied:
		return false

	var was_alive := current_hp > 0

	current_hp = maxf(0.0, current_hp - amount)

	# Update damage stage
	_update_stage()

	return was_alive and current_hp <= 0  # Returns true if this damage destroyed voxel


## Heal voxel.
func heal(amount: float) -> void:
	if not is_occupied:
		return

	current_hp = minf(max_hp, current_hp + amount)
	_update_stage()


## Update damage stage based on HP.
func _update_stage() -> void:
	var hp_ratio := current_hp / max_hp if max_hp > 0 else 0.0

	if hp_ratio <= 0:
		stage = DamageStage.CRATER
		is_occupied = false
	elif hp_ratio < CRATER_THRESHOLD:
		stage = DamageStage.RUBBLE
	elif hp_ratio < RUBBLE_THRESHOLD:
		stage = DamageStage.RUBBLE
	elif hp_ratio < CRACKED_THRESHOLD:
		stage = DamageStage.CRACKED
	else:
		stage = DamageStage.INTACT


## Check if voxel is destroyed.
func is_destroyed() -> bool:
	return stage == DamageStage.CRATER or current_hp <= 0


## Check if voxel is damaged.
func is_damaged() -> bool:
	return stage != DamageStage.INTACT


## Get HP percentage.
func get_hp_percent() -> float:
	if max_hp <= 0:
		return 0.0
	return current_hp / max_hp


## Get stage name.
func get_stage_name() -> String:
	match stage:
		DamageStage.INTACT: return "Intact"
		DamageStage.CRACKED: return "Cracked"
		DamageStage.RUBBLE: return "Rubble"
		DamageStage.CRATER: return "Crater"
	return "Unknown"


## Set position.
func set_position(x: int, y: int, z: int) -> void:
	grid_x = x
	grid_y = y
	grid_z = z


## Get position as Vector3i.
func get_position() -> Vector3i:
	return Vector3i(grid_x, grid_y, grid_z)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"stage": stage,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"is_power_node": is_power_node,
		"is_industrial": is_industrial,
		"is_structural": is_structural,
		"is_occupied": is_occupied,
		"building_type": building_type,
		"building_id": building_id,
		"position": {"x": grid_x, "y": grid_y, "z": grid_z}
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	stage = data.get("stage", DamageStage.INTACT)
	current_hp = data.get("current_hp", DEFAULT_MAX_HP)
	max_hp = data.get("max_hp", DEFAULT_MAX_HP)
	is_power_node = data.get("is_power_node", false)
	is_industrial = data.get("is_industrial", false)
	is_structural = data.get("is_structural", false)
	is_occupied = data.get("is_occupied", true)
	building_type = data.get("building_type", 0)
	building_id = data.get("building_id", -1)

	var pos: Dictionary = data.get("position", {})
	grid_x = pos.get("x", 0)
	grid_y = pos.get("y", 0)
	grid_z = pos.get("z", 0)


## Create with parameters.
static func create(x: int, y: int, z: int, hp: float = DEFAULT_MAX_HP,
				   building: int = 0, power_node: bool = false,
				   industrial: bool = false) -> VoxelState:
	var state := VoxelState.new()
	state.set_position(x, y, z)
	state.initialize(hp, building, power_node, industrial)
	return state


## Create empty/unoccupied voxel.
static func create_empty(x: int, y: int, z: int) -> VoxelState:
	var state := VoxelState.new()
	state.set_position(x, y, z)
	state.is_occupied = false
	state.current_hp = 0
	state.stage = DamageStage.CRATER
	return state
