class_name PowerGridDisplay
extends RefCounted
## PowerGridDisplay visualizes power grid network with lines and plant status.

signal line_selected(from_id: int, to_id: int)
signal plant_selected(plant_id: int)
signal blackout_warning_shown(district_id: int)

## Line colors
const LINE_INACTIVE_COLOR := Color.BLACK
const LINE_ACTIVE_LOW_COLOR := Color("#336633")
const LINE_ACTIVE_HIGH_COLOR := Color.GREEN
const LINE_OVERLOAD_COLOR := Color.ORANGE

## Plant status colors
const PLANT_OPERATIONAL_COLOR := Color.GREEN
const PLANT_DAMAGED_COLOR := Color.YELLOW
const PLANT_DESTROYED_COLOR := Color.RED

## Visual constants
const LINE_WIDTH := 2.0
const POWER_FLOW_ARROW_SIZE := 8.0
const UPDATE_THROTTLE := 0.05  ## Minimum time between visual updates

## Power network data
var _plants: Dictionary = {}       ## plant_id -> {position, power_output, max_power, status}
var _lines: Dictionary = {}        ## "from_to" -> {from_id, to_id, power_flow, max_capacity}
var _district_power: Dictionary = {}  ## district_id -> {powered, power_ratio}

## UI components
var _container: Control = null
var _line_renderer: Control = null
var _plant_indicators: Dictionary = {}  ## plant_id -> Control
var _district_indicators: Dictionary = {}  ## district_id -> DistrictPowerIndicator

## State
var _last_update_time := 0.0
var _needs_redraw := false

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = Control.new()
	_container.name = "PowerGridDisplay"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Line renderer (custom draw)
	_line_renderer = Control.new()
	_line_renderer.name = "LineRenderer"
	_line_renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_line_renderer.draw.connect(_draw_power_lines)
	_line_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_line_renderer)

	parent.add_child(_container)
	return _container


## Set power plant data.
func set_plant(plant_id: int, position: Vector2, power_output: float, max_power: float, status: int) -> void:
	_plants[plant_id] = {
		"position": position,
		"power_output": power_output,
		"max_power": max_power,
		"status": status  ## 0 = operational, 1 = damaged, 2 = destroyed
	}
	_create_plant_indicator(plant_id)
	_needs_redraw = true


## Remove power plant.
func remove_plant(plant_id: int) -> void:
	_plants.erase(plant_id)
	if _plant_indicators.has(plant_id):
		if is_instance_valid(_plant_indicators[plant_id]):
			_plant_indicators[plant_id].queue_free()
		_plant_indicators.erase(plant_id)
	_needs_redraw = true


## Set power line data.
func set_line(from_id: int, to_id: int, power_flow: float, max_capacity: float) -> void:
	var key := "%d_%d" % [from_id, to_id]
	_lines[key] = {
		"from_id": from_id,
		"to_id": to_id,
		"power_flow": power_flow,
		"max_capacity": max_capacity
	}
	_needs_redraw = true


## Remove power line.
func remove_line(from_id: int, to_id: int) -> void:
	var key := "%d_%d" % [from_id, to_id]
	_lines.erase(key)
	_needs_redraw = true


## Set district power status.
func set_district_power(district_id: int, powered: bool, power_ratio: float) -> void:
	_district_power[district_id] = {
		"powered": powered,
		"power_ratio": power_ratio
	}
	_update_district_indicator(district_id)


## Create plant indicator.
func _create_plant_indicator(plant_id: int) -> void:
	if _plant_indicators.has(plant_id):
		return

	var indicator := ColorRect.new()
	indicator.name = "PlantIndicator_%d" % plant_id
	indicator.custom_minimum_size = Vector2(12, 12)
	indicator.color = PLANT_OPERATIONAL_COLOR
	indicator.mouse_filter = Control.MOUSE_FILTER_STOP
	indicator.gui_input.connect(func(event): _on_plant_indicator_input(plant_id, event))

	_container.add_child(indicator)
	_plant_indicators[plant_id] = indicator
	_update_plant_indicator(plant_id)


## Update plant indicator.
func _update_plant_indicator(plant_id: int) -> void:
	if not _plants.has(plant_id) or not _plant_indicators.has(plant_id):
		return

	var plant: Dictionary = _plants[plant_id]
	var indicator: ColorRect = _plant_indicators[plant_id]

	# Set position
	indicator.position = plant["position"] - Vector2(6, 6)

	# Set color based on status
	match plant["status"]:
		0:  # Operational
			var ratio: float = plant["power_output"] / maxf(plant["max_power"], 1.0)
			indicator.color = PLANT_OPERATIONAL_COLOR.lerp(PLANT_DAMAGED_COLOR, 1.0 - ratio)
		1:  # Damaged
			indicator.color = PLANT_DAMAGED_COLOR
		2:  # Destroyed
			indicator.color = PLANT_DESTROYED_COLOR


## Update district indicator.
func _update_district_indicator(district_id: int) -> void:
	if not _district_indicators.has(district_id):
		return

	var data: Dictionary = _district_power.get(district_id, {})
	var indicator: DistrictPowerIndicator = _district_indicators[district_id]
	indicator.set_powered(data.get("powered", false), data.get("power_ratio", 0.0))


## Draw power lines.
func _draw_power_lines() -> void:
	if _line_renderer == null:
		return

	for key in _lines:
		var line: Dictionary = _lines[key]
		var from_id: int = line["from_id"]
		var to_id: int = line["to_id"]

		if not _plants.has(from_id) or not _plants.has(to_id):
			continue

		var from_pos: Vector2 = _plants[from_id]["position"]
		var to_pos: Vector2 = _plants[to_id]["position"]
		var power_flow: float = line["power_flow"]
		var max_capacity: float = line["max_capacity"]

		# Determine line color
		var line_color: Color
		if power_flow <= 0:
			line_color = LINE_INACTIVE_COLOR
		else:
			var ratio := power_flow / maxf(max_capacity, 1.0)
			if ratio > 1.0:
				line_color = LINE_OVERLOAD_COLOR
			else:
				line_color = LINE_ACTIVE_LOW_COLOR.lerp(LINE_ACTIVE_HIGH_COLOR, ratio)

		# Draw line
		_line_renderer.draw_line(from_pos, to_pos, line_color, LINE_WIDTH, true)

		# Draw power flow direction arrow
		if power_flow > 0:
			_draw_flow_arrow(from_pos, to_pos, line_color)


## Draw power flow arrow.
func _draw_flow_arrow(from_pos: Vector2, to_pos: Vector2, color: Color) -> void:
	var mid := (from_pos + to_pos) / 2
	var direction := (to_pos - from_pos).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)

	var arrow_tip := mid + direction * POWER_FLOW_ARROW_SIZE
	var arrow_left := mid - direction * POWER_FLOW_ARROW_SIZE / 2 + perpendicular * POWER_FLOW_ARROW_SIZE / 2
	var arrow_right := mid - direction * POWER_FLOW_ARROW_SIZE / 2 - perpendicular * POWER_FLOW_ARROW_SIZE / 2

	var points := PackedVector2Array([arrow_tip, arrow_left, arrow_right])
	_line_renderer.draw_polygon(points, PackedColorArray([color, color, color]))


## Handle plant indicator input.
func _on_plant_indicator_input(plant_id: int, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			plant_selected.emit(plant_id)


## Update power grid visual (call this each frame or on change).
func update_power_grid_visual() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_update_time < UPDATE_THROTTLE and not _needs_redraw:
		return

	_last_update_time = current_time
	_needs_redraw = false

	# Update plant indicators
	for plant_id in _plants:
		_update_plant_indicator(plant_id)

	# Redraw lines
	if _line_renderer != null:
		_line_renderer.queue_redraw()


## Register district indicator.
func register_district_indicator(district_id: int, indicator: DistrictPowerIndicator) -> void:
	_district_indicators[district_id] = indicator
	_update_district_indicator(district_id)


## Unregister district indicator.
func unregister_district_indicator(district_id: int) -> void:
	_district_indicators.erase(district_id)


## Clear all visuals.
func clear() -> void:
	_plants.clear()
	_lines.clear()
	_district_power.clear()

	for indicator in _plant_indicators.values():
		if is_instance_valid(indicator):
			indicator.queue_free()
	_plant_indicators.clear()

	_district_indicators.clear()
	_needs_redraw = true


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	clear()
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
