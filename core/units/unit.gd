class_name Unit
extends Entity
## Unit is the core entity class representing individual units in the game.
## Extends Entity to add unit-specific properties and component accessors.
## Designed for high-performance scenarios with 5,000+ concurrent instances.

signal died(killer_id: int)
signal damaged(amount: float, source_id: int)
signal healed(amount: float)
signal state_changed(old_state: int, new_state: int)

## Unit states
enum State {
	IDLE = 0,
	MOVING = 1,
	ATTACKING = 2,
	DEAD = 3,
	SPAWNING = 4
}

## Faction ID this unit belongs to
var faction_id: int = 0

## Unit type identifier (e.g., "soldier", "drone", "forge_walker")
var unit_type: String = ""

## Current unit state
var current_state: int = State.IDLE

## Whether this unit is alive
var is_alive: bool = true

## Rendering instance index (for MultiMesh batching, -1 if not rendered)
var render_instance_index: int = -1

## Rendering mesh group ID (for MultiMesh grouping by unit type)
var render_group_id: int = -1

## Cached component references (for performance)
var _health_component: HealthComponent = null
var _movement_component: MovementComponent = null
var _combat_component: Component = null
var _faction_component: Component = null
var _ai_component: AIComponent = null

## Static ID counter for unique unit generation
static var _next_unit_id: int = 1

## ID generation lock for thread safety (future proofing)
static var _id_generation_enabled: bool = true


func _init() -> void:
	super._init()
	type_enum = EntityTypes.Type.UNIT
	entity_type = "Unit"


## Generate a new unique unit ID.
## Returns the next available unit ID.
static func generate_unit_id() -> int:
	if not _id_generation_enabled:
		push_error("Unit ID generation is disabled")
		return -1
	var new_id := _next_unit_id
	_next_unit_id += 1
	return new_id


## Reset the unit ID counter (for testing or new game).
static func reset_id_counter(start_id: int = 1) -> void:
	_next_unit_id = start_id


## Get the current ID counter value.
static func get_current_id_counter() -> int:
	return _next_unit_id


## Create and initialize a new unit with the given parameters.
static func create(p_faction_id: int, p_unit_type: String, p_position: Vector3 = Vector3.ZERO) -> Unit:
	var unit := Unit.new()
	var unit_id := generate_unit_id()
	unit.initialize(unit_id, EntityTypes.Type.UNIT)
	unit.faction_id = p_faction_id
	unit.unit_type = p_unit_type

	# Add default components
	var health := HealthComponent.new()
	unit.add_component(health)

	var movement := MovementComponent.new()
	movement.set_position(p_position)
	unit.add_component(movement)

	return unit


## Initialize unit with faction and type.
func initialize_unit(unit_id: int, p_faction_id: int, p_unit_type: String) -> void:
	initialize(unit_id, EntityTypes.Type.UNIT)
	faction_id = p_faction_id
	unit_type = p_unit_type
	is_alive = true
	current_state = State.IDLE


## Override add_component to cache common component references.
func add_component(component: Component) -> bool:
	var result := super.add_component(component)
	if result:
		_cache_component_reference(component)
	return result


## Override remove_component to clear cached references.
func remove_component(type_name: String) -> Component:
	var component := super.remove_component(type_name)
	if component != null:
		_clear_component_cache(type_name)
	return component


## Cache component reference for fast access.
func _cache_component_reference(component: Component) -> void:
	match component.get_component_type():
		"HealthComponent":
			_health_component = component as HealthComponent
		"MovementComponent":
			_movement_component = component as MovementComponent
		"CombatComponent":
			_combat_component = component
		"FactionComponent":
			_faction_component = component
		"AIComponent":
			_ai_component = component as AIComponent


## Clear cached component reference.
func _clear_component_cache(type_name: String) -> void:
	match type_name:
		"HealthComponent":
			_health_component = null
		"MovementComponent":
			_movement_component = null
		"CombatComponent":
			_combat_component = null
		"FactionComponent":
			_faction_component = null
		"AIComponent":
			_ai_component = null


## Get health component (cached).
func get_health() -> HealthComponent:
	if _health_component == null:
		_health_component = get_component("HealthComponent") as HealthComponent
	return _health_component


## Get movement component (cached).
func get_movement() -> MovementComponent:
	if _movement_component == null:
		_movement_component = get_component("MovementComponent") as MovementComponent
	return _movement_component


## Get combat component (cached).
func get_combat() -> Component:
	if _combat_component == null:
		_combat_component = get_component("CombatComponent")
	return _combat_component


## Get faction component (cached).
func get_faction() -> Component:
	if _faction_component == null:
		_faction_component = get_component("FactionComponent")
	return _faction_component


## Get AI component (cached).
func get_ai() -> AIComponent:
	if _ai_component == null:
		_ai_component = get_component("AIComponent") as AIComponent
	return _ai_component


## Convenience: Get current position from MovementComponent.
func get_position() -> Vector3:
	var movement := get_movement()
	if movement != null:
		return movement.get_position()
	return Vector3.ZERO


## Convenience: Set position via MovementComponent.
func set_position(pos: Vector3) -> void:
	var movement := get_movement()
	if movement != null:
		movement.set_position(pos)


## Convenience: Get velocity from MovementComponent.
func get_velocity() -> Vector3:
	var movement := get_movement()
	if movement != null:
		return movement.get_velocity()
	return Vector3.ZERO


## Convenience: Set velocity via MovementComponent.
func set_velocity(vel: Vector3) -> void:
	var movement := get_movement()
	if movement != null:
		movement.set_velocity(vel)


## Convenience: Get rotation from MovementComponent.
func get_rotation() -> Vector3:
	var movement := get_movement()
	if movement != null:
		return movement.get_rotation()
	return Vector3.ZERO


## Convenience: Set rotation via MovementComponent.
func set_rotation(rot: Vector3) -> void:
	var movement := get_movement()
	if movement != null:
		movement.set_rotation(rot)


## Convenience: Get current health from HealthComponent.
func get_current_health() -> float:
	var health := get_health()
	if health != null:
		return health.get_current_health()
	return 0.0


## Convenience: Get max health from HealthComponent.
func get_max_health() -> float:
	var health := get_health()
	if health != null:
		return health.get_max_health()
	return 0.0


## Convenience: Get health percentage.
func get_health_percentage() -> float:
	var health := get_health()
	if health != null:
		return health.get_health_percentage()
	return 0.0


## Apply damage to this unit.
func take_damage(amount: float, source_id: int = -1) -> float:
	var health := get_health()
	if health == null:
		return 0.0

	var actual_damage := health.apply_damage(amount, source_id)
	if actual_damage > 0:
		damaged.emit(actual_damage, source_id)

	if health.is_dead() and is_alive:
		_die(source_id)

	return actual_damage


## Heal this unit.
func heal_damage(amount: float) -> float:
	var health := get_health()
	if health == null:
		return 0.0

	var actual_heal := health.heal(amount)
	if actual_heal > 0:
		healed.emit(actual_heal)

	return actual_heal


## Handle unit death.
func _die(killer_id: int) -> void:
	if not is_alive:
		return

	is_alive = false
	set_state(State.DEAD)
	died.emit(killer_id)


## Check if unit is dead.
func is_dead() -> bool:
	return not is_alive or current_state == State.DEAD


## Set unit state.
func set_state(new_state: int) -> void:
	if new_state == current_state:
		return
	var old_state := current_state
	current_state = new_state
	state_changed.emit(old_state, new_state)


## Get state name for debugging.
func get_state_name() -> String:
	match current_state:
		State.IDLE: return "IDLE"
		State.MOVING: return "MOVING"
		State.ATTACKING: return "ATTACKING"
		State.DEAD: return "DEAD"
		State.SPAWNING: return "SPAWNING"
		_: return "UNKNOWN"


## Override spawn to set state.
func spawn() -> void:
	set_state(State.SPAWNING)
	super.spawn()
	if is_alive:
		set_state(State.IDLE)


## Override despawn to cleanup.
func despawn() -> void:
	render_instance_index = -1
	render_group_id = -1
	super.despawn()


## Set rendering instance info (for MultiMesh).
func set_render_instance(group_id: int, instance_index: int) -> void:
	render_group_id = group_id
	render_instance_index = instance_index


## Clear rendering instance info.
func clear_render_instance() -> void:
	render_group_id = -1
	render_instance_index = -1


## Check if unit has rendering info.
func has_render_instance() -> bool:
	return render_instance_index >= 0


## Override serialization to include unit-specific data.
func to_dict() -> Dictionary:
	var base := super.to_dict()

	base["unit"] = {
		"faction_id": faction_id,
		"unit_type": unit_type,
		"current_state": current_state,
		"is_alive": is_alive,
		"render_instance_index": render_instance_index,
		"render_group_id": render_group_id
	}

	return base


## Override deserialization to restore unit-specific data.
static func from_dict(data: Dictionary) -> Unit:
	var unit := Unit.new()

	# Restore base Entity properties
	unit.id = data.get("id", -1)
	unit.id_string = data.get("id_string", "")
	unit.entity_type = data.get("entity_type", "Unit")
	unit.type_enum = data.get("type_enum", EntityTypes.Type.UNIT)
	unit.is_active = data.get("is_active", true)
	unit.is_spawned = data.get("is_spawned", false)
	unit.spawn_time = data.get("spawn_time", 0)
	unit.despawn_time = data.get("despawn_time", 0)
	unit.name = unit.id_string

	# Restore unit-specific properties
	var unit_data: Dictionary = data.get("unit", {})
	unit.faction_id = unit_data.get("faction_id", 0)
	unit.unit_type = unit_data.get("unit_type", "")
	unit.current_state = unit_data.get("current_state", State.IDLE)
	unit.is_alive = unit_data.get("is_alive", true)
	unit.render_instance_index = unit_data.get("render_instance_index", -1)
	unit.render_group_id = unit_data.get("render_group_id", -1)

	# Components are reconstructed by the calling code
	return unit


## Reset unit for reuse in object pool.
func reset() -> void:
	super.reset()
	faction_id = 0
	unit_type = ""
	current_state = State.IDLE
	is_alive = true
	render_instance_index = -1
	render_group_id = -1
	_health_component = null
	_movement_component = null
	_combat_component = null
	_faction_component = null
	_ai_component = null


## Get a compact summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"id_string": id_string,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"state": get_state_name(),
		"is_alive": is_alive,
		"position": get_position(),
		"health": get_health_percentage(),
		"components": get_component_count()
	}
