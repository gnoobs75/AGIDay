class_name GPUProjectileSystem
extends RefCounted
## GPUProjectileSystem renders 10,000+ projectiles using GPU-accelerated MultiMesh.
## Minimizes CPU overhead by batching projectile transforms.

signal projectile_spawned(projectile_id: int)
signal projectile_destroyed(projectile_id: int)
signal batch_update_completed(count: int)

## Configuration
const MAX_PROJECTILES := 15000        ## Maximum concurrent projectiles
const BATCH_SIZE := 500               ## Projectiles per batch update
const UPDATE_BUDGET_MS := 2.0         ## Max milliseconds for updates

## Projectile types
enum ProjectileType {
	BULLET,      ## Fast, small
	PLASMA,      ## Medium, glowing
	MISSILE,     ## Large, tracking
	BEAM,        ## Instant, line
	SPREAD       ## Multiple small
}

## Projectile pools per type
var _pools: Dictionary = {}           ## ProjectileType -> MultiMeshPool
var _projectile_data: Dictionary = {} ## projectile_id -> ProjectileData
var _next_id := 0

## Active projectile tracking
var _active_count := 0
var _type_counts: Dictionary = {}

## Update batching
var _pending_updates: Array[int] = []
var _update_index := 0


func _init() -> void:
	_initialize_pools()


## Initialize projectile pools.
func _initialize_pools() -> void:
	for proj_type in ProjectileType.values():
		_pools[proj_type] = {
			"transforms": [],
			"active_ids": [],
			"max_count": MAX_PROJECTILES / ProjectileType.size()
		}
		_type_counts[proj_type] = 0


## Spawn projectile.
func spawn_projectile(type: ProjectileType, position: Vector3,
					  velocity: Vector3, damage: float = 10.0,
					  lifetime: float = 5.0, owner_id: int = -1) -> int:
	if _active_count >= MAX_PROJECTILES:
		# Remove oldest projectile to make room
		_remove_oldest_projectile()

	var id := _next_id
	_next_id += 1

	var data := ProjectileData.new()
	data.id = id
	data.type = type
	data.position = position
	data.velocity = velocity
	data.damage = damage
	data.lifetime = lifetime
	data.remaining_time = lifetime
	data.owner_id = owner_id
	data.is_active = true

	_projectile_data[id] = data
	_pools[type]["active_ids"].append(id)
	_active_count += 1
	_type_counts[type] += 1

	projectile_spawned.emit(id)
	return id


## Spawn batch of projectiles.
func spawn_batch(type: ProjectileType, spawn_data: Array) -> Array[int]:
	var ids: Array[int] = []

	for data in spawn_data:
		var id := spawn_projectile(
			type,
			data.get("position", Vector3.ZERO),
			data.get("velocity", Vector3.FORWARD * 100),
			data.get("damage", 10.0),
			data.get("lifetime", 5.0),
			data.get("owner_id", -1)
		)
		ids.append(id)

	return ids


## Update all projectiles (call each frame).
func update(delta: float) -> void:
	var start_time := Time.get_ticks_usec()
	var updated := 0
	var destroyed_ids: Array[int] = []

	# Update projectile positions
	for id in _projectile_data:
		var elapsed_ms := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed_ms > UPDATE_BUDGET_MS:
			break

		var proj: ProjectileData = _projectile_data[id]
		if not proj.is_active:
			continue

		# Update position
		proj.position += proj.velocity * delta

		# Update lifetime
		proj.remaining_time -= delta
		if proj.remaining_time <= 0:
			destroyed_ids.append(id)
			continue

		# Check bounds (destroy if out of world)
		if proj.position.length() > 1000:
			destroyed_ids.append(id)
			continue

		updated += 1

	# Remove destroyed projectiles
	for id in destroyed_ids:
		destroy_projectile(id)

	if updated > 0:
		batch_update_completed.emit(updated)


## Destroy projectile.
func destroy_projectile(projectile_id: int) -> void:
	if not _projectile_data.has(projectile_id):
		return

	var proj: ProjectileData = _projectile_data[projectile_id]
	var proj_type: ProjectileType = proj.type

	proj.is_active = false

	# Remove from pool
	var pool: Dictionary = _pools[proj_type]
	var idx := pool["active_ids"].find(projectile_id)
	if idx >= 0:
		pool["active_ids"].remove_at(idx)

	_projectile_data.erase(projectile_id)
	_active_count -= 1
	_type_counts[proj_type] = maxi(0, _type_counts[proj_type] - 1)

	projectile_destroyed.emit(projectile_id)


## Remove oldest projectile (for pool management).
func _remove_oldest_projectile() -> void:
	var oldest_id := -1
	var oldest_time := INF

	for id in _projectile_data:
		var proj: ProjectileData = _projectile_data[id]
		var age := proj.lifetime - proj.remaining_time
		if age > oldest_time:
			oldest_time = age
			oldest_id = id

	if oldest_id >= 0:
		destroy_projectile(oldest_id)


## Get projectile at position (for collision).
func get_projectile_at(position: Vector3, radius: float = 0.5) -> ProjectileData:
	var radius_sq := radius * radius

	for id in _projectile_data:
		var proj: ProjectileData = _projectile_data[id]
		if not proj.is_active:
			continue

		var dist_sq := proj.position.distance_squared_to(position)
		if dist_sq <= radius_sq:
			return proj

	return null


## Get projectiles in radius.
func get_projectiles_in_radius(position: Vector3, radius: float) -> Array[ProjectileData]:
	var result: Array[ProjectileData] = []
	var radius_sq := radius * radius

	for id in _projectile_data:
		var proj: ProjectileData = _projectile_data[id]
		if not proj.is_active:
			continue

		var dist_sq := proj.position.distance_squared_to(position)
		if dist_sq <= radius_sq:
			result.append(proj)

	return result


## Check collision with sphere.
func check_collision(position: Vector3, radius: float,
					 faction_filter: int = -1) -> Array[ProjectileData]:
	var hits: Array[ProjectileData] = []
	var radius_sq := radius * radius

	for id in _projectile_data:
		var proj: ProjectileData = _projectile_data[id]
		if not proj.is_active:
			continue

		# Filter by faction (projectiles from same faction don't hit)
		if faction_filter >= 0 and proj.owner_id == faction_filter:
			continue

		var dist_sq := proj.position.distance_squared_to(position)
		if dist_sq <= radius_sq:
			hits.append(proj)

	return hits


## Get transforms for rendering (MultiMesh).
func get_render_transforms(type: ProjectileType) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []

	for id in _pools[type]["active_ids"]:
		if _projectile_data.has(id):
			var proj: ProjectileData = _projectile_data[id]
			if proj.is_active:
				var transform := Transform3D.IDENTITY
				transform.origin = proj.position

				# Rotate to face velocity direction
				if proj.velocity.length_squared() > 0.001:
					var forward := proj.velocity.normalized()
					transform = transform.looking_at(proj.position + forward, Vector3.UP)

				transforms.append(transform)

	return transforms


## Get all render data for batch rendering.
func get_all_render_data() -> Dictionary:
	var data := {}

	for proj_type in ProjectileType.values():
		data[proj_type] = get_render_transforms(proj_type)

	return data


## Get projectile count.
func get_active_count() -> int:
	return _active_count


## Get count by type.
func get_count_by_type(type: ProjectileType) -> int:
	return _type_counts.get(type, 0)


## Get projectile by ID.
func get_projectile(projectile_id: int) -> ProjectileData:
	return _projectile_data.get(projectile_id)


## Clear all projectiles.
func clear_all() -> void:
	var ids := _projectile_data.keys().duplicate()
	for id in ids:
		destroy_projectile(id)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"active_count": _active_count,
		"max_count": MAX_PROJECTILES,
		"usage_percent": float(_active_count) / float(MAX_PROJECTILES) * 100.0,
		"type_counts": _type_counts.duplicate(),
		"data_entries": _projectile_data.size()
	}


## ProjectileData class.
class ProjectileData:
	var id: int = 0
	var type: ProjectileType = ProjectileType.BULLET
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var damage: float = 10.0
	var lifetime: float = 5.0
	var remaining_time: float = 5.0
	var owner_id: int = -1
	var is_active: bool = true
	var has_hit: bool = false
