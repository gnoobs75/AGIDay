class_name HarvesterDisassembly
extends RefCounted
## HarvesterDisassembly manages continuous disassembly progress over time.
## Bypasses intermediate stages for direct transition to rubble.

signal disassembly_started(position: Vector3i, harvester_id: int)
signal disassembly_progress(position: Vector3i, progress: float)
signal disassembly_complete(position: Vector3i, harvester_id: int, faction_id: String)
signal disassembly_cancelled(position: Vector3i, harvester_id: int)

## Active disassembly operations (pos_key -> DisassemblyOperation)
var _operations: Dictionary = {}


## Disassembly operation data
class DisassemblyOperation:
	var position: Vector3i
	var harvester_id: int
	var faction_id: String
	var target_stage: int
	var total_time: float
	var elapsed_time: float
	var progress: float

	func _init(pos: Vector3i, harvester: int, faction: String, stage: int) -> void:
		position = pos
		harvester_id = harvester
		faction_id = faction
		target_stage = stage
		total_time = VoxelStage.get_disassembly_time(stage)
		elapsed_time = 0.0
		progress = 0.0

	func update(delta: float) -> bool:
		if total_time <= 0:
			progress = 1.0
			return true

		elapsed_time += delta
		progress = clampf(elapsed_time / total_time, 0.0, 1.0)
		return progress >= 1.0


func _init() -> void:
	pass


## Start disassembly of voxel.
func start_disassembly(
	position: Vector3i,
	harvester_id: int,
	faction_id: String,
	current_stage: int
) -> bool:
	var key := _get_position_key(position)

	# Check if already being disassembled
	if _operations.has(key):
		return false

	# Can't disassemble crater
	if current_stage == VoxelStage.Stage.CRATER:
		return false

	var operation := DisassemblyOperation.new(
		position,
		harvester_id,
		faction_id,
		current_stage
	)

	_operations[key] = operation
	disassembly_started.emit(position, harvester_id)

	return true


## Cancel disassembly.
func cancel_disassembly(position: Vector3i) -> bool:
	var key := _get_position_key(position)
	var operation: DisassemblyOperation = _operations.get(key)

	if operation == null:
		return false

	disassembly_cancelled.emit(position, operation.harvester_id)
	_operations.erase(key)

	return true


## Process all disassembly operations.
func process(delta: float) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []

	for key in _operations:
		var operation: DisassemblyOperation = _operations[key]
		var is_complete := operation.update(delta)

		disassembly_progress.emit(operation.position, operation.progress)

		if is_complete:
			completed.append({
				"position": operation.position,
				"harvester_id": operation.harvester_id,
				"faction_id": operation.faction_id
			})

	# Remove completed operations
	for data in completed:
		var op_key := _get_position_key(data["position"])
		var operation: DisassemblyOperation = _operations.get(op_key)

		if operation != null:
			disassembly_complete.emit(
				operation.position,
				operation.harvester_id,
				operation.faction_id
			)
			_operations.erase(op_key)

	return completed


## Get disassembly progress.
func get_progress(position: Vector3i) -> float:
	var key := _get_position_key(position)
	var operation: DisassemblyOperation = _operations.get(key)
	return operation.progress if operation != null else 0.0


## Check if position is being disassembled.
func is_disassembling(position: Vector3i) -> bool:
	var key := _get_position_key(position)
	return _operations.has(key)


## Get harvester doing disassembly.
func get_harvester_at(position: Vector3i) -> int:
	var key := _get_position_key(position)
	var operation: DisassemblyOperation = _operations.get(key)
	return operation.harvester_id if operation != null else -1


## Get all active disassembly positions.
func get_active_positions() -> Array[Vector3i]:
	var positions: Array[Vector3i] = []
	for key in _operations:
		var operation: DisassemblyOperation = _operations[key]
		positions.append(operation.position)
	return positions


## Get position key.
func _get_position_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var ops_data: Dictionary = {}
	for key in _operations:
		var op: DisassemblyOperation = _operations[key]
		ops_data[key] = {
			"position": {"x": op.position.x, "y": op.position.y, "z": op.position.z},
			"harvester_id": op.harvester_id,
			"faction_id": op.faction_id,
			"target_stage": op.target_stage,
			"total_time": op.total_time,
			"elapsed_time": op.elapsed_time
		}

	return {"operations": ops_data}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_operations.clear()

	for key in data.get("operations", {}):
		var op_data: Dictionary = data["operations"][key]
		var pos_data: Dictionary = op_data.get("position", {})
		var position := Vector3i(
			pos_data.get("x", 0),
			pos_data.get("y", 0),
			pos_data.get("z", 0)
		)

		var operation := DisassemblyOperation.new(
			position,
			op_data.get("harvester_id", -1),
			op_data.get("faction_id", ""),
			op_data.get("target_stage", 0)
		)
		operation.total_time = op_data.get("total_time", 10.0)
		operation.elapsed_time = op_data.get("elapsed_time", 0.0)
		operation.progress = operation.elapsed_time / operation.total_time if operation.total_time > 0 else 1.0

		_operations[key] = operation


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"active_operations": _operations.size()
	}
