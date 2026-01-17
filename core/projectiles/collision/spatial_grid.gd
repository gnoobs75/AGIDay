class_name ProjectileSpatialGrid
extends RefCounted
## ProjectileSpatialGrid provides efficient spatial partitioning for collision detection.
## Reduces O(n*m) collision checks to O(region_n * region_m).
##
## PERFORMANCE OPTIMIZED: Uses Vector3i keys instead of string concatenation.
## This avoids thousands of string allocations per frame for 10,000+ projectiles.

## Cell size in world units
var cell_size: float = 32.0

## Inverse cell size (cached for faster division)
var _inv_cell_size: float = 1.0 / 32.0

## Grid cells (cell_key -> Array of entity IDs)
var _cells: Dictionary = {}  ## Vector3i -> Array[int]

## Entity positions (entity_id -> Vector3)
var _entity_positions: Dictionary = {}

## Entity cell keys (entity_id -> Vector3i)
var _entity_cells: Dictionary = {}


func _init(grid_cell_size: float = 32.0) -> void:
	cell_size = grid_cell_size
	_inv_cell_size = 1.0 / grid_cell_size


## Insert entity into grid.
func insert(entity_id: int, position: Vector3) -> void:
	var cell_key := _get_cell_key(position)

	# Remove from old cell if exists
	if _entity_cells.has(entity_id):
		var old_key: Vector3i = _entity_cells[entity_id]
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
		var old_key: Vector3i = _entity_cells[entity_id]

		if old_key != new_cell_key:
			# Cell changed, update
			if _cells.has(old_key):
				_cells[old_key].erase(entity_id)
				# Clean up empty cells to prevent memory growth
				if _cells[old_key].is_empty():
					_cells.erase(old_key)

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
		var cell_key: Vector3i = _entity_cells[entity_id]
		if _cells.has(cell_key):
			_cells[cell_key].erase(entity_id)
			# Clean up empty cells to prevent memory growth
			if _cells[cell_key].is_empty():
				_cells.erase(cell_key)

		_entity_cells.erase(entity_id)
	_entity_positions.erase(entity_id)


## Query entities in radius.
func query_radius(center: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	var radius_squared := radius * radius

	# Get cell range that could contain entities in radius
	var min_cx := int(floor((center.x - radius) * _inv_cell_size))
	var max_cx := int(floor((center.x + radius) * _inv_cell_size))
	var min_cy := int(floor((center.y - radius) * _inv_cell_size))
	var max_cy := int(floor((center.y + radius) * _inv_cell_size))
	var min_cz := int(floor((center.z - radius) * _inv_cell_size))
	var max_cz := int(floor((center.z + radius) * _inv_cell_size))

	# Check entities in those cells
	var checked: Dictionary = {}

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			for cz in range(min_cz, max_cz + 1):
				var cell_key := Vector3i(cx, cy, cz)
				if not _cells.has(cell_key):
					continue

				var entities: Array = _cells[cell_key]
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
	var min_cx := int(floor(min_pos.x * _inv_cell_size))
	var max_cx := int(floor(max_pos.x * _inv_cell_size))
	var min_cy := int(floor(min_pos.y * _inv_cell_size))
	var max_cy := int(floor(max_pos.y * _inv_cell_size))
	var min_cz := int(floor(min_pos.z * _inv_cell_size))
	var max_cz := int(floor(max_pos.z * _inv_cell_size))

	var checked: Dictionary = {}

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			for cz in range(min_cz, max_cz + 1):
				var cell_key := Vector3i(cx, cy, cz)
				if not _cells.has(cell_key):
					continue

				var entities: Array = _cells[cell_key]
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


## Get entities in specific cell (by Vector3i key).
func get_entities_in_cell_v3i(cell_key: Vector3i) -> Array[int]:
	var result: Array[int] = []
	if _cells.has(cell_key):
		var entities: Array = _cells[cell_key]
		for entity_id in entities:
			result.append(entity_id)
	return result


## Get entities in specific cell (legacy string interface for compatibility).
func get_entities_in_cell(cell_key_str: String) -> Array[int]:
	# Parse string key "x,y,z" to Vector3i
	var parts := cell_key_str.split(",")
	if parts.size() != 3:
		return []
	var cell_key := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	return get_entities_in_cell_v3i(cell_key)


## Get cell key for position (Vector3i - fast, no allocation).
func _get_cell_key(position: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(position.x * _inv_cell_size)),
		int(floor(position.y * _inv_cell_size)),
		int(floor(position.z * _inv_cell_size))
	)


## Get cell key as string (legacy - avoid in hot paths).
func get_cell_key_string(position: Vector3) -> String:
	var key := _get_cell_key(position)
	return "%d,%d,%d" % [key.x, key.y, key.z]


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


## Batch update multiple entities (more efficient than individual updates).
func batch_update(updates: Array) -> void:
	## updates is Array of {entity_id: int, position: Vector3}
	for update_data in updates:
		var entity_id: int = update_data.entity_id
		var new_position: Vector3 = update_data.position
		update(entity_id, new_position)


## Batch insert multiple entities.
func batch_insert(entities: Array) -> void:
	## entities is Array of {entity_id: int, position: Vector3}
	for entity_data in entities:
		var entity_id: int = entity_data.entity_id
		var position: Vector3 = entity_data.position
		insert(entity_id, position)


## Batch remove multiple entities.
func batch_remove(entity_ids: Array[int]) -> void:
	for entity_id in entity_ids:
		remove(entity_id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var non_empty_cells := 0
	var max_entities_per_cell := 0
	var total_entities_in_cells := 0

	for cell_key in _cells:
		var count: int = _cells[cell_key].size()
		if count > 0:
			non_empty_cells += 1
			total_entities_in_cells += count
			max_entities_per_cell = maxi(max_entities_per_cell, count)

	var avg_per_cell := 0.0
	if non_empty_cells > 0:
		avg_per_cell = float(total_entities_in_cells) / float(non_empty_cells)

	return {
		"entity_count": _entity_positions.size(),
		"total_cells": _cells.size(),
		"non_empty_cells": non_empty_cells,
		"max_entities_per_cell": max_entities_per_cell,
		"avg_entities_per_cell": avg_per_cell,
		"cell_size": cell_size
	}
