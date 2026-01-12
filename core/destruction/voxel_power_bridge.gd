class_name VoxelPowerBridge
extends RefCounted
## VoxelPowerBridge connects voxel destruction to power grid simulation.
## Tracks power node status and triggers cascade failures when nodes destroyed.

signal power_node_destroyed(position: Vector3i, node_type: String)
signal power_node_repaired(position: Vector3i, node_type: String)
signal cascade_failure_triggered(affected_positions: Array[Vector3i])
signal grid_disconnection(district_id: String)

## Power node types
const NODE_TYPE_SOLAR := "solar_panel"
const NODE_TYPE_FUSION := "fusion_reactor"
const NODE_TYPE_SUBSTATION := "substation"
const NODE_TYPE_HUB := "power_hub"
const NODE_TYPE_CONDUIT := "power_conduit"

## Reference to voxel system
var _voxel_system: VoxelSystem = null

## Power node registry
var _power_nodes: Dictionary = {}  ## "x,z" -> PowerNodeData

## Active nodes (not destroyed)
var _active_nodes: Dictionary = {}  ## "x,z" -> true

## Node connections (adjacency)
var _connections: Dictionary = {}  ## "x,z" -> Array[String] (connected node keys)

## District assignments
var _node_districts: Dictionary = {}  ## "x,z" -> district_id


## Power node data.
class PowerNodeData:
	var position: Vector3i = Vector3i.ZERO
	var node_type: String = ""
	var power_output: float = 0.0
	var is_active: bool = true
	var district_id: String = ""


func _init() -> void:
	pass


## Connect to voxel system.
func connect_to_voxel_system(voxel_system: VoxelSystem) -> void:
	_voxel_system = voxel_system
	voxel_system.set_power_grid_callback(_on_power_node_change)


## Register a power node.
func register_power_node(
	position: Vector3i,
	node_type: String,
	power_output: float,
	district_id: String = ""
) -> void:
	var key := _pos_to_key(position)

	var node := PowerNodeData.new()
	node.position = position
	node.node_type = node_type
	node.power_output = power_output
	node.is_active = true
	node.district_id = district_id

	_power_nodes[key] = node
	_active_nodes[key] = true

	if not district_id.is_empty():
		_node_districts[key] = district_id

	# Register with voxel system
	if _voxel_system != null:
		_voxel_system.register_power_node(position)


## Connect two power nodes.
func connect_nodes(pos1: Vector3i, pos2: Vector3i) -> void:
	var key1 := _pos_to_key(pos1)
	var key2 := _pos_to_key(pos2)

	if not _connections.has(key1):
		_connections[key1] = []
	if not _connections.has(key2):
		_connections[key2] = []

	if not _connections[key1].has(key2):
		_connections[key1].append(key2)
	if not _connections[key2].has(key1):
		_connections[key2].append(key1)


## Handle power node state change from voxel system.
func _on_power_node_change(position: Vector3i, destroyed: bool) -> void:
	var key := _pos_to_key(position)

	if not _power_nodes.has(key):
		return

	var node: PowerNodeData = _power_nodes[key]

	if destroyed and node.is_active:
		_handle_node_destroyed(key, node)
	elif not destroyed and not node.is_active:
		_handle_node_repaired(key, node)


## Handle node destruction.
func _handle_node_destroyed(key: String, node: PowerNodeData) -> void:
	node.is_active = false
	_active_nodes.erase(key)

	power_node_destroyed.emit(node.position, node.node_type)

	# Check for cascade failure
	if _should_trigger_cascade(key, node):
		_trigger_cascade_failure(key)

	# Check for district disconnection
	if not node.district_id.is_empty():
		if _is_district_disconnected(node.district_id):
			grid_disconnection.emit(node.district_id)


## Handle node repair.
func _handle_node_repaired(key: String, node: PowerNodeData) -> void:
	node.is_active = true
	_active_nodes[key] = true

	power_node_repaired.emit(node.position, node.node_type)


## Check if cascade failure should trigger.
func _should_trigger_cascade(key: String, node: PowerNodeData) -> bool:
	# Hubs and substations can trigger cascades
	return node.node_type == NODE_TYPE_HUB or node.node_type == NODE_TYPE_SUBSTATION


## Trigger cascade failure from destroyed node.
func _trigger_cascade_failure(origin_key: String) -> void:
	var affected: Array[Vector3i] = []

	# Find all nodes that depended on this one
	var to_check: Array = [origin_key]
	var checked: Dictionary = {origin_key: true}

	while not to_check.is_empty():
		var current_key: String = to_check.pop_front()

		if not _connections.has(current_key):
			continue

		for connected_key in _connections[current_key]:
			if checked.has(connected_key):
				continue
			checked[connected_key] = true

			# Check if this node loses power
			if _loses_power_without(connected_key, origin_key):
				if _power_nodes.has(connected_key):
					var node: PowerNodeData = _power_nodes[connected_key]
					if node.is_active:
						node.is_active = false
						_active_nodes.erase(connected_key)
						affected.append(node.position)

				to_check.append(connected_key)

	if not affected.is_empty():
		cascade_failure_triggered.emit(affected)


## Check if node loses power without the origin.
func _loses_power_without(node_key: String, removed_key: String) -> bool:
	# Simple check: if only connected to removed node
	if not _connections.has(node_key):
		return true

	var connections: Array = _connections[node_key]

	# Check if any remaining active connection exists
	for key in connections:
		if key == removed_key:
			continue
		if _active_nodes.has(key):
			return false

	return true


## Check if district is disconnected from power.
func _is_district_disconnected(district_id: String) -> bool:
	# Find all nodes in district
	var district_nodes: Array = []
	for key in _node_districts:
		if _node_districts[key] == district_id:
			district_nodes.append(key)

	# Check if any power source is still connected
	for key in district_nodes:
		if _active_nodes.has(key):
			var node: PowerNodeData = _power_nodes[key]
			if node.node_type == NODE_TYPE_SOLAR or node.node_type == NODE_TYPE_FUSION:
				return false

	return true


## Get total power output for district.
func get_district_power(district_id: String) -> float:
	var total := 0.0

	for key in _node_districts:
		if _node_districts[key] != district_id:
			continue
		if not _active_nodes.has(key):
			continue
		if not _power_nodes.has(key):
			continue

		var node: PowerNodeData = _power_nodes[key]
		total += node.power_output

	return total


## Get active power nodes in district.
func get_district_active_nodes(district_id: String) -> Array[Vector3i]:
	var result: Array[Vector3i] = []

	for key in _node_districts:
		if _node_districts[key] != district_id:
			continue
		if not _active_nodes.has(key):
			continue
		if _power_nodes.has(key):
			result.append(_power_nodes[key].position)

	return result


## Get all destroyed power nodes.
func get_destroyed_nodes() -> Array[Vector3i]:
	var result: Array[Vector3i] = []

	for key in _power_nodes:
		if not _active_nodes.has(key):
			result.append(_power_nodes[key].position)

	return result


## Convert position to key.
func _pos_to_key(position: Vector3i) -> String:
	return "%d,%d" % [position.x, position.z]


## Convert key to position.
func _key_to_pos(key: String) -> Vector3i:
	var parts := key.split(",")
	if parts.size() == 2:
		return Vector3i(int(parts[0]), 0, int(parts[1]))
	return Vector3i.ZERO


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"total_nodes": _power_nodes.size(),
		"active_nodes": _active_nodes.size(),
		"destroyed_nodes": _power_nodes.size() - _active_nodes.size(),
		"connections": _connections.size(),
		"districts": _node_districts.values().reduce(func(acc, d): return acc if acc.has(d) else acc + [d], []).size() if not _node_districts.is_empty() else 0
	}
