class_name WreckHarvesting
extends RefCounted
## WreckHarvesting handles the mechanics of harvester units collecting REE from wrecks.
## Faster than building disassembly with dynamic yield based on wreck size.

signal harvesting_started(wreck_id: int, wreck_type: String, duration: float)
signal harvesting_progress(wreck_id: int, progress: float)
signal harvesting_completed(wreck_id: int, ree_yield: float)
signal harvesting_cancelled(wreck_id: int, reason: String)
signal wreck_flattened(wreck_id: int, position: Vector3)
signal terrain_smoothed(wreck_id: int, position: Vector3, radius: float)

## Wreck types
enum WreckType {
	DESTROYED_BUILDING,
	ROBOT_WRECK,
	VEHICLE_WRECK,
	DEBRIS_PILE
}

## Wreck size categories
enum WreckSize {
	SMALL,   ## 1-2 units
	MEDIUM,  ## 3-5 units
	LARGE,   ## 6-10 units
	MASSIVE  ## 11+ units
}

## Base harvesting times (seconds)
const HARVESTING_TIMES := {
	WreckSize.SMALL: 5.0,
	WreckSize.MEDIUM: 7.0,
	WreckSize.LARGE: 9.0,
	WreckSize.MASSIVE: 10.0
}

## Base REE yield
const BASE_REE_YIELD := 50.0
const REE_PER_SIZE_UNIT := 10.0

## Wreck type multipliers
const TYPE_MULTIPLIERS := {
	WreckType.DESTROYED_BUILDING: 1.0,
	WreckType.ROBOT_WRECK: 1.2,      ## Robots give more REE
	WreckType.VEHICLE_WRECK: 1.5,    ## Vehicles give most REE
	WreckType.DEBRIS_PILE: 0.8       ## Debris gives less
}

## Active harvesting operations
var _active_operations: Dictionary = {}  ## wreck_id -> HarvestOperation
var _depleted_wrecks: Array[int] = []

## Target prioritization
const PRIORITY_WRECK := 2          ## Wrecks have higher priority
const PRIORITY_BUILDING := 1       ## Buildings have lower priority


func _init() -> void:
	pass


## Start harvesting a wreck.
func start_harvesting(wreck_id: int, wreck_type: WreckType, wreck_position: Vector3,
					  wreck_size: int) -> bool:
	# Already being harvested
	if _active_operations.has(wreck_id):
		return false

	# Already depleted
	if wreck_id in _depleted_wrecks:
		return false

	var size_category := _get_size_category(wreck_size)
	var duration: float = HARVESTING_TIMES[size_category]
	var ree_yield := _calculate_yield(wreck_type, wreck_size)

	var operation := HarvestOperation.new()
	operation.wreck_id = wreck_id
	operation.wreck_type = wreck_type
	operation.wreck_size = wreck_size
	operation.position = wreck_position
	operation.duration = duration
	operation.ree_yield = ree_yield
	operation.progress = 0.0
	operation.is_active = true

	_active_operations[wreck_id] = operation

	harvesting_started.emit(wreck_id, _get_wreck_type_name(wreck_type), duration)
	return true


## Update harvesting progress.
func update_harvesting(wreck_id: int, delta: float) -> bool:
	if not _active_operations.has(wreck_id):
		return false

	var operation: HarvestOperation = _active_operations[wreck_id]
	if not operation.is_active:
		return false

	operation.progress += delta
	harvesting_progress.emit(wreck_id, operation.progress / operation.duration)

	if operation.progress >= operation.duration:
		_complete_harvesting(wreck_id)
		return true

	return false


## Complete harvesting and return REE yield.
func _complete_harvesting(wreck_id: int) -> void:
	if not _active_operations.has(wreck_id):
		return

	var operation: HarvestOperation = _active_operations[wreck_id]
	var ree_yield := operation.ree_yield
	var position := operation.position
	var wreck_size := operation.wreck_size

	operation.is_active = false
	_depleted_wrecks.append(wreck_id)
	_active_operations.erase(wreck_id)

	harvesting_completed.emit(wreck_id, ree_yield)
	wreck_flattened.emit(wreck_id, position)

	# Smooth terrain where wreck was (radius based on size)
	var smooth_radius := 2.0 + wreck_size * 0.5
	terrain_smoothed.emit(wreck_id, position, smooth_radius)


## Cancel ongoing harvesting.
func cancel_harvesting(wreck_id: int, reason: String = "cancelled") -> void:
	if not _active_operations.has(wreck_id):
		return

	_active_operations.erase(wreck_id)
	harvesting_cancelled.emit(wreck_id, reason)


## Calculate yield based on wreck type and size.
func _calculate_yield(wreck_type: WreckType, wreck_size: int) -> float:
	var base := BASE_REE_YIELD + (wreck_size * REE_PER_SIZE_UNIT)
	var multiplier: float = TYPE_MULTIPLIERS[wreck_type]
	return base * multiplier


## Get size category from size value.
func _get_size_category(wreck_size: int) -> WreckSize:
	if wreck_size <= 2:
		return WreckSize.SMALL
	elif wreck_size <= 5:
		return WreckSize.MEDIUM
	elif wreck_size <= 10:
		return WreckSize.LARGE
	else:
		return WreckSize.MASSIVE


## Check if wreck can be harvested.
func can_harvest(wreck_id: int) -> bool:
	# Already being harvested
	if _active_operations.has(wreck_id):
		return false

	# Already depleted
	if wreck_id in _depleted_wrecks:
		return false

	return true


## Get harvesting progress for wreck.
func get_progress(wreck_id: int) -> float:
	if not _active_operations.has(wreck_id):
		return 0.0

	var operation: HarvestOperation = _active_operations[wreck_id]
	return operation.progress / operation.duration


## Get remaining time for wreck.
func get_remaining_time(wreck_id: int) -> float:
	if not _active_operations.has(wreck_id):
		return 0.0

	var operation: HarvestOperation = _active_operations[wreck_id]
	return maxf(0.0, operation.duration - operation.progress)


## Get expected REE yield for wreck.
func get_expected_yield(wreck_type: WreckType, wreck_size: int) -> float:
	return _calculate_yield(wreck_type, wreck_size)


## Get expected duration for wreck size.
func get_expected_duration(wreck_size: int) -> float:
	var category := _get_size_category(wreck_size)
	return HARVESTING_TIMES[category]


## Get wreck type from string.
static func get_wreck_type(type_name: String) -> WreckType:
	match type_name.to_lower():
		"destroyed_building", "building": return WreckType.DESTROYED_BUILDING
		"robot_wreck", "robot": return WreckType.ROBOT_WRECK
		"vehicle_wreck", "vehicle": return WreckType.VEHICLE_WRECK
		"debris_pile", "debris": return WreckType.DEBRIS_PILE
		_: return WreckType.DEBRIS_PILE


## Get wreck type name.
func _get_wreck_type_name(wreck_type: WreckType) -> String:
	match wreck_type:
		WreckType.DESTROYED_BUILDING: return "Destroyed Building"
		WreckType.ROBOT_WRECK: return "Robot Wreck"
		WreckType.VEHICLE_WRECK: return "Vehicle Wreck"
		WreckType.DEBRIS_PILE: return "Debris Pile"
	return "Unknown"


## Get target priority for wreck (higher = more important).
static func get_priority() -> int:
	return PRIORITY_WRECK


## Is wreck being harvested.
func is_harvesting(wreck_id: int) -> bool:
	return _active_operations.has(wreck_id)


## Was wreck already depleted.
func was_depleted(wreck_id: int) -> bool:
	return wreck_id in _depleted_wrecks


## Get active operation count.
func get_active_count() -> int:
	return _active_operations.size()


## Get all active wreck IDs.
func get_active_wreck_ids() -> Array[int]:
	var result: Array[int] = []
	for wreck_id in _active_operations:
		result.append(wreck_id)
	return result


## Clear depleted wrecks list.
func clear_depleted() -> void:
	_depleted_wrecks.clear()


## Get statistics.
func get_statistics() -> Dictionary:
	var total_progress := 0.0
	var total_yield := 0.0
	for wreck_id in _active_operations:
		var op: HarvestOperation = _active_operations[wreck_id]
		total_progress += op.progress / op.duration
		total_yield += op.ree_yield

	return {
		"active_operations": _active_operations.size(),
		"depleted_wrecks": _depleted_wrecks.size(),
		"average_progress": total_progress / maxf(1, _active_operations.size()),
		"pending_yield": total_yield
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var operations := {}
	for wreck_id in _active_operations:
		var op: HarvestOperation = _active_operations[wreck_id]
		operations[str(wreck_id)] = op.to_dict()

	return {
		"active_operations": operations,
		"depleted_wrecks": _depleted_wrecks.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_active_operations.clear()
	_depleted_wrecks.clear()

	var operations: Dictionary = data.get("active_operations", {})
	for key in operations:
		var op := HarvestOperation.new()
		op.from_dict(operations[key])
		_active_operations[int(key)] = op

	var depleted: Array = data.get("depleted_wrecks", [])
	for wreck_id in depleted:
		_depleted_wrecks.append(wreck_id)


## HarvestOperation inner class.
class HarvestOperation:
	var wreck_id: int = -1
	var wreck_type: WreckType = WreckType.DEBRIS_PILE
	var wreck_size: int = 1
	var position: Vector3 = Vector3.ZERO
	var duration: float = 5.0
	var ree_yield: float = 50.0
	var progress: float = 0.0
	var is_active: bool = false

	func to_dict() -> Dictionary:
		return {
			"wreck_id": wreck_id,
			"wreck_type": wreck_type,
			"wreck_size": wreck_size,
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"duration": duration,
			"ree_yield": ree_yield,
			"progress": progress,
			"is_active": is_active
		}

	func from_dict(data: Dictionary) -> void:
		wreck_id = data.get("wreck_id", -1)
		wreck_type = data.get("wreck_type", WreckType.DEBRIS_PILE)
		wreck_size = data.get("wreck_size", 1)
		var pos: Dictionary = data.get("position", {})
		position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		duration = data.get("duration", 5.0)
		ree_yield = data.get("ree_yield", 50.0)
		progress = data.get("progress", 0.0)
		is_active = data.get("is_active", false)
