class_name VisibilityState
extends RefCounted
## VisibilityState defines fog of war visibility states and transitions.

## Visibility states
enum State {
	UNEXPLORED = 0,  ## Never seen
	EXPLORED = 1,    ## Seen before but not currently visible
	VISIBLE = 2      ## Currently within unit vision range
}

## State names for debugging
const STATE_NAMES := {
	State.UNEXPLORED: "unexplored",
	State.EXPLORED: "explored",
	State.VISIBLE: "visible"
}

## Valid state transitions
const VALID_TRANSITIONS := {
	State.UNEXPLORED: [State.EXPLORED, State.VISIBLE],
	State.EXPLORED: [State.VISIBLE],
	State.VISIBLE: [State.EXPLORED]
}


## Check if transition is valid.
static func is_valid_transition(from_state: int, to_state: int) -> bool:
	if from_state == to_state:
		return true
	if not VALID_TRANSITIONS.has(from_state):
		return false
	return to_state in VALID_TRANSITIONS[from_state]


## Get state name.
static func get_state_name(state: int) -> String:
	return STATE_NAMES.get(state, "unknown")


## Check if state is visible.
static func is_visible(state: int) -> bool:
	return state == State.VISIBLE


## Check if state has been explored.
static func is_explored(state: int) -> bool:
	return state >= State.EXPLORED
