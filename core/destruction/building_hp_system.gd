class_name BuildingHPSystem
extends RefCounted
## BuildingHPSystem manages building health states and damage application.
## Handles damage types, stage transitions, and destruction events.

signal building_damaged(building_id: int, damage: float, new_hp: float)
signal building_stage_changed(building_id: int, old_stage: int, new_stage: int)
signal building_destroyed(building_id: int, position: Vector3)
signal effects_requested(position: Vector3, effect_type: String, intensity: int)

## HP stages
enum HPStage {
	INTACT = 0,    ## 100% HP
	CRACKED = 1,   ## 50-99% HP
	RUBBLE = 2,    ## 1-49% HP
	CRATER = 3     ## 0% HP
}

## Damage type multipliers
const DAMAGE_MULTIPLIERS := {
	"kinetic": 1.2,
	"explosive": 1.5,
	"energy": 0.8,
	"nano_shred": 0.9,
	"default": 1.0
}

## Default max health
const DEFAULT_MAX_HEALTH := 100.0

## Stage thresholds (percentage of max health)
const STAGE_THRESHOLDS := {
	HPStage.INTACT: 1.0,
	HPStage.CRACKED: 0.5,
	HPStage.RUBBLE: 0.01,
	HPStage.CRATER: 0.0
}

## Effect intensities per stage
const STAGE_EFFECTS := {
	HPStage.CRACKED: {"type": "dust_small", "particles": 10},
	HPStage.RUBBLE: {"type": "collapse", "particles": 70},
	HPStage.CRATER: {"type": "explosion", "particles": 100}
}


## Building health data.
class BuildingData:
	var building_id: int = 0
	var position: Vector3 = Vector3.ZERO
	var max_health: float = DEFAULT_MAX_HEALTH
	var current_health: float = DEFAULT_MAX_HEALTH
	var stage: int = HPStage.INTACT
	var building_type: String = ""
	var voxel_positions: Array[Vector3i] = []
	var is_destroyed: bool = false

	func get_health_percent() -> float:
		if max_health <= 0:
			return 0.0
		return current_health / max_health


## Building registry
var _buildings: Dictionary = {}  ## building_id -> BuildingData

## Position lookup
var _position_to_building: Dictionary = {}  ## "x,y,z" -> building_id

## Voxel system reference for updating voxels
var _voxel_system = null  ## VoxelSystem

## Next building ID
var _next_id: int = 1

## Thread mutex for concurrent access
var _mutex: Mutex = null


func _init() -> void:
	_mutex = Mutex.new()


## Set voxel system reference.
func set_voxel_system(voxel_system) -> void:
	_voxel_system = voxel_system


## Register a new building.
func register_building(
	position: Vector3,
	max_health: float = DEFAULT_MAX_HEALTH,
	building_type: String = "generic",
	voxel_positions: Array[Vector3i] = []
) -> int:
	_mutex.lock()

	var building := BuildingData.new()
	building.building_id = _next_id
	building.position = position
	building.max_health = max_health
	building.current_health = max_health
	building.stage = HPStage.INTACT
	building.building_type = building_type
	building.voxel_positions = voxel_positions

	_buildings[_next_id] = building

	# Register position lookup
	var key := _pos_to_key(position)
	_position_to_building[key] = _next_id

	# Register voxel positions
	for vpos in voxel_positions:
		var vkey := _vpos_to_key(vpos)
		_position_to_building[vkey] = _next_id

	var id := _next_id
	_next_id += 1

	_mutex.unlock()
	return id


## Apply damage to building.
func apply_damage(
	building_id: int,
	damage: float,
	damage_type: String = "default"
) -> void:
	_mutex.lock()

	if not _buildings.has(building_id):
		_mutex.unlock()
		return

	var building: BuildingData = _buildings[building_id]

	if building.is_destroyed:
		_mutex.unlock()
		return

	# Apply damage multiplier
	var multiplier := DAMAGE_MULTIPLIERS.get(damage_type, 1.0)
	var effective_damage := damage * multiplier

	var old_hp := building.current_health
	building.current_health = maxf(0.0, building.current_health - effective_damage)

	_mutex.unlock()

	building_damaged.emit(building_id, effective_damage, building.current_health)

	# Check stage transition
	var new_stage := _calculate_stage(building.get_health_percent())
	if new_stage != building.stage:
		_handle_stage_transition(building_id, building, new_stage)


## Apply damage at position.
func apply_damage_at_position(
	position: Vector3,
	damage: float,
	damage_type: String = "default"
) -> void:
	var building_id := get_building_at_position(position)
	if building_id > 0:
		apply_damage(building_id, damage, damage_type)


## Apply damage to voxel position.
func apply_damage_at_voxel(
	voxel_pos: Vector3i,
	damage: float,
	damage_type: String = "default"
) -> void:
	var key := _vpos_to_key(voxel_pos)
	if _position_to_building.has(key):
		apply_damage(_position_to_building[key], damage, damage_type)


## Calculate HP stage from health percentage.
func _calculate_stage(health_percent: float) -> int:
	if health_percent <= 0:
		return HPStage.CRATER
	elif health_percent < STAGE_THRESHOLDS[HPStage.RUBBLE]:
		return HPStage.RUBBLE
	elif health_percent < STAGE_THRESHOLDS[HPStage.CRACKED]:
		return HPStage.CRACKED
	else:
		return HPStage.INTACT


## Handle stage transition.
func _handle_stage_transition(building_id: int, building: BuildingData, new_stage: int) -> void:
	var old_stage := building.stage
	building.stage = new_stage

	building_stage_changed.emit(building_id, old_stage, new_stage)

	# Request visual effects
	if STAGE_EFFECTS.has(new_stage):
		var effect := STAGE_EFFECTS[new_stage]
		effects_requested.emit(building.position, effect["type"], effect["particles"])

	# Update voxels if connected
	if _voxel_system != null:
		_update_building_voxels(building, new_stage)

	# Mark destroyed at crater
	if new_stage == HPStage.CRATER:
		building.is_destroyed = true
		building_destroyed.emit(building_id, building.position)


## Update voxels for building stage.
func _update_building_voxels(building: BuildingData, stage: int) -> void:
	if _voxel_system == null:
		return

	# Map building stage to voxel stage
	var voxel_stage: int
	match stage:
		HPStage.INTACT:
			voxel_stage = VoxelStage.Stage.INTACT
		HPStage.CRACKED:
			voxel_stage = VoxelStage.Stage.CRACKED
		HPStage.RUBBLE:
			voxel_stage = VoxelStage.Stage.RUBBLE
		HPStage.CRATER:
			voxel_stage = VoxelStage.Stage.CRATER
		_:
			voxel_stage = VoxelStage.Stage.INTACT

	# Apply damage to voxels to match stage
	for vpos in building.voxel_positions:
		var voxel = _voxel_system.get_voxel(vpos)
		if voxel != null and voxel.stage < voxel_stage:
			# Calculate damage needed to reach stage
			var target_hp := 0
			match voxel_stage:
				VoxelStage.Stage.INTACT: target_hp = 100
				VoxelStage.Stage.CRACKED: target_hp = 49
				VoxelStage.Stage.RUBBLE: target_hp = 9
				VoxelStage.Stage.CRATER: target_hp = 0

			var damage_needed := voxel.current_hp - target_hp
			if damage_needed > 0:
				_voxel_system.damage_voxel(vpos, damage_needed)


## Get building at world position.
func get_building_at_position(position: Vector3) -> int:
	var key := _pos_to_key(position)
	return _position_to_building.get(key, 0)


## Get building data.
func get_building(building_id: int) -> BuildingData:
	return _buildings.get(building_id)


## Get building health.
func get_health(building_id: int) -> float:
	if _buildings.has(building_id):
		return _buildings[building_id].current_health
	return 0.0


## Get building stage.
func get_stage(building_id: int) -> int:
	if _buildings.has(building_id):
		return _buildings[building_id].stage
	return HPStage.CRATER


## Check if building is destroyed.
func is_destroyed(building_id: int) -> bool:
	if _buildings.has(building_id):
		return _buildings[building_id].is_destroyed
	return true


## Repair building to full health.
func repair_building(building_id: int) -> void:
	if not _buildings.has(building_id):
		return

	var building: BuildingData = _buildings[building_id]
	building.current_health = building.max_health
	building.stage = HPStage.INTACT
	building.is_destroyed = false

	building_stage_changed.emit(building_id, HPStage.CRATER, HPStage.INTACT)


## Get all buildings.
func get_all_buildings() -> Array[int]:
	var result: Array[int] = []
	for id in _buildings:
		result.append(id)
	return result


## Get buildings by stage.
func get_buildings_by_stage(stage: int) -> Array[int]:
	var result: Array[int] = []
	for id in _buildings:
		if _buildings[id].stage == stage:
			result.append(id)
	return result


## Get destroyed buildings.
func get_destroyed_buildings() -> Array[int]:
	var result: Array[int] = []
	for id in _buildings:
		if _buildings[id].is_destroyed:
			result.append(id)
	return result


## Remove building from registry.
func remove_building(building_id: int) -> void:
	_mutex.lock()

	if _buildings.has(building_id):
		var building: BuildingData = _buildings[building_id]

		# Remove position lookups
		var key := _pos_to_key(building.position)
		_position_to_building.erase(key)

		for vpos in building.voxel_positions:
			var vkey := _vpos_to_key(vpos)
			_position_to_building.erase(vkey)

		_buildings.erase(building_id)

	_mutex.unlock()


## Convert position to key.
func _pos_to_key(position: Vector3) -> String:
	return "%d,%d,%d" % [int(position.x), int(position.y), int(position.z)]


## Convert voxel position to key.
func _vpos_to_key(position: Vector3i) -> String:
	return "v%d,%d,%d" % [position.x, position.y, position.z]


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var buildings_data: Array = []
	for id in _buildings:
		var b: BuildingData = _buildings[id]
		var voxels: Array = []
		for v in b.voxel_positions:
			voxels.append([v.x, v.y, v.z])

		buildings_data.append({
			"id": b.building_id,
			"position": [b.position.x, b.position.y, b.position.z],
			"max_health": b.max_health,
			"current_health": b.current_health,
			"stage": b.stage,
			"building_type": b.building_type,
			"voxel_positions": voxels,
			"is_destroyed": b.is_destroyed
		})

	return {
		"buildings": buildings_data,
		"next_id": _next_id
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_mutex.lock()

	_buildings.clear()
	_position_to_building.clear()

	_next_id = data.get("next_id", 1)

	var buildings_data: Array = data.get("buildings", [])
	for b_data in buildings_data:
		var building := BuildingData.new()
		building.building_id = b_data.get("id", 0)

		var pos: Array = b_data.get("position", [0, 0, 0])
		building.position = Vector3(pos[0], pos[1], pos[2])

		building.max_health = b_data.get("max_health", DEFAULT_MAX_HEALTH)
		building.current_health = b_data.get("current_health", DEFAULT_MAX_HEALTH)
		building.stage = b_data.get("stage", HPStage.INTACT)
		building.building_type = b_data.get("building_type", "generic")
		building.is_destroyed = b_data.get("is_destroyed", false)

		var voxels: Array = b_data.get("voxel_positions", [])
		for v in voxels:
			building.voxel_positions.append(Vector3i(v[0], v[1], v[2]))

		_buildings[building.building_id] = building

		# Rebuild lookups
		var key := _pos_to_key(building.position)
		_position_to_building[key] = building.building_id

		for vpos in building.voxel_positions:
			var vkey := _vpos_to_key(vpos)
			_position_to_building[vkey] = building.building_id

	_mutex.unlock()


## Get stage name.
static func get_stage_name(stage: int) -> String:
	match stage:
		HPStage.INTACT: return "Intact"
		HPStage.CRACKED: return "Cracked"
		HPStage.RUBBLE: return "Rubble"
		HPStage.CRATER: return "Crater"
		_: return "Unknown"


## Get statistics.
func get_statistics() -> Dictionary:
	var stage_counts := {
		HPStage.INTACT: 0,
		HPStage.CRACKED: 0,
		HPStage.RUBBLE: 0,
		HPStage.CRATER: 0
	}

	for id in _buildings:
		var stage: int = _buildings[id].stage
		stage_counts[stage] = stage_counts.get(stage, 0) + 1

	return {
		"total_buildings": _buildings.size(),
		"by_stage": stage_counts,
		"destroyed": get_destroyed_buildings().size()
	}
