class_name BulkripperUnit
extends RefCounted
## BulkripperUnit is the LogiBots Colossus claw-digger for efficient REE collection.
## Specialized for resource gathering with 2x collection rate and defensive capabilities.

signal ree_collected(amount: float, source_position: Vector3)
signal collection_started(target_position: Vector3)
signal collection_completed(total_collected: float)
signal cargo_changed(current: float, max: float)
signal returning_to_factory(factory_id: int)

## Unit stats
const MAX_HEALTH := 150.0
const MOVEMENT_SPEED := 0.8
const ARMOR := 40.0
const ATTACK_COOLDOWN := 8.0
const BASE_DAMAGE := 25.0

## Claw Dig ability configuration
const COLLECTION_RADIUS := 10.0
const COLLECTION_RATE_MULTIPLIER := 2.0
const BASE_COLLECTION_RATE := 5.0       ## REE per second
const MAX_CARGO := 200.0                ## REE capacity
const COLLECTION_TICK_RATE := 0.5       ## Seconds between collection ticks

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

## Resource collection state
var _current_cargo: float = 0.0
var _is_collecting: bool = false
var _collection_timer: float = 0.0
var _collection_target: Vector3 = Vector3.ZERO
var _assigned_factory_id: int = -1

## Movement state
enum State { IDLE, MOVING, COLLECTING, RETURNING, ATTACKING, DEAD }
var _current_state: State = State.IDLE
var _movement_target: Vector3 = Vector3.ZERO


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
		State.MOVING:
			_update_moving(delta)
		State.COLLECTING:
			_update_collecting(delta)
		State.RETURNING:
			_update_returning(delta)
		State.ATTACKING:
			_update_attacking(delta)


## Update idle state.
func _update_idle(_delta: float) -> void:
	pass


## Update movement.
func _update_moving(delta: float) -> void:
	var direction := (_movement_target - position).normalized()
	direction.y = 0  # Keep on ground plane

	if position.distance_to(_movement_target) > 1.0:
		velocity = direction * MOVEMENT_SPEED * 10.0
		position += velocity * delta
		rotation = atan2(direction.x, direction.z)
	else:
		velocity = Vector3.ZERO
		_current_state = State.IDLE


## Update collection state.
func _update_collecting(delta: float) -> void:
	_collection_timer += delta

	if _collection_timer >= COLLECTION_TICK_RATE:
		_collection_timer = 0.0

		var collected := _perform_collection_tick()
		if collected > 0:
			ree_collected.emit(collected, _collection_target)

		# Check if cargo full
		if _current_cargo >= MAX_CARGO:
			_start_return_to_factory()


## Perform a single collection tick.
func _perform_collection_tick() -> float:
	var collection_amount := BASE_COLLECTION_RATE * COLLECTION_RATE_MULTIPLIER * COLLECTION_TICK_RATE
	var space_available := MAX_CARGO - _current_cargo
	var actual_collected := minf(collection_amount, space_available)

	_current_cargo += actual_collected
	cargo_changed.emit(_current_cargo, MAX_CARGO)

	return actual_collected


## Update returning to factory.
func _update_returning(delta: float) -> void:
	var direction := (_movement_target - position).normalized()
	direction.y = 0

	if position.distance_to(_movement_target) > 2.0:
		velocity = direction * MOVEMENT_SPEED * 10.0
		position += velocity * delta
		rotation = atan2(direction.x, direction.z)
	else:
		# Arrived at factory - deposit cargo
		var deposited := _current_cargo
		_current_cargo = 0.0
		cargo_changed.emit(_current_cargo, MAX_CARGO)
		collection_completed.emit(deposited)
		_current_state = State.IDLE


## Update attacking state.
func _update_attacking(delta: float) -> void:
	if current_target_id < 0:
		_current_state = State.IDLE
		return

	# Would check target validity and attack when cooldown ready
	if attack_cooldown_timer <= 0:
		attack_cooldown_timer = ATTACK_COOLDOWN


## Start collecting at position.
func start_collection(target_position: Vector3) -> void:
	if not is_alive:
		return

	_collection_target = target_position
	_collection_timer = 0.0

	# Move to collection site first if not in range
	if position.distance_to(target_position) > COLLECTION_RADIUS:
		_movement_target = target_position
		_current_state = State.MOVING
	else:
		_current_state = State.COLLECTING
		_is_collecting = true
		collection_started.emit(target_position)


## Stop collecting.
func stop_collection() -> void:
	_is_collecting = false
	if _current_state == State.COLLECTING:
		_current_state = State.IDLE


## Start returning to factory.
func _start_return_to_factory() -> void:
	if _assigned_factory_id < 0:
		return

	_is_collecting = false
	_current_state = State.RETURNING
	returning_to_factory.emit(_assigned_factory_id)


## Set factory to return to.
func assign_factory(factory_id: int, factory_position: Vector3) -> void:
	_assigned_factory_id = factory_id
	_movement_target = factory_position


## Force return to factory.
func return_to_factory() -> void:
	if _assigned_factory_id >= 0:
		_start_return_to_factory()


## Move to position.
func move_to(target: Vector3) -> void:
	if not is_alive:
		return

	_movement_target = target
	_current_state = State.MOVING


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
	_is_collecting = false
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


## Is currently collecting.
func is_collecting() -> bool:
	return _is_collecting


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.IDLE: return "Idle"
		State.MOVING: return "Moving"
		State.COLLECTING: return "Collecting"
		State.RETURNING: return "Returning"
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
		"unit_type": "bulkripper",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"cargo": _current_cargo,
		"max_cargo": MAX_CARGO,
		"cargo_percent": get_cargo_percentage(),
		"is_collecting": _is_collecting,
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
		"current_state": _current_state,
		"is_collecting": _is_collecting,
		"collection_target": {"x": _collection_target.x, "y": _collection_target.y, "z": _collection_target.z},
		"assigned_factory_id": _assigned_factory_id,
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
	_current_state = data.get("current_state", State.IDLE)
	_is_collecting = data.get("is_collecting", false)

	var target: Dictionary = data.get("collection_target", {})
	_collection_target = Vector3(target.get("x", 0), target.get("y", 0), target.get("z", 0))

	_assigned_factory_id = data.get("assigned_factory_id", -1)
	attack_cooldown_timer = data.get("attack_cooldown", 0.0)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> BulkripperUnit:
	var unit := BulkripperUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_bulkripper",
		"faction_key": "logibots_colossus",
		"unit_type": "bulkripper",
		"display_name": "Bulkripper",
		"description": "Heavy claw-digger that efficiently extracts REE from destruction sites at double the normal rate.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.0,
			"max_speed": MOVEMENT_SPEED * 10.0,
			"acceleration": 20.0,
			"turn_rate": 2.0,
			"armor": ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 1.0 / ATTACK_COOLDOWN,
			"attack_range": 5.0,
			"vision_range": 15.0
		},
		"production_cost": {
			"ree": 200,
			"energy": 40,
			"time": 12.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/bulkripper.tres",
			"material_path": "res://assets/materials/logibots/bulkripper_mat.tres",
			"scale": [1.5, 1.5, 1.5],
			"use_multimesh": true,
			"lod_distances": [50.0, 100.0, 200.0]
		},
		"ai_behavior": {
			"behavior_type": "gatherer",
			"aggro_range": 8.0,
			"flee_health_percent": 0.15,
			"preferred_target": "",
			"formation_type": "none"
		},
		"abilities": ["claw_dig"],
		"tags": ["gatherer", "heavy", "industrial", "logibots"]
	}
