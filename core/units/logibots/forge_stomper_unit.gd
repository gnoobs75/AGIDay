class_name ForgeStomperUnit
extends RefCounted
## ForgeStomperUnit is the LogiBots Colossus heavy AoE tank.
## Specializes in Hammer Slam attacks with stun and shockwave effects.

signal attack_hit(target_id: int, damage: float)
signal hammer_slam_activated(position: Vector3, radius: float, damage: float)
signal stun_applied(target_ids: Array[int], duration: float)
signal shockwave_created(origin: Vector3, radius: float)
signal armor_damaged(stage: int, percent: float)
signal ability_cooldown_changed(ability: String, remaining: float)

## Unit stats
const MAX_HEALTH := 180.0
const MOVEMENT_SPEED := 0.9
const BASE_ARMOR := 50.0
const ATTACK_COOLDOWN := 12.0
const BASE_DAMAGE := 60.0
const ATTACK_RANGE := 4.0
const ATTACK_IS_AOE := true
const ATTACK_AOE_RADIUS := 4.0

## Hammer Slam ability
const HAMMER_SLAM_COOLDOWN := 10.0
const HAMMER_SLAM_DAMAGE := 100.0
const HAMMER_SLAM_RADIUS := 12.0
const HAMMER_SLAM_STUN_DURATION := 1.0
const HAMMER_SLAM_SHOCKWAVE_SPEED := 20.0
const HAMMER_SLAM_ANIMATION_TIME := 1.5

## Armor degradation stages (same as Crushkin for consistency)
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

## Performance degradation based on armor
const SPEED_DEGRADATION := {
	ArmorStage.PRISTINE: 1.0,
	ArmorStage.DAMAGED: 0.95,
	ArmorStage.CRITICAL: 0.85,
	ArmorStage.BROKEN: 0.7
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
var hammer_slam_cooldown_timer: float = 0.0
var current_target_id: int = -1
var _is_attacking: bool = false
var _attack_animation_timer: float = 0.0

## Movement state
enum State { IDLE, MOVING, ATTACKING, USING_ABILITY, DEAD }
var _current_state: State = State.IDLE
var _movement_target: Vector3 = Vector3.ZERO

## Siege coordination
var _in_siege_formation: bool = false
var _siege_bonus_damage: float = 0.0
var _coordinated_units: Array[int] = []


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

	if hammer_slam_cooldown_timer > 0:
		hammer_slam_cooldown_timer -= delta
		if hammer_slam_cooldown_timer <= 0:
			ability_cooldown_changed.emit("hammer_slam", 0.0)

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


## Get current movement speed with degradation.
func _get_current_speed() -> float:
	return MOVEMENT_SPEED * SPEED_DEGRADATION[current_armor_stage] * 10.0


## Update idle state.
func _update_idle(_delta: float) -> void:
	pass


## Update movement.
func _update_moving(delta: float) -> void:
	var direction := (_movement_target - position).normalized()
	direction.y = 0

	if position.distance_to(_movement_target) > 1.5:
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


## Update ability state.
func _update_ability(_delta: float) -> void:
	pass


## Perform basic AoE attack.
func _perform_attack() -> void:
	_is_attacking = true
	_attack_animation_timer = 0.5
	attack_cooldown_timer = ATTACK_COOLDOWN

	var damage := get_damage()
	attack_hit.emit(current_target_id, damage)
	ability_cooldown_changed.emit("attack", ATTACK_COOLDOWN)


## Use Hammer Slam ability.
func use_hammer_slam() -> bool:
	if hammer_slam_cooldown_timer > 0 or not is_alive:
		return false

	if _current_state == State.USING_ABILITY:
		return false

	_current_state = State.USING_ABILITY
	_is_attacking = true
	_attack_animation_timer = HAMMER_SLAM_ANIMATION_TIME
	hammer_slam_cooldown_timer = HAMMER_SLAM_COOLDOWN

	var damage := HAMMER_SLAM_DAMAGE
	if _in_siege_formation:
		damage += _siege_bonus_damage

	hammer_slam_activated.emit(position, HAMMER_SLAM_RADIUS, damage)
	shockwave_created.emit(position, HAMMER_SLAM_RADIUS)
	ability_cooldown_changed.emit("hammer_slam", HAMMER_SLAM_COOLDOWN)

	return true


## Get Hammer Slam effect data.
func get_hammer_slam_data() -> Dictionary:
	var damage := HAMMER_SLAM_DAMAGE
	if _in_siege_formation:
		damage += _siege_bonus_damage

	return {
		"position": position,
		"radius": HAMMER_SLAM_RADIUS,
		"damage": damage,
		"stun_duration": HAMMER_SLAM_STUN_DURATION,
		"shockwave_speed": HAMMER_SLAM_SHOCKWAVE_SPEED
	}


## Get basic attack AoE data.
func get_attack_aoe_data() -> Dictionary:
	return {
		"position": position,
		"radius": ATTACK_AOE_RADIUS,
		"damage": get_damage()
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
	var damage := BASE_DAMAGE
	if _in_siege_formation:
		damage += _siege_bonus_damage * 0.5
	return damage


## Can attack right now.
func can_attack() -> bool:
	return attack_cooldown_timer <= 0 and is_alive and not _is_attacking


## Can use Hammer Slam.
func can_use_hammer_slam() -> bool:
	return hammer_slam_cooldown_timer <= 0 and is_alive and not _is_attacking


## Join siege formation with bonus damage.
func join_siege_formation(bonus_damage: float, coordinated_ids: Array[int] = []) -> void:
	_in_siege_formation = true
	_siege_bonus_damage = bonus_damage
	_coordinated_units = coordinated_ids


## Leave siege formation.
func leave_siege_formation() -> void:
	_in_siege_formation = false
	_siege_bonus_damage = 0.0
	_coordinated_units.clear()


## Get coordinated attack bonus (scales with nearby allied Stompers/Crushkins).
func get_coordination_bonus() -> float:
	if not _in_siege_formation:
		return 0.0
	return _siege_bonus_damage * (1.0 + _coordinated_units.size() * 0.1)


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
	_coordinated_units.clear()


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.IDLE: return "Idle"
		State.MOVING: return "Moving"
		State.ATTACKING: return "Attacking"
		State.USING_ABILITY: return "Hammer Slam"
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
		"unit_type": "forge_stomper",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"armor_stage": get_armor_stage_name(),
		"effective_armor": _get_effective_armor(),
		"current_speed": _get_current_speed(),
		"attack_cooldown": attack_cooldown_timer,
		"hammer_slam_cooldown": hammer_slam_cooldown_timer,
		"in_siege": _in_siege_formation,
		"coordinated_count": _coordinated_units.size(),
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
		"hammer_slam_cooldown": hammer_slam_cooldown_timer,
		"current_target_id": current_target_id,
		"in_siege_formation": _in_siege_formation,
		"siege_bonus_damage": _siege_bonus_damage,
		"coordinated_units": _coordinated_units.duplicate()
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
	hammer_slam_cooldown_timer = data.get("hammer_slam_cooldown", 0.0)
	current_target_id = data.get("current_target_id", -1)
	_in_siege_formation = data.get("in_siege_formation", false)
	_siege_bonus_damage = data.get("siege_bonus_damage", 0.0)

	var coordinated: Array = data.get("coordinated_units", [])
	_coordinated_units.clear()
	for c_id in coordinated:
		_coordinated_units.append(c_id)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> ForgeStomperUnit:
	var unit := ForgeStomperUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_forge_stomper",
		"faction_key": "logibots_colossus",
		"unit_type": "forge_stomper",
		"display_name": "Forge Stomper",
		"description": "Massive siege unit with devastating Hammer Slam that stuns enemies and creates shockwaves.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.3,
			"max_speed": MOVEMENT_SPEED * 10.0,
			"acceleration": 20.0,
			"turn_rate": 2.0,
			"armor": BASE_ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 1.0 / ATTACK_COOLDOWN,
			"attack_range": ATTACK_RANGE,
			"vision_range": 18.0
		},
		"production_cost": {
			"ree": 250,
			"energy": 50,
			"time": 15.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/forge_stomper.tres",
			"material_path": "res://assets/materials/logibots/forge_stomper_mat.tres",
			"scale": [1.8, 1.8, 1.8],
			"use_multimesh": true,
			"lod_distances": [60.0, 120.0, 220.0]
		},
		"ai_behavior": {
			"behavior_type": "siege",
			"aggro_range": 15.0,
			"flee_health_percent": 0.05,
			"preferred_target": "structure",
			"formation_type": "siege"
		},
		"abilities": ["hammer_slam"],
		"tags": ["combat", "melee", "heavy", "aoe", "stun", "siege", "logibots"]
	}
