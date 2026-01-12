extends Node
## EntityManager Singleton - Global manager for entity lifecycle and queries.
## Provides centralized entity management with typed pooling and efficient queries.
## Set as autoload: EntityManager

## Signal emitted when an entity is created
signal entity_created(entity: Entity)

## Signal emitted when an entity is destroyed
signal entity_destroyed(entity_id: int)

## Signal emitted when an entity is spawned
signal entity_spawned(entity_id: int)

## Signal emitted when an entity is despawned
signal entity_despawned(entity_id: int)

## Signal emitted when a component is added to an entity
signal component_added(entity_id: int, component_type: String)

## Signal emitted when a component is removed from an entity
signal component_removed(entity_id: int, component_type: String)

## Default pool sizes per entity type
const DEFAULT_POOL_SIZES: Dictionary = {
	"Unit": 5000,
	"Projectile": 10000,
	"Building": 500,
	"Effect": 2000,
	"District": 100,
	"Resource": 500,
	"Factory": 50,
	"Custom": 1000
}

## Maximum entities allowed per type
const MAX_ENTITIES_PER_TYPE: Dictionary = {
	"Unit": 10000,
	"Projectile": 20000,
	"Building": 1000,
	"Effect": 5000,
	"District": 200,
	"Resource": 1000,
	"Factory": 100,
	"Custom": 5000
}

## Active entities indexed by ID
var _entities: Dictionary = {}

## Typed entity pools for reuse
## Maps entity type -> Array[Entity]
var _typed_pools: Dictionary = {}

## Next entity ID per type for deterministic generation
var _next_ids: Dictionary = {}

## ID seed for deterministic behavior
var _id_seed: int = 0

## Component type to entity ID index for fast queries
## Maps component type name -> Array of entity IDs
var _component_index: Dictionary = {}

## Entity type to entity ID index
## Maps entity type name -> Array of entity IDs
var _type_index: Dictionary = {}

## Entities marked for despawn (processed at end of frame)
var _despawn_queue: Array[int] = []

## Total entities created (including destroyed) for statistics
var _total_created: int = 0

## Performance tracking
var _last_query_time_usec: int = 0
var _last_update_time_usec: int = 0


func _ready() -> void:
	_initialize_pools()
	print("EntityManager: Initialized with typed pools")


func _initialize_pools() -> void:
	for type_name in DEFAULT_POOL_SIZES:
		_typed_pools[type_name] = []
		_next_ids[type_name] = _id_seed + 1
		_preallocate_pool(type_name, DEFAULT_POOL_SIZES[type_name])


## Pre-allocate entities for a specific type pool.
func _preallocate_pool(type_name: String, count: int) -> void:
	if not _typed_pools.has(type_name):
		_typed_pools[type_name] = []

	var pool: Array = _typed_pools[type_name]
	for i in range(count):
		var entity := Entity.new()
		pool.append(entity)


## Set the ID seed for deterministic entity generation.
func set_seed(seed_value: int) -> void:
	_id_seed = seed_value
	for type_name in _next_ids:
		_next_ids[type_name] = seed_value + 1


## Generate the next deterministic entity ID for a type.
func _generate_entity_id(type_name: String) -> int:
	if not _next_ids.has(type_name):
		_next_ids[type_name] = _id_seed + 1

	var id: int = _next_ids[type_name]
	_next_ids[type_name] += 1
	return id


# =============================================================================
# Entity Lifecycle API
# =============================================================================

## Create a new entity of the specified type.
## Returns the created entity or null if max entities reached.
func create_entity(type_name: String = "Custom") -> Entity:
	var max_count: int = MAX_ENTITIES_PER_TYPE.get(type_name, 5000)
	var current_count: int = 0
	if _type_index.has(type_name):
		current_count = _type_index[type_name].size()

	if current_count >= max_count:
		push_error("EntityManager: Maximum entity limit reached for type '%s' (%d)" % [type_name, max_count])
		return null

	var entity: Entity = get_pooled_entity(type_name)

	# Initialize entity
	var entity_id := _generate_entity_id(type_name)
	var type_enum := EntityTypes.get_type_from_name(type_name)
	entity.initialize(entity_id, type_enum)

	# Register entity
	_entities[entity.id] = entity
	_total_created += 1

	# Add to type index
	if not _type_index.has(type_name):
		_type_index[type_name] = []
	_type_index[type_name].append(entity.id)

	entity_created.emit(entity)
	return entity


## Create a new entity with specific EntityTypes.Type.
func create_typed_entity(type: EntityTypes.Type) -> Entity:
	var type_name := EntityTypes.get_type_name(type)
	return create_entity(type_name)


## Get a pooled entity or create a new one.
func get_pooled_entity(type_name: String) -> Entity:
	if not _typed_pools.has(type_name):
		_typed_pools[type_name] = []

	var pool: Array = _typed_pools[type_name]
	if pool.size() > 0:
		var entity: Entity = pool.pop_back()
		entity.reset()
		return entity

	return Entity.new()


## Return an entity to its type pool.
func return_to_pool(entity: Entity) -> void:
	var type_name := entity.entity_type
	if not _typed_pools.has(type_name):
		_typed_pools[type_name] = []

	entity.reset()
	_typed_pools[type_name].append(entity)


## Spawn an entity (activate lifecycle).
func spawn_entity(entity_id: int) -> bool:
	var entity := get_entity(entity_id)
	if entity == null:
		return false

	entity.spawn()
	entity_spawned.emit(entity_id)
	return true


## Despawn an entity (deactivate without destroying).
func despawn_entity(entity_id: int) -> bool:
	var entity := get_entity(entity_id)
	if entity == null:
		return false

	entity.despawn()
	entity_despawned.emit(entity_id)
	return true


## Queue an entity for despawn at end of frame.
func queue_despawn(entity_id: int) -> void:
	if entity_id not in _despawn_queue:
		_despawn_queue.append(entity_id)


## Process despawn queue (call at end of frame).
func process_despawn_queue() -> int:
	var count := _despawn_queue.size()
	for entity_id in _despawn_queue:
		destroy_entity(entity_id)
	_despawn_queue.clear()
	return count


## Destroy an entity by ID, returning it to the pool.
## Returns true if entity was found and destroyed.
func destroy_entity(entity_id: int) -> bool:
	if not _entities.has(entity_id):
		return false

	var entity: Entity = _entities[entity_id]

	# Despawn if spawned
	if entity.is_spawned:
		entity.despawn()

	# Remove from component indices
	for component_type in entity.get_component_types():
		_remove_from_component_index(entity_id, component_type)

	# Remove from type index
	var type_name := entity.entity_type
	if _type_index.has(type_name):
		_type_index[type_name].erase(entity_id)

	# Remove from active entities
	_entities.erase(entity_id)

	# Return to pool
	return_to_pool(entity)

	entity_destroyed.emit(entity_id)
	return true


## Activate an entity without full spawn.
func activate_entity(entity_id: int) -> bool:
	var entity := get_entity(entity_id)
	if entity == null:
		return false
	entity.is_active = true
	return true


## Deactivate an entity without destruction.
func deactivate_entity(entity_id: int) -> bool:
	var entity := get_entity(entity_id)
	if entity == null:
		return false
	entity.is_active = false
	return true


# =============================================================================
# Entity Query API
# =============================================================================

## Get an entity by ID (< 0.01ms).
func get_entity(entity_id: int) -> Entity:
	var start := Time.get_ticks_usec()
	var result: Entity = _entities.get(entity_id)
	_last_query_time_usec = Time.get_ticks_usec() - start
	return result


## Check if an entity exists.
func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


## Get all active entities.
func get_all_entities() -> Array[Entity]:
	var entities: Array[Entity] = []
	for entity in _entities.values():
		entities.append(entity)
	return entities


## Get all spawned entities.
func get_spawned_entities() -> Array[Entity]:
	var entities: Array[Entity] = []
	for entity in _entities.values():
		if entity.is_spawned:
			entities.append(entity)
	return entities


## Get entities by type.
func get_entities_by_type(entity_type: String) -> Array[Entity]:
	var start := Time.get_ticks_usec()
	var result: Array[Entity] = []

	if _type_index.has(entity_type):
		for entity_id in _type_index[entity_type]:
			var entity := get_entity(entity_id)
			if entity != null:
				result.append(entity)

	_last_query_time_usec = Time.get_ticks_usec() - start
	return result


## Get entities with a specific component.
func get_entities_with_component(component_type: String) -> Array[Entity]:
	var start := Time.get_ticks_usec()
	var result: Array[Entity] = []

	if _component_index.has(component_type):
		for entity_id in _component_index[component_type]:
			var entity := get_entity(entity_id)
			if entity != null and entity.is_active:
				result.append(entity)

	_last_query_time_usec = Time.get_ticks_usec() - start
	return result


## Get entities with ALL specified components.
func get_entities_with_components(component_types: Array[String]) -> Array[Entity]:
	var start := Time.get_ticks_usec()
	var result: Array[Entity] = []

	if component_types.is_empty():
		_last_query_time_usec = Time.get_ticks_usec() - start
		return get_all_entities()

	# Find the smallest component index to iterate
	var smallest_type := ""
	var smallest_count := 999999

	for type_name in component_types:
		if not _component_index.has(type_name):
			_last_query_time_usec = Time.get_ticks_usec() - start
			return result  # No entities have this component

		var count: int = _component_index[type_name].size()
		if count < smallest_count:
			smallest_count = count
			smallest_type = type_name

	# Iterate smallest set and check for all components
	for entity_id in _component_index[smallest_type]:
		var entity := get_entity(entity_id)
		if entity != null and entity.is_active and entity.has_components(component_types):
			result.append(entity)

	_last_query_time_usec = Time.get_ticks_usec() - start
	return result


## Query entities with ANY of the specified component types.
func get_entities_with_any_component(component_types: Array[String]) -> Array[Entity]:
	var result: Array[Entity] = []
	var seen_ids: Dictionary = {}

	for type_name in component_types:
		if _component_index.has(type_name):
			for entity_id in _component_index[type_name]:
				if not seen_ids.has(entity_id):
					var entity := get_entity(entity_id)
					if entity != null and entity.is_active:
						result.append(entity)
						seen_ids[entity_id] = true

	return result


## Get entity count.
func get_entity_count() -> int:
	return _entities.size()


## Get entity count by type.
func get_entity_count_by_type(entity_type: String) -> int:
	if _type_index.has(entity_type):
		return _type_index[entity_type].size()
	return 0


## Get spawned entity count.
func get_spawned_count() -> int:
	var count := 0
	for entity in _entities.values():
		if entity.is_spawned:
			count += 1
	return count


# =============================================================================
# Component Management API
# =============================================================================

## Add a component to an entity.
func add_component(entity_id: int, component: Component) -> bool:
	var entity := get_entity(entity_id)
	if entity == null:
		push_error("EntityManager: Cannot add component to non-existent entity %d" % entity_id)
		return false

	if not entity.add_component(component):
		return false

	# Update component index
	var type_name := component.get_component_type()
	_add_to_component_index(entity_id, type_name)

	component_added.emit(entity_id, type_name)
	return true


## Remove a component from an entity by type.
func remove_component(entity_id: int, component_type: String) -> Component:
	var entity := get_entity(entity_id)
	if entity == null:
		return null

	var component := entity.remove_component(component_type)
	if component != null:
		_remove_from_component_index(entity_id, component_type)
		component_removed.emit(entity_id, component_type)

	return component


## Add entity to component index.
func _add_to_component_index(entity_id: int, component_type: String) -> void:
	if not _component_index.has(component_type):
		_component_index[component_type] = []
	if entity_id not in _component_index[component_type]:
		_component_index[component_type].append(entity_id)


## Remove entity from component index.
func _remove_from_component_index(entity_id: int, component_type: String) -> void:
	if _component_index.has(component_type):
		_component_index[component_type].erase(entity_id)


# =============================================================================
# Batch Operations API
# =============================================================================

## Update all active entities (call their components' on_update).
func update_all_entities(delta: float) -> void:
	var start := Time.get_ticks_usec()

	for entity in _entities.values():
		if entity.is_active and entity.is_spawned:
			entity.notify_components_update(delta)

	_last_update_time_usec = Time.get_ticks_usec() - start


## Despawn all inactive entities.
func despawn_inactive_entities() -> int:
	var despawned := 0
	var to_despawn: Array[int] = []

	for entity in _entities.values():
		if not entity.is_active:
			to_despawn.append(entity.id)

	for entity_id in to_despawn:
		if destroy_entity(entity_id):
			despawned += 1

	return despawned


## Create multiple entities of the same type.
func batch_create_entities(type_name: String, count: int) -> Array[Entity]:
	var entities: Array[Entity] = []
	for i in range(count):
		var entity := create_entity(type_name)
		if entity != null:
			entities.append(entity)
		else:
			break
	return entities


## Destroy multiple entities by ID.
func batch_destroy_entities(entity_ids: Array[int]) -> int:
	var destroyed := 0
	for entity_id in entity_ids:
		if destroy_entity(entity_id):
			destroyed += 1
	return destroyed


## Spawn multiple entities.
func batch_spawn_entities(entity_ids: Array[int]) -> int:
	var spawned := 0
	for entity_id in entity_ids:
		if spawn_entity(entity_id):
			spawned += 1
	return spawned


## Despawn multiple entities.
func batch_despawn_entities(entity_ids: Array[int]) -> int:
	var despawned := 0
	for entity_id in entity_ids:
		if despawn_entity(entity_id):
			despawned += 1
	return despawned


## Add component to multiple entities using factory.
func batch_add_component(entity_ids: Array[int], factory: Callable) -> int:
	var added := 0
	for entity_id in entity_ids:
		var component = factory.call()
		if component is Component:
			if add_component(entity_id, component):
				added += 1
	return added


## Remove component from multiple entities.
func batch_remove_component(entity_ids: Array[int], component_type: String) -> int:
	var removed := 0
	for entity_id in entity_ids:
		if remove_component(entity_id, component_type) != null:
			removed += 1
	return removed


# =============================================================================
# Pool Management API
# =============================================================================

## Get pool size for a specific entity type.
func get_pool_size(type_name: String) -> int:
	if _typed_pools.has(type_name):
		return _typed_pools[type_name].size()
	return 0


## Get total pool size across all types.
func get_total_pool_size() -> int:
	var total := 0
	for pool in _typed_pools.values():
		total += pool.size()
	return total


## Expand pool for a specific type.
func expand_pool(type_name: String, count: int) -> void:
	_preallocate_pool(type_name, count)


## Clear a specific type pool.
func clear_pool(type_name: String) -> void:
	if _typed_pools.has(type_name):
		_typed_pools[type_name].clear()


# =============================================================================
# Serialization API
# =============================================================================

## Serialize all entities to dictionary.
func to_dict() -> Dictionary:
	var entities_data: Array = []
	for entity in _entities.values():
		entities_data.append(entity.to_dict())

	return {
		"id_seed": _id_seed,
		"next_ids": _next_ids.duplicate(),
		"entities": entities_data
	}


## Deserialize entities from dictionary.
func from_dict(data: Dictionary, component_registry = null) -> void:
	clear()

	_id_seed = data.get("id_seed", 0)
	_next_ids = data.get("next_ids", {}).duplicate()

	var entities_data: Array = data.get("entities", [])
	for entity_data in entities_data:
		var entity := Entity.from_dict(entity_data)

		# Register entity
		_entities[entity.id] = entity

		# Add to type index
		if not _type_index.has(entity.entity_type):
			_type_index[entity.entity_type] = []
		_type_index[entity.entity_type].append(entity.id)

		# Reconstruct components if registry provided
		if component_registry != null:
			var components_data: Dictionary = entity_data.get("components", {})
			for type_name in components_data:
				var component = component_registry.create_component(type_name)
				if component != null:
					component._from_dict(components_data[type_name])
					entity.add_component(component)
					_add_to_component_index(entity.id, type_name)


## Clear all entities and reset state.
func clear() -> void:
	for entity in _entities.values():
		if entity.is_spawned:
			entity.despawn()
		return_to_pool(entity)

	_entities.clear()
	_component_index.clear()
	_type_index.clear()
	_despawn_queue.clear()


## Reset manager to initial state with new seed.
func reset(seed_value: int = 0) -> void:
	clear()
	set_seed(seed_value)
	_total_created = 0


# =============================================================================
# Statistics API
# =============================================================================

## Get last query time in microseconds.
func get_last_query_time_usec() -> int:
	return _last_query_time_usec


## Get last update time in microseconds.
func get_last_update_time_usec() -> int:
	return _last_update_time_usec


## Get comprehensive statistics.
func get_stats() -> Dictionary:
	var pool_stats: Dictionary = {}
	for type_name in _typed_pools:
		pool_stats[type_name] = _typed_pools[type_name].size()

	var type_counts: Dictionary = {}
	for type_name in _type_index:
		type_counts[type_name] = _type_index[type_name].size()

	return {
		"total_entities": _entities.size(),
		"total_created": _total_created,
		"spawned_count": get_spawned_count(),
		"pool_sizes": pool_stats,
		"entities_by_type": type_counts,
		"component_types_indexed": _component_index.size(),
		"despawn_queue_size": _despawn_queue.size(),
		"last_query_time_usec": _last_query_time_usec,
		"last_update_time_usec": _last_update_time_usec
	}
