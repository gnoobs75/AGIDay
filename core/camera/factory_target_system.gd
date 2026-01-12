class_name FactoryTargetSystem
extends RefCounted
## FactoryTargetSystem manages factory selection for camera targeting.

signal factory_selected(factory_id: int)
signal factory_deselected(factory_id: int)
signal factory_hovered(factory_id: int)
signal factory_unhovered(factory_id: int)
signal target_changed(old_factory_id: int, new_factory_id: int)

## Selection state
var _selected_factory_id: int = -1
var _hovered_factory_id: int = -1

## Factory registry
var _factories: Dictionary = {}  ## factory_id -> FactoryData

## Camera controller reference
var _camera_controller: FactoryCameraController = null

## Selection settings
var _auto_zoom_on_select: bool = true
var _zoom_level_on_select: float = 1.0


## Factory data class
class FactoryData:
	var factory_id: int = -1
	var position: Vector3 = Vector3.ZERO
	var faction_id: String = ""
	var is_selectable: bool = true
	var bounds_radius: float = 5.0
	var display_name: String = ""


func _init() -> void:
	pass


## Set camera controller reference.
func set_camera_controller(controller: FactoryCameraController) -> void:
	_camera_controller = controller


## Register a factory.
func register_factory(
	factory_id: int,
	position: Vector3,
	faction_id: String,
	display_name: String = ""
) -> void:
	var data := FactoryData.new()
	data.factory_id = factory_id
	data.position = position
	data.faction_id = faction_id
	data.display_name = display_name if not display_name.is_empty() else "Factory %d" % factory_id

	_factories[factory_id] = data


## Unregister a factory.
func unregister_factory(factory_id: int) -> void:
	if factory_id == _selected_factory_id:
		deselect()

	if factory_id == _hovered_factory_id:
		_hovered_factory_id = -1
		factory_unhovered.emit(factory_id)

	_factories.erase(factory_id)


## Update factory position.
func update_factory_position(factory_id: int, position: Vector3) -> void:
	if _factories.has(factory_id):
		_factories[factory_id].position = position

		# Update camera target if this is the selected factory
		if factory_id == _selected_factory_id and _camera_controller != null:
			_camera_controller.target_factory(factory_id, position)


## Set factory selectable state.
func set_factory_selectable(factory_id: int, selectable: bool) -> void:
	if _factories.has(factory_id):
		_factories[factory_id].is_selectable = selectable

		# Deselect if no longer selectable
		if not selectable and factory_id == _selected_factory_id:
			deselect()


## Select a factory.
func select_factory(factory_id: int) -> bool:
	if not _factories.has(factory_id):
		return false

	var data: FactoryData = _factories[factory_id]
	if not data.is_selectable:
		return false

	var old_id := _selected_factory_id
	_selected_factory_id = factory_id

	# Emit signals
	if old_id >= 0:
		factory_deselected.emit(old_id)

	factory_selected.emit(factory_id)
	target_changed.emit(old_id, factory_id)

	# Update camera
	if _camera_controller != null:
		_camera_controller.target_factory(factory_id, data.position)

		if _auto_zoom_on_select:
			_camera_controller.zoom_to(_zoom_level_on_select)

	return true


## Deselect current factory.
func deselect() -> void:
	if _selected_factory_id < 0:
		return

	var old_id := _selected_factory_id
	_selected_factory_id = -1

	factory_deselected.emit(old_id)
	target_changed.emit(old_id, -1)

	if _camera_controller != null:
		_camera_controller.clear_target()


## Set hovered factory.
func set_hovered(factory_id: int) -> void:
	if factory_id == _hovered_factory_id:
		return

	var old_hovered := _hovered_factory_id
	_hovered_factory_id = factory_id

	if old_hovered >= 0:
		factory_unhovered.emit(old_hovered)

	if factory_id >= 0:
		factory_hovered.emit(factory_id)


## Clear hover state.
func clear_hover() -> void:
	set_hovered(-1)


## Get factory at world position.
func get_factory_at_position(world_position: Vector3) -> int:
	for factory_id in _factories:
		var data: FactoryData = _factories[factory_id]

		# Check distance to factory center
		var distance := data.position.distance_to(world_position)
		if distance <= data.bounds_radius:
			return factory_id

	return -1


## Get factory by screen position (requires camera).
func get_factory_at_screen_position(screen_pos: Vector2, camera: Camera3D) -> int:
	if camera == null:
		return -1

	# Cast ray from camera through screen position
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0

	# Check intersection with factory positions (simplified)
	var closest_id := -1
	var closest_distance := INF

	for factory_id in _factories:
		var data: FactoryData = _factories[factory_id]

		# Check if ray passes near factory position
		var ray_dir := (to - from).normalized()
		var to_factory := data.position - from
		var projection := to_factory.dot(ray_dir)

		if projection > 0:
			var closest_point := from + ray_dir * projection
			var distance := data.position.distance_to(closest_point)

			if distance <= data.bounds_radius and projection < closest_distance:
				closest_id = factory_id
				closest_distance = projection

	return closest_id


## Cycle to next factory.
func select_next_factory() -> void:
	var factory_ids := _factories.keys()
	if factory_ids.is_empty():
		return

	factory_ids.sort()

	if _selected_factory_id < 0:
		select_factory(factory_ids[0])
	else:
		var current_idx := factory_ids.find(_selected_factory_id)
		var next_idx := (current_idx + 1) % factory_ids.size()
		select_factory(factory_ids[next_idx])


## Cycle to previous factory.
func select_previous_factory() -> void:
	var factory_ids := _factories.keys()
	if factory_ids.is_empty():
		return

	factory_ids.sort()

	if _selected_factory_id < 0:
		select_factory(factory_ids[factory_ids.size() - 1])
	else:
		var current_idx := factory_ids.find(_selected_factory_id)
		var prev_idx := (current_idx - 1 + factory_ids.size()) % factory_ids.size()
		select_factory(factory_ids[prev_idx])


## Get selected factory ID.
func get_selected_factory_id() -> int:
	return _selected_factory_id


## Get hovered factory ID.
func get_hovered_factory_id() -> int:
	return _hovered_factory_id


## Check if any factory is selected.
func has_selection() -> bool:
	return _selected_factory_id >= 0


## Get factory data.
func get_factory_data(factory_id: int) -> FactoryData:
	return _factories.get(factory_id)


## Get all factory IDs.
func get_all_factory_ids() -> Array[int]:
	var ids: Array[int] = []
	for factory_id in _factories:
		ids.append(factory_id)
	return ids


## Get factories by faction.
func get_factories_by_faction(faction_id: String) -> Array[int]:
	var ids: Array[int] = []
	for factory_id in _factories:
		if _factories[factory_id].faction_id == faction_id:
			ids.append(factory_id)
	return ids


## Set auto-zoom on select.
func set_auto_zoom(enabled: bool, zoom_level: float = 1.0) -> void:
	_auto_zoom_on_select = enabled
	_zoom_level_on_select = clampf(zoom_level, 0.0, 1.0)


## Get factory count.
func get_factory_count() -> int:
	return _factories.size()


## Clear all factories.
func clear() -> void:
	deselect()
	_hovered_factory_id = -1
	_factories.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"factory_count": _factories.size(),
		"selected_factory": _selected_factory_id,
		"hovered_factory": _hovered_factory_id,
		"auto_zoom": _auto_zoom_on_select,
		"has_camera_controller": _camera_controller != null
	}
