class_name HumanResistanceSync
extends RefCounted
## HumanResistanceSync handles multiplayer synchronization for the Human Resistance faction.
## Ensures consistent faction state across all clients with server authority.

signal faction_state_synced(state: Dictionary)
signal unit_spawned(unit_id: int, unit_data: Dictionary)
signal unit_action_synced(unit_id: int, action: String, data: Dictionary)
signal unit_destroyed(unit_id: int, destroyer_faction: String)
signal commander_buff_synced(commander_id: int, buff_data: Dictionary)
signal resource_dropped(position: Vector3, amount: float)

## Sync rates
const STATE_SYNC_RATE := 60.0         ## Hz - faction state sync rate
const UNIT_SYNC_RATE := 30.0          ## Hz - individual unit sync rate
const BATCH_SIZE := 50                ## Max units per sync batch

## Authority
var _is_server := false
var _network_manager: NetworkManager = null

## Faction state
var _faction_state: Dictionary = {
	"unit_count": 0,
	"wave_number": 0,
	"difficulty_multiplier": 1.0,
	"threat_level": 0.0,
	"active_commanders": 0,
	"spawn_budget": 0
}

## Unit tracking
var _synced_units: Dictionary = {}     ## unit_id -> unit_state
var _pending_spawns: Array[Dictionary] = []
var _pending_actions: Array[Dictionary] = []
var _pending_deaths: Array[int] = []

## Sync timing
var _last_state_sync := 0.0
var _last_unit_sync := 0.0
var _sync_batch_index := 0

## Deterministic state for AI
var _deterministic_rng: DeterministicRNG = null
var _ai_decision_seed := 0


func _init() -> void:
	pass


## Initialize with network manager.
func initialize(network_manager: NetworkManager, deterministic_rng: DeterministicRNG) -> void:
	_network_manager = network_manager
	_deterministic_rng = deterministic_rng
	_is_server = network_manager.is_server()


## Update synchronization (call each frame).
func update(delta: float) -> void:
	if _network_manager == null or not _network_manager.is_network_connected():
		return

	_last_state_sync += delta
	_last_unit_sync += delta

	if _is_server:
		# Server broadcasts state
		if _last_state_sync >= 1.0 / STATE_SYNC_RATE:
			_broadcast_faction_state()
			_last_state_sync = 0.0

		if _last_unit_sync >= 1.0 / UNIT_SYNC_RATE:
			_broadcast_unit_updates()
			_last_unit_sync = 0.0

		# Process pending events
		_process_pending_spawns()
		_process_pending_deaths()


## Set server authority.
func set_authority(is_server: bool) -> void:
	_is_server = is_server


## Update faction state (server only).
func update_faction_state(state: Dictionary) -> void:
	if not _is_server:
		return

	for key in state:
		_faction_state[key] = state[key]


## Queue unit spawn (server only).
func queue_spawn(unit_data: Dictionary) -> void:
	if not _is_server:
		return

	_pending_spawns.append(unit_data)


## Queue unit action (server only).
func queue_action(unit_id: int, action: String, data: Dictionary) -> void:
	if not _is_server:
		return

	_pending_actions.append({
		"unit_id": unit_id,
		"action": action,
		"data": data,
		"timestamp": Time.get_ticks_msec()
	})


## Queue unit death (server only).
func queue_death(unit_id: int, destroyer_faction: String) -> void:
	if not _is_server:
		return

	# Deaths are critical events - send immediately
	_send_unit_death(unit_id, destroyer_faction)


## Register existing unit for sync.
func register_unit(unit_id: int, unit_state: Dictionary) -> void:
	_synced_units[unit_id] = unit_state


## Unregister unit from sync.
func unregister_unit(unit_id: int) -> void:
	_synced_units.erase(unit_id)


## Update unit state (server only).
func update_unit_state(unit_id: int, state: Dictionary) -> void:
	if not _is_server:
		return

	if _synced_units.has(unit_id):
		for key in state:
			_synced_units[unit_id][key] = state[key]
	else:
		_synced_units[unit_id] = state


## Get deterministic AI decision.
func get_ai_decision(unit_id: int, decision_type: String) -> int:
	if _deterministic_rng == null:
		return 0

	# Combine unit_id and decision_type for unique but deterministic result
	var combined_seed := unit_id * 1000 + decision_type.hash() % 1000
	return _deterministic_rng.randi_range(0, 100)


## Broadcast faction state to all clients.
func _broadcast_faction_state() -> void:
	if not _is_server or _network_manager == null:
		return

	var sync_data := {
		"type": "hr_faction_state",
		"state": _faction_state,
		"timestamp": Time.get_ticks_msec(),
		"rng_frame": _deterministic_rng.get_current_frame() if _deterministic_rng != null else 0
	}

	_network_manager.rpc_send("rpc_hr_faction_sync", [sync_data], 0)


## Broadcast unit updates in batches.
func _broadcast_unit_updates() -> void:
	if not _is_server or _network_manager == null:
		return

	var unit_ids := _synced_units.keys()
	if unit_ids.is_empty():
		return

	# Get batch of units to sync
	var start_index := _sync_batch_index * BATCH_SIZE
	var end_index := mini(start_index + BATCH_SIZE, unit_ids.size())

	if start_index >= unit_ids.size():
		_sync_batch_index = 0
		start_index = 0
		end_index = mini(BATCH_SIZE, unit_ids.size())

	var batch_data := {}
	for i in range(start_index, end_index):
		var unit_id: int = unit_ids[i]
		batch_data[unit_id] = _create_unit_sync_data(unit_id)

	var sync_data := {
		"type": "hr_unit_batch",
		"units": batch_data,
		"batch_index": _sync_batch_index,
		"total_units": unit_ids.size(),
		"timestamp": Time.get_ticks_msec()
	}

	_network_manager.rpc_send("rpc_hr_unit_sync", [sync_data], 0)
	_sync_batch_index += 1

	# Also send pending actions
	if not _pending_actions.is_empty():
		var actions := _pending_actions.duplicate()
		_pending_actions.clear()
		_network_manager.rpc_send("rpc_hr_actions", [actions], 0)


## Create sync data for a unit.
func _create_unit_sync_data(unit_id: int) -> Dictionary:
	var state: Dictionary = _synced_units.get(unit_id, {})
	return {
		"position": state.get("position", Vector3.ZERO),
		"rotation": state.get("rotation", 0.0),
		"health": state.get("health", 0),
		"state": state.get("state", "idle"),
		"target_id": state.get("target_id", -1),
		"velocity": state.get("velocity", Vector3.ZERO)
	}


## Process pending spawns.
func _process_pending_spawns() -> void:
	if _pending_spawns.is_empty():
		return

	for spawn_data in _pending_spawns:
		_send_spawn_event(spawn_data)

	_pending_spawns.clear()


## Process pending deaths.
func _process_pending_deaths() -> void:
	# Deaths should be sent immediately via queue_death()
	pass


## Send spawn event to all clients.
func _send_spawn_event(unit_data: Dictionary) -> void:
	if _network_manager == null:
		return

	var spawn_event := {
		"type": "hr_spawn",
		"unit_id": unit_data.get("unit_id", 0),
		"unit_type": unit_data.get("unit_type", ""),
		"position": unit_data.get("position", Vector3.ZERO),
		"rotation": unit_data.get("rotation", 0.0),
		"health": unit_data.get("health", 100),
		"squad_id": unit_data.get("squad_id", -1),
		"commander_id": unit_data.get("commander_id", -1),
		"timestamp": Time.get_ticks_msec()
	}

	# Spawns are critical events
	_network_manager.send_critical_event("hr_spawn", spawn_event)
	unit_spawned.emit(spawn_event["unit_id"], spawn_event)


## Send unit death to all clients.
func _send_unit_death(unit_id: int, destroyer_faction: String) -> void:
	if _network_manager == null:
		return

	var death_event := {
		"type": "hr_death",
		"unit_id": unit_id,
		"destroyer_faction": destroyer_faction,
		"timestamp": Time.get_ticks_msec()
	}

	# Deaths are critical events
	_network_manager.send_critical_event("hr_death", death_event)
	_synced_units.erase(unit_id)
	unit_destroyed.emit(unit_id, destroyer_faction)


## Send commander buff to all clients.
func sync_commander_buff(commander_id: int, buff_data: Dictionary) -> void:
	if not _is_server or _network_manager == null:
		return

	var buff_event := {
		"type": "hr_commander_buff",
		"commander_id": commander_id,
		"buff_type": buff_data.get("type", ""),
		"radius": buff_data.get("radius", 0.0),
		"strength": buff_data.get("strength", 0.0),
		"affected_units": buff_data.get("affected_units", []),
		"timestamp": Time.get_ticks_msec()
	}

	_network_manager.rpc_send("rpc_hr_commander_buff", [buff_event], 0)
	commander_buff_synced.emit(commander_id, buff_event)


## Send resource drop to all clients.
func sync_resource_drop(position: Vector3, amount: float, source_unit_id: int) -> void:
	if not _is_server or _network_manager == null:
		return

	var drop_event := {
		"type": "hr_resource_drop",
		"position": position,
		"amount": amount,
		"source_unit_id": source_unit_id,
		"timestamp": Time.get_ticks_msec()
	}

	_network_manager.rpc_send("rpc_hr_resource_drop", [drop_event], 0)
	resource_dropped.emit(position, amount)


## Receive faction state sync (client).
func receive_faction_state(data: Dictionary) -> void:
	if _is_server:
		return

	_faction_state = data.get("state", {})

	# Sync RNG frame if needed
	if _deterministic_rng != null:
		var server_frame: int = data.get("rng_frame", 0)
		if _deterministic_rng.get_current_frame() < server_frame:
			_deterministic_rng.advance_to_frame(server_frame)

	faction_state_synced.emit(_faction_state)


## Receive unit batch sync (client).
func receive_unit_batch(data: Dictionary) -> void:
	if _is_server:
		return

	var units: Dictionary = data.get("units", {})
	for unit_id_str in units:
		var unit_id := int(unit_id_str)
		var unit_data: Dictionary = units[unit_id_str]

		if _synced_units.has(unit_id):
			# Update existing unit
			for key in unit_data:
				_synced_units[unit_id][key] = unit_data[key]
		else:
			# New unit (may have missed spawn event)
			_synced_units[unit_id] = unit_data


## Receive actions sync (client).
func receive_actions(actions: Array) -> void:
	if _is_server:
		return

	for action in actions:
		var unit_id: int = action.get("unit_id", -1)
		var action_type: String = action.get("action", "")
		var action_data: Dictionary = action.get("data", {})
		unit_action_synced.emit(unit_id, action_type, action_data)


## Receive spawn event (client).
func receive_spawn(data: Dictionary) -> void:
	if _is_server:
		return

	var unit_id: int = data.get("unit_id", 0)
	_synced_units[unit_id] = {
		"position": data.get("position", Vector3.ZERO),
		"rotation": data.get("rotation", 0.0),
		"health": data.get("health", 100),
		"state": "spawned"
	}
	unit_spawned.emit(unit_id, data)


## Receive death event (client).
func receive_death(data: Dictionary) -> void:
	if _is_server:
		return

	var unit_id: int = data.get("unit_id", -1)
	var destroyer: String = data.get("destroyer_faction", "")
	_synced_units.erase(unit_id)
	unit_destroyed.emit(unit_id, destroyer)


## Get faction state.
func get_faction_state() -> Dictionary:
	return _faction_state.duplicate()


## Get unit count.
func get_synced_unit_count() -> int:
	return _synced_units.size()


## Get unit state.
func get_unit_state(unit_id: int) -> Dictionary:
	return _synced_units.get(unit_id, {})


## Get sync statistics.
func get_sync_stats() -> Dictionary:
	return {
		"is_server": _is_server,
		"synced_units": _synced_units.size(),
		"pending_spawns": _pending_spawns.size(),
		"pending_actions": _pending_actions.size(),
		"faction_state": _faction_state
	}


## Clear all sync state.
func clear() -> void:
	_synced_units.clear()
	_pending_spawns.clear()
	_pending_actions.clear()
	_pending_deaths.clear()
	_faction_state = {
		"unit_count": 0,
		"wave_number": 0,
		"difficulty_multiplier": 1.0,
		"threat_level": 0.0,
		"active_commanders": 0,
		"spawn_budget": 0
	}
