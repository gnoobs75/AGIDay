class_name AssemblySequenceState
extends RefCounted
## AssemblySequenceState tracks the current state of an assembly process for save/load.

signal state_changed(assembly_id: int)
signal part_changed(assembly_id: int, part_index: int)

## State identity
var assembly_id: int = -1
var unit_template: String = ""
var faction_id: String = ""

## Progress tracking
var elapsed_time: float = 0.0
var current_part_index: int = 0
var is_complete: bool = false
var is_paused: bool = false

## Part progress
var part_progress: float = 0.0  ## 0.0 to 1.0 within current part

## Factory reference
var factory_id: int = -1
var production_slot: int = -1

## Timing
var start_time: float = 0.0  ## Game time when assembly started
var pause_time: float = 0.0  ## Time spent paused


func _init() -> void:
	pass


## Initialize state for new assembly.
func initialize(p_assembly_id: int, p_unit_template: String, p_faction_id: String, game_time: float) -> void:
	assembly_id = p_assembly_id
	unit_template = p_unit_template
	faction_id = p_faction_id
	start_time = game_time
	elapsed_time = 0.0
	current_part_index = 0
	part_progress = 0.0
	is_complete = false
	is_paused = false
	pause_time = 0.0


## Update state from assembly sequence.
func update_from_sequence(sequence: AssemblySequence, delta: float) -> void:
	if is_complete or is_paused:
		return

	elapsed_time += delta

	# Get current part info
	var part_info := sequence.get_part_at_time(elapsed_time)
	if part_info.is_empty():
		return

	var new_part_index: int = part_info["index"]
	part_progress = part_info["progress"]

	# Check if we moved to a new part
	if new_part_index != current_part_index:
		current_part_index = new_part_index
		part_changed.emit(assembly_id, current_part_index)

	# Check completion
	if elapsed_time >= sequence.total_assembly_time:
		is_complete = true
		part_progress = 1.0
		current_part_index = sequence.get_part_count() - 1

	state_changed.emit(assembly_id)


## Pause assembly.
func pause() -> void:
	if not is_paused and not is_complete:
		is_paused = true
		state_changed.emit(assembly_id)


## Resume assembly.
func resume() -> void:
	if is_paused:
		is_paused = false
		state_changed.emit(assembly_id)


## Get overall progress (0.0 to 1.0).
func get_progress(sequence: AssemblySequence) -> float:
	if sequence.total_assembly_time <= 0:
		return 1.0 if is_complete else 0.0
	return minf(elapsed_time / sequence.total_assembly_time, 1.0)


## Get remaining time.
func get_remaining_time(sequence: AssemblySequence) -> float:
	return maxf(0.0, sequence.total_assembly_time - elapsed_time)


## Get time spent on current part.
func get_current_part_time(sequence: AssemblySequence) -> float:
	var accumulated := 0.0
	for i in current_part_index:
		var part := sequence.get_part(i)
		if part != null:
			accumulated += part.assembly_time

	return elapsed_time - accumulated


## Set factory reference.
func set_factory_reference(p_factory_id: int, p_slot: int) -> void:
	factory_id = p_factory_id
	production_slot = p_slot


## Serialization.
func to_dict() -> Dictionary:
	return {
		"assembly_id": assembly_id,
		"unit_template": unit_template,
		"faction_id": faction_id,
		"elapsed_time": elapsed_time,
		"current_part_index": current_part_index,
		"is_complete": is_complete,
		"is_paused": is_paused,
		"part_progress": part_progress,
		"factory_id": factory_id,
		"production_slot": production_slot,
		"start_time": start_time,
		"pause_time": pause_time
	}


func from_dict(data: Dictionary) -> void:
	assembly_id = data.get("assembly_id", -1)
	unit_template = data.get("unit_template", "")
	faction_id = data.get("faction_id", "")
	elapsed_time = data.get("elapsed_time", 0.0)
	current_part_index = data.get("current_part_index", 0)
	is_complete = data.get("is_complete", false)
	is_paused = data.get("is_paused", false)
	part_progress = data.get("part_progress", 0.0)
	factory_id = data.get("factory_id", -1)
	production_slot = data.get("production_slot", -1)
	start_time = data.get("start_time", 0.0)
	pause_time = data.get("pause_time", 0.0)


## Create from dictionary (static constructor).
static func create_from_dict(data: Dictionary) -> AssemblySequenceState:
	var state := AssemblySequenceState.new()
	state.from_dict(data)
	return state


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": assembly_id,
		"template": unit_template,
		"faction": faction_id,
		"elapsed": elapsed_time,
		"part_index": current_part_index,
		"part_progress": part_progress,
		"is_complete": is_complete,
		"is_paused": is_paused,
		"factory": factory_id,
		"slot": production_slot
	}
