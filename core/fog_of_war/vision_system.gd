class_name VisionSystem
extends RefCounted
## VisionSystem manages vision calculations for all units.
## Provides vision data to fog of war grid with <2ms performance budget.

signal unit_vision_updated(unit_id: int, visible_voxels: Array)
signal vision_calculation_complete(units_processed: int, time_ms: float)

## Performance configuration
const UPDATE_BUDGET_MS := 2.0  ## Max ms per frame
const CACHE_DURATION := 0.1  ## Seconds before cache expires

## Unit vision components (unit_id -> VisionComponent)
var _vision_components: Dictionary = {}

## Line of sight calculator
var _los: LineOfSight = null

## Vision cache (unit_id -> {voxels: Array, time: float, position: Vector3})
var _vision_cache: Dictionary = {}

## Pending updates queue
var _pending_updates: Array[int] = []

## Update scheduling (round-robin through units)
var _current_update_index := 0

## Performance metrics
var _last_update_time_ms := 0.0
var _cache_hits := 0
var _cache_misses := 0

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _is_blocking_voxel: Callable  ## (x, y, z) -> bool


func _init() -> void:
	_los = LineOfSight.new()


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_blocking_voxel_check(callback: Callable) -> void:
	_is_blocking_voxel = callback
	_los.set_blocking_check(callback)


## Register unit with vision.
func register_unit(unit_id: int, faction_id: String, unit_type: String) -> VisionComponent:
	var component := VisionComponent.new()
	component.initialize(unit_id, faction_id, unit_type)

	_vision_components[unit_id] = component
	_pending_updates.append(unit_id)

	return component


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_vision_components.erase(unit_id)
	_vision_cache.erase(unit_id)

	var idx := _pending_updates.find(unit_id)
	if idx != -1:
		_pending_updates.remove_at(idx)


## Get vision component.
func get_component(unit_id: int) -> VisionComponent:
	return _vision_components.get(unit_id)


## Update unit position.
func update_unit_position(unit_id: int, position: Vector3) -> void:
	var component := get_component(unit_id)
	if component == null:
		return

	var old_pos := component.position
	component.update_position(position)

	# Invalidate cache if moved significantly
	if old_pos.distance_to(position) > 0.5:
		_vision_cache.erase(unit_id)

		if unit_id not in _pending_updates:
			_pending_updates.append(unit_id)


## Get visible voxels for unit.
func get_visible_voxels(unit_id: int) -> Array[Vector2i]:
	var component := get_component(unit_id)
	if component == null:
		return []

	# Check cache
	var current_time := Time.get_ticks_msec() / 1000.0

	if _vision_cache.has(unit_id):
		var cache: Dictionary = _vision_cache[unit_id]
		var cache_age := current_time - cache["time"]

		if cache_age < CACHE_DURATION and cache["position"].distance_to(component.position) < 0.1:
			_cache_hits += 1
			return cache["voxels"]

	_cache_misses += 1

	# Calculate vision
	var voxels := _calculate_vision(component)

	# Update cache
	_vision_cache[unit_id] = {
		"voxels": voxels,
		"time": current_time,
		"position": component.position
	}

	return voxels


## Calculate visible voxels for component.
func _calculate_vision(component: VisionComponent) -> Array[Vector2i]:
	return _los.get_visible_voxels(
		component.position,
		component.vision_range,
		component.vision_height,
		component.can_see_through_buildings
	)


## Process pending vision updates within time budget.
func process_updates() -> int:
	if _vision_components.is_empty():
		return 0

	var start_time := Time.get_ticks_usec()
	var budget_us := int(UPDATE_BUDGET_MS * 1000)
	var processed := 0

	# Update unit positions first
	for unit_id in _vision_components:
		if _get_unit_position.is_valid():
			var pos: Vector3 = _get_unit_position.call(unit_id)
			_vision_components[unit_id].update_position(pos)

	# Process pending updates
	while not _pending_updates.is_empty():
		var unit_id: int = _pending_updates[0]
		_pending_updates.remove_at(0)

		if _vision_components.has(unit_id):
			var voxels := get_visible_voxels(unit_id)
			unit_vision_updated.emit(unit_id, voxels)
			processed += 1

		# Check time budget
		var elapsed := Time.get_ticks_usec() - start_time
		if elapsed > budget_us:
			break

	_last_update_time_ms = float(Time.get_ticks_usec() - start_time) / 1000.0
	vision_calculation_complete.emit(processed, _last_update_time_ms)

	return processed


## Force immediate vision update for unit.
func update_unit_immediate(unit_id: int) -> Array[Vector2i]:
	_vision_cache.erase(unit_id)  ## Invalidate cache
	return get_visible_voxels(unit_id)


## Get all visible voxels for faction.
func get_faction_visible_voxels(faction_id: String) -> Array[Vector2i]:
	var all_voxels: Array[Vector2i] = []
	var seen: Dictionary = {}  ## For deduplication

	for unit_id in _vision_components:
		var component: VisionComponent = _vision_components[unit_id]

		if component.faction_id != faction_id:
			continue

		var voxels := get_visible_voxels(unit_id)

		for voxel in voxels:
			var key := str(voxel.x) + "_" + str(voxel.y)
			if not seen.has(key):
				seen[key] = true
				all_voxels.append(voxel)

	return all_voxels


## Get units with vision at position.
func get_units_seeing_position(voxel_x: int, voxel_z: int) -> Array[int]:
	var units: Array[int] = []
	var target := Vector2i(voxel_x, voxel_z)

	for unit_id in _vision_components:
		var voxels := get_visible_voxels(unit_id)
		if target in voxels:
			units.append(unit_id)

	return units


## Invalidate all caches (call when terrain changes).
func invalidate_all_caches() -> void:
	_vision_cache.clear()

	for unit_id in _vision_components:
		if unit_id not in _pending_updates:
			_pending_updates.append(unit_id)


## Get cache statistics.
func get_cache_stats() -> Dictionary:
	var total := _cache_hits + _cache_misses
	var hit_rate := 0.0 if total == 0 else float(_cache_hits) / float(total)

	return {
		"cache_hits": _cache_hits,
		"cache_misses": _cache_misses,
		"hit_rate": hit_rate,
		"cached_entries": _vision_cache.size()
	}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_counts: Dictionary = {}

	for unit_id in _vision_components:
		var component: VisionComponent = _vision_components[unit_id]
		var faction := component.faction_id
		faction_counts[faction] = faction_counts.get(faction, 0) + 1

	return {
		"registered_units": _vision_components.size(),
		"pending_updates": _pending_updates.size(),
		"last_update_time_ms": _last_update_time_ms,
		"cache_stats": get_cache_stats(),
		"units_by_faction": faction_counts
	}
