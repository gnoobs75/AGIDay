class_name AssemblyProgressManager
extends RefCounted
## AssemblyProgressManager coordinates multiple assembly progress displays.

signal progress_display_created(assembly_id: int)
signal progress_display_removed(assembly_id: int)
signal all_assemblies_complete()

## Maximum simultaneous displays
const MAX_DISPLAYS := 10

## Active displays
var _displays: Dictionary = {}  ## assembly_id -> AssemblyProgressDisplay
var _display_pool: Array[AssemblyProgressDisplay] = []

## Factory associations
var _factory_displays: Dictionary = {}  ## factory_id -> Array[int] (assembly_ids)

## UI parent for displays
var _ui_parent: Control = null

## Zoom level for visibility control
var _current_zoom: float = 1.0
var _detail_threshold: float = 0.5  ## Minimum zoom to show details


func _init() -> void:
	pass


## Initialize with UI parent.
func initialize(ui_parent: Control) -> void:
	_ui_parent = ui_parent


## Create a progress display for an assembly.
func create_display(assembly_id: int, factory_id: int, unit_template: String) -> AssemblyProgressDisplay:
	if _displays.size() >= MAX_DISPLAYS:
		push_warning("Maximum progress displays reached")
		return null

	if _displays.has(assembly_id):
		return _displays[assembly_id]

	# Get or create display
	var display := _get_pooled_display()
	if display == null:
		display = AssemblyProgressDisplay.new()
		if _ui_parent != null:
			display.create_ui(_ui_parent)

	# Connect signals
	display.display_completed.connect(_on_display_completed)
	display.display_cancelled.connect(_on_display_cancelled)

	# Start display
	display.start_display(assembly_id, unit_template)

	_displays[assembly_id] = display

	# Track factory association
	if not _factory_displays.has(factory_id):
		_factory_displays[factory_id] = []
	_factory_displays[factory_id].append(assembly_id)

	# Apply current zoom
	display.set_visible_for_zoom(_current_zoom, _detail_threshold)

	progress_display_created.emit(assembly_id)

	return display


## Get existing display for assembly.
func get_display(assembly_id: int) -> AssemblyProgressDisplay:
	if _displays.has(assembly_id):
		return _displays[assembly_id]
	return null


## Update all displays (call each frame).
func update(delta: float, assemblies: Dictionary) -> void:
	# assemblies: assembly_id -> AssemblyProcess
	for assembly_id in _displays:
		var display: AssemblyProgressDisplay = _displays[assembly_id]

		if assemblies.has(assembly_id):
			var process: AssemblyProcess = assemblies[assembly_id]
			display.update_from_process(process)

			# Check completion
			if process.is_complete and not display.is_complete():
				display.complete_display()


## Update a specific display directly.
func update_display(assembly_id: int, progress: float, part_name: String, remaining_time: float) -> void:
	if _displays.has(assembly_id):
		_displays[assembly_id].update_progress(progress, part_name, remaining_time)


## Remove display for assembly.
func remove_display(assembly_id: int) -> void:
	if not _displays.has(assembly_id):
		return

	var display: AssemblyProgressDisplay = _displays[assembly_id]

	# Disconnect signals
	if display.display_completed.is_connected(_on_display_completed):
		display.display_completed.disconnect(_on_display_completed)
	if display.display_cancelled.is_connected(_on_display_cancelled):
		display.display_cancelled.disconnect(_on_display_cancelled)

	# Clear and pool
	display.clear()
	_return_to_pool(display)

	_displays.erase(assembly_id)

	# Remove from factory tracking
	for factory_id in _factory_displays:
		var assemblies: Array = _factory_displays[factory_id]
		var idx := assemblies.find(assembly_id)
		if idx != -1:
			assemblies.remove_at(idx)
			break

	progress_display_removed.emit(assembly_id)


## Remove all displays for a factory.
func remove_factory_displays(factory_id: int) -> void:
	if not _factory_displays.has(factory_id):
		return

	var assemblies: Array = _factory_displays[factory_id].duplicate()
	for assembly_id in assemblies:
		remove_display(assembly_id)

	_factory_displays.erase(factory_id)


## Set zoom level for visibility control.
func set_zoom_level(zoom: float) -> void:
	_current_zoom = zoom

	for assembly_id in _displays:
		_displays[assembly_id].set_visible_for_zoom(zoom, _detail_threshold)


## Set detail threshold.
func set_detail_threshold(threshold: float) -> void:
	_detail_threshold = threshold
	set_zoom_level(_current_zoom)  # Reapply visibility


## Position display at screen location.
func position_display(assembly_id: int, screen_position: Vector2) -> void:
	if _displays.has(assembly_id):
		_displays[assembly_id].set_display_position(screen_position)


## Position all displays for a factory.
func position_factory_displays(factory_id: int, base_position: Vector2, offset: Vector2 = Vector2(0, 30)) -> void:
	if not _factory_displays.has(factory_id):
		return

	var assemblies: Array = _factory_displays[factory_id]
	var current_pos := base_position

	for assembly_id in assemblies:
		if _displays.has(assembly_id):
			_displays[assembly_id].set_display_position(current_pos)
			current_pos += offset


## Get pooled display or null.
func _get_pooled_display() -> AssemblyProgressDisplay:
	if _display_pool.is_empty():
		return null

	return _display_pool.pop_back()


## Return display to pool.
func _return_to_pool(display: AssemblyProgressDisplay) -> void:
	if _display_pool.size() < MAX_DISPLAYS:
		_display_pool.append(display)


## Handle display completion.
func _on_display_completed(assembly_id: int) -> void:
	# Check if all displays are complete
	var all_complete := true
	for id in _displays:
		if not _displays[id].is_complete():
			all_complete = false
			break

	if all_complete and not _displays.is_empty():
		all_assemblies_complete.emit()


## Handle display cancellation.
func _on_display_cancelled(assembly_id: int) -> void:
	# Auto-remove cancelled displays after a delay would need timer
	pass


## Get all active display IDs.
func get_active_display_ids() -> Array[int]:
	var ids: Array[int] = []
	for assembly_id in _displays:
		if _displays[assembly_id].is_active():
			ids.append(assembly_id)
	return ids


## Get displays for a factory.
func get_factory_display_ids(factory_id: int) -> Array:
	if _factory_displays.has(factory_id):
		return _factory_displays[factory_id].duplicate()
	return []


## Get active count.
func get_active_count() -> int:
	return _displays.size()


## Check if display exists.
func has_display(assembly_id: int) -> bool:
	return _displays.has(assembly_id)


## Cleanup all displays.
func cleanup() -> void:
	for assembly_id in _displays.keys():
		var display: AssemblyProgressDisplay = _displays[assembly_id]
		display.cleanup()

	_displays.clear()
	_factory_displays.clear()

	for display in _display_pool:
		display.cleanup()

	_display_pool.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var factory_counts: Dictionary = {}
	for factory_id in _factory_displays:
		factory_counts[factory_id] = _factory_displays[factory_id].size()

	return {
		"active_displays": _displays.size(),
		"pooled_displays": _display_pool.size(),
		"factory_distribution": factory_counts,
		"current_zoom": _current_zoom,
		"detail_threshold": _detail_threshold
	}
