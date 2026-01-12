class_name PowerNode
extends RefCounted
## PowerNode represents voxel-based power infrastructure.

signal node_destroyed(node_id: int)
signal node_repaired(node_id: int)
signal output_changed(node_id: int, new_output: float)
signal state_changed(node_id: int, new_state: int)

## Node types
enum NodeType {
	SOLAR_PANEL,
	FUSION_REACTOR,
	POWER_LINE,
	SUBSTATION
}

## Node states
enum NodeState {
	ACTIVE,
	INACTIVE,
	DAMAGED,
	DESTROYED
}

## Default outputs by type
const SOLAR_OUTPUT := 25.0
const FUSION_OUTPUT := 100.0
const POWER_LINE_CAPACITY := 50.0
const SUBSTATION_CAPACITY := 200.0

## Node identity
var node_id: int = -1
var faction_id: String = ""
var node_type: int = NodeType.SOLAR_PANEL
var node_state: int = NodeState.ACTIVE

## Voxel position
var voxel_position: Vector3i = Vector3i.ZERO

## Power properties
var base_output: float = 0.0
var current_output: float = 0.0
var efficiency: float = 1.0  ## Affected by damage or time of day

## Connection data
var connected_district_ids: Array[int] = []
var connected_node_ids: Array[int] = []

## Health for damage tracking
var max_health: float = 100.0
var current_health: float = 100.0

## Voxel stage (for multi-stage construction)
var voxel_stage: int = 1
var max_voxel_stage: int = 1


func _init() -> void:
	pass


## Initialize as solar panel.
func init_as_solar(p_id: int, p_faction: String, p_position: Vector3i) -> void:
	node_id = p_id
	faction_id = p_faction
	node_type = NodeType.SOLAR_PANEL
	voxel_position = p_position
	base_output = SOLAR_OUTPUT
	current_output = base_output
	max_health = 50.0
	current_health = max_health


## Initialize as fusion reactor.
func init_as_fusion(p_id: int, p_faction: String, p_position: Vector3i) -> void:
	node_id = p_id
	faction_id = p_faction
	node_type = NodeType.FUSION_REACTOR
	voxel_position = p_position
	base_output = FUSION_OUTPUT
	current_output = base_output
	max_health = 150.0
	current_health = max_health


## Initialize as power line.
func init_as_power_line(p_id: int, p_faction: String, p_position: Vector3i) -> void:
	node_id = p_id
	faction_id = p_faction
	node_type = NodeType.POWER_LINE
	voxel_position = p_position
	base_output = POWER_LINE_CAPACITY
	current_output = base_output
	max_health = 30.0
	current_health = max_health


## Initialize as substation.
func init_as_substation(p_id: int, p_faction: String, p_position: Vector3i) -> void:
	node_id = p_id
	faction_id = p_faction
	node_type = NodeType.SUBSTATION
	voxel_position = p_position
	base_output = SUBSTATION_CAPACITY
	current_output = base_output
	max_health = 100.0
	current_health = max_health


## Update output based on state and efficiency.
func update_output() -> void:
	var old_output := current_output

	if node_state == NodeState.DESTROYED:
		current_output = 0.0
	elif node_state == NodeState.INACTIVE:
		current_output = 0.0
	elif node_state == NodeState.DAMAGED:
		current_output = base_output * efficiency * 0.5  # 50% when damaged
	else:
		current_output = base_output * efficiency

	# Apply voxel stage modifier
	if max_voxel_stage > 1:
		current_output *= float(voxel_stage) / float(max_voxel_stage)

	if current_output != old_output:
		output_changed.emit(node_id, current_output)


## Set efficiency (for solar: daylight, for damaged: reduced).
func set_efficiency(new_efficiency: float) -> void:
	efficiency = clampf(new_efficiency, 0.0, 1.0)
	update_output()


## Set voxel stage.
func set_voxel_stage(stage: int, max_stage: int) -> void:
	voxel_stage = clampi(stage, 1, max_stage)
	max_voxel_stage = max_stage
	update_output()


## Apply damage.
func apply_damage(damage: float) -> void:
	if node_state == NodeState.DESTROYED:
		return

	var old_state := node_state
	current_health = maxf(0.0, current_health - damage)

	if current_health <= 0.0:
		_set_state(NodeState.DESTROYED)
	elif current_health < max_health * 0.5:
		_set_state(NodeState.DAMAGED)

	if node_state != old_state:
		update_output()


## Repair node.
func repair(amount: float) -> void:
	var old_state := node_state
	current_health = minf(max_health, current_health + amount)

	if current_health >= max_health:
		_set_state(NodeState.ACTIVE)
	elif current_health >= max_health * 0.5 and node_state == NodeState.DAMAGED:
		_set_state(NodeState.ACTIVE)

	if node_state != old_state:
		update_output()


## Fully repair.
func full_repair() -> void:
	var was_destroyed := node_state == NodeState.DESTROYED
	current_health = max_health
	_set_state(NodeState.ACTIVE)
	update_output()

	if was_destroyed:
		node_repaired.emit(node_id)


## Set state.
func _set_state(new_state: int) -> void:
	if node_state == new_state:
		return

	var old_state := node_state
	node_state = new_state
	state_changed.emit(node_id, new_state)

	if new_state == NodeState.DESTROYED and old_state != NodeState.DESTROYED:
		node_destroyed.emit(node_id)
	elif old_state == NodeState.DESTROYED and new_state != NodeState.DESTROYED:
		node_repaired.emit(node_id)


## Activate node.
func activate() -> void:
	if node_state == NodeState.INACTIVE:
		_set_state(NodeState.ACTIVE)
		update_output()


## Deactivate node.
func deactivate() -> void:
	if node_state == NodeState.ACTIVE:
		_set_state(NodeState.INACTIVE)
		update_output()


## Add connected district.
func add_connected_district(district_id: int) -> void:
	if not connected_district_ids.has(district_id):
		connected_district_ids.append(district_id)


## Remove connected district.
func remove_connected_district(district_id: int) -> void:
	var idx := connected_district_ids.find(district_id)
	if idx != -1:
		connected_district_ids.remove_at(idx)


## Add connected node.
func add_connected_node(other_node_id: int) -> void:
	if not connected_node_ids.has(other_node_id):
		connected_node_ids.append(other_node_id)


## Remove connected node.
func remove_connected_node(other_node_id: int) -> void:
	var idx := connected_node_ids.find(other_node_id)
	if idx != -1:
		connected_node_ids.remove_at(idx)


## Check if node is active and producing.
func is_producing() -> bool:
	return node_state == NodeState.ACTIVE and current_output > 0.0


## Check if node is generator (produces power).
func is_generator() -> bool:
	return node_type == NodeType.SOLAR_PANEL or node_type == NodeType.FUSION_REACTOR


## Check if node is transmission (moves power).
func is_transmission() -> bool:
	return node_type == NodeType.POWER_LINE or node_type == NodeType.SUBSTATION


## Get type name.
func get_type_name() -> String:
	match node_type:
		NodeType.SOLAR_PANEL:
			return "solar_panel"
		NodeType.FUSION_REACTOR:
			return "fusion_reactor"
		NodeType.POWER_LINE:
			return "power_line"
		NodeType.SUBSTATION:
			return "substation"
		_:
			return "unknown"


## Get state name.
func get_state_name() -> String:
	match node_state:
		NodeState.ACTIVE:
			return "active"
		NodeState.INACTIVE:
			return "inactive"
		NodeState.DAMAGED:
			return "damaged"
		NodeState.DESTROYED:
			return "destroyed"
		_:
			return "unknown"


## Serialization.
func to_dict() -> Dictionary:
	return {
		"node_id": node_id,
		"faction_id": faction_id,
		"node_type": node_type,
		"node_state": node_state,
		"voxel_position": {"x": voxel_position.x, "y": voxel_position.y, "z": voxel_position.z},
		"base_output": base_output,
		"current_output": current_output,
		"efficiency": efficiency,
		"connected_district_ids": connected_district_ids.duplicate(),
		"connected_node_ids": connected_node_ids.duplicate(),
		"max_health": max_health,
		"current_health": current_health,
		"voxel_stage": voxel_stage,
		"max_voxel_stage": max_voxel_stage
	}


func from_dict(data: Dictionary) -> void:
	node_id = data.get("node_id", -1)
	faction_id = data.get("faction_id", "")
	node_type = data.get("node_type", NodeType.SOLAR_PANEL)
	node_state = data.get("node_state", NodeState.ACTIVE)

	var pos: Dictionary = data.get("voxel_position", {})
	voxel_position = Vector3i(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	base_output = data.get("base_output", 0.0)
	current_output = data.get("current_output", 0.0)
	efficiency = data.get("efficiency", 1.0)
	max_health = data.get("max_health", 100.0)
	current_health = data.get("current_health", 100.0)
	voxel_stage = data.get("voxel_stage", 1)
	max_voxel_stage = data.get("max_voxel_stage", 1)

	connected_district_ids.clear()
	for did in data.get("connected_district_ids", []):
		connected_district_ids.append(int(did))

	connected_node_ids.clear()
	for nid in data.get("connected_node_ids", []):
		connected_node_ids.append(int(nid))


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": node_id,
		"faction": faction_id,
		"type": get_type_name(),
		"state": get_state_name(),
		"output": current_output,
		"efficiency": efficiency,
		"health_percent": current_health / max_health if max_health > 0 else 0.0,
		"connected_districts": connected_district_ids.size(),
		"connected_nodes": connected_node_ids.size()
	}
