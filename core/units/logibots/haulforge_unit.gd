class_name HaulforgeUnit
extends RefCounted
## HaulforgeUnit is the LogiBots Colossus heavy lifter for REE transport.
## Can carry 500 REE, moves 20% slower when loaded, auto-returns when full.

signal ree_loaded(amount: float, total: float)
signal ree_unloaded(amount: float, factory_id: int)
signal cargo_changed(current: float, max: float)
signal returning_to_factory(factory_id: int)
signal arrived_at_destination(destination_type: String)
signal load_state_changed(is_loaded: bool)

## Unit stats
const MAX_HEALTH := 200.0
const BASE_MOVEMENT_SPEED := 0.6
const LOADED_SPEED_MULTIPLIER := 0.8    ## 20% slower when loaded
const ARMOR := 60.0
const ATTACK_COOLDOWN := 10.0
const BASE_DAMAGE := 30.0

## Heavy Lift ability configuration
const MAX_CARGO := 500.0                ## REE capacity
const LOAD_RATE := 50.0                 ## REE per second when loading
const UNLOAD_RATE := 100.0              ## REE per second when unloading
const AUTO_RETURN_ENABLED := true

## Unit data
var unit_id: int = -1
var faction_id: int = 0
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var rotation: float = 0.0

## Health
var current_health: float = MAX_HEALTH
var is_alive: bool = true

## Combat
var attack_cooldown_timer: float = 0.0
var current_target_id: int = -1

## Cargo state
var _current_cargo: float = 0.0
var _is_loaded: bool = false

## Movement state
enum State { IDLE, MOVING_TO_PICKUP, LOADING, MOVING_TO_FACTORY, UNLOADING, ATTACKING, DEAD }
var _current_state: State = State.IDLE
var _movement_target: Vector3 = Vector3.ZERO

## Factory and pickup assignments
var _assigned_factory_id: int = -1
var _assigned_factory_position: Vector3 = Vector3.ZERO
var _pickup_target: Vector3 = Vector3.ZERO
var _load_timer: float = 0.0


func _init() -> void:
	pass


## Initialize unit with ID and faction.
func initialize(p_unit_id: int, p_faction_id: int, p_position: Vector3) -> void:
	unit_id = p_unit_id
	faction_id = p_faction_id
	position = p_position
	current_health = MAX_HEALTH
	is_alive = true
	_current_state = State.IDLE
	_current_cargo = 0.0
	_is_loaded = false


## Update unit each frame.
func update(delta: float) -> void:
	if not is_alive:
		return

	# Update attack cooldown
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

	# State machine
	match _current_state:
		State.IDLE:
			_update_idle(delta)
		State.MOVING_TO_PICKUP:
			_update_moving_to_pickup(delta)
		State.LOADING:
			_update_loading(delta)
		State.MOVING_TO_FACTORY:
			_update_moving_to_factory(delta)
		State.UNLOADING:
			_update_unloading(delta)
		State.ATTACKING:
			_update_attacking(delta)


## Get current movement speed.
func _get_current_speed() -> float:
	if _is_loaded:
		return BASE_MOVEMENT_SPEED * LOADED_SPEED_MULTIPLIER * 10.0
	return BASE_MOVEMENT_SPEED * 10.0


## Update idle state.
func _update_idle(_delta: float) -> void:
	pass


## Update moving to pickup location.
func _update_moving_to_pickup(delta: float) -> void:
	var direction := (_pickup_target - position).normalized()
	direction.y = 0

	if position.distance_to(_pickup_target) > 2.0:
		velocity = direction * _get_current_speed()
		position += velocity * delta
		rotation = atan2(direction.x, direction.z)
	else:
		velocity = Vector3.ZERO
		_current_state = State.LOADING
		_load_timer = 0.0
		arrived_at_destination.emit("pickup")


## Update loading state.
func _update_loading(delta: float) -> void:
	_load_timer += delta

	var load_amount := LOAD_RATE * delta
	var space_available := MAX_CARGO - _current_cargo
	var actual_loaded := minf(load_amount, space_available)

	_current_cargo += actual_loaded
	cargo_changed.emit(_current_cargo, MAX_CARGO)

	if actual_loaded > 0:
		ree_loaded.emit(actual_loaded, _current_cargo)

	# Update loaded state
	if not _is_loaded and _current_cargo > 0:
		_is_loaded = true
		load_state_changed.emit(true)

	# Check if full and auto-return
	if _current_cargo >= MAX_CARGO:
		if AUTO_RETURN_ENABLED and _assigned_factory_id >= 0:
			_start_return_to_factory()


## Update moving to factory.
func _update_moving_to_factory(delta: float) -> void:
	var direction := (_assigned_factory_position - position).normalized()
	direction.y = 0

	if position.distance_to(_assigned_factory_position) > 3.0:
		velocity = direction * _get_current_speed()
		position += velocity * delta
		rotation = atan2(direction.x, direction.z)
	else:
		velocity = Vector3.ZERO
		_current_state = State.UNLOADING
		_load_timer = 0.0
		arrived_at_destination.emit("factory")


## Update unloading state.
func _update_unloading(delta: float) -> void:
	_load_timer += delta

	var unload_amount := UNLOAD_RATE * delta
	var actual_unloaded := minf(unload_amount, _current_cargo)

	_current_cargo -= actual_unloaded
	cargo_changed.emit(_current_cargo, MAX_CARGO)

	if actual_unloaded > 0:
		ree_unloaded.emit(actual_unloaded, _assigned_factory_id)

	# Check if empty
	if _current_cargo <= 0:
		_current_cargo = 0.0
		_is_loaded = false
		load_state_changed.emit(false)
		_current_state = State.IDLE


## Update attacking state.
func _update_attacking(_delta: float) -> void:
	if current_target_id < 0:
		_current_state = State.IDLE
		return

	if attack_cooldown_timer <= 0:
		attack_cooldown_timer = ATTACK_COOLDOWN


## Start return to factory.
func _start_return_to_factory() -> void:
	if _assigned_factory_id < 0:
		return

	_current_state = State.MOVING_TO_FACTORY
	returning_to_factory.emit(_assigned_factory_id)


## Assign factory for deposits.
func assign_factory(factory_id: int, factory_position: Vector3) -> void:
	_assigned_factory_id = factory_id
	_assigned_factory_position = factory_position


## Set pickup location and start moving.
func pickup_at(target_position: Vector3) -> void:
	if not is_alive:
		return

	_pickup_target = target_position
	_current_state = State.MOVING_TO_PICKUP


## Force return to factory.
func return_to_factory() -> void:
	if _assigned_factory_id >= 0:
		_start_return_to_factory()


## Load REE directly (instant load).
func load_ree(amount: float) -> float:
	var space_available := MAX_CARGO - _current_cargo
	var actual_loaded := minf(amount, space_available)

	_current_cargo += actual_loaded
	cargo_changed.emit(_current_cargo, MAX_CARGO)

	if not _is_loaded and _current_cargo > 0:
		_is_loaded = true
		load_state_changed.emit(true)

	if actual_loaded > 0:
		ree_loaded.emit(actual_loaded, _current_cargo)

	return actual_loaded


## Unload REE directly (instant unload).
func unload_ree() -> float:
	var unloaded := _current_cargo
	_current_cargo = 0.0
	_is_loaded = false
	load_state_changed.emit(false)
	cargo_changed.emit(_current_cargo, MAX_CARGO)
	return unloaded


## Move to position.
func move_to(target: Vector3) -> void:
	if not is_alive:
		return

	_movement_target = target
	_current_state = State.MOVING_TO_PICKUP
	_pickup_target = target


## Attack target.
func attack_target(target_id: int) -> void:
	if not is_alive:
		return

	current_target_id = target_id
	_current_state = State.ATTACKING


## Get attack damage.
func get_damage() -> float:
	return BASE_DAMAGE


## Can attack right now.
func can_attack() -> bool:
	return attack_cooldown_timer <= 0 and is_alive


## Apply damage to unit.
func take_damage(amount: float, _source_id: int = -1) -> float:
	# Apply armor reduction
	var damage_reduction := ARMOR / (ARMOR + 100.0)
	var actual_damage := amount * (1.0 - damage_reduction)

	current_health -= actual_damage
	if current_health <= 0:
		current_health = 0
		_die()

	return actual_damage


## Handle death.
func _die() -> void:
	is_alive = false
	_current_state = State.DEAD
	velocity = Vector3.ZERO


## Get current cargo.
func get_cargo() -> float:
	return _current_cargo


## Get cargo percentage.
func get_cargo_percentage() -> float:
	return _current_cargo / MAX_CARGO


## Is cargo full.
func is_cargo_full() -> bool:
	return _current_cargo >= MAX_CARGO


## Is currently loaded (carrying cargo).
func is_loaded() -> bool:
	return _is_loaded


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.IDLE: return "Idle"
		State.MOVING_TO_PICKUP: return "Moving to Pickup"
		State.LOADING: return "Loading"
		State.MOVING_TO_FACTORY: return "Returning"
		State.UNLOADING: return "Unloading"
		State.ATTACKING: return "Attacking"
		State.DEAD: return "Dead"
	return "Unknown"


## Get transform for rendering.
func get_transform() -> Transform3D:
	var transform := Transform3D.IDENTITY
	transform.origin = position
	transform.basis = Basis(Vector3.UP, rotation)
	return transform


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"unit_id": unit_id,
		"faction_id": faction_id,
		"unit_type": "haulforge",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"cargo": _current_cargo,
		"max_cargo": MAX_CARGO,
		"cargo_percent": get_cargo_percentage(),
		"is_loaded": _is_loaded,
		"current_speed": _get_current_speed(),
		"is_alive": is_alive,
		"assigned_factory": _assigned_factory_id
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"faction_id": faction_id,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"rotation": rotation,
		"current_health": current_health,
		"is_alive": is_alive,
		"current_cargo": _current_cargo,
		"is_loaded": _is_loaded,
		"current_state": _current_state,
		"assigned_factory_id": _assigned_factory_id,
		"assigned_factory_position": {
			"x": _assigned_factory_position.x,
			"y": _assigned_factory_position.y,
			"z": _assigned_factory_position.z
		},
		"pickup_target": {"x": _pickup_target.x, "y": _pickup_target.y, "z": _pickup_target.z},
		"attack_cooldown": attack_cooldown_timer
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	unit_id = data.get("unit_id", -1)
	faction_id = data.get("faction_id", 0)

	var pos: Dictionary = data.get("position", {})
	position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	var vel: Dictionary = data.get("velocity", {})
	velocity = Vector3(vel.get("x", 0), vel.get("y", 0), vel.get("z", 0))

	rotation = data.get("rotation", 0.0)
	current_health = data.get("current_health", MAX_HEALTH)
	is_alive = data.get("is_alive", true)
	_current_cargo = data.get("current_cargo", 0.0)
	_is_loaded = data.get("is_loaded", false)
	_current_state = data.get("current_state", State.IDLE)
	_assigned_factory_id = data.get("assigned_factory_id", -1)

	var factory_pos: Dictionary = data.get("assigned_factory_position", {})
	_assigned_factory_position = Vector3(
		factory_pos.get("x", 0),
		factory_pos.get("y", 0),
		factory_pos.get("z", 0)
	)

	var pickup: Dictionary = data.get("pickup_target", {})
	_pickup_target = Vector3(pickup.get("x", 0), pickup.get("y", 0), pickup.get("z", 0))

	attack_cooldown_timer = data.get("attack_cooldown", 0.0)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> HaulforgeUnit:
	var unit := HaulforgeUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_haulforge",
		"faction_key": "logibots_colossus",
		"unit_type": "haulforge",
		"display_name": "Haulforge",
		"description": "Massive heavy lifter that carries 500 REE per trip. Slower when loaded but essential for bulk transport operations.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.0,
			"max_speed": BASE_MOVEMENT_SPEED * 10.0,
			"acceleration": 15.0,
			"turn_rate": 1.5,
			"armor": ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 1.0 / ATTACK_COOLDOWN,
			"attack_range": 6.0,
			"vision_range": 12.0
		},
		"production_cost": {
			"ree": 300,
			"energy": 60,
			"time": 18.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/haulforge.tres",
			"material_path": "res://assets/materials/logibots/haulforge_mat.tres",
			"scale": [2.0, 2.0, 2.0],
			"use_multimesh": true,
			"lod_distances": [50.0, 100.0, 200.0]
		},
		"ai_behavior": {
			"behavior_type": "transport",
			"aggro_range": 5.0,
			"flee_health_percent": 0.2,
			"preferred_target": "",
			"formation_type": "none"
		},
		"abilities": ["heavy_lift"],
		"tags": ["transport", "heavy", "industrial", "logibots", "cargo"]
	}
