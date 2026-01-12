class_name System
extends RefCounted
## Base System class for the ECS framework.
## Systems are stateless processors that iterate over entities with specific components.
## State should live in components, not systems.

## Reference to the EntityManager for querying entities
var entity_manager: EntityManager

## Component types this system operates on (filter for queries)
var required_components: Array[String] = []

## Priority for system execution order (lower = earlier)
var priority: int = 0

## Whether this system is enabled
var is_enabled: bool = true

## Performance tracking
var last_process_time_usec: int = 0
var last_entity_count: int = 0

## Time budget in microseconds (0 = unlimited)
var time_budget_usec: int = 0


func _init(manager: EntityManager = null) -> void:
	entity_manager = manager


## Set the entity manager reference.
func set_entity_manager(manager: EntityManager) -> void:
	entity_manager = manager


## Get the system name for debugging and logging.
func get_system_name() -> String:
	return "System"


## Called once when the system is registered.
## Override to perform initialization.
func initialize() -> void:
	pass


## Called every frame to process entities.
## Override to implement system logic.
func process(delta: float) -> void:
	if not is_enabled or entity_manager == null:
		return

	var start_time := Time.get_ticks_usec()
	var entities := query_entities()
	last_entity_count = entities.size()

	for entity in entities:
		if time_budget_usec > 0:
			var elapsed := Time.get_ticks_usec() - start_time
			if elapsed >= time_budget_usec:
				push_warning("%s exceeded time budget (%d/%d usec)" % [
					get_system_name(), elapsed, time_budget_usec
				])
				break

		process_entity(entity, delta)

	last_process_time_usec = Time.get_ticks_usec() - start_time


## Called for each entity that matches the required components.
## Override to implement per-entity logic.
func process_entity(entity: Entity, delta: float) -> void:
	pass


## Called at fixed intervals (physics process).
## Override to implement fixed-timestep logic.
func physics_process(delta: float) -> void:
	if not is_enabled or entity_manager == null:
		return

	var start_time := Time.get_ticks_usec()
	var entities := query_entities()
	last_entity_count = entities.size()

	for entity in entities:
		if time_budget_usec > 0:
			var elapsed := Time.get_ticks_usec() - start_time
			if elapsed >= time_budget_usec:
				break

		physics_process_entity(entity, delta)

	last_process_time_usec = Time.get_ticks_usec() - start_time


## Called for each entity during physics process.
## Override to implement per-entity physics logic.
func physics_process_entity(entity: Entity, delta: float) -> void:
	pass


## Query entities that match required components.
func query_entities() -> Array[Entity]:
	if entity_manager == null:
		return []
	return entity_manager.query_entities(required_components)


## Query entities with additional component filters.
func query_entities_with(additional_components: Array[String]) -> Array[Entity]:
	if entity_manager == null:
		return []

	var all_components: Array[String] = required_components.duplicate()
	for comp in additional_components:
		if comp not in all_components:
			all_components.append(comp)

	return entity_manager.query_entities(all_components)


## Get a specific component from an entity.
## Convenience method for common pattern.
func get_component(entity: Entity, type_name: String) -> Component:
	return entity.get_component(type_name)


## Called when the system is being destroyed.
## Override to perform cleanup.
func cleanup() -> void:
	pass


## Enable or disable the system.
func set_enabled(enabled: bool) -> void:
	is_enabled = enabled


## Get performance statistics.
func get_stats() -> Dictionary:
	return {
		"name": get_system_name(),
		"enabled": is_enabled,
		"priority": priority,
		"last_process_time_usec": last_process_time_usec,
		"last_entity_count": last_entity_count,
		"time_budget_usec": time_budget_usec
	}
