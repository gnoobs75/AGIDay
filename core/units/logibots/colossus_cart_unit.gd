class_name ColossusCartUnit
extends RefCounted
## ColossusCartUnit is the LogiBots Colossus troop transport vehicle.
## Can load 8 units and transport them safely across the battlefield.

signal unit_loaded(unit_id: int, cargo_count: int)
signal unit_unloaded(unit_id: int, position: Vector3)
signal all_units_unloaded(count: int, positions: Array[Vector3])
signal cargo_changed(count: int, max_count: int)
signal loading_started()
signal loading_completed(count: int)
signal unloading_started()
signal unloading_completed()
signal armor_damaged(stage: int, percent: float)

## Unit stats
const MAX_HEALTH := 250.0
const MOVEMENT_SPEED := 0.8
const BASE_ARMOR := 40.0
const ATTACK_COOLDOWN := 0.0       ## No attack capability
const BASE_DAMAGE := 0.0

## Transport configuration
const MAX_CARGO := 8               ## Maximum units to carry
const LOAD_RADIUS := 10.0          ## Radius to search for loadable units
const LOAD_TIME_PER_UNIT := 0.15   ## Seconds per unit to load
const UNLOAD_TIME_PER_UNIT := 0.15 ## Seconds per unit to unload
const TOTAL_LOAD_TIME := 1.5       ## Max animation time
const FORMATION_SPACING := 2.5     ## Space between deployed units

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
var _is_unloading: bool = false
var _pending_load_ids: Array[int] = []
var _unload_positions: Array[Vector3] = []

## Movement state
enum State { IDLE, MOVING, LOADING, UNLOADING, DEAD }
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

	# State machine
	match _current_state:
		State.IDLE:
			_update_idle(delta)
		State.MOVING:
			_update_moving(delta)
		State.LOADING:
			_update_loading(delta)
		State.UNLOADING:
			_update_unloading(delta)


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
	var units_to_load := int(_loading_timer / LOAD_TIME_PER_UNIT)
	while units_to_load > 0 and not _pending_load_ids.is_empty():
		var load_id: int = _pending_load_ids.pop_front()
		_loaded_units.append(load_id)
		unit_loaded.emit(load_id, _loaded_units.size())
		cargo_changed.emit(_loaded_units.size(), MAX_CARGO)
		units_to_load -= 1

	# Check if loading complete
	if _pending_load_ids.is_empty() or _loading_timer >= TOTAL_LOAD_TIME:
		_is_loading = false
		_current_state = State.IDLE
		loading_completed.emit(_loaded_units.size())


## Update unloading state.
func _update_unloading(delta: float) -> void:
	_loading_timer += delta

	# Unload units over time
	var units_to_unload := int(_loading_timer / UNLOAD_TIME_PER_UNIT)
	while units_to_unload > 0 and not _loaded_units.is_empty():
		var unload_id: int = _loaded_units.pop_front()
		var unload_pos: Vector3
		if not _unload_positions.is_empty():
			unload_pos = _unload_positions.pop_front()
		else:
			unload_pos = _calculate_default_unload_position(_loaded_units.size())

		unit_unloaded.emit(unload_id, unload_pos)
		cargo_changed.emit(_loaded_units.size(), MAX_CARGO)
		units_to_unload -= 1

	# Check if unloading complete
	if _loaded_units.is_empty() or _loading_timer >= TOTAL_LOAD_TIME:
		_is_unloading = false
		_current_state = State.IDLE
		unloading_completed.emit()


## Calculate default unload position in formation.
func _calculate_default_unload_position(index: int) -> Vector3:
	var forward := Vector3(sin(rotation), 0, cos(rotation))
	var right := forward.cross(Vector3.UP)

	# Grid formation behind transport
	var row := index / 4
	var col := index % 4

	var offset := -forward * (3.0 + row * FORMATION_SPACING)
	offset += right * ((col - 1.5) * FORMATION_SPACING)

	return position + offset


## Calculate formation positions for all cargo.
func _calculate_formation_positions(target: Vector3) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var count := _loaded_units.size()

	var dir_to_target := (target - position).normalized()
	dir_to_target.y = 0
	if dir_to_target.length_squared() < 0.01:
		dir_to_target = Vector3(sin(rotation), 0, cos(rotation))

	var right := dir_to_target.cross(Vector3.UP).normalized()

	for i in count:
		var row := i / 4
		var col := i % 4
		var offset := dir_to_target * (row * FORMATION_SPACING)
		offset += right * ((col - 1.5) * FORMATION_SPACING)
		positions.append(target + offset)

	return positions


## Start loading nearby units.
func load_units(unit_ids: Array[int]) -> bool:
	if not is_alive or _is_loading or _is_unloading:
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


## Start unloading all units at target position.
func unload_units(target_position: Vector3 = Vector3.ZERO) -> bool:
	if not is_alive or _is_loading or _is_unloading:
		return false

	if _loaded_units.is_empty():
		return false

	_is_unloading = true
	_loading_timer = 0.0

	# Calculate formation positions
	if target_position == Vector3.ZERO:
		target_position = position
	_unload_positions = _calculate_formation_positions(target_position)

	_current_state = State.UNLOADING
	unloading_started.emit()

	return true


## Unload a single unit.
func unload_single_unit(unit_idx: int = 0) -> int:
	if _loaded_units.is_empty() or unit_idx >= _loaded_units.size():
		return -1

	var unloaded_id: int = _loaded_units[unit_idx]
	_loaded_units.remove_at(unit_idx)

	var unload_pos := _calculate_default_unload_position(0)
	unit_unloaded.emit(unloaded_id, unload_pos)
	cargo_changed.emit(_loaded_units.size(), MAX_CARGO)

	return unloaded_id


## Move to position.
func move_to(target: Vector3) -> void:
	if not is_alive or _is_loading or _is_unloading:
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


## Apply damage to unit (cargo is protected).
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


## Handle death (loaded units are lost).
func _die() -> void:
	is_alive = false
	_current_state = State.DEAD
	velocity = Vector3.ZERO

	# Loaded units are destroyed with transport
	_loaded_units.clear()
	_pending_load_ids.clear()


## Get cargo count.
func get_cargo_count() -> int:
	return _loaded_units.size()


## Get loaded unit IDs.
func get_loaded_units() -> Array[int]:
	return _loaded_units.duplicate()


## Has space for more units.
func has_space() -> bool:
	return _loaded_units.size() < MAX_CARGO


## Is currently loading or unloading.
func is_busy() -> bool:
	return _is_loading or _is_unloading


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.IDLE: return "Idle"
		State.MOVING: return "Moving"
		State.LOADING: return "Loading"
		State.UNLOADING: return "Unloading"
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
		"unit_type": "colossus_cart",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"armor_stage": get_armor_stage_name(),
		"cargo_count": _loaded_units.size(),
		"max_cargo": MAX_CARGO,
		"is_loading": _is_loading,
		"is_unloading": _is_unloading,
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
		"is_unloading": _is_unloading,
		"loading_timer": _loading_timer
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
	_is_unloading = data.get("is_unloading", false)
	_loading_timer = data.get("loading_timer", 0.0)

	var loaded: Array = data.get("loaded_units", [])
	_loaded_units.clear()
	for loaded_id in loaded:
		_loaded_units.append(loaded_id)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> ColossusCartUnit:
	var unit := ColossusCartUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_colossus_cart",
		"faction_key": "logibots_colossus",
		"unit_type": "colossus_cart",
		"display_name": "Colossus Cart",
		"description": "Heavy transport vehicle that carries up to 8 units safely across the battlefield.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.0,
			"max_speed": MOVEMENT_SPEED * 10.0,
			"acceleration": 12.0,
			"turn_rate": 1.5,
			"armor": BASE_ARMOR,
			"base_damage": BASE_DAMAGE,
			"attack_speed": 0.0,
			"attack_range": 0.0,
			"vision_range": 15.0
		},
		"production_cost": {
			"ree": 280,
			"energy": 45,
			"time": 16.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/colossus_cart.tres",
			"material_path": "res://assets/materials/logibots/colossus_cart_mat.tres",
			"scale": [2.0, 2.0, 3.0],
			"use_multimesh": false,
			"lod_distances": [60.0, 120.0, 220.0]
		},
		"ai_behavior": {
			"behavior_type": "transport",
			"aggro_range": 0.0,
			"flee_health_percent": 0.3,
			"preferred_target": "",
			"formation_type": "none"
		},
		"abilities": ["load_units", "unload_units"],
		"tags": ["transport", "heavy", "support", "logibots", "unarmed"]
	}
