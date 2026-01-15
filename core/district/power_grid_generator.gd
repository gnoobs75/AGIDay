class_name PowerGridGenerator
extends RefCounted
## PowerGridGenerator creates the power infrastructure for the city.
## Places fusion reactors at corners, connects them via substations, and adds solar panels.

signal generation_started()
signal reactor_placed(position: Vector2i)
signal substation_placed(position: Vector2i)
signal solar_placed(position: Vector2i)
signal connection_created(from: Vector2i, to: Vector2i)
signal generation_completed()

## Grid dimensions (matches ZoneGenerator)
const ZONE_GRID_SIZE := 16
const VOXELS_PER_ZONE := 32

## Power structure types
enum PowerType {
	NONE,
	FUSION_REACTOR,   ## Corner power plants
	SUBSTATION,       ## Mid-connection distribution
	SOLAR_PANEL,      ## Industrial zone solar
	POWER_LINE        ## Connection paths
}

## Power structure data
const FUSION_REACTOR_OUTPUT := 1000.0    ## MW
const SUBSTATION_CAPACITY := 500.0       ## MW throughput
const SOLAR_PANEL_OUTPUT := 50.0         ## MW per panel

## Solar panel placement
const SOLAR_PROBABILITY := 0.5
const SOLAR_CLUSTER_SIZE := 3

## RNG
var _rng: RandomNumberGenerator = null

## Generated data
var _power_grid: Array = []           ## 2D array of PowerType
var _power_output: Array = []         ## 2D array of float (power output)
var _connections: Array = []          ## Array of connection data
var _reactor_positions: Array[Vector2i] = []
var _substation_positions: Array[Vector2i] = []
var _solar_positions: Array[Vector2i] = []


func _init() -> void:
	_rng = RandomNumberGenerator.new()


## Generate power grid layout.
func generate_power_grid(zone_grid: Array, seed: int = 0) -> Dictionary:
	_rng.seed = seed if seed != 0 else Time.get_ticks_msec()

	generation_started.emit()

	_initialize_grids()
	_place_fusion_reactors()
	_connect_reactors_steiner()
	_place_substations()
	_place_solar_panels(zone_grid)

	generation_completed.emit()

	return {
		"power_grid": _power_grid,
		"power_output": _power_output,
		"connections": _connections,
		"reactors": _reactor_positions.duplicate(),
		"substations": _substation_positions.duplicate(),
		"solar_panels": _solar_positions.duplicate()
	}


## Initialize empty grids.
func _initialize_grids() -> void:
	_power_grid = []
	_power_output = []
	_connections = []
	_reactor_positions.clear()
	_substation_positions.clear()
	_solar_positions.clear()

	for x in ZONE_GRID_SIZE:
		var power_row := []
		var output_row := []

		for y in ZONE_GRID_SIZE:
			power_row.append(PowerType.NONE)
			output_row.append(0.0)

		_power_grid.append(power_row)
		_power_output.append(output_row)


## Place fusion reactors at four corners.
func _place_fusion_reactors() -> void:
	# Reactor positions match power hub positions from ZoneGenerator
	var corners := [
		Vector2i(1, 1),
		Vector2i(14, 1),
		Vector2i(1, 14),
		Vector2i(14, 14)
	]

	for corner in corners:
		_power_grid[corner.x][corner.y] = PowerType.FUSION_REACTOR
		_power_output[corner.x][corner.y] = FUSION_REACTOR_OUTPUT
		_reactor_positions.append(corner)
		reactor_placed.emit(corner)


## Connect reactors using simplified Steiner tree approach.
## Creates an X pattern through center for efficient coverage.
func _connect_reactors_steiner() -> void:
	# Steiner point at center minimizes total wire length
	var center := Vector2i(ZONE_GRID_SIZE / 2, ZONE_GRID_SIZE / 2)

	# Connect each reactor to center (simplified Steiner tree)
	for reactor_pos in _reactor_positions:
		_create_connection(reactor_pos, center)

	# Mark center as a major substation
	_power_grid[center.x][center.y] = PowerType.SUBSTATION
	_power_output[center.x][center.y] = SUBSTATION_CAPACITY * 2  # Central hub
	_substation_positions.append(center)
	substation_placed.emit(center)


## Create connection path between two points.
func _create_connection(from: Vector2i, to: Vector2i) -> void:
	var connection := {
		"from": from,
		"to": to,
		"path": []
	}

	# Use L-shaped path (horizontal then vertical)
	var current := from
	var path: Array[Vector2i] = [current]

	# Move horizontally first
	var dir_x := 1 if to.x > from.x else -1
	while current.x != to.x:
		current = Vector2i(current.x + dir_x, current.y)
		path.append(current)

		# Mark as power line (unless already something else)
		if _power_grid[current.x][current.y] == PowerType.NONE:
			_power_grid[current.x][current.y] = PowerType.POWER_LINE

	# Move vertically
	var dir_y := 1 if to.y > from.y else -1
	while current.y != to.y:
		current = Vector2i(current.x, current.y + dir_y)
		path.append(current)

		if _power_grid[current.x][current.y] == PowerType.NONE:
			_power_grid[current.x][current.y] = PowerType.POWER_LINE

	connection["path"] = path
	_connections.append(connection)
	connection_created.emit(from, to)


## Place substations at connection midpoints.
func _place_substations() -> void:
	for connection in _connections:
		var path: Array = connection["path"]
		if path.size() < 4:
			continue

		# Place substation at midpoint of each connection
		var mid_idx := path.size() / 2
		var mid_pos: Vector2i = path[mid_idx]

		# Skip if already occupied by reactor or other substation
		if _power_grid[mid_pos.x][mid_pos.y] in [PowerType.FUSION_REACTOR, PowerType.SUBSTATION]:
			continue

		_power_grid[mid_pos.x][mid_pos.y] = PowerType.SUBSTATION
		_power_output[mid_pos.x][mid_pos.y] = SUBSTATION_CAPACITY
		_substation_positions.append(mid_pos)
		substation_placed.emit(mid_pos)


## Place solar panels in industrial zones.
func _place_solar_panels(zone_grid: Array) -> void:
	if zone_grid.is_empty():
		return

	# ZoneGenerator uses ZoneType enum where INDUSTRIAL = 1
	const ZONE_INDUSTRIAL := 1

	for x in ZONE_GRID_SIZE:
		if x >= zone_grid.size():
			continue

		for y in ZONE_GRID_SIZE:
			if y >= zone_grid[x].size():
				continue

			# Check if industrial zone
			if zone_grid[x][y] != ZONE_INDUSTRIAL:
				continue

			# Skip if already has power structure
			if _power_grid[x][y] != PowerType.NONE:
				continue

			# 50% probability for solar panel
			if _rng.randf() < SOLAR_PROBABILITY:
				_power_grid[x][y] = PowerType.SOLAR_PANEL
				_power_output[x][y] = SOLAR_PANEL_OUTPUT
				_solar_positions.append(Vector2i(x, y))
				solar_placed.emit(Vector2i(x, y))


## Get power type at position.
func get_power_at(x: int, y: int) -> PowerType:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return PowerType.NONE
	return _power_grid[x][y]


## Get power output at position.
func get_output_at(x: int, y: int) -> float:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return 0.0
	return _power_output[x][y]


## Get total power generation capacity.
func get_total_capacity() -> float:
	var total := 0.0

	for x in ZONE_GRID_SIZE:
		for y in ZONE_GRID_SIZE:
			total += _power_output[x][y]

	return total


## Get reactor power output.
func get_reactor_output() -> float:
	return _reactor_positions.size() * FUSION_REACTOR_OUTPUT


## Get solar panel output.
func get_solar_output() -> float:
	return _solar_positions.size() * SOLAR_PANEL_OUTPUT


## Check if position is powered (connected to grid).
func is_powered(x: int, y: int) -> bool:
	if x < 0 or x >= ZONE_GRID_SIZE or y < 0 or y >= ZONE_GRID_SIZE:
		return false

	# Direct power sources are always powered
	if _power_grid[x][y] in [PowerType.FUSION_REACTOR, PowerType.SUBSTATION, PowerType.SOLAR_PANEL]:
		return true

	# Check adjacency to power lines or substations
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var nx: int = x + dir.x
		var ny: int = y + dir.y

		if nx < 0 or nx >= ZONE_GRID_SIZE or ny < 0 or ny >= ZONE_GRID_SIZE:
			continue

		if _power_grid[nx][ny] != PowerType.NONE:
			return true

	return false


## Get nearest power source to position.
func get_nearest_power_source(x: int, y: int) -> Vector2i:
	var nearest := Vector2i(-1, -1)
	var nearest_dist := INF

	# Check reactors
	for pos in _reactor_positions:
		var dist := Vector2i(x, y).distance_to(pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = pos

	# Check substations
	for pos in _substation_positions:
		var dist := Vector2i(x, y).distance_to(pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = pos

	return nearest


## Get power grid array.
func get_power_grid() -> Array:
	return _power_grid


## Get connections.
func get_connections() -> Array:
	return _connections


## Get power type name.
static func get_power_name(power_type: PowerType) -> String:
	match power_type:
		PowerType.NONE: return "None"
		PowerType.FUSION_REACTOR: return "Fusion Reactor"
		PowerType.SUBSTATION: return "Substation"
		PowerType.SOLAR_PANEL: return "Solar Panel"
		PowerType.POWER_LINE: return "Power Line"
	return "Unknown"


## Get statistics.
func get_statistics() -> Dictionary:
	var line_count := 0
	for x in ZONE_GRID_SIZE:
		for y in ZONE_GRID_SIZE:
			if _power_grid[x][y] == PowerType.POWER_LINE:
				line_count += 1

	return {
		"grid_size": ZONE_GRID_SIZE,
		"reactor_count": _reactor_positions.size(),
		"substation_count": _substation_positions.size(),
		"solar_count": _solar_positions.size(),
		"power_line_count": line_count,
		"total_capacity_mw": get_total_capacity(),
		"reactor_output_mw": get_reactor_output(),
		"solar_output_mw": get_solar_output()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"power_grid": _power_grid.duplicate(true),
		"power_output": _power_output.duplicate(true),
		"connections": _connections.duplicate(true),
		"reactors": _reactor_positions.duplicate(),
		"substations": _substation_positions.duplicate(),
		"solar_panels": _solar_positions.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_power_grid = data.get("power_grid", []).duplicate(true)
	_power_output = data.get("power_output", []).duplicate(true)
	_connections = data.get("connections", []).duplicate(true)

	_reactor_positions.clear()
	for pos in data.get("reactors", []):
		_reactor_positions.append(pos)

	_substation_positions.clear()
	for pos in data.get("substations", []):
		_substation_positions.append(pos)

	_solar_positions.clear()
	for pos in data.get("solar_panels", []):
		_solar_positions.append(pos)
