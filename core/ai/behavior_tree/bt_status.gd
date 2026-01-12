class_name BTStatus
extends RefCounted
## BTStatus defines return values for behavior tree node execution.

## Behavior tree execution status
enum Status {
	SUCCESS = 0,   ## Node completed successfully
	FAILURE = 1,   ## Node failed
	RUNNING = 2    ## Node is still executing
}

## Convert status to string for debugging.
static func to_string_status(status: int) -> String:
	match status:
		Status.SUCCESS:
			return "SUCCESS"
		Status.FAILURE:
			return "FAILURE"
		Status.RUNNING:
			return "RUNNING"
		_:
			return "UNKNOWN"


## Check if status is terminal (SUCCESS or FAILURE).
static func is_terminal(status: int) -> bool:
	return status == Status.SUCCESS or status == Status.FAILURE
