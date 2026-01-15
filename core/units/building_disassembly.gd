class_name BuildingDisassembly
extends RefCounted
## BuildingDisassembly handles the mechanics of harvester units disassembling intact buildings.
## Different building types have different disassembly times and yields.

signal disassembly_started(building_id: int, building_type: String, duration: float)
signal disassembly_progress(building_id: int, progress: float)
signal disassembly_completed(building_id: int, ree_yield: float)
signal disassembly_cancelled(building_id: int, reason: String)
signal building_flattened(building_id: int, position: Vector3)

## Building type configurations
enum BuildingType {
	INDUSTRIAL,
	RESIDENTIAL,
	COMMERCIAL,
	OTHER
}

## Disassembly times (seconds)
const DISASSEMBLY_TIMES := {
	BuildingType.INDUSTRIAL: 20.0,
	BuildingType.RESIDENTIAL: 30.0,
	BuildingType.COMMERCIAL: 25.0,
	BuildingType.OTHER: 25.0
}

## REE yields
const REE_YIELDS := {
	BuildingType.INDUSTRIAL: 200.0,
	BuildingType.RESIDENTIAL: 100.0,
	BuildingType.COMMERCIAL: 150.0,
	BuildingType.OTHER: 150.0
}

## Active disassembly operations
var _active_operations: Dictionary = {}  ## building_id -> DisassemblyOperation
var _completed_buildings: Array[int] = []


func _init() -> void:
	pass


## Start disassembly of a building.
## building_type should be a BuildingDisassembly.BuildingType enum value (int)
func start_disassembly(building_id: int, building_type: int,
					   building_position: Vector3, harvester_faction: int,
					   building_faction: int) -> bool:
	# Can't disassemble own faction's buildings
	if harvester_faction == building_faction:
		return false

	# Already being disassembled
	if _active_operations.has(building_id):
		return false

	# Already completed
	if building_id in _completed_buildings:
		return false

	var duration: float = DISASSEMBLY_TIMES[building_type]
	var ree_yield: float = REE_YIELDS[building_type]

	var operation := DisassemblyOperation.new()
	operation.building_id = building_id
	operation.building_type = building_type
	operation.position = building_position
	operation.duration = duration
	operation.ree_yield = ree_yield
	operation.progress = 0.0
	operation.is_active = true

	_active_operations[building_id] = operation

	disassembly_started.emit(building_id, _get_building_type_name(building_type), duration)
	return true


## Update disassembly progress.
func update_disassembly(building_id: int, delta: float) -> bool:
	if not _active_operations.has(building_id):
		return false

	var operation: DisassemblyOperation = _active_operations[building_id]
	if not operation.is_active:
		return false

	operation.progress += delta
	disassembly_progress.emit(building_id, operation.progress / operation.duration)

	if operation.progress >= operation.duration:
		_complete_disassembly(building_id)
		return true

	return false


## Complete disassembly and return REE yield.
func _complete_disassembly(building_id: int) -> void:
	if not _active_operations.has(building_id):
		return

	var operation: DisassemblyOperation = _active_operations[building_id]
	var ree_yield := operation.ree_yield
	var position := operation.position

	operation.is_active = false
	_completed_buildings.append(building_id)
	_active_operations.erase(building_id)

	disassembly_completed.emit(building_id, ree_yield)
	building_flattened.emit(building_id, position)


## Cancel ongoing disassembly.
func cancel_disassembly(building_id: int, reason: String = "cancelled") -> void:
	if not _active_operations.has(building_id):
		return

	_active_operations.erase(building_id)
	disassembly_cancelled.emit(building_id, reason)


## Check if building can be disassembled.
func can_disassemble(building_id: int, harvester_faction: int, building_faction: int) -> bool:
	# Can't disassemble own buildings
	if harvester_faction == building_faction:
		return false

	# Already being or was disassembled
	if _active_operations.has(building_id):
		return false

	if building_id in _completed_buildings:
		return false

	return true


## Get disassembly progress for building.
func get_progress(building_id: int) -> float:
	if not _active_operations.has(building_id):
		return 0.0

	var operation: DisassemblyOperation = _active_operations[building_id]
	return operation.progress / operation.duration


## Get remaining time for building.
func get_remaining_time(building_id: int) -> float:
	if not _active_operations.has(building_id):
		return 0.0

	var operation: DisassemblyOperation = _active_operations[building_id]
	return maxf(0.0, operation.duration - operation.progress)


## Get expected REE yield for building type.
static func get_expected_yield(building_type: int) -> float:
	return REE_YIELDS[building_type]


## Get expected duration for building type.
static func get_expected_duration(building_type: int) -> float:
	return DISASSEMBLY_TIMES[building_type]


## Get building type from string.
static func get_building_type(type_name: String) -> int:
	match type_name.to_lower():
		"industrial": return BuildingDisassembly.BuildingType.INDUSTRIAL
		"residential": return BuildingDisassembly.BuildingType.RESIDENTIAL
		"commercial": return BuildingDisassembly.BuildingType.COMMERCIAL
		_: return BuildingDisassembly.BuildingType.OTHER


## Get building type name.
func _get_building_type_name(building_type: int) -> String:
	match building_type:
		BuildingDisassembly.BuildingType.INDUSTRIAL: return "Industrial"
		BuildingDisassembly.BuildingType.RESIDENTIAL: return "Residential"
		BuildingDisassembly.BuildingType.COMMERCIAL: return "Commercial"
		BuildingDisassembly.BuildingType.OTHER: return "Other"
	return "Unknown"


## Is building being disassembled.
func is_disassembling(building_id: int) -> bool:
	return _active_operations.has(building_id)


## Was building already disassembled.
func was_disassembled(building_id: int) -> bool:
	return building_id in _completed_buildings


## Get active operation count.
func get_active_count() -> int:
	return _active_operations.size()


## Get all active building IDs.
func get_active_building_ids() -> Array[int]:
	var result: Array[int] = []
	for building_id in _active_operations:
		result.append(building_id)
	return result


## Clear completed buildings list.
func clear_completed() -> void:
	_completed_buildings.clear()


## Get statistics.
func get_statistics() -> Dictionary:
	var total_progress := 0.0
	for building_id in _active_operations:
		var op: DisassemblyOperation = _active_operations[building_id]
		total_progress += op.progress / op.duration

	return {
		"active_operations": _active_operations.size(),
		"completed_buildings": _completed_buildings.size(),
		"average_progress": total_progress / maxf(1, _active_operations.size())
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var operations := {}
	for building_id in _active_operations:
		var op: DisassemblyOperation = _active_operations[building_id]
		operations[str(building_id)] = op.to_dict()

	return {
		"active_operations": operations,
		"completed_buildings": _completed_buildings.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_active_operations.clear()
	_completed_buildings.clear()

	var operations: Dictionary = data.get("active_operations", {})
	for key in operations:
		var op := DisassemblyOperation.new()
		op.from_dict(operations[key])
		_active_operations[int(key)] = op

	var completed: Array = data.get("completed_buildings", [])
	for building_id in completed:
		_completed_buildings.append(building_id)


## DisassemblyOperation inner class.
class DisassemblyOperation:
	var building_id: int = -1
	var building_type: int = BuildingDisassembly.BuildingType.OTHER
	var position: Vector3 = Vector3.ZERO
	var duration: float = 25.0
	var ree_yield: float = 150.0
	var progress: float = 0.0
	var is_active: bool = false

	func to_dict() -> Dictionary:
		return {
			"building_id": building_id,
			"building_type": building_type,
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"duration": duration,
			"ree_yield": ree_yield,
			"progress": progress,
			"is_active": is_active
		}

	func from_dict(data: Dictionary) -> void:
		building_id = data.get("building_id", -1)
		building_type = data.get("building_type", BuildingDisassembly.BuildingType.OTHER)
		var pos: Dictionary = data.get("position", {})
		position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		duration = data.get("duration", 25.0)
		ree_yield = data.get("ree_yield", 150.0)
		progress = data.get("progress", 0.0)
		is_active = data.get("is_active", false)
