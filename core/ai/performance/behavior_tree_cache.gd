class_name BehaviorTreeCache
extends RefCounted
## BehaviorTreeCache reuses behavior trees for same unit type and faction.
## Reduces memory overhead through shared instances.

signal cache_hit(unit_type: String, faction_id: String)
signal cache_miss(unit_type: String, faction_id: String)
signal cache_created(cache_key: String)

## Cached trees (cache_key -> BTNode)
var _cache: Dictionary = {}

## Reference counts (cache_key -> count)
var _ref_counts: Dictionary = {}

## Unit to cache key mapping (unit_id -> cache_key)
var _unit_cache_keys: Dictionary = {}

## Cache statistics
var _hits := 0
var _misses := 0


func _init() -> void:
	pass


## Generate cache key for unit type and faction.
func _get_cache_key(unit_type: String, faction_id: String) -> String:
	return faction_id + "_" + unit_type


## Get or create cached behavior tree.
func get_tree(unit_id: int, unit_type: String, faction_id: String, tree_factory: Callable) -> LimboAIWrapper.BTNode:
	var cache_key := _get_cache_key(unit_type, faction_id)

	if _cache.has(cache_key):
		_hits += 1
		_ref_counts[cache_key] += 1
		_unit_cache_keys[unit_id] = cache_key
		cache_hit.emit(unit_type, faction_id)
		return _cache[cache_key]

	# Create new tree
	_misses += 1
	cache_miss.emit(unit_type, faction_id)

	if not tree_factory.is_valid():
		return null

	var tree: LimboAIWrapper.BTNode = tree_factory.call(unit_type, faction_id)

	if tree != null:
		_cache[cache_key] = tree
		_ref_counts[cache_key] = 1
		_unit_cache_keys[unit_id] = cache_key
		cache_created.emit(cache_key)

	return tree


## Release unit's reference to cached tree.
func release_unit(unit_id: int) -> void:
	if not _unit_cache_keys.has(unit_id):
		return

	var cache_key: String = _unit_cache_keys[unit_id]
	_unit_cache_keys.erase(unit_id)

	if _ref_counts.has(cache_key):
		_ref_counts[cache_key] -= 1

		# Don't actually remove the tree - keep it for future units
		# Only remove if we're memory constrained


## Check if tree exists in cache.
func has_tree(unit_type: String, faction_id: String) -> bool:
	var cache_key := _get_cache_key(unit_type, faction_id)
	return _cache.has(cache_key)


## Get reference count for cache key.
func get_ref_count(unit_type: String, faction_id: String) -> int:
	var cache_key := _get_cache_key(unit_type, faction_id)
	return _ref_counts.get(cache_key, 0)


## Invalidate cache for faction (call when faction progression changes).
func invalidate_faction(faction_id: String) -> void:
	var keys_to_remove: Array[String] = []

	for cache_key in _cache:
		if cache_key.begins_with(faction_id + "_"):
			keys_to_remove.append(cache_key)

	for key in keys_to_remove:
		_cache.erase(key)
		_ref_counts.erase(key)

	# Update unit mappings
	var units_to_update: Array[int] = []
	for unit_id in _unit_cache_keys:
		if _unit_cache_keys[unit_id] in keys_to_remove:
			units_to_update.append(unit_id)

	for unit_id in units_to_update:
		_unit_cache_keys.erase(unit_id)


## Clear entire cache.
func clear() -> void:
	_cache.clear()
	_ref_counts.clear()
	_unit_cache_keys.clear()


## Get cache hit ratio.
func get_hit_ratio() -> float:
	var total := _hits + _misses
	if total == 0:
		return 0.0
	return float(_hits) / float(total)


## Get memory estimate (approximate).
func get_memory_estimate() -> int:
	# Rough estimate: each tree is ~1KB
	return _cache.size() * 1024


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"cached_trees": _cache.size(),
		"active_units": _unit_cache_keys.size(),
		"cache_hits": _hits,
		"cache_misses": _misses,
		"hit_ratio": get_hit_ratio(),
		"memory_estimate_kb": get_memory_estimate() / 1024
	}
