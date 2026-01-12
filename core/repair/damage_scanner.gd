class_name DamageScanner
extends RefCounted
## DamageScanner detects damaged voxels within a scan radius for repair targeting.

signal scan_completed(scanner_id: int, damaged_count: int)
signal scan_started(scanner_id: int)
signal damaged_voxel_found(position: Vector3i, damage_stage: int)

## Damage stages
const STAGE_INTACT := 0
const STAGE_CRACKED := 1
const STAGE_RUBBLE := 2
const STAGE_CRATER := 3

## Default scan radius
const DEFAULT_SCAN_RADIUS := 10.0

## Faction-specific scan radii
const FACTION_SCAN_RADII := {
	"AETHER_SWARM": 10.0,
	"OPTIFORGE_LEGION": 8.0,
	"DYNAPODS_VANGUARD": 12.0,
	"LOGIBOTS_COLOSSUS": 9.0
}

## Scanner identity
var scanner_id: int = -1
var faction_id: String = ""

## Scan configuration
var scan_radius: float = DEFAULT_SCAN_RADIUS
var scan_position: Vector3 = Vector3.ZERO

## Last scan results
var _last_scan_results: Array[DamagedVoxelInfo] = []
var _scan_in_progress: bool = false


## Damaged voxel info class
class DamagedVoxelInfo:
	var position: Vector3i = Vector3i.ZERO
	var world_position: Vector3 = Vector3.ZERO
	var damage_stage: int = 0
	var distance: float = 0.0

	func _init(pos: Vector3i = Vector3i.ZERO, world_pos: Vector3 = Vector3.ZERO, stage: int = 0, dist: float = 0.0) -> void:
		position = pos
		world_position = world_pos
		damage_stage = stage
		distance = dist


func _init() -> void:
	pass


## Initialize scanner.
func initialize(p_scanner_id: int, p_faction_id: String = "") -> void:
	scanner_id = p_scanner_id
	faction_id = p_faction_id

	# Set faction-specific scan radius
	if FACTION_SCAN_RADII.has(faction_id):
		scan_radius = FACTION_SCAN_RADII[faction_id]
	else:
		scan_radius = DEFAULT_SCAN_RADIUS


## Set scan position.
func set_scan_position(position: Vector3) -> void:
	scan_position = position


## Set custom scan radius.
func set_scan_radius(radius: float) -> void:
	scan_radius = maxf(radius, 1.0)


## Scan for damaged voxels using a voxel grid callback.
## Returns array of DamagedVoxelInfo sorted by distance.
func scan_for_damaged_voxels(get_voxel_state_callback: Callable) -> Array[DamagedVoxelInfo]:
	_scan_in_progress = true
	scan_started.emit(scanner_id)

	_last_scan_results.clear()

	# Calculate voxel bounds to scan
	var center_voxel := Vector3i(
		roundi(scan_position.x),
		roundi(scan_position.y),
		roundi(scan_position.z)
	)

	var radius_int := ceili(scan_radius)
	var radius_sq := scan_radius * scan_radius

	# Scan all voxels in radius
	for x in range(-radius_int, radius_int + 1):
		for y in range(-radius_int, radius_int + 1):
			for z in range(-radius_int, radius_int + 1):
				var voxel_pos := center_voxel + Vector3i(x, y, z)
				var world_pos := Vector3(voxel_pos)

				# Check distance
				var distance := scan_position.distance_to(world_pos)
				if distance > scan_radius:
					continue

				# Get voxel state through callback
				var damage_stage: int = get_voxel_state_callback.call(voxel_pos)

				# Check if damaged (stage 1 or 2)
				if _is_repairable_damage(damage_stage):
					var info := DamagedVoxelInfo.new(voxel_pos, world_pos, damage_stage, distance)
					_last_scan_results.append(info)
					damaged_voxel_found.emit(voxel_pos, damage_stage)

	# Sort by distance
	_last_scan_results.sort_custom(_compare_by_distance)

	_scan_in_progress = false
	scan_completed.emit(scanner_id, _last_scan_results.size())

	return _last_scan_results


## Scan for damaged voxels within voxel positions array.
func scan_voxel_positions(
	positions: Array,
	get_voxel_state_callback: Callable
) -> Array[DamagedVoxelInfo]:
	_scan_in_progress = true
	scan_started.emit(scanner_id)

	_last_scan_results.clear()

	for pos in positions:
		if not pos is Vector3i:
			continue

		var voxel_pos: Vector3i = pos
		var world_pos := Vector3(voxel_pos)

		# Check distance
		var distance := scan_position.distance_to(world_pos)
		if distance > scan_radius:
			continue

		# Get voxel state through callback
		var damage_stage: int = get_voxel_state_callback.call(voxel_pos)

		# Check if damaged
		if _is_repairable_damage(damage_stage):
			var info := DamagedVoxelInfo.new(voxel_pos, world_pos, damage_stage, distance)
			_last_scan_results.append(info)
			damaged_voxel_found.emit(voxel_pos, damage_stage)

	# Sort by distance
	_last_scan_results.sort_custom(_compare_by_distance)

	_scan_in_progress = false
	scan_completed.emit(scanner_id, _last_scan_results.size())

	return _last_scan_results


## Check if damage stage is repairable.
func _is_repairable_damage(damage_stage: int) -> bool:
	return damage_stage == STAGE_CRACKED or damage_stage == STAGE_RUBBLE


## Compare function for sorting by distance.
func _compare_by_distance(a: DamagedVoxelInfo, b: DamagedVoxelInfo) -> bool:
	return a.distance < b.distance


## Get last scan results.
func get_last_scan_results() -> Array[DamagedVoxelInfo]:
	return _last_scan_results


## Get closest damaged voxel from last scan.
func get_closest_damaged() -> DamagedVoxelInfo:
	if _last_scan_results.is_empty():
		return null
	return _last_scan_results[0]


## Get damaged voxels at specific stage.
func get_damaged_at_stage(stage: int) -> Array[DamagedVoxelInfo]:
	var results: Array[DamagedVoxelInfo] = []
	for info in _last_scan_results:
		if info.damage_stage == stage:
			results.append(info)
	return results


## Check if any damaged voxels were found.
func has_damaged_voxels() -> bool:
	return not _last_scan_results.is_empty()


## Get damaged voxel count from last scan.
func get_damaged_count() -> int:
	return _last_scan_results.size()


## Check if scan is in progress.
func is_scanning() -> bool:
	return _scan_in_progress


## Clear last scan results.
func clear_results() -> void:
	_last_scan_results.clear()


## Get positions of all damaged voxels.
func get_damaged_positions() -> Array[Vector3i]:
	var positions: Array[Vector3i] = []
	for info in _last_scan_results:
		positions.append(info.position)
	return positions


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"scanner_id": scanner_id,
		"faction_id": faction_id,
		"scan_radius": scan_radius,
		"scan_position": scan_position,
		"damaged_count": _last_scan_results.size(),
		"is_scanning": _scan_in_progress
	}
