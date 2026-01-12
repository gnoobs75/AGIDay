class_name DetailViewManager
extends RefCounted
## DetailViewManager coordinates detail view displays for multiple factories.

signal factory_detail_opened(factory_id: int)
signal factory_detail_closed(factory_id: int)
signal assembly_started(factory_id: int, assembly_id: int)
signal assembly_completed(factory_id: int, assembly_id: int)

## Active displays
var _factory_displays: Dictionary = {}  ## factory_id -> DetailViewAssemblyDisplay

## Current factory in view
var _current_factory_id: int = -1

## Viewport and UI references
var _detail_viewport: SubViewport = null
var _ui_parent: Control = null

## Active display
var _active_display: DetailViewAssemblyDisplay = null


func _init() -> void:
	pass


## Initialize with viewport and UI parent.
func initialize(viewport: SubViewport, ui_parent: Control) -> void:
	_detail_viewport = viewport
	_ui_parent = ui_parent


## Open detail view for a factory.
func open_factory_detail(factory_id: int) -> DetailViewAssemblyDisplay:
	# Close current if different
	if _current_factory_id != factory_id and _current_factory_id >= 0:
		close_factory_detail()

	_current_factory_id = factory_id

	# Get or create display
	if not _factory_displays.has(factory_id):
		var display := DetailViewAssemblyDisplay.new()
		display.initialize(_detail_viewport, _ui_parent)

		# Connect signals
		display.assembly_display_started.connect(_on_assembly_started.bind(factory_id))
		display.assembly_display_completed.connect(_on_assembly_completed.bind(factory_id))

		_factory_displays[factory_id] = display

	_active_display = _factory_displays[factory_id]

	factory_detail_opened.emit(factory_id)

	return _active_display


## Close current factory detail.
func close_factory_detail() -> void:
	if _current_factory_id < 0:
		return

	if _active_display != null:
		_active_display.stop_display()
		_active_display.set_visible(false)

	var closed_id := _current_factory_id
	_current_factory_id = -1
	_active_display = null

	factory_detail_closed.emit(closed_id)


## Start assembly display for current factory.
func start_assembly(factory_id: int, assembly: AssemblyProcess) -> void:
	if factory_id != _current_factory_id:
		return

	if _active_display != null:
		_active_display.start_display(assembly)


## Update assembly display.
func update_assembly(factory_id: int, assembly: AssemblyProcess) -> void:
	if factory_id != _current_factory_id:
		return

	if _active_display != null:
		_active_display.update_display()


## Complete assembly display.
func complete_assembly(factory_id: int) -> void:
	if factory_id != _current_factory_id:
		return

	if _active_display != null:
		_active_display.complete_display()


## Update all displays (call each frame).
func update(_delta: float) -> void:
	if _active_display != null and _active_display.is_active():
		_active_display.update_display()


## Show no assembly state.
func show_no_assembly() -> void:
	if _active_display != null:
		_active_display.show_no_assembly()


## Handle assembly started.
func _on_assembly_started(assembly_id: int, factory_id: int) -> void:
	assembly_started.emit(factory_id, assembly_id)


## Handle assembly completed.
func _on_assembly_completed(assembly_id: int, factory_id: int) -> void:
	assembly_completed.emit(factory_id, assembly_id)


## Get current factory ID.
func get_current_factory() -> int:
	return _current_factory_id


## Check if detail view is open.
func is_detail_open() -> bool:
	return _current_factory_id >= 0


## Get active display.
func get_active_display() -> DetailViewAssemblyDisplay:
	return _active_display


## Get display for factory.
func get_factory_display(factory_id: int) -> DetailViewAssemblyDisplay:
	return _factory_displays.get(factory_id)


## Remove factory display.
func remove_factory_display(factory_id: int) -> void:
	if not _factory_displays.has(factory_id):
		return

	var display: DetailViewAssemblyDisplay = _factory_displays[factory_id]

	if factory_id == _current_factory_id:
		close_factory_detail()

	display.cleanup()
	_factory_displays.erase(factory_id)


## Cleanup all displays.
func cleanup() -> void:
	close_factory_detail()

	for factory_id in _factory_displays.keys():
		_factory_displays[factory_id].cleanup()

	_factory_displays.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"current_factory": _current_factory_id,
		"display_count": _factory_displays.size(),
		"is_detail_open": is_detail_open(),
		"active_display": _active_display.get_summary() if _active_display != null else {}
	}
