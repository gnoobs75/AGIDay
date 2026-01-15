class_name MinimapContent
extends RefCounted
## MinimapContent manages units, buildings, districts, and fog on the minimap.

## Icon sizes
const UNIT_SIZE := 4.0
const BUILDING_SIZE := 8.0
const DISTRICT_BORDER_WIDTH := 2.0

## World bounds
const WORLD_SIZE := 512.0

## Renderer reference
var _renderer: MinimapRenderer = null

## Entity tracking
var _units: Dictionary = {}       ## unit_id -> {position, faction, node}
var _buildings: Dictionary = {}   ## building_id -> {position, faction, size, node}
var _districts: Dictionary = {}   ## district_id -> {bounds, faction, node}

## Fog texture
var _fog_texture: ImageTexture = null
var _fog_node: TextureRect = null

## Power grid lines
var _power_lines: Array[Dictionary] = []  ## [{from, to, node}]


func _init() -> void:
	pass


## Initialize with renderer.
func initialize(renderer: MinimapRenderer) -> void:
	_renderer = renderer


## Render content to texture.
func render_to_texture(layer_visibility: Dictionary) -> void:
	if _renderer == null:
		return

	# Update layer visibility
	_renderer.set_layer_visible("units", layer_visibility.get("units", true))
	_renderer.set_layer_visible("buildings", layer_visibility.get("buildings", true))
	_renderer.set_layer_visible("fog", layer_visibility.get("fog", true))
	_renderer.set_layer_visible("districts", layer_visibility.get("districts", true))
	_renderer.set_layer_visible("power_grid", layer_visibility.get("power_grid", false))

	# Update entity positions
	_update_unit_nodes()
	_update_building_nodes()


## Add unit.
func add_unit(unit_id: int, position: Vector3, faction_id: String) -> void:
	if _renderer == null:
		return

	var minimap_pos := _world_to_minimap(position)
	var color: Color = UITheme.FACTION_COLORS.get(faction_id, Color.GRAY)

	# Create unit dot
	var node := ColorRect.new()
	node.name = "Unit_%d" % unit_id
	node.color = color
	node.size = Vector2(UNIT_SIZE, UNIT_SIZE)
	node.position = minimap_pos - Vector2(UNIT_SIZE / 2, UNIT_SIZE / 2)

	_renderer.get_unit_layer().add_child(node)

	_units[unit_id] = {
		"position": position,
		"faction": faction_id,
		"node": node
	}


## Update unit position.
func update_unit(unit_id: int, position: Vector3) -> void:
	if not _units.has(unit_id):
		return

	var data: Dictionary = _units[unit_id]
	data["position"] = position

	var minimap_pos := _world_to_minimap(position)
	var node: ColorRect = data["node"]
	if node != null and is_instance_valid(node):
		node.position = minimap_pos - Vector2(UNIT_SIZE / 2, UNIT_SIZE / 2)


## Remove unit.
func remove_unit(unit_id: int) -> void:
	if not _units.has(unit_id):
		return

	var data: Dictionary = _units[unit_id]
	var node: Control = data["node"]
	if node != null and is_instance_valid(node):
		node.queue_free()

	_units.erase(unit_id)


## Add building.
func add_building(building_id: int, position: Vector3, faction_id: String, size: float = 1.0) -> void:
	if _renderer == null:
		return

	var minimap_pos := _world_to_minimap(position)
	var color: Color = UITheme.FACTION_COLORS.get(faction_id, Color.GRAY)
	var building_size := BUILDING_SIZE * size

	# Create building square
	var node := ColorRect.new()
	node.name = "Building_%d" % building_id
	node.color = color
	node.size = Vector2(building_size, building_size)
	node.position = minimap_pos - Vector2(building_size / 2, building_size / 2)

	_renderer.get_building_layer().add_child(node)

	_buildings[building_id] = {
		"position": position,
		"faction": faction_id,
		"size": size,
		"node": node
	}


## Remove building.
func remove_building(building_id: int) -> void:
	if not _buildings.has(building_id):
		return

	var data: Dictionary = _buildings[building_id]
	var node: Control = data["node"]
	if node != null and is_instance_valid(node):
		node.queue_free()

	_buildings.erase(building_id)


## Update district.
func update_district(district_id: int, bounds: Rect2, faction_id: String) -> void:
	if _renderer == null:
		return

	# Remove existing
	if _districts.has(district_id):
		var old_data: Dictionary = _districts[district_id]
		var old_node: Control = old_data["node"]
		if old_node != null and is_instance_valid(old_node):
			old_node.queue_free()

	var color: Color = UITheme.FACTION_COLORS.get(faction_id, Color.GRAY)

	# Convert bounds to minimap coords
	var minimap_pos := _world_to_minimap(Vector3(bounds.position.x, 0, bounds.position.y))
	var minimap_size := bounds.size * (_renderer.get_render_size() / WORLD_SIZE)

	# Create district border using a custom draw control
	var node := Control.new()
	node.name = "District_%d" % district_id
	node.position = minimap_pos
	node.size = minimap_size

	# Store color for drawing
	node.set_meta("district_color", color)
	node.draw.connect(func():
		var c: Color = node.get_meta("district_color", Color.GRAY)
		node.draw_rect(Rect2(Vector2.ZERO, node.size), c, false, DISTRICT_BORDER_WIDTH)
	)
	node.queue_redraw()

	_renderer.get_district_layer().add_child(node)

	_districts[district_id] = {
		"bounds": bounds,
		"faction": faction_id,
		"node": node
	}


## Set fog texture.
func set_fog_texture(texture: ImageTexture) -> void:
	_fog_texture = texture

	if _renderer == null:
		return

	if _fog_node == null:
		_fog_node = TextureRect.new()
		_fog_node.name = "FogTexture"
		_fog_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fog_node.stretch_mode = TextureRect.STRETCH_SCALE
		_fog_node.modulate.a = 0.7  ## Semi-transparent fog
		_renderer.get_fog_layer().add_child(_fog_node)

	_fog_node.texture = texture


## Add power grid line.
func add_power_line(from_pos: Vector3, to_pos: Vector3) -> void:
	if _renderer == null:
		return

	var from_minimap := _world_to_minimap(from_pos)
	var to_minimap := _world_to_minimap(to_pos)

	var node := Line2D.new()
	node.name = "PowerLine_%d" % _power_lines.size()
	node.add_point(from_minimap)
	node.add_point(to_minimap)
	node.default_color = Color.YELLOW
	node.width = 1.0

	_renderer.get_power_layer().add_child(node)

	_power_lines.append({
		"from": from_pos,
		"to": to_pos,
		"node": node
	})


## Clear power grid.
func clear_power_grid() -> void:
	for line_data in _power_lines:
		var node: Line2D = line_data["node"]
		if node != null and is_instance_valid(node):
			node.queue_free()

	_power_lines.clear()


## Update unit nodes.
func _update_unit_nodes() -> void:
	for unit_id in _units:
		var data: Dictionary = _units[unit_id]
		var node: ColorRect = data["node"]
		if node != null and is_instance_valid(node):
			var minimap_pos := _world_to_minimap(data["position"])
			node.position = minimap_pos - Vector2(UNIT_SIZE / 2, UNIT_SIZE / 2)


## Update building nodes.
func _update_building_nodes() -> void:
	# Buildings are static, just ensure nodes are valid
	pass


## Convert world to minimap coordinates.
func _world_to_minimap(world_pos: Vector3) -> Vector2:
	if _renderer == null:
		return Vector2.ZERO

	var render_size := float(_renderer.get_render_size())
	return Vector2(
		(world_pos.x / WORLD_SIZE) * render_size,
		(world_pos.z / WORLD_SIZE) * render_size
	)


## Get unit count.
func get_unit_count() -> int:
	return _units.size()


## Get building count.
func get_building_count() -> int:
	return _buildings.size()


## Get district count.
func get_district_count() -> int:
	return _districts.size()


## Clear all content.
func clear_all() -> void:
	# Clear units
	for unit_id in _units.keys():
		remove_unit(unit_id)

	# Clear buildings
	for building_id in _buildings.keys():
		remove_building(building_id)

	# Clear districts
	for district_id in _districts:
		var data: Dictionary = _districts[district_id]
		var node: Control = data["node"]
		if node != null and is_instance_valid(node):
			node.queue_free()
	_districts.clear()

	# Clear power grid
	clear_power_grid()

	# Clear fog
	if _fog_node != null and is_instance_valid(_fog_node):
		_fog_node.queue_free()
		_fog_node = null


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"unit_count": _units.size(),
		"building_count": _buildings.size(),
		"district_count": _districts.size(),
		"power_lines": _power_lines.size(),
		"has_fog": _fog_texture != null
	}
