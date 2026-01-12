class_name HackingSynchronization
extends RefCounted
## HackingSynchronization handles multiplayer sync for hacking state.
## Provides RPC-ready methods for network synchronization.

signal sync_requested(state: HackingState)
signal batch_sync_requested(states: Array[HackingState])
signal remote_hack_received(unit_id: int, hacker_faction: String)
signal remote_unhack_received(unit_id: int)
signal sync_completed(unit_count: int)

## State cache
var _cache: HackingStateCache = null

## Pending sync queue
var _pending_sync: Array[int] = []

## Sync interval (seconds)
var sync_interval: float = 0.1  ## 100ms

## Time since last sync
var _sync_timer: float = 0.0

## Maximum batch size
var max_batch_size: int = 50

## Local peer ID
var local_peer_id: int = 1


func _init() -> void:
	_cache = HackingStateCache.new()


## Get cache.
func get_cache() -> HackingStateCache:
	return _cache


## Queue state for sync.
func queue_sync(unit_id: int) -> void:
	if unit_id not in _pending_sync:
		_pending_sync.append(unit_id)
	_cache.mark_dirty(unit_id)


## Update sync timer.
func update(delta: float) -> void:
	_sync_timer += delta

	if _sync_timer >= sync_interval:
		_sync_timer = 0.0
		_process_sync_queue()


## Process sync queue.
func _process_sync_queue() -> void:
	if _pending_sync.is_empty():
		return

	var dirty_states := _cache.get_dirty_states()
	if dirty_states.is_empty():
		_pending_sync.clear()
		return

	# Batch sync
	var batch: Array[HackingState] = []
	var batch_count := 0

	for state in dirty_states:
		batch.append(state)
		batch_count += 1

		if batch_count >= max_batch_size:
			batch_sync_requested.emit(batch)
			batch.clear()
			batch_count = 0

	# Send remaining
	if not batch.is_empty():
		batch_sync_requested.emit(batch)

	# Clear dirty flags
	_cache.clear_dirty_flags()
	_pending_sync.clear()

	sync_completed.emit(dirty_states.size())


## Create hack RPC data.
func create_hack_rpc(unit_id: int, hacker_faction: String, time_remaining: float) -> Dictionary:
	return {
		"type": "hack",
		"unit_id": unit_id,
		"hacker_faction": hacker_faction,
		"time_remaining": time_remaining,
		"timestamp": Time.get_ticks_msec()
	}


## Create unhack RPC data.
func create_unhack_rpc(unit_id: int) -> Dictionary:
	return {
		"type": "unhack",
		"unit_id": unit_id,
		"timestamp": Time.get_ticks_msec()
	}


## Create batch sync RPC data.
func create_batch_rpc(states: Array[HackingState]) -> Dictionary:
	var states_data: Array = []
	for state in states:
		states_data.append(state.to_dict())

	return {
		"type": "batch_sync",
		"states": states_data,
		"timestamp": Time.get_ticks_msec()
	}


## Process received RPC.
func process_rpc(data: Dictionary) -> void:
	var rpc_type: String = data.get("type", "")

	match rpc_type:
		"hack":
			_process_hack_rpc(data)
		"unhack":
			_process_unhack_rpc(data)
		"batch_sync":
			_process_batch_rpc(data)


## Process hack RPC.
func _process_hack_rpc(data: Dictionary) -> void:
	var unit_id: int = data.get("unit_id", -1)
	var hacker_faction: String = data.get("hacker_faction", "")

	if unit_id >= 0:
		remote_hack_received.emit(unit_id, hacker_faction)

		# Update cache
		var state := _cache.get_state(unit_id)
		if state != null:
			state.state = HackingState.State.HACKED
			state.hacker_faction = hacker_faction
			state.current_owner_faction = hacker_faction
			state.time_remaining = data.get("time_remaining", 30.0)


## Process unhack RPC.
func _process_unhack_rpc(data: Dictionary) -> void:
	var unit_id: int = data.get("unit_id", -1)

	if unit_id >= 0:
		remote_unhack_received.emit(unit_id)

		# Update cache
		var state := _cache.get_state(unit_id)
		if state != null:
			state.state = HackingState.State.OWNED
			state.hacker_faction = ""
			state.current_owner_faction = state.original_faction
			state.time_remaining = 0.0


## Process batch RPC.
func _process_batch_rpc(data: Dictionary) -> void:
	var states_data: Array = data.get("states", [])

	for state_data in states_data:
		var state := HackingState.from_dict(state_data)
		if state.is_valid:
			_cache.set_state(state.unit_id, state)
			_cache.mark_clean(state.unit_id)


## Force immediate sync.
func force_sync() -> void:
	_sync_timer = sync_interval
	_process_sync_queue()


## Serialize all state for save file.
func serialize_all() -> Dictionary:
	var states: Array = []
	for state in _cache.get_all_states():
		states.append(state.to_dict())

	return {
		"hacking_states": states,
		"save_time": Time.get_ticks_msec()
	}


## Deserialize from save file.
func deserialize_all(data: Dictionary) -> void:
	_cache.clear()

	for state_data in data.get("hacking_states", []):
		var state := HackingState.from_dict(state_data)
		if state.is_valid:
			_cache.set_state(state.unit_id, state)
			_cache.mark_clean(state.unit_id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"cache": _cache.get_stats(),
		"pending_sync": _pending_sync.size(),
		"sync_timer": _sync_timer,
		"sync_interval": sync_interval
	}
