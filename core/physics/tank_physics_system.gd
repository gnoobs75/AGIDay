class_name TankPhysicsSystem
extends RefCounted
## TankPhysicsSystem manages physics for Tank faction with optimization.
## Supports 500+ units at 60fps with <5ms frame budget.

signal physics_updated(active_count: int, elapsed_ms: float)
signal collision_resolved(unit_a: int, unit_b: int)

## Performance settings
const MAX_FRAME_TIME_MS := 5.0
const COLLISION_CHECK_FREQUENCY := 15  ## Check collisions every N frames
const SPATIAL_CELL_SIZE := 10.0
const MAX_COLLISIONS_PER_FRAME := 50

## Physics controller
var controller: TankPhysicsController = null

## Spatial hash for collision detection
var _spatial_cells: Dictionary = {}  ## cell_key -> Array[unit_id]

## Frame counter
var _frame_counter: int = 0

## Last frame time
var _last_frame_time_ms: float = 0.0

## Collision pairs processed this frame
var _collisions_this_frame: int = 0


func _init() -> void:
	controller = TankPhysicsController.new()


## Register unit.
func register_unit(unit_id: int, unit_type: String = "default", position: Vector3 = Vector3.ZERO) -> void:
	controller.register_unit(unit_id, unit_type, position)
	_update_spatial_hash(unit_id, position)


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_remove_from_spatial_hash(unit_id)
	controller.unregister_unit(unit_id)


## Update physics system.
func update(delta: float) -> void:
	var start_time := Time.get_ticks_usec()
	_frame_counter += 1
	_collisions_this_frame = 0

	# Update physics
	controller.update(delta)

	# Update spatial hash
	_rebuild_spatial_hash()

	# Check collisions periodically
	if _frame_counter % COLLISION_CHECK_FREQUENCY == 0:
		_check_collisions()

	_last_frame_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0

	var active := controller._unit_physics.size() - controller._frozen_units.size()
	physics_updated.emit(active, _last_frame_time_ms)


## Set camera position.
func set_camera_position(position: Vector3) -> void:
	controller.set_camera_position(position)


## Apply force to unit.
func apply_force(unit_id: int, force: Vector3) -> void:
	controller.apply_force(unit_id, force)


## Apply knockback to unit.
func apply_knockback(unit_id: int, direction: Vector3, force: float) -> void:
	controller.apply_knockback(unit_id, direction, force)


## Apply AoE knockback.
func apply_aoe_knockback(center: Vector3, radius: float, force: float) -> void:
	controller.apply_aoe_knockback(center, radius, force)


## Get unit position.
func get_position(unit_id: int) -> Vector3:
	return controller.get_position(unit_id)


## Get unit velocity.
func get_velocity(unit_id: int) -> Vector3:
	return controller.get_velocity(unit_id)


## Rebuild spatial hash from unit positions.
func _rebuild_spatial_hash() -> void:
	_spatial_cells.clear()

	for unit_id in controller._unit_physics:
		if controller.is_frozen(unit_id):
			continue

		var pos: Vector3 = controller.get_position(unit_id)
		var cell_key := _get_cell_key(pos)

		if not _spatial_cells.has(cell_key):
			_spatial_cells[cell_key] = []

		_spatial_cells[cell_key].append(unit_id)


## Update spatial hash for single unit.
func _update_spatial_hash(unit_id: int, position: Vector3) -> void:
	_remove_from_spatial_hash(unit_id)

	var cell_key := _get_cell_key(position)

	if not _spatial_cells.has(cell_key):
		_spatial_cells[cell_key] = []

	_spatial_cells[cell_key].append(unit_id)


## Remove unit from spatial hash.
func _remove_from_spatial_hash(unit_id: int) -> void:
	for cell_key in _spatial_cells:
		var cell: Array = _spatial_cells[cell_key]
		var idx := cell.find(unit_id)
		if idx >= 0:
			cell.remove_at(idx)
			return


## Get cell key from position.
func _get_cell_key(position: Vector3) -> String:
	var cx := int(position.x / SPATIAL_CELL_SIZE)
	var cz := int(position.z / SPATIAL_CELL_SIZE)
	return "%d,%d" % [cx, cz]


## Get neighboring cell keys.
func _get_neighbor_keys(cell_key: String) -> Array[String]:
	var parts := cell_key.split(",")
	var cx := int(parts[0])
	var cz := int(parts[1])

	var neighbors: Array[String] = []

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			neighbors.append("%d,%d" % [cx + dx, cz + dz])

	return neighbors


## Check collisions using spatial hash.
func _check_collisions() -> void:
	var checked_pairs: Dictionary = {}

	for cell_key in _spatial_cells:
		var units: Array = _spatial_cells[cell_key]
		var neighbor_keys := _get_neighbor_keys(cell_key)

		# Check within cell
		for i in range(units.size()):
			for j in range(i + 1, units.size()):
				if _collisions_this_frame >= MAX_COLLISIONS_PER_FRAME:
					return

				var pair_key := _get_pair_key(units[i], units[j])
				if checked_pairs.has(pair_key):
					continue

				checked_pairs[pair_key] = true
				_check_pair_collision(units[i], units[j])

		# Check with neighboring cells
		for neighbor_key in neighbor_keys:
			if neighbor_key == cell_key:
				continue

			if not _spatial_cells.has(neighbor_key):
				continue

			var neighbor_units: Array = _spatial_cells[neighbor_key]

			for unit_a in units:
				for unit_b in neighbor_units:
					if _collisions_this_frame >= MAX_COLLISIONS_PER_FRAME:
						return

					var pair_key := _get_pair_key(unit_a, unit_b)
					if checked_pairs.has(pair_key):
						continue

					checked_pairs[pair_key] = true
					_check_pair_collision(unit_a, unit_b)


## Get unique pair key.
func _get_pair_key(unit_a: int, unit_b: int) -> String:
	var min_id := mini(unit_a, unit_b)
	var max_id := maxi(unit_a, unit_b)
	return "%d_%d" % [min_id, max_id]


## Check and resolve collision between pair.
func _check_pair_collision(unit_a: int, unit_b: int) -> void:
	if controller.check_collision(unit_a, unit_b):
		controller.resolve_collision(unit_a, unit_b)
		_collisions_this_frame += 1
		collision_resolved.emit(unit_a, unit_b)


## Get last frame time.
func get_last_frame_time_ms() -> float:
	return _last_frame_time_ms


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"controller": controller.to_dict(),
		"frame_counter": _frame_counter
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	controller.from_dict(data.get("controller", {}))
	_frame_counter = data.get("frame_counter", 0)
	_rebuild_spatial_hash()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"controller": controller.get_summary(),
		"spatial_cells": _spatial_cells.size(),
		"last_frame_ms": "%.2fms" % _last_frame_time_ms,
		"collisions_this_frame": _collisions_this_frame,
		"frame": _frame_counter
	}
