class_name SiegehaulUnit
extends RefCounted
## SiegehaulUnit is the LogiBots Colossus long-range siege artillery.
## Specializes in structure destruction with Breach Shot for obstacle clearing.

signal attack_hit(target_id: int, damage: float, is_structure: bool)
signal breach_shot_fired(origin: Vector3, target: Vector3, damage: float)
signal obstacle_destroyed(position: Vector3)
signal voxel_destruction_requested(position: Vector3, radius: float, damage: float)
signal armor_damaged(stage: int, percent: float)
signal ability_cooldown_changed(ability: String, remaining: float)

## Unit stats
const MAX_HEALTH := 140.0
const MOVEMENT_SPEED := 0.7
const BASE_ARMOR := 35.0
const ATTACK_COOLDOWN := 8.0
const BASE_DAMAGE := 80.0
const STRUCTURE_DAMAGE := 150.0
const ATTACK_RANGE := 25.0
const MIN_ATTACK_RANGE := 8.0           ## Cannot attack targets too close

## Breach Shot ability
const BREACH_SHOT_COOLDOWN := 6.0
const BREACH_SHOT_DAMAGE := 120.0
const BREACH_SHOT_RADIUS := 4.0
const BREACH_SHOT_PROJECTILE_SPEED := 40.0
const BREACH_SHOT_ANIMATION_TIME := 1.2
const BREACH_SHOT_LINE_DESTRUCTION := true  ## Destroys obstacles in line

## Armor degradation stages
enum ArmorStage { PRISTINE, DAMAGED, CRITICAL, BROKEN }
const ARMOR_STAGE_THRESHOLDS := {
	ArmorStage.PRISTINE: 1.0,
	ArmorStage.DAMAGED: 0.7,
	ArmorStage.CRITICAL: 0.4,
	ArmorStage.BROKEN: 0.0
}
const ARMOR_STAGE_MULTIPLIERS := {
	ArmorStage.PRISTINE: 1.0,
	ArmorStage.DAMAGED: 0.85,
	ArmorStage.CRITICAL: 0.6,
	ArmorStage.BROKEN: 0.3
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

## Combat state
var attack_cooldown_timer: float = 0.0
var breach_shot_cooldown_timer: float = 0.0
var current_target_id: int = -1
var current_target_position: Vector3 = Vector3.ZERO
var _is_attacking: bool = false
var _attack_animation_timer: float = 0.0

## Movement state
enum State { IDLE, MOVING, ATTACKING, USING_ABILITY, REPOSITIONING, DEAD }
var _current_state: State = State.IDLE
var _movement_target: Vector3 = Vector3.ZERO

## Targeting
var _target_is_structure: bool = false
var _pending_breach_target: Vector3 = Vector3.ZERO


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


## Update unit each frame.
func update(delta: float) -> void:
	if not is_alive:
		return

	# Update cooldowns
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta
		if attack_cooldown_timer <= 0:
			ability_cooldown_changed.emit("attack", 0.0)

	if breach_shot_cooldown_timer > 0:
		breach_shot_cooldown_timer -= delta
		if breach_shot_cooldown_timer <= 0:
			ability_cooldown_changed.emit("breach_shot", 0.0)

	# Update animation timer
	if _attack_animation_timer > 0:
		_attack_animation_timer -= delta
		if _attack_animation_timer <= 0:
			_is_attacking = false
			if _current_state == State.USING_ABILITY:
				_current_state = State.IDLE

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
		State.REPOSITIONING:
			_update_repositioning(delta)


## Update idle state.
func _update_idle(_delta: float) -> void:
	pass


## Update movement.
func _update_moving(delta: float) -> void:
	var direction := (_movement_target - position).normalized()
	direction.y = 0

	if position.distance_to(_movement_target) > 2.0:
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

	# Check if target is in valid range
	var distance := position.distance_to(current_target_position)
	if distance < MIN_ATTACK_RANGE:
		# Too close, need to reposition
		_reposition_from_target()
		return

	if distance > ATTACK_RANGE:
		# Too far, move closer
		_movement_target = _calculate_attack_position(current_target_position)
		_current_state = State.MOVING
		return

	if attack_cooldown_timer <= 0 and not _is_attacking:
		_perform_attack()


## Calculate position to attack from.
func _calculate_attack_position(target_pos: Vector3) -> Vector3:
	var direction := (position - target_pos).normalized()
	var optimal_range := (MIN_ATTACK_RANGE + ATTACK_RANGE) * 0.5
	return target_pos + direction * optimal_range


## Reposition away from too-close target.
func _reposition_from_target() -> void:
	var direction := (position - current_target_position).normalized()
	_movement_target = position + direction * (MIN_ATTACK_RANGE + 5.0)
	_current_state = State.REPOSITIONING


## Update repositioning state.
func _update_repositioning(delta: float) -> void:
	var direction := (_movement_target - position).normalized()
	direction.y = 0

	if position.distance_to(_movement_target) > 1.0:
		velocity = direction * MOVEMENT_SPEED * 10.0
		position += velocity * delta
		rotation = atan2(direction.x, direction.z)
	else:
		velocity = Vector3.ZERO
		_current_state = State.ATTACKING


## Update ability state.
func _update_ability(_delta: float) -> void:
	pass


## Perform basic attack.
func _perform_attack() -> void:
	_is_attacking = true
	_attack_animation_timer = 0.6
	attack_cooldown_timer = ATTACK_COOLDOWN

	var damage := get_damage(_target_is_structure)
	attack_hit.emit(current_target_id, damage, _target_is_structure)
	ability_cooldown_changed.emit("attack", ATTACK_COOLDOWN)


## Use Breach Shot ability.
func use_breach_shot(target_position: Vector3) -> bool:
	if breach_shot_cooldown_timer > 0 or not is_alive:
		return false

	if _current_state == State.USING_ABILITY:
		return false

	# Check range
	var distance := position.distance_to(target_position)
	if distance < MIN_ATTACK_RANGE or distance > ATTACK_RANGE:
		return false

	_current_state = State.USING_ABILITY
	_is_attacking = true
	_attack_animation_timer = BREACH_SHOT_ANIMATION_TIME
	breach_shot_cooldown_timer = BREACH_SHOT_COOLDOWN
	_pending_breach_target = target_position

	# Fire the breach shot
	breach_shot_fired.emit(position, target_position, BREACH_SHOT_DAMAGE)

	# Request voxel destruction
	voxel_destruction_requested.emit(target_position, BREACH_SHOT_RADIUS, BREACH_SHOT_DAMAGE)

	# Destroy obstacles in line if enabled
	if BREACH_SHOT_LINE_DESTRUCTION:
		_destroy_obstacles_in_line(position, target_position)

	ability_cooldown_changed.emit("breach_shot", BREACH_SHOT_COOLDOWN)

	return true


## Destroy obstacles between attacker and target.
func _destroy_obstacles_in_line(start: Vector3, end: Vector3) -> void:
	var direction := (end - start).normalized()
	var distance := start.distance_to(end)
	var step := 3.0  # Check every 3 units

	var current_pos := start + direction * step
	var checked := step

	while checked < distance:
		obstacle_destroyed.emit(current_pos)
		current_pos += direction * step
		checked += step


## Get Breach Shot projectile data.
func get_breach_shot_data() -> Dictionary:
	return {
		"origin": position,
		"target": _pending_breach_target,
		"damage": BREACH_SHOT_DAMAGE,
		"radius": BREACH_SHOT_RADIUS,
		"speed": BREACH_SHOT_PROJECTILE_SPEED
	}


## Get effective armor.
func _get_effective_armor() -> float:
	return BASE_ARMOR * ARMOR_STAGE_MULTIPLIERS[current_armor_stage]


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
	if not is_alive or _is_attacking:
		return

	_movement_target = target
	_current_state = State.MOVING


## Attack target.
func attack_target(target_id: int, target_pos: Vector3, is_structure: bool = false) -> void:
	if not is_alive:
		return

	current_target_id = target_id
	current_target_position = target_pos
	_target_is_structure = is_structure
	_current_state = State.ATTACKING


## Stop attacking.
func stop_attacking() -> void:
	current_target_id = -1
	if _current_state == State.ATTACKING:
		_current_state = State.IDLE


## Get attack damage.
func get_damage(is_structure: bool = false) -> float:
	if is_structure:
		return STRUCTURE_DAMAGE
	return BASE_DAMAGE


## Can attack right now.
func can_attack() -> bool:
	return attack_cooldown_timer <= 0 and is_alive and not _is_attacking


## Can use Breach Shot.
func can_use_breach_shot() -> bool:
	return breach_shot_cooldown_timer <= 0 and is_alive and not _is_attacking


## Check if target is in valid attack range.
func is_in_attack_range(target_pos: Vector3) -> bool:
	var distance := position.distance_to(target_pos)
	return distance >= MIN_ATTACK_RANGE and distance <= ATTACK_RANGE


## Apply damage to unit.
func take_damage(amount: float, _source_id: int = -1) -> float:
	var armor := _get_effective_armor()
	var damage_reduction := armor / (armor + 100.0)
	var actual_damage := amount * (1.0 - damage_reduction)

	current_health -= actual_damage
	_update_armor_stage()

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
		State.USING_ABILITY: return "Breach Shot"
		State.REPOSITIONING: return "Repositioning"
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
		"unit_type": "siegehaul",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"armor_stage": get_armor_stage_name(),
		"effective_armor": _get_effective_armor(),
		"attack_cooldown": attack_cooldown_timer,
		"breach_shot_cooldown": breach_shot_cooldown_timer,
		"attack_range": ATTACK_RANGE,
		"min_range": MIN_ATTACK_RANGE,
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
		"attack_cooldown": attack_cooldown_timer,
		"breach_shot_cooldown": breach_shot_cooldown_timer,
		"current_target_id": current_target_id,
		"current_target_position": {
			"x": current_target_position.x,
			"y": current_target_position.y,
			"z": current_target_position.z
		},
		"target_is_structure": _target_is_structure
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
	attack_cooldown_timer = data.get("attack_cooldown", 0.0)
	breach_shot_cooldown_timer = data.get("breach_shot_cooldown", 0.0)
	current_target_id = data.get("current_target_id", -1)

	var target_pos: Dictionary = data.get("current_target_position", {})
	current_target_position = Vector3(
		target_pos.get("x", 0),
		target_pos.get("y", 0),
		target_pos.get("z", 0)
	)

	_target_is_structure = data.get("target_is_structure", false)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> SiegehaulUnit:
	var unit := SiegehaulUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_siegehaul",
		"faction_key": "logibots_colossus",
		"unit_type": "siegehaul",
		"display_name": "Siegehaul",
		"description": "Long-range artillery with devastating Breach Shot that destroys structures and clears obstacles in its path.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.0,
			"max_speed": MOVEMENT_SPEED * 10.0,
			"acceleration": 15.0,
			"turn_rate": 1.8,
			"armor": BASE_ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 1.0 / ATTACK_COOLDOWN,
			"attack_range": ATTACK_RANGE,
			"vision_range": 30.0
		},
		"production_cost": {
			"ree": 350,
			"energy": 70,
			"time": 20.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/siegehaul.tres",
			"material_path": "res://assets/materials/logibots/siegehaul_mat.tres",
			"scale": [1.6, 1.6, 1.6],
			"use_multimesh": false,
			"lod_distances": [70.0, 140.0, 260.0]
		},
		"ai_behavior": {
			"behavior_type": "artillery",
			"aggro_range": 25.0,
			"flee_health_percent": 0.25,
			"preferred_target": "structure",
			"formation_type": "rear"
		},
		"abilities": ["breach_shot"],
		"tags": ["artillery", "ranged", "siege", "structure_killer", "logibots"],
		"uses_heavy_physics": true
	}
