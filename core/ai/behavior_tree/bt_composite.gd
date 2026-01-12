class_name BTComposite
extends BTNode
## BTComposite is the base class for composite nodes that have children.
## Provides child management functionality.

## Child nodes
var children: Array[BTNode] = []

## Current child index during execution
var current_child_index: int = 0


func _init(p_name: String = "") -> void:
	super._init(p_name if not p_name.is_empty() else "BTComposite")


## Add a child node.
func add_child(child: BTNode) -> BTComposite:
	child.parent = self
	children.append(child)
	return self


## Add multiple children.
func add_children(new_children: Array[BTNode]) -> BTComposite:
	for child in new_children:
		add_child(child)
	return self


## Remove a child node.
func remove_child(child: BTNode) -> bool:
	var idx := children.find(child)
	if idx >= 0:
		children[idx].parent = null
		children.remove_at(idx)
		return true
	return false


## Get child count.
func get_child_count() -> int:
	return children.size()


## Get child at index.
func get_child(index: int) -> BTNode:
	if index >= 0 and index < children.size():
		return children[index]
	return null


## Initialize all children with seed.
func initialize(seed: int = 0) -> void:
	super.initialize(seed)
	for i in children.size():
		# Give each child a unique but deterministic seed
		children[i].initialize(seed + i + 1)


## Override reset to also reset children.
func _on_reset() -> void:
	current_child_index = 0
	for child in children:
		child.reset()


## Override interrupt to also interrupt children.
func _on_interrupt() -> void:
	for child in children:
		child.interrupt()


## Get debug info including children.
func get_debug_info() -> Dictionary:
	var info := super.get_debug_info()
	info["child_count"] = children.size()
	info["current_child_index"] = current_child_index

	var child_info: Array[Dictionary] = []
	for child in children:
		child_info.append(child.get_debug_info())
	info["children"] = child_info

	return info
