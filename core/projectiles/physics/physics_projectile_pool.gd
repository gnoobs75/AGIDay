class_name PhysicsProjectilePool
extends RefCounted
## PhysicsProjectilePool manages pre-allocated physics projectiles.
## Supports dynamic capacity based on quality settings.

## Pool of projectiles
var _pool: Array[PhysicsProjectile] = []

## Free indices
var _free_indices: Array[int] = []

## Active count
var _active_count: int = 0

## Current capacity
var _capacity: int = 0


func _init(initial_capacity: int = 7500) -> void:
	resize(initial_capacity)


## Resize pool capacity.
func resize(new_capacity: int) -> void:
	if new_capacity == _capacity:
		return

	if new_capacity > _capacity:
		# Expand pool
		for i in range(_capacity, new_capacity):
			var proj := PhysicsProjectile.new()
			proj.id = i
			_pool.append(proj)
			_free_indices.append(i)
	else:
		# Shrink pool (release excess active projectiles)
		var to_release: Array[int] = []
		for i in range(new_capacity, _capacity):
			if i < _pool.size() and _pool[i].is_active:
				to_release.append(i)

		for idx in to_release:
			release_by_id(idx)

		# Truncate pool
		_pool.resize(new_capacity)

		# Rebuild free indices
		_free_indices.clear()
		for i in range(new_capacity - 1, -1, -1):
			if not _pool[i].is_active:
				_free_indices.append(i)

	_capacity = new_capacity


## Acquire projectile from pool.
func acquire() -> PhysicsProjectile:
	if _free_indices.is_empty():
		return null

	var index: int = _free_indices.pop_back()
	var proj: PhysicsProjectile = _pool[index]
	proj.is_active = true
	_active_count += 1

	return proj


## Release projectile back to pool.
func release(proj: PhysicsProjectile) -> void:
	if proj == null or not proj.is_active:
		return

	proj.reset()
	_free_indices.append(proj.id)
	_active_count -= 1


## Release by ID.
func release_by_id(proj_id: int) -> void:
	if proj_id < 0 or proj_id >= _pool.size():
		return

	var proj: PhysicsProjectile = _pool[proj_id]
	release(proj)


## Get projectile by ID.
func get_projectile(proj_id: int) -> PhysicsProjectile:
	if proj_id < 0 or proj_id >= _pool.size():
		return null

	var proj: PhysicsProjectile = _pool[proj_id]
	return proj if proj.is_active else null


## Get all active projectiles.
func get_active_projectiles() -> Array[PhysicsProjectile]:
	var active: Array[PhysicsProjectile] = []
	for proj in _pool:
		if proj.is_active:
			active.append(proj)
	return active


## Get active count.
func get_active_count() -> int:
	return _active_count


## Get capacity.
func get_capacity() -> int:
	return _capacity


## Has available slots.
func has_available() -> bool:
	return not _free_indices.is_empty()


## Clear all.
func clear() -> void:
	for proj in _pool:
		if proj.is_active:
			proj.reset()

	_free_indices.clear()
	for i in range(_capacity - 1, -1, -1):
		_free_indices.append(i)

	_active_count = 0


## Get summary.
func get_summary() -> Dictionary:
	return {
		"capacity": _capacity,
		"active": _active_count,
		"available": _free_indices.size()
	}
