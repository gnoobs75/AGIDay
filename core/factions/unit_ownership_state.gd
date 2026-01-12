class_name UnitOwnershipState
extends RefCounted
## UnitOwnershipState defines ownership states and transition rules.

## Ownership states
enum State {
	OWNED = 0,          ## Unit belongs to original faction
	HACKED = 1,         ## Temporarily controlled by enemy (30s duration)
	MIND_CONTROLLED = 2 ## Permanently controlled by enemy
}

## State durations (seconds)
const HACKED_DURATION := 30.0
const MIND_CONTROL_DURATION := -1.0  ## Permanent

## Unhacking chance per hit from original faction
const UNHACK_CHANCE_PER_HIT := 0.10  ## 10%

## Valid state transitions
const VALID_TRANSITIONS := {
	State.OWNED: [State.HACKED, State.MIND_CONTROLLED],
	State.HACKED: [State.OWNED, State.MIND_CONTROLLED],
	State.MIND_CONTROLLED: [State.OWNED]  ## Only via special ability
}


## Get state name.
static func get_state_name(state: int) -> String:
	match state:
		State.OWNED: return "Owned"
		State.HACKED: return "Hacked"
		State.MIND_CONTROLLED: return "Mind Controlled"
	return "Unknown"


## Check if transition is valid.
static func is_valid_transition(from_state: int, to_state: int) -> bool:
	var valid: Array = VALID_TRANSITIONS.get(from_state, [])
	return to_state in valid


## Get duration for state.
static func get_state_duration(state: int) -> float:
	match state:
		State.HACKED: return HACKED_DURATION
		State.MIND_CONTROLLED: return MIND_CONTROL_DURATION
	return -1.0


## Check if state is temporary.
static func is_temporary_state(state: int) -> bool:
	return state == State.HACKED


## Check if state grants control to another faction.
static func is_controlled_state(state: int) -> bool:
	return state == State.HACKED or state == State.MIND_CONTROLLED


## Get all states.
static func get_all_states() -> Array[int]:
	return [State.OWNED, State.HACKED, State.MIND_CONTROLLED]
