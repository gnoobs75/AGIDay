class_name ProductionQueue
extends RefCounted
## ProductionQueue manages unit production queue for a factory.
## Handles continuous production with resource validation.

signal production_started(production: UnitProduction)
signal production_progress(production: UnitProduction, progress: float)
signal production_completed(production: UnitProduction)
signal production_cancelled(production: UnitProduction)
signal production_requeued(production: UnitProduction)
signal resources_insufficient(production: UnitProduction)

## Queue capacity
var max_queue_size: int = 10

## Production queue
var queue: Array[UnitProduction] = []

## Current production (first in queue being actively produced)
var current_production: UnitProduction = null

## Next production ID
var _next_id: int = 1

## Factory this queue belongs to
var factory_id: int = -1

## Faction this queue belongs to
var faction_id: String = ""


func _init() -> void:
	pass


## Add unit to production queue.
func queue_unit(unit_type: String, config: Dictionary = {}) -> UnitProduction:
	if queue.size() >= max_queue_size:
		return null

	var production := UnitProduction.new(unit_type, faction_id)
	production.id = _next_id
	_next_id += 1
	production.factory_id = factory_id
	production.queue_position = queue.size()

	# Initialize from config
	production.initialize_from_config(config)

	queue.append(production)

	return production


## Remove unit from queue.
func dequeue(production_id: int) -> bool:
	for i in queue.size():
		if queue[i].id == production_id:
			var production := queue[i]

			# Can't dequeue currently producing unit
			if production == current_production and production.is_in_progress():
				production.cancel()
				production_cancelled.emit(production)

			queue.remove_at(i)
			_update_queue_positions()
			return true

	return false


## Cancel specific production.
func cancel(production_id: int) -> bool:
	for production in queue:
		if production.id == production_id:
			production.cancel()
			production_cancelled.emit(production)
			return true
	return false


## Clear entire queue.
func clear() -> void:
	for production in queue:
		production.cancel()
		production_cancelled.emit(production)

	queue.clear()
	current_production = null


## Update queue positions after removal.
func _update_queue_positions() -> void:
	for i in queue.size():
		queue[i].queue_position = i


## Process production (called every frame).
func process(delta: float, speed_multiplier: float, has_resources: bool) -> UnitProduction:
	if queue.is_empty():
		current_production = null
		return null

	# Get first unit in queue
	var production := queue[0]
	current_production = production

	# Check if we should start or continue production
	match production.state:
		UnitProduction.State.QUEUED:
			if has_resources:
				production.start()
				production_started.emit(production)
			else:
				production.set_awaiting_resources()
				resources_insufficient.emit(production)

		UnitProduction.State.AWAITING_RESOURCES:
			if has_resources:
				production.start()
				production_started.emit(production)
			else:
				# Check if we should requeue
				if production.update_resource_wait(delta):
					_requeue_production(production)
					return null

		UnitProduction.State.IN_PROGRESS:
			if not has_resources:
				# Pause production if we lost resources
				production.set_awaiting_resources()
				resources_insufficient.emit(production)
			else:
				# Update progress
				var completed := production.update(delta, speed_multiplier)
				production_progress.emit(production, production.progress)

				if completed:
					production_completed.emit(production)
					queue.remove_at(0)
					_update_queue_positions()
					return production

	return null


## Move production to end of queue.
func _requeue_production(production: UnitProduction) -> void:
	var idx := queue.find(production)
	if idx >= 0 and idx < queue.size() - 1:
		queue.remove_at(idx)
		production.state = UnitProduction.State.QUEUED
		production.resource_wait_time = 0.0
		queue.append(production)
		_update_queue_positions()
		production_requeued.emit(production)


## Get queue size.
func get_queue_size() -> int:
	return queue.size()


## Get queue capacity remaining.
func get_remaining_capacity() -> int:
	return max_queue_size - queue.size()


## Check if queue is full.
func is_full() -> bool:
	return queue.size() >= max_queue_size


## Check if queue is empty.
func is_empty() -> bool:
	return queue.is_empty()


## Get production by ID.
func get_production(id: int) -> UnitProduction:
	for production in queue:
		if production.id == id:
			return production
	return null


## Get production at position.
func get_at(position: int) -> UnitProduction:
	if position >= 0 and position < queue.size():
		return queue[position]
	return null


## Get all queued productions.
func get_all() -> Array[UnitProduction]:
	return queue.duplicate()


## Get total REE cost of queue.
func get_total_ree_cost() -> float:
	var total := 0.0
	for production in queue:
		if not production.is_complete():
			total += production.ree_cost * (1.0 - production.progress)
	return total


## Get estimated completion time.
func get_estimated_time(speed_multiplier: float = 1.0) -> float:
	var total := 0.0
	for production in queue:
		if not production.is_complete():
			total += production.get_remaining_time(speed_multiplier)
	return total


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var queue_data: Array = []
	for production in queue:
		queue_data.append(production.to_dict())

	return {
		"max_queue_size": max_queue_size,
		"queue": queue_data,
		"next_id": _next_id,
		"factory_id": factory_id,
		"faction_id": faction_id
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> ProductionQueue:
	var pq := ProductionQueue.new()
	pq.max_queue_size = data.get("max_queue_size", 10)
	pq._next_id = data.get("next_id", 1)
	pq.factory_id = data.get("factory_id", -1)
	pq.faction_id = data.get("faction_id", "")

	pq.queue.clear()
	for prod_data in data.get("queue", []):
		var production := UnitProduction.from_dict(prod_data)
		pq.queue.append(production)

	if not pq.queue.is_empty():
		pq.current_production = pq.queue[0]

	return pq


## Get summary for debugging.
func get_summary() -> Dictionary:
	var current_unit := ""
	var current_progress := 0.0

	if current_production != null:
		current_unit = current_production.unit_type
		current_progress = current_production.progress

	return {
		"size": "%d/%d" % [queue.size(), max_queue_size],
		"current": current_unit if not current_unit.is_empty() else "none",
		"progress": "%.0f%%" % (current_progress * 100),
		"factory": factory_id
	}
