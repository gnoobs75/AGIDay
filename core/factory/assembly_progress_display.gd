class_name AssemblyProgressDisplay
extends RefCounted
## AssemblyProgressDisplay manages UI components showing assembly progress.

signal display_updated(assembly_id: int, progress: float)
signal display_completed(assembly_id: int)
signal display_cancelled(assembly_id: int)

## UI element references
var progress_bar: ProgressBar = null
var part_label: Label = null
var time_label: Label = null
var container: Control = null

## Display state
var _assembly_id: int = -1
var _unit_template: String = ""
var _current_part_name: String = ""
var _progress: float = 0.0
var _remaining_time: float = 0.0
var _is_active: bool = false
var _is_complete: bool = false

## Text formatting (pre-allocate to reduce allocations)
var _part_text_prefix := "Assembling: "
var _time_text_prefix := "Time: "


func _init() -> void:
	pass


## Initialize with UI components.
func initialize(p_container: Control, p_progress_bar: ProgressBar, p_part_label: Label, p_time_label: Label) -> void:
	container = p_container
	progress_bar = p_progress_bar
	part_label = p_part_label
	time_label = p_time_label

	# Configure progress bar
	if progress_bar != null:
		progress_bar.min_value = 0.0
		progress_bar.max_value = 100.0
		progress_bar.value = 0.0

	# Initialize labels
	if part_label != null:
		part_label.text = ""

	if time_label != null:
		time_label.text = ""


## Create UI components dynamically.
func create_ui(parent: Control) -> void:
	# Create container
	container = VBoxContainer.new()
	container.name = "AssemblyProgressContainer"
	parent.add_child(container)

	# Create progress bar
	progress_bar = ProgressBar.new()
	progress_bar.name = "AssemblyProgressBar"
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(200, 20)
	container.add_child(progress_bar)

	# Create part label
	part_label = Label.new()
	part_label.name = "PartLabel"
	part_label.text = ""
	part_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(part_label)

	# Create time label
	time_label = Label.new()
	time_label.name = "TimeLabel"
	time_label.text = ""
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(time_label)


## Start displaying assembly progress.
func start_display(assembly_id: int, unit_template: String) -> void:
	_assembly_id = assembly_id
	_unit_template = unit_template
	_current_part_name = ""
	_progress = 0.0
	_remaining_time = 0.0
	_is_active = true
	_is_complete = false

	_show_container()
	update_display()


## Update display with new progress data.
func update_progress(progress: float, part_name: String, remaining_time: float) -> void:
	if not _is_active:
		return

	_progress = clampf(progress, 0.0, 1.0)
	_current_part_name = part_name
	_remaining_time = maxf(0.0, remaining_time)

	update_display()
	display_updated.emit(_assembly_id, _progress)


## Update from AssemblyProcess directly.
func update_from_process(process: AssemblyProcess) -> void:
	if process == null:
		return

	var progress := process.get_progress()
	var remaining := process.get_remaining_time()
	var part_name := ""

	# Get current part name
	if process.sequence != null and process.current_part_index < process.sequence.get_part_count():
		var part := process.sequence.get_part(process.current_part_index)
		if part != null:
			part_name = part.part_name

	update_progress(progress, part_name, remaining)


## Refresh all UI elements.
func update_display() -> void:
	# Update progress bar
	if progress_bar != null:
		progress_bar.value = _progress * 100.0

	# Update part label
	if part_label != null:
		if _current_part_name.is_empty():
			part_label.text = _part_text_prefix + "..."
		else:
			part_label.text = _part_text_prefix + _current_part_name

	# Update time label
	if time_label != null:
		time_label.text = _time_text_prefix + "%.1fs" % _remaining_time


## Mark assembly as complete.
func complete_display() -> void:
	_is_active = false
	_is_complete = true
	_progress = 1.0
	_remaining_time = 0.0

	if progress_bar != null:
		progress_bar.value = 100.0

	if part_label != null:
		part_label.text = "Assembly Complete"

	if time_label != null:
		time_label.text = ""

	display_completed.emit(_assembly_id)


## Mark assembly as cancelled.
func cancel_display() -> void:
	_is_active = false
	_is_complete = false

	if part_label != null:
		part_label.text = "Assembly Cancelled"

	display_cancelled.emit(_assembly_id)

	# Hide after brief delay would require timer
	_hide_container()


## Show the container.
func _show_container() -> void:
	if container != null:
		container.visible = true


## Hide the container.
func _hide_container() -> void:
	if container != null:
		container.visible = false


## Clear and reset display.
func clear() -> void:
	_assembly_id = -1
	_unit_template = ""
	_current_part_name = ""
	_progress = 0.0
	_remaining_time = 0.0
	_is_active = false
	_is_complete = false

	if progress_bar != null:
		progress_bar.value = 0.0

	if part_label != null:
		part_label.text = ""

	if time_label != null:
		time_label.text = ""

	_hide_container()


## Check if display is active.
func is_active() -> bool:
	return _is_active


## Check if display shows completed assembly.
func is_complete() -> bool:
	return _is_complete


## Get current assembly ID.
func get_assembly_id() -> int:
	return _assembly_id


## Get current progress.
func get_progress() -> float:
	return _progress


## Set visibility based on zoom level.
func set_visible_for_zoom(zoom_level: float, detail_threshold: float = 0.5) -> void:
	if container != null:
		container.visible = _is_active and zoom_level >= detail_threshold


## Set position (for world-space UI).
func set_display_position(position: Vector2) -> void:
	if container != null:
		container.position = position


## Cleanup UI components.
func cleanup() -> void:
	if container != null and is_instance_valid(container):
		container.queue_free()

	container = null
	progress_bar = null
	part_label = null
	time_label = null


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"assembly_id": _assembly_id,
		"unit_template": _unit_template,
		"progress": _progress,
		"remaining_time": _remaining_time,
		"current_part": _current_part_name,
		"is_active": _is_active,
		"is_complete": _is_complete
	}
