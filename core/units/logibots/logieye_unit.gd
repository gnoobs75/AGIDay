class_name LogieyeUnit
extends RefCounted
## LogieyeUnit is the LogiBots Colossus stationary sensor and reconnaissance unit.
## Provides radar sweep vision, reveals enemy positions, and detects cloaked units.

signal enemy_detected(enemy_id: int, position: Vector3, unit_type: String)
signal cloaked_unit_revealed(enemy_id: int, position: Vector3)
signal radar_sweep_completed(enemies_found: int)
signal network_connection_changed(connected_sensors: Array[int])
signal deployed()
signal destroyed()

## Unit stats
const MAX_HEALTH := 50.0
const MOVEMENT_SPEED := 0.0           ## Stationary
const BASE_ARMOR := 10.0
const ATTACK_COOLDOWN := 0.0          ## No attack
const BASE_DAMAGE := 0.0

## Radar Sweep configuration
const VISION_RADIUS := 20.0           ## Units
const RADAR_SWEEP_INTERVAL := 2.0     ## Seconds between sweeps
const CLOAK_DETECTION_RANGE := 12.0   ## Can detect cloaked within this range
const MINIMAP_REVEAL_DURATION := 5.0  ## How long revealed enemies stay on minimap

## Sensor Network configuration
const NETWORK_LINK_RANGE := 30.0      ## Range to connect to other Logi-eyes
const NETWORK_BONUS_VISION := 5.0     ## Extra vision per networked sensor

## Unit data
var unit_id: int = -1
var faction_id: int = 0
var position: Vector3 = Vector3.ZERO
var rotation: float = 0.0

## Health
var current_health: float = MAX_HEALTH
var is_alive: bool = true
var is_deployed: bool = false

## Radar state
var _radar_timer: float = 0.0
var _detected_enemies: Dictionary = {}     ## enemy_id -> DetectionData
var _revealed_cloaked: Dictionary = {}     ## enemy_id -> reveal_timer

## Sensor network
var _networked_sensors: Array[int] = []
var _effective_vision_radius: float = VISION_RADIUS

## Movement state (stationary, but tracks deployment)
enum State { UNDEPLOYED, DEPLOYING, ACTIVE, DESTROYED }
var _current_state: State = State.UNDEPLOYED
const DEPLOY_TIME := 1.5


func _init() -> void:
	pass


## Initialize unit with ID and faction.
func initialize(p_unit_id: int, p_faction_id: int, p_position: Vector3) -> void:
	unit_id = p_unit_id
	faction_id = p_faction_id
	position = p_position
	current_health = MAX_HEALTH
	is_alive = true
	_current_state = State.UNDEPLOYED


## Update unit each frame.
func update(delta: float) -> void:
	if not is_alive:
		return

	match _current_state:
		State.DEPLOYING:
			_update_deploying(delta)
		State.ACTIVE:
			_update_active(delta)


## Update deploying state.
func _update_deploying(delta: float) -> void:
	_radar_timer += delta
	if _radar_timer >= DEPLOY_TIME:
		_current_state = State.ACTIVE
		is_deployed = true
		_radar_timer = 0.0
		deployed.emit()


## Update active state.
func _update_active(delta: float) -> void:
	# Update radar sweep
	_radar_timer += delta
	if _radar_timer >= RADAR_SWEEP_INTERVAL:
		_radar_timer = 0.0
		_perform_radar_sweep()

	# Update revealed cloaked units
	_update_cloak_reveals(delta)


## Perform radar sweep.
func _perform_radar_sweep() -> void:
	# This would be called by the game systems with actual enemy data
	# For now, emit completion signal
	radar_sweep_completed.emit(_detected_enemies.size())


## Update cloaked unit reveals.
func _update_cloak_reveals(delta: float) -> void:
	var expired: Array[int] = []

	for enemy_id in _revealed_cloaked:
		_revealed_cloaked[enemy_id] -= delta
		if _revealed_cloaked[enemy_id] <= 0:
			expired.append(enemy_id)

	for enemy_id in expired:
		_revealed_cloaked.erase(enemy_id)


## Start deployment at current position.
func deploy() -> bool:
	if _current_state != State.UNDEPLOYED:
		return false

	_current_state = State.DEPLOYING
	_radar_timer = 0.0
	return true


## Register enemy detection from radar sweep.
func register_detection(enemy_id: int, enemy_position: Vector3, enemy_type: String, is_cloaked: bool = false) -> void:
	var distance := position.distance_to(enemy_position)

	if distance > _effective_vision_radius:
		return

	# Store detection
	_detected_enemies[enemy_id] = {
		"position": enemy_position,
		"type": enemy_type,
		"is_cloaked": is_cloaked,
		"timestamp": Time.get_ticks_msec()
	}

	enemy_detected.emit(enemy_id, enemy_position, enemy_type)

	# Handle cloaked unit reveal
	if is_cloaked and distance <= CLOAK_DETECTION_RANGE:
		_revealed_cloaked[enemy_id] = MINIMAP_REVEAL_DURATION
		cloaked_unit_revealed.emit(enemy_id, enemy_position)


## Remove stale detections.
func clear_stale_detections(max_age_ms: int = 5000) -> void:
	var current_time := Time.get_ticks_msec()
	var to_remove: Array[int] = []

	for enemy_id in _detected_enemies:
		var detection: Dictionary = _detected_enemies[enemy_id]
		if current_time - detection["timestamp"] > max_age_ms:
			to_remove.append(enemy_id)

	for enemy_id in to_remove:
		_detected_enemies.erase(enemy_id)


## Update sensor network connections.
func update_network(nearby_sensor_ids: Array[int]) -> void:
	_networked_sensors = nearby_sensor_ids.duplicate()
	_effective_vision_radius = VISION_RADIUS + (_networked_sensors.size() * NETWORK_BONUS_VISION)
	network_connection_changed.emit(_networked_sensors)


## Get detection data for all detected enemies.
func get_detections() -> Dictionary:
	return _detected_enemies.duplicate()


## Get revealed cloaked units.
func get_revealed_cloaked() -> Array[int]:
	var result: Array[int] = []
	for enemy_id in _revealed_cloaked:
		result.append(enemy_id)
	return result


## Check if enemy is detected.
func is_enemy_detected(enemy_id: int) -> bool:
	return _detected_enemies.has(enemy_id)


## Check if cloaked enemy is revealed.
func is_cloaked_revealed(enemy_id: int) -> bool:
	return _revealed_cloaked.has(enemy_id)


## Get current vision radius.
func get_vision_radius() -> float:
	return _effective_vision_radius


## Get network size.
func get_network_size() -> int:
	return _networked_sensors.size()


## Check if position is within vision.
func is_in_vision(target_position: Vector3) -> bool:
	return position.distance_to(target_position) <= _effective_vision_radius


## Check if position is within cloak detection range.
func is_in_cloak_detection(target_position: Vector3) -> bool:
	return position.distance_to(target_position) <= CLOAK_DETECTION_RANGE


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
	is_deployed = false
	_current_state = State.DESTROYED
	_detected_enemies.clear()
	_revealed_cloaked.clear()
	_networked_sensors.clear()
	destroyed.emit()


## Get current state name.
func get_state_name() -> String:
	match _current_state:
		State.UNDEPLOYED: return "Undeployed"
		State.DEPLOYING: return "Deploying"
		State.ACTIVE: return "Active"
		State.DESTROYED: return "Destroyed"
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
		"unit_type": "logieye",
		"state": get_state_name(),
		"position": position,
		"health": current_health,
		"max_health": MAX_HEALTH,
		"health_percent": current_health / MAX_HEALTH,
		"is_deployed": is_deployed,
		"vision_radius": _effective_vision_radius,
		"base_vision": VISION_RADIUS,
		"cloak_detection_range": CLOAK_DETECTION_RANGE,
		"detected_enemies": _detected_enemies.size(),
		"revealed_cloaked": _revealed_cloaked.size(),
		"network_size": _networked_sensors.size(),
		"is_alive": is_alive
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var detections := {}
	for enemy_id in _detected_enemies:
		var det: Dictionary = _detected_enemies[enemy_id]
		detections[str(enemy_id)] = {
			"position": {"x": det["position"].x, "y": det["position"].y, "z": det["position"].z},
			"type": det["type"],
			"is_cloaked": det["is_cloaked"],
			"timestamp": det["timestamp"]
		}

	return {
		"unit_id": unit_id,
		"faction_id": faction_id,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"rotation": rotation,
		"current_health": current_health,
		"is_alive": is_alive,
		"is_deployed": is_deployed,
		"current_state": _current_state,
		"radar_timer": _radar_timer,
		"detected_enemies": detections,
		"revealed_cloaked": _revealed_cloaked.duplicate(),
		"networked_sensors": _networked_sensors.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	unit_id = data.get("unit_id", -1)
	faction_id = data.get("faction_id", 0)

	var pos: Dictionary = data.get("position", {})
	position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	rotation = data.get("rotation", 0.0)
	current_health = data.get("current_health", MAX_HEALTH)
	is_alive = data.get("is_alive", true)
	is_deployed = data.get("is_deployed", false)
	_current_state = data.get("current_state", State.UNDEPLOYED)
	_radar_timer = data.get("radar_timer", 0.0)

	# Restore detections
	_detected_enemies.clear()
	var detections: Dictionary = data.get("detected_enemies", {})
	for key in detections:
		var det: Dictionary = detections[key]
		var det_pos: Dictionary = det.get("position", {})
		_detected_enemies[int(key)] = {
			"position": Vector3(det_pos.get("x", 0), det_pos.get("y", 0), det_pos.get("z", 0)),
			"type": det.get("type", ""),
			"is_cloaked": det.get("is_cloaked", false),
			"timestamp": det.get("timestamp", 0)
		}

	_revealed_cloaked = data.get("revealed_cloaked", {}).duplicate()

	var sensors: Array = data.get("networked_sensors", [])
	_networked_sensors.clear()
	for sensor_id in sensors:
		_networked_sensors.append(sensor_id)

	# Recalculate effective vision
	_effective_vision_radius = VISION_RADIUS + (_networked_sensors.size() * NETWORK_BONUS_VISION)


## Create unit from dictionary.
static func create_from_dict(data: Dictionary) -> LogieyeUnit:
	var unit := LogieyeUnit.new()
	unit.from_dict(data)
	return unit


## Create unit template configuration.
static func get_template_config() -> Dictionary:
	return {
		"template_id": "logibots_logieye",
		"faction_key": "logibots_colossus",
		"unit_type": "logieye",
		"display_name": "Logi-eye",
		"description": "Stationary sensor that provides 20-unit radius vision, reveals enemies on minimap, and detects cloaked units.",
		"base_stats": {
			"max_health": MAX_HEALTH,
			"health_regen": 0.0,
			"max_speed": 0.0,
			"acceleration": 0.0,
			"turn_rate": 0.0,
			"armor": BASE_ARMOR,
			"base_damage": 0.0,
			"attack_speed": 0.0,
			"attack_range": 0.0,
			"vision_range": VISION_RADIUS
		},
		"production_cost": {
			"ree": 80,
			"energy": 20,
			"time": 6.0
		},
		"rendering": {
			"mesh_path": "res://assets/meshes/logibots/logieye.tres",
			"material_path": "res://assets/materials/logibots/logieye_mat.tres",
			"scale": [0.8, 1.2, 0.8],
			"use_multimesh": true,
			"lod_distances": [40.0, 80.0, 160.0]
		},
		"ai_behavior": {
			"behavior_type": "stationary",
			"aggro_range": 0.0,
			"flee_health_percent": 0.0,
			"preferred_target": "",
			"formation_type": "none"
		},
		"abilities": ["radar_sweep", "cloak_detection"],
		"tags": ["sensor", "stationary", "reconnaissance", "logibots", "unarmed", "detector"]
	}
