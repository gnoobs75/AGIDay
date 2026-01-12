class_name RepairTargetSelector
extends RefCounted
## RepairTargetSelector prioritizes and selects optimal repair targets.

signal target_selected(position: Vector3i, priority: int)
signal no_targets_available()

## Priority levels
const PRIORITY_POWER := 1        ## Power infrastructure (highest)
const PRIORITY_PATHWAY := 2      ## Strategic pathways (medium)
const PRIORITY_GENERAL := 3      ## General buildings (lowest)

## Callbacks for infrastructure detection
var _is_power_node_callback: Callable = Callable()
var _is_strategic_pathway_callback: Callable = Callable()

## Scanner position for distance calculations
var _selector_position: Vector3 = Vector3.ZERO


## Repair target info
class RepairTarget:
	var position: Vector3i = Vector3i.ZERO
	var world_position: Vector3 = Vector3.ZERO
	var priority: int = PRIORITY_GENERAL
	var distance: float = 0.0
	var damage_stage: int = 0

	func _init(pos: Vector3i = Vector3i.ZERO, world_pos: Vector3 = Vector3.ZERO, prio: int = PRIORITY_GENERAL, dist: float = 0.0, stage: int = 0) -> void:
		position = pos
		world_position = world_pos
		priority = prio
		distance = dist
		damage_stage = stage


func _init() -> void:
	pass


## Set callback to check if voxel is power infrastructure.
## Callback signature: func(position: Vector3i) -> bool
func set_power_node_callback(callback: Callable) -> void:
	_is_power_node_callback = callback


## Set callback to check if voxel is on strategic pathway.
## Callback signature: func(position: Vector3i) -> bool
func set_strategic_pathway_callback(callback: Callable) -> void:
	_is_strategic_pathway_callback = callback


## Set selector position for distance calculations.
func set_position(position: Vector3) -> void:
	_selector_position = position


## Select optimal repair target from damaged voxels.
func select_repair_target(damaged_voxels: Array) -> RepairTarget:
	if damaged_voxels.is_empty():
		no_targets_available.emit()
		return null

	# Categorize all voxels by priority
	var priority_1: Array[RepairTarget] = []
	var priority_2: Array[RepairTarget] = []
	var priority_3: Array[RepairTarget] = []

	for voxel_info in damaged_voxels:
		var target := _create_repair_target(voxel_info)

		match target.priority:
			PRIORITY_POWER:
				priority_1.append(target)
			PRIORITY_PATHWAY:
				priority_2.append(target)
			PRIORITY_GENERAL:
				priority_3.append(target)

	# Select from highest priority with targets
	var selected: RepairTarget = null

	if not priority_1.is_empty():
		selected = _select_closest_target(priority_1)
	elif not priority_2.is_empty():
		selected = _select_closest_target(priority_2)
	elif not priority_3.is_empty():
		selected = _select_closest_target(priority_3)

	if selected != null:
		target_selected.emit(selected.position, selected.priority)
	else:
		no_targets_available.emit()

	return selected


## Create repair target from damaged voxel info.
func _create_repair_target(voxel_info) -> RepairTarget:
	var position: Vector3i
	var world_position: Vector3
	var damage_stage: int = 0

	# Handle DamageScanner.DamagedVoxelInfo
	if voxel_info is DamageScanner.DamagedVoxelInfo:
		position = voxel_info.position
		world_position = voxel_info.world_position
		damage_stage = voxel_info.damage_stage
	# Handle Dictionary format
	elif voxel_info is Dictionary:
		position = voxel_info.get("position", Vector3i.ZERO)
		world_position = Vector3(position)
		damage_stage = voxel_info.get("damage_stage", 0)
	# Handle Vector3i directly
	elif voxel_info is Vector3i:
		position = voxel_info
		world_position = Vector3(position)
	else:
		position = Vector3i.ZERO
		world_position = Vector3.ZERO

	var distance := _selector_position.distance_to(world_position)
	var priority := _determine_priority(position)

	return RepairTarget.new(position, world_position, priority, distance, damage_stage)


## Determine priority level for a voxel position.
func _determine_priority(position: Vector3i) -> int:
	# Check power infrastructure first (highest priority)
	if _is_power_node_callback.is_valid():
		if _is_power_node_callback.call(position):
			return PRIORITY_POWER

	# Check strategic pathway (medium priority)
	if _is_strategic_pathway_callback.is_valid():
		if _is_strategic_pathway_callback.call(position):
			return PRIORITY_PATHWAY

	# Default to general (lowest priority)
	return PRIORITY_GENERAL


## Select closest target from array.
func _select_closest_target(targets: Array[RepairTarget]) -> RepairTarget:
	if targets.is_empty():
		return null

	var closest: RepairTarget = targets[0]

	for target in targets:
		if target.distance < closest.distance:
			closest = target

	return closest


## Get all targets at a specific priority level.
func filter_by_priority(damaged_voxels: Array, priority: int) -> Array[RepairTarget]:
	var results: Array[RepairTarget] = []

	for voxel_info in damaged_voxels:
		var target := _create_repair_target(voxel_info)
		if target.priority == priority:
			results.append(target)

	return results


## Get prioritized list of all targets.
func get_prioritized_targets(damaged_voxels: Array) -> Array[RepairTarget]:
	var all_targets: Array[RepairTarget] = []

	for voxel_info in damaged_voxels:
		all_targets.append(_create_repair_target(voxel_info))

	# Sort by priority first, then by distance
	all_targets.sort_custom(_compare_targets)

	return all_targets


## Compare function for sorting targets.
func _compare_targets(a: RepairTarget, b: RepairTarget) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority  # Lower priority number = higher priority
	return a.distance < b.distance


## Get priority name for debugging.
static func get_priority_name(priority: int) -> String:
	match priority:
		PRIORITY_POWER:
			return "Power Infrastructure"
		PRIORITY_PATHWAY:
			return "Strategic Pathway"
		PRIORITY_GENERAL:
			return "General Building"
		_:
			return "Unknown"


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"selector_position": _selector_position,
		"has_power_callback": _is_power_node_callback.is_valid(),
		"has_pathway_callback": _is_strategic_pathway_callback.is_valid()
	}
