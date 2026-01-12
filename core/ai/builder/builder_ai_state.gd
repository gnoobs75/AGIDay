class_name BuilderAIState
extends RefCounted
## BuilderAIState defines builder AI states and transitions.

## Builder states
enum State {
	IDLE,
	SCANNING,
	NAVIGATING,
	REPAIRING,
	EVADING,
	RETREATING
}

## State names for debugging
const STATE_NAMES := {
	State.IDLE: "idle",
	State.SCANNING: "scanning",
	State.NAVIGATING: "navigating",
	State.REPAIRING: "repairing",
	State.EVADING: "evading",
	State.RETREATING: "retreating"
}

## Valid transitions
const VALID_TRANSITIONS := {
	State.IDLE: [State.SCANNING, State.EVADING, State.RETREATING],
	State.SCANNING: [State.IDLE, State.NAVIGATING, State.EVADING],
	State.NAVIGATING: [State.REPAIRING, State.SCANNING, State.EVADING, State.IDLE],
	State.REPAIRING: [State.SCANNING, State.IDLE, State.EVADING, State.NAVIGATING],
	State.EVADING: [State.SCANNING, State.IDLE, State.RETREATING],
	State.RETREATING: [State.IDLE, State.SCANNING]
}


## Check if transition is valid.
static func is_valid_transition(from_state: int, to_state: int) -> bool:
	if not VALID_TRANSITIONS.has(from_state):
		return false
	return to_state in VALID_TRANSITIONS[from_state]


## Get state name.
static func get_state_name(state: int) -> String:
	return STATE_NAMES.get(state, "unknown")
