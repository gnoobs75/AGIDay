class_name TerrainFlatteningSystem
extends RefCounted
## TerrainFlatteningSystem handles building disassembly and wreck harvesting.
## Transforms urban landscape into flattened wasteland, tracking map evolution.

signal building_flattening_started(building_id: int, position: Vector3, duration: float)
signal building_flattening_completed(building_id: int, position: Vector3, ree_yield: float)
signal wreck_harvesting_started(wreck_id: int, position: Vector3, duration: float)
signal wreck_harvesting_completed(wreck_id: int, position: Vector3, ree_yield: float)
signal terrain_smoothed(position: Vector3, radius: float)
signal map_stage_changed(old_stage: int, new_stage: int)
signal destruction_percentage_updated(percentage: float)
signal pathfinding_update_required(area: AABB)

## Map evolution stages
enum MapStage {
	EARLY_GAME,     ## <30% destroyed
	MID_GAME,       ## 30-70% destroyed
	LATE_GAME       ## >70% destroyed
}

## Stage thresholds
const EARLY_GAME_THRESHOLD := 0.30
const MID_GAME_THRESHOLD := 0.70

## Building type REE yields
const BUILDING_REE_YIELDS := {
	"residential": 100.0,
	"commercial": 150.0,
	"industrial": 200.0,
	"power_plant": 250.0,
	"factory": 300.0,
	"tower": 175.0,
	"warehouse": 125.0
}

## Size multipliers for REE yield
const SIZE_MULTIPLIERS := {
	"small": 0.5,
	"medium": 1.0,
	"large": 1.5,
	"massive": 2.0
}

## Damage state modifiers (damaged buildings yield less)
const DAMAGE_MODIFIERS := {
	"intact": 1.0,
	"damaged": 0.8,
	"critical": 0.6,
	"rubble": 0.4
}

## Base disassembly/harvesting times (seconds)
const BASE_DISASSEMBLY_TIME := 30.0
const BASE_HARVESTING_TIME := 20.0
const TIME_PER_SIZE_UNIT := 5.0

## Smoothing configuration
const SMOOTHING_RADIUS_BASE := 2.0
const SMOOTHING_RADIUS_PER_SIZE := 1.0
const SMOOTHED_TERRAIN_HEIGHT := 0.0

## Active operations
var _active_disassembly: Dictionary = {}    ## building_id -> DisassemblyOperation
var _active_harvesting: Dictionary = {}      ## wreck_id -> HarvestingOperation
var _completed_buildings: Array[int] = []
var _completed_wrecks: Array[int] = []

## Map state tracking
var _total_buildings: int = 0
var _destroyed_buildings: int = 0
var _flattened_buildings: int = 0
var _current_stage: MapStage = MapStage.EARLY_GAME
var _destruction_percentage: float = 0.0

## Terrain data (coordinate -> TerrainCell)
var _terrain_cells: Dictionary = {}
var _smoothed_areas: Array[AABB] = []


func _init() -> void:
	pass


## Initialize with total building count.
func initialize(total_building_count: int) -> void:
	_total_buildings = total_building_count
	_destroyed_buildings = 0
	_flattened_buildings = 0
	_current_stage = MapStage.EARLY_GAME
	_destruction_percentage = 0.0

	_active_disassembly.clear()
	_active_harvesting.clear()
	_completed_buildings.clear()
	_completed_wrecks.clear()
	_terrain_cells.clear()
	_smoothed_areas.clear()


## Update system (call every frame).
func update(delta: float) -> void:
	_update_disassembly_operations(delta)
	_update_harvesting_operations(delta)


## Update all active disassembly operations.
func _update_disassembly_operations(delta: float) -> void:
	var completed_ids: Array[int] = []

	for building_id in _active_disassembly:
		var op: DisassemblyOperation = _active_disassembly[building_id]
		op.progress += delta

		if op.progress >= op.duration:
			_complete_disassembly(building_id)
			completed_ids.append(building_id)

	for building_id in completed_ids:
		_active_disassembly.erase(building_id)


## Update all active harvesting operations.
func _update_harvesting_operations(delta: float) -> void:
	var completed_ids: Array[int] = []

	for wreck_id in _active_harvesting:
		var op: HarvestingOperation = _active_harvesting[wreck_id]
		op.progress += delta

		if op.progress >= op.duration:
			_complete_harvesting(wreck_id)
			completed_ids.append(wreck_id)

	for wreck_id in completed_ids:
		_active_harvesting.erase(wreck_id)


# ============================================
# BUILDING DISASSEMBLY
# ============================================

## Start disassembling a building.
func start_building_disassembly(building_id: int, building_data: Dictionary) -> bool:
	if _active_disassembly.has(building_id):
		return false

	if building_id in _completed_buildings:
		return false

	var building_type: String = building_data.get("type", "residential")
	var building_size: String = building_data.get("size", "medium")
	var damage_state: String = building_data.get("damage_state", "intact")
	var position: Vector3 = building_data.get("position", Vector3.ZERO)
	var bounds: AABB = building_data.get("bounds", AABB(position, Vector3.ONE * 5))

	# Calculate duration
	var size_factor := _get_size_factor(building_size)
	var duration := BASE_DISASSEMBLY_TIME + TIME_PER_SIZE_UNIT * size_factor

	# Calculate REE yield
	var ree_yield := _calculate_building_yield(building_type, building_size, damage_state)

	# Create operation
	var op := DisassemblyOperation.new()
	op.building_id = building_id
	op.building_type = building_type
	op.building_size = building_size
	op.damage_state = damage_state
	op.position = position
	op.bounds = bounds
	op.duration = duration
	op.ree_yield = ree_yield
	op.progress = 0.0

	_active_disassembly[building_id] = op

	building_flattening_started.emit(building_id, position, duration)
	return true


## Complete building disassembly.
func _complete_disassembly(building_id: int) -> void:
	if not _active_disassembly.has(building_id):
		return

	var op: DisassemblyOperation = _active_disassembly[building_id]

	# Mark as completed
	_completed_buildings.append(building_id)
	_flattened_buildings += 1

	# Flatten terrain in building area
	_flatten_area(op.position, op.bounds, op.building_size)

	# Update map state
	_update_destruction_state()

	building_flattening_completed.emit(building_id, op.position, op.ree_yield)


## Calculate REE yield for a building.
func _calculate_building_yield(building_type: String, size: String, damage_state: String) -> float:
	var base_yield: float = BUILDING_REE_YIELDS.get(building_type, 100.0)
	var size_mult: float = SIZE_MULTIPLIERS.get(size, 1.0)
	var damage_mult: float = DAMAGE_MODIFIERS.get(damage_state, 1.0)

	return base_yield * size_mult * damage_mult


# ============================================
# WRECK HARVESTING
# ============================================

## Start harvesting a wreck.
func start_wreck_harvesting(wreck_id: int, wreck_data: Dictionary) -> bool:
	if _active_harvesting.has(wreck_id):
		return false

	if wreck_id in _completed_wrecks:
		return false

	var wreck_type: String = wreck_data.get("type", "debris")
	var wreck_size: int = wreck_data.get("size", 1)
	var position: Vector3 = wreck_data.get("position", Vector3.ZERO)
	var original_building_type: String = wreck_data.get("original_building_type", "residential")

	# Calculate duration
	var duration := BASE_HARVESTING_TIME + wreck_size * 2.0

	# Calculate REE yield (wrecks yield less than intact buildings)
	var base_yield: float = BUILDING_REE_YIELDS.get(original_building_type, 100.0)
	var ree_yield := base_yield * 0.4 + wreck_size * 10.0

	# Create operation
	var op := HarvestingOperation.new()
	op.wreck_id = wreck_id
	op.wreck_type = wreck_type
	op.wreck_size = wreck_size
	op.position = position
	op.original_building_type = original_building_type
	op.duration = duration
	op.ree_yield = ree_yield
	op.progress = 0.0

	_active_harvesting[wreck_id] = op

	wreck_harvesting_started.emit(wreck_id, position, duration)
	return true


## Complete wreck harvesting.
func _complete_harvesting(wreck_id: int) -> void:
	if not _active_harvesting.has(wreck_id):
		return

	var op: HarvestingOperation = _active_harvesting[wreck_id]

	# Mark as completed
	_completed_wrecks.append(wreck_id)

	# Smooth terrain at wreck location
	var smooth_radius := SMOOTHING_RADIUS_BASE + op.wreck_size * 0.5
	_smooth_terrain(op.position, smooth_radius)

	wreck_harvesting_completed.emit(wreck_id, op.position, op.ree_yield)


# ============================================
# TERRAIN MODIFICATION
# ============================================

## Flatten area where building was removed.
func _flatten_area(position: Vector3, bounds: AABB, building_size: String) -> void:
	var size_factor := _get_size_factor(building_size)
	var smooth_radius := SMOOTHING_RADIUS_BASE + SMOOTHING_RADIUS_PER_SIZE * size_factor

	# Create flattened terrain cell
	var cell := TerrainCell.new()
	cell.position = position
	cell.bounds = bounds
	cell.is_flattened = true
	cell.height = SMOOTHED_TERRAIN_HEIGHT
	cell.traversable = true

	var cell_key := _get_cell_key(position)
	_terrain_cells[cell_key] = cell

	# Track smoothed area for pathfinding updates
	var expanded_bounds := AABB(
		bounds.position - Vector3.ONE * smooth_radius,
		bounds.size + Vector3.ONE * smooth_radius * 2
	)
	_smoothed_areas.append(expanded_bounds)

	# Smooth surrounding terrain
	_smooth_terrain(position, smooth_radius)

	# Notify pathfinding system
	pathfinding_update_required.emit(expanded_bounds)
	terrain_smoothed.emit(position, smooth_radius)


## Smooth terrain around a position.
func _smooth_terrain(center: Vector3, radius: float) -> void:
	# Create smooth terrain cells in radius
	var step := 2.0
	var half_radius := radius / 2.0

	for x in range(-int(half_radius / step), int(half_radius / step) + 1):
		for z in range(-int(half_radius / step), int(half_radius / step) + 1):
			var offset := Vector3(x * step, 0, z * step)
			var pos := center + offset

			if pos.distance_to(center) <= radius:
				var cell_key := _get_cell_key(pos)
				if not _terrain_cells.has(cell_key):
					var cell := TerrainCell.new()
					cell.position = pos
					cell.is_flattened = true
					cell.height = SMOOTHED_TERRAIN_HEIGHT
					cell.traversable = true
					_terrain_cells[cell_key] = cell


## Get cell key for position.
func _get_cell_key(position: Vector3) -> String:
	var grid_x := int(position.x / 2.0)
	var grid_z := int(position.z / 2.0)
	return "%d_%d" % [grid_x, grid_z]


## Get size factor from size name.
func _get_size_factor(size: String) -> float:
	match size:
		"small": return 1.0
		"medium": return 2.0
		"large": return 3.0
		"massive": return 5.0
	return 2.0


# ============================================
# MAP EVOLUTION TRACKING
# ============================================

## Update destruction state and check for stage change.
func _update_destruction_state() -> void:
	if _total_buildings <= 0:
		return

	var old_percentage := _destruction_percentage
	_destruction_percentage = float(_destroyed_buildings + _flattened_buildings) / float(_total_buildings)

	if _destruction_percentage != old_percentage:
		destruction_percentage_updated.emit(_destruction_percentage)

	# Check for stage change
	var new_stage := _calculate_map_stage()
	if new_stage != _current_stage:
		var old_stage := _current_stage
		_current_stage = new_stage
		map_stage_changed.emit(old_stage, new_stage)


## Calculate current map stage.
func _calculate_map_stage() -> MapStage:
	if _destruction_percentage < EARLY_GAME_THRESHOLD:
		return MapStage.EARLY_GAME
	elif _destruction_percentage < MID_GAME_THRESHOLD:
		return MapStage.MID_GAME
	else:
		return MapStage.LATE_GAME


## Register building destruction (not from harvesting).
func register_building_destroyed(building_id: int) -> void:
	_destroyed_buildings += 1
	_update_destruction_state()


# ============================================
# QUERY METHODS
# ============================================

## Check if building is being disassembled.
func is_disassembling(building_id: int) -> bool:
	return _active_disassembly.has(building_id)


## Check if wreck is being harvested.
func is_harvesting(wreck_id: int) -> bool:
	return _active_harvesting.has(wreck_id)


## Check if building was already flattened.
func is_building_flattened(building_id: int) -> bool:
	return building_id in _completed_buildings


## Check if wreck was already harvested.
func is_wreck_harvested(wreck_id: int) -> bool:
	return wreck_id in _completed_wrecks


## Get disassembly progress (0.0 - 1.0).
func get_disassembly_progress(building_id: int) -> float:
	if not _active_disassembly.has(building_id):
		return 0.0
	var op: DisassemblyOperation = _active_disassembly[building_id]
	return op.progress / op.duration


## Get harvesting progress (0.0 - 1.0).
func get_harvesting_progress(wreck_id: int) -> float:
	if not _active_harvesting.has(wreck_id):
		return 0.0
	var op: HarvestingOperation = _active_harvesting[wreck_id]
	return op.progress / op.duration


## Get current map stage.
func get_map_stage() -> MapStage:
	return _current_stage


## Get destruction percentage.
func get_destruction_percentage() -> float:
	return _destruction_percentage


## Check if position is flattened terrain.
func is_terrain_flattened(position: Vector3) -> bool:
	var cell_key := _get_cell_key(position)
	if _terrain_cells.has(cell_key):
		return _terrain_cells[cell_key].is_flattened
	return false


## Get terrain height at position.
func get_terrain_height(position: Vector3) -> float:
	var cell_key := _get_cell_key(position)
	if _terrain_cells.has(cell_key):
		return _terrain_cells[cell_key].height
	return 0.0


## Get stage name.
static func get_stage_name(stage: MapStage) -> String:
	match stage:
		MapStage.EARLY_GAME: return "Early Game"
		MapStage.MID_GAME: return "Mid Game"
		MapStage.LATE_GAME: return "Late Game"
	return "Unknown"


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"total_buildings": _total_buildings,
		"destroyed_buildings": _destroyed_buildings,
		"flattened_buildings": _flattened_buildings,
		"destruction_percentage": _destruction_percentage,
		"current_stage": get_stage_name(_current_stage),
		"active_disassembly": _active_disassembly.size(),
		"active_harvesting": _active_harvesting.size(),
		"completed_buildings": _completed_buildings.size(),
		"completed_wrecks": _completed_wrecks.size(),
		"terrain_cells": _terrain_cells.size()
	}


# ============================================
# CANCELLATION
# ============================================

## Cancel disassembly operation.
func cancel_disassembly(building_id: int) -> void:
	_active_disassembly.erase(building_id)


## Cancel harvesting operation.
func cancel_harvesting(wreck_id: int) -> void:
	_active_harvesting.erase(wreck_id)


# ============================================
# SERIALIZATION
# ============================================

## Serialize to dictionary.
func to_dict() -> Dictionary:
	var disassembly_data := {}
	for building_id in _active_disassembly:
		disassembly_data[str(building_id)] = _active_disassembly[building_id].to_dict()

	var harvesting_data := {}
	for wreck_id in _active_harvesting:
		harvesting_data[str(wreck_id)] = _active_harvesting[wreck_id].to_dict()

	var cells_data := {}
	for key in _terrain_cells:
		cells_data[key] = _terrain_cells[key].to_dict()

	return {
		"total_buildings": _total_buildings,
		"destroyed_buildings": _destroyed_buildings,
		"flattened_buildings": _flattened_buildings,
		"current_stage": _current_stage,
		"destruction_percentage": _destruction_percentage,
		"active_disassembly": disassembly_data,
		"active_harvesting": harvesting_data,
		"completed_buildings": _completed_buildings.duplicate(),
		"completed_wrecks": _completed_wrecks.duplicate(),
		"terrain_cells": cells_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_total_buildings = data.get("total_buildings", 0)
	_destroyed_buildings = data.get("destroyed_buildings", 0)
	_flattened_buildings = data.get("flattened_buildings", 0)
	_current_stage = data.get("current_stage", MapStage.EARLY_GAME)
	_destruction_percentage = data.get("destruction_percentage", 0.0)

	_active_disassembly.clear()
	var disassembly_data: Dictionary = data.get("active_disassembly", {})
	for key in disassembly_data:
		var op := DisassemblyOperation.new()
		op.from_dict(disassembly_data[key])
		_active_disassembly[int(key)] = op

	_active_harvesting.clear()
	var harvesting_data: Dictionary = data.get("active_harvesting", {})
	for key in harvesting_data:
		var op := HarvestingOperation.new()
		op.from_dict(harvesting_data[key])
		_active_harvesting[int(key)] = op

	_completed_buildings.clear()
	for b_id in data.get("completed_buildings", []):
		_completed_buildings.append(b_id)

	_completed_wrecks.clear()
	for w_id in data.get("completed_wrecks", []):
		_completed_wrecks.append(w_id)

	_terrain_cells.clear()
	var cells_data: Dictionary = data.get("terrain_cells", {})
	for key in cells_data:
		var cell := TerrainCell.new()
		cell.from_dict(cells_data[key])
		_terrain_cells[key] = cell


## DisassemblyOperation inner class.
class DisassemblyOperation:
	var building_id: int = -1
	var building_type: String = ""
	var building_size: String = "medium"
	var damage_state: String = "intact"
	var position: Vector3 = Vector3.ZERO
	var bounds: AABB = AABB()
	var duration: float = 30.0
	var ree_yield: float = 100.0
	var progress: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"building_id": building_id,
			"building_type": building_type,
			"building_size": building_size,
			"damage_state": damage_state,
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"bounds_pos": {"x": bounds.position.x, "y": bounds.position.y, "z": bounds.position.z},
			"bounds_size": {"x": bounds.size.x, "y": bounds.size.y, "z": bounds.size.z},
			"duration": duration,
			"ree_yield": ree_yield,
			"progress": progress
		}

	func from_dict(data: Dictionary) -> void:
		building_id = data.get("building_id", -1)
		building_type = data.get("building_type", "")
		building_size = data.get("building_size", "medium")
		damage_state = data.get("damage_state", "intact")
		var pos: Dictionary = data.get("position", {})
		position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		var b_pos: Dictionary = data.get("bounds_pos", {})
		var b_size: Dictionary = data.get("bounds_size", {})
		bounds = AABB(
			Vector3(b_pos.get("x", 0), b_pos.get("y", 0), b_pos.get("z", 0)),
			Vector3(b_size.get("x", 1), b_size.get("y", 1), b_size.get("z", 1))
		)
		duration = data.get("duration", 30.0)
		ree_yield = data.get("ree_yield", 100.0)
		progress = data.get("progress", 0.0)


## HarvestingOperation inner class.
class HarvestingOperation:
	var wreck_id: int = -1
	var wreck_type: String = "debris"
	var wreck_size: int = 1
	var position: Vector3 = Vector3.ZERO
	var original_building_type: String = ""
	var duration: float = 20.0
	var ree_yield: float = 50.0
	var progress: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"wreck_id": wreck_id,
			"wreck_type": wreck_type,
			"wreck_size": wreck_size,
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"original_building_type": original_building_type,
			"duration": duration,
			"ree_yield": ree_yield,
			"progress": progress
		}

	func from_dict(data: Dictionary) -> void:
		wreck_id = data.get("wreck_id", -1)
		wreck_type = data.get("wreck_type", "debris")
		wreck_size = data.get("wreck_size", 1)
		var pos: Dictionary = data.get("position", {})
		position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		original_building_type = data.get("original_building_type", "")
		duration = data.get("duration", 20.0)
		ree_yield = data.get("ree_yield", 50.0)
		progress = data.get("progress", 0.0)


## TerrainCell inner class.
class TerrainCell:
	var position: Vector3 = Vector3.ZERO
	var bounds: AABB = AABB()
	var is_flattened: bool = false
	var height: float = 0.0
	var traversable: bool = true

	func to_dict() -> Dictionary:
		return {
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"bounds_pos": {"x": bounds.position.x, "y": bounds.position.y, "z": bounds.position.z},
			"bounds_size": {"x": bounds.size.x, "y": bounds.size.y, "z": bounds.size.z},
			"is_flattened": is_flattened,
			"height": height,
			"traversable": traversable
		}

	func from_dict(data: Dictionary) -> void:
		var pos: Dictionary = data.get("position", {})
		position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		var b_pos: Dictionary = data.get("bounds_pos", {})
		var b_size: Dictionary = data.get("bounds_size", {})
		bounds = AABB(
			Vector3(b_pos.get("x", 0), b_pos.get("y", 0), b_pos.get("z", 0)),
			Vector3(b_size.get("x", 1), b_size.get("y", 1), b_size.get("z", 1))
		)
		is_flattened = data.get("is_flattened", false)
		height = data.get("height", 0.0)
		traversable = data.get("traversable", true)
