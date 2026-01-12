class_name AssemblyLODSystem
extends RefCounted
## AssemblyLODSystem manages level-of-detail and visibility for assembly animations.

signal lod_level_changed(assembly_id: int, lod_level: int)
signal assembly_culled(assembly_id: int)
signal assembly_visible(assembly_id: int)

## LOD levels
const LOD_FULL := 0       ## Full animation and particles
const LOD_REDUCED := 1    ## Animation only, no particles
const LOD_MINIMAL := 2    ## No animation, instant assembly
const LOD_CULLED := 3     ## Not visible, skip all visuals

## Distance thresholds (squared for performance)
const LOD_FULL_DISTANCE_SQ := 900.0      ## 30 units
const LOD_REDUCED_DISTANCE_SQ := 2500.0  ## 50 units
const LOD_MINIMAL_DISTANCE_SQ := 10000.0 ## 100 units

## Update frequency
const LOD_UPDATE_INTERVAL := 0.2  ## Seconds between LOD checks

## Assembly tracking
var _assembly_lod: Dictionary = {}  ## assembly_id -> LODData
var _time_since_update: float = 0.0

## Camera reference
var _camera_position: Vector3 = Vector3.ZERO
var _frustum_planes: Array = []  ## Plane array for frustum culling

## Performance stats
var _visible_count: int = 0
var _culled_count: int = 0


## LOD data for each assembly
class LODData:
	var assembly_id: int = -1
	var position: Vector3 = Vector3.ZERO
	var bounds_radius: float = 2.0
	var current_lod: int = LOD_FULL
	var is_visible: bool = true
	var distance_sq: float = 0.0


func _init() -> void:
	pass


## Register an assembly for LOD management.
func register_assembly(assembly_id: int, position: Vector3, bounds_radius: float = 2.0) -> void:
	var data := LODData.new()
	data.assembly_id = assembly_id
	data.position = position
	data.bounds_radius = bounds_radius
	data.current_lod = _calculate_lod(position)
	data.is_visible = true

	_assembly_lod[assembly_id] = data


## Unregister an assembly.
func unregister_assembly(assembly_id: int) -> void:
	_assembly_lod.erase(assembly_id)


## Update assembly position.
func update_position(assembly_id: int, position: Vector3) -> void:
	if _assembly_lod.has(assembly_id):
		_assembly_lod[assembly_id].position = position


## Update camera position for LOD calculations.
func update_camera(camera_position: Vector3, frustum_planes: Array = []) -> void:
	_camera_position = camera_position
	_frustum_planes = frustum_planes


## Update LOD levels for all assemblies (call periodically).
func update(delta: float) -> void:
	_time_since_update += delta
	if _time_since_update < LOD_UPDATE_INTERVAL:
		return

	_time_since_update = 0.0
	_visible_count = 0
	_culled_count = 0

	for assembly_id in _assembly_lod:
		var data: LODData = _assembly_lod[assembly_id]
		_update_assembly_lod(data)


## Update LOD for a single assembly.
func _update_assembly_lod(data: LODData) -> void:
	var old_lod := data.current_lod
	var was_visible := data.is_visible

	# Check frustum visibility first
	data.is_visible = _is_in_frustum(data.position, data.bounds_radius)

	if data.is_visible:
		_visible_count += 1
		data.current_lod = _calculate_lod(data.position)
	else:
		_culled_count += 1
		data.current_lod = LOD_CULLED

	# Emit signals for changes
	if data.current_lod != old_lod:
		lod_level_changed.emit(data.assembly_id, data.current_lod)

	if data.is_visible != was_visible:
		if data.is_visible:
			assembly_visible.emit(data.assembly_id)
		else:
			assembly_culled.emit(data.assembly_id)


## Calculate LOD level based on distance.
func _calculate_lod(position: Vector3) -> int:
	var distance_sq := position.distance_squared_to(_camera_position)

	if distance_sq <= LOD_FULL_DISTANCE_SQ:
		return LOD_FULL
	elif distance_sq <= LOD_REDUCED_DISTANCE_SQ:
		return LOD_REDUCED
	elif distance_sq <= LOD_MINIMAL_DISTANCE_SQ:
		return LOD_MINIMAL
	else:
		return LOD_CULLED


## Check if position is within camera frustum.
func _is_in_frustum(position: Vector3, radius: float) -> bool:
	if _frustum_planes.is_empty():
		# No frustum data, assume visible
		return true

	# Check against each frustum plane
	for plane in _frustum_planes:
		if plane is Plane:
			if plane.distance_to(position) < -radius:
				return false

	return true


## Get LOD level for an assembly.
func get_lod_level(assembly_id: int) -> int:
	if _assembly_lod.has(assembly_id):
		return _assembly_lod[assembly_id].current_lod
	return LOD_CULLED


## Check if assembly is visible.
func is_visible(assembly_id: int) -> bool:
	if _assembly_lod.has(assembly_id):
		return _assembly_lod[assembly_id].is_visible
	return false


## Check if assembly should show particles.
func should_show_particles(assembly_id: int) -> bool:
	return get_lod_level(assembly_id) == LOD_FULL


## Check if assembly should animate.
func should_animate(assembly_id: int) -> bool:
	var lod := get_lod_level(assembly_id)
	return lod == LOD_FULL or lod == LOD_REDUCED


## Check if assembly should skip to end.
func should_skip_animation(assembly_id: int) -> bool:
	var lod := get_lod_level(assembly_id)
	return lod == LOD_MINIMAL or lod == LOD_CULLED


## Get distance to assembly (squared).
func get_distance_squared(assembly_id: int) -> float:
	if _assembly_lod.has(assembly_id):
		return _assembly_lod[assembly_id].position.distance_squared_to(_camera_position)
	return INF


## Get visible assembly count.
func get_visible_count() -> int:
	return _visible_count


## Get culled assembly count.
func get_culled_count() -> int:
	return _culled_count


## Get all visible assembly IDs.
func get_visible_assemblies() -> Array[int]:
	var visible: Array[int] = []
	for assembly_id in _assembly_lod:
		if _assembly_lod[assembly_id].is_visible:
			visible.append(assembly_id)
	return visible


## Get all assemblies at a specific LOD level.
func get_assemblies_at_lod(lod_level: int) -> Array[int]:
	var result: Array[int] = []
	for assembly_id in _assembly_lod:
		if _assembly_lod[assembly_id].current_lod == lod_level:
			result.append(assembly_id)
	return result


## Force update all LOD levels immediately.
func force_update() -> void:
	_time_since_update = LOD_UPDATE_INTERVAL
	update(0.0)


## Clear all tracked assemblies.
func clear() -> void:
	_assembly_lod.clear()
	_visible_count = 0
	_culled_count = 0


## Get LOD level name for debugging.
static func get_lod_name(lod_level: int) -> String:
	match lod_level:
		LOD_FULL:
			return "Full"
		LOD_REDUCED:
			return "Reduced"
		LOD_MINIMAL:
			return "Minimal"
		LOD_CULLED:
			return "Culled"
		_:
			return "Unknown"


## Get summary for debugging.
func get_summary() -> Dictionary:
	var lod_counts: Dictionary = {
		"full": 0,
		"reduced": 0,
		"minimal": 0,
		"culled": 0
	}

	for assembly_id in _assembly_lod:
		var lod := _assembly_lod[assembly_id].current_lod
		match lod:
			LOD_FULL:
				lod_counts["full"] += 1
			LOD_REDUCED:
				lod_counts["reduced"] += 1
			LOD_MINIMAL:
				lod_counts["minimal"] += 1
			LOD_CULLED:
				lod_counts["culled"] += 1

	return {
		"total_tracked": _assembly_lod.size(),
		"visible": _visible_count,
		"culled": _culled_count,
		"lod_distribution": lod_counts,
		"camera_position": _camera_position
	}
