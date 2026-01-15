class_name PayloadSlingerUnit
extends RefCounted
## PayloadSlingerUnit is the LogiBots Colossus catapult system for tactical unit deployment.
## Launches up to 4 units in an arc to target locations for rapid assault deployment.

signal unit_loaded(unit_id: int, cargo_count: int)
signal units_launched(unit_ids: Array[int], target: Vector3)
signal unit_landed(unit_id: int, position: Vector3)
signal all_units_landed(count: int)
signal cargo_changed(count: int, max_count: int)
signal loading_started()
signal loading_completed(count: int)
signal launch_started(target: Vector3)
signal launch_completed()
signal armor_damaged(stage: int, percent: float)
signal ability_cooldown_changed(ability: String, remaining: float)

## Unit stats
const MAX_HEALTH := 180.0
const MOVEMENT_SPEED := 0.6
const BASE_ARMOR := 45.0
const ATTACK_COOLDOWN := 0.0       ## No attack capability
const BASE_DAMAGE := 0.0

## Launch Squad configuration
const MAX_CARGO := 4               ## Maximum units to launch
const LAUNCH_COOLDOWN := 10.0      ## Seconds between launches
const LAUNCH_RANGE_MIN := 15.0     ## Minimum launch distance
const LAUNCH_RANGE_MAX := 50.0     ## Maximum launch distance
const LAUNCH_HEIGHT := 30.0        ## Arc peak height
const LAUNCH_FLIGHT_TIME := 2.0    ## Seconds in air
const LOAD_RADIUS := 8.0           ## Radius to search for loadable units
const LOAD_TIME := 1.5             ## Total load animation time
const FORMATION_SPREAD := 3.0      ## Landing spread radius

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

## Cargo state
var _loaded_units: Array[int] = []
var _loading_timer: float = 0.0
var _is_loading: bool = false
var _pending_load_ids: Array[int] = []

## Launch state
var launch_cooldown_timer: float = 0.0
var _is_launching: bool = false
var _launch_timer: float = 0.0
var _launch_target: Vector3 = Vector3.ZERO
var _launched_units: Array[int] = []
var _landing_positions: Array[Vector3] = []

## Movement state
enum State { IDLE, MOVING, LOADING, AIMING, LAUNCHING, DEAD }
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
	_loaded_units.clear()


## Update unit each frame.
func update(delta: float) -> void:
	if not is_alive:
		return

	# Update cooldowns
	if launch_cooldown_timer > 0:
		launch_cooldown_timer -= delta
		if launch_cooldown_timer <= 0:
			ability_cooldown_changed.emit("launch_squad", 0.0)

	# Update launch flight
	if _is_launching:
		_update_flight(delta)

	# State machine
	match _current_state:
		State.IDLE:
			_update_idle(delta)
		State.MOVING:
			_update_moving(delta)
		State.LOADING:
			_update_loading(delta)
		State.AIMING:
			_update_aiming(delta)
		State.LAUNCHING:
			_update_launching(delta)


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


## Update loading state.
func _update_loading(delta: float) -> void:
	_loading_timer += delta

	# Load units over time
	var load_progress := _loading_timer / LOAD_TIME
	var units_to_load := int(load_progress * _pending_load_ids.size())

	while _loaded_units.size() < units_to_load and not _pending_load_ids.is_empty():
		var load_id: int = _pending_load_ids.pop_front()
		_loaded_units.append(load_id)
		unit_loaded.emit(load_id, _loaded_units.size())
		cargo_changed.emit(_loaded_units.size(), MAX_CARGO)

	# Check if loading complete
	if _pending_load_ids.is_empty() or _loading_timer >= LOAD_TIME:
		_is_loading = false
		_current_state = State.IDLE
		loading_completed.emit(_loaded_units.size())


## Update aiming state.
func _update_aiming(_delta: float) -> void:
	# Face target
	var dir_to_target := (_launch_target - position).normalized()
	dir_to_target.y = 0
	rotation = atan2(dir_to_target.x, dir_to_target.z)


## Update launching state.
func _update_launching(_delta: float) -> void:
	# Launching handled by flight update
	pass


## Update flight of launched units.
func _update_flight(delta: float) -> void:
	_launch_timer += delta

	var flight_progress := _launch_timer / LAUNCH_FLIGHT_TIME

	if flight_progress >= 1.0:
		# All units have landed
		_complete_launch()
		return

	# Could emit progress events here for visual effects


## Complete the launch sequence.
func _complete_launch() -> void:
	# Emit landing events for each unit
	for i in _launched_units.size():
		var landed_id: int = _launched_units[i]
		var land_pos: Vector3 = _landing_positions[i]
		unit_landed.emit(landed_id, land_pos)

	all_units_landed.emit(_launched_units.size())

	_is_launching = false
	_launched_units.clear()
	_landing_positions.clear()
	_current_state = State.IDLE
	launch_completed.emit()


## Calculate landing positions around target.
func _calculate_landing_positions(target: Vector3, count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []

	if count == 1:
		positions.append(target)
		return positions

	# Spread units around target in a circle
	var angle_step := TAU / float(count)
	for i in count:
		var angle := angle_step * i
		var offset := Vector3(
			cos(angle) * FORMATION_SPREAD,
			0,
			sin(angle) * FORMATION_SPREAD
		)
		positions.append(target + offset)

	return positions


## Calculate launch arc data for visualization.
func get_launch_arc_data(target: Vector3) -> Dictionary:
	var distance := position.distance_to(target)
	var direction := (target - position).normalized()
	direction.y = 0

	# Simple parabolic arc
	var arc_points: Array[Vector3] = []
	var steps := 20
	for i in steps + 1:
		var t := float(i) / float(steps)
		var horizontal_pos := position.lerp(target, t)
		var arc_height := LAUNCH_HEIGHT * 4.0 * t * (1.0 - t)  # Parabola
		horizontal_pos.y = position.y + arc_height
		arc_points.append(horizontal_pos)

	return {
		"origin": position,
		"target": target,
		"arc_points": arc_points,
		"flight_time": LAUNCH_FLIGHT_TIME,
		"peak_height": LAUNCH_HEIGHT
	}


## Start loading nearby units.
func load_units(unit_ids: Array[int]) -> bool:
	if not is_alive or _is_loading or _is_launching:
		return false

	if _loaded_units.size() >= MAX_CARGO:
		return false

	# Filter to only load what we can fit
	var space_available := MAX_CARGO - _loaded_units.size()
	_pending_load_ids.clear()

	for i in mini(unit_ids.size(), space_available):
		_pending_load_ids.append(unit_ids[i])

	if _pending_load_ids.is_empty():
		return false

	_is_loading = true
	_loading_timer = 0.0
	_current_state = State.LOADING
	loading_started.emit()

	return true


## Launch loaded units to target position.
func launch_squad(target: Vector3) -> bool:
	if not is_alive or _is_loading or _is_launching:
		return false

	if _loaded_units.is_empty():
		return false

	if launch_cooldown_timer > 0:
		return false

	# Validate range
	var distance := position.distance_to(target)
	if distance < LAUNCH_RANGE_MIN or distance > LAUNCH_RANGE_MAX:
		return false

	# Start launch
	_launch_target = target
	_launched_units = _loaded_units.duplicate()
	_loaded_units.clear()
	_landing_positions = _calculate_landing_positions(target, _launched_units.size())

	_is_launching = true
	_launch_timer = 0.0
	launch_cooldown_timer = LAUNCH_COOLDOWN
	_current_state = State.LAUNCHING

	launch_started.emit(target)
	units_launched.emit(_launched_units, target)
	cargo_changed.emit(0, MAX_CARGO)
	ability_cooldown_changed.emit("launch_squad", LAUNCH_COOLDOWN)

	return true


## Aim at target (for preview).
func aim_at(target: Vector3) -> void:
	if not is_alive or _is_launching:
		return

	_launch_target = target
	_current_state = State.AIMING


## Stop aiming.
func stop_aiming() -> void:
	if _current_state == State.AIMING:
		_current_state = State.IDLE


## Move to position.
func move_to(target: Vector3) -> void:
	if not is_alive or _is_loading or _is_launching:
		return

	_movement_target = target
	_current_state = State.MOVING


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
	velocity = Vector3.ZERO

	# Loaded units (not yet launched) are lost
	_loaded_units.clear()
	_pending_load_ids.clear()


## Can launch right now.
func can_launch() -> bool:
	return launch_cooldown_timer <= 0 and is_alive and not _is_launching and not _loaded_units.is_empty()


## Check if target is in valid launch range.
func is_in_launch_range(target: Vector3) -> bool:
	var distance := position.distance_to(target)
	return distance >= LAUNCH_RANGE_MIN and distance <= LAUNCH_RANGE_MAX


## Get cargo count.
func get_cargo_count() -> int:
	return _loaded_units.size()


## Has space for more units.
func has_space() -> bool:
	return _loaded_units.size() < MAX_CARGO


## Is currently busy.
func is_busy() -> bool:
	return _is_loading or _is_launching


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.IDLE: return "Idle"
		State.MOVING: return "Moving"
		State.LOADING: return "Loading"
		State.AIMING: return "Aiming"
		State.LAUNCHING: return "Launching"
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
		"unit_type": "payload_slinger",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"armor_stage": get_armor_stage_name(),
		"cargo_count": _loaded_units.size(),
		"max_cargo": MAX_CARGO,
		"launch_cooldown": launch_cooldown_timer,
		"is_loading": _is_loading,
		"is_launching": _is_launching,
		"launch_range": [LAUNCH_RANGE_MIN, LAUNCH_RANGE_MAX],
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
		"loaded_units": _loaded_units.duplicate(),
		"is_loading": _is_loading,
		"is_launching": _is_launching,
		"launch_cooldown": launch_cooldown_timer,
		"launch_target": {"x": _launch_target.x, "y": _launch_target.y, "z": _launch_target.z}
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
	_is_loading = data.get("is_loading", false)
	_is_launching = data.get("is_launching", false)
	launch_cooldown_timer = data.get("launch_cooldown", 0.0)

	var target: Dictionary = data.get("launch_target", {})
	_launch_target = Vector3(target.get("x", 0), target.get("y", 0), target.get("z", 0))

	var loaded: Array = data.get("loaded_units", [])
	_loaded_units.clear()
	for loaded_id in loaded:
		_loaded_units.append(loaded_id)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> PayloadSlingerUnit:
	var unit := PayloadSlingerUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_payload_slinger",
		"faction_key": "logibots_colossus",
		"unit_type": "payload_slinger",
		"display_name": "Payload Slinger",
		"description": "Catapult system that launches up to 4 units in an arc for rapid tactical deployment.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.0,
			"max_speed": MOVEMENT_SPEED * 10.0,
			"acceleration": 10.0,
			"turn_rate": 2.0,
			"armor": BASE_ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 0.0,
			"attack_range": LAUNCH_RANGE_MAX,
			"vision_range": 25.0
		},
		"production_cost": {
			"ree": 320,
			"energy": 55,
			"time": 18.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/payload_slinger.tres",
			"material_path": "res://assets/materials/logibots/payload_slinger_mat.tres",
			"scale": [1.8, 1.8, 2.2],
			"use_multimesh": false,
			"lod_distances": [60.0, 120.0, 220.0]
		},
		"ai_behavior": {
			"behavior_type": "support",
			"aggro_range": 0.0,
			"flee_health_percent": 0.25,
			"preferred_target": "",
			"formation_type": "rear"
		},
		"abilities": ["load_units", "launch_squad"],
		"tags": ["transport", "catapult", "support", "logibots", "tactical", "unarmed"]
	}
