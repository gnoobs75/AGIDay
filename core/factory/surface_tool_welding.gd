class_name SurfaceToolWelding
extends RefCounted
## SurfaceToolWelding combines individual part meshes into cohesive final unit geometry.

signal welding_started(part_index: int)
signal welding_completed(part_index: int, mesh: Mesh)
signal final_mesh_ready(mesh: ArrayMesh)

## Welding parameters
const WELD_VERTEX_EPSILON := 0.001  ## Distance for vertex merging
const MAX_PARTS_PER_WELD := 20

## Current welding state
var _surface_tool: SurfaceTool = null
var _accumulated_mesh: ArrayMesh = null
var _part_count: int = 0
var _is_welding: bool = false

## Material tracking
var _current_material: Material = null
var _materials_by_surface: Dictionary = {}


func _init() -> void:
	_surface_tool = SurfaceTool.new()


## Begin a new welding session for assembling a unit.
func begin_welding(base_material: Material = null) -> void:
	_surface_tool.clear()
	_accumulated_mesh = ArrayMesh.new()
	_part_count = 0
	_is_welding = true
	_current_material = base_material
	_materials_by_surface.clear()


## Add a part mesh to the assembly at a specific transform.
func weld_part(part_mesh: Mesh, part_transform: Transform3D, material_override: Material = null) -> bool:
	if not _is_welding:
		push_warning("Cannot weld: no welding session active")
		return false

	if _part_count >= MAX_PARTS_PER_WELD:
		push_warning("Maximum parts per weld exceeded")
		return false

	if part_mesh == null:
		return false

	welding_started.emit(_part_count)

	# Process each surface of the mesh
	for surface_idx in part_mesh.get_surface_count():
		_weld_surface(part_mesh, surface_idx, part_transform, material_override)

	_part_count += 1

	welding_completed.emit(_part_count - 1, part_mesh)
	return true


## Weld a specific surface from a mesh.
func _weld_surface(mesh: Mesh, surface_idx: int, transform: Transform3D, material_override: Material) -> void:
	_surface_tool.clear()
	_surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Get mesh data
	var arrays := mesh.surface_get_arrays(surface_idx)
	if arrays.is_empty():
		return

	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

	# Transform and add vertices
	if indices.is_empty():
		# Non-indexed mesh
		for i in vertices.size():
			_add_vertex(vertices[i], normals, uvs, i, transform)
	else:
		# Indexed mesh
		for idx in indices:
			_add_vertex(vertices[idx], normals, uvs, idx, transform)

	# Determine material
	var mat := material_override if material_override != null else _current_material
	if mat == null:
		mat = mesh.surface_get_material(surface_idx)

	if mat != null:
		_surface_tool.set_material(mat)

	# Commit to accumulated mesh
	var new_surface_idx := _accumulated_mesh.get_surface_count()
	_surface_tool.commit(_accumulated_mesh)

	if mat != null:
		_materials_by_surface[new_surface_idx] = mat


## Add a vertex with transform applied.
func _add_vertex(vertex: Vector3, normals: PackedVector3Array, uvs: PackedVector2Array, idx: int, transform: Transform3D) -> void:
	# Apply transform to vertex
	var transformed_vertex := transform * vertex

	# Set normal if available
	if idx < normals.size():
		var transformed_normal := transform.basis * normals[idx]
		_surface_tool.set_normal(transformed_normal.normalized())

	# Set UV if available
	if idx < uvs.size():
		_surface_tool.set_uv(uvs[idx])

	_surface_tool.add_vertex(transformed_vertex)


## Finalize welding and get the combined mesh.
func finish_welding() -> ArrayMesh:
	if not _is_welding:
		return null

	_is_welding = false

	# Optimize the mesh if we have multiple surfaces
	if _accumulated_mesh.get_surface_count() > 1:
		_optimize_mesh()

	final_mesh_ready.emit(_accumulated_mesh)

	var result := _accumulated_mesh
	_accumulated_mesh = null
	return result


## Optimize the accumulated mesh by merging vertices.
func _optimize_mesh() -> void:
	# Generate tangents for each surface
	for i in _accumulated_mesh.get_surface_count():
		_surface_tool.clear()
		_surface_tool.create_from(_accumulated_mesh, i)
		_surface_tool.generate_tangents()


## Cancel current welding session.
func cancel_welding() -> void:
	_surface_tool.clear()
	_accumulated_mesh = null
	_part_count = 0
	_is_welding = false
	_materials_by_surface.clear()


## Get current part count.
func get_part_count() -> int:
	return _part_count


## Check if welding is active.
func is_welding() -> bool:
	return _is_welding


## Create a combined mesh from multiple parts at once.
static func combine_meshes(parts: Array[Mesh], transforms: Array[Transform3D], material: Material = null) -> ArrayMesh:
	var welder := SurfaceToolWelding.new()
	welder.begin_welding(material)

	var count := mini(parts.size(), transforms.size())
	for i in count:
		welder.weld_part(parts[i], transforms[i])

	return welder.finish_welding()


## Create mesh from primitive for placeholder parts.
static func create_box_mesh(size: Vector3, material: Material = null) -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := size / 2.0

	# Define box vertices (8 corners)
	var corners := [
		Vector3(-half.x, -half.y, -half.z),  # 0
		Vector3(half.x, -half.y, -half.z),   # 1
		Vector3(half.x, half.y, -half.z),    # 2
		Vector3(-half.x, half.y, -half.z),   # 3
		Vector3(-half.x, -half.y, half.z),   # 4
		Vector3(half.x, -half.y, half.z),    # 5
		Vector3(half.x, half.y, half.z),     # 6
		Vector3(-half.x, half.y, half.z)     # 7
	]

	# Face indices and normals
	var faces := [
		[0, 1, 2, 3, Vector3(0, 0, -1)],  # Front
		[5, 4, 7, 6, Vector3(0, 0, 1)],   # Back
		[4, 0, 3, 7, Vector3(-1, 0, 0)],  # Left
		[1, 5, 6, 2, Vector3(1, 0, 0)],   # Right
		[3, 2, 6, 7, Vector3(0, 1, 0)],   # Top
		[4, 5, 1, 0, Vector3(0, -1, 0)]   # Bottom
	]

	for face in faces:
		surface_tool.set_normal(face[4])
		# First triangle
		surface_tool.add_vertex(corners[face[0]])
		surface_tool.add_vertex(corners[face[1]])
		surface_tool.add_vertex(corners[face[2]])
		# Second triangle
		surface_tool.add_vertex(corners[face[0]])
		surface_tool.add_vertex(corners[face[2]])
		surface_tool.add_vertex(corners[face[3]])

	if material != null:
		surface_tool.set_material(material)

	surface_tool.generate_tangents()

	var mesh := ArrayMesh.new()
	surface_tool.commit(mesh)
	return mesh


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"is_welding": _is_welding,
		"part_count": _part_count,
		"surface_count": _accumulated_mesh.get_surface_count() if _accumulated_mesh != null else 0,
		"has_material": _current_material != null
	}
