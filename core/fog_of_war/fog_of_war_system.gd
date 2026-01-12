class_name FogOfWarSystem
extends RefCounted
## FogOfWarSystem manages fog of war for all factions.
## Provides faction-isolated visibility with <2ms update budget.

signal faction_added(faction_id: String)
signal faction_removed(faction_id: String)
signal visibility_updated(faction_id: String, voxel_x: int, voxel_z: int, state: int)

## Performance configuration
const UPDATE_BUDGET_MS := 2.0  ## Max ms per frame for updates

## Faction identifiers
const FACTION_AETHER_SWARM := "AETHER_SWARM"
const FACTION_OPTIFORGE_LEGION := "OPTIFORGE_LEGION"
const FACTION_DYNAPODS_VANGUARD := "DYNAPODS_VANGUARD"
const FACTION_LOGIBOTS_COLOSSUS := "LOGIBOTS_COLOSSUS"

## Default factions
const DEFAULT_FACTIONS := [
	FACTION_AETHER_SWARM,
	FACTION_OPTIFORGE_LEGION,
	FACTION_DYNAPODS_VANGUARD,
	FACTION_LOGIBOTS_COLOSSUS
]

## Faction grids (faction_id -> FogOfWarGrid)
var _faction_grids: Dictionary = {}

## Pending updates queue (for time-slicing)
var _pending_updates: Array[Dictionary] = []

## Performance metrics
var _last_update_time_ms := 0.0
var _total_updates := 0


func _init() -> void:
	pass


## Initialize with default factions.
func initialize_default_factions() -> void:
	for faction_id in DEFAULT_FACTIONS:
		add_faction(faction_id)


## Add faction to the system.
func add_faction(faction_id: String) -> bool:
	if _faction_grids.has(faction_id):
		return false

	_faction_grids[faction_id] = FogOfWarGrid.new(faction_id)
	faction_added.emit(faction_id)
	return true


## Remove faction from the system.
func remove_faction(faction_id: String) -> bool:
	if not _faction_grids.has(faction_id):
		return false

	_faction_grids.erase(faction_id)
	faction_removed.emit(faction_id)
	return true


## Get faction grid.
func get_faction_grid(faction_id: String) -> FogOfWarGrid:
	return _faction_grids.get(faction_id)


## Get visibility for faction at position.
func get_visibility(faction_id: String, voxel_x: int, voxel_z: int) -> int:
	var grid := get_faction_grid(faction_id)
	if grid == null:
		return VisibilityState.State.UNEXPLORED
	return grid.get_visibility(voxel_x, voxel_z)


## Set visibility for faction at position.
func set_visibility(faction_id: String, voxel_x: int, voxel_z: int, state: int, current_time: float = 0.0) -> bool:
	var grid := get_faction_grid(faction_id)
	if grid == null:
		return false

	var changed := grid.set_visibility(voxel_x, voxel_z, state, current_time)
	if changed:
		visibility_updated.emit(faction_id, voxel_x, voxel_z, state)

	return changed


## Reveal area for faction.
func reveal_area(faction_id: String, center_x: int, center_z: int, radius: int, current_time: float = 0.0) -> int:
	var grid := get_faction_grid(faction_id)
	if grid == null:
		return 0
	return grid.reveal_area(center_x, center_z, radius, current_time)


## Hide area for faction.
func hide_area(faction_id: String, center_x: int, center_z: int, radius: int) -> int:
	var grid := get_faction_grid(faction_id)
	if grid == null:
		return 0
	return grid.hide_area(center_x, center_z, radius)


## Check if position is visible to faction.
func is_visible_to_faction(faction_id: String, voxel_x: int, voxel_z: int) -> bool:
	var grid := get_faction_grid(faction_id)
	if grid == null:
		return false
	return grid.is_visible(voxel_x, voxel_z)


## Check if position has been explored by faction.
func is_explored_by_faction(faction_id: String, voxel_x: int, voxel_z: int) -> bool:
	var grid := get_faction_grid(faction_id)
	if grid == null:
		return false
	return grid.is_explored(voxel_x, voxel_z)


## Queue visibility update for time-sliced processing.
func queue_reveal(faction_id: String, center_x: int, center_z: int, radius: int) -> void:
	_pending_updates.append({
		"type": "reveal",
		"faction_id": faction_id,
		"center_x": center_x,
		"center_z": center_z,
		"radius": radius
	})


## Queue hide update for time-sliced processing.
func queue_hide(faction_id: String, center_x: int, center_z: int, radius: int) -> void:
	_pending_updates.append({
		"type": "hide",
		"faction_id": faction_id,
		"center_x": center_x,
		"center_z": center_z,
		"radius": radius
	})


## Process pending updates within time budget.
func process_updates(current_time: float) -> int:
	if _pending_updates.is_empty():
		return 0

	var start_time := Time.get_ticks_usec()
	var budget_us := int(UPDATE_BUDGET_MS * 1000)
	var processed := 0

	while not _pending_updates.is_empty():
		var update: Dictionary = _pending_updates[0]
		_pending_updates.remove_at(0)

		match update["type"]:
			"reveal":
				reveal_area(
					update["faction_id"],
					update["center_x"],
					update["center_z"],
					update["radius"],
					current_time
				)
			"hide":
				hide_area(
					update["faction_id"],
					update["center_x"],
					update["center_z"],
					update["radius"]
				)

		processed += 1
		_total_updates += 1

		# Check time budget
		var elapsed := Time.get_ticks_usec() - start_time
		if elapsed > budget_us:
			break

	_last_update_time_ms = float(Time.get_ticks_usec() - start_time) / 1000.0

	return processed


## Clear all visible cells for all factions.
func clear_all_visible() -> void:
	for faction_id in _faction_grids:
		_faction_grids[faction_id].clear_all_visible()


## Get dirty chunks for faction (for network sync).
func get_dirty_chunks(faction_id: String) -> Array[FogChunk]:
	var grid := get_faction_grid(faction_id)
	if grid == null:
		return []
	return grid.get_dirty_chunks()


## Clear dirty flags for faction.
func clear_dirty_flags(faction_id: String) -> void:
	var grid := get_faction_grid(faction_id)
	if grid != null:
		grid.clear_dirty_flags()


## Serialization.
func to_dict() -> Dictionary:
	var grids_data: Dictionary = {}

	for faction_id in _faction_grids:
		grids_data[faction_id] = _faction_grids[faction_id].to_dict()

	return {
		"faction_grids": grids_data
	}


func from_dict(data: Dictionary) -> void:
	var grids_data: Dictionary = data.get("faction_grids", {})

	for faction_id in grids_data:
		if not _faction_grids.has(faction_id):
			add_faction(faction_id)
		_faction_grids[faction_id].from_dict(grids_data[faction_id])


## Get total memory usage across all factions.
func get_total_memory_usage() -> int:
	var total := 0
	for faction_id in _faction_grids:
		total += _faction_grids[faction_id].get_memory_usage()
	return total


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_summaries: Dictionary = {}

	for faction_id in _faction_grids:
		faction_summaries[faction_id] = _faction_grids[faction_id].get_summary()

	return {
		"faction_count": _faction_grids.size(),
		"pending_updates": _pending_updates.size(),
		"last_update_time_ms": _last_update_time_ms,
		"total_updates": _total_updates,
		"total_memory_mb": get_total_memory_usage() / (1024 * 1024),
		"factions": faction_summaries
	}
