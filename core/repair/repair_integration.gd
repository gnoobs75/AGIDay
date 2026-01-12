class_name RepairIntegration
extends RefCounted
## RepairIntegration connects auto-repair with power grid and pathfinding systems.

signal power_node_repaired(node_id: int)
signal pathway_repaired(voxel_position: Vector3i)
signal voxel_repaired(position: Vector3i, voxel_type: int)
signal repair_integration_completed(repair_type: String, id: int)
signal power_restoration_triggered(district_id: int)
signal pathfinding_update_queued(chunk_id: Vector3i)

## Voxel types for repair
enum VoxelType {
	GENERIC,
	POWER_NODE,
	PATHWAY,
	STRUCTURE
}

## Pending updates (queued to avoid frame hitches)
var _pending_power_updates: Array[int] = []
var _pending_pathfinding_chunks: Array[Vector3i] = []
var _pending_unit_recalculations: Array[int] = []

## System references
var _power_node_manager = null  # PowerNodeManager
var _power_grid_system = null   # PowerGridSystem
var _pathfinding_system = null  # Pathfinding system reference
var _unit_manager = null        # Unit manager reference

## Update configuration
var _batch_updates: bool = true
var _max_updates_per_frame: int = 5


func _init() -> void:
	pass


## Set system references.
func set_power_node_manager(manager) -> void:
	_power_node_manager = manager


func set_power_grid_system(system) -> void:
	_power_grid_system = system


func set_pathfinding_system(system) -> void:
	_pathfinding_system = system


func set_unit_manager(manager) -> void:
	_unit_manager = manager


## Configure batching.
func set_batch_updates(enabled: bool, max_per_frame: int = 5) -> void:
	_batch_updates = enabled
	_max_updates_per_frame = max_per_frame


# ============================================
# REPAIR EVENT HANDLERS
# ============================================

## Handle voxel repair.
func on_voxel_repaired(position: Vector3i, voxel_type: int) -> void:
	voxel_repaired.emit(position, voxel_type)

	match voxel_type:
		VoxelType.POWER_NODE:
			_handle_power_node_repair(position)
		VoxelType.PATHWAY:
			_handle_pathway_repair(position)
		VoxelType.STRUCTURE:
			_handle_structure_repair(position)
		_:
			_handle_generic_repair(position)


## Handle power node repair at position.
func _handle_power_node_repair(position: Vector3i) -> void:
	if _power_node_manager == null:
		return

	var node := _power_node_manager.get_node_at_position(position)
	if node == null:
		return

	on_power_node_repaired(node.node_id)


## Handle power node repair by ID.
func on_power_node_repaired(node_id: int) -> void:
	if _power_node_manager == null:
		return

	var node := _power_node_manager.get_node(node_id)
	if node == null:
		return

	# Full repair the power node
	node.full_repair()

	power_node_repaired.emit(node_id)

	if _batch_updates:
		_pending_power_updates.append(node_id)
	else:
		_activate_power_node(node_id)
		_recalculate_power_distribution(node.faction_id)

	repair_integration_completed.emit("power_node", node_id)


## Activate power node in grid.
func _activate_power_node(node_id: int) -> void:
	if _power_node_manager == null:
		return

	var node := _power_node_manager.get_node(node_id)
	if node != null:
		node.activate()


## Recalculate power distribution.
func _recalculate_power_distribution(faction_id: String) -> void:
	if _power_grid_system == null:
		return

	_power_grid_system.power_api.recalculate()

	# Check for power restoration in districts
	_check_power_restoration(faction_id)


## Check if any districts have power restored.
func _check_power_restoration(faction_id: String) -> void:
	if _power_grid_system == null:
		return

	var districts := _power_grid_system.get_faction_districts(faction_id)
	for district in districts:
		if district.has_power and not district.is_blackout:
			power_restoration_triggered.emit(district.district_id)


## Handle pathway repair at position.
func _handle_pathway_repair(position: Vector3i) -> void:
	pathway_repaired.emit(position)

	if _batch_updates:
		_queue_pathfinding_update(position)
	else:
		_update_pathfinding_at_position(position)

	repair_integration_completed.emit("pathway", 0)


## Handle pathway repair.
func on_pathway_repaired(position: Vector3i) -> void:
	_handle_pathway_repair(position)


## Queue pathfinding update for position.
func _queue_pathfinding_update(position: Vector3i) -> void:
	# Convert to chunk coordinates
	var chunk_id := _get_chunk_id(position)

	if not _pending_pathfinding_chunks.has(chunk_id):
		_pending_pathfinding_chunks.append(chunk_id)
		pathfinding_update_queued.emit(chunk_id)


## Get chunk ID for position.
func _get_chunk_id(position: Vector3i) -> Vector3i:
	const CHUNK_SIZE := 16
	return Vector3i(
		int(floor(float(position.x) / CHUNK_SIZE)),
		int(floor(float(position.y) / CHUNK_SIZE)),
		int(floor(float(position.z) / CHUNK_SIZE))
	)


## Update pathfinding at position.
func _update_pathfinding_at_position(position: Vector3i) -> void:
	if _pathfinding_system == null:
		return

	var chunk_id := _get_chunk_id(position)
	_mark_chunk_dirty(chunk_id)
	_recalculate_paths_in_area(position)


## Mark pathfinding chunk as dirty.
func _mark_chunk_dirty(chunk_id: Vector3i) -> void:
	# Interface with pathfinding system
	# This would call pathfinding_system.mark_chunk_dirty(chunk_id)
	pass


## Recalculate paths for units in area.
func _recalculate_paths_in_area(position: Vector3i) -> void:
	if _unit_manager == null:
		return

	# Get units near position and queue path recalculation
	# This would iterate nearby units and add them to pending recalculations
	pass


## Handle structure repair.
func _handle_structure_repair(position: Vector3i) -> void:
	# Generic structure repair - may affect both power and pathfinding
	_queue_pathfinding_update(position)


## Handle generic voxel repair.
func _handle_generic_repair(position: Vector3i) -> void:
	# Check if this affects navigation
	_queue_pathfinding_update(position)


# ============================================
# BATCH UPDATE PROCESSING
# ============================================

## Process pending updates (call each frame).
func process_pending_updates() -> void:
	if not _batch_updates:
		return

	var processed := 0

	# Process power updates
	var power_factions: Dictionary = {}
	while not _pending_power_updates.is_empty() and processed < _max_updates_per_frame:
		var node_id: int = _pending_power_updates.pop_front()
		_activate_power_node(node_id)

		if _power_node_manager != null:
			var node := _power_node_manager.get_node(node_id)
			if node != null:
				power_factions[node.faction_id] = true

		processed += 1

	# Recalculate power for affected factions
	for faction_id in power_factions:
		_recalculate_power_distribution(faction_id)

	# Process pathfinding updates
	while not _pending_pathfinding_chunks.is_empty() and processed < _max_updates_per_frame:
		var chunk_id: Vector3i = _pending_pathfinding_chunks.pop_front()
		_mark_chunk_dirty(chunk_id)
		processed += 1

	# Process unit path recalculations
	while not _pending_unit_recalculations.is_empty() and processed < _max_updates_per_frame:
		var unit_id: int = _pending_unit_recalculations.pop_front()
		_recalculate_unit_path(unit_id)
		processed += 1


## Recalculate path for specific unit.
func _recalculate_unit_path(unit_id: int) -> void:
	# Interface with unit/pathfinding system
	pass


## Force process all pending updates.
func force_process_all() -> void:
	var old_batch := _batch_updates
	_batch_updates = false

	while not _pending_power_updates.is_empty():
		var node_id: int = _pending_power_updates.pop_front()
		_activate_power_node(node_id)

	if _power_grid_system != null:
		_power_grid_system.power_api.recalculate()

	while not _pending_pathfinding_chunks.is_empty():
		var chunk_id: Vector3i = _pending_pathfinding_chunks.pop_front()
		_mark_chunk_dirty(chunk_id)

	while not _pending_unit_recalculations.is_empty():
		var unit_id: int = _pending_unit_recalculations.pop_front()
		_recalculate_unit_path(unit_id)

	_batch_updates = old_batch


## Get pending update counts.
func get_pending_counts() -> Dictionary:
	return {
		"power_updates": _pending_power_updates.size(),
		"pathfinding_chunks": _pending_pathfinding_chunks.size(),
		"unit_recalculations": _pending_unit_recalculations.size()
	}


## Check if has pending updates.
func has_pending_updates() -> bool:
	return (not _pending_power_updates.is_empty() or
			not _pending_pathfinding_chunks.is_empty() or
			not _pending_unit_recalculations.is_empty())


# ============================================
# SERIALIZATION
# ============================================

func to_dict() -> Dictionary:
	var power_updates: Array = []
	for id in _pending_power_updates:
		power_updates.append(id)

	var pathfinding_chunks: Array = []
	for chunk in _pending_pathfinding_chunks:
		pathfinding_chunks.append({"x": chunk.x, "y": chunk.y, "z": chunk.z})

	var unit_recalcs: Array = []
	for id in _pending_unit_recalculations:
		unit_recalcs.append(id)

	return {
		"pending_power_updates": power_updates,
		"pending_pathfinding_chunks": pathfinding_chunks,
		"pending_unit_recalculations": unit_recalcs,
		"batch_updates": _batch_updates,
		"max_updates_per_frame": _max_updates_per_frame
	}


func from_dict(data: Dictionary) -> void:
	_pending_power_updates.clear()
	for id in data.get("pending_power_updates", []):
		_pending_power_updates.append(int(id))

	_pending_pathfinding_chunks.clear()
	for chunk_data in data.get("pending_pathfinding_chunks", []):
		_pending_pathfinding_chunks.append(Vector3i(
			chunk_data.get("x", 0),
			chunk_data.get("y", 0),
			chunk_data.get("z", 0)
		))

	_pending_unit_recalculations.clear()
	for id in data.get("pending_unit_recalculations", []):
		_pending_unit_recalculations.append(int(id))

	_batch_updates = data.get("batch_updates", true)
	_max_updates_per_frame = data.get("max_updates_per_frame", 5)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"batch_updates": _batch_updates,
		"max_per_frame": _max_updates_per_frame,
		"pending": get_pending_counts(),
		"has_power_manager": _power_node_manager != null,
		"has_power_grid": _power_grid_system != null,
		"has_pathfinding": _pathfinding_system != null,
		"has_unit_manager": _unit_manager != null
	}
