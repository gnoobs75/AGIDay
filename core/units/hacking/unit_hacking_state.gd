class_name UnitHackingState
extends RefCounted
## UnitHackingState manages hacking state for a single unit.
## Integrates with Unit class for behavior and visual switching.

signal state_entered(state: int)
signal state_exited(state: int)
signal unit_hacked(unit_id: int, hacker_faction: String)
signal unit_unhacked(unit_id: int)
signal unit_mind_controlled(unit_id: int, controller_faction: String)
signal behavior_switch_requested(behavior_type: String)
signal visual_switch_requested(faction_id: String)

## Unit states
enum UnitState {
	OWNED = 0,          ## Controlled by original faction
	HACKED = 1,         ## Temporarily controlled by enemy
	MIND_CONTROLLED = 2 ## Permanently controlled by enemy
}

## Unit ID
var unit_id: int = -1

## Current state
var current_state: int = UnitState.OWNED

## Previous state (for transitions)
var previous_state: int = UnitState.OWNED

## Original faction (immutable)
var original_faction: String = ""

## Current controlling faction
var current_owner_faction: String = ""

## Faction that initiated hack/mind control
var controller_faction: String = ""

## State entry timestamp (for duration tracking)
var state_entry_time: int = 0

## Is transition in progress
var _transitioning: bool = false


func _init(id: int = -1, faction: String = "") -> void:
	unit_id = id
	original_faction = faction
	current_owner_faction = faction
	state_entry_time = Time.get_ticks_msec()


## Transition to new state.
func transition_state(new_state: int, new_controller: String = "") -> bool:
	# Prevent concurrent transitions
	if _transitioning:
		return false

	# Validate transition
	if not _is_valid_transition(current_state, new_state):
		return false

	_transitioning = true

	# Exit current state
	_on_state_exit(current_state)
	state_exited.emit(current_state)

	# Update state
	previous_state = current_state
	current_state = new_state
	state_entry_time = Time.get_ticks_msec()

	# Handle controller
	match new_state:
		UnitState.OWNED:
			current_owner_faction = original_faction
			controller_faction = ""
		UnitState.HACKED, UnitState.MIND_CONTROLLED:
			controller_faction = new_controller
			current_owner_faction = new_controller

	# Enter new state
	_on_state_enter(new_state)
	state_entered.emit(new_state)

	# Emit specific signals
	_emit_transition_signal(new_state, new_controller)

	_transitioning = false
	return true


## Check if transition is valid.
func _is_valid_transition(from_state: int, to_state: int) -> bool:
	# Same state is not valid
	if from_state == to_state:
		return false

	match from_state:
		UnitState.OWNED:
			# Can transition to HACKED or MIND_CONTROLLED
			return to_state in [UnitState.HACKED, UnitState.MIND_CONTROLLED]
		UnitState.HACKED:
			# Can return to OWNED or escalate to MIND_CONTROLLED
			return to_state in [UnitState.OWNED, UnitState.MIND_CONTROLLED]
		UnitState.MIND_CONTROLLED:
			# Can only return to OWNED (via special ability)
			return to_state == UnitState.OWNED

	return false


## Called when entering a state.
func _on_state_enter(state: int) -> void:
	match state:
		UnitState.OWNED:
			_on_owned_state()
		UnitState.HACKED:
			_on_hacked_state()
		UnitState.MIND_CONTROLLED:
			_on_mind_controlled_state()


## Called when exiting a state.
func _on_state_exit(state: int) -> void:
	# Cleanup for state-specific resources
	pass


## Emit transition-specific signal.
func _emit_transition_signal(new_state: int, controller: String) -> void:
	match new_state:
		UnitState.OWNED:
			unit_unhacked.emit(unit_id)
		UnitState.HACKED:
			unit_hacked.emit(unit_id, controller)
		UnitState.MIND_CONTROLLED:
			unit_mind_controlled.emit(unit_id, controller)


## Handle OWNED state entry.
func _on_owned_state() -> void:
	# Restore original AI behavior
	behavior_switch_requested.emit("original")

	# Restore original visual appearance
	visual_switch_requested.emit(original_faction)


## Handle HACKED state entry.
func _on_hacked_state() -> void:
	# Switch to hacker's AI behavior
	behavior_switch_requested.emit("hacker")

	# Switch to hacker's visual appearance
	visual_switch_requested.emit(controller_faction)


## Handle MIND_CONTROLLED state entry.
func _on_mind_controlled_state() -> void:
	# Switch to controller's AI behavior
	behavior_switch_requested.emit("controller")

	# Switch to controller's visual appearance with special indicator
	visual_switch_requested.emit(controller_faction)


## Check if unit is owned by original faction.
func is_owned() -> bool:
	return current_state == UnitState.OWNED


## Check if unit is hacked.
func is_hacked() -> bool:
	return current_state == UnitState.HACKED


## Check if unit is mind controlled.
func is_mind_controlled() -> bool:
	return current_state == UnitState.MIND_CONTROLLED


## Check if unit is controlled by enemy.
func is_enemy_controlled() -> bool:
	return current_state != UnitState.OWNED


## Get time in current state (milliseconds).
func get_time_in_state() -> int:
	return Time.get_ticks_msec() - state_entry_time


## Get state name.
static func get_state_name(state: int) -> String:
	match state:
		UnitState.OWNED: return "Owned"
		UnitState.HACKED: return "Hacked"
		UnitState.MIND_CONTROLLED: return "Mind Controlled"
	return "Unknown"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"current_state": current_state,
		"previous_state": previous_state,
		"original_faction": original_faction,
		"current_owner_faction": current_owner_faction,
		"controller_faction": controller_faction,
		"state_entry_time": state_entry_time
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> UnitHackingState:
	var state := UnitHackingState.new(
		data.get("unit_id", -1),
		data.get("original_faction", "")
	)
	state.current_state = data.get("current_state", UnitState.OWNED)
	state.previous_state = data.get("previous_state", UnitState.OWNED)
	state.current_owner_faction = data.get("current_owner_faction", state.original_faction)
	state.controller_faction = data.get("controller_faction", "")
	state.state_entry_time = data.get("state_entry_time", Time.get_ticks_msec())
	return state


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"unit_id": unit_id,
		"state": get_state_name(current_state),
		"original_faction": original_faction,
		"current_owner": current_owner_faction,
		"time_in_state_ms": get_time_in_state()
	}
