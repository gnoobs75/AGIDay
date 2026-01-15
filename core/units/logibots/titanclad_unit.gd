class_name TitancladUnit
extends RefCounted
## TitancladUnit is the LogiBots Colossus walking fortress.
## Provides area protection with Fortress Stance that boosts armor and protects allies.

signal attack_hit(target_id: int, damage: float)
signal fortress_stance_activated(position: Vector3, radius: float)
signal fortress_stance_deactivated()
signal ally_protected(ally_id: int, damage_reduction: float)
signal armor_regenerating(current: float, max: float)
signal armor_damaged(stage: int, percent: float)

## Unit stats
const MAX_HEALTH := 400.0
const BASE_MOVEMENT_SPEED := 0.5
const FORTRESS_MOVEMENT_SPEED := 0.2
const BASE_ARMOR := 100.0
const ATTACK_COOLDOWN := 15.0
const BASE_DAMAGE := 40.0
const ATTACK_RANGE := 5.0

## Fortress Stance configuration
const FORTRESS_ARMOR_BONUS := 0.5           ## 50% more armor
const FORTRESS_ALLY_RADIUS := 15.0
const FORTRESS_ALLY_DAMAGE_REDUCTION := 0.2 ## 20% damage reduction
const FORTRESS_ACTIVATION_TIME := 1.0       ## Time to enter stance
const FORTRESS_DEACTIVATION_TIME := 0.5

## Armor regeneration (slow, needs repair units for faster)
const ARMOR_REGEN_RATE := 0.5               ## HP per second
const ARMOR_REGEN_DELAY := 10.0             ## Seconds after taking damage
const REPAIR_UNIT_BONUS := 5.0              ## Additional HP/s per repair unit

## Armor degradation stages
enum ArmorStage { PRISTINE, DAMAGED, CRITICAL, BROKEN }
const ARMOR_STAGE_THRESHOLDS := {
	ArmorStage.PRISTINE: 1.0,
	ArmorStage.DAMAGED: 0.75,
	ArmorStage.CRITICAL: 0.5,
	ArmorStage.BROKEN: 0.25
}
const ARMOR_STAGE_MULTIPLIERS := {
	ArmorStage.PRISTINE: 1.0,
	ArmorStage.DAMAGED: 0.9,
	ArmorStage.CRITICAL: 0.7,
	ArmorStage.BROKEN: 0.4
}

## Unit data
var unit_id: int = -1
var faction_id: int = 0
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var rotation: float = 0.0

## Health and armor
var current_health: float = MAX_HEALTH
var current_armor_stage: ArmorStage = ArmorStage.PRISTINE
var is_alive: bool = true

## Fortress Stance state
var _fortress_stance_active: bool = false
var _fortress_stance_timer: float = 0.0
var _protected_allies: Array[int] = []

## Armor regeneration
var _armor_regen_timer: float = 0.0
var _time_since_damage: float = 0.0
var _repair_units_nearby: int = 0

## Combat state
var attack_cooldown_timer: float = 0.0
var current_target_id: int = -1
var _is_attacking: bool = false
var _attack_animation_timer: float = 0.0

## Movement state
enum State { IDLE, MOVING, ATTACKING, ENTERING_FORTRESS, FORTRESS_ACTIVE, EXITING_FORTRESS, DEAD }
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
	current_armor_stage = ArmorStage.PRISTINE
	is_alive = true
	_current_state = State.IDLE
	_fortress_stance_active = false


## Update unit each frame.
func update(delta: float) -> void:
	if not is_alive:
		return

	# Update cooldowns
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

	# Update animation timer
	if _attack_animation_timer > 0:
		_attack_animation_timer -= delta
		if _attack_animation_timer <= 0:
			_is_attacking = false

	# Update armor regeneration
	_time_since_damage += delta
	if _time_since_damage >= ARMOR_REGEN_DELAY:
		_update_armor_regen(delta)

	# State machine
	match _current_state:
		State.IDLE:
			_update_idle(delta)
		State.MOVING:
			_update_moving(delta)
		State.ATTACKING:
			_update_attacking(delta)
		State.ENTERING_FORTRESS:
			_update_entering_fortress(delta)
		State.FORTRESS_ACTIVE:
			_update_fortress_active(delta)
		State.EXITING_FORTRESS:
			_update_exiting_fortress(delta)


## Get current movement speed.
func _get_current_speed() -> float:
	if _fortress_stance_active:
		return FORTRESS_MOVEMENT_SPEED * 10.0
	return BASE_MOVEMENT_SPEED * 10.0


## Update armor regeneration.
func _update_armor_regen(delta: float) -> void:
	if current_health >= MAX_HEALTH:
		return

	var regen_rate := ARMOR_REGEN_RATE + (_repair_units_nearby * REPAIR_UNIT_BONUS)
	var regen_amount := regen_rate * delta

	current_health = minf(current_health + regen_amount, MAX_HEALTH)
	_update_armor_stage()
	armor_regenerating.emit(current_health, MAX_HEALTH)


## Update idle state.
func _update_idle(_delta: float) -> void:
	pass


## Update movement.
func _update_moving(delta: float) -> void:
	var direction := (_movement_target - position).normalized()
	direction.y = 0

	if position.distance_to(_movement_target) > 2.0:
		velocity = direction * _get_current_speed()
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


## Update entering fortress stance.
func _update_entering_fortress(delta: float) -> void:
	_fortress_stance_timer += delta

	if _fortress_stance_timer >= FORTRESS_ACTIVATION_TIME:
		_fortress_stance_active = true
		_current_state = State.FORTRESS_ACTIVE
		fortress_stance_activated.emit(position, FORTRESS_ALLY_RADIUS)


## Update fortress active state.
func _update_fortress_active(_delta: float) -> void:
	# Can still attack while in fortress mode
	if current_target_id >= 0 and attack_cooldown_timer <= 0 and not _is_attacking:
		_perform_attack()


## Update exiting fortress stance.
func _update_exiting_fortress(delta: float) -> void:
	_fortress_stance_timer += delta

	if _fortress_stance_timer >= FORTRESS_DEACTIVATION_TIME:
		_fortress_stance_active = false
		_current_state = State.IDLE
		fortress_stance_deactivated.emit()


## Perform basic attack.
func _perform_attack() -> void:
	_is_attacking = true
	_attack_animation_timer = 0.6
	attack_cooldown_timer = ATTACK_COOLDOWN

	attack_hit.emit(current_target_id, BASE_DAMAGE)


## Toggle Fortress Stance.
func toggle_fortress_stance() -> bool:
	if not is_alive:
		return false

	if _fortress_stance_active:
		# Deactivate
		_fortress_stance_timer = 0.0
		_current_state = State.EXITING_FORTRESS
		_protected_allies.clear()
		return true
	else:
		# Activate
		if _current_state == State.MOVING:
			return false
		_fortress_stance_timer = 0.0
		_current_state = State.ENTERING_FORTRESS
		return true


## Get effective armor (with fortress bonus).
func _get_effective_armor() -> float:
	var base: float = BASE_ARMOR * ARMOR_STAGE_MULTIPLIERS[current_armor_stage]
	if _fortress_stance_active:
		base *= (1.0 + FORTRESS_ARMOR_BONUS)
	return base


## Calculate damage reduction for ally in range.
func get_ally_protection(ally_position: Vector3) -> float:
	if not _fortress_stance_active:
		return 0.0

	var distance := position.distance_to(ally_position)
	if distance <= FORTRESS_ALLY_RADIUS:
		return FORTRESS_ALLY_DAMAGE_REDUCTION
	return 0.0


## Register ally as protected.
func register_protected_ally(ally_id: int) -> void:
	if ally_id not in _protected_allies:
		_protected_allies.append(ally_id)
		ally_protected.emit(ally_id, FORTRESS_ALLY_DAMAGE_REDUCTION)


## Unregister ally.
func unregister_protected_ally(ally_id: int) -> void:
	var idx := _protected_allies.find(ally_id)
	if idx >= 0:
		_protected_allies.remove_at(idx)


## Set repair units nearby.
func set_repair_units_nearby(count: int) -> void:
	_repair_units_nearby = count


## Update armor stage based on health.
func _update_armor_stage() -> void:
	var health_percent := current_health / MAX_HEALTH
	var old_stage := current_armor_stage

	if health_percent > ARMOR_STAGE_THRESHOLDS[ArmorStage.DAMAGED]:
		current_armor_stage = ArmorStage.PRISTINE
	elif health_percent > ARMOR_STAGE_THRESHOLDS[ArmorStage.CRITICAL]:
		current_armor_stage = ArmorStage.DAMAGED
	elif health_percent > ARMOR_STAGE_THRESHOLDS[ArmorStage.BROKEN]:
		current_armor_stage = ArmorStage.CRITICAL
	else:
		current_armor_stage = ArmorStage.BROKEN

	if current_armor_stage != old_stage:
		armor_damaged.emit(current_armor_stage, health_percent)


## Move to position.
func move_to(target: Vector3) -> void:
	if not is_alive:
		return

	if _fortress_stance_active:
		# Can move slowly in fortress mode
		_movement_target = target
		_current_state = State.FORTRESS_ACTIVE
	else:
		_movement_target = target
		_current_state = State.MOVING


## Attack target.
func attack_target(target_id: int) -> void:
	if not is_alive:
		return

	current_target_id = target_id
	if not _fortress_stance_active:
		_current_state = State.ATTACKING


## Apply damage to unit.
func take_damage(amount: float, _source_id: int = -1) -> float:
	var armor := _get_effective_armor()
	var damage_reduction := armor / (armor + 100.0)
	var actual_damage := amount * (1.0 - damage_reduction)

	current_health -= actual_damage
	_time_since_damage = 0.0  # Reset regen timer
	_update_armor_stage()

	if current_health <= 0:
		current_health = 0
		_die()

	return actual_damage


## Handle death.
func _die() -> void:
	is_alive = false
	_current_state = State.DEAD
	_fortress_stance_active = false
	_protected_allies.clear()
	velocity = Vector3.ZERO
	fortress_stance_deactivated.emit()


## Is in fortress stance.
func is_fortress_active() -> bool:
	return _fortress_stance_active


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.IDLE: return "Idle"
		State.MOVING: return "Moving"
		State.ATTACKING: return "Attacking"
		State.ENTERING_FORTRESS: return "Entering Fortress"
		State.FORTRESS_ACTIVE: return "Fortress Active"
		State.EXITING_FORTRESS: return "Exiting Fortress"
		State.DEAD: return "Dead"
	return "Unknown"


## Get armor stage name.
func get_armor_stage_name() -> String:
	match current_armor_stage:
		ArmorStage.PRISTINE: return "Pristine"
		ArmorStage.DAMAGED: return "Damaged"
		ArmorStage.CRITICAL: return "Critical"
		ArmorStage.BROKEN: return "Broken"
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
		"unit_type": "titanclad",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"armor_stage": get_armor_stage_name(),
		"effective_armor": _get_effective_armor(),
		"fortress_active": _fortress_stance_active,
		"protected_allies": _protected_allies.size(),
		"repair_units": _repair_units_nearby,
		"time_since_damage": _time_since_damage,
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
		"current_armor_stage": current_armor_stage,
		"is_alive": is_alive,
		"current_state": _current_state,
		"fortress_stance_active": _fortress_stance_active,
		"fortress_stance_timer": _fortress_stance_timer,
		"protected_allies": _protected_allies.duplicate(),
		"time_since_damage": _time_since_damage,
		"attack_cooldown": attack_cooldown_timer,
		"current_target_id": current_target_id
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
	current_armor_stage = data.get("current_armor_stage", ArmorStage.PRISTINE)
	is_alive = data.get("is_alive", true)
	_current_state = data.get("current_state", State.IDLE)
	_fortress_stance_active = data.get("fortress_stance_active", false)
	_fortress_stance_timer = data.get("fortress_stance_timer", 0.0)
	_time_since_damage = data.get("time_since_damage", 0.0)
	attack_cooldown_timer = data.get("attack_cooldown", 0.0)
	current_target_id = data.get("current_target_id", -1)

	var allies: Array = data.get("protected_allies", [])
	_protected_allies.clear()
	for ally_id in allies:
		_protected_allies.append(ally_id)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> TitancladUnit:
	var unit := TitancladUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_titanclad",
		"faction_key": "logibots_colossus",
		"unit_type": "titanclad",
		"display_name": "Titanclad",
		"description": "Walking fortress that can enter Fortress Stance to protect nearby allies and massively increase armor.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": ARMOR_REGEN_RATE,
			"max_speed": BASE_MOVEMENT_SPEED * 10.0,
			"acceleration": 10.0,
			"turn_rate": 1.5,
			"armor": BASE_ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 1.0 / ATTACK_COOLDOWN,
			"attack_range": ATTACK_RANGE,
			"vision_range": 20.0
		},
		"production_cost": {
			"ree": 500,
			"energy": 100,
			"time": 30.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/titanclad.tres",
			"material_path": "res://assets/materials/logibots/titanclad_mat.tres",
			"scale": [2.5, 2.5, 2.5],
			"use_multimesh": false,
			"lod_distances": [80.0, 160.0, 280.0]
		},
		"ai_behavior": {
			"behavior_type": "defensive",
			"aggro_range": 18.0,
			"flee_health_percent": 0.0,
			"preferred_target": "",
			"formation_type": "fortress"
		},
		"abilities": ["fortress_stance"],
		"tags": ["heavy", "tank", "defensive", "aura", "logibots"],
		"uses_heavy_physics": true
	}
