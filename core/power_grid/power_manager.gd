class_name PowerManager
extends RefCounted
## PowerManager handles power grid connections, blackouts, and cascading failures.
## Manages power plants, lines, and district power distribution.

signal power_line_destroyed(from: Vector2i, to: Vector2i)
signal blackout_started(affected_districts: Array)
signal blackout_ended(district_id: int)
signal power_restored(district_id: int)
signal cascade_failure(origin: Vector2i, affected_count: int)

## Power plant types
enum PlantType {
	FUSION_REACTOR,
	SOLAR_PANEL,
	SUBSTATION
}

## Power line state
enum LineState {
	INTACT,
	DAMAGED,
	DESTROYED
}

## Configuration
const FUSION_OUTPUT := 1000.0         ## MW per fusion reactor
const SOLAR_OUTPUT := 50.0            ## MW per solar panel
const SUBSTATION_CAPACITY := 500.0    ## MW throughput
const LINE_HP := 100.0
const CASCADE_DELAY := 1.0            ## Seconds between cascade steps

## Power plants
var _plants: Dictionary = {}          ## Vector2i -> PlantData
var _plant_count := 0

## Power lines
var _lines: Dictionary = {}           ## line_id -> LineData
var _line_count := 0

## District power state
var _district_power: Dictionary = {}  ## district_id -> {generation, consumption, powered}

## Connection graph
var _connections: Dictionary = {}     ## Vector2i -> Array[Vector2i]

## Blackout tracking
var _blackout_districts: Array = []
var _cascade_pending: Array = []


func _init() -> void:
	pass


## Initialize from power grid generator data.
func initialize_from_power_grid(power_data: Dictionary) -> void:
	_plants.clear()
	_lines.clear()
	_connections.clear()
	_plant_count = 0
	_line_count = 0

	# Create plants
	for pos in power_data.get("reactors", []):
		_add_plant(pos, PlantType.FUSION_REACTOR, FUSION_OUTPUT)

	for pos in power_data.get("substations", []):
		_add_plant(pos, PlantType.SUBSTATION, SUBSTATION_CAPACITY)

	for pos in power_data.get("solar_panels", []):
		_add_plant(pos, PlantType.SOLAR_PANEL, SOLAR_OUTPUT)

	# Create connections from paths
	for connection in power_data.get("connections", []):
		var from: Vector2i = connection.get("from", Vector2i.ZERO)
		var to: Vector2i = connection.get("to", Vector2i.ZERO)
		_add_connection(from, to)
		_create_line(from, to)


## Add a power plant.
func _add_plant(position: Variant, type: PlantType, output: float) -> void:
	var pos: Vector2i
	if position is Vector2i:
		pos = position
	elif position is Dictionary:
		pos = Vector2i(position.get("x", 0), position.get("y", 0))
	else:
		return

	var plant := PlantData.new()
	plant.position = pos
	plant.type = type
	plant.max_output = output
	plant.current_output = output
	plant.is_active = true

	_plants[pos] = plant
	_plant_count += 1


## Add connection between two positions.
func _add_connection(from: Vector2i, to: Vector2i) -> void:
	if not _connections.has(from):
		_connections[from] = []
	if to not in _connections[from]:
		_connections[from].append(to)

	if not _connections.has(to):
		_connections[to] = []
	if from not in _connections[to]:
		_connections[to].append(from)


## Create power line between positions.
func _create_line(from: Vector2i, to: Vector2i) -> void:
	var line := LineData.new()
	line.id = _line_count
	line.from_pos = from
	line.to_pos = to
	line.hp = LINE_HP
	line.max_hp = LINE_HP
	line.state = LineState.INTACT

	_lines[_line_count] = line
	_line_count += 1


## Damage power line at position.
func damage_line(position: Vector3, damage: float, radius: float = 5.0) -> int:
	var damaged_count := 0
	var grid_pos := Vector2i(int(position.x / 32), int(position.z / 32))

	for line_id in _lines:
		var line: LineData = _lines[line_id]
		if line.state == LineState.DESTROYED:
			continue

		# Check if line segment is near damage position
		if _is_line_near_position(line, grid_pos, radius / 32):
			line.hp -= damage
			damaged_count += 1

			if line.hp <= 0:
				_destroy_line(line)

	return damaged_count


## Check if line is near position.
func _is_line_near_position(line: LineData, pos: Vector2i, radius: float) -> bool:
	# Simple distance check to line segment
	var line_vec := Vector2(line.to_pos - line.from_pos)
	var pos_vec := Vector2(pos - line.from_pos)

	var line_len := line_vec.length()
	if line_len < 0.001:
		return Vector2(pos - line.from_pos).length() <= radius

	var t := clampf(pos_vec.dot(line_vec) / (line_len * line_len), 0.0, 1.0)
	var closest := Vector2(line.from_pos) + line_vec * t
	var distance := (Vector2(pos) - closest).length()

	return distance <= radius


## Destroy a power line.
func _destroy_line(line: LineData) -> void:
	line.state = LineState.DESTROYED
	line.hp = 0

	# Remove from connection graph
	if _connections.has(line.from_pos):
		_connections[line.from_pos].erase(line.to_pos)
	if _connections.has(line.to_pos):
		_connections[line.to_pos].erase(line.from_pos)

	power_line_destroyed.emit(line.from_pos, line.to_pos)

	# Check for cascade failures
	_check_cascade_failure(line.from_pos)
	_check_cascade_failure(line.to_pos)


## Check for cascade failures from position.
func _check_cascade_failure(origin: Vector2i) -> void:
	# Find disconnected plants
	var connected := _get_connected_plants(origin)
	var disconnected := []

	for pos in _plants:
		if pos not in connected and pos != origin:
			var plant: PlantData = _plants[pos]
			if plant.is_active:
				disconnected.append(pos)

	if not disconnected.is_empty():
		_cascade_pending.append_array(disconnected)
		cascade_failure.emit(origin, disconnected.size())


## Get all plants connected to origin.
func _get_connected_plants(origin: Vector2i) -> Array:
	var visited := [origin]
	var queue := [origin]

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		if _connections.has(current):
			for neighbor in _connections[current]:
				if neighbor not in visited:
					visited.append(neighbor)
					queue.append(neighbor)

	return visited


## Update power distribution (call each frame).
func update(delta: float) -> void:
	# Process cascade failures
	_process_cascade_pending(delta)

	# Calculate power distribution
	_calculate_power_distribution()


## Process pending cascade failures.
func _process_cascade_pending(delta: float) -> void:
	# Process cascade with delay would use timer
	# For now, process immediately
	for pos in _cascade_pending:
		if _plants.has(pos):
			var plant: PlantData = _plants[pos]
			plant.is_active = false
			plant.current_output = 0

	_cascade_pending.clear()


## Calculate power distribution to districts.
func _calculate_power_distribution() -> void:
	# Calculate total generation
	var total_generation := 0.0

	for pos in _plants:
		var plant: PlantData = _plants[pos]
		if plant.is_active:
			total_generation += plant.current_output

	# Distribute to districts based on consumption
	var total_consumption := 0.0
	for district_id in _district_power:
		total_consumption += _district_power[district_id].get("consumption", 0.0)

	for district_id in _district_power:
		var district_data: Dictionary = _district_power[district_id]
		var consumption: float = district_data.get("consumption", 0.0)

		if total_consumption > 0:
			var ratio := consumption / total_consumption
			var allocated := total_generation * ratio
			district_data["allocated"] = allocated
			district_data["powered"] = allocated >= consumption * 0.5
		else:
			district_data["allocated"] = 0.0
			district_data["powered"] = true


## Register district for power tracking.
func register_district(district_id: int, consumption: float) -> void:
	_district_power[district_id] = {
		"consumption": consumption,
		"allocated": 0.0,
		"powered": true
	}


## Set district consumption.
func set_district_consumption(district_id: int, consumption: float) -> void:
	if _district_power.has(district_id):
		_district_power[district_id]["consumption"] = consumption


## Check if district is powered.
func is_district_powered(district_id: int) -> bool:
	if _district_power.has(district_id):
		return _district_power[district_id].get("powered", false)
	return false


## Get district power allocation.
func get_district_power(district_id: int) -> float:
	if _district_power.has(district_id):
		return _district_power[district_id].get("allocated", 0.0)
	return 0.0


## Get total power generation.
func get_total_generation() -> float:
	var total := 0.0
	for pos in _plants:
		var plant: PlantData = _plants[pos]
		if plant.is_active:
			total += plant.current_output
	return total


## Get total power consumption.
func get_total_consumption() -> float:
	var total := 0.0
	for district_id in _district_power:
		total += _district_power[district_id].get("consumption", 0.0)
	return total


## Get plant at position.
func get_plant_at(position: Vector2i) -> PlantData:
	return _plants.get(position)


## Get all plants.
func get_all_plants() -> Dictionary:
	return _plants


## Get line count.
func get_line_count() -> int:
	return _line_count


## Get active line count.
func get_active_line_count() -> int:
	var count := 0
	for line_id in _lines:
		if _lines[line_id].state != LineState.DESTROYED:
			count += 1
	return count


## Get statistics.
func get_statistics() -> Dictionary:
	var plant_counts := {
		PlantType.FUSION_REACTOR: 0,
		PlantType.SOLAR_PANEL: 0,
		PlantType.SUBSTATION: 0
	}
	var active_plants := 0

	for pos in _plants:
		var plant: PlantData = _plants[pos]
		plant_counts[plant.type] += 1
		if plant.is_active:
			active_plants += 1

	return {
		"total_plants": _plant_count,
		"active_plants": active_plants,
		"plant_counts": plant_counts,
		"total_lines": _line_count,
		"active_lines": get_active_line_count(),
		"total_generation": get_total_generation(),
		"total_consumption": get_total_consumption(),
		"blackout_districts": _blackout_districts.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var plants_data := {}
	for pos in _plants:
		plants_data["%d,%d" % [pos.x, pos.y]] = _plants[pos].to_dict()

	var lines_data := {}
	for line_id in _lines:
		lines_data[str(line_id)] = _lines[line_id].to_dict()

	return {
		"plants": plants_data,
		"lines": lines_data,
		"district_power": _district_power.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_plants.clear()
	_lines.clear()
	_connections.clear()

	var plants_data: Dictionary = data.get("plants", {})
	for key in plants_data:
		var parts: PackedStringArray = key.split(",")
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		var plant := PlantData.new()
		plant.from_dict(plants_data[key])
		_plants[pos] = plant

	var lines_data: Dictionary = data.get("lines", {})
	for key in lines_data:
		var line := LineData.new()
		line.from_dict(lines_data[key])
		_lines[int(key)] = line

		# Rebuild connections
		if line.state != LineState.DESTROYED:
			_add_connection(line.from_pos, line.to_pos)

	_district_power = data.get("district_power", {}).duplicate(true)
	_plant_count = _plants.size()
	_line_count = _lines.size()


## PlantData class.
class PlantData:
	var position: Vector2i = Vector2i.ZERO
	var type: PlantType = PlantType.SOLAR_PANEL
	var max_output: float = 0.0
	var current_output: float = 0.0
	var is_active: bool = true

	func to_dict() -> Dictionary:
		return {
			"position": {"x": position.x, "y": position.y},
			"type": type,
			"max_output": max_output,
			"current_output": current_output,
			"is_active": is_active
		}

	func from_dict(data: Dictionary) -> void:
		var pos: Dictionary = data.get("position", {})
		position = Vector2i(pos.get("x", 0), pos.get("y", 0))
		type = data.get("type", PlantType.SOLAR_PANEL)
		max_output = data.get("max_output", 0.0)
		current_output = data.get("current_output", 0.0)
		is_active = data.get("is_active", true)


## LineData class.
class LineData:
	var id: int = 0
	var from_pos: Vector2i = Vector2i.ZERO
	var to_pos: Vector2i = Vector2i.ZERO
	var hp: float = 100.0
	var max_hp: float = 100.0
	var state: LineState = LineState.INTACT

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"from_pos": {"x": from_pos.x, "y": from_pos.y},
			"to_pos": {"x": to_pos.x, "y": to_pos.y},
			"hp": hp,
			"max_hp": max_hp,
			"state": state
		}

	func from_dict(data: Dictionary) -> void:
		id = data.get("id", 0)
		var fp: Dictionary = data.get("from_pos", {})
		from_pos = Vector2i(fp.get("x", 0), fp.get("y", 0))
		var tp: Dictionary = data.get("to_pos", {})
		to_pos = Vector2i(tp.get("x", 0), tp.get("y", 0))
		hp = data.get("hp", 100.0)
		max_hp = data.get("max_hp", 100.0)
		state = data.get("state", LineState.INTACT)
