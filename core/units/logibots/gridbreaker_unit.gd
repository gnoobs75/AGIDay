class_name GridbreakerUnit
extends RefCounted
## GridbreakerUnit is the LogiBots Colossus power grid disruptor.
## Specializes in targeting power nodes to create blackouts affecting enemy districts.

signal attack_hit(target_id: int, damage: float)
signal power_surge_activated(target_node: Vector3)
signal blackout_started(affected_districts: Array[int], duration: float)
signal blackout_ended(affected_districts: Array[int])
signal power_node_targeted(node_position: Vector3)
signal ability_cooldown_changed(ability: String, remaining: float)

## Unit stats
const MAX_HEALTH := 100.0
const MOVEMENT_SPEED := 1.0
const BASE_ARMOR := 20.0
const ATTACK_COOLDOWN := 5.0
const BASE_DAMAGE := 20.0
const ATTACK_RANGE := 8.0

## Power Surge ability configuration
const POWER_SURGE_COOLDOWN := 15.0
const POWER_SURGE_RANGE := 25.0
const BLACKOUT_DURATION := 30.0         ## Seconds of blackout
const BLACKOUT_PROPAGATION_TIME := 0.1  ## 100ms propagation
const POWER_SURGE_ANIMATION_TIME := 1.0

## Unit data
var unit_id: int = -1
var faction_id: int = 0
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var rotation: float = 0.0

## Health
var current_health: float = MAX_HEALTH
var is_alive: bool = true

## Combat state
var attack_cooldown_timer: float = 0.0
var power_surge_cooldown_timer: float = 0.0
var current_target_id: int = -1
var _is_attacking: bool = false
var _attack_animation_timer: float = 0.0

## Power Surge state
var _targeted_power_node: Vector3 = Vector3.ZERO
var _active_blackouts: Dictionary = {}  ## district_id -> remaining_time

## Movement state
enum State { IDLE, MOVING, ATTACKING, USING_ABILITY, DEAD }
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


## Update unit each frame.
func update(delta: float) -> void:
	if not is_alive:
		return

	# Update cooldowns
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta
		if attack_cooldown_timer <= 0:
			ability_cooldown_changed.emit("attack", 0.0)

	if power_surge_cooldown_timer > 0:
		power_surge_cooldown_timer -= delta
		if power_surge_cooldown_timer <= 0:
			ability_cooldown_changed.emit("power_surge", 0.0)

	# Update animation timer
	if _attack_animation_timer > 0:
		_attack_animation_timer -= delta
		if _attack_animation_timer <= 0:
			_is_attacking = false
			if _current_state == State.USING_ABILITY:
				_current_state = State.IDLE

	# Update active blackouts
	_update_blackouts(delta)

	# State machine
	match _current_state:
		State.IDLE:
			_update_idle(delta)
		State.MOVING:
			_update_moving(delta)
		State.ATTACKING:
			_update_attacking(delta)
		State.USING_ABILITY:
			_update_ability(delta)


## Update active blackouts.
func _update_blackouts(delta: float) -> void:
	var expired_districts: Array[int] = []

	for district_id in _active_blackouts:
		_active_blackouts[district_id] -= delta
		if _active_blackouts[district_id] <= 0:
			expired_districts.append(district_id)

	if not expired_districts.is_empty():
		for district_id in expired_districts:
			_active_blackouts.erase(district_id)
		blackout_ended.emit(expired_districts)


## Update idle state.
func _update_idle(_delta: float) -> void:
	pass


## Update movement.
func _update_moving(delta: float) -> void:
	var direction := (_movement_target - position).normalized()
	direction.y = 0

	if position.distance_to(_movement_target) > 1.0:
		velocity = direction * MOVEMENT_SPEED * 10.0
		position += velocity * delta
		rotation = atan2(direction.x, direction.z)
	else:
		velocity = Vector3.ZERO
		_current_state = State.IDLE


## Update attacking state.
func _update_attacking(_delta: float) -> void:
	if current_target_id < 0:
		_current_state = State.IDLE
		return

	if attack_cooldown_timer <= 0 and not _is_attacking:
		_perform_attack()


## Update ability state.
func _update_ability(_delta: float) -> void:
	pass


## Perform basic attack.
func _perform_attack() -> void:
	_is_attacking = true
	_attack_animation_timer = 0.4
	attack_cooldown_timer = ATTACK_COOLDOWN

	attack_hit.emit(current_target_id, BASE_DAMAGE)
	ability_cooldown_changed.emit("attack", ATTACK_COOLDOWN)


## Use Power Surge ability on power node.
func use_power_surge(power_node_position: Vector3) -> bool:
	if power_surge_cooldown_timer > 0 or not is_alive:
		return false

	if _current_state == State.USING_ABILITY:
		return false

	# Check range
	var distance := position.distance_to(power_node_position)
	if distance > POWER_SURGE_RANGE:
		return false

	_current_state = State.USING_ABILITY
	_is_attacking = true
	_attack_animation_timer = POWER_SURGE_ANIMATION_TIME
	power_surge_cooldown_timer = POWER_SURGE_COOLDOWN
	_targeted_power_node = power_node_position

	power_surge_activated.emit(power_node_position)
	ability_cooldown_changed.emit("power_surge", POWER_SURGE_COOLDOWN)

	return true


## Register blackout effect on districts.
func register_blackout(affected_district_ids: Array[int]) -> void:
	for district_id in affected_district_ids:
		_active_blackouts[district_id] = BLACKOUT_DURATION

	blackout_started.emit(affected_district_ids, BLACKOUT_DURATION)


## Get Power Surge effect data.
func get_power_surge_data() -> Dictionary:
	return {
		"caster_position": position,
		"target_position": _targeted_power_node,
		"blackout_duration": BLACKOUT_DURATION,
		"propagation_time": BLACKOUT_PROPAGATION_TIME,
		"range": POWER_SURGE_RANGE
	}


## Target a power node (for preview).
func target_power_node(node_position: Vector3) -> void:
	_targeted_power_node = node_position
	power_node_targeted.emit(node_position)


## Move to position.
func move_to(target: Vector3) -> void:
	if not is_alive or _is_attacking:
		return

	_movement_target = target
	_current_state = State.MOVING


## Attack target.
func attack_target(target_id: int) -> void:
	if not is_alive:
		return

	current_target_id = target_id
	_current_state = State.ATTACKING


## Stop attacking.
func stop_attacking() -> void:
	current_target_id = -1
	if _current_state == State.ATTACKING:
		_current_state = State.IDLE


## Get attack damage.
func get_damage() -> float:
	return BASE_DAMAGE


## Can attack right now.
func can_attack() -> bool:
	return attack_cooldown_timer <= 0 and is_alive and not _is_attacking


## Can use Power Surge.
func can_use_power_surge() -> bool:
	return power_surge_cooldown_timer <= 0 and is_alive and not _is_attacking


## Check if target is in Power Surge range.
func is_in_surge_range(target_pos: Vector3) -> bool:
	return position.distance_to(target_pos) <= POWER_SURGE_RANGE


## Get active blackout count.
func get_active_blackout_count() -> int:
	return _active_blackouts.size()


## Get blackout remaining time for district.
func get_blackout_remaining(district_id: int) -> float:
	return _active_blackouts.get(district_id, 0.0)


## Apply damage to unit.
func take_damage(amount: float, _source_id: int = -1) -> float:
	var damage_reduction := BASE_ARMOR / (BASE_ARMOR + 100.0)
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
	_is_attacking = false
	velocity = Vector3.ZERO


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.IDLE: return "Idle"
		State.MOVING: return "Moving"
		State.ATTACKING: return "Attacking"
		State.USING_ABILITY: return "Power Surge"
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
		"unit_type": "gridbreaker",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"attack_cooldown": attack_cooldown_timer,
		"power_surge_cooldown": power_surge_cooldown_timer,
		"active_blackouts": _active_blackouts.size(),
		"is_alive": is_alive
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
		"current_state": _current_state,
		"attack_cooldown": attack_cooldown_timer,
		"power_surge_cooldown": power_surge_cooldown_timer,
		"current_target_id": current_target_id,
		"active_blackouts": _active_blackouts.duplicate()
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
	_current_state = data.get("current_state", State.IDLE)
	attack_cooldown_timer = data.get("attack_cooldown", 0.0)
	power_surge_cooldown_timer = data.get("power_surge_cooldown", 0.0)
	current_target_id = data.get("current_target_id", -1)
	_active_blackouts = data.get("active_blackouts", {}).duplicate()


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> GridbreakerUnit:
	var unit := GridbreakerUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_gridbreaker",
		"faction_key": "logibots_colossus",
		"unit_type": "gridbreaker",
		"display_name": "Gridbreaker",
		"description": "Power grid disruptor that creates 30-second blackouts affecting enemy production and research.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.0,
			"max_speed": MOVEMENT_SPEED * 10.0,
			"acceleration": 25.0,
			"turn_rate": 3.5,
			"armor": BASE_ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 1.0 / ATTACK_COOLDOWN,
			"attack_range": ATTACK_RANGE,
			"vision_range": 18.0
		},
		"production_cost": {
			"ree": 180,
			"energy": 35,
			"time": 12.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/gridbreaker.tres",
			"material_path": "res://assets/materials/logibots/gridbreaker_mat.tres",
			"scale": [1.2, 1.2, 1.2],
			"use_multimesh": true,
			"lod_distances": [50.0, 100.0, 200.0]
		},
		"ai_behavior": {
			"behavior_type": "saboteur",
			"aggro_range": 10.0,
			"flee_health_percent": 0.3,
			"preferred_target": "power_node",
			"formation_type": "none"
		},
		"abilities": ["power_surge"],
		"tags": ["utility", "saboteur", "infrastructure", "logibots"]
	}
