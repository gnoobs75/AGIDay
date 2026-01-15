class_name VoxelPathfinding
extends RefCounted
## VoxelPathfinding integrates voxel destruction with unit navigation.
## Updates pathfinding when voxels change and handles unit type traversability.

signal traversability_changed(position: Vector3i, old_state: int, new_state: int)
signal chunk_dirty(chunk_pos: Vector2i)
signal units_need_reroute(unit_ids: Array)
signal path_invalidated(unit_id: int)

## Unit size categories
enum UnitSize {
	SMALL,   ## Zerg swarms, Dynapods scouts
	MEDIUM,  ## Standard infantry
	LARGE,   ## Tanks, LogiBots
	FLYING   ## Aerial units
}

## Voxel damage stages (from VoxelState)
const STAGE_INTACT := 0
const STAGE_CRACKED := 1
const STAGE_RUBBLE := 2
const STAGE_CRATER := 3

## Configuration
const AFFECTED_UNIT_RADIUS := 5.0     ## Units within this radius get notified
const CHUNK_SIZE := 32                 ## Voxels per chunk
const MAX_DIRTY_CHUNKS_PER_FRAME := 4  ## Limit chunk updates per frame

## Traversability costs by voxel state and unit size
const TRAVERSABILITY_COSTS := {
	UnitSize.SMALL: {
		STAGE_INTACT: INF,     ## Blocked
		STAGE_CRACKED: INF,    ## Blocked
		STAGE_RUBBLE: INF,     ## Blocked
		STAGE_CRATER: 1.0      ## Free passage
	},
	UnitSize.MEDIUM: {
		STAGE_INTACT: INF,
		STAGE_CRACKED: INF,
		STAGE_RUBBLE: INF,
		STAGE_CRATER: 1.0
	},
	UnitSize.LARGE: {
		STAGE_INTACT: INF,
		STAGE_CRACKED: INF,
		STAGE_RUBBLE: 2.0,     ## Can pass with penalty
		STAGE_CRATER: 1.0
	},
	UnitSize.FLYING: {
		STAGE_INTACT: 1.0,     ## Unaffected
		STAGE_CRACKED: 1.0,
		STAGE_RUBBLE: 1.0,
		STAGE_CRATER: 1.0
	}
}

## Unit size classifications by type
var _unit_sizes: Dictionary = {}  ## unit_type -> UnitSize

## Dirty chunks needing pathfinding update
var _dirty_chunks: Array[Vector2i] = []

## Unit positions for affected notifications
var _unit_positions: Dictionary = {}  ## unit_id -> {position, size, path}

## Voxel state cache
var _voxel_states: Dictionary = {}  ## Vector3i -> stage


func _init() -> void:
	_setup_default_unit_sizes()


## Setup default unit size classifications.
func _setup_default_unit_sizes() -> void:
	# Aether Swarm - Small (zerg-like)
	_unit_sizes["aether_drone"] = UnitSize.SMALL
	_unit_sizes["aether_scout"] = UnitSize.SMALL
	_unit_sizes["aether_infiltrator"] = UnitSize.SMALL
	_unit_sizes["aether_phaser"] = UnitSize.SMALL

	# OptiForge Legion - Medium
	_unit_sizes["opti_grunt"] = UnitSize.MEDIUM
	_unit_sizes["opti_soldier"] = UnitSize.MEDIUM
	_unit_sizes["opti_heavy"] = UnitSize.LARGE
	_unit_sizes["opti_elite"] = UnitSize.MEDIUM

	# Dynapods Vanguard - Small/Medium
	_unit_sizes["dyna_runner"] = UnitSize.SMALL
	_unit_sizes["dyna_striker"] = UnitSize.MEDIUM
	_unit_sizes["dyna_acrobat"] = UnitSize.SMALL
	_unit_sizes["dyna_juggernaut"] = UnitSize.LARGE

	# LogiBots Colossus - Large
	_unit_sizes["logi_worker"] = UnitSize.MEDIUM
	_unit_sizes["logi_defender"] = UnitSize.LARGE
	_unit_sizes["logi_artillery"] = UnitSize.LARGE
	_unit_sizes["logi_titan"] = UnitSize.LARGE

	# Human Remnant
	_unit_sizes["human_soldier"] = UnitSize.MEDIUM
	_unit_sizes["human_heavy"] = UnitSize.LARGE
	_unit_sizes["human_vehicle"] = UnitSize.LARGE


## Register unit type with size category.
func register_unit_type(unit_type: String, size: UnitSize) -> void:
	_unit_sizes[unit_type] = size


## Get unit size for type.
func get_unit_size(unit_type: String) -> UnitSize:
	return _unit_sizes.get(unit_type, UnitSize.MEDIUM)


## Check if unit can traverse voxel at position.
func can_traverse(unit_type: String, position: Vector3i) -> bool:
	var size := get_unit_size(unit_type)
	var cost := get_traversal_cost(size, position)
	return cost < INF


## Get traversal cost for unit size at position.
func get_traversal_cost(size: UnitSize, position: Vector3i) -> float:
	var stage: int = _voxel_states.get(position, STAGE_CRATER)  # Default to passable
	var costs: Dictionary = TRAVERSABILITY_COSTS.get(size, {})
	return costs.get(stage, INF)


## Handle voxel state change event.
func on_voxel_state_changed(position: Vector3i, old_stage: int, new_stage: int) -> void:
	_voxel_states[position] = new_stage

	# Check if traversability changed for any unit size
	var traversability_changed_flag := false

	for size in UnitSize.values():
		var old_cost: float = TRAVERSABILITY_COSTS[size].get(old_stage, INF)
		var new_cost: float = TRAVERSABILITY_COSTS[size].get(new_stage, INF)

		var old_passable := old_cost < INF
		var new_passable := new_cost < INF

		if old_passable != new_passable:
			traversability_changed_flag = true
			break

	if traversability_changed_flag:
		traversability_changed.emit(position, old_stage, new_stage)

		# Mark chunk as dirty
		var chunk_pos := _position_to_chunk(position)
		if chunk_pos not in _dirty_chunks:
			_dirty_chunks.append(chunk_pos)
			chunk_dirty.emit(chunk_pos)

		# Notify affected units
		_notify_affected_units(position)


## Convert voxel position to chunk position.
func _position_to_chunk(position: Vector3i) -> Vector2i:
	return Vector2i(position.x / CHUNK_SIZE, position.z / CHUNK_SIZE)


## Notify units within radius of position change.
func _notify_affected_units(position: Vector3i) -> void:
	var world_pos := Vector3(position.x, position.y, position.z)
	var affected_ids: Array = []

	for unit_id in _unit_positions:
		var unit_data: Dictionary = _unit_positions[unit_id]
		var unit_pos: Vector3 = unit_data.get("position", Vector3.INF)

		if world_pos.distance_to(unit_pos) <= AFFECTED_UNIT_RADIUS:
			affected_ids.append(unit_id)

	if not affected_ids.is_empty():
		units_need_reroute.emit(affected_ids)


## Register unit for path tracking.
func register_unit(unit_id: int, unit_type: String, position: Vector3) -> void:
	_unit_positions[unit_id] = {
		"position": position,
		"size": get_unit_size(unit_type),
		"type": unit_type,
		"path": []
	}


## Update unit position.
func update_unit_position(unit_id: int, position: Vector3) -> void:
	if _unit_positions.has(unit_id):
		_unit_positions[unit_id]["position"] = position


## Set unit path.
func set_unit_path(unit_id: int, path: Array) -> void:
	if _unit_positions.has(unit_id):
		_unit_positions[unit_id]["path"] = path


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_positions.erase(unit_id)


## Check if unit's current path is still valid.
func is_path_valid(unit_id: int) -> bool:
	if not _unit_positions.has(unit_id):
		return false

	var unit_data: Dictionary = _unit_positions[unit_id]
	var path: Array = unit_data.get("path", [])
	var size: UnitSize = unit_data.get("size", UnitSize.MEDIUM)

	for waypoint in path:
		if waypoint is Vector3:
			var voxel_pos := Vector3i(int(waypoint.x), int(waypoint.y), int(waypoint.z))
			if get_traversal_cost(size, voxel_pos) >= INF:
				path_invalidated.emit(unit_id)
				return false

	return true


## Process dirty chunks (call each frame).
func process_dirty_chunks() -> int:
	var processed := 0

	while not _dirty_chunks.is_empty() and processed < MAX_DIRTY_CHUNKS_PER_FRAME:
		var chunk_pos: Vector2i = _dirty_chunks.pop_front()
		_process_chunk_pathfinding(chunk_pos)
		processed += 1

	return processed


## Process pathfinding update for chunk.
func _process_chunk_pathfinding(chunk_pos: Vector2i) -> void:
	# This would integrate with actual pathfinding system
	# For now, just notify of update
	pass


## Get pathfinding cost grid for area.
func get_cost_grid(min_pos: Vector2i, max_pos: Vector2i, unit_size: UnitSize) -> Array:
	var grid := []

	for x in range(min_pos.x, max_pos.x + 1):
		var row := []
		for z in range(min_pos.y, max_pos.y + 1):
			# Check ground level (y=0) by default
			var voxel_pos := Vector3i(x, 0, z)
			var cost := get_traversal_cost(unit_size, voxel_pos)
			row.append(cost)
		grid.append(row)

	return grid


## Set voxel state (for initialization).
func set_voxel_state(position: Vector3i, stage: int) -> void:
	_voxel_states[position] = stage


## Bulk set voxel states.
func set_voxel_states_bulk(states: Dictionary) -> void:
	for pos in states:
		_voxel_states[pos] = states[pos]


## Get pending dirty chunk count.
func get_dirty_chunk_count() -> int:
	return _dirty_chunks.size()


## Get registered unit count.
func get_registered_unit_count() -> int:
	return _unit_positions.size()


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"registered_units": _unit_positions.size(),
		"dirty_chunks": _dirty_chunks.size(),
		"voxel_states_cached": _voxel_states.size(),
		"unit_types_registered": _unit_sizes.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var states_serialized := {}
	for pos in _voxel_states:
		states_serialized["%d,%d,%d" % [pos.x, pos.y, pos.z]] = _voxel_states[pos]

	return {
		"voxel_states": states_serialized,
		"dirty_chunks": _dirty_chunks.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_voxel_states.clear()

	var states_data: Dictionary = data.get("voxel_states", {})
	for key in states_data:
		var parts: PackedStringArray = key.split(",")
		var pos := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		_voxel_states[pos] = states_data[key]

	_dirty_chunks.clear()
	for chunk in data.get("dirty_chunks", []):
		if chunk is Vector2i:
			_dirty_chunks.append(chunk)
		elif chunk is Dictionary:
			_dirty_chunks.append(Vector2i(chunk.get("x", 0), chunk.get("y", 0)))
