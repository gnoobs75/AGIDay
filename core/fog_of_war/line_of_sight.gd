class_name LineOfSight
extends RefCounted
## LineOfSight provides raycasting-based vision calculations.
## Uses Bresenham line algorithm for efficient voxel traversal.

signal los_blocked(from_pos: Vector3, to_pos: Vector3, blocker_pos: Vector3)

## Configuration
const VOXEL_SIZE := 1.0  ## World units per voxel

## Callback for checking if voxel blocks vision
var _is_blocking_voxel: Callable  ## (voxel_x, voxel_y, voxel_z) -> bool


func _init() -> void:
	pass


## Set blocking voxel check callback.
func set_blocking_check(callback: Callable) -> void:
	_is_blocking_voxel = callback


## Check line of sight between two positions.
func check_los(from_pos: Vector3, to_pos: Vector3, can_see_through_buildings: bool = false) -> bool:
	if can_see_through_buildings:
		return true

	if not _is_blocking_voxel.is_valid():
		return true  ## Assume clear if no callback

	# Get voxel coordinates
	var from_voxel := _world_to_voxel(from_pos)
	var to_voxel := _world_to_voxel(to_pos)

	# Use 3D Bresenham
	var blocking := _bresenham_3d(from_voxel, to_voxel)

	return blocking.is_empty()


## Get all visible voxels from position within range.
func get_visible_voxels(from_pos: Vector3, vision_range: float, vision_height: float, can_see_through_buildings: bool = false) -> Array[Vector2i]:
	var visible: Array[Vector2i] = []
	var from_voxel := _world_to_voxel(from_pos)
	var range_voxels := int(ceil(vision_range))
	var effective_pos := Vector3(from_pos.x, from_pos.y + vision_height, from_pos.z)

	# Check all voxels in range
	for dx in range(-range_voxels, range_voxels + 1):
		for dz in range(-range_voxels, range_voxels + 1):
			var dist_sq := dx * dx + dz * dz
			if dist_sq > range_voxels * range_voxels:
				continue

			var target_x := from_voxel.x + dx
			var target_z := from_voxel.z + dz

			# Check LOS
			var target_pos := Vector3(
				float(target_x) * VOXEL_SIZE + VOXEL_SIZE * 0.5,
				from_pos.y,
				float(target_z) * VOXEL_SIZE + VOXEL_SIZE * 0.5
			)

			if check_los(effective_pos, target_pos, can_see_through_buildings):
				visible.append(Vector2i(target_x, target_z))

	return visible


## 3D Bresenham line algorithm - returns blocking voxels.
func _bresenham_3d(from_voxel: Vector3i, to_voxel: Vector3i) -> Array[Vector3i]:
	var blockers: Array[Vector3i] = []

	var dx := absi(to_voxel.x - from_voxel.x)
	var dy := absi(to_voxel.y - from_voxel.y)
	var dz := absi(to_voxel.z - from_voxel.z)

	var sx := 1 if from_voxel.x < to_voxel.x else -1
	var sy := 1 if from_voxel.y < to_voxel.y else -1
	var sz := 1 if from_voxel.z < to_voxel.z else -1

	var x := from_voxel.x
	var y := from_voxel.y
	var z := from_voxel.z

	# Determine dominant axis
	if dx >= dy and dx >= dz:
		# X is dominant
		var err_y := 2 * dy - dx
		var err_z := 2 * dz - dx

		while x != to_voxel.x:
			# Skip start position
			if x != from_voxel.x or y != from_voxel.y or z != from_voxel.z:
				if _is_blocking(x, y, z):
					blockers.append(Vector3i(x, y, z))
					return blockers

			if err_y > 0:
				y += sy
				err_y -= 2 * dx
			if err_z > 0:
				z += sz
				err_z -= 2 * dx

			err_y += 2 * dy
			err_z += 2 * dz
			x += sx

	elif dy >= dx and dy >= dz:
		# Y is dominant
		var err_x := 2 * dx - dy
		var err_z := 2 * dz - dy

		while y != to_voxel.y:
			if x != from_voxel.x or y != from_voxel.y or z != from_voxel.z:
				if _is_blocking(x, y, z):
					blockers.append(Vector3i(x, y, z))
					return blockers

			if err_x > 0:
				x += sx
				err_x -= 2 * dy
			if err_z > 0:
				z += sz
				err_z -= 2 * dy

			err_x += 2 * dx
			err_z += 2 * dz
			y += sy

	else:
		# Z is dominant
		var err_x := 2 * dx - dz
		var err_y := 2 * dy - dz

		while z != to_voxel.z:
			if x != from_voxel.x or y != from_voxel.y or z != from_voxel.z:
				if _is_blocking(x, y, z):
					blockers.append(Vector3i(x, y, z))
					return blockers

			if err_x > 0:
				x += sx
				err_x -= 2 * dz
			if err_y > 0:
				y += sy
				err_y -= 2 * dz

			err_x += 2 * dx
			err_y += 2 * dy
			z += sz

	return blockers


## Check if voxel is blocking.
func _is_blocking(x: int, y: int, z: int) -> bool:
	if not _is_blocking_voxel.is_valid():
		return false
	return _is_blocking_voxel.call(x, y, z)


## Convert world position to voxel coordinates.
func _world_to_voxel(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / VOXEL_SIZE)),
		int(floor(pos.y / VOXEL_SIZE)),
		int(floor(pos.z / VOXEL_SIZE))
	)


## Convert voxel to world position (center of voxel).
func _voxel_to_world(voxel: Vector3i) -> Vector3:
	return Vector3(
		float(voxel.x) * VOXEL_SIZE + VOXEL_SIZE * 0.5,
		float(voxel.y) * VOXEL_SIZE + VOXEL_SIZE * 0.5,
		float(voxel.z) * VOXEL_SIZE + VOXEL_SIZE * 0.5
	)
