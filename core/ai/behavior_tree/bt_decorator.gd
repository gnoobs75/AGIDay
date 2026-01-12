class_name BTDecorator
extends BTNode
## BTDecorator wraps a single child and modifies its behavior.
## Base class for decorator nodes like Inverter, Repeater, etc.

## The child node
var child: BTNode = null


func _init(p_name: String = "", p_child: BTNode = null) -> void:
	super._init(p_name if not p_name.is_empty() else "Decorator")
	if p_child != null:
		set_child(p_child)


## Set the child node.
func set_child(p_child: BTNode) -> BTDecorator:
	if child != null:
		child.parent = null
	child = p_child
	if child != null:
		child.parent = self
	return self


## Get the child node.
func get_child() -> BTNode:
	return child


## Initialize child with seed.
func initialize(seed: int = 0) -> void:
	super.initialize(seed)
	if child != null:
		child.initialize(seed + 1)


## Override reset to also reset child.
func _on_reset() -> void:
	if child != null:
		child.reset()


## Override interrupt to also interrupt child.
func _on_interrupt() -> void:
	if child != null:
		child.interrupt()


## Default execution passes through to child.
func _execute(context: Dictionary) -> int:
	if child == null:
		return BTStatus.Status.FAILURE
	return child.execute(context)


## Get debug info including child.
func get_debug_info() -> Dictionary:
	var info := super.get_debug_info()
	if child != null:
		info["child"] = child.get_debug_info()
	return info
