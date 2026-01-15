class_name VoxelStateData
extends RefCounted
## VoxelStateData represents individual voxel data for destruction tracking.
## Stores position, HP, stage, timing, and node type flags.

## Position in voxel grid
var position: Vector3i = Vector3i.ZERO

## Current health points (0-100)
var current_hp: int = 100

## Maximum health points
var max_hp: int = 100

## Current destruction stage (0-3)
var stage: int = VoxelStage.Stage.INTACT

## Timestamp of last damage (for timing effects)
var last_damage_time: float = 0.0

## Timestamp when stage last changed
var stage_change_time: float = 0.0

## Node type flags (bitfield)
var type_flags: int = 0

## Voxel type identifier
var voxel_type: String = "default"

## Owning faction (empty = neutral)
var faction_id: String = ""


## Node type flag constants
const FLAG_NONE := 0
const FLAG_POWER_NODE := 1 << 0      ## Part of power infrastructure
const FLAG_POWER_HUB := 1 << 1       ## Power distribution hub
const FLAG_STRATEGIC := 1 << 2       ## Strategic pathway
const FLAG_RESOURCE := 1 << 3        ## Resource deposit
const FLAG_INDUSTRIAL := 1 << 4      ## Industrial building
const FLAG_RESIDENTIAL := 1 << 5     ## Residential building
const FLAG_SPAWNER := 1 << 6         ## Can spawn units


func _init(pos: Vector3i = Vector3i.ZERO, hp: int = 100) -> void:
	position = pos
	current_hp = hp
	max_hp = hp
	stage = VoxelStage.Stage.INTACT


## Apply damage and return new stage if changed, -1 if no change.
func apply_damage(damage: int, current_time: float = 0.0) -> int:
	if not VoxelStage.can_take_damage(stage):
		return -1

	last_damage_time = current_time

	var old_stage := stage
	current_hp = maxi(0, current_hp - damage)

	# Calculate new stage from HP percentage
	var hp_percent := float(current_hp) / float(max_hp)
	stage = VoxelStage.get_stage_from_health(hp_percent)

	if stage != old_stage:
		stage_change_time = current_time
		return stage

	return -1


## Repair voxel and return new stage if changed, -1 if no change.
func apply_repair(heal_amount: int, current_time: float = 0.0) -> int:
	var old_stage := stage
	current_hp = mini(max_hp, current_hp + heal_amount)

	# Calculate new stage from HP percentage
	var hp_percent := float(current_hp) / float(max_hp)
	stage = VoxelStage.get_stage_from_health(hp_percent)

	if stage != old_stage:
		stage_change_time = current_time
		return stage

	return -1


## Check if voxel is power infrastructure.
func is_power_node() -> bool:
	return (type_flags & FLAG_POWER_NODE) != 0 or (type_flags & FLAG_POWER_HUB) != 0


## Check if voxel is on strategic pathway.
func is_strategic_pathway() -> bool:
	return (type_flags & FLAG_STRATEGIC) != 0


## Check if voxel is resource deposit.
func is_resource() -> bool:
	return (type_flags & FLAG_RESOURCE) != 0


## Check if voxel can be traversed.
func is_traversable() -> bool:
	return VoxelStage.is_traversable(stage)


## Get health as percentage (0.0 - 1.0).
func get_health_percent() -> float:
	if max_hp <= 0:
		return 0.0
	return float(current_hp) / float(max_hp)


## Set node type flag.
func set_flag(flag: int, enabled: bool) -> void:
	if enabled:
		type_flags |= flag
	else:
		type_flags &= ~flag


## Check if flag is set.
func has_flag(flag: int) -> bool:
	return (type_flags & flag) != 0


## Serialize to binary (3 bytes: stage, hp, flags).
func to_binary() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(3)
	data[0] = stage
	data[1] = current_hp
	data[2] = type_flags & 0xFF  # Only lower 8 bits
	return data


## Deserialize from binary.
func from_binary(data: PackedByteArray, offset: int = 0) -> void:
	if data.size() < offset + 3:
		return
	stage = data[offset]
	current_hp = data[offset + 1]
	type_flags = data[offset + 2]


## Serialize to dictionary for save files.
func to_dict() -> Dictionary:
	return {
		"position": [position.x, position.y, position.z],
		"current_hp": current_hp,
		"max_hp": max_hp,
		"stage": stage,
		"last_damage_time": last_damage_time,
		"stage_change_time": stage_change_time,
		"type_flags": type_flags,
		"voxel_type": voxel_type,
		"faction_id": faction_id
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	var pos_arr: Array = data.get("position", [0, 0, 0])
	position = Vector3i(pos_arr[0], pos_arr[1], pos_arr[2])
	current_hp = data.get("current_hp", 100)
	max_hp = data.get("max_hp", 100)
	stage = data.get("stage", VoxelStage.Stage.INTACT)
	last_damage_time = data.get("last_damage_time", 0.0)
	stage_change_time = data.get("stage_change_time", 0.0)
	type_flags = data.get("type_flags", 0)
	voxel_type = data.get("voxel_type", "default")
	faction_id = data.get("faction_id", "")


## Create copy of voxel state.
func duplicate() -> VoxelStateData:
	var copy := VoxelStateData.new(position, max_hp)
	copy.current_hp = current_hp
	copy.stage = stage
	copy.last_damage_time = last_damage_time
	copy.stage_change_time = stage_change_time
	copy.type_flags = type_flags
	copy.voxel_type = voxel_type
	copy.faction_id = faction_id
	return copy


## Get debug string.
func _to_string() -> String:
	return "VoxelStateData(%s, HP:%d/%d, Stage:%s)" % [
		position,
		current_hp,
		max_hp,
		VoxelStage.get_name(stage)
	]
