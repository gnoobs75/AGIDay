class_name RepairPrioritizationManager
extends RefCounted
## RepairPrioritizationManager coordinates repair target selection for builders.

signal repair_target_assigned(builder_id: int, target_position: Vector3i)
signal builder_no_targets(builder_id: int)
signal priority_targets_updated()

## Builder selectors
var _builder_selectors: Dictionary = {}  ## builder_id -> RepairTargetSelector

## Shared infrastructure detection callbacks
var _power_node_callback: Callable = Callable()
var _pathway_callback: Callable = Callable()

## Target reservations to prevent multiple builders targeting same voxel
var _reserved_targets: Dictionary = {}  ## "x,y,z" -> builder_id


func _init() -> void:
	pass


## Set power node detection callback.
func set_power_node_callback(callback: Callable) -> void:
	_power_node_callback = callback

	# Update all existing selectors
	for builder_id in _builder_selectors:
		_builder_selectors[builder_id].set_power_node_callback(callback)


## Set strategic pathway detection callback.
func set_pathway_callback(callback: Callable) -> void:
	_pathway_callback = callback

	# Update all existing selectors
	for builder_id in _builder_selectors:
		_builder_selectors[builder_id].set_strategic_pathway_callback(callback)


## Register a builder.
func register_builder(builder_id: int) -> RepairTargetSelector:
	if _builder_selectors.has(builder_id):
		return _builder_selectors[builder_id]

	var selector := RepairTargetSelector.new()

	if _power_node_callback.is_valid():
		selector.set_power_node_callback(_power_node_callback)

	if _pathway_callback.is_valid():
		selector.set_strategic_pathway_callback(_pathway_callback)

	_builder_selectors[builder_id] = selector

	return selector


## Unregister a builder.
func unregister_builder(builder_id: int) -> void:
	# Release any reserved targets
	release_builder_reservations(builder_id)

	_builder_selectors.erase(builder_id)


## Update builder position.
func update_builder_position(builder_id: int, position: Vector3) -> void:
	if _builder_selectors.has(builder_id):
		_builder_selectors[builder_id].set_position(position)


## Select repair target for a builder from scanned voxels.
func select_target_for_builder(builder_id: int, damaged_voxels: Array) -> RepairTargetSelector.RepairTarget:
	if not _builder_selectors.has(builder_id):
		register_builder(builder_id)

	var selector: RepairTargetSelector = _builder_selectors[builder_id]

	# Filter out already reserved targets
	var available_voxels := _filter_unreserved(damaged_voxels)

	if available_voxels.is_empty():
		builder_no_targets.emit(builder_id)
		return null

	var target := selector.select_repair_target(available_voxels)

	if target != null:
		# Reserve the target
		_reserve_target(target.position, builder_id)
		repair_target_assigned.emit(builder_id, target.position)

	return target


## Filter out reserved voxels.
func _filter_unreserved(damaged_voxels: Array) -> Array:
	var available: Array = []

	for voxel_info in damaged_voxels:
		var position: Vector3i

		if voxel_info is DamageScanner.DamagedVoxelInfo:
			position = voxel_info.position
		elif voxel_info is Dictionary:
			position = voxel_info.get("position", Vector3i.ZERO)
		elif voxel_info is Vector3i:
			position = voxel_info
		else:
			continue

		var key := _position_to_key(position)
		if not _reserved_targets.has(key):
			available.append(voxel_info)

	return available


## Reserve a target for a builder.
func _reserve_target(position: Vector3i, builder_id: int) -> void:
	var key := _position_to_key(position)
	_reserved_targets[key] = builder_id


## Release a specific target reservation.
func release_target(position: Vector3i) -> void:
	var key := _position_to_key(position)
	_reserved_targets.erase(key)


## Release all reservations for a builder.
func release_builder_reservations(builder_id: int) -> void:
	var keys_to_remove: Array = []

	for key in _reserved_targets:
		if _reserved_targets[key] == builder_id:
			keys_to_remove.append(key)

	for key in keys_to_remove:
		_reserved_targets.erase(key)


## Check if target is reserved.
func is_target_reserved(position: Vector3i) -> bool:
	var key := _position_to_key(position)
	return _reserved_targets.has(key)


## Get builder reserving a target.
func get_reserving_builder(position: Vector3i) -> int:
	var key := _position_to_key(position)
	return _reserved_targets.get(key, -1)


## Convert position to string key.
func _position_to_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]


## Get best target for a builder across priority levels.
func get_best_target_info(builder_id: int, damaged_voxels: Array) -> Dictionary:
	if not _builder_selectors.has(builder_id):
		register_builder(builder_id)

	var selector: RepairTargetSelector = _builder_selectors[builder_id]
	var available := _filter_unreserved(damaged_voxels)

	if available.is_empty():
		return {}

	var target := selector.select_repair_target(available)
	if target == null:
		return {}

	return {
		"position": target.position,
		"world_position": target.world_position,
		"priority": target.priority,
		"priority_name": RepairTargetSelector.get_priority_name(target.priority),
		"distance": target.distance,
		"damage_stage": target.damage_stage
	}


## Get count of available targets by priority.
func get_available_target_counts(damaged_voxels: Array) -> Dictionary:
	var available := _filter_unreserved(damaged_voxels)

	var counts := {
		RepairTargetSelector.PRIORITY_POWER: 0,
		RepairTargetSelector.PRIORITY_PATHWAY: 0,
		RepairTargetSelector.PRIORITY_GENERAL: 0
	}

	# Use a temporary selector
	var temp_selector := RepairTargetSelector.new()
	if _power_node_callback.is_valid():
		temp_selector.set_power_node_callback(_power_node_callback)
	if _pathway_callback.is_valid():
		temp_selector.set_strategic_pathway_callback(_pathway_callback)

	var targets := temp_selector.get_prioritized_targets(available)
	for target in targets:
		counts[target.priority] = counts.get(target.priority, 0) + 1

	return counts


## Get reserved target count.
func get_reserved_count() -> int:
	return _reserved_targets.size()


## Get all reserved positions.
func get_reserved_positions() -> Array[Vector3i]:
	var positions: Array[Vector3i] = []

	for key in _reserved_targets:
		var parts := key.split(",")
		if parts.size() == 3:
			positions.append(Vector3i(int(parts[0]), int(parts[1]), int(parts[2])))

	return positions


## Clear all reservations.
func clear_reservations() -> void:
	_reserved_targets.clear()


## Clear all data.
func clear() -> void:
	_builder_selectors.clear()
	_reserved_targets.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"builder_count": _builder_selectors.size(),
		"reserved_targets": _reserved_targets.size(),
		"has_power_callback": _power_node_callback.is_valid(),
		"has_pathway_callback": _pathway_callback.is_valid()
	}
