class_name MultiMeshPool
extends RefCounted
## MultiMeshPool manages high-performance instanced rendering for thousands of units.
## Uses MultiMesh for single draw call per unit type.

signal pool_created(unit_type: String)
signal instance_added(unit_type: String, instance_id: int)
signal instance_removed(unit_type: String, instance_id: int)
signal batch_updated(unit_type: String, count: int)

## Configuration
const MAX_INSTANCES_PER_POOL := 5000
const BATCH_SIZE := 100
const LOD_DISTANCE := 100.0
const INSTANTIATION_BUDGET_MS := 10.0

## Pool storage
var _pools: Dictionary = {}  ## unit_type -> MultiMeshData

## Instance tracking
var _instance_map: Dictionary = {}  ## unit_type -> {unit_id -> instance_index}
var _reverse_map: Dictionary = {}   ## unit_type -> {instance_index -> unit_id}

## Free instance tracking (for reuse)
var _free_instances: Dictionary = {}  ## unit_type -> Array[int]

## Pending updates (batched)
var _pending_transforms: Dictionary = {}  ## unit_type -> Array[{index, transform}]

## Scene tree reference
var _scene_root: Node3D = null

## Statistics
var _total_instances := 0
var _total_draw_calls := 0
var _update_time_ms := 0.0


func _init() -> void:
	pass


## Initialize with scene root for adding MultiMeshInstance3D nodes.
func initialize(scene_root: Node3D) -> void:
	_scene_root = scene_root


## Create pool for unit type.
func create_pool(unit_type: String, mesh: Mesh, initial_capacity: int = 1000) -> void:
	if _pools.has(unit_type):
		push_warning("MultiMeshPool: Pool for '%s' already exists" % unit_type)
		return

	var data := MultiMeshData.new()
	data.unit_type = unit_type
	data.capacity = mini(initial_capacity, MAX_INSTANCES_PER_POOL)

	# Create MultiMesh
	data.multimesh = MultiMesh.new()
	data.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	data.multimesh.instance_count = data.capacity
	data.multimesh.visible_instance_count = 0
	data.multimesh.mesh = mesh

	# Create MultiMeshInstance3D
	data.instance_node = MultiMeshInstance3D.new()
	data.instance_node.name = "MultiMesh_" + unit_type
	data.instance_node.multimesh = data.multimesh
	data.instance_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	data.instance_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	if _scene_root != null:
		_scene_root.add_child(data.instance_node)

	_pools[unit_type] = data
	_instance_map[unit_type] = {}
	_reverse_map[unit_type] = {}
	_free_instances[unit_type] = []
	_pending_transforms[unit_type] = []

	_total_draw_calls += 1
	pool_created.emit(unit_type)


## Add instance to pool.
func add_instance(unit_type: String, unit_id: int, transform: Transform3D) -> int:
	if not _pools.has(unit_type):
		push_error("MultiMeshPool: Pool '%s' not found" % unit_type)
		return -1

	var data: MultiMeshData = _pools[unit_type]
	var instance_map: Dictionary = _instance_map[unit_type]
	var reverse_map: Dictionary = _reverse_map[unit_type]
	var free_list: Array = _free_instances[unit_type]

	# Check if unit already has instance
	if instance_map.has(unit_id):
		return instance_map[unit_id]

	var instance_index: int

	# Reuse free instance or allocate new
	if not free_list.is_empty():
		instance_index = free_list.pop_back()
	else:
		# Need new instance
		if data.active_count >= data.capacity:
			# Try to expand
			if not _expand_pool(unit_type):
				push_warning("MultiMeshPool: Pool '%s' at max capacity" % unit_type)
				return -1

		instance_index = data.active_count
		data.active_count += 1
		data.multimesh.visible_instance_count = data.active_count

	# Set transform
	data.multimesh.set_instance_transform(instance_index, transform)

	# Track mapping
	instance_map[unit_id] = instance_index
	reverse_map[instance_index] = unit_id

	_total_instances += 1
	instance_added.emit(unit_type, instance_index)

	return instance_index


## Remove instance from pool.
func remove_instance(unit_type: String, unit_id: int) -> void:
	if not _pools.has(unit_type):
		return

	var data: MultiMeshData = _pools[unit_type]
	var instance_map: Dictionary = _instance_map[unit_type]
	var reverse_map: Dictionary = _reverse_map[unit_type]
	var free_list: Array = _free_instances[unit_type]

	if not instance_map.has(unit_id):
		return

	var instance_index: int = instance_map[unit_id]

	# Instance swapping: move last instance to this slot
	var last_index := data.active_count - 1

	if instance_index != last_index:
		# Get last instance's unit ID
		var last_unit_id: int = reverse_map.get(last_index, -1)

		if last_unit_id >= 0:
			# Copy last transform to removed slot
			var last_transform := data.multimesh.get_instance_transform(last_index)
			data.multimesh.set_instance_transform(instance_index, last_transform)

			# Update mappings for swapped instance
			instance_map[last_unit_id] = instance_index
			reverse_map[instance_index] = last_unit_id

	# Remove from maps
	instance_map.erase(unit_id)
	reverse_map.erase(last_index)

	# Reduce visible count
	data.active_count -= 1
	data.multimesh.visible_instance_count = data.active_count

	_total_instances -= 1
	instance_removed.emit(unit_type, instance_index)


## Update instance transform.
func update_transform(unit_type: String, unit_id: int, transform: Transform3D) -> void:
	if not _pools.has(unit_type):
		return

	var instance_map: Dictionary = _instance_map[unit_type]
	if not instance_map.has(unit_id):
		return

	var instance_index: int = instance_map[unit_id]
	var data: MultiMeshData = _pools[unit_type]

	data.multimesh.set_instance_transform(instance_index, transform)


## Queue transform update for batching.
func queue_transform_update(unit_type: String, unit_id: int, transform: Transform3D) -> void:
	if not _pools.has(unit_type):
		return

	var instance_map: Dictionary = _instance_map[unit_type]
	if not instance_map.has(unit_id):
		return

	var instance_index: int = instance_map[unit_id]
	_pending_transforms[unit_type].append({
		"index": instance_index,
		"transform": transform
	})


## Process pending transform updates in batches.
func process_pending_updates() -> void:
	var start_time := Time.get_ticks_usec()

	for unit_type in _pending_transforms:
		var updates: Array = _pending_transforms[unit_type]
		if updates.is_empty():
			continue

		var data: MultiMeshData = _pools[unit_type]
		var processed := 0

		while not updates.is_empty() and processed < BATCH_SIZE:
			var update: Dictionary = updates.pop_front()
			data.multimesh.set_instance_transform(update["index"], update["transform"])
			processed += 1

		if processed > 0:
			batch_updated.emit(unit_type, processed)

	_update_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0


## Expand pool capacity.
func _expand_pool(unit_type: String) -> bool:
	var data: MultiMeshData = _pools[unit_type]

	if data.capacity >= MAX_INSTANCES_PER_POOL:
		return false

	var new_capacity := mini(data.capacity * 2, MAX_INSTANCES_PER_POOL)
	var old_capacity := data.capacity

	# Create new MultiMesh with larger capacity
	var new_multimesh := MultiMesh.new()
	new_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	new_multimesh.instance_count = new_capacity
	new_multimesh.visible_instance_count = data.active_count
	new_multimesh.mesh = data.multimesh.mesh

	# Copy existing transforms
	for i in data.active_count:
		var transform := data.multimesh.get_instance_transform(i)
		new_multimesh.set_instance_transform(i, transform)

	# Replace multimesh
	data.multimesh = new_multimesh
	data.instance_node.multimesh = new_multimesh
	data.capacity = new_capacity

	push_warning("MultiMeshPool: Expanded '%s' from %d to %d" % [unit_type, old_capacity, new_capacity])
	return true


## Apply LOD based on camera distance.
func apply_lod(unit_type: String, camera_position: Vector3) -> void:
	if not _pools.has(unit_type):
		return

	var data: MultiMeshData = _pools[unit_type]
	var instance_map: Dictionary = _instance_map[unit_type]

	# For distant units, we could skip updates or use simpler meshes
	# This is a simplified implementation
	for unit_id in instance_map:
		var instance_index: int = instance_map[unit_id]
		var transform := data.multimesh.get_instance_transform(instance_index)
		var distance := camera_position.distance_to(transform.origin)

		if distance > LOD_DISTANCE:
			# Could switch to LOD mesh or reduce update frequency
			pass


## Get instance count for unit type.
func get_instance_count(unit_type: String) -> int:
	if not _pools.has(unit_type):
		return 0
	return _pools[unit_type].active_count


## Get total instance count.
func get_total_instances() -> int:
	return _total_instances


## Check if pool exists.
func has_pool(unit_type: String) -> bool:
	return _pools.has(unit_type)


## Get pool capacity.
func get_pool_capacity(unit_type: String) -> int:
	if not _pools.has(unit_type):
		return 0
	return _pools[unit_type].capacity


## Clear pool.
func clear_pool(unit_type: String) -> void:
	if not _pools.has(unit_type):
		return

	var data: MultiMeshData = _pools[unit_type]
	data.active_count = 0
	data.multimesh.visible_instance_count = 0

	_instance_map[unit_type].clear()
	_reverse_map[unit_type].clear()
	_free_instances[unit_type].clear()
	_pending_transforms[unit_type].clear()


## Get statistics.
func get_statistics() -> Dictionary:
	var pool_stats: Dictionary = {}
	for unit_type in _pools:
		var data: MultiMeshData = _pools[unit_type]
		pool_stats[unit_type] = {
			"active": data.active_count,
			"capacity": data.capacity,
			"utilization": float(data.active_count) / float(data.capacity) if data.capacity > 0 else 0.0
		}

	return {
		"total_instances": _total_instances,
		"total_draw_calls": _total_draw_calls,
		"pool_count": _pools.size(),
		"update_time_ms": _update_time_ms,
		"pools": pool_stats
	}


## Cleanup.
func cleanup() -> void:
	for unit_type in _pools:
		var data: MultiMeshData = _pools[unit_type]
		if data.instance_node != null and is_instance_valid(data.instance_node):
			data.instance_node.queue_free()

	_pools.clear()
	_instance_map.clear()
	_reverse_map.clear()
	_free_instances.clear()
	_pending_transforms.clear()
	_total_instances = 0
	_total_draw_calls = 0


## MultiMeshData helper class.
class MultiMeshData:
	var unit_type: String = ""
	var multimesh: MultiMesh = null
	var instance_node: MultiMeshInstance3D = null
	var capacity: int = 0
	var active_count: int = 0
