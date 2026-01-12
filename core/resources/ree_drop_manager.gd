class_name REEDropManager
extends RefCounted
## REEDropManager handles REE drops with efficient spatial queries.
## Manages drop spawning, collection, and cleanup.

signal drop_spawned(drop: REEDrop)
signal drop_collected(drop_id: int, collector_faction: String, amount: float)
signal drop_expired(drop_id: int)
signal collection_failed(drop_id: int, reason: String)

## Spatial grid cell size
const GRID_CELL_SIZE := 16.0

## All drops (id -> REEDrop)
var drops: Dictionary = {}

## Spatial grid (cell_key -> Array of drop IDs)
var _spatial_grid: Dictionary = {}

## Next drop ID
var _next_drop_id: int = 1

## Faction resource manager reference
var resource_manager = null

## Collection statistics
var stats: Dictionary = {
	"total_spawned": 0,
	"total_collected": 0,
	"total_expired": 0,
	"total_ree_collected": 0.0,
	"total_ree_expired": 0.0
}


func _init() -> void:
	pass


## Spawn REE drop at position.
func spawn_drop(
	position: Vector3,
	amount: float,
	faction_id: String,
	source_type: String = "",
	source_id: int = -1
) -> REEDrop:
	if amount <= 0:
		return null

	var drop := REEDrop.new()
	drop.id = _next_drop_id
	_next_drop_id += 1
	drop.initialize(position, amount, faction_id, source_type, source_id)

	# Register drop
	drops[drop.id] = drop
	_add_to_spatial_grid(drop)

	# Connect signals
	drop.collected.connect(_on_drop_collected.bind(drop.id))
	drop.expired.connect(_on_drop_expired.bind(drop.id))

	stats["total_spawned"] += 1
	drop_spawned.emit(drop)

	return drop


## Spawn REE drop from building destruction.
func spawn_from_building(
	position: Vector3,
	ree_value: float,
	faction_id: String,
	building_id: int
) -> REEDrop:
	return spawn_drop(position, ree_value, faction_id, "building", building_id)


## Spawn REE drop from unit death/salvage.
func spawn_from_unit(
	position: Vector3,
	ree_value: float,
	faction_id: String,
	unit_id: int
) -> REEDrop:
	return spawn_drop(position, ree_value, faction_id, "unit", unit_id)


## Update all drops.
func update(delta: float) -> void:
	var to_remove: Array[int] = []

	for drop_id in drops:
		var drop: REEDrop = drops[drop_id]
		drop.update(delta)

		if not drop.is_valid():
			to_remove.append(drop_id)

	# Remove invalid drops
	for drop_id in to_remove:
		_remove_drop(drop_id)


## Collect REE within radius for faction.
func collect_in_radius(
	position: Vector3,
	radius: float,
	collector_faction: String,
	max_collect: float = INF
) -> float:
	var nearby := get_drops_in_radius(position, radius)
	var total_collected := 0.0
	var remaining := max_collect

	for drop in nearby:
		if remaining <= 0:
			break

		if drop.can_be_collected_by(collector_faction):
			var collected := drop.collect(collector_faction, remaining)
			total_collected += collected
			remaining -= collected

			if collected > 0:
				drop_collected.emit(drop.id, collector_faction, collected)
				_add_to_faction_resources(collector_faction, collected)

	return total_collected


## Try to collect specific drop.
func collect_drop(
	drop_id: int,
	collector_faction: String,
	max_collect: float = INF
) -> float:
	var drop: REEDrop = drops.get(drop_id)
	if drop == null:
		collection_failed.emit(drop_id, "Drop not found")
		return 0.0

	if not drop.can_be_collected_by(collector_faction):
		collection_failed.emit(drop_id, "Wrong faction")
		return 0.0

	var collected := drop.collect(collector_faction, max_collect)

	if collected > 0:
		drop_collected.emit(drop_id, collector_faction, collected)
		_add_to_faction_resources(collector_faction, collected)

	return collected


## Get drop by ID.
func get_drop(id: int) -> REEDrop:
	return drops.get(id)


## Get drops in radius using spatial grid.
func get_drops_in_radius(position: Vector3, radius: float) -> Array[REEDrop]:
	var result: Array[REEDrop] = []

	# Calculate grid cells to check
	var min_cell := _get_grid_cell(position - Vector3(radius, 0, radius))
	var max_cell := _get_grid_cell(position + Vector3(radius, 0, radius))

	for cx in range(min_cell.x, max_cell.x + 1):
		for cy in range(min_cell.y, max_cell.y + 1):
			var cell_key := _get_cell_key(cx, cy)
			var cell_drops: Array = _spatial_grid.get(cell_key, [])

			for drop_id in cell_drops:
				var drop: REEDrop = drops.get(drop_id)
				if drop != null and drop.is_valid():
					var distance := position.distance_to(drop.position)
					if distance <= radius:
						result.append(drop)

	return result


## Get drops for faction.
func get_faction_drops(faction_id: String) -> Array[REEDrop]:
	var result: Array[REEDrop] = []
	for drop in drops.values():
		if drop.faction_id == faction_id and drop.is_valid():
			result.append(drop)
	return result


## Get all valid drops.
func get_all_drops() -> Array[REEDrop]:
	var result: Array[REEDrop] = []
	for drop in drops.values():
		if drop.is_valid():
			result.append(drop)
	return result


## Get total REE on ground for faction.
func get_faction_total_ree(faction_id: String) -> float:
	var total := 0.0
	for drop in get_faction_drops(faction_id):
		total += drop.amount
	return total


## Remove drop.
func _remove_drop(drop_id: int) -> void:
	var drop: REEDrop = drops.get(drop_id)
	if drop == null:
		return

	_remove_from_spatial_grid(drop)
	drops.erase(drop_id)


## Add drop to spatial grid.
func _add_to_spatial_grid(drop: REEDrop) -> void:
	var cell_key := _get_cell_key_for_position(drop.position)

	if not _spatial_grid.has(cell_key):
		_spatial_grid[cell_key] = []

	_spatial_grid[cell_key].append(drop.id)


## Remove drop from spatial grid.
func _remove_from_spatial_grid(drop: REEDrop) -> void:
	var cell_key := _get_cell_key_for_position(drop.position)
	var cell: Array = _spatial_grid.get(cell_key, [])

	var idx := cell.find(drop.id)
	if idx >= 0:
		cell.remove_at(idx)


## Get grid cell for position.
func _get_grid_cell(position: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(position.x / GRID_CELL_SIZE)),
		int(floor(position.z / GRID_CELL_SIZE))
	)


## Get cell key for position.
func _get_cell_key_for_position(position: Vector3) -> String:
	var cell := _get_grid_cell(position)
	return _get_cell_key(cell.x, cell.y)


## Get cell key from coordinates.
func _get_cell_key(cx: int, cy: int) -> String:
	return str(cx) + "," + str(cy)


## Add collected REE to faction resources.
func _add_to_faction_resources(faction_id: String, amount: float) -> void:
	if resource_manager != null and resource_manager.has_method("add_faction_ree"):
		resource_manager.add_faction_ree(faction_id, amount)

	stats["total_ree_collected"] += amount


## Handle drop collected.
func _on_drop_collected(collector_faction: String, amount: float, drop_id: int) -> void:
	stats["total_collected"] += 1


## Handle drop expired.
func _on_drop_expired(drop_id: int) -> void:
	var drop: REEDrop = drops.get(drop_id)
	if drop != null:
		stats["total_expired"] += 1
		stats["total_ree_expired"] += drop.amount

	drop_expired.emit(drop_id)


## Get statistics.
func get_statistics() -> Dictionary:
	return stats.duplicate()


## Clear all drops.
func clear() -> void:
	drops.clear()
	_spatial_grid.clear()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var drops_data: Dictionary = {}
	for id in drops:
		drops_data[str(id)] = drops[id].to_dict()

	return {
		"drops": drops_data,
		"next_drop_id": _next_drop_id,
		"stats": stats.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> REEDropManager:
	var manager := REEDropManager.new()
	manager._next_drop_id = data.get("next_drop_id", 1)
	manager.stats = data.get("stats", {}).duplicate()

	# Restore drops
	manager.drops.clear()
	manager._spatial_grid.clear()

	for id_str in data.get("drops", {}):
		var drop := REEDrop.from_dict(data["drops"][id_str])
		manager.drops[int(id_str)] = drop
		manager._add_to_spatial_grid(drop)

		# Reconnect signals
		drop.collected.connect(manager._on_drop_collected.bind(drop.id))
		drop.expired.connect(manager._on_drop_expired.bind(drop.id))

	return manager


## Get summary for debugging.
func get_summary() -> Dictionary:
	var valid_count := 0
	var total_ree := 0.0

	for drop in drops.values():
		if drop.is_valid():
			valid_count += 1
			total_ree += drop.amount

	return {
		"total_drops": drops.size(),
		"valid_drops": valid_count,
		"total_ree_on_ground": "%.1f" % total_ree,
		"spawned": stats["total_spawned"],
		"collected": stats["total_collected"],
		"expired": stats["total_expired"]
	}
