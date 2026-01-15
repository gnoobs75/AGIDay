class_name UnitManager
extends RefCounted
## UnitManager is the central coordinator for all unit lifecycle operations.
## Integrates spatial grid, object pooling, and provides efficient querying.

signal unit_spawned(unit_id: int, faction_id: int, unit_type: String)
signal unit_despawned(unit_id: int)
signal units_batch_spawned(unit_ids: Array[int])
signal units_batch_despawned(count: int)

## Sub-systems
var _unit_pool: UnitPool = null
var _spatial_grid: SpatialGrid = null

## Unit collections
var _units_by_id: Dictionary = {}        ## unit_id -> unit_data
var _units_by_faction: Dictionary = {}   ## faction_id -> Array[unit_id]
var _units_by_type: Dictionary = {}      ## unit_type -> Array[unit_id]

## Performance tracking
var _spawn_count := 0
var _despawn_count := 0
var _query_count := 0
var _last_spawn_time := 0.0
var _last_query_time := 0.0


func _init() -> void:
	# Initialize faction arrays
	for i in 5:
		_units_by_faction[i] = []


## Initialize with sub-systems.
func initialize(unit_pool: UnitPool = null, spatial_grid: SpatialGrid = null) -> void:
	if unit_pool != null:
		_unit_pool = unit_pool
	else:
		_unit_pool = UnitPool.new()
		_unit_pool.initialize()

	if spatial_grid != null:
		_spatial_grid = spatial_grid
	else:
		_spatial_grid = SpatialGrid.new()


## Spawn a unit.
func spawn_unit(unit_type: String, faction_id: int, position: Vector3,
				rotation: float = 0.0) -> Dictionary:
	var start_time := Time.get_ticks_usec()

	# Get from pool
	var unit := _unit_pool.get_unit(unit_type)
	if unit.is_empty():
		push_warning("UnitManager: Failed to spawn unit of type '%s'" % unit_type)
		return {}

	var unit_id: int = unit["id"]

	# Initialize unit data
	unit["faction_id"] = faction_id
	unit["position"] = position
	unit["rotation"] = rotation
	unit["is_active"] = true
	unit["created_at"] = Time.get_ticks_msec()

	# Register in collections
	_units_by_id[unit_id] = unit

	if not _units_by_faction.has(faction_id):
		_units_by_faction[faction_id] = []
	_units_by_faction[faction_id].append(unit_id)

	if not _units_by_type.has(unit_type):
		_units_by_type[unit_type] = []
	_units_by_type[unit_type].append(unit_id)

	# Register in spatial grid
	_spatial_grid.add_unit(unit_id, position)

	_spawn_count += 1
	_last_spawn_time = (Time.get_ticks_usec() - start_time) / 1000.0

	unit_spawned.emit(unit_id, faction_id, unit_type)
	return unit


## Despawn a unit.
func despawn_unit(unit_id: int) -> void:
	if not _units_by_id.has(unit_id):
		return

	var unit: Dictionary = _units_by_id[unit_id]
	var faction_id: int = unit.get("faction_id", 0)
	var unit_type: String = unit.get("type", "")

	# Remove from collections
	_units_by_id.erase(unit_id)

	if _units_by_faction.has(faction_id):
		var faction_units: Array = _units_by_faction[faction_id]
		var idx := faction_units.find(unit_id)
		if idx >= 0:
			faction_units.remove_at(idx)

	if _units_by_type.has(unit_type):
		var type_units: Array = _units_by_type[unit_type]
		var idx := type_units.find(unit_id)
		if idx >= 0:
			type_units.remove_at(idx)

	# Remove from spatial grid
	_spatial_grid.remove_unit(unit_id)

	# Return to pool
	_unit_pool.return_unit(unit_id)

	_despawn_count += 1
	unit_despawned.emit(unit_id)


## Batch spawn multiple units.
func spawn_units_batch(spawn_data: Array[Dictionary]) -> Array[int]:
	var spawned_ids: Array[int] = []

	for data in spawn_data:
		var unit := spawn_unit(
			data.get("type", ""),
			data.get("faction_id", 0),
			data.get("position", Vector3.ZERO),
			data.get("rotation", 0.0)
		)

		if not unit.is_empty():
			spawned_ids.append(unit["id"])

	units_batch_spawned.emit(spawned_ids)
	return spawned_ids


## Batch despawn multiple units.
func despawn_units_batch(unit_ids: Array[int]) -> void:
	for unit_id in unit_ids:
		despawn_unit(unit_id)

	units_batch_despawned.emit(unit_ids.size())


## Get unit by ID.
func get_unit(unit_id: int) -> Dictionary:
	_query_count += 1
	return _units_by_id.get(unit_id, {})


## Get all units for a faction.
func get_faction_units(faction_id: int) -> Array[Dictionary]:
	var start_time := Time.get_ticks_usec()
	var result: Array[Dictionary] = []

	if _units_by_faction.has(faction_id):
		for unit_id in _units_by_faction[faction_id]:
			if _units_by_id.has(unit_id):
				result.append(_units_by_id[unit_id])

	_query_count += 1
	_last_query_time = (Time.get_ticks_usec() - start_time) / 1000.0
	return result


## Get all units of a type.
func get_type_units(unit_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if _units_by_type.has(unit_type):
		for unit_id in _units_by_type[unit_type]:
			if _units_by_id.has(unit_id):
				result.append(_units_by_id[unit_id])

	_query_count += 1
	return result


## Get units within radius.
func get_units_in_radius(position: Vector3, radius: float,
						 faction_filter: int = -1) -> Array[Dictionary]:
	var start_time := Time.get_ticks_usec()
	var result: Array[Dictionary] = []

	var unit_ids: Array[int] = _spatial_grid.get_units_in_radius(position, radius)

	for unit_id in unit_ids:
		if not _units_by_id.has(unit_id):
			continue

		var unit: Dictionary = _units_by_id[unit_id]

		# Apply faction filter
		if faction_filter >= 0 and unit.get("faction_id", -1) != faction_filter:
			continue

		result.append(unit)

	_query_count += 1
	_last_query_time = (Time.get_ticks_usec() - start_time) / 1000.0
	return result


## Get nearest unit to position.
func get_nearest_unit(position: Vector3, max_radius: float = INF,
					  faction_filter: int = -1) -> Dictionary:
	var start_time := Time.get_ticks_usec()

	if faction_filter < 0:
		# No filter, use spatial grid directly
		var unit_id: int = _spatial_grid.get_nearest_unit(position, max_radius)
		_query_count += 1
		_last_query_time = (Time.get_ticks_usec() - start_time) / 1000.0

		if unit_id >= 0:
			return _units_by_id.get(unit_id, {})
		return {}

	# With faction filter, get radius and filter manually
	var units := get_units_in_radius(position, max_radius, faction_filter)
	if units.is_empty():
		return {}

	var nearest: Dictionary = {}
	var nearest_dist := INF

	for unit in units:
		var unit_pos: Vector3 = unit.get("position", Vector3.INF)
		var dist := position.distance_to(unit_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = unit

	_last_query_time = (Time.get_ticks_usec() - start_time) / 1000.0
	return nearest


## Get K nearest units.
func get_k_nearest_units(position: Vector3, k: int, max_radius: float = INF,
						 faction_filter: int = -1) -> Array[Dictionary]:
	var unit_ids: Array[int] = _spatial_grid.get_k_nearest_units(position, k, max_radius)
	var result: Array[Dictionary] = []

	for unit_id in unit_ids:
		if not _units_by_id.has(unit_id):
			continue

		var unit: Dictionary = _units_by_id[unit_id]

		if faction_filter >= 0 and unit.get("faction_id", -1) != faction_filter:
			continue

		result.append(unit)

	_query_count += 1
	return result


## Update unit position.
func update_unit_position(unit_id: int, new_position: Vector3) -> void:
	if not _units_by_id.has(unit_id):
		return

	_units_by_id[unit_id]["position"] = new_position
	_spatial_grid.update_unit_position(unit_id, new_position)


## Update unit health.
func update_unit_health(unit_id: int, health: float) -> void:
	if not _units_by_id.has(unit_id):
		return

	_units_by_id[unit_id]["health"] = health

	# Check for death
	if health <= 0:
		_units_by_id[unit_id]["is_alive"] = false


## Update unit state.
func update_unit_state(unit_id: int, state: String) -> void:
	if _units_by_id.has(unit_id):
		_units_by_id[unit_id]["state"] = state


## Kill unit (mark dead, schedule despawn).
func kill_unit(unit_id: int) -> void:
	if not _units_by_id.has(unit_id):
		return

	var unit: Dictionary = _units_by_id[unit_id]
	unit["health"] = 0
	unit["is_alive"] = false
	unit["state"] = "dead"


## Get all alive units.
func get_alive_units(faction_filter: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for unit_id in _units_by_id:
		var unit: Dictionary = _units_by_id[unit_id]
		if not unit.get("is_alive", true):
			continue
		if faction_filter >= 0 and unit.get("faction_id", -1) != faction_filter:
			continue
		result.append(unit)

	return result


## Get dead units (for cleanup).
func get_dead_units() -> Array[int]:
	var result: Array[int] = []

	for unit_id in _units_by_id:
		var unit: Dictionary = _units_by_id[unit_id]
		if not unit.get("is_alive", true):
			result.append(unit_id)

	return result


## Cleanup dead units.
func cleanup_dead_units() -> int:
	var dead := get_dead_units()
	despawn_units_batch(dead)
	return dead.size()


## Get unit count.
func get_unit_count(faction_filter: int = -1) -> int:
	if faction_filter < 0:
		return _units_by_id.size()

	if _units_by_faction.has(faction_filter):
		return _units_by_faction[faction_filter].size()

	return 0


## Get alive unit count.
func get_alive_count(faction_filter: int = -1) -> int:
	return get_alive_units(faction_filter).size()


## Check if unit exists.
func has_unit(unit_id: int) -> bool:
	return _units_by_id.has(unit_id)


## Get unit pool.
func get_unit_pool() -> UnitPool:
	return _unit_pool


## Get spatial grid.
func get_spatial_grid() -> SpatialGrid:
	return _spatial_grid


## Clear all units.
func clear_all() -> void:
	var all_ids: Array[int] = []
	for unit_id in _units_by_id:
		all_ids.append(unit_id)

	despawn_units_batch(all_ids)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"total_units": _units_by_id.size(),
		"spawn_count": _spawn_count,
		"despawn_count": _despawn_count,
		"query_count": _query_count,
		"last_spawn_time_ms": _last_spawn_time,
		"last_query_time_ms": _last_query_time,
		"units_by_faction": _get_faction_counts(),
		"spatial_grid": _spatial_grid.get_statistics() if _spatial_grid else {},
		"unit_pool": _unit_pool.get_summary() if _unit_pool else {}
	}


## Get unit counts by faction.
func _get_faction_counts() -> Dictionary:
	var counts := {}
	for faction_id in _units_by_faction:
		counts[faction_id] = _units_by_faction[faction_id].size()
	return counts


## Cleanup.
func cleanup() -> void:
	clear_all()
	if _unit_pool:
		_unit_pool.cleanup()
	if _spatial_grid:
		_spatial_grid.clear()
