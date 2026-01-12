class_name Snapshot
extends RefCounted
## Snapshot captures a complete game state at a point in time.
## Used for save/load and deterministic replay systems.

## Snapshot trigger types
enum TriggerType {
	MANUAL = 0,         # User-initiated save
	WAVE_COMPLETE = 1,  # End of wave
	TIMED = 2,          # Periodic snapshot (every 5 minutes)
	CHECKPOINT = 3,     # Game checkpoint
	AUTOSAVE = 4        # Autosave system
}

## Unique snapshot ID (incrementing)
var snapshot_id: int = 0

## Frame number when snapshot was taken (for replay)
var frame_number: int = 0

## Wave number at snapshot time
var wave_number: int = 0

## Game time in seconds when snapshot was taken
var game_time: float = 0.0

## Real timestamp when snapshot was created
var timestamp: int = 0

## What triggered this snapshot
var trigger: TriggerType = TriggerType.MANUAL

## Complete entity data (entity_id -> component data)
var entities: Dictionary = {}

## Resource data (resource_type -> amount)
var resources: Dictionary = {}

## District control data (district_id -> faction_id)
var district_control: Dictionary = {}

## System states (system_name -> state data)
var system_states: Dictionary = {}

## World state (global game state)
var world_state: Dictionary = {}

## Custom metadata
var metadata: Dictionary = {}


func _init() -> void:
	timestamp = int(Time.get_unix_time_from_system())


## Create a snapshot from current game state
static func create_from_state(
	game_state: Dictionary,
	p_frame_number: int,
	p_wave_number: int,
	p_game_time: float,
	p_trigger: TriggerType = TriggerType.MANUAL
) -> Snapshot:
	var snapshot := Snapshot.new()
	snapshot.frame_number = p_frame_number
	snapshot.wave_number = p_wave_number
	snapshot.game_time = p_game_time
	snapshot.trigger = p_trigger

	# Deep copy game state
	snapshot.entities = game_state.get("entities", {}).duplicate(true)
	snapshot.resources = game_state.get("resources", {}).duplicate(true)
	snapshot.district_control = game_state.get("district_control", {}).duplicate(true)
	snapshot.system_states = game_state.get("system_states", {}).duplicate(true)
	snapshot.world_state = game_state.get("world_state", {}).duplicate(true)
	snapshot.metadata = game_state.get("metadata", {}).duplicate(true)

	return snapshot


## Convert snapshot to dictionary for serialization
func to_dict() -> Dictionary:
	return {
		"snapshot_id": snapshot_id,
		"frame_number": frame_number,
		"wave_number": wave_number,
		"game_time": game_time,
		"timestamp": timestamp,
		"trigger": trigger,
		"entities": entities,
		"resources": resources,
		"district_control": district_control,
		"system_states": system_states,
		"world_state": world_state,
		"metadata": metadata
	}


## Restore snapshot from dictionary
static func from_dict(data: Dictionary) -> Snapshot:
	var snapshot := Snapshot.new()
	snapshot.snapshot_id = data.get("snapshot_id", 0)
	snapshot.frame_number = data.get("frame_number", 0)
	snapshot.wave_number = data.get("wave_number", 0)
	snapshot.game_time = data.get("game_time", 0.0)
	snapshot.timestamp = data.get("timestamp", 0)
	snapshot.trigger = data.get("trigger", TriggerType.MANUAL)
	snapshot.entities = data.get("entities", {}).duplicate(true)
	snapshot.resources = data.get("resources", {}).duplicate(true)
	snapshot.district_control = data.get("district_control", {}).duplicate(true)
	snapshot.system_states = data.get("system_states", {}).duplicate(true)
	snapshot.world_state = data.get("world_state", {}).duplicate(true)
	snapshot.metadata = data.get("metadata", {}).duplicate(true)
	return snapshot


## Get entity count in this snapshot
func get_entity_count() -> int:
	return entities.size()


## Get approximate memory size in bytes
func get_memory_size() -> int:
	var size := 0

	# Estimate entity data size
	for entity_id in entities:
		size += entity_id.length() if entity_id is String else 8
		size += _estimate_dict_size(entities[entity_id])

	# Estimate other data
	size += _estimate_dict_size(resources)
	size += _estimate_dict_size(district_control)
	size += _estimate_dict_size(system_states)
	size += _estimate_dict_size(world_state)
	size += _estimate_dict_size(metadata)

	return size


func _estimate_dict_size(dict: Dictionary) -> int:
	if dict.is_empty():
		return 0

	# Rough estimate: serialize and measure
	var bytes := var_to_bytes(dict)
	return bytes.size()


## Clone this snapshot
func duplicate() -> Snapshot:
	return Snapshot.from_dict(to_dict())


## Get formatted timestamp string
func get_formatted_timestamp() -> String:
	return SaveFormat.format_timestamp(timestamp)


## Get trigger type as string
func get_trigger_string() -> String:
	match trigger:
		TriggerType.MANUAL: return "Manual"
		TriggerType.WAVE_COMPLETE: return "Wave Complete"
		TriggerType.TIMED: return "Timed"
		TriggerType.CHECKPOINT: return "Checkpoint"
		TriggerType.AUTOSAVE: return "Autosave"
		_: return "Unknown"
