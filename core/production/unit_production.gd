class_name UnitProduction
extends RefCounted
## UnitProduction tracks an individual unit being produced.
## Stores production progress, costs, and configuration.

## Production states
enum State {
	QUEUED = 0,       ## Waiting in queue
	IN_PROGRESS = 1,  ## Currently being produced
	AWAITING_RESOURCES = 2,  ## Waiting for resources
	COMPLETED = 3,    ## Production finished
	CANCELLED = 4     ## Production cancelled
}

## Unique production ID
var id: int = 0

## Unit type identifier
var unit_type: String = ""

## Faction producing this unit
var faction_id: String = ""

## Current state
var state: int = State.QUEUED

## Production progress (0.0 to 1.0)
var progress: float = 0.0

## Base production time (seconds)
var production_time: float = 10.0

## REE cost
var ree_cost: float = 100.0

## Power cost (per second during production)
var power_cost: float = 5.0

## Time spent waiting for resources
var resource_wait_time: float = 0.0

## Maximum wait time before requeue
var max_resource_wait: float = 5.0

## Factory producing this unit
var factory_id: int = -1

## Queue position
var queue_position: int = 0

## Custom metadata
var metadata: Dictionary = {}


func _init(p_unit_type: String = "", p_faction: String = "") -> void:
	unit_type = p_unit_type
	faction_id = p_faction


## Initialize from unit configuration.
func initialize_from_config(config: Dictionary) -> void:
	production_time = config.get("production_time", 10.0)
	ree_cost = config.get("ree_cost", 100.0)
	power_cost = config.get("power_cost", 5.0)


## Start production.
func start() -> void:
	if state == State.QUEUED or state == State.AWAITING_RESOURCES:
		state = State.IN_PROGRESS
		resource_wait_time = 0.0


## Update production progress.
func update(delta: float, speed_multiplier: float = 1.0) -> bool:
	if state != State.IN_PROGRESS:
		return false

	if production_time <= 0:
		progress = 1.0
	else:
		progress += (delta * speed_multiplier) / production_time

	if progress >= 1.0:
		progress = 1.0
		state = State.COMPLETED
		return true

	return false


## Set waiting for resources.
func set_awaiting_resources() -> void:
	if state == State.IN_PROGRESS or state == State.QUEUED:
		state = State.AWAITING_RESOURCES


## Update resource wait timer.
func update_resource_wait(delta: float) -> bool:
	if state != State.AWAITING_RESOURCES:
		return false

	resource_wait_time += delta

	# Return true if exceeded max wait time
	return resource_wait_time >= max_resource_wait


## Cancel production.
func cancel() -> void:
	state = State.CANCELLED


## Check if complete.
func is_complete() -> bool:
	return state == State.COMPLETED


## Check if in progress.
func is_in_progress() -> bool:
	return state == State.IN_PROGRESS


## Check if queued.
func is_queued() -> bool:
	return state == State.QUEUED


## Check if waiting for resources.
func is_awaiting_resources() -> bool:
	return state == State.AWAITING_RESOURCES


## Check if cancelled.
func is_cancelled() -> bool:
	return state == State.CANCELLED


## Get remaining time.
func get_remaining_time(speed_multiplier: float = 1.0) -> float:
	if speed_multiplier <= 0 or production_time <= 0:
		return 0.0
	return (1.0 - progress) * production_time / speed_multiplier


## Get state name.
func get_state_name() -> String:
	match state:
		State.QUEUED: return "Queued"
		State.IN_PROGRESS: return "In Progress"
		State.AWAITING_RESOURCES: return "Awaiting Resources"
		State.COMPLETED: return "Completed"
		State.CANCELLED: return "Cancelled"
	return "Unknown"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"unit_type": unit_type,
		"faction_id": faction_id,
		"state": state,
		"progress": progress,
		"production_time": production_time,
		"ree_cost": ree_cost,
		"power_cost": power_cost,
		"resource_wait_time": resource_wait_time,
		"max_resource_wait": max_resource_wait,
		"factory_id": factory_id,
		"queue_position": queue_position,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> UnitProduction:
	var production := UnitProduction.new(
		data.get("unit_type", ""),
		data.get("faction_id", "")
	)

	production.id = data.get("id", 0)
	production.state = data.get("state", State.QUEUED)
	production.progress = data.get("progress", 0.0)
	production.production_time = data.get("production_time", 10.0)
	production.ree_cost = data.get("ree_cost", 100.0)
	production.power_cost = data.get("power_cost", 5.0)
	production.resource_wait_time = data.get("resource_wait_time", 0.0)
	production.max_resource_wait = data.get("max_resource_wait", 5.0)
	production.factory_id = data.get("factory_id", -1)
	production.queue_position = data.get("queue_position", 0)
	production.metadata = data.get("metadata", {}).duplicate()

	return production


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"unit": unit_type,
		"faction": faction_id,
		"state": get_state_name(),
		"progress": "%.0f%%" % (progress * 100)
	}
