extends Node
## ECSWorld is the main coordinator for the Entity Component System.
## Set as an autoload to provide global access to ECS functionality.
## Handles entity management, component registration, system execution,
## entity validation, and reference tracking.

## The entity manager instance
var entity_manager: EntityManager

## The component registry for serialization
var component_registry: ComponentRegistry

## The system manager for processing
var system_manager: SystemManager

## The entity validator for data validation
var entity_validator: EntityValidator

## The reference tracker for dangling reference handling
var reference_tracker: ReferenceTracker

## Whether the ECS is initialized
var is_initialized: bool = false

## Performance statistics
var stats: Dictionary = {}


func _ready() -> void:
	initialize()


## Initialize the ECS world with default configuration.
func initialize(pool_size: int = 10000, seed_value: int = 0) -> void:
	if is_initialized:
		push_warning("ECSWorld: Already initialized")
		return

	# Use the autoload singletons (they're already initialized)
	entity_manager = EntityManager
	component_registry = ComponentRegistry

	# Create the system manager and other components
	system_manager = SystemManager.new(entity_manager)
	entity_validator = EntityValidator.new(entity_manager)
	reference_tracker = ReferenceTracker.new(entity_manager)

	_register_core_components()

	is_initialized = true
	print("ECSWorld: Initialized with pool size %d" % pool_size)


## Register core component types.
## Override or extend to register game-specific components.
func _register_core_components() -> void:
	# Base component is registered by default
	component_registry.register("Component", func() -> Component:
		return Component.new()
	)


## Called every frame to process systems.
func _process(delta: float) -> void:
	if not is_initialized:
		return

	system_manager.process(delta)
	_update_stats()


## Called every physics frame to process systems.
func _physics_process(delta: float) -> void:
	if not is_initialized:
		return

	system_manager.physics_process(delta)


## Update performance statistics.
func _update_stats() -> void:
	stats = {
		"entity_count": entity_manager.get_entity_count(),
		"pool_size": entity_manager.get_total_pool_size(),
		"system_count": system_manager.get_system_count(),
		"last_query_time_usec": entity_manager.get_last_query_time_usec(),
		"last_system_time_usec": system_manager.last_total_time_usec
	}


# =============================================================================
# Entity Management API
# =============================================================================

## Create a new entity of the specified type.
func create_entity(type_name: String = "Entity") -> Entity:
	return entity_manager.create_entity(type_name)


## Create an entity with a specific EntityTypes.Type.
func create_typed_entity(type: EntityTypes.Type) -> Entity:
	var type_name := EntityTypes.get_type_name(type)
	return entity_manager.create_entity(type_name)


## Destroy an entity by ID.
func destroy_entity(entity_id: int) -> bool:
	reference_tracker.unregister_all_from_source(entity_id)
	return entity_manager.destroy_entity(entity_id)


## Get an entity by ID.
func get_entity(entity_id: int) -> Entity:
	return entity_manager.get_entity(entity_id)


## Check if an entity exists.
func has_entity(entity_id: int) -> bool:
	return entity_manager.has_entity(entity_id)


## Query entities with specific components.
func query(component_types: Array[String]) -> Array[Entity]:
	return entity_manager.query_entities(component_types)


## Query entities by entity type.
func query_by_type(entity_type: String) -> Array[Entity]:
	return entity_manager.query_by_type(entity_type)


# =============================================================================
# Component API
# =============================================================================

## Add a component to an entity.
func add_component(entity_id: int, component: Component) -> bool:
	return entity_manager.add_component(entity_id, component)


## Remove a component from an entity.
func remove_component(entity_id: int, component_type: String) -> Component:
	return entity_manager.remove_component(entity_id, component_type)


## Register a component type for serialization.
func register_component(type_name: String, factory: Callable, schema: ComponentSchema = null) -> void:
	component_registry.register(type_name, factory, schema)


## Register a component script.
func register_component_script(type_name: String, script: GDScript, schema: ComponentSchema = null) -> void:
	component_registry.register_script(type_name, script, schema)


## Register a component schema.
func register_schema(type_name: String, schema: ComponentSchema) -> void:
	component_registry.register_schema(type_name, schema)


# =============================================================================
# System API
# =============================================================================

## Register a system for processing.
func register_system(system: System) -> void:
	system_manager.register_system(system)


## Unregister a system.
func unregister_system(name: String) -> bool:
	return system_manager.unregister_system(name)


## Get a system by name.
func get_system(name: String) -> System:
	return system_manager.get_system(name)


## Enable a system.
func enable_system(name: String) -> bool:
	return system_manager.enable_system(name)


## Disable a system.
func disable_system(name: String) -> bool:
	return system_manager.disable_system(name)


# =============================================================================
# Validation API
# =============================================================================

## Validate an entity.
func validate_entity(entity: Entity) -> bool:
	return entity_validator.validate_entity(entity)


## Validate entity data before deserialization.
func validate_entity_data(data: Dictionary) -> bool:
	return entity_validator.validate_entity_data(data)


## Validate component data against its schema.
func validate_component_data(type_name: String, data: Dictionary) -> bool:
	return component_registry.validate_data(type_name, data)


## Get validation errors.
func get_validation_errors() -> Array[String]:
	return entity_validator.get_errors()


# =============================================================================
# Reference Tracking API
# =============================================================================

## Register a reference between entities.
func register_reference(source_id: int, target_id: int, field_path: String) -> void:
	reference_tracker.register_reference(source_id, target_id, field_path)


## Scan and register all references in an entity.
func scan_entity_references(entity: Entity) -> void:
	reference_tracker.scan_entity_references(entity)


## Clean all dangling references.
func clean_dangling_references() -> int:
	return entity_validator.clean_all_dangling_references()


## Check if an entity is referenced by others.
func is_entity_referenced(entity_id: int) -> bool:
	return reference_tracker.is_referenced(entity_id)


# =============================================================================
# Serialization API
# =============================================================================

## Serialize the entire ECS state to dictionary.
func to_dict() -> Dictionary:
	return {
		"entity_manager": entity_manager.to_dict(),
		"component_registry": component_registry.to_dict()
	}


## Deserialize ECS state from dictionary.
func from_dict(data: Dictionary) -> void:
	var em_data: Dictionary = data.get("entity_manager", {})
	entity_manager.from_dict(em_data, component_registry)

	# Rebuild reference tracking
	reference_tracker.clear()
	for entity in entity_manager.get_all_entities():
		reference_tracker.scan_entity_references(entity)


## Clear all entities and reset to initial state.
func clear() -> void:
	reference_tracker.clear()
	entity_manager.clear()


## Reset the ECS world with a new seed.
func reset(seed_value: int = 0) -> void:
	reference_tracker.clear()
	entity_manager.reset(seed_value)


# =============================================================================
# Utility API
# =============================================================================

## Get current performance statistics.
func get_stats() -> Dictionary:
	return stats


## Get entity count.
func get_entity_count() -> int:
	return entity_manager.get_entity_count()


## Generate a formatted entity ID string.
func generate_id_string(type: EntityTypes.Type, entity: Entity) -> String:
	return EntityTypes.generate_id_string(type, entity.id)


## Print debug information.
func debug_print() -> void:
	print("=== ECSWorld Debug ===")
	print("Entities: %d" % entity_manager.get_entity_count())
	print("Pool size: %d" % entity_manager.get_total_pool_size())
	print("Registered components: %s" % str(component_registry.get_registered_types()))
	print("Systems: %s" % str(system_manager.get_system_names()))
	print("Reference stats: %s" % str(reference_tracker.get_stats()))
	print("Stats: %s" % str(stats))
	print("======================")
