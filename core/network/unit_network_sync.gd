class_name UnitNetworkSync
extends RefCounted
## UnitNetworkSync handles network synchronization for individual units.
## Optimized for handling up to 500+ units without bandwidth issues.

signal unit_state_updated(unit_id: int, state: Dictionary)
signal unit_interpolated(unit_id: int, position: Vector3, rotation: float)
signal sync_error(unit_id: int, error: String)

## Sync configuration
const MAX_UNITS_PER_BATCH := 50
const POSITION_THRESHOLD := 0.1      ## Min position change to sync
const ROTATION_THRESHOLD := 0.05     ## Min rotation change to sync (radians)
const HEALTH_SYNC_IMMEDIATE := true  ## Always sync health changes immediately

## Priority levels for sync
enum SyncPriority {
	LOW,        ## Background updates
	NORMAL,     ## Regular state
	HIGH,       ## Important changes
	CRITICAL    ## Must sync immediately
}

## Unit sync data
var _unit_states: Dictionary = {}        ## unit_id -> UnitSyncState
var _pending_updates: Array[Dictionary] = []
var _interpolation_targets: Dictionary = {}  ## unit_id -> {from, to, progress}

## Bandwidth tracking
var _bytes_sent := 0
var _bytes_received := 0
var _packets_sent := 0
var _last_bandwidth_reset := 0.0

## Authority
var _is_server := false


func _init() -> void:
	pass


## Set server authority.
func set_authority(is_server: bool) -> void:
	_is_server = is_server


## Register unit for synchronization.
func register_unit(unit_id: int, initial_state: Dictionary) -> void:
	var sync_state := UnitSyncState.new()
	sync_state.unit_id = unit_id
	sync_state.current_state = initial_state.duplicate(true)
	sync_state.last_synced_state = initial_state.duplicate(true)
	sync_state.last_sync_time = Time.get_ticks_msec()
	_unit_states[unit_id] = sync_state


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_states.erase(unit_id)
	_interpolation_targets.erase(unit_id)


## Update unit state locally.
func update_local_state(unit_id: int, state: Dictionary) -> void:
	if not _unit_states.has(unit_id):
		register_unit(unit_id, state)
		return

	var sync_state: UnitSyncState = _unit_states[unit_id]
	sync_state.current_state = state.duplicate(true)
	sync_state.dirty = _calculate_dirty_fields(sync_state)


## Get units that need syncing.
func get_units_to_sync() -> Array[Dictionary]:
	var units_to_sync: Array[Dictionary] = []

	for unit_id in _unit_states:
		var sync_state: UnitSyncState = _unit_states[unit_id]
		if sync_state.dirty.size() > 0:
			var sync_data := _create_sync_packet(unit_id, sync_state)
			if not sync_data.is_empty():
				units_to_sync.append(sync_data)

			# Mark as synced
			sync_state.last_synced_state = sync_state.current_state.duplicate(true)
			sync_state.last_sync_time = Time.get_ticks_msec()
			sync_state.dirty.clear()

	return units_to_sync


## Get batched sync data.
func get_sync_batches() -> Array[Dictionary]:
	var all_units := get_units_to_sync()
	var batches: Array[Dictionary] = []

	var current_batch: Array[Dictionary] = []
	for unit_data in all_units:
		current_batch.append(unit_data)
		if current_batch.size() >= MAX_UNITS_PER_BATCH:
			batches.append({"units": current_batch.duplicate()})
			current_batch.clear()

	if not current_batch.is_empty():
		batches.append({"units": current_batch})

	return batches


## Apply received sync data.
func apply_sync_data(data: Dictionary) -> void:
	var units: Array = data.get("units", [])

	for unit_data in units:
		_apply_unit_sync(unit_data)


## Apply sync for a single unit.
func _apply_unit_sync(data: Dictionary) -> void:
	var unit_id: int = data.get("unit_id", -1)
	if unit_id < 0:
		return

	if not _unit_states.has(unit_id):
		# New unit - register it
		register_unit(unit_id, data)
		unit_state_updated.emit(unit_id, data)
		return

	var sync_state: UnitSyncState = _unit_states[unit_id]

	# Setup interpolation for position
	if data.has("position"):
		var new_pos: Vector3 = data["position"]
		var old_pos: Vector3 = sync_state.current_state.get("position", new_pos)

		_interpolation_targets[unit_id] = {
			"from_pos": old_pos,
			"to_pos": new_pos,
			"from_rot": sync_state.current_state.get("rotation", 0.0),
			"to_rot": data.get("rotation", 0.0),
			"progress": 0.0
		}

	# Apply non-interpolated fields immediately
	for key in data:
		if key not in ["position", "rotation"]:
			sync_state.current_state[key] = data[key]

	sync_state.last_synced_state = sync_state.current_state.duplicate(true)
	unit_state_updated.emit(unit_id, sync_state.current_state)


## Update interpolation (call each frame).
func update_interpolation(delta: float) -> void:
	var completed: Array[int] = []

	for unit_id in _interpolation_targets:
		var target: Dictionary = _interpolation_targets[unit_id]
		target["progress"] += delta * 10.0  ## Interpolation speed

		if target["progress"] >= 1.0:
			target["progress"] = 1.0
			completed.append(unit_id)

		# Interpolate position
		var from_pos: Vector3 = target["from_pos"]
		var to_pos: Vector3 = target["to_pos"]
		var interp_pos := from_pos.lerp(to_pos, target["progress"])

		# Interpolate rotation
		var from_rot: float = target["from_rot"]
		var to_rot: float = target["to_rot"]
		var interp_rot := lerpf(from_rot, to_rot, target["progress"])

		# Update state
		if _unit_states.has(unit_id):
			_unit_states[unit_id].current_state["position"] = interp_pos
			_unit_states[unit_id].current_state["rotation"] = interp_rot

		unit_interpolated.emit(unit_id, interp_pos, interp_rot)

	# Remove completed interpolations
	for unit_id in completed:
		_interpolation_targets.erase(unit_id)


## Calculate dirty fields for a unit.
func _calculate_dirty_fields(sync_state: UnitSyncState) -> Array[String]:
	var dirty: Array[String] = []
	var current := sync_state.current_state
	var last := sync_state.last_synced_state

	# Check position
	if current.has("position") and last.has("position"):
		var pos_diff: Vector3 = current["position"] - last["position"]
		if pos_diff.length() > POSITION_THRESHOLD:
			dirty.append("position")
	elif current.has("position"):
		dirty.append("position")

	# Check rotation
	if current.has("rotation") and last.has("rotation"):
		var rot_diff: float = absf(current["rotation"] - last["rotation"])
		if rot_diff > ROTATION_THRESHOLD:
			dirty.append("rotation")
	elif current.has("rotation"):
		dirty.append("rotation")

	# Check health (always sync if changed)
	if current.get("health", -1) != last.get("health", -1):
		dirty.append("health")

	# Check state
	if current.get("state", "") != last.get("state", ""):
		dirty.append("state")

	# Check target
	if current.get("target_id", -1) != last.get("target_id", -1):
		dirty.append("target_id")

	return dirty


## Create sync packet for a unit.
func _create_sync_packet(unit_id: int, sync_state: UnitSyncState) -> Dictionary:
	var packet := {"unit_id": unit_id}

	for field in sync_state.dirty:
		if sync_state.current_state.has(field):
			packet[field] = sync_state.current_state[field]

	return packet


## Get unit state.
func get_unit_state(unit_id: int) -> Dictionary:
	if _unit_states.has(unit_id):
		return _unit_states[unit_id].current_state.duplicate()
	return {}


## Get interpolated position.
func get_interpolated_position(unit_id: int) -> Vector3:
	if _interpolation_targets.has(unit_id):
		var target: Dictionary = _interpolation_targets[unit_id]
		var from: Vector3 = target["from_pos"]
		var to: Vector3 = target["to_pos"]
		return from.lerp(to, target["progress"])

	if _unit_states.has(unit_id):
		return _unit_states[unit_id].current_state.get("position", Vector3.ZERO)

	return Vector3.ZERO


## Get unit count.
func get_synced_unit_count() -> int:
	return _unit_states.size()


## Get bandwidth statistics.
func get_bandwidth_stats() -> Dictionary:
	return {
		"bytes_sent": _bytes_sent,
		"bytes_received": _bytes_received,
		"packets_sent": _packets_sent,
		"units_tracked": _unit_states.size(),
		"interpolating": _interpolation_targets.size()
	}


## Reset bandwidth tracking.
func reset_bandwidth_stats() -> void:
	_bytes_sent = 0
	_bytes_received = 0
	_packets_sent = 0


## Clear all sync state.
func clear() -> void:
	_unit_states.clear()
	_interpolation_targets.clear()
	_pending_updates.clear()
	reset_bandwidth_stats()


## UnitSyncState helper class.
class UnitSyncState:
	var unit_id: int = -1
	var current_state: Dictionary = {}
	var last_synced_state: Dictionary = {}
	var last_sync_time: int = 0
	var dirty: Array[String] = []
	var priority: int = 0  ## SyncPriority
