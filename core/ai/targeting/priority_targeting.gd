class_name PriorityTargeting
extends RefCounted
## PriorityTargeting implements strategic target priority (buildings > ranged > melee).

## Unit types for priority
enum UnitType {
	UNKNOWN,
	BUILDING,
	RANGED,
	MELEE,
	SUPPORT,
	SIEGE
}

## Priority weights (higher = more priority)
const PRIORITY_BUILDING := 1.0
const PRIORITY_SIEGE := 0.9
const PRIORITY_RANGED := 0.8
const PRIORITY_SUPPORT := 0.7
const PRIORITY_MELEE := 0.5
const PRIORITY_UNKNOWN := 0.3

## Distance penalty factor
const DISTANCE_PENALTY_FACTOR := 0.02  ## Per meter

## Health bonus (prioritize low health)
const LOW_HEALTH_BONUS := 0.3
const LOW_HEALTH_THRESHOLD := 0.3  ## 30% health

## Unit type cache (unit_id -> UnitType)
var _unit_types: Dictionary = {}

## Callbacks
var _get_unit_type: Callable  ## (unit_id) -> String
var _get_unit_health_percent: Callable  ## (unit_id) -> float
var _get_unit_position: Callable  ## (unit_id) -> Vector3


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_type(callback: Callable) -> void:
	_get_unit_type = callback


func set_get_unit_health_percent(callback: Callable) -> void:
	_get_unit_health_percent = callback


func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


## Calculate priority score for target.
func calculate_priority(target_id: int, attacker_position: Vector3) -> float:
	var base_priority := _get_type_priority(target_id)

	# Apply distance penalty
	var distance_penalty := 0.0
	if _get_unit_position.is_valid():
		var target_pos: Vector3 = _get_unit_position.call(target_id)
		if target_pos != Vector3.INF:
			var distance := attacker_position.distance_to(target_pos)
			distance_penalty = distance * DISTANCE_PENALTY_FACTOR

	# Apply low health bonus
	var health_bonus := 0.0
	if _get_unit_health_percent.is_valid():
		var health: float = _get_unit_health_percent.call(target_id)
		if health < LOW_HEALTH_THRESHOLD:
			health_bonus = LOW_HEALTH_BONUS * (1.0 - health / LOW_HEALTH_THRESHOLD)

	return maxf(0.0, base_priority - distance_penalty + health_bonus)


## Get base priority for unit type.
func _get_type_priority(unit_id: int) -> float:
	var unit_type := _get_cached_type(unit_id)

	match unit_type:
		UnitType.BUILDING:
			return PRIORITY_BUILDING
		UnitType.SIEGE:
			return PRIORITY_SIEGE
		UnitType.RANGED:
			return PRIORITY_RANGED
		UnitType.SUPPORT:
			return PRIORITY_SUPPORT
		UnitType.MELEE:
			return PRIORITY_MELEE
		_:
			return PRIORITY_UNKNOWN


## Get cached unit type.
func _get_cached_type(unit_id: int) -> int:
	if _unit_types.has(unit_id):
		return _unit_types[unit_id]

	var unit_type := _determine_unit_type(unit_id)
	_unit_types[unit_id] = unit_type
	return unit_type


## Determine unit type from callback.
func _determine_unit_type(unit_id: int) -> int:
	if not _get_unit_type.is_valid():
		return UnitType.UNKNOWN

	var type_string: String = _get_unit_type.call(unit_id)

	match type_string.to_lower():
		"building", "structure", "tower", "base":
			return UnitType.BUILDING
		"ranged", "archer", "gunner", "sniper":
			return UnitType.RANGED
		"melee", "infantry", "warrior", "brawler":
			return UnitType.MELEE
		"support", "healer", "medic", "buffer":
			return UnitType.SUPPORT
		"siege", "artillery", "catapult", "cannon":
			return UnitType.SIEGE
		_:
			return UnitType.UNKNOWN


## Get highest priority target from list.
func get_highest_priority(target_ids: Array[int], attacker_position: Vector3) -> int:
	var highest_priority := 0.0
	var highest_id := -1

	for target_id in target_ids:
		var priority := calculate_priority(target_id, attacker_position)
		if priority > highest_priority:
			highest_priority = priority
			highest_id = target_id

	return highest_id


## Get targets sorted by priority.
func get_targets_by_priority(target_ids: Array[int], attacker_position: Vector3) -> Array[int]:
	var priority_list: Array[Dictionary] = []

	for target_id in target_ids:
		priority_list.append({
			"id": target_id,
			"priority": calculate_priority(target_id, attacker_position)
		})

	priority_list.sort_custom(func(a, b): return a["priority"] > b["priority"])

	var sorted: Array[int] = []
	for entry in priority_list:
		sorted.append(entry["id"])

	return sorted


## Set unit type manually.
func set_unit_type(unit_id: int, unit_type: int) -> void:
	_unit_types[unit_id] = unit_type


## Clear cached type for unit.
func clear_unit(unit_id: int) -> void:
	_unit_types.erase(unit_id)


## Clear all cached types.
func clear_all() -> void:
	_unit_types.clear()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var types_data: Dictionary = {}
	for unit_id in _unit_types:
		types_data[str(unit_id)] = _unit_types[unit_id]

	return {"unit_types": types_data}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_types.clear()
	for unit_id_str in data.get("unit_types", {}):
		_unit_types[int(unit_id_str)] = data["unit_types"][unit_id_str]


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_counts: Dictionary = {}
	for type_val in UnitType.values():
		type_counts[UnitType.keys()[type_val]] = 0

	for unit_id in _unit_types:
		var type_name: String = UnitType.keys()[_unit_types[unit_id]]
		type_counts[type_name] += 1

	return {
		"cached_units": _unit_types.size(),
		"type_distribution": type_counts
	}
