class_name AssemblyProcessManager
extends RefCounted
## AssemblyProcessManager coordinates all active assembly processes.

signal assembly_started(process_id: int, unit_template: String)
signal assembly_completed(process_id: int, unit_template: String, assembled_parts: Array)
signal assembly_cancelled(process_id: int)
signal all_assemblies_complete()

## Maximum simultaneous assemblies for performance
const MAX_SIMULTANEOUS_ASSEMBLIES := 10

## Active assemblies (process_id -> AssemblyProcess)
var _active_assemblies: Dictionary = {}

## Completed assemblies awaiting collection (process_id -> AssemblyProcess)
var _completed_assemblies: Dictionary = {}

## Next process ID
var _next_process_id: int = 1

## Performance tracking
var _last_update_time_ms: float = 0.0
var _total_completed: int = 0

## Sequence cache
var _sequence_cache: Dictionary = {}


func _init() -> void:
	pass


## Start a new assembly process.
func start_assembly(unit_template: String, faction_id: String, factory_position: Vector3, factory_node: Node3D = null) -> int:
	# Check capacity
	if _active_assemblies.size() >= MAX_SIMULTANEOUS_ASSEMBLIES:
		push_warning("Maximum simultaneous assemblies reached")
		return -1

	# Get or create sequence
	var sequence := _get_or_create_sequence(unit_template, faction_id)
	if sequence == null:
		push_error("Failed to create assembly sequence for: %s" % unit_template)
		return -1

	# Create process
	var process := AssemblyProcess.new()
	process.initialize(_next_process_id, sequence, faction_id, factory_position, factory_node)

	# Connect signals
	process.assembly_completed.connect(_on_assembly_completed.bind(process.process_id))
	process.assembly_cancelled.connect(_on_assembly_cancelled.bind(process.process_id))

	_active_assemblies[_next_process_id] = process

	var process_id := _next_process_id
	_next_process_id += 1

	assembly_started.emit(process_id, unit_template)

	return process_id


## Get or create assembly sequence.
func _get_or_create_sequence(unit_template: String, faction_id: String) -> AssemblySequence:
	var cache_key := "%s_%s" % [unit_template, faction_id]

	if _sequence_cache.has(cache_key):
		return _sequence_cache[cache_key]

	var sequence := AssemblySequence.new()
	if not sequence.initialize(unit_template, faction_id):
		return null

	_sequence_cache[cache_key] = sequence
	return sequence


## Update all active assemblies (call each frame).
func update_assemblies(delta: float) -> void:
	var start_time := Time.get_ticks_usec()

	# Update each active assembly
	var completed_ids: Array[int] = []

	for process_id in _active_assemblies:
		var process: AssemblyProcess = _active_assemblies[process_id]

		process.update(delta)

		if process.is_complete:
			completed_ids.append(process_id)

	# Move completed to collection queue
	for process_id in completed_ids:
		var process: AssemblyProcess = _active_assemblies[process_id]
		_completed_assemblies[process_id] = process
		_active_assemblies.erase(process_id)

	_last_update_time_ms = float(Time.get_ticks_usec() - start_time) / 1000.0

	# Check if all assemblies are done
	if _active_assemblies.is_empty() and not _completed_assemblies.is_empty():
		all_assemblies_complete.emit()


## Cancel an assembly process.
func cancel_assembly(process_id: int) -> bool:
	if not _active_assemblies.has(process_id):
		return false

	var process: AssemblyProcess = _active_assemblies[process_id]
	process.cleanup()

	_active_assemblies.erase(process_id)

	return true


## Cleanup all assemblies.
func cleanup_all() -> void:
	for process_id in _active_assemblies:
		var process: AssemblyProcess = _active_assemblies[process_id]
		process.cleanup()

	_active_assemblies.clear()

	# Also cleanup completed
	for process_id in _completed_assemblies:
		var process: AssemblyProcess = _completed_assemblies[process_id]
		process.cleanup()

	_completed_assemblies.clear()


## Get active assembly by ID.
func get_assembly(process_id: int) -> AssemblyProcess:
	if _active_assemblies.has(process_id):
		return _active_assemblies[process_id]
	if _completed_assemblies.has(process_id):
		return _completed_assemblies[process_id]
	return null


## Get assembled parts for a completed assembly.
func get_assembled_parts(process_id: int) -> Array[Node3D]:
	if _completed_assemblies.has(process_id):
		return _completed_assemblies[process_id].assembled_parts

	return []


## Collect and remove a completed assembly.
func collect_completed(process_id: int) -> AssemblyProcess:
	if not _completed_assemblies.has(process_id):
		return null

	var process: AssemblyProcess = _completed_assemblies[process_id]
	_completed_assemblies.erase(process_id)
	_total_completed += 1

	return process


## Get all active assembly IDs.
func get_active_assembly_ids() -> Array[int]:
	var ids: Array[int] = []
	for process_id in _active_assemblies:
		ids.append(process_id)
	return ids


## Get all completed assembly IDs.
func get_completed_assembly_ids() -> Array[int]:
	var ids: Array[int] = []
	for process_id in _completed_assemblies:
		ids.append(process_id)
	return ids


## Get assembly progress.
func get_assembly_progress(process_id: int) -> float:
	var process := get_assembly(process_id)
	if process != null:
		return process.get_progress()
	return 0.0


## Check if can start new assembly.
func can_start_assembly() -> bool:
	return _active_assemblies.size() < MAX_SIMULTANEOUS_ASSEMBLIES


## Get active count.
func get_active_count() -> int:
	return _active_assemblies.size()


## Get completed count.
func get_completed_count() -> int:
	return _completed_assemblies.size()


## Signal handlers.
func _on_assembly_completed(process_id: int) -> void:
	if _active_assemblies.has(process_id):
		var process: AssemblyProcess = _active_assemblies[process_id]
		assembly_completed.emit(process_id, process.unit_template, process.assembled_parts)


func _on_assembly_cancelled(process_id: int) -> void:
	assembly_cancelled.emit(process_id)


## Clear sequence cache.
func clear_cache() -> void:
	_sequence_cache.clear()
	AssemblySequence.clear_cache()


## Serialization.
func to_dict() -> Dictionary:
	var active_data: Dictionary = {}
	for process_id in _active_assemblies:
		active_data[str(process_id)] = _active_assemblies[process_id].to_dict()

	var completed_data: Dictionary = {}
	for process_id in _completed_assemblies:
		completed_data[str(process_id)] = _completed_assemblies[process_id].to_dict()

	return {
		"active_assemblies": active_data,
		"completed_assemblies": completed_data,
		"next_process_id": _next_process_id,
		"total_completed": _total_completed
	}


func from_dict(data: Dictionary) -> void:
	_active_assemblies.clear()
	_completed_assemblies.clear()

	_next_process_id = data.get("next_process_id", 1)
	_total_completed = data.get("total_completed", 0)

	# Note: Full restoration would require access to factory nodes
	# This just restores the state data
	var active_data: Dictionary = data.get("active_assemblies", {})
	for process_id_str in active_data:
		var process := AssemblyProcess.new()
		process.from_dict(active_data[process_id_str])

		# Recreate sequence
		var sequence := _get_or_create_sequence(process.unit_template, process.faction_id)
		if sequence != null:
			process.sequence = sequence

		_active_assemblies[int(process_id_str)] = process

	var completed_data: Dictionary = data.get("completed_assemblies", {})
	for process_id_str in completed_data:
		var process := AssemblyProcess.new()
		process.from_dict(completed_data[process_id_str])
		_completed_assemblies[int(process_id_str)] = process


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_progress := 0.0
	for process_id in _active_assemblies:
		total_progress += _active_assemblies[process_id].get_progress()

	var avg_progress := total_progress / _active_assemblies.size() if not _active_assemblies.is_empty() else 0.0

	return {
		"active_count": _active_assemblies.size(),
		"completed_pending": _completed_assemblies.size(),
		"total_completed": _total_completed,
		"average_progress": avg_progress,
		"last_update_ms": _last_update_time_ms,
		"cache_size": _sequence_cache.size(),
		"can_start_new": can_start_assembly()
	}
