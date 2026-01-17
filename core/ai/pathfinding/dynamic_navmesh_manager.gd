class_name DynamicNavMeshManager
extends Node3D
## DynamicNavMeshManager handles real-time navigation mesh updates when voxel terrain changes.
## Uses NavigationServer3D for efficient pathfinding with dynamic obstacle support.

signal navmesh_rebuilt(region_id: int)
signal navigation_ready()

## Navigation map RID
var _nav_map: RID = RID()

## Navigation regions by chunk coordinate
var _nav_regions: Dictionary = {}  ## Vector2i -> RID

## Pending region updates (batched for performance)
var _pending_updates: Array[Vector2i] = []

## Update timer for batching
var _update_timer: float = 0.0
const UPDATE_BATCH_INTERVAL := 0.2  ## Batch updates every 200ms
const MAX_UPDATES_PER_FRAME := 4    ## Limit region rebuilds per frame

## Region configuration
const REGION_SIZE := 32.0           ## World units per navigation region
const CELL_SIZE := 0.5              ## Navigation cell size
const CELL_HEIGHT := 0.25           ## Navigation cell height
const AGENT_HEIGHT := 2.0           ## Default agent height
const AGENT_RADIUS := 0.5           ## Default agent radius
const AGENT_MAX_CLIMB := 0.5        ## Max step height
const AGENT_MAX_SLOPE := 45.0       ## Max walkable slope in degrees

## Voxel system reference
var _voxel_system = null

## VoxelPathfindingBridge reference
var _pathfinding_bridge: VoxelPathfindingBridge = null

## Blocked cells from voxel system
var _blocked_cells: Dictionary = {}  ## Vector2i -> true

## World bounds
var _world_min := Vector3.ZERO
var _world_max := Vector3(512, 10, 512)

## Is system initialized
var _initialized := false


func _ready() -> void:
	_initialize_navigation()


func _process(delta: float) -> void:
	if not _initialized:
		return

	# Process batched updates
	_update_timer += delta
	if _update_timer >= UPDATE_BATCH_INTERVAL:
		_update_timer = 0.0
		_process_pending_updates()


## Initialize the navigation system.
func _initialize_navigation() -> void:
	# Create navigation map
	_nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_nav_map, true)
	NavigationServer3D.map_set_cell_size(_nav_map, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(_nav_map, CELL_HEIGHT)
	NavigationServer3D.map_set_edge_connection_margin(_nav_map, 0.5)
	NavigationServer3D.map_set_link_connection_radius(_nav_map, 1.0)

	_initialized = true
	print("[NavMesh] Navigation system initialized - cell size: %.2f, region size: %.1f" % [CELL_SIZE, REGION_SIZE])


## Connect to voxel system for terrain changes.
func connect_to_voxel_system(voxel_system) -> void:
	_voxel_system = voxel_system

	# Connect to pathfinding update signal
	if voxel_system.has_signal("pathfinding_update_needed"):
		voxel_system.pathfinding_update_needed.connect(_on_pathfinding_update_needed)

	print("[NavMesh] Connected to voxel system")


## Connect to VoxelPathfindingBridge for batched updates.
func connect_to_pathfinding_bridge(bridge: VoxelPathfindingBridge) -> void:
	_pathfinding_bridge = bridge
	bridge.navmesh_update_requested.connect(_on_navmesh_update_requested)
	bridge.blocked_cells_changed.connect(_on_blocked_cells_changed)
	print("[NavMesh] Connected to pathfinding bridge")


## Initialize navigation regions for world area.
func initialize_world_regions(world_size: Vector3 = Vector3(512, 10, 512)) -> void:
	_world_max = world_size

	var regions_x := int(ceil(world_size.x / REGION_SIZE))
	var regions_z := int(ceil(world_size.z / REGION_SIZE))

	print("[NavMesh] Creating %d x %d navigation regions..." % [regions_x, regions_z])

	for z in range(regions_z):
		for x in range(regions_x):
			var region_coord := Vector2i(x, z)
			_create_navigation_region(region_coord)

	# Build initial navmesh for all regions
	call_deferred("_build_all_regions")


## Create a navigation region at chunk coordinate.
func _create_navigation_region(coord: Vector2i) -> RID:
	if _nav_regions.has(coord):
		return _nav_regions[coord]

	var region_rid := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region_rid, _nav_map)
	NavigationServer3D.region_set_navigation_layers(region_rid, 1)

	# Set region transform
	var world_pos := Vector3(coord.x * REGION_SIZE, 0, coord.y * REGION_SIZE)
	NavigationServer3D.region_set_transform(region_rid, Transform3D(Basis.IDENTITY, world_pos))

	_nav_regions[coord] = region_rid
	return region_rid


## Build initial navmesh for all regions.
func _build_all_regions() -> void:
	var total := _nav_regions.size()
	var built := 0

	for coord in _nav_regions:
		_rebuild_region_navmesh(coord)
		built += 1

		# Yield periodically to prevent freezing
		if built % 16 == 0:
			await get_tree().process_frame

	print("[NavMesh] Built %d navigation regions" % total)
	navigation_ready.emit()


## Rebuild navmesh for a specific region.
func _rebuild_region_navmesh(coord: Vector2i) -> void:
	if not _nav_regions.has(coord):
		_create_navigation_region(coord)

	var region_rid: RID = _nav_regions[coord]
	var navmesh := _generate_navmesh_for_region(coord)

	NavigationServer3D.region_set_navigation_mesh(region_rid, navmesh)


## Generate NavigationMesh for a region based on voxel terrain.
func _generate_navmesh_for_region(coord: Vector2i) -> NavigationMesh:
	var navmesh := NavigationMesh.new()

	# Configure navmesh parameters
	navmesh.cell_size = CELL_SIZE
	navmesh.cell_height = CELL_HEIGHT
	navmesh.agent_height = AGENT_HEIGHT
	navmesh.agent_radius = AGENT_RADIUS
	navmesh.agent_max_climb = AGENT_MAX_CLIMB
	navmesh.agent_max_slope = AGENT_MAX_SLOPE

	# Calculate region bounds
	var min_x := coord.x * REGION_SIZE
	var min_z := coord.y * REGION_SIZE
	var max_x := min_x + REGION_SIZE
	var max_z := min_z + REGION_SIZE

	# Generate vertices and polygons based on traversable terrain
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []

	# Grid-based navmesh generation
	var grid_step := CELL_SIZE * 2  # Sample every 2 cells
	var vertex_grid: Dictionary = {}  ## Vector2i -> vertex_index

	# First pass: create vertices for traversable cells
	for z in range(int(min_z), int(max_z), int(grid_step)):
		for x in range(int(min_x), int(max_x), int(grid_step)):
			var cell := Vector2i(x, z)

			# Check if cell is traversable
			if _is_cell_traversable(Vector3i(x, 0, z)):
				var idx := vertices.size()
				vertices.append(Vector3(x - min_x, 0, z - min_z))
				vertex_grid[cell] = idx

	# Second pass: create polygons (triangles) connecting adjacent traversable cells
	for z in range(int(min_z), int(max_z - grid_step), int(grid_step)):
		for x in range(int(min_x), int(max_x - grid_step), int(grid_step)):
			var c0 := Vector2i(x, z)
			var c1 := Vector2i(x + int(grid_step), z)
			var c2 := Vector2i(x + int(grid_step), z + int(grid_step))
			var c3 := Vector2i(x, z + int(grid_step))

			# Check if we have a quad of traversable cells
			if vertex_grid.has(c0) and vertex_grid.has(c1) and vertex_grid.has(c2) and vertex_grid.has(c3):
				# Create two triangles for the quad
				var tri1 := PackedInt32Array([vertex_grid[c0], vertex_grid[c1], vertex_grid[c2]])
				var tri2 := PackedInt32Array([vertex_grid[c0], vertex_grid[c2], vertex_grid[c3]])
				polygons.append(tri1)
				polygons.append(tri2)

	# Set navmesh data
	if vertices.size() > 0:
		navmesh.vertices = vertices
		for poly in polygons:
			navmesh.add_polygon(poly)

	return navmesh


## Check if a voxel cell is traversable.
func _is_cell_traversable(pos: Vector3i) -> bool:
	# Check blocked cells cache first
	var cell_key := Vector2i(pos.x, pos.z)
	if _blocked_cells.has(cell_key):
		return false

	# Check voxel system if available
	if _voxel_system != null and _voxel_system.is_valid_position(pos):
		return _voxel_system.is_traversable(pos)

	# Default to traversable for areas outside voxel terrain
	return true


## Handle voxel changes from voxel system.
func _on_pathfinding_update_needed(positions: Array) -> void:
	for pos in positions:
		if pos is Vector3i:
			var region_coord := _world_to_region(Vector3(pos.x, pos.y, pos.z))
			if region_coord not in _pending_updates:
				_pending_updates.append(region_coord)


## Handle navmesh update request from bridge.
func _on_navmesh_update_requested(aabb: AABB) -> void:
	# Convert AABB to affected regions
	var min_region := _world_to_region(aabb.position)
	var max_region := _world_to_region(aabb.position + aabb.size)

	for z in range(min_region.y, max_region.y + 1):
		for x in range(min_region.x, max_region.x + 1):
			var coord := Vector2i(x, z)
			if coord not in _pending_updates:
				_pending_updates.append(coord)


## Handle blocked cells update from bridge.
func _on_blocked_cells_changed(positions: Array[Vector3i]) -> void:
	_blocked_cells.clear()
	for pos in positions:
		_blocked_cells[Vector2i(pos.x, pos.z)] = true


## Convert world position to region coordinate.
func _world_to_region(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / REGION_SIZE)),
		int(floor(world_pos.z / REGION_SIZE))
	)


## Process pending region updates.
func _process_pending_updates() -> void:
	if _pending_updates.is_empty():
		return

	var updates_this_frame := 0
	while not _pending_updates.is_empty() and updates_this_frame < MAX_UPDATES_PER_FRAME:
		var coord: Vector2i = _pending_updates.pop_front()

		if _nav_regions.has(coord):
			_rebuild_region_navmesh(coord)
			navmesh_rebuilt.emit(coord.x * 1000 + coord.y)  # Simple region ID
			updates_this_frame += 1


## Get path from start to end position.
func find_path(start: Vector3, end: Vector3) -> PackedVector3Array:
	if not _initialized or not _nav_map.is_valid():
		return PackedVector3Array()

	return NavigationServer3D.map_get_path(
		_nav_map,
		start,
		end,
		true,  # Optimize path
		1      # Navigation layers
	)


## Get closest point on navmesh.
func get_closest_point(pos: Vector3) -> Vector3:
	if not _initialized or not _nav_map.is_valid():
		return pos

	return NavigationServer3D.map_get_closest_point(_nav_map, pos)


## Check if point is on navmesh.
func is_point_on_navmesh(pos: Vector3) -> bool:
	if not _initialized or not _nav_map.is_valid():
		return false

	var closest := NavigationServer3D.map_get_closest_point(_nav_map, pos)
	return pos.distance_to(closest) < 1.0


## Get navigation map RID for NavigationAgent3D.
func get_navigation_map() -> RID:
	return _nav_map


## Mark region as needing update.
func mark_region_dirty(world_pos: Vector3) -> void:
	var coord := _world_to_region(world_pos)
	if coord not in _pending_updates:
		_pending_updates.append(coord)


## Force rebuild all regions.
func rebuild_all() -> void:
	for coord in _nav_regions:
		if coord not in _pending_updates:
			_pending_updates.append(coord)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"initialized": _initialized,
		"total_regions": _nav_regions.size(),
		"pending_updates": _pending_updates.size(),
		"blocked_cells": _blocked_cells.size(),
		"nav_map_valid": _nav_map.is_valid()
	}


## Cleanup.
func cleanup() -> void:
	# Free all navigation regions
	for coord in _nav_regions:
		var rid: RID = _nav_regions[coord]
		if rid.is_valid():
			NavigationServer3D.free_rid(rid)
	_nav_regions.clear()

	# Free navigation map
	if _nav_map.is_valid():
		NavigationServer3D.free_rid(_nav_map)

	_initialized = false
	print("[NavMesh] Navigation system cleaned up")
