class_name GenerationUtils
extends RefCounted
## GenerationUtils provides shared utility functions for procedural generation.
## Includes noise, random selection, and grid utilities.


## Weighted random selection from array.
static func weighted_select(items: Array, weights: Array, rng: RandomNumberGenerator) -> Variant:
	if items.is_empty() or weights.is_empty():
		return null

	var total := 0.0
	for w in weights:
		total += float(w)

	if total <= 0:
		return items[rng.randi() % items.size()]

	var roll := rng.randf() * total
	var cumulative := 0.0

	for i in items.size():
		if i < weights.size():
			cumulative += float(weights[i])
			if roll <= cumulative:
				return items[i]

	return items[items.size() - 1]


## Shuffle array in place using Fisher-Yates.
static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp


## Generate simplex-like noise value.
static func noise_2d(x: float, y: float, seed: int) -> float:
	# Simple hash-based noise
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - ix
	var fy := y - iy

	var v00 := _hash_2d(ix, iy, seed)
	var v10 := _hash_2d(ix + 1, iy, seed)
	var v01 := _hash_2d(ix, iy + 1, seed)
	var v11 := _hash_2d(ix + 1, iy + 1, seed)

	# Bilinear interpolation
	var v0 := lerpf(v00, v10, fx)
	var v1 := lerpf(v01, v11, fx)
	return lerpf(v0, v1, fy)


## Hash function for 2D coordinates.
static func _hash_2d(x: int, y: int, seed: int) -> float:
	var n := x + y * 57 + seed * 131
	n = (n << 13) ^ n
	n = n * (n * n * 15731 + 789221) + 1376312589
	return (1.0 - float(n & 0x7fffffff) / 1073741824.0) * 0.5 + 0.5


## Generate fractal noise (multiple octaves).
static func fractal_noise_2d(x: float, y: float, seed: int, octaves: int = 4, persistence: float = 0.5) -> float:
	var total := 0.0
	var frequency := 1.0
	var amplitude := 1.0
	var max_value := 0.0

	for i in octaves:
		total += noise_2d(x * frequency, y * frequency, seed + i) * amplitude
		max_value += amplitude
		amplitude *= persistence
		frequency *= 2.0

	return total / max_value


## Check if point is within bounds.
static func in_bounds(x: int, y: int, width: int, height: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


## Get neighbors in cardinal directions.
static func get_cardinal_neighbors(x: int, y: int) -> Array[Vector2i]:
	return [
		Vector2i(x, y - 1),  # North
		Vector2i(x + 1, y),  # East
		Vector2i(x, y + 1),  # South
		Vector2i(x - 1, y)   # West
	]


## Get all 8 neighbors.
static func get_all_neighbors(x: int, y: int) -> Array[Vector2i]:
	return [
		Vector2i(x, y - 1),      # N
		Vector2i(x + 1, y - 1),  # NE
		Vector2i(x + 1, y),      # E
		Vector2i(x + 1, y + 1),  # SE
		Vector2i(x, y + 1),      # S
		Vector2i(x - 1, y + 1),  # SW
		Vector2i(x - 1, y),      # W
		Vector2i(x - 1, y - 1)   # NW
	]


## Manhattan distance.
static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Euclidean distance squared.
static func distance_squared(a: Vector2i, b: Vector2i) -> int:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy


## Euclidean distance.
static func distance(a: Vector2i, b: Vector2i) -> float:
	return sqrt(float(distance_squared(a, b)))


## Linear interpolation for integers.
static func lerp_int(a: int, b: int, t: float) -> int:
	return int(a + (b - a) * t)


## Clamp integer to range.
static func clamp_int(value: int, min_val: int, max_val: int) -> int:
	if value < min_val:
		return min_val
	if value > max_val:
		return max_val
	return value


## Remap value from one range to another.
static func remap(value: float, from_min: float, from_max: float, to_min: float, to_max: float) -> float:
	if from_max - from_min == 0:
		return to_min
	return to_min + (value - from_min) * (to_max - to_min) / (from_max - from_min)


## Flood fill algorithm.
static func flood_fill(
	start: Vector2i,
	width: int,
	height: int,
	check_func: Callable
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited: Dictionary = {}
	var stack: Array[Vector2i] = [start]

	while not stack.is_empty():
		var pos := stack.pop_back()
		var key := str(pos.x) + "," + str(pos.y)

		if visited.has(key):
			continue

		if not in_bounds(pos.x, pos.y, width, height):
			continue

		if not check_func.call(pos.x, pos.y):
			continue

		visited[key] = true
		result.append(pos)

		# Add neighbors
		for neighbor in get_cardinal_neighbors(pos.x, pos.y):
			stack.append(neighbor)

	return result


## Find bounding box of points.
static func get_bounding_box(points: Array[Vector2i]) -> Rect2i:
	if points.is_empty():
		return Rect2i()

	var min_x := points[0].x
	var min_y := points[0].y
	var max_x := points[0].x
	var max_y := points[0].y

	for point in points:
		min_x = mini(min_x, point.x)
		min_y = mini(min_y, point.y)
		max_x = maxi(max_x, point.x)
		max_y = maxi(max_y, point.y)

	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Generate Poisson disk sampling points.
static func poisson_disk_sample(
	width: int,
	height: int,
	min_distance: float,
	rng: RandomNumberGenerator,
	max_attempts: int = 30
) -> Array[Vector2i]:
	var cell_size := min_distance / sqrt(2.0)
	var grid_width := int(ceil(width / cell_size))
	var grid_height := int(ceil(height / cell_size))

	# Grid to track occupied cells
	var grid: Array = []
	for y in grid_height:
		var row: Array = []
		for x in grid_width:
			row.append(-1)
		grid.append(row)

	var points: Array[Vector2i] = []
	var active: Array[int] = []

	# Start with random point
	var start := Vector2i(rng.randi() % width, rng.randi() % height)
	points.append(start)
	active.append(0)

	var gx := int(start.x / cell_size)
	var gy := int(start.y / cell_size)
	grid[gy][gx] = 0

	while not active.is_empty():
		var idx := rng.randi() % active.size()
		var point := points[active[idx]]

		var found := false
		for attempt in max_attempts:
			var angle := rng.randf() * TAU
			var dist := min_distance + rng.randf() * min_distance
			var new_x := int(point.x + cos(angle) * dist)
			var new_y := int(point.y + sin(angle) * dist)

			if new_x < 0 or new_x >= width or new_y < 0 or new_y >= height:
				continue

			var new_gx := int(new_x / cell_size)
			var new_gy := int(new_y / cell_size)

			# Check nearby cells
			var valid := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var cx := new_gx + dx
					var cy := new_gy + dy
					if cx >= 0 and cx < grid_width and cy >= 0 and cy < grid_height:
						var other_idx: int = grid[cy][cx]
						if other_idx >= 0:
							var other := points[other_idx]
							if distance_squared(Vector2i(new_x, new_y), other) < min_distance * min_distance:
								valid = false
								break
					if not valid:
						break

			if valid:
				var new_idx := points.size()
				points.append(Vector2i(new_x, new_y))
				active.append(new_idx)
				grid[new_gy][new_gx] = new_idx
				found = true
				break

		if not found:
			active.remove_at(idx)

	return points


## Bresenham line algorithm.
static func bresenham_line(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []

	var dx := absi(end.x - start.x)
	var dy := absi(end.y - start.y)
	var sx := 1 if start.x < end.x else -1
	var sy := 1 if start.y < end.y else -1
	var err := dx - dy

	var x := start.x
	var y := start.y

	while true:
		points.append(Vector2i(x, y))

		if x == end.x and y == end.y:
			break

		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

	return points


## Generate random point in rect.
static func random_point_in_rect(rect: Rect2i, rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(
		rect.position.x + rng.randi() % rect.size.x,
		rect.position.y + rng.randi() % rect.size.y
	)
