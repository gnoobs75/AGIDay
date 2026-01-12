class_name SpawnSyncManager
extends RefCounted
## SpawnSyncManager handles synchronized spawning across all clients.
## Ensures all clients see units spawn at the same locations and times.

signal spawn_confirmed(spawn_id: int, entity_id: int)
signal spawn_failed(spawn_id: int, reason: String)
signal spawn_batch_completed(batch_id: int, count: int)

## Configuration
const SPAWN_BUFFER_TIME := 0.1       ## Seconds to buffer spawns for batching
const MAX_SPAWNS_PER_BATCH := 50
const SPAWN_CONFIRMATION_TIMEOUT := 5.0  ## Seconds

## Spawn data
var _pending_spawns: Array[SpawnRequest] = []
var _spawn_counter := 0
var _batch_counter := 0

## Confirmation tracking (server)
var _awaiting_confirmation: Dictionary = {}  ## spawn_id -> SpawnRequest

## Received spawns (client)
var _spawn_queue: Array[SpawnRequest] = []

## Authority
var _is_server := false
var _network_manager: NetworkManager = null
var _deterministic_rng: DeterministicRNG = null

## Timing
var _buffer_timer := 0.0
var _last_batch_time := 0.0


func _init() -> void:
	pass


## Initialize with network manager.
func initialize(network_manager: NetworkManager, deterministic_rng: DeterministicRNG = null) -> void:
	_network_manager = network_manager
	_deterministic_rng = deterministic_rng
	_is_server = network_manager.is_server()


## Set server authority.
func set_authority(is_server: bool) -> void:
	_is_server = is_server


## Request a spawn (server only).
func request_spawn(spawn_type: String, position: Vector3, rotation: float,
				   faction_id: String, extra_data: Dictionary = {}) -> int:
	if not _is_server:
		push_warning("SpawnSyncManager: Only server can request spawns")
		return -1

	var spawn_id := _spawn_counter
	_spawn_counter += 1

	var request := SpawnRequest.new()
	request.spawn_id = spawn_id
	request.spawn_type = spawn_type
	request.position = position
	request.rotation = rotation
	request.faction_id = faction_id
	request.extra_data = extra_data
	request.timestamp = Time.get_ticks_msec()
	request.rng_seed = _deterministic_rng.randi() if _deterministic_rng != null else randi()

	_pending_spawns.append(request)
	return spawn_id


## Request batch spawn (server only).
func request_batch_spawn(spawns: Array[Dictionary]) -> int:
	if not _is_server:
		return -1

	var batch_id := _batch_counter
	_batch_counter += 1

	for spawn_data in spawns:
		var spawn_id := _spawn_counter
		_spawn_counter += 1

		var request := SpawnRequest.new()
		request.spawn_id = spawn_id
		request.batch_id = batch_id
		request.spawn_type = spawn_data.get("type", "unit")
		request.position = spawn_data.get("position", Vector3.ZERO)
		request.rotation = spawn_data.get("rotation", 0.0)
		request.faction_id = spawn_data.get("faction_id", "")
		request.extra_data = spawn_data.get("extra_data", {})
		request.timestamp = Time.get_ticks_msec()
		request.rng_seed = _deterministic_rng.randi() if _deterministic_rng != null else randi()

		_pending_spawns.append(request)

	return batch_id


## Update (call each frame).
func update(delta: float) -> void:
	if _is_server:
		_buffer_timer += delta

		# Send batched spawns
		if _buffer_timer >= SPAWN_BUFFER_TIME and not _pending_spawns.is_empty():
			_send_spawn_batch()
			_buffer_timer = 0.0

		# Check for confirmation timeouts
		_check_confirmation_timeouts()
	else:
		# Client: process spawn queue
		_process_spawn_queue()


## Send spawn batch to all clients.
func _send_spawn_batch() -> void:
	if _network_manager == null or _pending_spawns.is_empty():
		return

	var batch: Array[Dictionary] = []
	var spawns_to_send := mini(_pending_spawns.size(), MAX_SPAWNS_PER_BATCH)

	for i in spawns_to_send:
		var request: SpawnRequest = _pending_spawns[i]
		batch.append(request.to_dict())

		# Track for confirmation
		_awaiting_confirmation[request.spawn_id] = request

	# Remove sent spawns
	for i in range(spawns_to_send - 1, -1, -1):
		_pending_spawns.remove_at(i)

	var packet := {
		"type": "spawn_batch",
		"spawns": batch,
		"batch_time": Time.get_ticks_msec(),
		"rng_frame": _deterministic_rng.get_current_frame() if _deterministic_rng != null else 0
	}

	# Spawns are critical events
	_network_manager.send_critical_event("spawn_batch", packet)
	_last_batch_time = Time.get_ticks_msec()


## Receive spawn batch (client).
func receive_spawn_batch(data: Dictionary) -> Array[SpawnRequest]:
	if _is_server:
		return []

	var spawns: Array = data.get("spawns", [])
	var result: Array[SpawnRequest] = []

	# Sync RNG if needed
	if _deterministic_rng != null:
		var server_frame: int = data.get("rng_frame", 0)
		if _deterministic_rng.get_current_frame() < server_frame:
			_deterministic_rng.advance_to_frame(server_frame)

	for spawn_data in spawns:
		var request := SpawnRequest.from_dict(spawn_data)
		_spawn_queue.append(request)
		result.append(request)

	return result


## Process spawn queue on client.
func _process_spawn_queue() -> void:
	# In a real implementation, this would spawn entities over time
	# to prevent lag spikes from many simultaneous spawns
	pass


## Get next spawn from queue (client).
func get_next_spawn() -> SpawnRequest:
	if _spawn_queue.is_empty():
		return null
	return _spawn_queue.pop_front()


## Get all pending spawns (client).
func get_pending_spawns() -> Array[SpawnRequest]:
	return _spawn_queue.duplicate()


## Confirm spawn completed (server).
func confirm_spawn(spawn_id: int, entity_id: int) -> void:
	if _awaiting_confirmation.has(spawn_id):
		_awaiting_confirmation.erase(spawn_id)
		spawn_confirmed.emit(spawn_id, entity_id)


## Check for confirmation timeouts.
func _check_confirmation_timeouts() -> void:
	var current_time := Time.get_ticks_msec()
	var timed_out: Array[int] = []

	for spawn_id in _awaiting_confirmation:
		var request: SpawnRequest = _awaiting_confirmation[spawn_id]
		var elapsed := (current_time - request.timestamp) / 1000.0
		if elapsed > SPAWN_CONFIRMATION_TIMEOUT:
			timed_out.append(spawn_id)

	for spawn_id in timed_out:
		var request: SpawnRequest = _awaiting_confirmation[spawn_id]
		_awaiting_confirmation.erase(spawn_id)
		spawn_failed.emit(spawn_id, "Spawn confirmation timeout")


## Get spawn statistics.
func get_stats() -> Dictionary:
	return {
		"is_server": _is_server,
		"pending_spawns": _pending_spawns.size(),
		"awaiting_confirmation": _awaiting_confirmation.size(),
		"spawn_queue": _spawn_queue.size(),
		"total_spawns": _spawn_counter,
		"total_batches": _batch_counter
	}


## Clear all spawn state.
func clear() -> void:
	_pending_spawns.clear()
	_awaiting_confirmation.clear()
	_spawn_queue.clear()
	_spawn_counter = 0
	_batch_counter = 0


## SpawnRequest data class.
class SpawnRequest:
	var spawn_id: int = -1
	var batch_id: int = -1
	var spawn_type: String = ""
	var position: Vector3 = Vector3.ZERO
	var rotation: float = 0.0
	var faction_id: String = ""
	var extra_data: Dictionary = {}
	var timestamp: int = 0
	var rng_seed: int = 0

	func to_dict() -> Dictionary:
		return {
			"spawn_id": spawn_id,
			"batch_id": batch_id,
			"spawn_type": spawn_type,
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"rotation": rotation,
			"faction_id": faction_id,
			"extra_data": extra_data,
			"timestamp": timestamp,
			"rng_seed": rng_seed
		}

	static func from_dict(data: Dictionary) -> SpawnRequest:
		var request := SpawnRequest.new()
		request.spawn_id = data.get("spawn_id", -1)
		request.batch_id = data.get("batch_id", -1)
		request.spawn_type = data.get("spawn_type", "")

		var pos: Dictionary = data.get("position", {})
		request.position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

		request.rotation = data.get("rotation", 0.0)
		request.faction_id = data.get("faction_id", "")
		request.extra_data = data.get("extra_data", {})
		request.timestamp = data.get("timestamp", 0)
		request.rng_seed = data.get("rng_seed", 0)

		return request
