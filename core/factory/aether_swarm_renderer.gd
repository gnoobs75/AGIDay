class_name AetherSwarmRenderer
extends RefCounted
## AetherSwarmRenderer handles high-performance rendering for Aether Swarm units.
## Optimized for 5,000+ simultaneous drone instances.

signal units_rendered(count: int)
signal lod_changed(unit_count: int, lod_level: int)

## Unit types for Aether Swarm
const UNIT_TYPES := {
	"aether_drone": {
		"mesh_path": "res://assets/meshes/aether/drone.tres",
		"initial_pool": 2000,
		"max_pool": 5000
	},
	"aether_scout": {
		"mesh_path": "res://assets/meshes/aether/scout.tres",
		"initial_pool": 500,
		"max_pool": 2000
	},
	"aether_infiltrator": {
		"mesh_path": "res://assets/meshes/aether/infiltrator.tres",
		"initial_pool": 200,
		"max_pool": 1000
	},
	"aether_phaser": {
		"mesh_path": "res://assets/meshes/aether/phaser.tres",
		"initial_pool": 300,
		"max_pool": 1500
	}
}

## LOD distances
const LOD_DISTANCES := [50.0, 100.0, 200.0]  ## Near, Medium, Far

## MultiMesh pool
var _multimesh_pool: MultiMeshPool = null

## Unit tracking
var _unit_instances: Dictionary = {}  ## unit_id -> {type, transform, lod_level}

## LOD meshes
var _lod_meshes: Dictionary = {}  ## unit_type -> [lod0, lod1, lod2]

## Camera reference for LOD
var _camera_position := Vector3.ZERO

## Batch processing
const BATCH_SIZE := 100
var _pending_adds: Array[Dictionary] = []
var _pending_removes: Array[int] = []

## Statistics
var _rendered_count := 0
var _lod_counts := [0, 0, 0]  ## Per LOD level


func _init() -> void:
	_multimesh_pool = MultiMeshPool.new()


## Initialize renderer.
func initialize(scene_root: Node3D) -> void:
	_multimesh_pool.initialize(scene_root)
	_create_unit_pools()


## Create pools for all Aether unit types.
func _create_unit_pools() -> void:
	for unit_type in UNIT_TYPES:
		var config: Dictionary = UNIT_TYPES[unit_type]
		var mesh := _load_or_create_mesh(unit_type)

		_multimesh_pool.create_pool(
			unit_type,
			mesh,
			config["initial_pool"]
		)


## Load or create placeholder mesh.
func _load_or_create_mesh(unit_type: String) -> Mesh:
	var config: Dictionary = UNIT_TYPES.get(unit_type, {})
	var mesh_path: String = config.get("mesh_path", "")

	if ResourceLoader.exists(mesh_path):
		return load(mesh_path)

	# Create placeholder mesh
	return _create_placeholder_mesh(unit_type)


## Create placeholder mesh for unit type.
func _create_placeholder_mesh(unit_type: String) -> Mesh:
	var mesh := SphereMesh.new()

	match unit_type:
		"aether_drone":
			mesh.radius = 0.3
			mesh.height = 0.6
		"aether_scout":
			mesh.radius = 0.4
			mesh.height = 0.8
		"aether_infiltrator":
			mesh.radius = 0.5
			mesh.height = 1.0
		"aether_phaser":
			mesh.radius = 0.6
			mesh.height = 1.2
		_:
			mesh.radius = 0.5
			mesh.height = 1.0

	# Create material with Aether Swarm colors (cyan/teal)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.0, 0.8, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.0, 0.5, 0.6)
	material.emission_energy_multiplier = 0.5
	mesh.material = material

	return mesh


## Add unit to renderer.
func add_unit(unit_id: int, unit_type: String, position: Vector3, rotation: float = 0.0) -> void:
	if not UNIT_TYPES.has(unit_type):
		push_warning("AetherSwarmRenderer: Unknown unit type '%s'" % unit_type)
		return

	var transform := Transform3D()
	transform.origin = position
	transform.basis = Basis(Vector3.UP, rotation)

	var instance_index := _multimesh_pool.add_instance(unit_type, unit_id, transform)

	if instance_index >= 0:
		_unit_instances[unit_id] = {
			"type": unit_type,
			"transform": transform,
			"lod_level": 0
		}
		_rendered_count += 1


## Remove unit from renderer.
func remove_unit(unit_id: int) -> void:
	if not _unit_instances.has(unit_id):
		return

	var info: Dictionary = _unit_instances[unit_id]
	_multimesh_pool.remove_instance(info["type"], unit_id)
	_unit_instances.erase(unit_id)
	_rendered_count -= 1


## Update unit transform.
func update_unit(unit_id: int, position: Vector3, rotation: float = 0.0) -> void:
	if not _unit_instances.has(unit_id):
		return

	var info: Dictionary = _unit_instances[unit_id]
	var transform := Transform3D()
	transform.origin = position
	transform.basis = Basis(Vector3.UP, rotation)

	info["transform"] = transform
	_multimesh_pool.queue_transform_update(info["type"], unit_id, transform)


## Batch add units.
func batch_add_units(units: Array[Dictionary]) -> void:
	for unit_data in units:
		add_unit(
			unit_data["id"],
			unit_data["type"],
			unit_data["position"],
			unit_data.get("rotation", 0.0)
		)


## Batch remove units.
func batch_remove_units(unit_ids: Array[int]) -> void:
	for unit_id in unit_ids:
		remove_unit(unit_id)


## Update (call each frame).
func update(delta: float, camera_position: Vector3) -> void:
	_camera_position = camera_position

	# Process pending batched updates
	_multimesh_pool.process_pending_updates()

	# Update LOD levels periodically
	_update_lod_levels()

	units_rendered.emit(_rendered_count)


## Update LOD levels based on camera distance.
func _update_lod_levels() -> void:
	_lod_counts = [0, 0, 0]

	for unit_id in _unit_instances:
		var info: Dictionary = _unit_instances[unit_id]
		var transform: Transform3D = info["transform"]
		var distance := _camera_position.distance_to(transform.origin)

		var new_lod := 0
		if distance > LOD_DISTANCES[2]:
			new_lod = 2
		elif distance > LOD_DISTANCES[1]:
			new_lod = 1
		elif distance > LOD_DISTANCES[0]:
			new_lod = 0

		if new_lod != info["lod_level"]:
			info["lod_level"] = new_lod
			# Could switch mesh LOD here if implemented

		_lod_counts[new_lod] += 1


## Set visibility for unit type.
func set_type_visible(unit_type: String, visible: bool) -> void:
	# Would need to access the MultiMeshInstance3D node
	pass


## Get unit count by type.
func get_unit_count(unit_type: String) -> int:
	return _multimesh_pool.get_instance_count(unit_type)


## Get total rendered count.
func get_total_count() -> int:
	return _rendered_count


## Get LOD distribution.
func get_lod_distribution() -> Array[int]:
	return _lod_counts.duplicate()


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"rendered_count": _rendered_count,
		"lod_distribution": _lod_counts.duplicate(),
		"pool_stats": _multimesh_pool.get_statistics()
	}


## Cleanup.
func cleanup() -> void:
	_multimesh_pool.cleanup()
	_unit_instances.clear()
	_rendered_count = 0
