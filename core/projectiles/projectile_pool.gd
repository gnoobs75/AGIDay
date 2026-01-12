class_name ProjectilePool
extends RefCounted
## ProjectilePool manages pre-allocated projectile instances for zero-allocation gameplay.
## Supports up to 10,000 simultaneous projectiles.

## Maximum pool capacity
const MAX_POOL_SIZE := 10000

## Pool of projectile instances
var _pool: Array[Projectile] = []

## Available indices (free list)
var _available: Array[int] = []

## Active count
var _active_count: int = 0


func _init(initial_size: int = MAX_POOL_SIZE) -> void:
	_initialize_pool(initial_size)


## Initialize pool with pre-allocated projectiles.
func _initialize_pool(size: int) -> void:
	_pool.clear()
	_available.clear()
	_active_count = 0

	var pool_size := mini(size, MAX_POOL_SIZE)

	for i in pool_size:
		var proj := Projectile.new()
		proj.id = i
		_pool.append(proj)
		_available.append(i)


## Acquire projectile from pool.
func acquire() -> Projectile:
	if _available.is_empty():
		return null

	var index: int = _available.pop_back()
	var proj: Projectile = _pool[index]
	proj.is_active = true
	_active_count += 1

	return proj


## Release projectile back to pool.
func release(proj: Projectile) -> void:
	if proj == null or not proj.is_active:
		return

	proj.reset()
	_available.append(proj.id)
	_active_count -= 1


## Release projectile by ID.
func release_by_id(proj_id: int) -> void:
	if proj_id < 0 or proj_id >= _pool.size():
		return

	var proj: Projectile = _pool[proj_id]
	release(proj)


## Get projectile by ID.
func get_projectile(proj_id: int) -> Projectile:
	if proj_id < 0 or proj_id >= _pool.size():
		return null

	var proj: Projectile = _pool[proj_id]
	return proj if proj.is_active else null


## Get all active projectiles.
func get_active_projectiles() -> Array[Projectile]:
	var active: Array[Projectile] = []

	for proj in _pool:
		if proj.is_active:
			active.append(proj)

	return active


## Get active count.
func get_active_count() -> int:
	return _active_count


## Get available count.
func get_available_count() -> int:
	return _available.size()


## Get pool capacity.
func get_capacity() -> int:
	return _pool.size()


## Check if pool has available slots.
func has_available() -> bool:
	return not _available.is_empty()


## Clear all projectiles.
func clear_all() -> void:
	for proj in _pool:
		if proj.is_active:
			proj.reset()

	_available.clear()
	for i in _pool.size():
		_available.append(i)

	_active_count = 0


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"capacity": _pool.size(),
		"active": _active_count,
		"available": _available.size()
	}
