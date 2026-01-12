class_name UnitStateMachine
extends RefCounted
## UnitStateMachine manages ownership state for a single unit.
## Handles state transitions, timers, and unhacking mechanics.

signal state_changed(old_state: int, new_state: int)
signal owner_changed(old_faction: String, new_faction: String)
signal hacking_expired(unit_id: int)
signal unhack_attempted(unit_id: int, success: bool)
signal visual_update_requested(faction_id: String)
signal ai_behavior_switch_requested(behavior_type: String)

## Unit ID
var unit_id: int = -1

## Current ownership state
var current_state: int = UnitOwnershipState.State.OWNED

## Original faction (never changes)
var original_faction: String = ""

## Current controlling faction
var owner_faction: String = ""

## Remaining duration for temporary states
var state_duration_remaining: float = -1.0

## Faction that hacked this unit
var hacker_faction: String = ""


func _init(id: int = -1, faction: String = "") -> void:
	unit_id = id
	original_faction = faction
	owner_faction = faction


## Process timer for temporary states.
func process(delta: float) -> void:
	if not UnitOwnershipState.is_temporary_state(current_state):
		return

	if state_duration_remaining <= 0:
		return

	state_duration_remaining -= delta

	if state_duration_remaining <= 0:
		_expire_temporary_state()


## Transition to new state.
func transition_to(
	new_state: int,
	new_owner: String = "",
	force: bool = false
) -> bool:
	# Validate transition
	if not force and not UnitOwnershipState.is_valid_transition(current_state, new_state):
		return false

	var old_state := current_state
	var old_owner := owner_faction

	current_state = new_state

	# Handle state-specific logic
	match new_state:
		UnitOwnershipState.State.OWNED:
			owner_faction = original_faction
			hacker_faction = ""
			state_duration_remaining = -1.0
			ai_behavior_switch_requested.emit("original")

		UnitOwnershipState.State.HACKED:
			owner_faction = new_owner
			hacker_faction = new_owner
			state_duration_remaining = UnitOwnershipState.HACKED_DURATION
			ai_behavior_switch_requested.emit("hacker")

		UnitOwnershipState.State.MIND_CONTROLLED:
			owner_faction = new_owner
			hacker_faction = new_owner
			state_duration_remaining = -1.0
			ai_behavior_switch_requested.emit("hacker")

	# Emit signals
	state_changed.emit(old_state, new_state)

	if old_owner != owner_faction:
		owner_changed.emit(old_owner, owner_faction)
		visual_update_requested.emit(owner_faction)

	return true


## Attempt to hack unit.
func attempt_hack(hacker: String) -> bool:
	if current_state != UnitOwnershipState.State.OWNED:
		return false

	return transition_to(UnitOwnershipState.State.HACKED, hacker)


## Attempt to mind control unit.
func attempt_mind_control(controller: String) -> bool:
	if current_state == UnitOwnershipState.State.MIND_CONTROLLED:
		return false

	return transition_to(UnitOwnershipState.State.MIND_CONTROLLED, controller)


## Handle damage from faction (for unhacking mechanic).
func on_damage_received(attacker_faction: String) -> bool:
	# Only hacked units can be unhacked
	if current_state != UnitOwnershipState.State.HACKED:
		return false

	# Only original faction can unhack
	if attacker_faction != original_faction:
		return false

	# Roll for unhacking
	var roll := randf()
	var success := roll < UnitOwnershipState.UNHACK_CHANCE_PER_HIT

	unhack_attempted.emit(unit_id, success)

	if success:
		transition_to(UnitOwnershipState.State.OWNED)
		return true

	return false


## Force return to original owner.
func force_return_to_owner() -> void:
	transition_to(UnitOwnershipState.State.OWNED, "", true)


## Handle temporary state expiration.
func _expire_temporary_state() -> void:
	if current_state == UnitOwnershipState.State.HACKED:
		hacking_expired.emit(unit_id)
		transition_to(UnitOwnershipState.State.OWNED)


## Check if unit is controlled by another faction.
func is_controlled() -> bool:
	return UnitOwnershipState.is_controlled_state(current_state)


## Check if unit is hacked.
func is_hacked() -> bool:
	return current_state == UnitOwnershipState.State.HACKED


## Check if unit is mind controlled.
func is_mind_controlled() -> bool:
	return current_state == UnitOwnershipState.State.MIND_CONTROLLED


## Get remaining hack duration.
func get_hack_time_remaining() -> float:
	if current_state != UnitOwnershipState.State.HACKED:
		return 0.0
	return maxf(0.0, state_duration_remaining)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"current_state": current_state,
		"original_faction": original_faction,
		"owner_faction": owner_faction,
		"state_duration_remaining": state_duration_remaining,
		"hacker_faction": hacker_faction
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> UnitStateMachine:
	var machine := UnitStateMachine.new(
		data.get("unit_id", -1),
		data.get("original_faction", "")
	)
	machine.current_state = data.get("current_state", UnitOwnershipState.State.OWNED)
	machine.owner_faction = data.get("owner_faction", machine.original_faction)
	machine.state_duration_remaining = data.get("state_duration_remaining", -1.0)
	machine.hacker_faction = data.get("hacker_faction", "")
	return machine


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"unit_id": unit_id,
		"state": UnitOwnershipState.get_state_name(current_state),
		"original_faction": original_faction,
		"owner_faction": owner_faction,
		"hack_remaining": "%.1fs" % get_hack_time_remaining() if is_hacked() else "N/A"
	}
