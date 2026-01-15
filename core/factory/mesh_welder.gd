class_name MeshWelder
extends RefCounted
## MeshWelder combines individual assembly parts into final unit meshes using SurfaceTool.
## Supports asynchronous mesh generation to prevent frame rate hitches.

signal weld_started(assembly_id: int)
signal weld_progress(assembly_id: int, progress: float)
signal weld_completed(assembly_id: int, mesh: ArrayMesh)
signal weld_failed(assembly_id: int, reason: String)

## Performance targets
const MAX_WELD_TIME_MS := 50.0  ## Target <50ms mesh generation
const BATCH_VERTEX_LIMIT := 1000  ## Vertices per batch for async

## Threading
var _weld_thread: Thread = null
var _thread_mutex: Mutex = null
var _pending_results: Dictionary = {}  ## assembly_id -> result data
var _is_thread_active := false

## Statistics
var _total_welds := 0
var _total_weld_time := 0.0
var _failed_welds := 0


func _init() -> void:
	_thread_mutex = Mutex.new()


## Weld parts synchronously (for simple assemblies).
func weld_parts_sync(parts: Array, factory_position: Vector3 = Vector3.ZERO) -> ArrayMesh:
	if parts.is_empty():
		return null

	var start_time := Time.get_ticks_usec()
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var has_content := false

	for part in parts:
		var part_mesh := _get_part_mesh(part)
		if part_mesh == null:
			continue

		var part_transform := _get_part_transform(part, factory_position)

		# Append mesh with transform
		for surface_idx in part_mesh.get_surface_count():
			surface_tool.append_from(part_mesh, surface_idx, part_transform)
			has_content = true

	if not has_content:
		return null

	# Generate normals and commit
	surface_tool.generate_normals()
	var final_mesh := surface_tool.commit()

	var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
	_total_welds += 1
	_total_weld_time += elapsed

	return final_mesh


## Weld parts asynchronously (for complex assemblies).
func weld_parts_async(assembly_id: int, parts: Array,
					  factory_position: Vector3 = Vector3.ZERO) -> void:
	if parts.is_empty():
		weld_failed.emit(assembly_id, "No parts to weld")
		return

	weld_started.emit(assembly_id)

	# Prepare part data for thread (cannot pass Node3D to thread)
	var part_data: Array[Dictionary] = []
	for part in parts:
		var data := _extract_part_data(part, factory_position)
		if not data.is_empty():
			part_data.append(data)

	if part_data.is_empty():
		weld_failed.emit(assembly_id, "No valid part meshes found")
		return

	# Start background thread
	_thread_mutex.lock()
	_is_thread_active = true
	_thread_mutex.unlock()

	_weld_thread = Thread.new()
	var callable := Callable(self, "_weld_thread_func").bind(assembly_id, part_data)
	var err := _weld_thread.start(callable)

	if err != OK:
		_failed_welds += 1
		weld_failed.emit(assembly_id, "Failed to start weld thread")


## Thread function for async welding.
func _weld_thread_func(assembly_id: int, part_data: Array[Dictionary]) -> void:
	var start_time := Time.get_ticks_usec()
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var total_parts := part_data.size()
	var processed := 0

	for data in part_data:
		var mesh: ArrayMesh = data.get("mesh")
		var transform: Transform3D = data.get("transform", Transform3D.IDENTITY)

		if mesh != null:
			for surface_idx in mesh.get_surface_count():
				surface_tool.append_from(mesh, surface_idx, transform)

		processed += 1

		# Report progress (thread-safe via mutex)
		_thread_mutex.lock()
		var progress := float(processed) / float(total_parts)
		_pending_results[assembly_id] = {"progress": progress, "completed": false}
		_thread_mutex.unlock()

	# Generate normals
	surface_tool.generate_normals()

	# Commit mesh
	var final_mesh := surface_tool.commit()

	var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0

	# Store result
	_thread_mutex.lock()
	_pending_results[assembly_id] = {
		"completed": true,
		"mesh": final_mesh,
		"elapsed_ms": elapsed,
		"success": final_mesh != null
	}
	_is_thread_active = false
	_thread_mutex.unlock()


## Check and process pending results (call from main thread).
func process_pending_results() -> void:
	_thread_mutex.lock()
	var results := _pending_results.duplicate()
	_thread_mutex.unlock()

	for assembly_id in results:
		var result: Dictionary = results[assembly_id]

		if result.get("completed", false):
			# Clean up thread
			if _weld_thread != null and _weld_thread.is_started():
				_weld_thread.wait_to_finish()
				_weld_thread = null

			_thread_mutex.lock()
			_pending_results.erase(assembly_id)
			_thread_mutex.unlock()

			if result.get("success", false):
				_total_welds += 1
				_total_weld_time += result.get("elapsed_ms", 0.0)
				weld_completed.emit(assembly_id, result.get("mesh"))
			else:
				_failed_welds += 1
				weld_failed.emit(assembly_id, "Mesh generation failed")
		else:
			# Report progress
			weld_progress.emit(assembly_id, result.get("progress", 0.0))


## Extract part data for thread processing.
func _extract_part_data(part: Variant, factory_position: Vector3) -> Dictionary:
	var mesh := _get_part_mesh(part)
	if mesh == null:
		return {}

	var transform := _get_part_transform(part, factory_position)

	return {
		"mesh": mesh,
		"transform": transform
	}


## Get mesh from part (supports Node3D with MeshInstance3D child or Dictionary).
func _get_part_mesh(part: Variant) -> ArrayMesh:
	if part is Dictionary:
		return part.get("mesh") as ArrayMesh

	if part is MeshInstance3D:
		var mesh: Mesh = part.mesh
		if mesh is ArrayMesh:
			return mesh
		# Convert to ArrayMesh if needed
		if mesh != null:
			return _convert_to_array_mesh(mesh)

	if part is Node3D:
		# Look for MeshInstance3D child
		for child in part.get_children():
			if child is MeshInstance3D:
				var mesh: Mesh = child.mesh
				if mesh is ArrayMesh:
					return mesh
				if mesh != null:
					return _convert_to_array_mesh(mesh)

	return null


## Convert any Mesh to ArrayMesh.
func _convert_to_array_mesh(mesh: Mesh) -> ArrayMesh:
	if mesh is ArrayMesh:
		return mesh

	var surface_tool := SurfaceTool.new()
	var array_mesh := ArrayMesh.new()

	for i in mesh.get_surface_count():
		surface_tool.create_from(mesh, i)
		surface_tool.commit(array_mesh)

	return array_mesh


## Get transform from part.
func _get_part_transform(part: Variant, factory_position: Vector3) -> Transform3D:
	var transform := Transform3D.IDENTITY

	if part is Dictionary:
		transform = part.get("transform", Transform3D.IDENTITY)
	elif part is Node3D:
		transform = part.global_transform

	# Make relative to factory position
	transform.origin -= factory_position

	return transform


## Weld multiple part groups into separate meshes.
func weld_batch(part_groups: Array[Array], factory_position: Vector3 = Vector3.ZERO) -> Array[ArrayMesh]:
	var results: Array[ArrayMesh] = []

	for parts in part_groups:
		var mesh := weld_parts_sync(parts, factory_position)
		results.append(mesh)

	return results


## Create optimized mesh from parts with material merging.
func weld_optimized(parts: Array, factory_position: Vector3 = Vector3.ZERO) -> ArrayMesh:
	if parts.is_empty():
		return null

	# Group parts by material
	var material_groups: Dictionary = {}  # material_hash -> Array[part_data]

	for part in parts:
		var part_mesh := _get_part_mesh(part)
		if part_mesh == null:
			continue

		var transform := _get_part_transform(part, factory_position)

		for surface_idx in part_mesh.get_surface_count():
			var material := part_mesh.surface_get_material(surface_idx)
			var mat_hash := material.get_instance_id() if material else 0

			if not material_groups.has(mat_hash):
				material_groups[mat_hash] = {
					"material": material,
					"surfaces": []
				}

			material_groups[mat_hash]["surfaces"].append({
				"mesh": part_mesh,
				"surface_idx": surface_idx,
				"transform": transform
			})

	# Build final mesh with separate surfaces per material
	var final_mesh := ArrayMesh.new()

	for mat_hash in material_groups:
		var group: Dictionary = material_groups[mat_hash]
		var surface_tool := SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

		for surface_data in group["surfaces"]:
			surface_tool.append_from(
				surface_data["mesh"],
				surface_data["surface_idx"],
				surface_data["transform"]
			)

		surface_tool.generate_normals()
		surface_tool.commit(final_mesh)

		# Set material on last added surface
		var surface_count := final_mesh.get_surface_count()
		if surface_count > 0 and group["material"] != null:
			final_mesh.surface_set_material(surface_count - 1, group["material"])

	return final_mesh


## Check if async weld is in progress.
func is_welding() -> bool:
	_thread_mutex.lock()
	var active := _is_thread_active
	_thread_mutex.unlock()
	return active


## Cancel pending async weld.
func cancel_async_weld(assembly_id: int) -> void:
	_thread_mutex.lock()
	_pending_results.erase(assembly_id)
	_thread_mutex.unlock()


## Get statistics.
func get_statistics() -> Dictionary:
	var avg_time := 0.0
	if _total_welds > 0:
		avg_time = _total_weld_time / float(_total_welds)

	return {
		"total_welds": _total_welds,
		"failed_welds": _failed_welds,
		"total_weld_time_ms": _total_weld_time,
		"average_weld_time_ms": avg_time,
		"is_welding": is_welding()
	}


## Cleanup.
func cleanup() -> void:
	if _weld_thread != null and _weld_thread.is_started():
		_weld_thread.wait_to_finish()
		_weld_thread = null

	_thread_mutex.lock()
	_pending_results.clear()
	_is_thread_active = false
	_thread_mutex.unlock()
