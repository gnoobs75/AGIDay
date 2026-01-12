class_name BTNode
extends RefCounted
## BTNode is the base class for all behavior tree nodes.
## Provides common functionality for execution, interruption, and debugging.

signal node_executed(node_name: String, status: int)
signal node_interrupted(node_name: String)

## Node name for debugging
var node_name: String = ""

## Parent node reference
var parent: BTNode = null

## Current execution status
var current_status: int = BTStatus.Status.FAILURE

## Whether this node is currently executing (RUNNING)
var is_running: bool = false

## Execution count for debugging
var execution_count: int = 0

## Seed for deterministic RNG
var rng_seed: int = 0
var _rng: RandomNumberGenerator = null


func _init(p_name: String = "") -> void:
	node_name = p_name if not p_name.is_empty() else "BTNode"
	_rng = RandomNumberGenerator.new()


## Initialize the node with a seed.
func initialize(seed: int = 0) -> void:
	rng_seed = seed
	_rng.seed = seed
	_on_initialize()


## Override in subclasses for custom initialization.
func _on_initialize() -> void:
	pass


## Execute this node.
## Returns BTStatus.Status value.
func execute(context: Dictionary) -> int:
	execution_count += 1
	current_status = _execute(context)
	is_running = (current_status == BTStatus.Status.RUNNING)
	node_executed.emit(node_name, current_status)
	return current_status


## Override in subclasses for custom execution logic.
func _execute(_context: Dictionary) -> int:
	return BTStatus.Status.FAILURE


## Interrupt this node if it's running.
func interrupt() -> void:
	if is_running:
		_on_interrupt()
		is_running = false
		current_status = BTStatus.Status.FAILURE
		node_interrupted.emit(node_name)


## Override in subclasses for custom interrupt handling.
func _on_interrupt() -> void:
	pass


## Reset this node to initial state.
func reset() -> void:
	is_running = false
	current_status = BTStatus.Status.FAILURE
	_on_reset()


## Override in subclasses for custom reset logic.
func _on_reset() -> void:
	pass


## Get a random float using the seeded RNG.
func rand_float() -> float:
	return _rng.randf()


## Get a random int in range using the seeded RNG.
func rand_int(min_val: int, max_val: int) -> int:
	return _rng.randi_range(min_val, max_val)


## Get status name for debugging.
func get_status_name() -> String:
	return BTStatus.to_string_status(current_status)


## Get debug info.
func get_debug_info() -> Dictionary:
	return {
		"name": node_name,
		"status": get_status_name(),
		"is_running": is_running,
		"execution_count": execution_count
	}
