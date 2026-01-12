class_name NetworkManager
extends RefCounted
## NetworkManager orchestrates networking for both P2P (local co-op) and server-authoritative modes.
## Wraps Godot's MultiplayerAPI with custom abstraction for extensibility.

signal connection_established(peer_id: int)
signal connection_failed(reason: String)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected()
signal state_synchronized()
signal rpc_received(peer_id: int, method: String, args: Array)

## Network modes
enum NetworkMode {
	OFFLINE,           ## Single-player, no networking overhead
	LOCAL_P2P,         ## Local co-op, peer-to-peer
	ONLINE_SERVER,     ## Online, server-authoritative (this client is server)
	ONLINE_CLIENT      ## Online, server-authoritative (this client is a client)
}

## Connection states
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	SYNCHRONIZING,
	READY
}

## Configuration
const SNAPSHOT_RATE := 60.0         ## Hz - state snapshots per second
const SNAPSHOT_INTERVAL := 1.0 / SNAPSHOT_RATE
const FRAME_BUDGET_MS := 1.0        ## Max ms per frame for network operations
const DEFAULT_PORT := 27015
const MAX_CLIENTS := 4

## Rate limiting
const RPC_RATE_LIMIT := 60          ## Max RPCs per second per client
const RPC_BURST_LIMIT := 10         ## Max burst RPCs

## State
var _mode := NetworkMode.OFFLINE
var _state := ConnectionState.DISCONNECTED
var _peer_id := 0
var _is_server := false
var _connected_peers: Array[int] = []

## Time tracking
var _last_snapshot_time := 0.0
var _network_time := 0.0
var _frame_time_used := 0.0

## Sub-systems (initialized externally)
var state_snapshot: StateSnapshot = null
var client_prediction: ClientPrediction = null
var rpc_validator: RPCValidator = null
var deterministic_rng: DeterministicRNG = null
var network_simulation: NetworkSimulation = null

## Multiplayer API reference
var _multiplayer: MultiplayerAPI = null
var _enet_peer: ENetMultiplayerPeer = null


func _init() -> void:
	pass


## Initialize the network manager.
func initialize(scene_tree: SceneTree) -> void:
	_multiplayer = scene_tree.get_multiplayer()

	# Connect multiplayer signals
	_multiplayer.connected_to_server.connect(_on_connected_to_server)
	_multiplayer.connection_failed.connect(_on_connection_failed)
	_multiplayer.peer_connected.connect(_on_peer_connected)
	_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_multiplayer.server_disconnected.connect(_on_server_disconnected)


## Host a game (server mode).
func host_game(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> bool:
	if _state != ConnectionState.DISCONNECTED:
		push_warning("NetworkManager: Already connected")
		return false

	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_server(port, max_clients)

	if error != OK:
		push_error("NetworkManager: Failed to create server: " + str(error))
		connection_failed.emit("Failed to create server")
		return false

	_multiplayer.multiplayer_peer = _enet_peer
	_is_server = true
	_mode = NetworkMode.ONLINE_SERVER
	_state = ConnectionState.CONNECTED
	_peer_id = 1  ## Server is always peer 1

	# Initialize server-side systems
	_initialize_server_systems()

	connection_established.emit(_peer_id)
	return true


## Join a game (client mode).
func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if _state != ConnectionState.DISCONNECTED:
		push_warning("NetworkManager: Already connected")
		return false

	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_client(address, port)

	if error != OK:
		push_error("NetworkManager: Failed to connect: " + str(error))
		connection_failed.emit("Failed to connect to server")
		return false

	_multiplayer.multiplayer_peer = _enet_peer
	_is_server = false
	_mode = NetworkMode.ONLINE_CLIENT
	_state = ConnectionState.CONNECTING

	return true


## Host local P2P game.
func host_local_p2p() -> bool:
	_mode = NetworkMode.LOCAL_P2P
	_is_server = true
	_state = ConnectionState.CONNECTED
	_peer_id = 1
	connection_established.emit(_peer_id)
	return true


## Join local P2P game.
func join_local_p2p(host_peer: NetworkManager) -> bool:
	_mode = NetworkMode.LOCAL_P2P
	_is_server = false
	_state = ConnectionState.CONNECTED
	_peer_id = 2
	connection_established.emit(_peer_id)
	return true


## Start offline/single-player mode.
func start_offline() -> void:
	_mode = NetworkMode.OFFLINE
	_is_server = true
	_state = ConnectionState.READY
	_peer_id = 1


## Disconnect from network.
func disconnect_network() -> void:
	if _enet_peer != null:
		_enet_peer.close()
		_enet_peer = null

	_multiplayer.multiplayer_peer = null
	_mode = NetworkMode.OFFLINE
	_state = ConnectionState.DISCONNECTED
	_is_server = false
	_peer_id = 0
	_connected_peers.clear()


## Update network (call each frame).
func update(delta: float) -> void:
	if _mode == NetworkMode.OFFLINE:
		return

	_frame_time_used = 0.0
	_network_time += delta

	# Send state snapshots at configured rate
	if _is_server:
		_last_snapshot_time += delta
		if _last_snapshot_time >= SNAPSHOT_INTERVAL:
			_send_state_snapshot()
			_last_snapshot_time = 0.0

	# Process client prediction
	if not _is_server and client_prediction != null:
		client_prediction.update(delta)

	# Apply network simulation (dev only)
	if network_simulation != null and network_simulation.is_enabled():
		network_simulation.update(delta)


## Send state snapshot to all clients.
func _send_state_snapshot() -> void:
	if state_snapshot == null:
		return

	if _check_frame_budget():
		return

	var snapshot := state_snapshot.create_snapshot()
	var compressed := state_snapshot.compress_delta(snapshot)

	for peer_id in _connected_peers:
		_rpc_send_snapshot(peer_id, compressed)


## Check if frame budget exceeded.
func _check_frame_budget() -> bool:
	return _frame_time_used >= FRAME_BUDGET_MS


## Add time to frame budget.
func _add_frame_time(ms: float) -> void:
	_frame_time_used += ms


## Initialize server-side systems.
func _initialize_server_systems() -> void:
	if deterministic_rng != null:
		var seed_value := int(Time.get_unix_time_from_system() * 1000)
		deterministic_rng.initialize(seed_value)


## Send RPC (wrapper with validation).
func rpc_send(method: String, args: Array, target_peer: int = 0) -> bool:
	if _mode == NetworkMode.OFFLINE:
		return false

	# Validate RPC
	if rpc_validator != null:
		if not rpc_validator.validate_outgoing(method, args):
			return false
		if not rpc_validator.check_rate_limit(_peer_id):
			push_warning("NetworkManager: RPC rate limited")
			return false

	# Apply simulation delays
	if network_simulation != null and network_simulation.is_enabled():
		network_simulation.queue_outgoing_rpc(method, args, target_peer)
		return true

	return _send_rpc_internal(method, args, target_peer)


## Internal RPC send.
func _send_rpc_internal(method: String, args: Array, target_peer: int) -> bool:
	# Implementation depends on actual RPC setup
	rpc_received.emit(_peer_id, method, args)
	return true


## Send snapshot RPC to specific peer.
func _rpc_send_snapshot(peer_id: int, data: PackedByteArray) -> void:
	# Would use actual RPC in real implementation
	pass


## Send critical event immediately (bypass batching).
func send_critical_event(event_type: String, data: Dictionary) -> void:
	if _mode == NetworkMode.OFFLINE:
		return

	# Critical events bypass normal batching
	var packet := {
		"type": event_type,
		"data": data,
		"timestamp": _network_time,
		"critical": true
	}

	if _is_server:
		for peer_id in _connected_peers:
			_send_critical_to_peer(peer_id, packet)
	else:
		_send_critical_to_peer(1, packet)  ## Send to server


## Send critical event to specific peer.
func _send_critical_to_peer(peer_id: int, packet: Dictionary) -> void:
	# Would use reliable RPC in real implementation
	pass


## Validate action on server (anti-cheat).
func validate_action(peer_id: int, action_type: String, action_data: Dictionary) -> bool:
	if not _is_server:
		return true  ## Only server validates

	if rpc_validator == null:
		return true

	return rpc_validator.validate_action(peer_id, action_type, action_data)


## Broadcast validated action to all clients.
func broadcast_validated_action(action_type: String, action_data: Dictionary) -> void:
	if not _is_server:
		return

	for peer_id in _connected_peers:
		_send_action_to_peer(peer_id, action_type, action_data)


## Send action to specific peer.
func _send_action_to_peer(peer_id: int, action_type: String, action_data: Dictionary) -> void:
	pass


## Signal handlers
func _on_connected_to_server() -> void:
	_state = ConnectionState.CONNECTED
	_peer_id = _multiplayer.get_unique_id()
	connection_established.emit(_peer_id)

	# Request initial state sync
	_state = ConnectionState.SYNCHRONIZING


func _on_connection_failed() -> void:
	_state = ConnectionState.DISCONNECTED
	connection_failed.emit("Connection to server failed")


func _on_peer_connected(peer_id: int) -> void:
	_connected_peers.append(peer_id)
	peer_connected.emit(peer_id)

	# Send current state to new peer
	if _is_server and state_snapshot != null:
		var full_snapshot := state_snapshot.create_full_snapshot()
		_rpc_send_snapshot(peer_id, full_snapshot)


func _on_peer_disconnected(peer_id: int) -> void:
	_connected_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)


func _on_server_disconnected() -> void:
	_state = ConnectionState.DISCONNECTED
	_connected_peers.clear()
	server_disconnected.emit()


## Getters
func get_mode() -> NetworkMode:
	return _mode


func get_state() -> ConnectionState:
	return _state


func get_peer_id() -> int:
	return _peer_id


func is_server() -> bool:
	return _is_server


func is_online() -> bool:
	return _mode == NetworkMode.ONLINE_SERVER or _mode == NetworkMode.ONLINE_CLIENT


func is_connected() -> bool:
	return _state == ConnectionState.CONNECTED or _state == ConnectionState.READY


func get_connected_peers() -> Array[int]:
	return _connected_peers.duplicate()


func get_network_time() -> float:
	return _network_time


## Cleanup.
func cleanup() -> void:
	disconnect_network()

	if state_snapshot != null:
		state_snapshot = null
	if client_prediction != null:
		client_prediction = null
	if rpc_validator != null:
		rpc_validator = null
	if deterministic_rng != null:
		deterministic_rng = null
	if network_simulation != null:
		network_simulation = null
