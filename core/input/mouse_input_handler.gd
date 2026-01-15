class_name MouseInputHandler
extends RefCounted
## MouseInputHandler processes mouse input for selection, camera, and interaction.
## Supports zoom, panning, and world object detection.

signal mouse_action(action: String, data: Dictionary)
signal selection_started(position: Vector2)
signal selection_ended(start: Vector2, end: Vector2)
signal hover_changed(object_type: String, object_data: Dictionary)
signal zoom_changed(zoom_level: float)
signal pan_started()
signal pan_ended()

## Mouse buttons
const BUTTON_LEFT := MOUSE_BUTTON_LEFT
const BUTTON_RIGHT := MOUSE_BUTTON_RIGHT
const BUTTON_MIDDLE := MOUSE_BUTTON_MIDDLE

## Configuration
const DOUBLE_CLICK_TIME := 0.3           ## 300ms for double click
const DRAG_THRESHOLD := 5.0              ## Pixels before drag starts
const ZOOM_SENSITIVITY := 0.1            ## Per scroll tick
const PAN_SENSITIVITY := 1.0             ## Pan speed multiplier
const MIN_ZOOM := 0.5
const MAX_ZOOM := 3.0

## State
var _left_pressed := false
var _right_pressed := false
var _middle_pressed := false
var _mouse_position := Vector2.ZERO
var _last_mouse_position := Vector2.ZERO

## Drag state
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_button := BUTTON_LEFT

## Double click tracking
var _last_click_time := 0.0
var _last_click_position := Vector2.ZERO
var _click_count := 0

## Panning state
var _is_panning := false
var _pan_start := Vector2.ZERO

## Selection box
var _is_selecting := false
var _selection_start := Vector2.ZERO

## Zoom
var _current_zoom := 1.0

## Hover tracking
var _hover_object_type := ""
var _hover_object_data: Dictionary = {}

## Cursor state
var _cursor_mode := "default"


func _init() -> void:
	pass


## Initialize mouse handler.
func initialize() -> void:
	pass


## Process input event.
func process_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return _handle_button_event(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		return _handle_motion_event(event as InputEventMouseMotion)
	return false


## Handle mouse button event.
func _handle_button_event(event: InputEventMouseButton) -> bool:
	_mouse_position = event.position
	var button := event.button_index
	var pressed := event.pressed

	match button:
		BUTTON_LEFT:
			return _handle_left_button(pressed)
		BUTTON_RIGHT:
			return _handle_right_button(pressed)
		BUTTON_MIDDLE:
			return _handle_middle_button(pressed)
		MOUSE_BUTTON_WHEEL_UP:
			if pressed:
				return _handle_zoom_in()
		MOUSE_BUTTON_WHEEL_DOWN:
			if pressed:
				return _handle_zoom_out()

	return false


## Handle left button.
func _handle_left_button(pressed: bool) -> bool:
	if pressed:
		_left_pressed = true
		_drag_start = _mouse_position
		_drag_button = BUTTON_LEFT

		# Check for double click
		var current_time := Time.get_ticks_msec() / 1000.0
		var time_diff := current_time - _last_click_time
		var dist := _mouse_position.distance_to(_last_click_position)

		if time_diff < DOUBLE_CLICK_TIME and dist < DRAG_THRESHOLD:
			_click_count += 1
		else:
			_click_count = 1

		_last_click_time = current_time
		_last_click_position = _mouse_position

		if _click_count >= 2:
			mouse_action.emit("double_click", {"position": _mouse_position})
			_click_count = 0
			return true

		return true
	else:
		_left_pressed = false

		if _is_selecting:
			# End selection box
			_is_selecting = false
			selection_ended.emit(_selection_start, _mouse_position)
			mouse_action.emit("selection_box", {
				"start": _selection_start,
				"end": _mouse_position
			})
			return true
		elif _is_dragging:
			# End drag
			_is_dragging = false
			mouse_action.emit("drag_end", {
				"start": _drag_start,
				"end": _mouse_position
			})
			return true
		else:
			# Click
			mouse_action.emit("click", {"position": _mouse_position})
			return true

	return false


## Handle right button.
func _handle_right_button(pressed: bool) -> bool:
	if pressed:
		_right_pressed = true
		_pan_start = _mouse_position
		_is_panning = true
		pan_started.emit()
		mouse_action.emit("right_click_start", {"position": _mouse_position})
		return true
	else:
		_right_pressed = false

		if _is_panning:
			_is_panning = false
			pan_ended.emit()

			# If didn't pan much, treat as right click
			if _mouse_position.distance_to(_pan_start) < DRAG_THRESHOLD:
				mouse_action.emit("right_click", {"position": _mouse_position})
			else:
				mouse_action.emit("pan_end", {
					"start": _pan_start,
					"end": _mouse_position
				})
			return true

	return false


## Handle middle button.
func _handle_middle_button(pressed: bool) -> bool:
	if pressed:
		_middle_pressed = true
		_pan_start = _mouse_position
		mouse_action.emit("middle_click", {"position": _mouse_position})
		return true
	else:
		_middle_pressed = false
		return true

	return false


## Handle zoom in.
func _handle_zoom_in() -> bool:
	var new_zoom := clampf(_current_zoom + ZOOM_SENSITIVITY, MIN_ZOOM, MAX_ZOOM)
	if new_zoom != _current_zoom:
		_current_zoom = new_zoom
		zoom_changed.emit(_current_zoom)
		mouse_action.emit("zoom", {
			"level": _current_zoom,
			"direction": "in",
			"position": _mouse_position
		})
	return true


## Handle zoom out.
func _handle_zoom_out() -> bool:
	var new_zoom := clampf(_current_zoom - ZOOM_SENSITIVITY, MIN_ZOOM, MAX_ZOOM)
	if new_zoom != _current_zoom:
		_current_zoom = new_zoom
		zoom_changed.emit(_current_zoom)
		mouse_action.emit("zoom", {
			"level": _current_zoom,
			"direction": "out",
			"position": _mouse_position
		})
	return true


## Handle mouse motion.
func _handle_motion_event(event: InputEventMouseMotion) -> bool:
	_last_mouse_position = _mouse_position
	_mouse_position = event.position

	# Panning with right button
	if _is_panning:
		var delta := _mouse_position - _last_mouse_position
		mouse_action.emit("pan", {
			"delta": delta * PAN_SENSITIVITY,
			"position": _mouse_position
		})
		return true

	# Selection box with left button
	if _left_pressed and not _is_selecting and not _is_dragging:
		var dist := _mouse_position.distance_to(_drag_start)
		if dist > DRAG_THRESHOLD:
			_is_selecting = true
			_selection_start = _drag_start
			selection_started.emit(_selection_start)

	if _is_selecting:
		mouse_action.emit("selection_update", {
			"start": _selection_start,
			"end": _mouse_position
		})
		return true

	# Hover update
	mouse_action.emit("move", {"position": _mouse_position})

	return false


## Update (call each frame).
func update(delta: float) -> void:
	# Edge panning could be implemented here
	pass


## Set hover object.
func set_hover_object(object_type: String, object_data: Dictionary) -> void:
	if object_type != _hover_object_type or object_data != _hover_object_data:
		_hover_object_type = object_type
		_hover_object_data = object_data
		hover_changed.emit(object_type, object_data)

		# Update cursor
		_update_cursor(object_type)


## Clear hover object.
func clear_hover_object() -> void:
	if not _hover_object_type.is_empty():
		_hover_object_type = ""
		_hover_object_data = {}
		hover_changed.emit("", {})
		_update_cursor("default")


## Update cursor based on context.
func _update_cursor(context: String) -> void:
	var new_cursor := "default"

	match context:
		"unit":
			new_cursor = "select"
		"enemy":
			new_cursor = "attack"
		"building":
			new_cursor = "interact"
		"resource":
			new_cursor = "gather"
		"ui":
			new_cursor = "pointer"

	if new_cursor != _cursor_mode:
		_cursor_mode = new_cursor
		# Would apply cursor here via Input.set_custom_mouse_cursor()


## Get current mouse position.
func get_mouse_position() -> Vector2:
	return _mouse_position


## Get current zoom level.
func get_zoom_level() -> float:
	return _current_zoom


## Set zoom level.
func set_zoom_level(level: float) -> void:
	_current_zoom = clampf(level, MIN_ZOOM, MAX_ZOOM)
	zoom_changed.emit(_current_zoom)


## Is currently panning.
func is_panning() -> bool:
	return _is_panning


## Is currently selecting.
func is_selecting() -> bool:
	return _is_selecting


## Get selection box.
func get_selection_box() -> Rect2:
	if not _is_selecting:
		return Rect2()

	var min_pos := Vector2(
		minf(_selection_start.x, _mouse_position.x),
		minf(_selection_start.y, _mouse_position.y)
	)
	var max_pos := Vector2(
		maxf(_selection_start.x, _mouse_position.x),
		maxf(_selection_start.y, _mouse_position.y)
	)

	return Rect2(min_pos, max_pos - min_pos)


## Get hover info.
func get_hover_info() -> Dictionary:
	return {
		"type": _hover_object_type,
		"data": _hover_object_data
	}


## Cancel current action.
func cancel_action() -> void:
	if _is_selecting:
		_is_selecting = false
		mouse_action.emit("selection_cancelled", {})
	if _is_panning:
		_is_panning = false
		pan_ended.emit()
	if _is_dragging:
		_is_dragging = false
		mouse_action.emit("drag_cancelled", {})


## Get status.
func get_status() -> Dictionary:
	return {
		"position": _mouse_position,
		"zoom": _current_zoom,
		"is_panning": _is_panning,
		"is_selecting": _is_selecting,
		"hover_type": _hover_object_type,
		"cursor_mode": _cursor_mode
	}
