class_name HackingState
extends RefCounted
## HackingState provides serialization for hacking data.

## Unit states
enum State {
	OWNED = 0,
	HACKED = 1,
	MIND_CONTROLLED = 2
}

## Unit ID
var unit_id: int = -1

## State
var state: int = State.OWNED

## Original faction
var original_faction: String = ""

## Current owner faction
var current_owner_faction: String = ""

## Hacker faction (for HACKED/MIND_CONTROLLED)
var hacker_faction: String = ""

## Time remaining (for HACKED state)
var time_remaining: float = 0.0

## Hack start timestamp
var hack_start_time: int = 0

## Is valid
var is_valid: bool = true


func _init() -> void:
	pass


## Create from unit hacking component.
static func from_component(component: UnitHackingComponent) -> HackingState:
	var state := HackingState.new()
	var state_obj := component.get_state_object()

	state.unit_id = state_obj.unit_id
	state.state = state_obj.current_state
	state.original_faction = state_obj.original_faction
	state.current_owner_faction = state_obj.current_owner_faction
	state.hacker_faction = state_obj.controller_faction

	return state


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"state": state,
		"original_faction": original_faction,
		"current_owner_faction": current_owner_faction,
		"hacker_faction": hacker_faction,
		"time_remaining": time_remaining,
		"hack_start_time": hack_start_time,
		"is_valid": is_valid
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> HackingState:
	var hack_state := HackingState.new()
	hack_state.unit_id = data.get("unit_id", -1)
	hack_state.state = data.get("state", State.OWNED)
	hack_state.original_faction = data.get("original_faction", "")
	hack_state.current_owner_faction = data.get("current_owner_faction", "")
	hack_state.hacker_faction = data.get("hacker_faction", "")
	hack_state.time_remaining = data.get("time_remaining", 0.0)
	hack_state.hack_start_time = data.get("hack_start_time", 0)
	hack_state.is_valid = data.get("is_valid", true)
	return hack_state


## Serialize to compact bytes for network.
func to_bytes() -> PackedByteArray:
	var bytes := PackedByteArray()

	# Pack unit_id (4 bytes)
	bytes.resize(4)
	bytes.encode_s32(0, unit_id)

	# Pack state (1 byte)
	bytes.append(state)

	# Pack time_remaining (4 bytes float)
	var time_bytes := PackedByteArray()
	time_bytes.resize(4)
	time_bytes.encode_float(0, time_remaining)
	bytes.append_array(time_bytes)

	# Pack faction IDs (length-prefixed strings)
	var factions := [original_faction, current_owner_faction, hacker_faction]
	for faction in factions:
		var faction_bytes: PackedByteArray = faction.to_utf8_buffer()
		bytes.append(faction_bytes.size())  # 1 byte length (max 255)
		bytes.append_array(faction_bytes)

	return bytes


## Deserialize from bytes.
static func from_bytes(bytes: PackedByteArray) -> HackingState:
	var hack_state := HackingState.new()

	if bytes.size() < 9:  # Minimum size
		hack_state.is_valid = false
		return hack_state

	var offset := 0

	# Read unit_id
	hack_state.unit_id = bytes.decode_s32(offset)
	offset += 4

	# Read state
	hack_state.state = bytes[offset]
	offset += 1

	# Read time_remaining
	hack_state.time_remaining = bytes.decode_float(offset)
	offset += 4

	# Read factions
	for i in 3:
		if offset >= bytes.size():
			break

		var length: int = bytes[offset]
		offset += 1

		if offset + length > bytes.size():
			break

		var faction_bytes := bytes.slice(offset, offset + length)
		var faction := faction_bytes.get_string_from_utf8()
		offset += length

		match i:
			0: hack_state.original_faction = faction
			1: hack_state.current_owner_faction = faction
			2: hack_state.hacker_faction = faction

	return hack_state


## Get state name.
static func get_state_name(s: int) -> String:
	match s:
		State.OWNED: return "Owned"
		State.HACKED: return "Hacked"
		State.MIND_CONTROLLED: return "Mind Controlled"
	return "Unknown"


## Check if hacked.
func is_hacked() -> bool:
	return state == State.HACKED


## Check if mind controlled.
func is_mind_controlled() -> bool:
	return state == State.MIND_CONTROLLED


## Check if owned.
func is_owned() -> bool:
	return state == State.OWNED
