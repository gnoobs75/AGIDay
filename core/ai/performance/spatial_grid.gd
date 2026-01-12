class_name SpatialGrid
extends RefCounted
## SpatialGrid provides optimized spatial queries for nearby units and projectiles.
## Uses cell-based partitioning for O(1) average case lookups.

signal unit_moved(unit_id: int, old_cell: Vector2i, new_cell: Vector2i)

## Grid configuration
const DEFAULT_CELL_SIZE := 20.0  ## World units per cell

## Grid data
var _cell_size: float = DEFAULT_CELL_SIZE

## Units per cell (cell_key -> Array[int])
var _cells: Dictionary = {}

## Unit positions (unit_id -> Vector3)
var _unit_positions: Dictionary = {}

## Unit cells (unit_id -> cell_key)
var _unit_cells: Dictionary = {}

## Unit factions (unit_id -> faction_id)
var _unit_factions: Dictionary = {}

## Projectiles per cell (cell_key -> Array[int])
var _projectile_cells: Dictionary = {}


func _init(cell_size: float = DEFAULT_CELL_SIZE) -> void:
	_cell_size = cell_size


## Get cell key for world position.
func _get_cell_key(position: Vector3) -> String:
	var cell_x := int(floor(position.x / _cell_size))
	var cell_z := int(floor(position.z / _cell_size))
	return str(cell_x) + "_" + str(cell_z)


## Get cell coordinates for world position.
func _get_cell_coords(position: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(position.x / _cell_size)),
		int(floor(position.z / _cell_size))
	)


## Register unit in grid.
func register_unit(unit_id: int, position: Vector3, faction_id: String) -> void:
	var cell_key := _get_cell_key(position)

	if not _cells.has(cell_key):
		_cells[cell_key] = []

	_cells[cell_key].append(unit_id)
	_unit_positions[unit_id] = position
	_unit_cells[unit_id] = cell_key
	_unit_factions[unit_id] = faction_id


## Unregister unit from grid.
func unregister_unit(unit_id: int) -> void:
	if not _unit_cells.has(unit_id):
		return

	var cell_key: String = _unit_cells[unit_id]

	if _cells.has(cell_key):
		var idx := _cells[cell_key].find(unit_id)
		if idx != -1:
			_cells[cell_key].remove_at(idx)

	_unit_positions.erase(unit_id)
	_unit_cells.erase(unit_id)
	_unit_factions.erase(unit_id)


## Update unit position.
func update_unit_position(unit_id: int, new_position: Vector3) -> void:
	if not _unit_cells.has(unit_id):
		return

	var old_cell_key: String = _unit_cells[unit_id]
	var new_cell_key := _get_cell_key(new_position)

	_unit_positions[unit_id] = new_position

	if old_cell_key != new_cell_key:
		# Remove from old cell
		if _cells.has(old_cell_key):
			var idx := _cells[old_cell_key].find(unit_id)
			if idx != -1:
				_cells[old_cell_key].remove_at(idx)

		# Add to new cell
		if not _cells.has(new_cell_key):
			_cells[new_cell_key] = []
		_cells[new_cell_key].append(unit_id)

		_unit_cells[unit_id] = new_cell_key

		var old_coords := _get_cell_coords(_unit_positions.get(unit_id, Vector3.ZERO))
		var new_coords := _get_cell_coords(new_position)
		unit_moved.emit(unit_id, old_coords, new_coords)


## Get units in range of position.
func get_units_in_range(position: Vector3, radius: float, faction_filter: String = "") -> Array[int]:
	var result: Array[int] = []
	var cells_to_check := _get_cells_in_range(position, radius)
	var radius_sq := radius * radius

	for cell_key in cells_to_check:
		if not _cells.has(cell_key):
			continue

		for unit_id in _cells[cell_key]:
			if faction_filter != "" and _unit_factions.get(unit_id, "") != faction_filter:
				continue

			var unit_pos: Vector3 = _unit_positions.get(unit_id, Vector3.INF)
			if unit_pos == Vector3.INF:
				continue

			var dist_sq := position.distance_squared_to(unit_pos)
			if dist_sq <= radius_sq:
				result.append(unit_id)

	return result


## Get enemies in range (units with different faction).
func get_enemies_in_range(position: Vector3, radius: float, exclude_faction: String) -> Array[int]:
	var result: Array[int] = []
	var cells_to_check := _get_cells_in_range(position, radius)
	var radius_sq := radius * radius

	for cell_key in cells_to_check:
		if not _cells.has(cell_key):
			continue

		for unit_id in _cells[cell_key]:
			var unit_faction: String = _unit_factions.get(unit_id, "")
			if unit_faction == exclude_faction:
				continue

			var unit_pos: Vector3 = _unit_positions.get(unit_id, Vector3.INF)
			if unit_pos == Vector3.INF:
				continue

			var dist_sq := position.distance_squared_to(unit_pos)
			if dist_sq <= radius_sq:
				result.append(unit_id)

	return result


## Get allies in range (units with same faction).
func get_allies_in_range(position: Vector3, radius: float, faction_id: String) -> Array[int]:
	return get_units_in_range(position, radius, faction_id)


## Get cells in range of position.
func _get_cells_in_range(position: Vector3, radius: float) -> Array[String]:
	var cells: Array[String] = []
	var cell_radius := int(ceil(radius / _cell_size))
	var center_coords := _get_cell_coords(position)

	for dx in range(-cell_radius, cell_radius + 1):
		for dz in range(-cell_radius, cell_radius + 1):
			var cell_key := str(center_coords.x + dx) + "_" + str(center_coords.y + dz)
			cells.append(cell_key)

	return cells


## Get nearest enemy.
func get_nearest_enemy(position: Vector3, max_range: float, exclude_faction: String) -> int:
	var enemies := get_enemies_in_range(position, max_range, exclude_faction)

	if enemies.is_empty():
		return -1

	var nearest_id := -1
	var nearest_dist_sq := INF

	for enemy_id in enemies:
		var enemy_pos: Vector3 = _unit_positions.get(enemy_id, Vector3.INF)
		if enemy_pos == Vector3.INF:
			continue

		var dist_sq := position.distance_squared_to(enemy_pos)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest_id = enemy_id

	return nearest_id


## Get nearest enemy distance.
func get_nearest_enemy_distance(unit_id: int) -> float:
	if not _unit_positions.has(unit_id):
		return INF

	var position: Vector3 = _unit_positions[unit_id]
	var faction: String = _unit_factions.get(unit_id, "")

	var nearest := get_nearest_enemy(position, 100.0, faction)

	if nearest == -1:
		return INF

	var enemy_pos: Vector3 = _unit_positions.get(nearest, Vector3.INF)
	if enemy_pos == Vector3.INF:
		return INF

	return position.distance_to(enemy_pos)


## Register projectile.
func register_projectile(projectile_id: int, position: Vector3) -> void:
	var cell_key := _get_cell_key(position)

	if not _projectile_cells.has(cell_key):
		_projectile_cells[cell_key] = []

	_projectile_cells[cell_key].append(projectile_id)


## Unregister projectile.
func unregister_projectile(projectile_id: int, position: Vector3) -> void:
	var cell_key := _get_cell_key(position)

	if _projectile_cells.has(cell_key):
		var idx := _projectile_cells[cell_key].find(projectile_id)
		if idx != -1:
			_projectile_cells[cell_key].remove_at(idx)


## Get projectiles in range.
func get_projectiles_in_range(position: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	var cells_to_check := _get_cells_in_range(position, radius)

	for cell_key in cells_to_check:
		if _projectile_cells.has(cell_key):
			for projectile_id in _projectile_cells[cell_key]:
				result.append(projectile_id)

	return result


## Get unit position.
func get_unit_position(unit_id: int) -> Vector3:
	return _unit_positions.get(unit_id, Vector3.INF)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var occupied_cells := 0
	var max_units_per_cell := 0

	for cell_key in _cells:
		if not _cells[cell_key].is_empty():
			occupied_cells += 1
			max_units_per_cell = max(max_units_per_cell, _cells[cell_key].size())

	return {
		"cell_size": _cell_size,
		"total_units": _unit_positions.size(),
		"occupied_cells": occupied_cells,
		"max_units_per_cell": max_units_per_cell,
		"projectile_cells": _projectile_cells.size()
	}
