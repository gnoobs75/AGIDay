class_name VoxelDamageSystem
extends RefCounted
## VoxelDamageSystem processes damage events for voxels.
## Uses async queue to avoid frame hitches during intense destruction.

signal voxel_damaged(position: Vector3i, damage: float, new_health: float)
signal voxel_stage_changed(position: Vector3i, old_stage: int, new_stage: int)
signal voxel_destroyed(position: Vector3i, faction_id: String)
signal resource_drop_requested(position: Vector3, amount: float, faction_id: String)
signal pathfinding_update_requested(position: Vector3i)
signal power_node_destroyed(position: Vector3i)

## Maximum damage events per frame
const MAX_EVENTS_PER_FRAME := 100

## Damage cooldown per voxel (seconds)
const DAMAGE_COOLDOWN := 0.1

## Damage queue
var _damage_queue: Array[Dictionary] = []

## Voxel health data (pos_key -> {health, max_health, stage, type, faction})
var _voxel_data: Dictionary = {}

## Damage cooldowns (pos_key -> remaining_cooldown)
var _cooldowns: Dictionary = {}

## Damage statistics by faction
var _faction_damage_stats: Dictionary = {}

## Mutex for thread safety
var _mutex: Mutex = null


func _init() -> void:
	_mutex = Mutex.new()


## Register voxel for damage tracking.
func register_voxel(
	position: Vector3i,
	max_health: float,
	voxel_type: String,
	faction_id: String
) -> void:
	var key := _get_position_key(position)

	_mutex.lock()
	_voxel_data[key] = {
		"position": position,
		"health": max_health,
		"max_health": max_health,
		"stage": VoxelStage.Stage.INTACT,
		"type": voxel_type,
		"faction": faction_id
	}
	_mutex.unlock()


## Attack voxel (queue damage).
func attack_voxel(
	position: Vector3i,
	damage: float,
	attacker_faction: String
) -> void:
	_queue_damage({
		"position": position,
		"damage": damage,
		"attacker": attacker_faction,
		"source": "attack"
	})


## Apply environmental damage.
func apply_environmental_damage(
	position: Vector3i,
	damage: float,
	damage_type: String
) -> void:
	_queue_damage({
		"position": position,
		"damage": damage,
		"attacker": "",
		"source": damage_type
	})


## Queue damage event.
func _queue_damage(event: Dictionary) -> void:
	_mutex.lock()
	_damage_queue.append(event)
	_mutex.unlock()


## Process damage queue (called every frame).
func process(delta: float) -> void:
	# Update cooldowns
	_update_cooldowns(delta)

	# Process queued damage
	_process_damage_queue()


## Update damage cooldowns.
func _update_cooldowns(delta: float) -> void:
	var to_remove: Array = []

	for key in _cooldowns:
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0:
			to_remove.append(key)

	for key in to_remove:
		_cooldowns.erase(key)


## Process damage queue.
func _process_damage_queue() -> void:
	_mutex.lock()
	var events_to_process := mini(_damage_queue.size(), MAX_EVENTS_PER_FRAME)
	var events: Array[Dictionary] = []

	for i in events_to_process:
		events.append(_damage_queue.pop_front())
	_mutex.unlock()

	for event in events:
		_apply_damage(event)


## Apply single damage event.
func _apply_damage(event: Dictionary) -> void:
	var position: Vector3i = event["position"]
	var damage: float = event["damage"]
	var attacker: String = event["attacker"]
	var source: String = event["source"]
	var key := _get_position_key(position)

	# Check cooldown
	if _cooldowns.has(key):
		return

	# Get voxel data
	var data: Dictionary = _voxel_data.get(key)
	if data == null:
		return

	var current_stage: int = data["stage"]

	# Check if can take damage
	if not VoxelStage.can_take_damage(current_stage):
		return

	# Apply damage multiplier
	var multiplier := VoxelStage.get_damage_multiplier(current_stage)
	var effective_damage := damage * multiplier

	# Apply damage
	var old_health: float = data["health"]
	var new_health := maxf(0.0, old_health - effective_damage)
	data["health"] = new_health

	# Set cooldown
	_cooldowns[key] = DAMAGE_COOLDOWN

	# Track statistics
	_track_damage_stats(attacker, effective_damage)

	voxel_damaged.emit(position, effective_damage, new_health)

	# Check stage transition
	var health_percent := new_health / data["max_health"]
	var new_stage := VoxelStage.get_stage_from_health(health_percent)

	if new_stage != current_stage:
		_handle_stage_transition(position, data, current_stage, new_stage, attacker)


## Handle voxel stage transition.
func _handle_stage_transition(
	position: Vector3i,
	data: Dictionary,
	old_stage: int,
	new_stage: int,
	attacker: String
) -> void:
	data["stage"] = new_stage

	voxel_stage_changed.emit(position, old_stage, new_stage)

	# Handle specific transitions
	if new_stage == VoxelStage.Stage.RUBBLE:
		# Generate resource drops
		var ree_amount := _calculate_ree_drop(data["type"])
		resource_drop_requested.emit(
			Vector3(position),
			ree_amount,
			data["faction"]
		)

	if new_stage == VoxelStage.Stage.CRATER:
		voxel_destroyed.emit(position, attacker)

		# Check if power node
		if data["type"] == "power_node" or data["type"] == "power_hub":
			power_node_destroyed.emit(position)

	# Request pathfinding update if traversability changed
	var was_traversable := VoxelStage.is_traversable(old_stage)
	var is_traversable := VoxelStage.is_traversable(new_stage)

	if was_traversable != is_traversable:
		pathfinding_update_requested.emit(position)


## Calculate REE drop for voxel type.
func _calculate_ree_drop(voxel_type: String) -> float:
	match voxel_type:
		"industrial": return 75.0
		"power_node", "power_hub": return 100.0
		"ree_node", "resource": return 150.0
		_: return 50.0


## Track damage statistics.
func _track_damage_stats(attacker: String, damage: float) -> void:
	if attacker.is_empty():
		return

	if not _faction_damage_stats.has(attacker):
		_faction_damage_stats[attacker] = {
			"damage_dealt": 0.0,
			"voxels_damaged": 0,
			"voxels_destroyed": 0
		}

	_faction_damage_stats[attacker]["damage_dealt"] += damage
	_faction_damage_stats[attacker]["voxels_damaged"] += 1


## Get voxel health.
func get_voxel_health(position: Vector3i) -> float:
	var key := _get_position_key(position)
	var data: Dictionary = _voxel_data.get(key, {})
	return data.get("health", 0.0)


## Get voxel stage.
func get_voxel_stage(position: Vector3i) -> int:
	var key := _get_position_key(position)
	var data: Dictionary = _voxel_data.get(key, {})
	return data.get("stage", VoxelStage.Stage.CRATER)


## Get faction damage statistics.
func get_faction_stats(faction_id: String) -> Dictionary:
	return _faction_damage_stats.get(faction_id, {
		"damage_dealt": 0.0,
		"voxels_damaged": 0,
		"voxels_destroyed": 0
	}).duplicate()


## Get position key.
func _get_position_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"voxel_data": _voxel_data.duplicate(true),
		"faction_damage_stats": _faction_damage_stats.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_voxel_data = data.get("voxel_data", {}).duplicate(true)
	_faction_damage_stats = data.get("faction_damage_stats", {}).duplicate(true)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"registered_voxels": _voxel_data.size(),
		"queued_damage": _damage_queue.size(),
		"active_cooldowns": _cooldowns.size(),
		"factions_tracked": _faction_damage_stats.size()
	}
