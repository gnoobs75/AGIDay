class_name SystemManager
extends RefCounted
## SystemManager handles system registration, ordering, and execution.
## Executes systems in priority order each frame.

## Reference to the EntityManager
var entity_manager: EntityManager

## Registered systems sorted by priority
var _systems: Array[System] = []

## Systems indexed by name for quick lookup
var _systems_by_name: Dictionary = {}

## Whether systems need re-sorting after priority change
var _needs_sort: bool = false

## Performance tracking
var last_total_time_usec: int = 0


func _init(manager: EntityManager = null) -> void:
	entity_manager = manager


## Set the entity manager reference.
func set_entity_manager(manager: EntityManager) -> void:
	entity_manager = manager
	for system in _systems:
		system.set_entity_manager(manager)


## Register a system.
## Systems are sorted by priority (lower = earlier execution).
func register_system(system: System) -> void:
	var name := system.get_system_name()

	if _systems_by_name.has(name):
		push_warning("SystemManager: System '%s' already registered, replacing" % name)
		unregister_system(name)

	system.set_entity_manager(entity_manager)
	_systems.append(system)
	_systems_by_name[name] = system
	_needs_sort = true

	system.initialize()


## Unregister a system by name.
func unregister_system(name: String) -> bool:
	if not _systems_by_name.has(name):
		return false

	var system: System = _systems_by_name[name]
	system.cleanup()

	_systems.erase(system)
	_systems_by_name.erase(name)

	return true


## Get a system by name.
func get_system(name: String) -> System:
	return _systems_by_name.get(name)


## Check if a system is registered.
func has_system(name: String) -> bool:
	return _systems_by_name.has(name)


## Sort systems by priority.
func _sort_systems() -> void:
	_systems.sort_custom(func(a: System, b: System) -> bool:
		return a.priority < b.priority
	)
	_needs_sort = false


## Process all enabled systems.
## Called every frame.
func process(delta: float) -> void:
	if _needs_sort:
		_sort_systems()

	var start_time := Time.get_ticks_usec()

	for system in _systems:
		if system.is_enabled:
			system.process(delta)

	last_total_time_usec = Time.get_ticks_usec() - start_time


## Physics process all enabled systems.
## Called every physics frame.
func physics_process(delta: float) -> void:
	if _needs_sort:
		_sort_systems()

	var start_time := Time.get_ticks_usec()

	for system in _systems:
		if system.is_enabled:
			system.physics_process(delta)

	last_total_time_usec = Time.get_ticks_usec() - start_time


## Enable a system by name.
func enable_system(name: String) -> bool:
	var system := get_system(name)
	if system:
		system.is_enabled = true
		return true
	return false


## Disable a system by name.
func disable_system(name: String) -> bool:
	var system := get_system(name)
	if system:
		system.is_enabled = false
		return true
	return false


## Set system priority and trigger re-sort.
func set_system_priority(name: String, priority: int) -> bool:
	var system := get_system(name)
	if system:
		system.priority = priority
		_needs_sort = true
		return true
	return false


## Get all system names in execution order.
func get_system_names() -> Array[String]:
	if _needs_sort:
		_sort_systems()

	var names: Array[String] = []
	for system in _systems:
		names.append(system.get_system_name())
	return names


## Get all systems.
func get_all_systems() -> Array[System]:
	if _needs_sort:
		_sort_systems()
	return _systems.duplicate()


## Get system count.
func get_system_count() -> int:
	return _systems.size()


## Get performance statistics for all systems.
func get_stats() -> Dictionary:
	var system_stats: Array = []
	for system in _systems:
		system_stats.append(system.get_stats())

	return {
		"total_systems": _systems.size(),
		"last_total_time_usec": last_total_time_usec,
		"systems": system_stats
	}


## Cleanup all systems.
func cleanup() -> void:
	for system in _systems:
		system.cleanup()

	_systems.clear()
	_systems_by_name.clear()
