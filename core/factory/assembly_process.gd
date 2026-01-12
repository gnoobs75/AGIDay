class_name AssemblyProcess
extends RefCounted
## AssemblyProcess tracks an individual unit assembly with animation.

signal part_animation_started(part_index: int)
signal part_animation_completed(part_index: int)
signal assembly_completed()
signal assembly_cancelled()

## Process identity
var process_id: int = -1
var unit_template: String = ""
var faction_id: String = ""

## Factory reference
var factory_position: Vector3 = Vector3.ZERO
var factory_node: Node3D = null

## Sequence reference
var sequence: AssemblySequence = null
var state: AssemblySequenceState = null

## Progress tracking
var elapsed_time: float = 0.0
var current_part_index: int = 0
var is_complete: bool = false
var is_cancelled: bool = false

## Assembled parts (MeshInstance3D nodes)
var assembled_parts: Array[Node3D] = []

## Active tweens for cleanup
var active_tweens: Array[Tween] = []

## Theme
var theme: FactionAssemblyTheme = null


func _init() -> void:
	pass


## Initialize assembly process.
func initialize(p_id: int, p_sequence: AssemblySequence, p_faction: String, p_factory_pos: Vector3, p_factory_node: Node3D = null) -> void:
	process_id = p_id
	sequence = p_sequence
	faction_id = p_faction
	factory_position = p_factory_pos
	factory_node = p_factory_node
	unit_template = p_sequence.unit_template

	elapsed_time = 0.0
	current_part_index = 0
	is_complete = false
	is_cancelled = false

	# Create state
	state = AssemblySequenceState.new()
	state.initialize(p_id, unit_template, faction_id, Time.get_ticks_msec() / 1000.0)

	# Get theme
	theme = FactionAssemblyTheme.create_for_faction(faction_id)


## Update the assembly process (call each frame).
func update(delta: float) -> void:
	if is_complete or is_cancelled:
		return

	elapsed_time += delta

	# Check what part we should be on
	var part_info := sequence.get_part_at_time(elapsed_time)
	if part_info.is_empty():
		return

	var target_part_index: int = part_info["index"]

	# Start animating new parts
	while current_part_index <= target_part_index:
		if current_part_index < sequence.get_part_count():
			if not _is_part_started(current_part_index):
				assemble_next_part()
		current_part_index += 1

	# Check completion
	if elapsed_time >= sequence.total_assembly_time:
		_complete_assembly()


## Check if a part animation has been started.
func _is_part_started(part_index: int) -> bool:
	return part_index < assembled_parts.size()


## Assemble the next part with animation.
func assemble_next_part() -> void:
	if current_part_index >= sequence.get_part_count():
		return

	var part := sequence.get_part(current_part_index)
	if part == null:
		return

	part_animation_started.emit(current_part_index)

	# Create mesh instance for this part
	var mesh_node := _create_part_mesh(part)
	if mesh_node == null:
		# Create placeholder if mesh loading fails
		mesh_node = _create_placeholder_mesh(part)

	# Set initial position and rotation
	mesh_node.position = factory_position + part.start_position
	mesh_node.quaternion = part.start_rotation
	mesh_node.scale = part.scale

	# Add to scene
	if factory_node != null:
		factory_node.add_child(mesh_node)
	else:
		# Fallback - would need scene tree access
		pass

	assembled_parts.append(mesh_node)

	# Animate to final position
	_animate_part(mesh_node, part)


## Create mesh for assembly part.
func _create_part_mesh(part: AssemblyPart) -> MeshInstance3D:
	if part.mesh.is_empty():
		return null

	var mesh_node := MeshInstance3D.new()

	# Try to load mesh resource
	if ResourceLoader.exists(part.mesh):
		var mesh_resource := load(part.mesh)
		if mesh_resource is Mesh:
			mesh_node.mesh = mesh_resource

	# Apply material if specified
	if not part.material.is_empty() and ResourceLoader.exists(part.material):
		var mat_resource := load(part.material)
		if mat_resource is Material:
			mesh_node.set_surface_override_material(0, mat_resource)

	# Apply theme color
	if theme != null and mesh_node.mesh != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = theme.primary_color
		mat.emission_enabled = true
		mat.emission = theme.glow_color
		mat.emission_energy_multiplier = theme.glow_intensity * 0.5
		mesh_node.set_surface_override_material(0, mat)

	mesh_node.name = "AssemblyPart_%s" % part.part_id

	return mesh_node


## Create placeholder mesh when actual mesh is not available.
func _create_placeholder_mesh(part: AssemblyPart) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()

	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	mesh_node.mesh = box

	var mat := StandardMaterial3D.new()
	if theme != null:
		mat.albedo_color = theme.secondary_color
	else:
		mat.albedo_color = Color.GRAY
	mesh_node.set_surface_override_material(0, mat)

	mesh_node.name = "AssemblyPart_%s_placeholder" % part.part_id

	return mesh_node


## Animate part from start to final position.
func _animate_part(mesh_node: Node3D, part: AssemblyPart) -> void:
	if factory_node == null:
		# Without scene tree, just set final position
		mesh_node.position = factory_position + part.final_position
		mesh_node.quaternion = part.final_rotation
		part_animation_completed.emit(current_part_index)
		return

	var tween := factory_node.create_tween()
	if tween == null:
		mesh_node.position = factory_position + part.final_position
		mesh_node.quaternion = part.final_rotation
		part_animation_completed.emit(current_part_index)
		return

	active_tweens.append(tween)

	var final_pos := factory_position + part.final_position

	# Animate position
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(mesh_node, "position", final_pos, part.assembly_time)

	# Animate rotation simultaneously
	tween.parallel().tween_property(mesh_node, "quaternion", part.final_rotation, part.assembly_time)

	# Schedule completion callback
	var part_idx := current_part_index
	tween.tween_callback(func(): _on_part_animation_done(part_idx, tween))


## Handle part animation completion.
func _on_part_animation_done(part_index: int, tween: Tween) -> void:
	# Remove from active tweens
	var idx := active_tweens.find(tween)
	if idx != -1:
		active_tweens.remove_at(idx)

	part_animation_completed.emit(part_index)


## Complete the assembly.
func _complete_assembly() -> void:
	if is_complete:
		return

	is_complete = true

	# Cleanup any remaining tweens
	_cleanup_tweens()

	assembly_completed.emit()


## Cancel and cleanup the assembly.
func cleanup() -> void:
	is_cancelled = true

	_cleanup_tweens()

	# Remove assembled parts
	for part_node in assembled_parts:
		if is_instance_valid(part_node):
			part_node.queue_free()

	assembled_parts.clear()

	assembly_cancelled.emit()


## Cleanup active tweens.
func _cleanup_tweens() -> void:
	for tween in active_tweens:
		if tween != null and tween.is_valid():
			tween.kill()

	active_tweens.clear()


## Get progress (0.0 to 1.0).
func get_progress() -> float:
	if sequence == null or sequence.total_assembly_time <= 0:
		return 0.0
	return minf(elapsed_time / sequence.total_assembly_time, 1.0)


## Get remaining time.
func get_remaining_time() -> float:
	if sequence == null:
		return 0.0
	return maxf(0.0, sequence.total_assembly_time - elapsed_time)


## Serialization.
func to_dict() -> Dictionary:
	return {
		"process_id": process_id,
		"unit_template": unit_template,
		"faction_id": faction_id,
		"factory_position": {"x": factory_position.x, "y": factory_position.y, "z": factory_position.z},
		"elapsed_time": elapsed_time,
		"current_part_index": current_part_index,
		"is_complete": is_complete,
		"state": state.to_dict() if state != null else {}
	}


func from_dict(data: Dictionary) -> void:
	process_id = data.get("process_id", -1)
	unit_template = data.get("unit_template", "")
	faction_id = data.get("faction_id", "")

	var pos: Dictionary = data.get("factory_position", {})
	factory_position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	elapsed_time = data.get("elapsed_time", 0.0)
	current_part_index = data.get("current_part_index", 0)
	is_complete = data.get("is_complete", false)

	if data.has("state"):
		state = AssemblySequenceState.create_from_dict(data["state"])


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": process_id,
		"template": unit_template,
		"faction": faction_id,
		"progress": get_progress(),
		"current_part": current_part_index,
		"total_parts": sequence.get_part_count() if sequence != null else 0,
		"is_complete": is_complete,
		"assembled_count": assembled_parts.size(),
		"active_tweens": active_tweens.size()
	}
