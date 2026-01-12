class_name CommandQueue
extends RefCounted
## CommandQueue processes commands in FIFO order for deterministic execution.

signal command_queued(command: Command)
signal command_executed(command: Command)
signal command_failed(command: Command, reason: String)
signal queue_processed(command_count: int)

## Command queue (FIFO)
var _queue: Array[Command] = []

## Command validator
var _validator: CommandValidator = null

## Command ID counter
var _next_command_id: int = 0

## Current frame number
var _current_frame: int = 0

## Command execution callback (command) -> bool
var _execution_callback: Callable

## Commands executed this frame
var _commands_this_frame: int = 0

## Maximum commands per frame (0 = unlimited)
var max_commands_per_frame: int = 0

## Statistics
var _stats: Dictionary = {
	"total_queued": 0,
	"total_executed": 0,
	"total_failed": 0
}


func _init() -> void:
	_validator = CommandValidator.new()


## Get validator.
func get_validator() -> CommandValidator:
	return _validator


## Set execution callback.
func set_execution_callback(callback: Callable) -> void:
	_execution_callback = callback


## Queue command.
func queue_command(command: Command) -> int:
	command.command_id = _next_command_id
	_next_command_id += 1
	command.frame_number = _current_frame

	_queue.append(command)
	_stats["total_queued"] += 1

	command_queued.emit(command)

	return command.command_id


## Queue ability command.
func queue_ability(
	ability_id: String,
	faction_id: String,
	target_pos: Vector3 = Vector3.INF,
	target_unit: int = -1
) -> int:
	var command := Command.create_ability(
		_next_command_id,
		ability_id,
		faction_id,
		_current_frame,
		target_pos,
		target_unit
	)
	return queue_command(command)


## Queue formation command.
func queue_formation(
	formation_type: String,
	faction_id: String,
	target_pos: Vector3,
	units: Array[int]
) -> int:
	var command := Command.create_formation(
		_next_command_id,
		formation_type,
		faction_id,
		_current_frame,
		target_pos,
		units
	)
	return queue_command(command)


## Queue movement command.
func queue_movement(
	faction_id: String,
	target_pos: Vector3,
	units: Array[int]
) -> int:
	var command := Command.create_movement(
		_next_command_id,
		faction_id,
		_current_frame,
		target_pos,
		units
	)
	return queue_command(command)


## Queue attack command.
func queue_attack(
	faction_id: String,
	target_unit: int,
	units: Array[int]
) -> int:
	var command := Command.create_attack(
		_next_command_id,
		faction_id,
		_current_frame,
		target_unit,
		units
	)
	return queue_command(command)


## Process queue for frame.
func process(frame: int) -> void:
	_current_frame = frame
	_commands_this_frame = 0

	var processed := 0

	while not _queue.is_empty():
		# Check per-frame limit
		if max_commands_per_frame > 0 and _commands_this_frame >= max_commands_per_frame:
			break

		var command: Command = _queue.pop_front()

		# Validate command
		var validation := _validator.validate(command)

		if validation["valid"]:
			# Execute command
			var success := _execute_command(command)

			if success:
				_stats["total_executed"] += 1
				command_executed.emit(command)
			else:
				_stats["total_failed"] += 1
				command_failed.emit(command, "Execution failed")
		else:
			_stats["total_failed"] += 1
			command_failed.emit(command, validation["reason"])

		_commands_this_frame += 1
		processed += 1

	queue_processed.emit(processed)


## Execute command via callback.
func _execute_command(command: Command) -> bool:
	if _execution_callback.is_valid():
		return _execution_callback.call(command)
	return true  # Default success if no callback


## Get queue size.
func get_queue_size() -> int:
	return _queue.size()


## Check if queue is empty.
func is_empty() -> bool:
	return _queue.is_empty()


## Clear queue.
func clear() -> void:
	_queue.clear()


## Peek at next command.
func peek() -> Command:
	return _queue[0] if not _queue.is_empty() else null


## Get statistics.
func get_stats() -> Dictionary:
	return _stats.duplicate()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var queue_data: Array = []
	for command in _queue:
		queue_data.append(command.to_dict())

	return {
		"next_command_id": _next_command_id,
		"current_frame": _current_frame,
		"queue": queue_data,
		"stats": _stats.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_next_command_id = data.get("next_command_id", 0)
	_current_frame = data.get("current_frame", 0)

	_queue.clear()
	for cmd_data in data.get("queue", []):
		_queue.append(Command.from_dict(cmd_data))

	_stats = data.get("stats", _stats).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"queue_size": _queue.size(),
		"next_id": _next_command_id,
		"current_frame": _current_frame,
		"commands_this_frame": _commands_this_frame,
		"stats": _stats
	}
