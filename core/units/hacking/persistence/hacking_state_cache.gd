class_name HackingStateCache
extends RefCounted
## HackingStateCache provides fast lookup for hacking state data.

## Cached states (unit_id -> HackingState)
var _cache: Dictionary = {}

## Cache dirty flags (unit_id -> bool)
var _dirty: Dictionary = {}

## Last access times (unit_id -> timestamp)
var _access_times: Dictionary = {}

## Maximum cache size
var max_cache_size: int = 1000

## Cache statistics
var _stats: Dictionary = {
	"hits": 0,
	"misses": 0,
	"evictions": 0
}


func _init() -> void:
	pass


## Get cached state.
func get_state(unit_id: int) -> HackingState:
	if _cache.has(unit_id):
		_stats["hits"] += 1
		_access_times[unit_id] = Time.get_ticks_msec()
		return _cache[unit_id]

	_stats["misses"] += 1
	return null


## Set cached state.
func set_state(unit_id: int, state: HackingState) -> void:
	# Check cache size
	if not _cache.has(unit_id) and _cache.size() >= max_cache_size:
		_evict_oldest()

	_cache[unit_id] = state
	_dirty[unit_id] = true
	_access_times[unit_id] = Time.get_ticks_msec()


## Remove cached state.
func remove_state(unit_id: int) -> void:
	_cache.erase(unit_id)
	_dirty.erase(unit_id)
	_access_times.erase(unit_id)


## Mark state as dirty (needs sync).
func mark_dirty(unit_id: int) -> void:
	if _cache.has(unit_id):
		_dirty[unit_id] = true


## Mark state as clean (synced).
func mark_clean(unit_id: int) -> void:
	_dirty[unit_id] = false


## Get all dirty states.
func get_dirty_states() -> Array[HackingState]:
	var dirty_states: Array[HackingState] = []

	for unit_id in _dirty:
		if _dirty[unit_id] and _cache.has(unit_id):
			dirty_states.append(_cache[unit_id])

	return dirty_states


## Get dirty unit IDs.
func get_dirty_unit_ids() -> Array[int]:
	var ids: Array[int] = []

	for unit_id in _dirty:
		if _dirty[unit_id]:
			ids.append(unit_id)

	return ids


## Clear all dirty flags.
func clear_dirty_flags() -> void:
	for unit_id in _dirty:
		_dirty[unit_id] = false


## Evict oldest entry.
func _evict_oldest() -> void:
	var oldest_id := -1
	var oldest_time := INF

	for unit_id in _access_times:
		if _access_times[unit_id] < oldest_time:
			oldest_time = _access_times[unit_id]
			oldest_id = unit_id

	if oldest_id >= 0:
		remove_state(oldest_id)
		_stats["evictions"] += 1


## Check if unit is cached.
func has_state(unit_id: int) -> bool:
	return _cache.has(unit_id)


## Get all cached states.
func get_all_states() -> Array[HackingState]:
	var states: Array[HackingState] = []
	for unit_id in _cache:
		states.append(_cache[unit_id])
	return states


## Clear cache.
func clear() -> void:
	_cache.clear()
	_dirty.clear()
	_access_times.clear()


## Get statistics.
func get_stats() -> Dictionary:
	var total := _stats["hits"] + _stats["misses"]
	var hit_rate := float(_stats["hits"]) / float(total) if total > 0 else 0.0

	return {
		"hits": _stats["hits"],
		"misses": _stats["misses"],
		"evictions": _stats["evictions"],
		"hit_rate": "%.1f%%" % (hit_rate * 100),
		"size": _cache.size(),
		"dirty_count": get_dirty_unit_ids().size()
	}


## Get summary for debugging.
func get_summary() -> Dictionary:
	return get_stats()
