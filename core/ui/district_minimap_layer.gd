class_name DistrictMinimapLayer
extends RefCounted
## DistrictMinimapLayer renders 16x16 district grid on minimap with ownership colors.

signal district_hovered(district_id: int)
signal district_clicked(district_id: int)

## Grid dimensions
const GRID_SIZE := 16
const TOTAL_DISTRICTS := 256
const WORLD_SIZE := 512.0

## Visual settings
const DISTRICT_BORDER_WIDTH := 1.0
const PULSE_SPEED := 2.0  ## Contested pulse frequency

## District type icons (unicode for simple display)
const TYPE_ICONS := {
	"power_hub": "[P]",
	"ree_node": "[R]",
	"research_facility": "[S]",
	"mixed": "[M]",
	"empty": ""
}

## District data
var _districts: Dictionary = {}  ## district_id -> {owner, type, contested, capture_progress}

## UI nodes per district
var _district_nodes: Dictionary = {}  ## district_id -> Control

## Parent layer
var _layer: Control = null

## Render size
var _render_size: int = 512

## Animation state
var _pulse_phase := 0.0


func _init() -> void:
	pass


## Initialize with parent layer.
func initialize(layer: Control, render_size: int) -> void:
	_layer = layer
	_render_size = render_size
	_create_grid()


## Create the district grid.
func _create_grid() -> void:
	if _layer == null:
		return

	var cell_size := float(_render_size) / float(GRID_SIZE)

	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var district_id := y * GRID_SIZE + x

			var node := Control.new()
			node.name = "District_%d" % district_id
			node.position = Vector2(x * cell_size, y * cell_size)
			node.size = Vector2(cell_size, cell_size)

			# Store district ID for mouse events
			node.set_meta("district_id", district_id)

			# Connect draw and mouse events
			node.draw.connect(_draw_district.bind(district_id))
			node.mouse_entered.connect(func(): district_hovered.emit(district_id))
			node.gui_input.connect(_on_district_input.bind(district_id))
			node.mouse_filter = Control.MOUSE_FILTER_STOP

			_layer.add_child(node)
			_district_nodes[district_id] = node

			# Initialize default data
			_districts[district_id] = {
				"owner": "",
				"type": "empty",
				"contested": false,
				"capture_progress": {}  ## faction_id -> progress (0-100)
			}


## Draw a district cell.
func _draw_district(district_id: int) -> void:
	if not _district_nodes.has(district_id):
		return

	var node: Control = _district_nodes[district_id]
	var data: Dictionary = _districts[district_id]
	var rect := Rect2(Vector2.ZERO, node.size)

	# Determine fill color
	var fill_color: Color
	if data["owner"].is_empty():
		fill_color = Color("#444444")  ## Gray for uncaptured
	else:
		fill_color = UITheme.FACTION_COLORS.get(data["owner"], Color.GRAY)

	# Apply pulse for contested
	if data["contested"]:
		var pulse := (sin(_pulse_phase * PULSE_SPEED) + 1.0) * 0.5
		fill_color = fill_color.lerp(Color.WHITE, pulse * 0.3)

	# Draw fill
	node.draw_rect(rect, fill_color, true)

	# Draw border
	var border_color := fill_color.lightened(0.3)
	node.draw_rect(rect, border_color, false, DISTRICT_BORDER_WIDTH)

	# Draw type icon if not empty
	var type_icon: String = TYPE_ICONS.get(data["type"], "")
	if not type_icon.is_empty():
		var font := ThemeDB.fallback_font
		var font_size := 10
		var text_pos := rect.size * 0.5 - Vector2(font_size * 0.3, -font_size * 0.3)
		node.draw_string(font, text_pos, type_icon, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

	# Draw capture progress if contested
	if data["contested"] and not data["capture_progress"].is_empty():
		_draw_capture_progress(node, data["capture_progress"], rect)


## Draw capture progress bars.
func _draw_capture_progress(node: Control, progress: Dictionary, rect: Rect2) -> void:
	var bar_height := 4.0
	var y := rect.size.y - bar_height - 2

	var total := 0.0
	for faction in progress:
		total += progress[faction]

	if total <= 0:
		return

	var x := 2.0
	var bar_width := rect.size.x - 4

	for faction in progress:
		var faction_progress: float = progress[faction]
		var width := (faction_progress / 100.0) * bar_width
		var color := UITheme.FACTION_COLORS.get(faction, Color.GRAY)
		node.draw_rect(Rect2(x, y, width, bar_height), color)
		x += width


## Update district data.
func update_district(district_id: int, owner: String, type: String, contested: bool, capture_progress: Dictionary = {}) -> void:
	if not _districts.has(district_id):
		return

	_districts[district_id] = {
		"owner": owner,
		"type": type,
		"contested": contested,
		"capture_progress": capture_progress.duplicate()
	}

	if _district_nodes.has(district_id):
		_district_nodes[district_id].queue_redraw()


## Update single property.
func set_district_owner(district_id: int, owner: String) -> void:
	if _districts.has(district_id):
		_districts[district_id]["owner"] = owner
		_request_redraw(district_id)


func set_district_contested(district_id: int, contested: bool) -> void:
	if _districts.has(district_id):
		_districts[district_id]["contested"] = contested
		_request_redraw(district_id)


func set_capture_progress(district_id: int, progress: Dictionary) -> void:
	if _districts.has(district_id):
		_districts[district_id]["capture_progress"] = progress.duplicate()
		_request_redraw(district_id)


## Request redraw.
func _request_redraw(district_id: int) -> void:
	if _district_nodes.has(district_id):
		_district_nodes[district_id].queue_redraw()


## Handle district input.
func _on_district_input(event: InputEvent, district_id: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			district_clicked.emit(district_id)


## Update animation (call each frame for contested pulse).
func update(delta: float) -> void:
	_pulse_phase += delta

	# Redraw contested districts
	for district_id in _districts:
		if _districts[district_id]["contested"]:
			_request_redraw(district_id)


## Convert world position to district ID.
func world_to_district_id(world_pos: Vector3) -> int:
	var grid_x := int(world_pos.x / (WORLD_SIZE / GRID_SIZE))
	var grid_y := int(world_pos.z / (WORLD_SIZE / GRID_SIZE))

	grid_x = clampi(grid_x, 0, GRID_SIZE - 1)
	grid_y = clampi(grid_y, 0, GRID_SIZE - 1)

	return grid_y * GRID_SIZE + grid_x


## Convert district ID to world position (center).
func district_id_to_world(district_id: int) -> Vector3:
	var grid_x := district_id % GRID_SIZE
	var grid_y := district_id / GRID_SIZE
	var cell_size := WORLD_SIZE / GRID_SIZE

	return Vector3(
		(grid_x + 0.5) * cell_size,
		0,
		(grid_y + 0.5) * cell_size
	)


## Get district data.
func get_district_data(district_id: int) -> Dictionary:
	return _districts.get(district_id, {}).duplicate()


## Get all districts owned by faction.
func get_faction_districts(faction_id: String) -> Array[int]:
	var result: Array[int] = []
	for district_id in _districts:
		if _districts[district_id]["owner"] == faction_id:
			result.append(district_id)
	return result


## Get ownership statistics.
func get_ownership_stats() -> Dictionary:
	var stats: Dictionary = {}

	for district_id in _districts:
		var owner: String = _districts[district_id]["owner"]
		if owner.is_empty():
			stats["neutral"] = stats.get("neutral", 0) + 1
		else:
			stats[owner] = stats.get(owner, 0) + 1

	return stats


## Cleanup.
func cleanup() -> void:
	for node in _district_nodes.values():
		if node != null and is_instance_valid(node):
			node.queue_free()

	_district_nodes.clear()
	_districts.clear()
