class_name PowerNodeManager
extends RefCounted
## PowerNodeManager handles voxel-based power infrastructure.

signal node_registered(node_id: int, node_type: int)
signal node_unregistered(node_id: int)
signal node_destroyed(node_id: int)
signal node_repaired(node_id: int)
signal voxel_power_changed(position: Vector3i, power: float)

## All power nodes (node_id -> PowerNode)
var _nodes: Dictionary = {}

## Nodes by voxel position (Vector3i string -> node_id)
var _position_map: Dictionary = {}

## Nodes by faction (faction_id -> Array[int])
var _faction_nodes: Dictionary = {}

## Nodes by type (node_type -> Array[int])
var _type_nodes: Dictionary = {}

## Next node ID
var _next_node_id: int = 1


func _init() -> void:
	for node_type in PowerNode.NodeType.values():
		_type_nodes[node_type] = []


## Get position key.
func _pos_key(pos: Vector3i) -> String:
	return "%d,%d,%d" % [pos.x, pos.y, pos.z]


## Register solar panel.
func register_solar(faction_id: String, position: Vector3i) -> PowerNode:
	var node := PowerNode.new()
	node.init_as_solar(_next_node_id, faction_id, position)
	return _register_node(node)


## Register fusion reactor.
func register_fusion(faction_id: String, position: Vector3i) -> PowerNode:
	var node := PowerNode.new()
	node.init_as_fusion(_next_node_id, faction_id, position)
	return _register_node(node)


## Register power line.
func register_power_line(faction_id: String, position: Vector3i) -> PowerNode:
	var node := PowerNode.new()
	node.init_as_power_line(_next_node_id, faction_id, position)
	return _register_node(node)


## Register substation.
func register_substation(faction_id: String, position: Vector3i) -> PowerNode:
	var node := PowerNode.new()
	node.init_as_substation(_next_node_id, faction_id, position)
	return _register_node(node)


## Internal registration.
func _register_node(node: PowerNode) -> PowerNode:
	_nodes[_next_node_id] = node
	_next_node_id += 1

	# Map by position
	var key := _pos_key(node.voxel_position)
	_position_map[key] = node.node_id

	# Add to faction list
	if not _faction_nodes.has(node.faction_id):
		_faction_nodes[node.faction_id] = []
	_faction_nodes[node.faction_id].append(node.node_id)

	# Add to type list
	_type_nodes[node.node_type].append(node.node_id)

	# Connect signals
	node.node_destroyed.connect(_on_node_destroyed)
	node.node_repaired.connect(_on_node_repaired)
	node.output_changed.connect(_on_output_changed)

	node_registered.emit(node.node_id, node.node_type)

	return node


## Unregister node.
func unregister_node(node_id: int) -> void:
	if not _nodes.has(node_id):
		return

	var node: PowerNode = _nodes[node_id]

	# Remove from position map
	var key := _pos_key(node.voxel_position)
	_position_map.erase(key)

	# Remove from faction list
	if _faction_nodes.has(node.faction_id):
		var idx: int = _faction_nodes[node.faction_id].find(node_id)
		if idx != -1:
			_faction_nodes[node.faction_id].remove_at(idx)

	# Remove from type list
	var type_idx: int = _type_nodes[node.node_type].find(node_id)
	if type_idx != -1:
		_type_nodes[node.node_type].remove_at(type_idx)

	_nodes.erase(node_id)
	node_unregistered.emit(node_id)


## Get node by ID.
func get_node(node_id: int) -> PowerNode:
	return _nodes.get(node_id)


## Get node at position.
func get_node_at_position(position: Vector3i) -> PowerNode:
	var key := _pos_key(position)
	if _position_map.has(key):
		return _nodes.get(_position_map[key])
	return null


## Check if position has power node.
func has_power_node(position: Vector3i) -> bool:
	return _position_map.has(_pos_key(position))


## Get all nodes for faction.
func get_faction_nodes(faction_id: String) -> Array[PowerNode]:
	var nodes: Array[PowerNode] = []
	if not _faction_nodes.has(faction_id):
		return nodes

	for node_id in _faction_nodes[faction_id]:
		var node: PowerNode = _nodes.get(node_id)
		if node != null:
			nodes.append(node)

	return nodes


## Get nodes by type.
func get_nodes_by_type(node_type: int) -> Array[PowerNode]:
	var nodes: Array[PowerNode] = []

	for node_id in _type_nodes[node_type]:
		var node: PowerNode = _nodes.get(node_id)
		if node != null:
			nodes.append(node)

	return nodes


## Get total output for faction.
func get_faction_output(faction_id: String) -> float:
	var total := 0.0
	for node in get_faction_nodes(faction_id):
		if node.is_producing():
			total += node.current_output
	return total


## Get generator count for faction.
func get_faction_generator_count(faction_id: String) -> Dictionary:
	var counts := {
		"solar": 0,
		"fusion": 0,
		"total": 0,
		"active": 0
	}

	for node in get_faction_nodes(faction_id):
		if node.is_generator():
			counts["total"] += 1
			if node.is_producing():
				counts["active"] += 1

			if node.node_type == PowerNode.NodeType.SOLAR_PANEL:
				counts["solar"] += 1
			elif node.node_type == PowerNode.NodeType.FUSION_REACTOR:
				counts["fusion"] += 1

	return counts


## Handle voxel destruction event.
func on_voxel_destroyed(position: Vector3i) -> void:
	var node := get_node_at_position(position)
	if node != null:
		node.apply_damage(node.max_health)  # Destroy the node


## Handle voxel damage event.
func on_voxel_damaged(position: Vector3i, damage_percent: float) -> void:
	var node := get_node_at_position(position)
	if node != null:
		node.apply_damage(node.max_health * damage_percent)


## Handle voxel stage change.
func on_voxel_stage_changed(position: Vector3i, stage: int, max_stage: int) -> void:
	var node := get_node_at_position(position)
	if node != null:
		node.set_voxel_stage(stage, max_stage)


## Update daylight for solar panels.
func update_daylight(multiplier: float) -> void:
	for node in get_nodes_by_type(PowerNode.NodeType.SOLAR_PANEL):
		node.set_efficiency(multiplier)


## Signal handlers.
func _on_node_destroyed(node_id: int) -> void:
	node_destroyed.emit(node_id)


func _on_node_repaired(node_id: int) -> void:
	node_repaired.emit(node_id)


func _on_output_changed(node_id: int, new_output: float) -> void:
	var node := get_node(node_id)
	if node != null:
		voxel_power_changed.emit(node.voxel_position, new_output)


## Serialization.
func to_dict() -> Dictionary:
	var nodes_data: Dictionary = {}
	for node_id in _nodes:
		nodes_data[str(node_id)] = _nodes[node_id].to_dict()

	return {
		"nodes": nodes_data,
		"next_node_id": _next_node_id
	}


func from_dict(data: Dictionary) -> void:
	_nodes.clear()
	_position_map.clear()
	_faction_nodes.clear()

	for node_type in PowerNode.NodeType.values():
		_type_nodes[node_type] = []

	_next_node_id = data.get("next_node_id", 1)

	var nodes_data: Dictionary = data.get("nodes", {})
	for node_id_str in nodes_data:
		var node := PowerNode.new()
		node.from_dict(nodes_data[node_id_str])

		_nodes[int(node_id_str)] = node

		# Rebuild indexes
		var key := _pos_key(node.voxel_position)
		_position_map[key] = node.node_id

		if not _faction_nodes.has(node.faction_id):
			_faction_nodes[node.faction_id] = []
		_faction_nodes[node.faction_id].append(node.node_id)

		_type_nodes[node.node_type].append(node.node_id)

		# Connect signals
		node.node_destroyed.connect(_on_node_destroyed)
		node.node_repaired.connect(_on_node_repaired)
		node.output_changed.connect(_on_output_changed)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_counts: Dictionary = {}
	for node_type in PowerNode.NodeType.values():
		var type_name: String
		match node_type:
			PowerNode.NodeType.SOLAR_PANEL:
				type_name = "solar"
			PowerNode.NodeType.FUSION_REACTOR:
				type_name = "fusion"
			PowerNode.NodeType.POWER_LINE:
				type_name = "power_line"
			PowerNode.NodeType.SUBSTATION:
				type_name = "substation"
		type_counts[type_name] = _type_nodes[node_type].size()

	var active_count := 0
	var total_output := 0.0
	for node_id in _nodes:
		var node: PowerNode = _nodes[node_id]
		if node.is_producing():
			active_count += 1
			total_output += node.current_output

	return {
		"total_nodes": _nodes.size(),
		"active_nodes": active_count,
		"by_type": type_counts,
		"total_output": total_output,
		"factions": _faction_nodes.size()
	}
