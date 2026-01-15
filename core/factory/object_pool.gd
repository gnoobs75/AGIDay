class_name ObjectPool
extends RefCounted
## ObjectPool provides generic object pooling with pre-allocation.
## Minimizes garbage collection by reusing objects.

signal pool_expanded(new_size: int)
signal pool_exhausted()
signal object_acquired()
signal object_released()

## Configuration
var _initial_size: int = 100
var _max_size: int = 1000
var _expansion_size: int = 50
var _auto_expand: bool = true

## Pool storage
var _available: Array = []
var _active: Dictionary = {}  ## object -> true (for O(1) lookup)

## Factory function for creating new objects
var _factory_func: Callable = Callable()
var _reset_func: Callable = Callable()

## Statistics
var _stats: PoolStatistics = null

## Thread safety
var _mutex: Mutex = null
var _thread_safe: bool = false


func _init(initial_size: int = 100, max_size: int = 1000) -> void:
	_initial_size = initial_size
	_max_size = max_size
	_stats = PoolStatistics.new()
	_mutex = Mutex.new()


## Initialize pool with factory function.
func initialize(factory: Callable, reset: Callable = Callable(),
				thread_safe: bool = false) -> void:
	_factory_func = factory
	_reset_func = reset
	_thread_safe = thread_safe

	# Pre-allocate initial objects
	_warm_pool(_initial_size)


## Pre-allocate objects.
func _warm_pool(count: int) -> void:
	if not _factory_func.is_valid():
		push_error("ObjectPool: No factory function set")
		return

	for i in count:
		var obj = _factory_func.call()
		if obj != null:
			_available.append(obj)

	_stats.total_created += count


## Acquire object from pool.
func acquire() -> Variant:
	if _thread_safe:
		_mutex.lock()

	var obj: Variant = null

	if not _available.is_empty():
		obj = _available.pop_back()
		_active[obj] = true
		_stats.acquired_count += 1
		_stats.current_active += 1
		_stats.peak_active = maxi(_stats.peak_active, _stats.current_active)
		object_acquired.emit()
	elif _auto_expand and _get_total_size() < _max_size:
		# Expand pool
		obj = _expand_and_acquire()
	else:
		# Pool exhausted
		_stats.exhaustion_count += 1
		pool_exhausted.emit()
		push_warning("ObjectPool: Pool exhausted, max size reached")

	if _thread_safe:
		_mutex.unlock()

	return obj


## Release object back to pool.
func release(obj: Variant) -> void:
	if obj == null:
		return

	if _thread_safe:
		_mutex.lock()

	if _active.has(obj):
		_active.erase(obj)

		# Reset object if reset function provided
		if _reset_func.is_valid():
			_reset_func.call(obj)

		_available.append(obj)
		_stats.released_count += 1
		_stats.current_active -= 1
		object_released.emit()
	else:
		push_warning("ObjectPool: Attempted to release object not from this pool")

	if _thread_safe:
		_mutex.unlock()


## Expand pool and acquire.
func _expand_and_acquire() -> Variant:
	var expand_count := mini(_expansion_size, _max_size - _get_total_size())

	if expand_count <= 0:
		return null

	_stats.expansion_count += 1
	push_warning("ObjectPool: Expanding pool by %d objects" % expand_count)

	for i in expand_count:
		var obj = _factory_func.call()
		if obj != null:
			_available.append(obj)
			_stats.total_created += 1

	pool_expanded.emit(_get_total_size())

	# Now acquire from expanded pool
	if not _available.is_empty():
		var obj = _available.pop_back()
		_active[obj] = true
		_stats.acquired_count += 1
		_stats.current_active += 1
		_stats.peak_active = maxi(_stats.peak_active, _stats.current_active)
		return obj

	return null


## Get total pool size.
func _get_total_size() -> int:
	return _available.size() + _active.size()


## Get available count.
func get_available_count() -> int:
	return _available.size()


## Get active count.
func get_active_count() -> int:
	return _active.size()


## Get pool statistics.
func get_statistics() -> Dictionary:
	return _stats.to_dict()


## Clear all objects from pool.
func clear() -> void:
	if _thread_safe:
		_mutex.lock()

	_available.clear()
	_active.clear()
	_stats.reset()

	if _thread_safe:
		_mutex.unlock()


## Pre-warm pool to specific size.
func warm(target_size: int) -> void:
	var current := _get_total_size()
	if target_size > current:
		var to_create := mini(target_size - current, _max_size - current)
		_warm_pool(to_create)


## Set auto-expand behavior.
func set_auto_expand(enabled: bool) -> void:
	_auto_expand = enabled


## Set expansion size.
func set_expansion_size(size: int) -> void:
	_expansion_size = maxi(1, size)


## Release all active objects.
func release_all() -> void:
	if _thread_safe:
		_mutex.lock()

	for obj in _active.keys():
		if _reset_func.is_valid():
			_reset_func.call(obj)
		_available.append(obj)

	var count := _active.size()
	_active.clear()
	_stats.released_count += count
	_stats.current_active = 0

	if _thread_safe:
		_mutex.unlock()


## Check if pool contains object.
func contains(obj: Variant) -> bool:
	return _active.has(obj) or obj in _available


## Get all active objects.
func get_active_objects() -> Array:
	return _active.keys()


## PoolStatistics helper class.
class PoolStatistics:
	var total_created: int = 0
	var acquired_count: int = 0
	var released_count: int = 0
	var current_active: int = 0
	var peak_active: int = 0
	var expansion_count: int = 0
	var exhaustion_count: int = 0

	func reset() -> void:
		total_created = 0
		acquired_count = 0
		released_count = 0
		current_active = 0
		peak_active = 0
		expansion_count = 0
		exhaustion_count = 0

	func to_dict() -> Dictionary:
		return {
			"total_created": total_created,
			"acquired_count": acquired_count,
			"released_count": released_count,
			"current_active": current_active,
			"peak_active": peak_active,
			"expansion_count": expansion_count,
			"exhaustion_count": exhaustion_count,
			"efficiency": _calculate_efficiency()
		}

	func _calculate_efficiency() -> float:
		if acquired_count == 0:
			return 1.0
		# Efficiency is how well we reused objects
		var reuses := acquired_count - total_created
		if reuses <= 0:
			return 0.0
		return float(reuses) / float(acquired_count)
