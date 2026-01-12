class_name MinimapInteraction
extends RefCounted
## MinimapInteraction handles click-to-pan and drag-to-select on minimap.

signal minimap_clicked(position: Vector2)
signal minimap_dragged(start: Vector2, end: Vector2)
signal right_click_menu_requested(position: Vector2)

## Interaction state
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO

## Minimap reference
var _minimap_rect: Control = null
var _render_size: int = 512
var _display_size: int = 256

## Camera view indicator
var _camera_view_rect := Rect2()

## Selection rectangle visual
var _selection_rect: Control = null


func _init() -> void:
	pass


## Initialize with minimap rect.
func initialize(minimap_rect: Control, render_size: int, display_size: int) -> void:
	_minimap_rect = minimap_rect
	_render_size = render_size
	_display_size = display_size

	# Connect input events
	_minimap_rect.gui_input.connect(_on_minimap_input)
	_minimap_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	# Create selection rectangle overlay
	_selection_rect = Control.new()
	_selection_rect.name = "SelectionRect"
	_selection_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selection_rect.visible = false
	_selection_rect.draw.connect(_draw_selection_rect)
	_minimap_rect.add_child(_selection_rect)


## Handle minimap input.
func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


## Handle mouse button events.
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var local_pos := _get_local_position(event.position)

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start potential drag
			_is_dragging = true
			_drag_start = local_pos
			_drag_current = local_pos
			_selection_rect.visible = true
			_selection_rect.queue_redraw()
		else:
			# End drag or click
			if _is_dragging:
				var drag_dist := _drag_current.distance_to(_drag_start)

				if drag_dist < 5.0:
					# It was a click
					minimap_clicked.emit(_display_to_render(local_pos))
				else:
					# It was a drag
					minimap_dragged.emit(
						_display_to_render(_drag_start),
						_display_to_render(_drag_current)
					)

			_is_dragging = false
			_selection_rect.visible = false

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			right_click_menu_requested.emit(event.global_position)


## Handle mouse motion.
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_dragging:
		_drag_current = _get_local_position(event.position)
		_selection_rect.queue_redraw()


## Get local position within minimap.
func _get_local_position(global_pos: Vector2) -> Vector2:
	if _minimap_rect == null:
		return Vector2.ZERO

	return global_pos - _minimap_rect.global_position


## Convert display coordinates to render coordinates.
func _display_to_render(display_pos: Vector2) -> Vector2:
	return display_pos * (float(_render_size) / float(_display_size))


## Convert render coordinates to display coordinates.
func _render_to_display(render_pos: Vector2) -> Vector2:
	return render_pos * (float(_display_size) / float(_render_size))


## Draw selection rectangle.
func _draw_selection_rect() -> void:
	if not _is_dragging or _selection_rect == null:
		return

	var rect := Rect2(_drag_start, _drag_current - _drag_start).abs()

	# Draw selection box
	_selection_rect.draw_rect(rect, Color(1, 1, 1, 0.3), true)
	_selection_rect.draw_rect(rect, Color.WHITE, false, 1.0)


## Set camera view rect for indicator.
func set_camera_view_rect(rect: Rect2) -> void:
	_camera_view_rect = rect


## Get camera view rect.
func get_camera_view_rect() -> Rect2:
	return _camera_view_rect


## Check if point is inside minimap.
func is_point_inside(global_pos: Vector2) -> bool:
	if _minimap_rect == null:
		return false

	var local := _get_local_position(global_pos)
	return local.x >= 0 and local.y >= 0 and local.x < _display_size and local.y < _display_size


## Get world position from screen position.
func screen_to_minimap(screen_pos: Vector2) -> Vector2:
	if _minimap_rect == null:
		return Vector2.ZERO

	var local := _get_local_position(screen_pos)
	return _display_to_render(local)


## Check if dragging.
func is_dragging() -> bool:
	return _is_dragging


## Cancel drag.
func cancel_drag() -> void:
	_is_dragging = false
	if _selection_rect != null:
		_selection_rect.visible = false


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"is_dragging": _is_dragging,
		"drag_start": _drag_start,
		"drag_current": _drag_current,
		"display_size": _display_size,
		"render_size": _render_size
	}
