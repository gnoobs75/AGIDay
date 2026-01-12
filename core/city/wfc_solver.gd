class_name WFCSolver
extends RefCounted
## WFCSolver implements Wave Function Collapse for procedural generation.
## Uses constraint propagation for efficient tile placement.

signal cell_collapsed(x: int, y: int, tile_id: String)
signal generation_progress(progress: float)
signal generation_complete(success: bool)

## Solver states
enum State {
	IDLE = 0,
	SOLVING = 1,
	COMPLETE = 2,
	FAILED = 3
}

## Grid width
var width: int = 0

## Grid height
var height: int = 0

## Tileset reference
var tileset: WFCTileset = null

## Random number generator
var _rng: RandomNumberGenerator = null

## Current state
var state: int = State.IDLE

## Grid of possible tiles (x,y -> Array of tile_ids)
var _possibilities: Array = []

## Collapsed grid (x,y -> tile_id or "")
var _collapsed: Array = []

## Cells remaining to collapse
var _remaining: int = 0

## Maximum iterations to prevent infinite loops
var _max_iterations: int = 100000


func _init() -> void:
	_rng = RandomNumberGenerator.new()


## Initialize solver with grid size.
func initialize(p_width: int, p_height: int, p_tileset: WFCTileset, seed: int = 0) -> void:
	width = p_width
	height = p_height
	tileset = p_tileset

	if seed != 0:
		_rng.seed = seed
	else:
		_rng.randomize()

	_reset_grid()


## Reset grid to initial state.
func _reset_grid() -> void:
	_possibilities.clear()
	_collapsed.clear()
	_remaining = width * height

	var all_tiles := tileset.get_tile_ids()

	for y in height:
		var poss_row: Array = []
		var coll_row: Array = []
		for x in width:
			poss_row.append(all_tiles.duplicate())
			coll_row.append("")
		_possibilities.append(poss_row)
		_collapsed.append(coll_row)

	state = State.IDLE


## Run solver to completion.
func solve() -> bool:
	if tileset == null or width <= 0 or height <= 0:
		state = State.FAILED
		generation_complete.emit(false)
		return false

	state = State.SOLVING
	var iterations := 0

	while _remaining > 0 and iterations < _max_iterations:
		# Find cell with minimum entropy
		var cell := _find_min_entropy_cell()
		if cell.x < 0:
			# No valid cell found - contradiction
			state = State.FAILED
			generation_complete.emit(false)
			return false

		# Collapse cell
		if not _collapse_cell(cell.x, cell.y):
			state = State.FAILED
			generation_complete.emit(false)
			return false

		# Propagate constraints
		if not _propagate(cell.x, cell.y):
			state = State.FAILED
			generation_complete.emit(false)
			return false

		iterations += 1

		# Report progress periodically
		if iterations % 100 == 0:
			var progress := 1.0 - (float(_remaining) / float(width * height))
			generation_progress.emit(progress)

	if _remaining <= 0:
		state = State.COMPLETE
		generation_complete.emit(true)
		return true
	else:
		state = State.FAILED
		generation_complete.emit(false)
		return false


## Solve incrementally (one step at a time).
func solve_step() -> bool:
	if state == State.COMPLETE or state == State.FAILED:
		return false

	if _remaining <= 0:
		state = State.COMPLETE
		return false

	state = State.SOLVING

	var cell := _find_min_entropy_cell()
	if cell.x < 0:
		state = State.FAILED
		return false

	if not _collapse_cell(cell.x, cell.y):
		state = State.FAILED
		return false

	if not _propagate(cell.x, cell.y):
		state = State.FAILED
		return false

	if _remaining <= 0:
		state = State.COMPLETE
		generation_complete.emit(true)

	return true


## Find cell with minimum entropy (fewest possibilities).
func _find_min_entropy_cell() -> Vector2i:
	var min_entropy := 999999
	var candidates: Array[Vector2i] = []

	for y in height:
		for x in width:
			if _collapsed[y][x] != "":
				continue

			var entropy: int = _possibilities[y][x].size()
			if entropy <= 0:
				# Contradiction - no valid tiles
				return Vector2i(-1, -1)

			if entropy < min_entropy:
				min_entropy = entropy
				candidates.clear()
				candidates.append(Vector2i(x, y))
			elif entropy == min_entropy:
				candidates.append(Vector2i(x, y))

	if candidates.is_empty():
		return Vector2i(-1, -1)

	# Random selection among equal entropy cells
	return candidates[_rng.randi() % candidates.size()]


## Collapse a cell to a single tile.
func _collapse_cell(x: int, y: int) -> bool:
	var possible: Array = _possibilities[y][x]
	if possible.is_empty():
		return false

	# Weighted random selection
	var tile_id := _weighted_select(possible)
	if tile_id.is_empty():
		return false

	_collapsed[y][x] = tile_id
	_possibilities[y][x] = [tile_id]
	_remaining -= 1

	cell_collapsed.emit(x, y, tile_id)
	return true


## Weighted random selection from possible tiles.
func _weighted_select(possible: Array) -> String:
	if possible.is_empty():
		return ""

	var total_weight := 0.0
	for tile_id in possible:
		var tile := tileset.get_tile(tile_id)
		if tile != null:
			total_weight += tile.weight

	if total_weight <= 0:
		return possible[_rng.randi() % possible.size()]

	var roll := _rng.randf() * total_weight
	var cumulative := 0.0

	for tile_id in possible:
		var tile := tileset.get_tile(tile_id)
		if tile != null:
			cumulative += tile.weight
			if roll <= cumulative:
				return tile_id

	return possible[possible.size() - 1]


## Propagate constraints from a collapsed cell.
func _propagate(start_x: int, start_y: int) -> bool:
	var stack: Array[Vector2i] = [Vector2i(start_x, start_y)]

	while not stack.is_empty():
		var pos := stack.pop_back()
		var x := pos.x
		var y := pos.y

		# Check all neighbors
		var neighbors := [
			{"dx": 0, "dy": -1, "dir": WFCTile.Direction.NORTH},
			{"dx": 1, "dy": 0, "dir": WFCTile.Direction.EAST},
			{"dx": 0, "dy": 1, "dir": WFCTile.Direction.SOUTH},
			{"dx": -1, "dy": 0, "dir": WFCTile.Direction.WEST}
		]

		for neighbor in neighbors:
			var nx: int = x + neighbor["dx"]
			var ny: int = y + neighbor["dy"]

			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				continue

			if _collapsed[ny][nx] != "":
				continue

			var changed := _constrain_cell(nx, ny, x, y, neighbor["dir"])
			if changed < 0:
				# Contradiction
				return false
			elif changed > 0:
				stack.append(Vector2i(nx, ny))

	return true


## Constrain cell based on neighbor.
## Returns: -1 = contradiction, 0 = no change, 1 = reduced
func _constrain_cell(x: int, y: int, from_x: int, from_y: int, direction: int) -> int:
	var possible: Array = _possibilities[y][x]
	var from_possible: Array = _possibilities[from_y][from_x]

	if possible.is_empty() or from_possible.is_empty():
		return -1

	# Get valid sockets from source cell
	var valid_sockets: Array[String] = []
	for tile_id in from_possible:
		var tile := tileset.get_tile(tile_id)
		if tile != null:
			var socket := tile.get_socket(direction)
			if not socket in valid_sockets:
				valid_sockets.append(socket)

	# Filter possibilities based on valid sockets
	var opposite := WFCTile.get_opposite_direction(direction)
	var new_possible: Array = []

	for tile_id in possible:
		var tile := tileset.get_tile(tile_id)
		if tile != null:
			var socket := tile.get_socket(opposite)
			if socket in valid_sockets:
				new_possible.append(tile_id)

	if new_possible.is_empty():
		return -1

	if new_possible.size() == possible.size():
		return 0

	_possibilities[y][x] = new_possible
	return 1


## Get collapsed tile at position.
func get_tile_at(x: int, y: int) -> String:
	if x < 0 or x >= width or y < 0 or y >= height:
		return ""
	return _collapsed[y][x]


## Get tile object at position.
func get_tile_object_at(x: int, y: int) -> WFCTile:
	var tile_id := get_tile_at(x, y)
	if tile_id.is_empty():
		return null
	return tileset.get_tile(tile_id)


## Get possibilities at position.
func get_possibilities_at(x: int, y: int) -> Array:
	if x < 0 or x >= width or y < 0 or y >= height:
		return []
	return _possibilities[y][x].duplicate()


## Check if solving is complete.
func is_complete() -> bool:
	return state == State.COMPLETE


## Check if solving failed.
func is_failed() -> bool:
	return state == State.FAILED


## Get progress (0.0 to 1.0).
func get_progress() -> float:
	var total := width * height
	if total <= 0:
		return 1.0
	return 1.0 - (float(_remaining) / float(total))


## Get entire collapsed grid.
func get_grid() -> Array:
	return _collapsed.duplicate(true)


## Pre-collapse specific cell (for seeding).
func pre_collapse(x: int, y: int, tile_id: String) -> bool:
	if x < 0 or x >= width or y < 0 or y >= height:
		return false

	var tile := tileset.get_tile(tile_id)
	if tile == null:
		return false

	if _collapsed[y][x] != "":
		return false

	_collapsed[y][x] = tile_id
	_possibilities[y][x] = [tile_id]
	_remaining -= 1

	# Propagate constraints
	return _propagate(x, y)


## Serialize current state.
func to_dict() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"state": state,
		"remaining": _remaining,
		"collapsed": _collapsed.duplicate(true),
		"rng_seed": _rng.seed
	}


## Deserialize state.
func from_dict(data: Dictionary, p_tileset: WFCTileset) -> void:
	width = data.get("width", 0)
	height = data.get("height", 0)
	state = data.get("state", State.IDLE)
	_remaining = data.get("remaining", 0)
	_collapsed = data.get("collapsed", []).duplicate(true)
	_rng.seed = data.get("rng_seed", 0)
	tileset = p_tileset

	# Rebuild possibilities from collapsed state
	_possibilities.clear()
	var all_tiles := tileset.get_tile_ids()

	for y in height:
		var poss_row: Array = []
		for x in width:
			if _collapsed[y][x] != "":
				poss_row.append([_collapsed[y][x]])
			else:
				poss_row.append(all_tiles.duplicate())
		_possibilities.append(poss_row)
