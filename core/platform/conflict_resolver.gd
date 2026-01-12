class_name ConflictResolver
extends RefCounted
## ConflictResolver handles data conflict resolution between local and cloud saves.
## Provides automatic merging for compatible changes and manual resolution for conflicts.

signal resolution_required(conflict: Dictionary)
signal conflict_resolved(key: String, resolution: String)
signal auto_merged(key: String, merged_data: Dictionary)

## Resolution strategies
enum ResolutionStrategy {
	KEEP_LOCAL,     ## Always prefer local data
	USE_CLOUD,      ## Always prefer cloud data
	PREFER_NEWER,   ## Use whichever is newer
	MANUAL          ## Require user input
}

## Configuration
var default_strategy := ResolutionStrategy.MANUAL

## Merge rules for specific data types
var _merge_rules: Dictionary = {}

## Pending resolutions
var _pending_conflicts: Array[ConflictData] = []


func _init() -> void:
	_register_default_merge_rules()


## Register default merge rules.
func _register_default_merge_rules() -> void:
	# Achievements - union of both sets (can't un-unlock)
	register_merge_rule("achievements", func(local, cloud):
		var merged := {}
		for key in local:
			merged[key] = local[key]
		for key in cloud:
			# If achievement is unlocked in either, it stays unlocked
			if cloud[key].get("unlocked", false):
				merged[key] = cloud[key]
			elif not merged.has(key):
				merged[key] = cloud[key]
		return merged
	)

	# Statistics - take maximum values
	register_merge_rule("statistics", func(local, cloud):
		var merged := {}
		var all_keys := {}
		for key in local:
			all_keys[key] = true
		for key in cloud:
			all_keys[key] = true

		for key in all_keys:
			var local_val = local.get(key, 0)
			var cloud_val = cloud.get(key, 0)
			# For most stats, higher is better
			if key.contains("time") or key.contains("fastest"):
				# For time-based, lower might be better
				merged[key] = mini(local_val, cloud_val) if local_val > 0 and cloud_val > 0 else maxi(local_val, cloud_val)
			else:
				merged[key] = maxi(local_val, cloud_val)
		return merged
	)

	# Settings - prefer local (user's current machine)
	register_merge_rule("settings", func(local, _cloud):
		return local
	)

	# Progression - merge with preference for higher progress
	register_merge_rule("progression", func(local, cloud):
		var merged := cloud.duplicate(true)
		for key in local:
			var local_val = local[key]
			var cloud_val = cloud.get(key, null)

			if cloud_val == null:
				merged[key] = local_val
			elif local_val is int and cloud_val is int:
				merged[key] = maxi(local_val, cloud_val)
			elif local_val is float and cloud_val is float:
				merged[key] = maxf(local_val, cloud_val)
			elif local_val is bool and cloud_val is bool:
				# For booleans, true usually means unlocked/completed
				merged[key] = local_val or cloud_val
			elif local_val is Dictionary and cloud_val is Dictionary:
				# Recursively merge dictionaries
				merged[key] = _merge_dictionaries(local_val, cloud_val)
		return merged
	)


## Register a custom merge rule.
func register_merge_rule(data_key: String, merge_func: Callable) -> void:
	_merge_rules[data_key] = merge_func


## Attempt to resolve a conflict.
func resolve_conflict(conflict_data: Dictionary) -> Dictionary:
	var key: String = conflict_data.get("key", "")
	var local_data: Dictionary = conflict_data.get("local_data", {})
	var cloud_data: Dictionary = conflict_data.get("cloud_data", {})
	var local_timestamp: int = conflict_data.get("local_timestamp", 0)
	var cloud_timestamp: int = conflict_data.get("cloud_timestamp", 0)

	# Try automatic merge first
	if _merge_rules.has(key):
		var merge_func: Callable = _merge_rules[key]
		var merged: Dictionary = merge_func.call(local_data, cloud_data)
		auto_merged.emit(key, merged)
		return {
			"resolved": true,
			"strategy": "auto_merge",
			"data": merged
		}

	# Apply default strategy
	match default_strategy:
		ResolutionStrategy.KEEP_LOCAL:
			return {
				"resolved": true,
				"strategy": "keep_local",
				"data": local_data
			}

		ResolutionStrategy.USE_CLOUD:
			return {
				"resolved": true,
				"strategy": "use_cloud",
				"data": cloud_data
			}

		ResolutionStrategy.PREFER_NEWER:
			var use_local := local_timestamp > cloud_timestamp
			return {
				"resolved": true,
				"strategy": "prefer_newer",
				"data": local_data if use_local else cloud_data
			}

		ResolutionStrategy.MANUAL:
			# Queue for manual resolution
			var pending := ConflictData.new()
			pending.key = key
			pending.local_data = local_data
			pending.cloud_data = cloud_data
			pending.local_timestamp = local_timestamp
			pending.cloud_timestamp = cloud_timestamp
			_pending_conflicts.append(pending)

			resolution_required.emit(conflict_data)
			return {
				"resolved": false,
				"strategy": "manual",
				"pending": true
			}

	return {"resolved": false}


## Manual resolution - keep local.
func resolve_manual_keep_local(key: String) -> Dictionary:
	for i in _pending_conflicts.size():
		if _pending_conflicts[i].key == key:
			var data := _pending_conflicts[i].local_data.duplicate(true)
			_pending_conflicts.remove_at(i)
			conflict_resolved.emit(key, "keep_local")
			return data
	return {}


## Manual resolution - use cloud.
func resolve_manual_use_cloud(key: String) -> Dictionary:
	for i in _pending_conflicts.size():
		if _pending_conflicts[i].key == key:
			var data := _pending_conflicts[i].cloud_data.duplicate(true)
			_pending_conflicts.remove_at(i)
			conflict_resolved.emit(key, "use_cloud")
			return data
	return {}


## Manual resolution - custom merge.
func resolve_manual_merge(key: String, merged_data: Dictionary) -> void:
	for i in _pending_conflicts.size():
		if _pending_conflicts[i].key == key:
			_pending_conflicts.remove_at(i)
			conflict_resolved.emit(key, "manual_merge")
			break


## Get pending conflicts.
func get_pending_conflicts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for conflict in _pending_conflicts:
		result.append({
			"key": conflict.key,
			"local_data": conflict.local_data,
			"cloud_data": conflict.cloud_data,
			"local_timestamp": conflict.local_timestamp,
			"cloud_timestamp": conflict.cloud_timestamp
		})
	return result


## Has pending conflicts.
func has_pending_conflicts() -> bool:
	return not _pending_conflicts.is_empty()


## Get conflict for key.
func get_conflict(key: String) -> Dictionary:
	for conflict in _pending_conflicts:
		if conflict.key == key:
			return {
				"key": conflict.key,
				"local_data": conflict.local_data,
				"cloud_data": conflict.cloud_data,
				"local_timestamp": conflict.local_timestamp,
				"cloud_timestamp": conflict.cloud_timestamp
			}
	return {}


## Merge two dictionaries recursively.
func _merge_dictionaries(local: Dictionary, cloud: Dictionary) -> Dictionary:
	var merged := cloud.duplicate(true)

	for key in local:
		if not cloud.has(key):
			merged[key] = local[key]
		elif local[key] is Dictionary and cloud[key] is Dictionary:
			merged[key] = _merge_dictionaries(local[key], cloud[key])
		elif local[key] is int and cloud[key] is int:
			merged[key] = maxi(local[key], cloud[key])
		elif local[key] is float and cloud[key] is float:
			merged[key] = maxf(local[key], cloud[key])
		elif local[key] is bool and cloud[key] is bool:
			merged[key] = local[key] or cloud[key]
		# For other types, prefer local

	return merged


## Generate diff between local and cloud.
static func generate_diff(local: Dictionary, cloud: Dictionary) -> Dictionary:
	var diff := {
		"local_only": {},
		"cloud_only": {},
		"different": {},
		"same": {}
	}

	# Keys only in local
	for key in local:
		if not cloud.has(key):
			diff["local_only"][key] = local[key]
		elif local[key] != cloud[key]:
			diff["different"][key] = {
				"local": local[key],
				"cloud": cloud[key]
			}
		else:
			diff["same"][key] = local[key]

	# Keys only in cloud
	for key in cloud:
		if not local.has(key):
			diff["cloud_only"][key] = cloud[key]

	return diff


## Set default strategy.
func set_default_strategy(strategy: ResolutionStrategy) -> void:
	default_strategy = strategy


## Clear all pending conflicts.
func clear_pending() -> void:
	_pending_conflicts.clear()


## ConflictData helper class.
class ConflictData:
	var key: String = ""
	var local_data: Dictionary = {}
	var cloud_data: Dictionary = {}
	var local_timestamp: int = 0
	var cloud_timestamp: int = 0
