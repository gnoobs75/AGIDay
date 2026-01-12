class_name DetailViewAssemblyDisplay
extends RefCounted
## DetailViewAssemblyDisplay shows detailed assembly animation in factory detail view.

signal assembly_display_started(assembly_id: int)
signal assembly_display_updated(assembly_id: int, progress: float)
signal assembly_display_completed(assembly_id: int)

## Camera positioning
const CAMERA_HEIGHT_OFFSET := 5.0
const CAMERA_DISTANCE := 10.0
const CAMERA_FOV := 45.0

## UI components
var _progress_bar: ProgressBar = null
var _info_label: Label = null
var _time_label: Label = null
var _ui_container: Control = null

## 3D scene components
var _assembly_scene: Node3D = null
var _assembly_camera: Camera3D = null
var _detail_viewport: SubViewport = null

## Current assembly state
var _current_assembly: AssemblyProcess = null
var _current_assembly_id: int = -1
var _is_active: bool = false

## Text formatting
var _info_prefix := "Assembling: "


func _init() -> void:
	pass


## Initialize with viewport and UI parent.
func initialize(viewport: SubViewport, ui_parent: Control) -> void:
	_detail_viewport = viewport

	# Create 3D scene in viewport
	if viewport != null:
		_create_assembly_scene()

	# Create UI components
	if ui_parent != null:
		_create_ui(ui_parent)


## Create 3D assembly scene.
func _create_assembly_scene() -> void:
	# Create root node for assembly scene
	_assembly_scene = Node3D.new()
	_assembly_scene.name = "AssemblyScene"
	_detail_viewport.add_child(_assembly_scene)

	# Create camera
	_assembly_camera = Camera3D.new()
	_assembly_camera.name = "AssemblyCamera"
	_assembly_camera.fov = CAMERA_FOV
	_assembly_camera.current = true
	_detail_viewport.add_child(_assembly_camera)

	# Initial camera position
	_position_camera(Vector3.ZERO)


## Create UI components.
func _create_ui(parent: Control) -> void:
	_ui_container = VBoxContainer.new()
	_ui_container.name = "AssemblyDisplayUI"
	_ui_container.visible = false

	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.name = "AssemblyProgressBar"
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = true
	_progress_bar.custom_minimum_size = Vector2(200, 25)
	_ui_container.add_child(_progress_bar)

	# Info label (current part)
	_info_label = Label.new()
	_info_label.name = "AssemblyInfoLabel"
	_info_label.text = ""
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_container.add_child(_info_label)

	# Time label
	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.text = ""
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_ui_container.add_child(_time_label)

	parent.add_child(_ui_container)


## Position camera to view assembly.
func _position_camera(assembly_position: Vector3) -> void:
	if _assembly_camera == null:
		return

	# Camera position: above and behind assembly
	var camera_pos := assembly_position + Vector3(0, CAMERA_HEIGHT_OFFSET, CAMERA_DISTANCE)
	_assembly_camera.position = camera_pos

	# Look at assembly position
	_assembly_camera.look_at(assembly_position)


## Start displaying an assembly process.
func start_display(assembly: AssemblyProcess) -> void:
	if assembly == null:
		return

	_current_assembly = assembly
	_current_assembly_id = assembly.process_id
	_is_active = true

	# Position camera for this assembly
	_position_camera(assembly.factory_position)

	# Show UI
	if _ui_container != null:
		_ui_container.visible = true

	# Initial update
	update_display()

	assembly_display_started.emit(_current_assembly_id)


## Update display with current assembly state.
func update_display() -> void:
	if not _is_active or _current_assembly == null:
		return

	# Calculate progress
	var progress := 0.0
	if _current_assembly.sequence != null and _current_assembly.sequence.total_assembly_time > 0:
		progress = _current_assembly.elapsed_time / _current_assembly.sequence.total_assembly_time
		progress = minf(progress, 1.0)

	# Update progress bar
	if _progress_bar != null:
		_progress_bar.value = progress * 100.0

	# Update info label with current part
	if _info_label != null:
		var part_name := _get_current_part_name()
		if part_name.is_empty():
			_info_label.text = _info_prefix + "..."
		else:
			_info_label.text = _info_prefix + part_name

	# Update time label
	if _time_label != null:
		var remaining := _current_assembly.get_remaining_time()
		_time_label.text = "%.1fs remaining" % remaining

	assembly_display_updated.emit(_current_assembly_id, progress)


## Get current part name from assembly.
func _get_current_part_name() -> String:
	if _current_assembly == null or _current_assembly.sequence == null:
		return ""

	var part_index := _current_assembly.current_part_index
	if part_index >= _current_assembly.sequence.get_part_count():
		part_index = _current_assembly.sequence.get_part_count() - 1

	var part := _current_assembly.sequence.get_part(part_index)
	if part != null:
		return part.part_name

	return ""


## Complete the current display.
func complete_display() -> void:
	if not _is_active:
		return

	# Update to 100%
	if _progress_bar != null:
		_progress_bar.value = 100.0

	if _info_label != null:
		_info_label.text = "Assembly Complete"

	if _time_label != null:
		_time_label.text = ""

	var completed_id := _current_assembly_id
	assembly_display_completed.emit(completed_id)


## Stop displaying current assembly.
func stop_display() -> void:
	_is_active = false
	_current_assembly = null
	_current_assembly_id = -1

	if _ui_container != null:
		_ui_container.visible = false

	if _progress_bar != null:
		_progress_bar.value = 0.0

	if _info_label != null:
		_info_label.text = ""

	if _time_label != null:
		_time_label.text = ""


## Check if assembly is active.
func is_active() -> bool:
	return _is_active


## Get current assembly ID.
func get_current_assembly_id() -> int:
	return _current_assembly_id


## Get assembly scene root.
func get_assembly_scene() -> Node3D:
	return _assembly_scene


## Add child to assembly scene.
func add_to_scene(node: Node3D) -> void:
	if _assembly_scene != null:
		_assembly_scene.add_child(node)


## Clear assembly scene.
func clear_scene() -> void:
	if _assembly_scene == null:
		return

	for child in _assembly_scene.get_children():
		child.queue_free()


## Set visibility.
func set_visible(visible: bool) -> void:
	if _ui_container != null:
		_ui_container.visible = visible and _is_active


## Handle no active assembly.
func show_no_assembly() -> void:
	stop_display()

	if _info_label != null:
		_info_label.text = "No active assembly"
		_info_label.visible = true

	if _ui_container != null:
		_ui_container.visible = true


## Cleanup.
func cleanup() -> void:
	stop_display()

	if _assembly_scene != null and is_instance_valid(_assembly_scene):
		_assembly_scene.queue_free()

	if _assembly_camera != null and is_instance_valid(_assembly_camera):
		_assembly_camera.queue_free()

	if _ui_container != null and is_instance_valid(_ui_container):
		_ui_container.queue_free()

	_assembly_scene = null
	_assembly_camera = null
	_ui_container = null
	_progress_bar = null
	_info_label = null
	_time_label = null


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"is_active": _is_active,
		"current_assembly_id": _current_assembly_id,
		"has_assembly": _current_assembly != null,
		"has_scene": _assembly_scene != null,
		"has_camera": _assembly_camera != null,
		"has_ui": _ui_container != null
	}
