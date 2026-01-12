class_name FactoryDetailView
extends RefCounted
## FactoryDetailView manages the detailed factory view with assembly progress.

signal detail_view_opened(factory_id: int)
signal detail_view_closed(factory_id: int)
signal zoom_level_changed(zoom: float)

## Zoom levels
const ZOOM_STRATEGIC := 0.0    ## Map overview
const ZOOM_FACTORY := 0.5      ## Factory visible
const ZOOM_DETAIL := 1.0       ## Full detail view

## View state
var _current_factory_id: int = -1
var _zoom_level: float = ZOOM_STRATEGIC
var _is_detail_view_active: bool = false

## Sub-systems
var _progress_manager: AssemblyProgressManager = null
var _visual_system: AssemblyVisualSystem = null

## UI references
var _detail_container: Control = null
var _factory_info_label: Label = null

## Factory tracking
var _factory_positions: Dictionary = {}  ## factory_id -> Vector3
var _factory_assemblies: Dictionary = {}  ## factory_id -> Array[int] (assembly_ids)


func _init() -> void:
	_progress_manager = AssemblyProgressManager.new()


## Initialize with UI container.
func initialize(detail_container: Control, visual_system: AssemblyVisualSystem = null) -> void:
	_detail_container = detail_container
	_visual_system = visual_system

	if detail_container != null:
		_progress_manager.initialize(detail_container)

		# Create factory info label
		_factory_info_label = Label.new()
		_factory_info_label.name = "FactoryInfoLabel"
		_factory_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_container.add_child(_factory_info_label)


## Set zoom level (0.0 = strategic, 1.0 = detail).
func set_zoom_level(zoom: float) -> void:
	var old_zoom := _zoom_level
	_zoom_level = clampf(zoom, 0.0, 1.0)

	# Update progress display visibility
	_progress_manager.set_zoom_level(_zoom_level)

	# Show/hide detail container
	if _detail_container != null:
		_detail_container.visible = _zoom_level >= ZOOM_FACTORY

	# Check if entering/leaving detail view
	var is_detail := _zoom_level >= ZOOM_DETAIL
	if is_detail != _is_detail_view_active:
		_is_detail_view_active = is_detail
		if is_detail and _current_factory_id >= 0:
			detail_view_opened.emit(_current_factory_id)
		elif not is_detail and _current_factory_id >= 0:
			detail_view_closed.emit(_current_factory_id)

	if old_zoom != _zoom_level:
		zoom_level_changed.emit(_zoom_level)


## Focus on a specific factory.
func focus_factory(factory_id: int, factory_position: Vector3) -> void:
	_current_factory_id = factory_id
	_factory_positions[factory_id] = factory_position

	# Update factory info
	if _factory_info_label != null:
		_factory_info_label.text = "Factory #%d" % factory_id

	# If already in detail view, open for this factory
	if _is_detail_view_active:
		detail_view_opened.emit(factory_id)


## Clear factory focus.
func clear_focus() -> void:
	if _current_factory_id >= 0 and _is_detail_view_active:
		detail_view_closed.emit(_current_factory_id)

	_current_factory_id = -1

	if _factory_info_label != null:
		_factory_info_label.text = ""


## Register an assembly with a factory.
func register_assembly(factory_id: int, assembly_id: int, unit_template: String) -> void:
	# Track assembly
	if not _factory_assemblies.has(factory_id):
		_factory_assemblies[factory_id] = []
	_factory_assemblies[factory_id].append(assembly_id)

	# Create progress display
	_progress_manager.create_display(assembly_id, factory_id, unit_template)


## Update assembly progress.
func update_assembly(assembly_id: int, progress: float, part_name: String, remaining_time: float) -> void:
	_progress_manager.update_display(assembly_id, progress, part_name, remaining_time)


## Update from assembly process.
func update_from_process(assembly_id: int, process: AssemblyProcess) -> void:
	var display := _progress_manager.get_display(assembly_id)
	if display != null:
		display.update_from_process(process)


## Complete assembly display.
func complete_assembly(assembly_id: int) -> void:
	var display := _progress_manager.get_display(assembly_id)
	if display != null:
		display.complete_display()


## Cancel assembly display.
func cancel_assembly(assembly_id: int) -> void:
	var display := _progress_manager.get_display(assembly_id)
	if display != null:
		display.cancel_display()

	# Remove from tracking
	for factory_id in _factory_assemblies:
		var assemblies: Array = _factory_assemblies[factory_id]
		var idx := assemblies.find(assembly_id)
		if idx != -1:
			assemblies.remove_at(idx)
			break


## Remove completed assembly.
func remove_assembly(assembly_id: int) -> void:
	_progress_manager.remove_display(assembly_id)

	# Remove from tracking
	for factory_id in _factory_assemblies:
		var assemblies: Array = _factory_assemblies[factory_id]
		var idx := assemblies.find(assembly_id)
		if idx != -1:
			assemblies.remove_at(idx)
			break


## Update all displays (call each frame).
func update(delta: float, camera_position: Vector3, processes: Dictionary) -> void:
	# Update progress displays
	_progress_manager.update(delta, processes)

	# Update visual system if available
	if _visual_system != null:
		_visual_system.update(delta, camera_position)

	# Position displays if in detail view
	if _is_detail_view_active and _current_factory_id >= 0:
		_position_displays_for_factory(_current_factory_id)


## Position displays for focused factory.
func _position_displays_for_factory(factory_id: int) -> void:
	if not _factory_positions.has(factory_id):
		return

	# Get base position (would need camera projection in real implementation)
	var base_pos := Vector2(100, 100)  ## Placeholder

	_progress_manager.position_factory_displays(factory_id, base_pos)


## Get current focused factory.
func get_focused_factory() -> int:
	return _current_factory_id


## Get current zoom level.
func get_zoom_level() -> float:
	return _zoom_level


## Check if in detail view.
func is_detail_view_active() -> bool:
	return _is_detail_view_active


## Get assemblies for a factory.
func get_factory_assemblies(factory_id: int) -> Array:
	if _factory_assemblies.has(factory_id):
		return _factory_assemblies[factory_id].duplicate()
	return []


## Get progress manager.
func get_progress_manager() -> AssemblyProgressManager:
	return _progress_manager


## Cleanup.
func cleanup() -> void:
	_progress_manager.cleanup()
	_factory_assemblies.clear()
	_factory_positions.clear()

	if _factory_info_label != null and is_instance_valid(_factory_info_label):
		_factory_info_label.queue_free()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var assembly_counts: Dictionary = {}
	for factory_id in _factory_assemblies:
		assembly_counts[factory_id] = _factory_assemblies[factory_id].size()

	return {
		"current_factory": _current_factory_id,
		"zoom_level": _zoom_level,
		"is_detail_view": _is_detail_view_active,
		"factory_assemblies": assembly_counts,
		"progress_manager": _progress_manager.get_summary()
	}
