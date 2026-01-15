class_name VoxelPathfindingBridge
extends RefCounted
## VoxelPathfindingBridge connects voxel destruction to navigation updates.
## Batches and optimizes navmesh rebake requests for changed regions.

signal navmesh_update_requested(region_aabb: AABB)
signal blocked_cells_changed(positions: Array[Vector3i])

## Minimum time between navmesh updates for same region
const UPDATE_COOLDOWN := 0.5

## Maximum pending updates before forced flush
const MAX_PENDING_UPDATES := 100

## Cell size for navmesh grid
const NAV_CELL_SIZE := 2.0

## Reference to voxel system
var _voxel_system: VoxelSystem = null

## Pending cell updates
var _pending_cells: Dictionary = {}  ## "x,z" -> Vector3i

## Region update cooldowns
var _region_cooldowns: Dictionary = {}  ## region_key -> expire_time

## Blocked cells cache
var _blocked_cells: Dictionary = {}  ## "x,z" -> true

## Current time
var _current_time: float = 0.0


func _init() -> void:
	pass


## Connect to voxel system.
func connect_to_voxel_system(voxel_system: VoxelSystem) -> void:
	_voxel_system = voxel_system
	voxel_system.set_pathfinding_callback(_on_voxel_changes)


## Handle voxel changes from voxel system.
func _on_voxel_changes(positions: Array[Vector3i]) -> void:
	for pos in positions:
		_queue_cell_update(pos)


## Queue a cell for navigation update.
func _queue_cell_update(position: Vector3i) -> void:
	var key := "%d,%d" % [position.x, position.z]
	_pending_cells[key] = position

	# Update blocked cells cache
	if _voxel_system != null:
		var is_blocked := not _voxel_system.is_traversable(position)
		if is_blocked:
			_blocked_cells[key] = true
		elif _blocked_cells.has(key):
			_blocked_cells.erase(key)

	# Force flush if too many pending
	if _pending_cells.size() >= MAX_PENDING_UPDATES:
		flush_updates()


## Process pending updates (call periodically).
func process(delta: float) -> void:
	_current_time += delta

	# Clean up expired cooldowns
	var expired: Array = []
	for key in _region_cooldowns:
		if _current_time >= _region_cooldowns[key]:
			expired.append(key)

	for key in expired:
		_region_cooldowns.erase(key)


## Flush all pending updates.
func flush_updates() -> void:
	if _pending_cells.is_empty():
		return

	# Group cells by region
	var regions: Dictionary = {}  ## region_key -> Array[Vector3i]

	for key in _pending_cells:
		var pos: Vector3i = _pending_cells[key]
		var region_key := _get_region_key(pos)

		if not regions.has(region_key):
			regions[region_key] = []
		regions[region_key].append(pos)

	_pending_cells.clear()

	# Request updates for each region
	for region_key in regions:
		# Check cooldown
		if _region_cooldowns.has(region_key):
			if _current_time < _region_cooldowns[region_key]:
				continue

		var cells: Array = regions[region_key]
		var aabb := _calculate_region_aabb(cells)

		_region_cooldowns[region_key] = _current_time + UPDATE_COOLDOWN

		navmesh_update_requested.emit(aabb)

	# Emit blocked cells changed
	var blocked_positions: Array[Vector3i] = []
	for key in _blocked_cells:
		var parts: PackedStringArray = key.split(",")
		if parts.size() == 2:
			blocked_positions.append(Vector3i(int(parts[0]), 0, int(parts[1])))

	blocked_cells_changed.emit(blocked_positions)


## Get region key for position.
func _get_region_key(position: Vector3i) -> String:
	# Group into 16x16 regions
	var region_x := position.x / 16
	var region_z := position.z / 16
	return "%d,%d" % [region_x, region_z]


## Calculate AABB for a group of cells.
func _calculate_region_aabb(cells: Array) -> AABB:
	if cells.is_empty():
		return AABB()

	var min_pos := Vector3(INF, -10, INF)
	var max_pos := Vector3(-INF, 10, -INF)

	for pos in cells:
		var world_pos := Vector3(pos.x, 0, pos.z)
		min_pos.x = minf(min_pos.x, world_pos.x - NAV_CELL_SIZE)
		min_pos.z = minf(min_pos.z, world_pos.z - NAV_CELL_SIZE)
		max_pos.x = maxf(max_pos.x, world_pos.x + NAV_CELL_SIZE)
		max_pos.z = maxf(max_pos.z, world_pos.z + NAV_CELL_SIZE)

	return AABB(min_pos, max_pos - min_pos)


## Check if position is blocked.
func is_blocked(position: Vector3i) -> bool:
	var key := "%d,%d" % [position.x, position.z]
	return _blocked_cells.has(key)


## Get all blocked positions.
func get_blocked_positions() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for key in _blocked_cells:
		var parts: PackedStringArray = key.split(",")
		if parts.size() == 2:
			result.append(Vector3i(int(parts[0]), 0, int(parts[1])))
	return result


## Clear blocked cell at position.
func clear_blocked(position: Vector3i) -> void:
	var key := "%d,%d" % [position.x, position.z]
	_blocked_cells.erase(key)


## Force rebuild of entire navigation.
func force_full_rebuild() -> void:
	var full_aabb := AABB(
		Vector3(0, -10, 0),
		Vector3(VoxelChunkManager.WORLD_SIZE, 20, VoxelChunkManager.WORLD_SIZE)
	)
	navmesh_update_requested.emit(full_aabb)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"pending_cells": _pending_cells.size(),
		"blocked_cells": _blocked_cells.size(),
		"active_cooldowns": _region_cooldowns.size()
	}
