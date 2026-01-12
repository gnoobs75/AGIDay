class_name ProjectileManager
extends RefCounted
## ProjectileManager handles spawning, updating, and querying projectiles.
## Supports up to 10,000 simultaneous projectiles with spatial queries.

signal projectile_spawned(projectile_id: int, faction_id: String, position: Vector3)
signal projectile_despawned(projectile_id: int, reason: String)
signal projectile_hit(projectile_id: int, target_id: int, damage: float)

## Projectile pool
var _pool: ProjectilePool = null

## Type registry
var _type_registry: ProjectileTypeRegistry = null

## Active projectiles by ID (for fast lookup)
var _active_by_id: Dictionary = {}

## Projectiles by faction
var _by_faction: Dictionary = {}

## Spatial grid for queries (cell_key -> Array[int] of projectile IDs)
var _spatial_grid: Dictionary = {}

## Spatial grid cell size
const GRID_CELL_SIZE := 64.0

## Current frame number (for determinism)
var _current_frame: int = 0

## Random seed for deterministic behavior
var _random_seed: int = 0

## Target position callback (for homing projectiles)
var _target_position_callback: Callable


func _init() -> void:
	_pool = ProjectilePool.new()
	_type_registry = ProjectileTypeRegistry.new()


## Set target position callback for homing projectiles.
func set_target_position_callback(callback: Callable) -> void:
	_target_position_callback = callback


## Get type registry.
func get_type_registry() -> ProjectileTypeRegistry:
	return _type_registry


## Spawn projectile.
func spawn_projectile(
	faction_id: String,
	type_id: String,
	position: Vector3,
	direction: Vector3,
	target_id: int = -1
) -> int:
	var proj_type := _type_registry.get_type(type_id)
	if proj_type == null:
		return -1

	var proj := _pool.acquire()
	if proj == null:
		return -1  # Pool exhausted

	proj.initialize(proj.id, faction_id, proj_type, position, direction, _current_frame, target_id)

	# Track active projectile
	_active_by_id[proj.id] = proj

	# Track by faction
	if not _by_faction.has(faction_id):
		_by_faction[faction_id] = []
	_by_faction[faction_id].append(proj.id)

	# Add to spatial grid
	_add_to_spatial_grid(proj)

	projectile_spawned.emit(proj.id, faction_id, position)

	return proj.id


## Spawn projectile with velocity override.
func spawn_projectile_with_velocity(
	faction_id: String,
	type_id: String,
	position: Vector3,
	velocity: Vector3,
	target_id: int = -1
) -> int:
	var proj_type := _type_registry.get_type(type_id)
	if proj_type == null:
		return -1

	var proj := _pool.acquire()
	if proj == null:
		return -1

	var direction := velocity.normalized() if velocity.length_squared() > 0 else Vector3.FORWARD
	proj.initialize(proj.id, faction_id, proj_type, position, direction, _current_frame, target_id)
	proj.velocity = velocity  # Override with exact velocity

	_active_by_id[proj.id] = proj

	if not _by_faction.has(faction_id):
		_by_faction[faction_id] = []
	_by_faction[faction_id].append(proj.id)

	_add_to_spatial_grid(proj)

	projectile_spawned.emit(proj.id, faction_id, position)

	return proj.id


## Despawn projectile.
func despawn_projectile(projectile_id: int, reason: String = "manual") -> void:
	var proj: Projectile = _active_by_id.get(projectile_id)
	if proj == null:
		return

	# Remove from spatial grid
	_remove_from_spatial_grid(proj)

	# Remove from faction list
	if _by_faction.has(proj.faction_id):
		_by_faction[proj.faction_id].erase(projectile_id)

	# Remove from active tracking
	_active_by_id.erase(projectile_id)

	# Return to pool
	_pool.release(proj)

	projectile_despawned.emit(projectile_id, reason)


## Update all projectiles.
func update_projectiles(delta: float) -> void:
	_current_frame += 1

	var to_despawn: Array[int] = []

	for proj_id in _active_by_id:
		var proj: Projectile = _active_by_id[proj_id]
		var proj_type := _type_registry.get_type(proj.projectile_type)

		# Remove from old grid cell
		_remove_from_spatial_grid(proj)

		# Update movement
		if proj_type != null and proj_type.is_homing() and proj.target_id >= 0:
			var target_pos := _get_target_position(proj.target_id)
			if target_pos != Vector3.INF:
				proj.update_homing(delta, target_pos, proj_type.homing_strength)
			else:
				# Target lost, switch to ballistic
				proj.target_id = -1
				proj.update_ballistic(delta)
		else:
			proj.update_ballistic(delta)

		# Add to new grid cell
		_add_to_spatial_grid(proj)

		# Check expiration
		if proj.is_expired():
			to_despawn.append(proj_id)

	# Despawn expired projectiles
	for proj_id in to_despawn:
		despawn_projectile(proj_id, "expired")


## Get projectiles in radius.
func get_projectiles_in_radius(center: Vector3, radius: float) -> Array[Projectile]:
	var result: Array[Projectile] = []
	var radius_squared := radius * radius

	# Get grid cells to check
	var cells := _get_cells_in_radius(center, radius)

	# Check projectiles in those cells
	var checked: Dictionary = {}

	for cell_key in cells:
		var proj_ids: Array = _spatial_grid.get(cell_key, [])
		for proj_id in proj_ids:
			if checked.has(proj_id):
				continue
			checked[proj_id] = true

			var proj: Projectile = _active_by_id.get(proj_id)
			if proj != null:
				var dist_sq := proj.position.distance_squared_to(center)
				if dist_sq <= radius_squared:
					result.append(proj)

	return result


## Get projectiles in radius by faction.
func get_enemy_projectiles_in_radius(center: Vector3, radius: float, exclude_faction: String) -> Array[Projectile]:
	var all_in_radius := get_projectiles_in_radius(center, radius)
	var result: Array[Projectile] = []

	for proj in all_in_radius:
		if proj.faction_id != exclude_faction:
			result.append(proj)

	return result


## Get projectile by ID.
func get_projectile(projectile_id: int) -> Projectile:
	return _active_by_id.get(projectile_id)


## Get all active projectiles.
func get_all_active() -> Array[Projectile]:
	var result: Array[Projectile] = []
	for proj_id in _active_by_id:
		result.append(_active_by_id[proj_id])
	return result


## Get projectiles by faction.
func get_projectiles_by_faction(faction_id: String) -> Array[Projectile]:
	var result: Array[Projectile] = []
	var ids: Array = _by_faction.get(faction_id, [])

	for proj_id in ids:
		var proj: Projectile = _active_by_id.get(proj_id)
		if proj != null:
			result.append(proj)

	return result


## Get active count.
func get_active_count() -> int:
	return _active_by_id.size()


## Clear all projectiles.
func clear_all() -> void:
	for proj_id in _active_by_id.keys():
		despawn_projectile(proj_id, "cleared")


## Get target position (via callback or default).
func _get_target_position(target_id: int) -> Vector3:
	if _target_position_callback.is_valid():
		return _target_position_callback.call(target_id)
	return Vector3.INF  # No valid target


## Add projectile to spatial grid.
func _add_to_spatial_grid(proj: Projectile) -> void:
	var cell_key := _get_cell_key(proj.position)

	if not _spatial_grid.has(cell_key):
		_spatial_grid[cell_key] = []

	_spatial_grid[cell_key].append(proj.id)


## Remove projectile from spatial grid.
func _remove_from_spatial_grid(proj: Projectile) -> void:
	var cell_key := _get_cell_key(proj.position)

	if _spatial_grid.has(cell_key):
		_spatial_grid[cell_key].erase(proj.id)


## Get cell key for position.
func _get_cell_key(position: Vector3) -> String:
	var cx := int(floor(position.x / GRID_CELL_SIZE))
	var cy := int(floor(position.y / GRID_CELL_SIZE))
	var cz := int(floor(position.z / GRID_CELL_SIZE))
	return "%d,%d,%d" % [cx, cy, cz]


## Get cells that intersect with radius.
func _get_cells_in_radius(center: Vector3, radius: float) -> Array[String]:
	var cells: Array[String] = []

	var min_cx := int(floor((center.x - radius) / GRID_CELL_SIZE))
	var max_cx := int(floor((center.x + radius) / GRID_CELL_SIZE))
	var min_cy := int(floor((center.y - radius) / GRID_CELL_SIZE))
	var max_cy := int(floor((center.y + radius) / GRID_CELL_SIZE))
	var min_cz := int(floor((center.z - radius) / GRID_CELL_SIZE))
	var max_cz := int(floor((center.z + radius) / GRID_CELL_SIZE))

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			for cz in range(min_cz, max_cz + 1):
				cells.append("%d,%d,%d" % [cx, cy, cz])

	return cells


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var projectiles_data: Array = []
	for proj_id in _active_by_id:
		projectiles_data.append(_active_by_id[proj_id].to_dict())

	return {
		"current_frame": _current_frame,
		"random_seed": _random_seed,
		"projectiles": projectiles_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	clear_all()

	_current_frame = data.get("current_frame", 0)
	_random_seed = data.get("random_seed", 0)

	for proj_data in data.get("projectiles", []):
		var proj := _pool.acquire()
		if proj == null:
			break

		# Load projectile data
		var loaded := Projectile.from_dict(proj_data)
		proj.id = loaded.id if loaded.id >= 0 else proj.id
		proj.faction_id = loaded.faction_id
		proj.projectile_type = loaded.projectile_type
		proj.position = loaded.position
		proj.velocity = loaded.velocity
		proj.rotation = loaded.rotation
		proj.lifetime = loaded.lifetime
		proj.damage = loaded.damage
		proj.hit_radius = loaded.hit_radius
		proj.target_id = loaded.target_id
		proj.homing_speed = loaded.homing_speed
		proj.particle_index = loaded.particle_index
		proj.visual_effect = loaded.visual_effect
		proj.is_active = true
		proj.pierce_remaining = loaded.pierce_remaining
		proj.spawn_frame = loaded.spawn_frame
		proj.hit_units = loaded.hit_units.duplicate()

		_active_by_id[proj.id] = proj

		if not _by_faction.has(proj.faction_id):
			_by_faction[proj.faction_id] = []
		_by_faction[proj.faction_id].append(proj.id)

		_add_to_spatial_grid(proj)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_counts: Dictionary = {}
	for faction_id in _by_faction:
		faction_counts[faction_id] = _by_faction[faction_id].size()

	return {
		"active_projectiles": _active_by_id.size(),
		"pool": _pool.get_summary(),
		"types": _type_registry.get_summary(),
		"by_faction": faction_counts,
		"spatial_cells": _spatial_grid.size(),
		"current_frame": _current_frame
	}
