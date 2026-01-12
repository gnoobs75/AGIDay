class_name PowerGridNode
extends RefCounted
## PowerGridNode represents a node in the city power distribution network.

## Node types
enum NodeType {
	GENERATOR = 0,    ## Power station producing power
	SUBSTATION = 1,   ## Distribution node
	CONSUMER = 2,     ## Building consuming power
	JUNCTION = 3      ## Connection point
}

## Unique node ID
var id: int = 0

## Node type
var type: int = NodeType.CONSUMER

## Position in grid
var position: Vector2i = Vector2i.ZERO

## Power output (for generators)
var power_output: float = 0.0

## Power capacity (for substations)
var power_capacity: float = 0.0

## Current power throughput
var power_throughput: float = 0.0

## Power demand (for consumers)
var power_demand: float = 0.0

## Connected node IDs
var connections: Array[int] = []

## Maximum connections allowed
var max_connections: int = 4

## Whether node is active
var is_active: bool = true

## Building ID this node belongs to
var building_id: int = -1

## Zone ID this node is in
var zone_id: int = -1

## Custom metadata
var metadata: Dictionary = {}


func _init(p_type: int = NodeType.CONSUMER, p_position: Vector2i = Vector2i.ZERO) -> void:
	type = p_type
	position = p_position
	_initialize_from_type()


## Initialize from type.
func _initialize_from_type() -> void:
	match type:
		NodeType.GENERATOR:
			max_connections = 8
			power_capacity = 100.0
		NodeType.SUBSTATION:
			max_connections = 6
			power_capacity = 50.0
		NodeType.CONSUMER:
			max_connections = 2
		NodeType.JUNCTION:
			max_connections = 4
			power_capacity = 25.0


## Add connection to another node.
func add_connection(node_id: int) -> bool:
	if connections.size() >= max_connections:
		return false
	if node_id in connections:
		return false

	connections.append(node_id)
	return true


## Remove connection.
func remove_connection(node_id: int) -> bool:
	var idx := connections.find(node_id)
	if idx < 0:
		return false

	connections.remove_at(idx)
	return true


## Check if connected to node.
func is_connected_to(node_id: int) -> bool:
	return node_id in connections


## Get number of connections.
func get_connection_count() -> int:
	return connections.size()


## Check if can add more connections.
func can_connect() -> bool:
	return connections.size() < max_connections


## Calculate available power.
func get_available_power() -> float:
	match type:
		NodeType.GENERATOR:
			return power_output
		NodeType.SUBSTATION, NodeType.JUNCTION:
			return power_capacity - power_throughput
	return 0.0


## Check if is power source.
func is_source() -> bool:
	return type == NodeType.GENERATOR


## Check if is distribution node.
func is_distributor() -> bool:
	return type == NodeType.SUBSTATION or type == NodeType.JUNCTION


## Check if is consumer.
func is_consumer() -> bool:
	return type == NodeType.CONSUMER


## Set power output (for generators).
func set_output(output: float) -> void:
	if type == NodeType.GENERATOR:
		power_output = maxf(0.0, output)


## Set power demand (for consumers).
func set_demand(demand: float) -> void:
	if type == NodeType.CONSUMER:
		power_demand = maxf(0.0, demand)


## Update throughput.
func update_throughput(throughput: float) -> void:
	power_throughput = clampf(throughput, 0.0, power_capacity)


## Check if powered.
func is_powered() -> bool:
	if type == NodeType.GENERATOR:
		return is_active
	if type == NodeType.CONSUMER:
		return power_throughput >= power_demand
	return power_throughput > 0


## Get satisfaction ratio (0.0 to 1.0).
func get_satisfaction() -> float:
	if type != NodeType.CONSUMER or power_demand <= 0:
		return 1.0
	return clampf(power_throughput / power_demand, 0.0, 1.0)


## Get type name.
func get_type_name() -> String:
	match type:
		NodeType.GENERATOR: return "Generator"
		NodeType.SUBSTATION: return "Substation"
		NodeType.CONSUMER: return "Consumer"
		NodeType.JUNCTION: return "Junction"
	return "Unknown"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"position": {"x": position.x, "y": position.y},
		"power_output": power_output,
		"power_capacity": power_capacity,
		"power_throughput": power_throughput,
		"power_demand": power_demand,
		"connections": connections.duplicate(),
		"max_connections": max_connections,
		"is_active": is_active,
		"building_id": building_id,
		"zone_id": zone_id,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> PowerGridNode:
	var pos_data: Dictionary = data.get("position", {})
	var node := PowerGridNode.new(
		data.get("type", NodeType.CONSUMER),
		Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))
	)

	node.id = data.get("id", 0)
	node.power_output = data.get("power_output", 0.0)
	node.power_capacity = data.get("power_capacity", 0.0)
	node.power_throughput = data.get("power_throughput", 0.0)
	node.power_demand = data.get("power_demand", 0.0)

	node.connections.clear()
	for conn_id in data.get("connections", []):
		node.connections.append(int(conn_id))

	node.max_connections = data.get("max_connections", 4)
	node.is_active = data.get("is_active", true)
	node.building_id = data.get("building_id", -1)
	node.zone_id = data.get("zone_id", -1)
	node.metadata = data.get("metadata", {}).duplicate()

	return node


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"type": get_type_name(),
		"position": "%d,%d" % [position.x, position.y],
		"connections": connections.size(),
		"powered": is_powered(),
		"satisfaction": "%.0f%%" % (get_satisfaction() * 100)
	}
