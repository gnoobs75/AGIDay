class_name VoxelRepairSystem
extends RefCounted
## VoxelRepairSystem handles progressive repair of damaged voxels.
## Manages repair progress, state transitions, and faction bonuses.

signal repair_started(builder_id: int, voxel_position: Vector3i)
signal repair_progress(builder_id: int, voxel_position: Vector3i, progress: float)
signal repair_completed(builder_id: int, voxel_position: Vector3i, new_stage: int)
signal repair_interrupted(builder_id: int, voxel_position: Vector3i, reason: String)

## Base repair times per stage transition (seconds)
const REPAIR_TIME_RUBBLE_TO_CRACKED := 8.0
const REPAIR_TIME_CRACKED_TO_INTACT := 5.0

## Repair range (world units)
const DEFAULT_REPAIR_RANGE := 5.0

## HP values after repair
const HP_AFTER_RUBBLE_REPAIR := 50   ## Cracked state
const HP_AFTER_CRACKED_REPAIR := 100 ## Intact state

## Faction repair bonuses
const FACTION_BONUS_OPTIFORGE_POWER := 1.5  ## OptiForge power infrastructure bonus
const FACTION_BONUS_LOGIBOTS_MULTI := 1.0   ## LogiBots can repair multiple

## Active repair states
var _active_repairs: Dictionary = {}  ## builder_id -> RepairState

## Chunk manager reference
var _chunk_manager: VoxelChunkManager = null


## Repair state tracking for each builder.
class RepairState:
	var builder_id: int = 0
	var target_position: Vector3i = Vector3i.ZERO
	var target_stage: int = 0        ## Stage being repaired from
	var progress: float = 0.0        ## 0.0 to 1.0
	var repair_speed: float = 1.0    ## Voxels per second (base rate)
	var faction_id: String = ""
	var is_power_node: bool = false
	var start_time: float = 0.0

	func get_repair_time() -> float:
		match target_stage:
			VoxelStage.Stage.RUBBLE:
				return REPAIR_TIME_RUBBLE_TO_CRACKED
			VoxelStage.Stage.CRACKED:
				return REPAIR_TIME_CRACKED_TO_INTACT
			_:
				return 0.0


func _init() -> void:
	pass


## Set chunk manager reference.
func set_chunk_manager(manager: VoxelChunkManager) -> void:
	_chunk_manager = manager


## Start repair on a voxel.
func start_repair(
	builder_id: int,
	voxel_position: Vector3i,
	builder_position: Vector3,
	repair_speed: float,
	faction_id: String
) -> bool:
	# Check if builder already repairing
	if _active_repairs.has(builder_id):
		return false

	# Get voxel state
	if _chunk_manager == null:
		return false

	var voxel := _chunk_manager.get_voxel(voxel_position)
	if voxel == null:
		return false

	# Check if voxel needs repair
	if voxel.stage == VoxelStage.Stage.INTACT:
		return false  # Already intact

	if voxel.stage == VoxelStage.Stage.CRATER:
		return false  # Can't repair craters

	# Check repair range
	var voxel_world_pos := Vector3(voxel_position)
	if builder_position.distance_to(voxel_world_pos) > DEFAULT_REPAIR_RANGE:
		return false

	# Create repair state
	var state := RepairState.new()
	state.builder_id = builder_id
	state.target_position = voxel_position
	state.target_stage = voxel.stage
	state.progress = 0.0
	state.repair_speed = repair_speed
	state.faction_id = faction_id
	state.is_power_node = voxel.is_power_node()
	state.start_time = Time.get_ticks_msec() / 1000.0

	_active_repairs[builder_id] = state

	repair_started.emit(builder_id, voxel_position)
	return true


## Update repair progress for a builder.
func update_repair(builder_id: int, delta: float) -> void:
	if not _active_repairs.has(builder_id):
		return

	var state: RepairState = _active_repairs[builder_id]

	# Verify voxel still needs repair
	var voxel := _chunk_manager.get_voxel(state.target_position)
	if voxel == null:
		_interrupt_repair(builder_id, "voxel_missing")
		return

	# Check if stage changed (took damage)
	if voxel.stage != state.target_stage:
		if voxel.stage < state.target_stage:
			# Voxel was repaired by something else
			_interrupt_repair(builder_id, "already_repaired")
		else:
			# Voxel took damage
			_interrupt_repair(builder_id, "voxel_damaged")
		return

	# Calculate effective repair speed
	var effective_speed := _calculate_effective_speed(state)

	# Progress repair
	var repair_time := state.get_repair_time()
	if repair_time <= 0:
		_interrupt_repair(builder_id, "invalid_stage")
		return

	var progress_rate := effective_speed / repair_time
	state.progress += progress_rate * delta

	repair_progress.emit(builder_id, state.target_position, state.progress)

	# Check completion
	if state.progress >= 1.0:
		_complete_repair(builder_id)


## Calculate effective repair speed with faction bonuses.
func _calculate_effective_speed(state: RepairState) -> float:
	var speed := state.repair_speed

	# Apply faction bonuses
	match state.faction_id:
		"optiforge":
			# OptiForge gets bonus for power infrastructure
			if state.is_power_node:
				speed *= FACTION_BONUS_OPTIFORGE_POWER
		"logibots":
			# LogiBots base multi-voxel ability handled elsewhere
			pass

	return speed


## Complete a repair.
func _complete_repair(builder_id: int) -> void:
	if not _active_repairs.has(builder_id):
		return

	var state: RepairState = _active_repairs[builder_id]

	# Get voxel and transition to new stage
	var voxel := _chunk_manager.get_voxel(state.target_position)
	if voxel == null:
		_active_repairs.erase(builder_id)
		return

	# Determine new stage and HP
	var new_stage: int
	var new_hp: int

	match state.target_stage:
		VoxelStage.Stage.RUBBLE:
			new_stage = VoxelStage.Stage.CRACKED
			new_hp = HP_AFTER_RUBBLE_REPAIR
		VoxelStage.Stage.CRACKED:
			new_stage = VoxelStage.Stage.INTACT
			new_hp = HP_AFTER_CRACKED_REPAIR
		_:
			_active_repairs.erase(builder_id)
			return

	# Apply repair to voxel
	var heal_amount := new_hp - voxel.current_hp
	if heal_amount > 0:
		_chunk_manager.repair_voxel_immediate(
			state.target_position,
			heal_amount,
			Time.get_ticks_msec() / 1000.0
		)

	repair_completed.emit(builder_id, state.target_position, new_stage)

	# Clean up
	_active_repairs.erase(builder_id)


## Interrupt a repair.
func _interrupt_repair(builder_id: int, reason: String) -> void:
	if not _active_repairs.has(builder_id):
		return

	var state: RepairState = _active_repairs[builder_id]
	repair_interrupted.emit(builder_id, state.target_position, reason)

	_active_repairs.erase(builder_id)


## Cancel repair for a builder.
func cancel_repair(builder_id: int) -> void:
	_interrupt_repair(builder_id, "cancelled")


## Check if builder is repairing.
func is_repairing(builder_id: int) -> bool:
	return _active_repairs.has(builder_id)


## Get repair progress for builder.
func get_repair_progress(builder_id: int) -> float:
	if not _active_repairs.has(builder_id):
		return 0.0
	return _active_repairs[builder_id].progress


## Get repair target for builder.
func get_repair_target(builder_id: int) -> Vector3i:
	if not _active_repairs.has(builder_id):
		return Vector3i(-1, -1, -1)
	return _active_repairs[builder_id].target_position


## Get all active repairs.
func get_active_repairs() -> Array[int]:
	var result: Array[int] = []
	for builder_id in _active_repairs:
		result.append(builder_id)
	return result


## Get repair time for stage transition.
static func get_repair_time(from_stage: int) -> float:
	match from_stage:
		VoxelStage.Stage.RUBBLE:
			return REPAIR_TIME_RUBBLE_TO_CRACKED
		VoxelStage.Stage.CRACKED:
			return REPAIR_TIME_CRACKED_TO_INTACT
		_:
			return 0.0


## Check if voxel can be repaired.
static func can_repair_voxel(voxel: VoxelState) -> bool:
	if voxel == null:
		return false
	return voxel.stage == VoxelStage.Stage.CRACKED or voxel.stage == VoxelStage.Stage.RUBBLE


## Get summary for debugging.
func get_summary() -> Dictionary:
	var repairs_info: Array = []
	for builder_id in _active_repairs:
		var state: RepairState = _active_repairs[builder_id]
		repairs_info.append({
			"builder_id": builder_id,
			"target": state.target_position,
			"progress": state.progress,
			"stage": state.target_stage,
			"faction": state.faction_id
		})

	return {
		"active_repairs": _active_repairs.size(),
		"repairs": repairs_info
	}
