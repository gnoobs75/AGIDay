class_name HarvesterUnit
extends RefCounted
## HarvesterUnit handles resource collection through building disassembly and wreck harvesting.
## Weak combat stats but critical for economy - high-value targets.

signal harvesting_started(target_type: String, target_position: Vector3)
signal harvesting_completed(ree_amount: float, target_type: String)
signal harvesting_cancelled(reason: String)
signal ree_collected(amount: float, total: float)
signal threat_detected(threat_level: float, enemies: Array[int])
signal fleeing_started(direction: Vector3)
signal fleeing_ended()
signal target_acquired(target_position: Vector3, target_type: String)
signal state_changed(old_state: int, new_state: int)

## Unit stats (weak combat)
const MAX_HEALTH := 20.0
const MOVEMENT_SPEED := 6.0
const BASE_ARMOR := 0.0
const ATTACK_COOLDOWN := 2.0         ## 0.5 attack speed
const BASE_DAMAGE := 1.0
const ATTACK_RANGE := 3.0

## Harvesting configuration
const SEARCH_RADIUS := 50.0          ## Range to search for targets
const THREAT_THRESHOLD := 0.3        ## 30% threat triggers fleeing
const FLEE_DISTANCE := 30.0          ## Distance to flee from threats
const HARVEST_RANGE := 2.0           ## Must be within this to harvest

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
var current_target_id: int = -1

## Harvester state
enum State { IDLE, SEARCHING, MOVING_TO_TARGET, HARVESTING, FLEEING, DEFENDING, DEAD }
var _current_state: State = State.IDLE
var _movement_target: Vector3 = Vector3.ZERO

## Harvest target
var _harvest_target_position: Vector3 = Vector3.ZERO
var _harvest_target_type: String = ""  ## "building", "wreck", etc.
var _harvest_target_id: int = -1
var _harvest_progress: float = 0.0
var _harvest_duration: float = 0.0
var _harvest_yield: float = 0.0

## Cargo
var _current_ree: float = 0.0
const MAX_REE_CARGO := 500.0

## Threat assessment
var _current_threat_level: float = 0.0
var _threat_enemies: Array[int] = []
var _flee_direction: Vector3 = Vector3.ZERO


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
	_current_ree = 0.0


## Update unit each frame.
func update(delta: float) -> void:
	if not is_alive:
		return

	# Update attack cooldown
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

	# Check threats
	if _current_state != State.FLEEING:
		_check_threats()

	# State machine
	match _current_state:
		State.IDLE:
			_update_idle(delta)
		State.SEARCHING:
			_update_searching(delta)
		State.MOVING_TO_TARGET:
			_update_moving_to_target(delta)
		State.HARVESTING:
			_update_harvesting(delta)
		State.FLEEING:
			_update_fleeing(delta)
		State.DEFENDING:
			_update_defending(delta)


## Check for threats and decide if need to flee.
func _check_threats() -> void:
	if _current_threat_level >= THREAT_THRESHOLD:
		_start_fleeing()


## Update idle state.
func _update_idle(_delta: float) -> void:
	# Transition to searching
	_set_state(State.SEARCHING)


## Update searching state.
func _update_searching(_delta: float) -> void:
	# Would be populated by game system with nearby targets
	pass


## Update moving to target.
func _update_moving_to_target(delta: float) -> void:
	var direction := (_harvest_target_position - position).normalized()
	direction.y = 0

	if position.distance_to(_harvest_target_position) > HARVEST_RANGE:
		velocity = direction * MOVEMENT_SPEED
		position += velocity * delta
		rotation = atan2(direction.x, direction.z)
	else:
		velocity = Vector3.ZERO
		_start_harvesting()


## Update harvesting state.
func _update_harvesting(delta: float) -> void:
	_harvest_progress += delta

	if _harvest_progress >= _harvest_duration:
		_complete_harvesting()


## Update fleeing state.
func _update_fleeing(delta: float) -> void:
	var flee_target := position + _flee_direction * FLEE_DISTANCE

	if position.distance_to(flee_target) > 2.0:
		velocity = _flee_direction * MOVEMENT_SPEED * 1.2  # Flee faster
		position += velocity * delta
		rotation = atan2(_flee_direction.x, _flee_direction.z)
	else:
		velocity = Vector3.ZERO
		_stop_fleeing()


## Update defending state.
func _update_defending(delta: float) -> void:
	if current_target_id < 0 or _current_threat_level < 0.1:
		_set_state(State.IDLE)
		return

	if attack_cooldown_timer <= 0:
		attack_cooldown_timer = ATTACK_COOLDOWN
		# Would emit attack signal


## Start fleeing from threats.
func _start_fleeing() -> void:
	if _threat_enemies.is_empty():
		return

	# Calculate flee direction (away from threats)
	var threat_center := Vector3.ZERO
	for _enemy_id in _threat_enemies:
		# Would get enemy positions
		pass

	_flee_direction = (position - threat_center).normalized()
	_flee_direction.y = 0
	if _flee_direction.length_squared() < 0.01:
		_flee_direction = Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()

	_set_state(State.FLEEING)
	fleeing_started.emit(_flee_direction)

	# Cancel any active harvesting
	if _harvest_progress > 0:
		harvesting_cancelled.emit("threat_detected")
		_harvest_progress = 0.0


## Stop fleeing.
func _stop_fleeing() -> void:
	_set_state(State.IDLE)
	fleeing_ended.emit()


## Start harvesting current target.
func _start_harvesting() -> void:
	_set_state(State.HARVESTING)
	_harvest_progress = 0.0
	harvesting_started.emit(_harvest_target_type, _harvest_target_position)


## Complete harvesting.
func _complete_harvesting() -> void:
	var collected := minf(_harvest_yield, MAX_REE_CARGO - _current_ree)
	_current_ree += collected

	ree_collected.emit(collected, _current_ree)
	harvesting_completed.emit(collected, _harvest_target_type)

	# Reset harvest state
	_harvest_progress = 0.0
	_harvest_target_id = -1
	_harvest_target_type = ""

	_set_state(State.IDLE)


## Set target for harvesting.
func set_harvest_target(target_id: int, target_pos: Vector3, target_type: String,
						duration: float, ree_yield: float) -> void:
	_harvest_target_id = target_id
	_harvest_target_position = target_pos
	_harvest_target_type = target_type
	_harvest_duration = duration
	_harvest_yield = ree_yield

	target_acquired.emit(target_pos, target_type)
	_set_state(State.MOVING_TO_TARGET)


## Update threat assessment.
func update_threat_assessment(threat_level: float, enemy_ids: Array[int]) -> void:
	_current_threat_level = threat_level
	_threat_enemies = enemy_ids.duplicate()

	if threat_level > 0:
		threat_detected.emit(threat_level, enemy_ids)


## Move to position.
func move_to(target: Vector3) -> void:
	if not is_alive:
		return

	_movement_target = target
	_harvest_target_position = target
	_set_state(State.MOVING_TO_TARGET)


## Force return to base with cargo.
func return_to_base(base_position: Vector3) -> void:
	_harvest_target_position = base_position
	_harvest_target_type = "return"
	_set_state(State.MOVING_TO_TARGET)


## Deposit REE cargo.
func deposit_ree() -> float:
	var deposited := _current_ree
	_current_ree = 0.0
	return deposited


## Set state with signal.
func _set_state(new_state: State) -> void:
	if new_state == _current_state:
		return
	var old_state := _current_state
	_current_state = new_state
	state_changed.emit(old_state, new_state)


## Apply damage to unit.
func take_damage(amount: float, _source_id: int = -1) -> float:
	var actual_damage := amount  # No armor
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


## Get current REE cargo.
func get_cargo() -> float:
	return _current_ree


## Get cargo percentage.
func get_cargo_percentage() -> float:
	return _current_ree / MAX_REE_CARGO


## Is carrying cargo.
func has_cargo() -> bool:
	return _current_ree > 0


## Get harvest progress.
func get_harvest_progress() -> float:
	if _harvest_duration <= 0:
		return 0.0
	return _harvest_progress / _harvest_duration


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.IDLE: return "Idle"
		State.SEARCHING: return "Searching"
		State.MOVING_TO_TARGET: return "Moving"
		State.HARVESTING: return "Harvesting"
		State.FLEEING: return "Fleeing"
		State.DEFENDING: return "Defending"
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
		"unit_type": "harvester",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"cargo_ree": _current_ree,
		"max_cargo": MAX_REE_CARGO,
		"cargo_percent": get_cargo_percentage(),
		"harvest_progress": get_harvest_progress(),
		"harvest_target_type": _harvest_target_type,
		"threat_level": _current_threat_level,
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
		"current_ree": _current_ree,
		"harvest_target_position": {
			"x": _harvest_target_position.x,
			"y": _harvest_target_position.y,
			"z": _harvest_target_position.z
		},
		"harvest_target_type": _harvest_target_type,
		"harvest_target_id": _harvest_target_id,
		"harvest_progress": _harvest_progress,
		"harvest_duration": _harvest_duration,
		"harvest_yield": _harvest_yield,
		"current_threat_level": _current_threat_level
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
	_current_ree = data.get("current_ree", 0.0)

	var target_pos: Dictionary = data.get("harvest_target_position", {})
	_harvest_target_position = Vector3(
		target_pos.get("x", 0),
		target_pos.get("y", 0),
		target_pos.get("z", 0)
	)

	_harvest_target_type = data.get("harvest_target_type", "")
	_harvest_target_id = data.get("harvest_target_id", -1)
	_harvest_progress = data.get("harvest_progress", 0.0)
	_harvest_duration = data.get("harvest_duration", 0.0)
	_harvest_yield = data.get("harvest_yield", 0.0)
	_current_threat_level = data.get("current_threat_level", 0.0)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> HarvesterUnit:
	var unit := HarvesterUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "harvester",
		"faction_key": "",  # Can be any faction
		"unit_type": "harvester",
		"display_name": "Harvester",
		"description": "Weak but critical resource gathering unit. Collects REE from destroyed buildings and wrecks.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.0,
			"max_speed": MOVEMENT_SPEED,
			"acceleration": 30.0,
			"turn_rate": 5.0,
			"armor": BASE_ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 0.5,
			"attack_range": ATTACK_RANGE,
			"vision_range": 15.0
		},
		"production_cost": {
			"ree": 100,
			"energy": 15,
			"time": 8.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/common/harvester.tres",
			"material_path": "res://assets/materials/common/harvester_mat.tres",
			"scale": [1.0, 1.0, 1.0],
			"use_multimesh": true,
			"lod_distances": [40.0, 80.0, 160.0]
		},
		"ai_behavior": {
			"behavior_type": "gatherer",
			"aggro_range": 5.0,
			"flee_health_percent": 0.5,
			"preferred_target": "wreck",
			"formation_type": "none"
		},
		"abilities": ["harvest", "disassemble"],
		"tags": ["harvester", "gatherer", "economy", "weak"]
	}
