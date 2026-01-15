class_name ProjectileSpatialGrid
extends RefCounted
## ProjectileSpatialGrid provides efficient spatial partitioning for collision detection.
## Reduces O(n*m) collision checks to O(region_n * region_m).

## Cell size in world units
var cell_size: float = 32.0

## Grid cells (cell_key -> Array of entity IDs)
var _cells: Dictionary = {}

## Entity positions (entity_id -> Vector3)
var _entity_positions: Dictionary = {}

## Entity cell keys (entity_id -> cell_key)
var _entity_cells: Dictionary = {}


func _init(grid_cell_size: float = 32.0) -> void:
	cell_size = grid_cell_size


## Insert entity into grid.
func insert(entity_id: int, position: Vector3) -> void:
	var cell_key := _get_cell_key(position)

	# Remove from old cell if exists
	if _entity_cells.has(entity_id):
		var old_key: String = _entity_cells[entity_id]
		if _cells.has(old_key):
			_cells[old_key].erase(entity_id)

	# Add to new cell
	if not _cells.has(cell_key):
		_cells[cell_key] = []
	_cells[cell_key].append(entity_id)

	_entity_positions[entity_id] = position
	_entity_cells[entity_id] = cell_key


## Update entity position.
func update(entity_id: int, new_position: Vector3) -> void:
	var new_cell_key := _get_cell_key(new_position)

	if _entity_cells.has(entity_id):
		var old_key: String = _entity_cells[entity_id]

		if old_key != new_cell_key:
			# Cell changed, update
			if _cells.has(old_key):
				_cells[old_key].erase(entity_id)

			if not _cells.has(new_cell_key):
				_cells[new_cell_key] = []
			_cells[new_cell_key].append(entity_id)

			_entity_cells[entity_id] = new_cell_key

	else:
		# New entity
		insert(entity_id, new_position)

	_entity_positions[entity_id] = new_position


## Remove entity from grid.
func remove(entity_id: int) -> void:
	if _entity_cells.has(entity_id):
		var cell_key: String = _entity_cells[entity_id]
		if _cells.has(cell_key):
			_cells[cell_key].erase(entity_id)

		_entity_cells.erase(entity_id)
	_entity_positions.erase(entity_id)


## Query entities in radius.
func query_radius(center: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	var radius_squared := radius * radius

	# Get cells that could contain entities in radius
	var cell_keys := _get_cells_in_radius(center, radius)

	# Check entities in those cells
	var checked: Dictionary = {}
	for cell_key in cell_keys:
		var entities: Array = _cells.get(cell_key, [])
		for entity_id in entities:
			if checked.has(entity_id):
				continue
			checked[entity_id] = true

			var pos: Vector3 = _entity_positions.get(entity_id, Vector3.INF)
			if pos != Vector3.INF:
				var dist_sq := pos.distance_squared_to(center)
				if dist_sq <= radius_squared:
					result.append(entity_id)

	return result


## Query entities in AABB.
func query_aabb(min_pos: Vector3, max_pos: Vector3) -> Array[int]:
	var result: Array[int] = []

	# Get cells that overlap AABB
	var min_cx := int(floor(min_pos.x / cell_size))
	var max_cx := int(floor(max_pos.x / cell_size))
	var min_cy := int(floor(min_pos.y / cell_size))
	var max_cy := int(floor(max_pos.y / cell_size))
	var min_cz := int(floor(min_pos.z / cell_size))
	var max_cz := int(floor(max_pos.z / cell_size))

	var checked: Dictionary = {}

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			for cz in range(min_cz, max_cz + 1):
				var cell_key := "%d,%d,%d" % [cx, cy, cz]
				var entities: Array = _cells.get(cell_key, [])

				for entity_id in entities:
					if checked.has(entity_id):
						continue
					checked[entity_id] = true

					var pos: Vector3 = _entity_positions.get(entity_id, Vector3.INF)
					if pos != Vector3.INF:
						if pos.x >= min_pos.x and pos.x <= max_pos.x and \
						   pos.y >= min_pos.y and pos.y <= max_pos.y and \
						   pos.z >= min_pos.z and pos.z <= max_pos.z:
							result.append(entity_id)

	return result


## Get entity position.
func get_position(entity_id: int) -> Vector3:
	return _entity_positions.get(entity_id, Vector3.INF)


## Check if entity exists.
func has_entity(entity_id: int) -> bool:
	return _entity_positions.has(entity_id)


## Get entities in specific cell.
func get_entities_in_cell(cell_key: String) -> Array[int]:
	var result: Array[int] = []
	var entities: Array = _cells.get(cell_key, [])
	for entity_id in entities:
		result.append(entity_id)
	return result


## Get cell key for position.
func _get_cell_key(position: Vector3) -> String:
	var cx := int(floor(position.x / cell_size))
	var cy := int(floor(position.y / cell_size))
	var cz := int(floor(position.z / cell_size))
	return "%d,%d,%d" % [cx, cy, cz]


## Get cells in radius.
func _get_cells_in_radius(center: Vector3, radius: float) -> Array[String]:
	var cells: Array[String] = []

	var min_cx := int(floor((center.x - radius) / cell_size))
	var max_cx := int(floor((center.x + radius) / cell_size))
	var min_cy := int(floor((center.y - radius) / cell_size))
	var max_cy := int(floor((center.y + radius) / cell_size))
	var min_cz := int(floor((center.z - radius) / cell_size))
	var max_cz := int(floor((center.z + radius) / cell_size))

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			for cz in range(min_cz, max_cz + 1):
				cells.append("%d,%d,%d" % [cx, cy, cz])

	return cells


## Clear all entities.
func clear() -> void:
	_cells.clear()
	_entity_positions.clear()
	_entity_cells.clear()


## Get entity count.
func get_entity_count() -> int:
	return _entity_positions.size()


## Get cell count.
func get_cell_count() -> int:
	return _cells.size()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var non_empty_cells := 0
	var max_entities_per_cell := 0

	for cell_key in _cells:
		var count: int = _cells[cell_key].size()
		if count > 0:
			non_empty_cells += 1
			max_entities_per_cell = maxi(max_entities_per_cell, count)

	return {
		"entity_count": _entity_positions.size(),
		"total_cells": _cells.size(),
		"non_empty_cells": non_empty_cells,
		"max_entities_per_cell": max_entities_per_cell,
		"cell_size": cell_size
	}
