class_name CameraStateSync
extends RefCounted
## CameraStateSync handles multiplayer synchronization of camera states.
## Keeps camera views consistent across all connected clients.

signal remote_zoom_changed(peer_id: int, zoom_level: float)
signal remote_factory_selected(peer_id: int, factory_id: int)
signal remote_position_changed(peer_id: int, position: Vector3)
signal sync_error(peer_id: int, error: String)
signal disconnection_handled(peer_id: int)

## Sync configuration
const SYNC_INTERVAL := 0.1           ## 100ms max delay for zoom changes
const POSITION_SYNC_INTERVAL := 0.05 ## 50ms for position (less critical)
const THROTTLE_THRESHOLD := 0.016    ## Min time between syncs

## Network reference
var _network_manager: NetworkManager = null
var _is_connected := false

## Local state
var _local_state: CameraState = null
var _last_synced_state: CameraState = null

## Remote states (peer_id -> CameraState)
var _remote_states: Dictionary = {}

## Timing
var _last_zoom_sync := 0.0
var _last_position_sync := 0.0
var _last_factory_sync := 0.0

## Pending syncs
var _pending_zoom_sync := false
var _pending_position_sync := false
var _pending_factory_sync := false

## Factory validation callback
var _factory_exists_callback: Callable


func _init() -> void:
	_local_state = CameraState.new()
	_last_synced_state = CameraState.new()


## Initialize with network manager.
func initialize(network_manager: NetworkManager) -> void:
	_network_manager = network_manager

	if _network_manager != null:
		_is_connected = _network_manager.is_connected()
		_network_manager.peer_connected.connect(_on_peer_connected)
		_network_manager.peer_disconnected.connect(_on_peer_disconnected)
		_network_manager.server_disconnected.connect(_on_server_disconnected)


## Set factory validation callback.
func set_factory_validator(callback: Callable) -> void:
	_factory_exists_callback = callback


## Update (call each frame).
func update(delta: float) -> void:
	if not _is_connected or _network_manager == null:
		return

	_last_zoom_sync += delta
	_last_position_sync += delta
	_last_factory_sync += delta

	# Process pending syncs with throttling
	if _pending_zoom_sync and _last_zoom_sync >= SYNC_INTERVAL:
		_sync_zoom()
		_pending_zoom_sync = false
		_last_zoom_sync = 0.0

	if _pending_position_sync and _last_position_sync >= POSITION_SYNC_INTERVAL:
		_sync_position()
		_pending_position_sync = false
		_last_position_sync = 0.0

	if _pending_factory_sync and _last_factory_sync >= SYNC_INTERVAL:
		_sync_factory_selection()
		_pending_factory_sync = false
		_last_factory_sync = 0.0


## Set local camera state.
func set_local_state(state: CameraState) -> void:
	_local_state = state

	# Connect to state change signal
	if not _local_state.state_changed.is_connected(_on_local_state_changed):
		_local_state.state_changed.connect(_on_local_state_changed)


## Handle local state change.
func _on_local_state_changed() -> void:
	if _last_synced_state == null:
		_last_synced_state = _local_state.clone()
		return

	# Detect what changed
	if _local_state.zoom_level != _last_synced_state.zoom_level:
		_pending_zoom_sync = true

	if _local_state.camera_position.distance_to(_last_synced_state.camera_position) > 0.1:
		_pending_position_sync = true

	if _local_state.selected_factory_id != _last_synced_state.selected_factory_id:
		_pending_factory_sync = true


## Sync zoom level to all peers.
func _sync_zoom() -> void:
	if _network_manager == null:
		return

	var sync_data := {
		"zoom_level": _local_state.zoom_level,
		"timestamp": _local_state.timestamp
	}

	_network_manager.rpc_send("rpc_camera_zoom", [sync_data], 0)
	_last_synced_state.zoom_level = _local_state.zoom_level


## Sync position to all peers.
func _sync_position() -> void:
	if _network_manager == null:
		return

	var sync_data := {
		"position": {
			"x": _local_state.camera_position.x,
			"y": _local_state.camera_position.y,
			"z": _local_state.camera_position.z
		},
		"rotation": {
			"x": _local_state.camera_rotation.x,
			"y": _local_state.camera_rotation.y,
			"z": _local_state.camera_rotation.z
		},
		"timestamp": _local_state.timestamp
	}

	_network_manager.rpc_send("rpc_camera_position", [sync_data], 0)
	_last_synced_state.camera_position = _local_state.camera_position
	_last_synced_state.camera_rotation = _local_state.camera_rotation


## Sync factory selection to all peers.
func _sync_factory_selection() -> void:
	if _network_manager == null:
		return

	var sync_data := {
		"factory_id": _local_state.selected_factory_id,
		"view_mode": _local_state.view_mode,
		"timestamp": _local_state.timestamp
	}

	_network_manager.rpc_send("rpc_camera_factory", [sync_data], 0)
	_last_synced_state.selected_factory_id = _local_state.selected_factory_id


## Receive zoom sync from remote peer.
func receive_zoom_sync(peer_id: int, data: Dictionary) -> void:
	var zoom_level: float = data.get("zoom_level", 1.0)
	var timestamp: int = data.get("timestamp", 0)

	# Get or create remote state
	var remote_state := _get_or_create_remote_state(peer_id)

	# Only apply if newer
	if timestamp > remote_state.timestamp:
		remote_state.zoom_level = zoom_level
		remote_state.timestamp = timestamp
		remote_zoom_changed.emit(peer_id, zoom_level)


## Receive position sync from remote peer.
func receive_position_sync(peer_id: int, data: Dictionary) -> void:
	var pos_data: Dictionary = data.get("position", {})
	var rot_data: Dictionary = data.get("rotation", {})
	var timestamp: int = data.get("timestamp", 0)

	var position := Vector3(
		pos_data.get("x", 0.0),
		pos_data.get("y", 0.0),
		pos_data.get("z", 0.0)
	)

	var rotation := Vector3(
		rot_data.get("x", 0.0),
		rot_data.get("y", 0.0),
		rot_data.get("z", 0.0)
	)

	var remote_state := _get_or_create_remote_state(peer_id)

	if timestamp > remote_state.timestamp:
		remote_state.camera_position = position
		remote_state.camera_rotation = rotation
		remote_state.timestamp = timestamp
		remote_position_changed.emit(peer_id, position)


## Receive factory selection sync from remote peer.
func receive_factory_sync(peer_id: int, data: Dictionary) -> void:
	var factory_id: int = data.get("factory_id", -1)
	var view_mode: int = data.get("view_mode", CameraState.ViewMode.FREE)
	var timestamp: int = data.get("timestamp", 0)

	# Validate factory exists
	if factory_id >= 0 and _factory_exists_callback.is_valid():
		if not _factory_exists_callback.call(factory_id):
			sync_error.emit(peer_id, "Factory %d does not exist" % factory_id)
			return

	var remote_state := _get_or_create_remote_state(peer_id)

	if timestamp > remote_state.timestamp:
		remote_state.selected_factory_id = factory_id
		remote_state.view_mode = view_mode
		remote_state.timestamp = timestamp
		remote_factory_selected.emit(peer_id, factory_id)


## Get or create remote state for peer.
func _get_or_create_remote_state(peer_id: int) -> CameraState:
	if not _remote_states.has(peer_id):
		_remote_states[peer_id] = CameraState.new()
	return _remote_states[peer_id]


## Get remote state for a peer.
func get_remote_state(peer_id: int) -> CameraState:
	return _remote_states.get(peer_id, null)


## Get all remote states.
func get_all_remote_states() -> Dictionary:
	return _remote_states.duplicate()


## Handle peer connected.
func _on_peer_connected(peer_id: int) -> void:
	# Create state for new peer
	_remote_states[peer_id] = CameraState.new()

	# Send our current state to new peer
	if _local_state != null:
		_sync_full_state_to_peer(peer_id)


## Handle peer disconnected.
func _on_peer_disconnected(peer_id: int) -> void:
	_remote_states.erase(peer_id)
	disconnection_handled.emit(peer_id)


## Handle server disconnected.
func _on_server_disconnected() -> void:
	_is_connected = false
	_remote_states.clear()


## Send full state to specific peer.
func _sync_full_state_to_peer(peer_id: int) -> void:
	if _network_manager == null or _local_state == null:
		return

	var sync_data := _local_state.to_dict()
	sync_data["type"] = "full_state"

	_network_manager.rpc_send("rpc_camera_full_state", [sync_data], peer_id)


## Receive full state sync.
func receive_full_state(peer_id: int, data: Dictionary) -> void:
	var remote_state := _get_or_create_remote_state(peer_id)
	remote_state.from_dict(data)

	# Emit all relevant signals
	remote_zoom_changed.emit(peer_id, remote_state.zoom_level)
	remote_position_changed.emit(peer_id, remote_state.camera_position)
	remote_factory_selected.emit(peer_id, remote_state.selected_factory_id)


## Force sync local state immediately.
func force_sync() -> void:
	_sync_zoom()
	_sync_position()
	_sync_factory_selection()
	_last_synced_state = _local_state.clone()


## Get local state.
func get_local_state() -> CameraState:
	return _local_state


## Set connection status.
func set_connected(connected: bool) -> void:
	_is_connected = connected
	if not connected:
		_remote_states.clear()


## Get sync statistics.
func get_stats() -> Dictionary:
	return {
		"connected": _is_connected,
		"remote_peers": _remote_states.size(),
		"pending_zoom": _pending_zoom_sync,
		"pending_position": _pending_position_sync,
		"pending_factory": _pending_factory_sync,
		"last_zoom_sync": _last_zoom_sync,
		"last_position_sync": _last_position_sync
	}


## Cleanup.
func cleanup() -> void:
	_remote_states.clear()
	_is_connected = false

	if _network_manager != null:
		if _network_manager.peer_connected.is_connected(_on_peer_connected):
			_network_manager.peer_connected.disconnect(_on_peer_connected)
		if _network_manager.peer_disconnected.is_connected(_on_peer_disconnected):
			_network_manager.peer_disconnected.disconnect(_on_peer_disconnected)
		if _network_manager.server_disconnected.is_connected(_on_server_disconnected):
			_network_manager.server_disconnected.disconnect(_on_server_disconnected)
