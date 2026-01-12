class_name AssemblyVisualSystem
extends RefCounted
## AssemblyVisualSystem coordinates all visual aspects of unit assembly.

signal visual_assembly_started(assembly_id: int)
signal visual_part_assembled(assembly_id: int, part_index: int)
signal visual_assembly_completed(assembly_id: int, mesh: Mesh)
signal visual_assembly_cancelled(assembly_id: int)

## Maximum simultaneous visual assemblies
const MAX_VISUAL_ASSEMBLIES := 20

## Visual assembly data
class VisualAssemblyData:
	var assembly_id: int = -1
	var factory_node: Node3D = null
	var position: Vector3 = Vector3.ZERO
	var unit_template: String = ""
	var faction_id: String = ""
	var theme: FactionAssemblyTheme = null
	var sequence: AssemblySequence = null
	var current_part: int = 0
	var part_nodes: Array[Node3D] = []
	var welder: SurfaceToolWelding = null
	var animation: AssemblyAnimation = null
	var elapsed_time: float = 0.0
	var is_complete: bool = false


## Sub-systems
var _particles: AssemblyParticles = null
var _lod_system: AssemblyLODSystem = null

## Active visual assemblies
var _visual_assemblies: Dictionary = {}  ## assembly_id -> VisualAssemblyData

## Scene tree reference
var _scene_tree: SceneTree = null


func _init() -> void:
	_particles = AssemblyParticles.new()
	_lod_system = AssemblyLODSystem.new()

	# Connect LOD signals
	_lod_system.lod_level_changed.connect(_on_lod_changed)


## Initialize with scene tree.
func initialize(scene_tree: SceneTree) -> void:
	_scene_tree = scene_tree


## Start a visual assembly process.
func start_visual_assembly(
	assembly_id: int,
	sequence: AssemblySequence,
	theme: FactionAssemblyTheme,
	factory_node: Node3D,
	factory_position: Vector3
) -> bool:
	if _visual_assemblies.size() >= MAX_VISUAL_ASSEMBLIES:
		push_warning("Maximum visual assemblies reached")
		return false

	var data := VisualAssemblyData.new()
	data.assembly_id = assembly_id
	data.factory_node = factory_node
	data.position = factory_position
	data.unit_template = sequence.unit_template
	data.faction_id = sequence.faction_id
	data.theme = theme
	data.sequence = sequence
	data.current_part = 0
	data.elapsed_time = 0.0
	data.is_complete = false

	# Initialize welder
	data.welder = SurfaceToolWelding.new()
	data.welder.begin_welding()

	# Initialize animation
	data.animation = AssemblyAnimation.new()
	if _scene_tree != null:
		data.animation.set_scene_tree(_scene_tree)
	data.animation.animation_completed.connect(_on_part_animation_done.bind(assembly_id))

	_visual_assemblies[assembly_id] = data

	# Register with LOD system
	_lod_system.register_assembly(assembly_id, factory_position)

	# Set up particles parent
	if factory_node != null:
		_particles.set_parent(factory_node)
		if theme != null:
			_particles.set_theme_colors(theme.primary_color, theme.glow_color, theme.particle_color)

	visual_assembly_started.emit(assembly_id)

	return true


## Update visual assemblies (call each frame).
func update(delta: float, camera_position: Vector3, frustum_planes: Array = []) -> void:
	# Update LOD system
	_lod_system.update_camera(camera_position, frustum_planes)
	_lod_system.update(delta)

	# Update particles
	_particles.update(delta)

	# Update each visual assembly
	var completed: Array[int] = []

	for assembly_id in _visual_assemblies:
		var data: VisualAssemblyData = _visual_assemblies[assembly_id]

		if data.is_complete:
			continue

		# Check LOD level
		if _lod_system.should_skip_animation(assembly_id):
			_skip_to_completion(data)
			continue

		data.elapsed_time += delta
		_update_visual_assembly(data, delta)

		if data.is_complete:
			completed.append(assembly_id)

	# Handle completions
	for assembly_id in completed:
		_finalize_assembly(assembly_id)


## Update a single visual assembly.
func _update_visual_assembly(data: VisualAssemblyData, _delta: float) -> void:
	if data.sequence == null:
		return

	# Get current part info
	var part_info := data.sequence.get_part_at_time(data.elapsed_time)
	if part_info.is_empty():
		return

	var target_part: int = part_info["index"]

	# Assemble new parts as needed
	while data.current_part <= target_part and data.current_part < data.sequence.get_part_count():
		_assemble_part(data, data.current_part)
		data.current_part += 1

	# Check completion
	if data.elapsed_time >= data.sequence.total_assembly_time:
		data.is_complete = true


## Assemble a specific part with visuals.
func _assemble_part(data: VisualAssemblyData, part_index: int) -> void:
	var part := data.sequence.get_part(part_index)
	if part == null:
		return

	# Create mesh node
	var mesh_node := _create_part_mesh(data, part)
	if mesh_node == null:
		return

	# Set initial position
	var start_pos := data.position + part.start_position
	mesh_node.position = start_pos
	mesh_node.quaternion = part.start_rotation
	mesh_node.scale = part.scale

	# Add to factory
	if data.factory_node != null:
		data.factory_node.add_child(mesh_node)

	data.part_nodes.append(mesh_node)

	# Add to welder
	if mesh_node.mesh != null and mesh_node.mesh is Mesh:
		var transform := Transform3D(
			Basis(part.final_rotation) * Basis.from_scale(part.scale),
			part.final_position
		)
		data.welder.weld_part(mesh_node.mesh, transform)

	# Set up animation
	var end_pos := data.position + part.final_position
	data.animation.add_animation(
		part_index,
		mesh_node,
		start_pos,
		end_pos,
		part.start_rotation,
		part.final_rotation,
		part.assembly_time,
		0.0,
		AssemblyAnimation.EaseType.EASE_OUT
	)

	# Start animation if visible
	if _lod_system.should_animate(data.assembly_id):
		data.animation.start_animation(part_index)

		# Spawn particles if at full LOD
		if _lod_system.should_show_particles(data.assembly_id):
			var particle_type := part.particle_type if not part.particle_type.is_empty() else AssemblyParticles.EFFECT_WELD_SPARKS
			_particles.spawn_particles(particle_type, start_pos, part.particle_intensity)
	else:
		# Skip animation, set final state
		mesh_node.position = end_pos
		mesh_node.quaternion = part.final_rotation


## Create mesh node for a part.
func _create_part_mesh(data: VisualAssemblyData, part: AssemblyPart) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()

	# Try to load mesh
	if not part.mesh.is_empty() and ResourceLoader.exists(part.mesh):
		var mesh_resource := load(part.mesh)
		if mesh_resource is Mesh:
			mesh_node.mesh = mesh_resource

	# Use placeholder if no mesh
	if mesh_node.mesh == null:
		mesh_node.mesh = _create_placeholder_mesh(part, data.theme)

	# Apply material
	var mat := _create_part_material(data.theme)
	if mat != null:
		mesh_node.set_surface_override_material(0, mat)

	mesh_node.name = "VisualPart_%s_%d" % [part.part_id, data.assembly_id]

	return mesh_node


## Create placeholder mesh for missing assets.
func _create_placeholder_mesh(part: AssemblyPart, theme: FactionAssemblyTheme) -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)

	var mat := StandardMaterial3D.new()
	if theme != null:
		mat.albedo_color = theme.secondary_color
		mat.emission_enabled = true
		mat.emission = theme.glow_color
		mat.emission_energy_multiplier = 0.3
	else:
		mat.albedo_color = Color.GRAY

	box.material = mat
	return box


## Create material for part based on theme.
func _create_part_material(theme: FactionAssemblyTheme) -> StandardMaterial3D:
	if theme == null:
		return null

	var mat := StandardMaterial3D.new()
	mat.albedo_color = theme.primary_color
	mat.emission_enabled = true
	mat.emission = theme.glow_color
	mat.emission_energy_multiplier = theme.glow_intensity * 0.5
	mat.metallic = 0.7
	mat.roughness = 0.3

	return mat


## Handle part animation completion.
func _on_part_animation_done(part_index: int, assembly_id: int) -> void:
	if not _visual_assemblies.has(assembly_id):
		return

	var data: VisualAssemblyData = _visual_assemblies[assembly_id]

	# Spawn completion particles
	if _lod_system.should_show_particles(assembly_id):
		var part := data.sequence.get_part(part_index)
		if part != null:
			var pos := data.position + part.final_position
			_particles.spawn_particles(AssemblyParticles.EFFECT_ASSEMBLY_GLOW, pos, 0.5)

	visual_part_assembled.emit(assembly_id, part_index)


## Skip to completion without animation.
func _skip_to_completion(data: VisualAssemblyData) -> void:
	if data.is_complete:
		return

	# Set all parts to final positions
	for i in data.sequence.get_part_count():
		if i >= data.part_nodes.size():
			# Create missing parts instantly
			var part := data.sequence.get_part(i)
			if part == null:
				continue

			var mesh_node := _create_part_mesh(data, part)
			if mesh_node != null:
				mesh_node.position = data.position + part.final_position
				mesh_node.quaternion = part.final_rotation
				mesh_node.scale = part.scale

				if data.factory_node != null:
					data.factory_node.add_child(mesh_node)

				data.part_nodes.append(mesh_node)

				# Add to welder
				if mesh_node.mesh != null:
					var transform := Transform3D(
						Basis(part.final_rotation) * Basis.from_scale(part.scale),
						part.final_position
					)
					data.welder.weld_part(mesh_node.mesh, transform)
		else:
			# Move existing parts to final position
			var part := data.sequence.get_part(i)
			if part != null and data.part_nodes[i] != null:
				data.part_nodes[i].position = data.position + part.final_position
				data.part_nodes[i].quaternion = part.final_rotation

	data.current_part = data.sequence.get_part_count()
	data.is_complete = true


## Finalize a completed assembly.
func _finalize_assembly(assembly_id: int) -> void:
	if not _visual_assemblies.has(assembly_id):
		return

	var data: VisualAssemblyData = _visual_assemblies[assembly_id]

	# Finish welding to get combined mesh
	var final_mesh := data.welder.finish_welding()

	visual_assembly_completed.emit(assembly_id, final_mesh)


## Cancel a visual assembly.
func cancel_visual_assembly(assembly_id: int) -> void:
	if not _visual_assemblies.has(assembly_id):
		return

	var data: VisualAssemblyData = _visual_assemblies[assembly_id]

	# Cancel animations
	if data.animation != null:
		data.animation.cancel_all()

	# Cancel welding
	if data.welder != null:
		data.welder.cancel_welding()

	# Remove part nodes
	for node in data.part_nodes:
		if is_instance_valid(node):
			node.queue_free()

	# Unregister from LOD
	_lod_system.unregister_assembly(assembly_id)

	_visual_assemblies.erase(assembly_id)

	visual_assembly_cancelled.emit(assembly_id)


## Collect completed assembly and clean up.
func collect_completed(assembly_id: int) -> Dictionary:
	if not _visual_assemblies.has(assembly_id):
		return {}

	var data: VisualAssemblyData = _visual_assemblies[assembly_id]

	if not data.is_complete:
		return {}

	# Prepare result
	var result := {
		"assembly_id": assembly_id,
		"part_nodes": data.part_nodes.duplicate(),
		"unit_template": data.unit_template,
		"faction_id": data.faction_id
	}

	# Unregister from LOD
	_lod_system.unregister_assembly(assembly_id)

	# Clear data (but don't free nodes - caller takes ownership)
	data.part_nodes.clear()
	_visual_assemblies.erase(assembly_id)

	return result


## Handle LOD level changes.
func _on_lod_changed(assembly_id: int, lod_level: int) -> void:
	if not _visual_assemblies.has(assembly_id):
		return

	var data: VisualAssemblyData = _visual_assemblies[assembly_id]

	# Skip animations if LOD is too low
	if lod_level >= AssemblyLODSystem.LOD_MINIMAL:
		if data.animation != null:
			data.animation.skip_to_end()


## Get visual assembly progress.
func get_progress(assembly_id: int) -> float:
	if not _visual_assemblies.has(assembly_id):
		return 0.0

	var data: VisualAssemblyData = _visual_assemblies[assembly_id]
	if data.sequence == null or data.sequence.total_assembly_time <= 0:
		return 0.0

	return minf(data.elapsed_time / data.sequence.total_assembly_time, 1.0)


## Check if assembly is complete.
func is_complete(assembly_id: int) -> bool:
	if _visual_assemblies.has(assembly_id):
		return _visual_assemblies[assembly_id].is_complete
	return false


## Get active assembly count.
func get_active_count() -> int:
	return _visual_assemblies.size()


## Cleanup all visual assemblies.
func cleanup() -> void:
	for assembly_id in _visual_assemblies.keys():
		cancel_visual_assembly(assembly_id)

	_particles.cleanup()
	_lod_system.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var active_count := 0
	var complete_count := 0

	for assembly_id in _visual_assemblies:
		if _visual_assemblies[assembly_id].is_complete:
			complete_count += 1
		else:
			active_count += 1

	return {
		"active_assemblies": active_count,
		"completed_pending": complete_count,
		"particles": _particles.get_summary(),
		"lod": _lod_system.get_summary()
	}
