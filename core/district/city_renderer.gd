class_name CityRenderer
extends Node3D
## CityRenderer creates visual 3D city from WFC building layout.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D with BoxMesh/CylinderMesh instead of CSG nodes.
## Cached materials are shared across all buildings to reduce allocations.
## Buildings are destructible and drop REE when destroyed.

signal city_rendered(building_count: int)
signal rendering_progress(percent: float)
signal building_destroyed(building_id: int, position: Vector3, ree_amount: float)
signal building_damaged(building_id: int, health_percent: float)

## Building type heights (units)
const BUILDING_HEIGHTS := {
	0: 0.0,    # EMPTY
	1: 4.0,    # SMALL_RESIDENTIAL
	2: 8.0,    # MEDIUM_RESIDENTIAL
	3: 12.0,   # LARGE_RESIDENTIAL
	4: 5.0,    # SMALL_COMMERCIAL
	5: 10.0,   # MEDIUM_COMMERCIAL
	6: 18.0,   # LARGE_COMMERCIAL
	7: 6.0,    # SMALL_INDUSTRIAL
	8: 10.0,   # MEDIUM_INDUSTRIAL
	9: 14.0,   # LARGE_INDUSTRIAL
	10: 30.0,  # SKYSCRAPER
	11: 8.0,   # WAREHOUSE
	12: 12.0,  # FACTORY
	13: 0.5,   # PARK (grass)
	14: 0.1    # ROAD
}

## Building HP based on height (taller = more HP)
const BUILDING_HP_MULTIPLIER := 20.0  # HP = height * multiplier

## REE drop amount based on building type
const BUILDING_REE_DROPS := {
	0: 0.0,    # EMPTY
	1: 5.0,    # SMALL_RESIDENTIAL
	2: 12.0,   # MEDIUM_RESIDENTIAL
	3: 20.0,   # LARGE_RESIDENTIAL
	4: 8.0,    # SMALL_COMMERCIAL
	5: 18.0,   # MEDIUM_COMMERCIAL
	6: 35.0,   # LARGE_COMMERCIAL
	7: 15.0,   # SMALL_INDUSTRIAL
	8: 30.0,   # MEDIUM_INDUSTRIAL
	9: 50.0,   # LARGE_INDUSTRIAL
	10: 100.0, # SKYSCRAPER
	11: 25.0,  # WAREHOUSE
	12: 40.0,  # FACTORY
	13: 2.0,   # PARK
	14: 0.0    # ROAD
}

## Building type sizes (grid cells)
const BUILDING_SIZES := {
	0: Vector2i(1, 1),    # EMPTY
	1: Vector2i(1, 1),    # SMALL_RESIDENTIAL
	2: Vector2i(2, 2),    # MEDIUM_RESIDENTIAL
	3: Vector2i(2, 3),    # LARGE_RESIDENTIAL
	4: Vector2i(1, 1),    # SMALL_COMMERCIAL
	5: Vector2i(2, 2),    # MEDIUM_COMMERCIAL
	6: Vector2i(3, 3),    # LARGE_COMMERCIAL
	7: Vector2i(2, 2),    # SMALL_INDUSTRIAL
	8: Vector2i(3, 3),    # MEDIUM_INDUSTRIAL
	9: Vector2i(4, 4),    # LARGE_INDUSTRIAL
	10: Vector2i(2, 2),   # SKYSCRAPER
	11: Vector2i(4, 3),   # WAREHOUSE
	12: Vector2i(4, 4),   # FACTORY
	13: Vector2i(3, 3),   # PARK
	14: Vector2i(1, 1)    # ROAD
}

## Building type colors
const BUILDING_COLORS := {
	0: Color(0.2, 0.2, 0.2),      # EMPTY - dark gray
	1: Color(0.7, 0.6, 0.5),      # SMALL_RESIDENTIAL - tan
	2: Color(0.75, 0.65, 0.55),   # MEDIUM_RESIDENTIAL - light tan
	3: Color(0.8, 0.7, 0.6),      # LARGE_RESIDENTIAL - beige
	4: Color(0.3, 0.5, 0.7),      # SMALL_COMMERCIAL - blue
	5: Color(0.35, 0.55, 0.75),   # MEDIUM_COMMERCIAL - light blue
	6: Color(0.4, 0.6, 0.8),      # LARGE_COMMERCIAL - sky blue
	7: Color(0.5, 0.4, 0.3),      # SMALL_INDUSTRIAL - brown
	8: Color(0.55, 0.45, 0.35),   # MEDIUM_INDUSTRIAL - rust
	9: Color(0.6, 0.5, 0.4),      # LARGE_INDUSTRIAL - copper
	10: Color(0.6, 0.7, 0.8),     # SKYSCRAPER - steel blue
	11: Color(0.45, 0.4, 0.35),   # WAREHOUSE - dark brown
	12: Color(0.4, 0.35, 0.3),    # FACTORY - dark rust
	13: Color(0.3, 0.6, 0.3),     # PARK - green
	14: Color(0.25, 0.25, 0.25)   # ROAD - asphalt gray
}

## Cell size in world units
const CELL_SIZE := 2.0

## Downsampling factor (render every Nth cell for performance)
## Increased from 4 to 8 for larger 1200x1200 map
const DOWNSAMPLE := 8

## Container for buildings
var _buildings_container: Node3D = null

## Particle container
var _particles_container: Node3D = null

## PERFORMANCE: Cached mesh primitives (created once, reused for all buildings)
## This eliminates the overhead of CSG nodes and reduces mesh allocations
var _cached_unit_box: BoxMesh = null  # 1x1x1 box mesh, scaled per-instance
var _cached_unit_cylinder: CylinderMesh = null  # 1-height cylinder, scaled per-instance
var _cached_unit_sphere: SphereMesh = null  # 1-radius sphere, scaled per-instance
var _cached_window_lit_mat: StandardMaterial3D = null
var _cached_window_dark_mat: StandardMaterial3D = null
var _cached_ac_mat: StandardMaterial3D = null
var _cached_antenna_mat: StandardMaterial3D = null
var _cached_tank_mat: StandardMaterial3D = null
var _cached_pole_mat: StandardMaterial3D = null
var _cached_light_glow_mat: StandardMaterial3D = null
var _cached_meshes_initialized := false

## Zone grid for visual differentiation (stored during WFC generation)
var _current_zone_grid: Array = []
var _current_city_size: int = 600

## Zone colors for visual differentiation (per faction)
const ZONE_COLORS := {
	0: Color(0.2, 0.8, 0.8),   # ZERG_ALLEY - Aether Swarm cyan
	1: Color(0.9, 0.4, 0.2),   # TANK_BOULEVARD - LogiBots orange
	2: Color(0.6, 0.8, 0.4),   # MIXED_USE - Dynapods green
	3: Color(0.8, 0.3, 0.3),   # INDUSTRIAL - OptiForge red
	4: Color(0.4, 0.7, 0.4),   # PARK - green
}

## Building data tracking (building_id -> BuildingData)
var _buildings: Dictionary = {}

## Spatial grid for fast building lookups (cell_key -> Array[building_id])
var _building_grid: Dictionary = {}
const GRID_CELL_SIZE := 20.0  # Size of each spatial grid cell

## Next building ID
var _next_building_id: int = 1

## Statistics
var _building_count := 0
var _render_time_ms := 0.0
var _buildings_destroyed := 0
var _total_ree_dropped := 0.0


## Health bar container
var _health_bars_container: Node3D = null

## Current camera height for health bar scaling
var _camera_height: float = 180.0


## Building data class
class BuildingData:
	var id: int = 0
	var body: StaticBody3D = null  # Physics body container
	var mesh: MeshInstance3D = null  # PERFORMANCE: Using MeshInstance3D instead of CSGBox3D
	var material: StandardMaterial3D = null
	var health_bar: Node3D = null
	var health_bar_fill: MeshInstance3D = null  # PERFORMANCE: Using MeshInstance3D instead of CSGBox3D
	var type: int = 0
	var position: Vector3 = Vector3.ZERO
	var size: Vector3 = Vector3.ZERO
	var max_hp: float = 100.0
	var current_hp: float = 100.0
	var ree_value: float = 0.0
	var damage_state: int = 0  # 0=intact, 1=damaged, 2=critical
	var fire_particles: GPUParticles3D = null  # Persistent fire for damaged buildings
	var smoke_particles: GPUParticles3D = null  # Persistent smoke for damaged buildings

	func get_hp_percent() -> float:
		return current_hp / maxf(1.0, max_hp) * 100.0


## Streets container
var _streets_container: Node3D = null


func _ready() -> void:
	_streets_container = Node3D.new()
	_streets_container.name = "Streets"
	add_child(_streets_container)

	_buildings_container = Node3D.new()
	_buildings_container.name = "Buildings"
	add_child(_buildings_container)

	_particles_container = Node3D.new()
	_particles_container.name = "DestructionParticles"
	add_child(_particles_container)

	_health_bars_container = Node3D.new()
	_health_bars_container.name = "BuildingHealthBars"
	add_child(_health_bars_container)

	# PERFORMANCE: Initialize cached mesh primitives
	_initialize_cached_meshes()


## PERFORMANCE: Initialize cached mesh primitives and materials.
## These are created once and reused for all buildings, eliminating CSG overhead.
func _initialize_cached_meshes() -> void:
	if _cached_meshes_initialized:
		return

	# Create unit box mesh (scaled per-instance)
	_cached_unit_box = BoxMesh.new()
	_cached_unit_box.size = Vector3.ONE

	# Create unit cylinder mesh
	_cached_unit_cylinder = CylinderMesh.new()
	_cached_unit_cylinder.top_radius = 1.0
	_cached_unit_cylinder.bottom_radius = 1.0
	_cached_unit_cylinder.height = 1.0

	# Create unit sphere mesh
	_cached_unit_sphere = SphereMesh.new()
	_cached_unit_sphere.radius = 1.0
	_cached_unit_sphere.height = 2.0

	# Create shared materials for common elements

	# Lit window material (warm yellow glow)
	_cached_window_lit_mat = StandardMaterial3D.new()
	_cached_window_lit_mat.albedo_color = Color(1.0, 0.95, 0.8)
	_cached_window_lit_mat.emission_enabled = true
	_cached_window_lit_mat.emission = Color(1.0, 0.9, 0.6)
	_cached_window_lit_mat.emission_energy_multiplier = 1.5
	_cached_window_lit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Dark window material
	_cached_window_dark_mat = StandardMaterial3D.new()
	_cached_window_dark_mat.albedo_color = Color(0.15, 0.18, 0.22)
	_cached_window_dark_mat.emission_enabled = true
	_cached_window_dark_mat.emission = Color(0.05, 0.08, 0.12)
	_cached_window_dark_mat.emission_energy_multiplier = 0.3

	# AC unit material (gray metal)
	_cached_ac_mat = StandardMaterial3D.new()
	_cached_ac_mat.albedo_color = Color(0.4, 0.42, 0.45)
	_cached_ac_mat.metallic = 0.6
	_cached_ac_mat.roughness = 0.5

	# Antenna material
	_cached_antenna_mat = StandardMaterial3D.new()
	_cached_antenna_mat.albedo_color = Color(0.3, 0.3, 0.35)
	_cached_antenna_mat.metallic = 0.8

	# Water tank material
	_cached_tank_mat = StandardMaterial3D.new()
	_cached_tank_mat.albedo_color = Color(0.35, 0.38, 0.4)
	_cached_tank_mat.metallic = 0.5

	# Street lamp pole material
	_cached_pole_mat = StandardMaterial3D.new()
	_cached_pole_mat.albedo_color = Color(0.2, 0.22, 0.25)
	_cached_pole_mat.metallic = 0.7
	_cached_pole_mat.roughness = 0.4

	# Light glow material (warm yellow)
	_cached_light_glow_mat = StandardMaterial3D.new()
	_cached_light_glow_mat.albedo_color = Color(1.0, 0.9, 0.7)
	_cached_light_glow_mat.emission_enabled = true
	_cached_light_glow_mat.emission = Color(1.0, 0.85, 0.5)
	_cached_light_glow_mat.emission_energy_multiplier = 1.5

	_cached_meshes_initialized = true
	print("CityRenderer: Cached mesh primitives initialized")


## Render city from WFC grid.
## grid is a 2D array of BuildingType integers.
func render_city(grid: Array, offset: Vector3 = Vector3.ZERO) -> void:
	var start_time := Time.get_ticks_msec()
	_building_count = 0

	# Clear existing buildings
	for child in _buildings_container.get_children():
		child.queue_free()

	if grid.is_empty():
		push_warning("CityRenderer: Empty grid provided")
		return

	var grid_size: int = grid.size()
	var processed_cells := {}  # Track which cells we've already built

	# Process grid with downsampling
	var step: int = DOWNSAMPLE
	var total_cells: int = (grid_size / step) * (grid_size / step)
	var cells_processed := 0

	for x in range(0, grid_size, step):
		for y in range(0, grid_size, step):
			var cell_key := "%d_%d" % [x, y]
			if processed_cells.has(cell_key):
				continue

			var building_type: int = grid[x][y] if y < grid[x].size() else 0

			# Skip empty cells and roads (for cleaner look)
			if building_type == 0 or building_type == 14:
				cells_processed += 1
				continue

			# Create building
			var height: float = BUILDING_HEIGHTS.get(building_type, 4.0)
			var size: Vector2i = BUILDING_SIZES.get(building_type, Vector2i(1, 1))
			var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY)

			# Scale size by cell size and downsample
			var world_size := Vector3(
				size.x * CELL_SIZE * step * 0.9,  # 0.9 for gaps between buildings
				height,
				size.y * CELL_SIZE * step * 0.9
			)

			# Position in world
			var world_pos := Vector3(
				x * CELL_SIZE + world_size.x / 2.0,
				world_size.y / 2.0,
				y * CELL_SIZE + world_size.z / 2.0
			) + offset

			# Create building mesh
			_create_building(world_pos, world_size, color, building_type)

			# Mark cells as processed
			for dx in range(0, size.x * step, step):
				for dy in range(0, size.y * step, step):
					processed_cells["%d_%d" % [x + dx, y + dy]] = true

			_building_count += 1
			cells_processed += 1

			# Emit progress every 100 buildings
			if _building_count % 100 == 0:
				rendering_progress.emit(float(cells_processed) / total_cells * 100.0)

	_render_time_ms = Time.get_ticks_msec() - start_time
	print("CityRenderer: Created %d buildings in %.1fms" % [_building_count, _render_time_ms])
	city_rendered.emit(_building_count)


## Create a single building mesh and track it.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D with BoxMesh instead of CSGBox3D.
func _create_building(pos: Vector3, size: Vector3, color: Color, building_type: int) -> int:
	# Create a StaticBody3D container for physics collision
	var body := StaticBody3D.new()
	body.position = pos
	body.set_meta("building_type", building_type)

	# PERFORMANCE: Create MeshInstance3D with BoxMesh instead of CSGBox3D
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	# Mesh position is relative to body (centered)
	mesh.position = Vector3.ZERO

	var material := StandardMaterial3D.new()
	material.albedo_color = color

	# Add slight emission for visibility
	material.emission_enabled = true
	material.emission = color * 0.1
	material.emission_energy_multiplier = 0.2

	# Special handling for parks
	if building_type == 13:
		material.albedo_color = Color(0.2, 0.5, 0.2)
		material.roughness = 1.0
	# Special handling for skyscrapers
	elif building_type == 10:
		material.metallic = 0.5
		material.roughness = 0.3
		material.emission_energy_multiplier = 0.4
	# Industrial buildings
	elif building_type >= 7 and building_type <= 12:
		material.roughness = 0.8

	mesh.set_surface_override_material(0, material)
	body.add_child(mesh)

	# Add window details for buildings tall enough
	if size.y > 4.0 and building_type != 13 and building_type != 14:  # Not parks or roads
		_add_building_windows(body, size, building_type)

	# Add rooftop details (AC units, antenna, etc.)
	if size.y > 8.0 and randf() < 0.6:
		_add_rooftop_details(body, size, building_type)

	# Add trees and benches to parks
	if building_type == 13:
		_add_park_details(body, size)

	# Add billboards to tall commercial buildings
	if building_type >= 4 and building_type <= 6 and size.y > 8.0 and randf() < 0.4:
		_add_billboard(body, size)

	# Only add collision for buildings tall enough to matter (height > 3)
	# This improves performance by skipping collision for parks, roads, small buildings
	if size.y > 3.0:
		var collision := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collision.shape = box_shape
		body.add_child(collision)

		# Set collision layer (buildings on layer 4)
		body.collision_layer = 8  # Layer 4 (bit 3)
		body.collision_mask = 0   # Buildings don't need to detect collisions

	_buildings_container.add_child(body)

	# Calculate HP based on height
	var height: float = BUILDING_HEIGHTS.get(building_type, 4.0)
	var hp: float = height * BUILDING_HP_MULTIPLIER
	var ree: float = BUILDING_REE_DROPS.get(building_type, 5.0)

	# Create building data
	var building_id := _next_building_id
	_next_building_id += 1

	var data := BuildingData.new()
	data.id = building_id
	data.body = body
	data.mesh = mesh
	data.material = material
	data.type = building_type
	data.position = pos
	data.size = size
	data.max_hp = hp
	data.current_hp = hp
	data.ree_value = ree

	# Create health bar for this building
	var health_bar := _create_building_health_bar(pos, size)
	data.health_bar = health_bar["bar"]
	data.health_bar_fill = health_bar["fill"]
	_health_bars_container.add_child(data.health_bar)

	_buildings[building_id] = data
	_add_building_to_grid(building_id, pos)  # Add to spatial grid for fast lookup
	body.set_meta("building_id", building_id)
	mesh.set_meta("building_id", building_id)

	return building_id


## Create a health bar for a building.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSGBox3D.
func _create_building_health_bar(pos: Vector3, size: Vector3) -> Dictionary:
	var bar := Node3D.new()
	bar.position = pos + Vector3(0, size.y + 1.0, 0)

	# Background (dark) - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var bar_width: float = minf(size.x, 4.0)
	var bg := MeshInstance3D.new()
	var bg_box := BoxMesh.new()
	bg_box.size = Vector3(bar_width, 0.3, 0.1)
	bg.mesh = bg_box
	bg.position.y = 0.15
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.1, 0.1)
	bg.set_surface_override_material(0, bg_mat)
	bar.add_child(bg)

	# Fill (green -> yellow -> red based on HP) - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(bar_width, 0.3, 0.1)
	fill.mesh = fill_box
	fill.position.y = 0.15
	fill.position.z = 0.05
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.2, 0.8, 0.2)
	fill_mat.emission_enabled = true
	fill_mat.emission = Color(0.1, 0.4, 0.1)
	fill_mat.emission_energy_multiplier = 0.5
	fill.set_surface_override_material(0, fill_mat)
	bar.add_child(fill)

	# Start hidden - will show based on camera height
	bar.visible = false

	return {"bar": bar, "fill": fill}


## Render a simplified city (faster, fewer buildings).
## size: The world-space size of the city (e.g., 600 = 600 units wide)
## offset: Where to place the city corner (e.g., Vector3(-300, 0, -300) centers it)
func render_simple_city(size: int = 256, offset: Vector3 = Vector3.ZERO) -> void:
	var start_time := Time.get_ticks_msec()
	_building_count = 0

	# Clear existing
	for child in _buildings_container.get_children():
		child.queue_free()
	for child in _streets_container.get_children():
		child.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345  # Deterministic for now

	# Street grid parameters
	var block_size := 80  # Size of each city block (increased for larger maps)
	var street_width := 10.0  # Width of streets
	var margin := 60  # Keep away from map edges

	# Factory positions on sides (North/East/South/West)
	var half_size: float = size / 2.0
	var factory_positions := [
		Vector2(half_size, 50),          # North factory
		Vector2(size - 50, half_size),   # East factory
		Vector2(half_size, size - 50),   # South factory
		Vector2(50, half_size)           # West factory
	]
	var factory_exclusion_radius := 80.0  # Keep buildings/streets away from factories

	# Create street grid material
	var street_mat := StandardMaterial3D.new()
	street_mat.albedo_color = Color(0.15, 0.15, 0.18)  # Dark asphalt
	street_mat.roughness = 0.95

	var street_line_mat := StandardMaterial3D.new()
	street_line_mat.albedo_color = Color(0.8, 0.75, 0.3)  # Yellow road lines
	street_line_mat.emission_enabled = true
	street_line_mat.emission = Color(0.4, 0.35, 0.1)
	street_line_mat.emission_energy_multiplier = 0.3

	# Create horizontal streets
	for y in range(margin, size - margin, block_size):
		# Check if near factory
		var skip := false
		for factory_pos in factory_positions:
			if absf(y - factory_pos.y) < factory_exclusion_radius:
				if factory_pos.x < margin + factory_exclusion_radius or factory_pos.x > size - margin - factory_exclusion_radius:
					skip = true
					break
		if skip:
			continue

		# Main street surface
		var street := CSGBox3D.new()
		street.size = Vector3(size - margin * 2, 0.05, street_width)
		street.position = Vector3(size / 2.0, 0.02, y) + offset
		street.material = street_mat
		_streets_container.add_child(street)

		# Center line (dashed effect via multiple small boxes)
		for lx in range(margin + 5, size - margin - 5, 15):
			var line := CSGBox3D.new()
			line.size = Vector3(8.0, 0.06, 0.3)
			line.position = Vector3(lx + 4.0, 0.05, y) + offset
			line.material = street_line_mat
			_streets_container.add_child(line)

	# Create vertical streets
	for x in range(margin, size - margin, block_size):
		# Check if near factory
		var skip := false
		for factory_pos in factory_positions:
			if absf(x - factory_pos.x) < factory_exclusion_radius:
				if factory_pos.y < margin + factory_exclusion_radius or factory_pos.y > size - margin - factory_exclusion_radius:
					skip = true
					break
		if skip:
			continue

		# Main street surface
		var street := CSGBox3D.new()
		street.size = Vector3(street_width, 0.05, size - margin * 2)
		street.position = Vector3(x, 0.02, size / 2.0) + offset
		street.material = street_mat
		_streets_container.add_child(street)

		# Center line
		for lz in range(margin + 5, size - margin - 5, 15):
			var line := CSGBox3D.new()
			line.size = Vector3(0.3, 0.06, 8.0)
			line.position = Vector3(x, 0.05, lz + 4.0) + offset
			line.material = street_line_mat
			_streets_container.add_child(line)

	# Place buildings in blocks (between streets)
	var building_types := [1, 2, 4, 5, 7, 10]

	for block_x in range(margin, size - margin, block_size):
		for block_y in range(margin, size - margin, block_size):
			# Skip blocks near factories
			var near_factory := false
			for factory_pos in factory_positions:
				var block_center := Vector2(block_x + block_size / 2.0, block_y + block_size / 2.0)
				if block_center.distance_to(factory_pos) < factory_exclusion_radius:
					near_factory = true
					break
			if near_factory:
				continue

			# Place 1-4 buildings per block
			var buildings_in_block: int = rng.randi_range(1, 4)
			var building_margin: float = street_width / 2.0 + 2.0  # Keep buildings off streets

			for _i in range(buildings_in_block):
				# Random position within block (avoiding street edges)
				var bx: float = block_x + rng.randf_range(building_margin, block_size - building_margin - 10)
				var by: float = block_y + rng.randf_range(building_margin, block_size - building_margin - 10)

				# Determine building type based on distance to center
				var center_x := size / 2.0
				var center_y := size / 2.0
				var dist_to_center := Vector2(bx - center_x, by - center_y).length()
				var normalized_dist := dist_to_center / (size / 2.0)

				var building_type: int
				if normalized_dist < 0.25:
					building_type = 10 if rng.randf() < 0.4 else 5
				elif normalized_dist < 0.5:
					building_type = building_types[rng.randi() % building_types.size()]
				else:
					building_type = [1, 2, 7, 8][rng.randi() % 4]

				var height: float = BUILDING_HEIGHTS.get(building_type, 4.0)
				height *= rng.randf_range(0.8, 1.3)

				var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY)
				color = color.lightened(rng.randf_range(-0.1, 0.1))

				# Random building size (smaller to fit in blocks)
				var building_width: float = rng.randf_range(8.0, 18.0)
				var building_depth: float = rng.randf_range(8.0, 18.0)
				var world_size := Vector3(building_width, height, building_depth)

				var world_pos := Vector3(
					bx + building_width / 2.0,
					world_size.y / 2.0,
					by + building_depth / 2.0
				) + offset

				_create_building(world_pos, world_size, color, building_type)
				_building_count += 1

	_render_time_ms = Time.get_ticks_msec() - start_time
	print("CityRenderer: Created %d buildings with street grid in %.1fms" % [_building_count, _render_time_ms])
	city_rendered.emit(_building_count)


## Get building count.
func get_building_count() -> int:
	return _building_count


## Get destroyed building count.
func get_destroyed_building_count() -> int:
	return _buildings_destroyed


## Get render time.
func get_render_time_ms() -> float:
	return _render_time_ms


## Clear all buildings and streets.
func clear() -> void:
	for child in _buildings_container.get_children():
		child.queue_free()
	for child in _particles_container.get_children():
		child.queue_free()
	for child in _health_bars_container.get_children():
		child.queue_free()
	for child in _streets_container.get_children():
		child.queue_free()
	_buildings.clear()
	_building_count = 0
	_next_building_id = 1


## Update camera height and health bar visibility.
## Call this from main.gd each frame with the current camera height.
func update_camera_height(height: float) -> void:
	_camera_height = height

	# Determine health bar visibility based on zoom level
	# Show health bars when zoomed in (height < 120), hide when zoomed out
	var show_bars: bool = height < 150.0
	var bar_scale: float = 1.0

	if show_bars:
		# Scale bars larger when zoomed in more
		# At height 50, scale = 2.0; at height 150, scale = 0.5
		bar_scale = lerpf(2.0, 0.5, (height - 50.0) / 100.0)
		bar_scale = clampf(bar_scale, 0.5, 2.5)

	# Update all building health bars
	for building_id in _buildings:
		var data: BuildingData = _buildings[building_id]
		if data.health_bar != null and is_instance_valid(data.health_bar):
			# Only show if damaged (HP < 100%)
			var is_damaged: bool = data.current_hp < data.max_hp
			data.health_bar.visible = show_bars and is_damaged

			if data.health_bar.visible:
				data.health_bar.scale = Vector3(bar_scale, bar_scale, bar_scale)


## Damage a building by ID. Returns remaining HP.
func damage_building(building_id: int, damage: float, hit_pos: Vector3 = Vector3.ZERO) -> float:
	if not _buildings.has(building_id):
		return 0.0

	var data: BuildingData = _buildings[building_id]
	data.current_hp -= damage

	# Spawn impact sparks at hit position
	var spark_pos: Vector3 = hit_pos if hit_pos != Vector3.ZERO else data.position + Vector3(0, data.size.y * 0.5, 0)
	_spawn_impact_sparks(spark_pos, damage)

	# Update visual damage state
	var hp_percent: float = data.get_hp_percent()
	var old_state: int = data.damage_state

	if hp_percent <= 0:
		# Building destroyed - cleanup fire/smoke first
		_cleanup_building_particles(data)
		_destroy_building(building_id)
		return 0.0
	elif hp_percent < 33:
		data.damage_state = 2  # Critical
	elif hp_percent < 66:
		data.damage_state = 1  # Damaged
	else:
		data.damage_state = 0  # Intact

	# Update visual if state changed
	if data.damage_state != old_state:
		_update_building_visual(data)
		_update_building_fire_effects(data)

	# Update health bar fill and color
	_update_building_health_bar(data)

	building_damaged.emit(building_id, hp_percent)
	return data.current_hp


## Update building health bar fill and color.
## PERFORMANCE: Updated for MeshInstance3D instead of CSGBox3D.
func _update_building_health_bar(data: BuildingData) -> void:
	if data.health_bar_fill == null:
		return

	var hp_percent: float = data.get_hp_percent() / 100.0

	# Get bar width from the BoxMesh (MeshInstance3D doesn't have .size directly)
	var bar_width: float = 4.0  # Default width
	if data.health_bar_fill.mesh is BoxMesh:
		bar_width = data.health_bar_fill.mesh.size.x

	# Scale fill based on HP
	data.health_bar_fill.scale.x = maxf(0.01, hp_percent)
	data.health_bar_fill.position.x = -bar_width * (1.0 - hp_percent) / 2.0

	# Color based on HP (green -> yellow -> red)
	# For MeshInstance3D, use get_surface_override_material instead of .material
	var fill_mat: StandardMaterial3D = data.health_bar_fill.get_surface_override_material(0)
	if fill_mat:
		var color: Color
		if hp_percent > 0.66:
			color = Color(0.2, 0.8, 0.2)  # Green
		elif hp_percent > 0.33:
			color = Color(0.9, 0.7, 0.1)  # Yellow
		else:
			color = Color(0.9, 0.2, 0.1)  # Red
		fill_mat.albedo_color = color
		fill_mat.emission = color * 0.5


## Damage buildings in a radius. Returns total damage dealt.
func damage_buildings_in_radius(center: Vector3, radius: float, damage: float) -> float:
	var total_damage: float = 0.0

	for building_id in _buildings.keys():
		var data: BuildingData = _buildings[building_id]
		var dist: float = center.distance_to(data.position)

		if dist <= radius:
			# Damage falloff based on distance
			var falloff: float = 1.0 - (dist / radius) * 0.5
			var actual_damage: float = damage * falloff
			damage_building(building_id, actual_damage)
			total_damage += actual_damage

	return total_damage


## Destroy a building completely.
func _destroy_building(building_id: int) -> void:
	if not _buildings.has(building_id):
		return

	var data: BuildingData = _buildings[building_id]

	# Spawn destruction particles
	_spawn_destruction_particles(data.position, data.size, data.type)

	# Remove the body (which contains the mesh and collision)
	if data.body != null and is_instance_valid(data.body):
		data.body.queue_free()
	elif data.mesh != null and is_instance_valid(data.mesh):
		# Fallback for buildings created before body was added
		data.mesh.queue_free()

	# Remove the health bar
	if data.health_bar != null and is_instance_valid(data.health_bar):
		data.health_bar.queue_free()

	# Emit signal with REE drop info
	building_destroyed.emit(building_id, data.position, data.ree_value)

	# Track stats
	_buildings_destroyed += 1
	_total_ree_dropped += data.ree_value
	_building_count -= 1

	# Remove from spatial grid
	_remove_building_from_grid(building_id, data.position)

	# Remove from tracking
	_buildings.erase(building_id)


## Update building visual based on damage state.
func _update_building_visual(data: BuildingData) -> void:
	if data.material == null:
		return

	var base_color: Color = BUILDING_COLORS.get(data.type, Color.GRAY)

	match data.damage_state:
		0:  # Intact
			data.material.albedo_color = base_color
			data.material.emission_energy_multiplier = 0.2
		1:  # Damaged - darker, more emission (fire glow)
			data.material.albedo_color = base_color.darkened(0.3)
			data.material.emission = Color(1.0, 0.5, 0.2)  # Orange fire
			data.material.emission_energy_multiplier = 0.5
		2:  # Critical - very dark, strong fire glow
			data.material.albedo_color = base_color.darkened(0.6)
			data.material.emission = Color(1.0, 0.3, 0.1)  # Red-orange fire
			data.material.emission_energy_multiplier = 1.0


## Spawn destruction particle effects.
func _spawn_destruction_particles(pos: Vector3, size: Vector3, building_type: int) -> void:
	# Create debris particles
	var debris := GPUParticles3D.new()
	debris.name = "DebrisParticles"
	debris.position = pos
	debris.emitting = true
	debris.one_shot = true
	debris.explosiveness = 0.9
	debris.amount = int(size.y * 3)  # More particles for taller buildings
	debris.lifetime = 2.0

	# Create particle material
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = size.y * 0.5
	mat.initial_velocity_max = size.y * 1.5
	mat.gravity = Vector3(0, -20, 0)
	mat.damping_min = 2.0
	mat.damping_max = 5.0

	# Color based on building type
	var debris_color: Color = BUILDING_COLORS.get(building_type, Color.GRAY).darkened(0.2)
	mat.color = debris_color

	debris.process_material = mat

	# Simple box mesh for debris chunks
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	debris.draw_pass_1 = mesh

	_particles_container.add_child(debris)

	# Create dust cloud
	var dust := GPUParticles3D.new()
	dust.name = "DustCloud"
	dust.position = pos
	dust.emitting = true
	dust.one_shot = true
	dust.explosiveness = 0.7
	dust.amount = int(size.x * size.z * 2)
	dust.lifetime = 3.0

	var dust_mat := ParticleProcessMaterial.new()
	dust_mat.direction = Vector3(0, 0.5, 0)
	dust_mat.spread = 180.0
	dust_mat.initial_velocity_min = 2.0
	dust_mat.initial_velocity_max = 8.0
	dust_mat.gravity = Vector3(0, -1, 0)
	dust_mat.damping_min = 1.0
	dust_mat.damping_max = 3.0
	dust_mat.scale_min = 1.0
	dust_mat.scale_max = 3.0
	dust_mat.color = Color(0.6, 0.55, 0.5, 0.6)

	dust.process_material = dust_mat

	# Sphere mesh for dust particles
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.8
	dust_mesh.height = 1.6
	dust.draw_pass_1 = dust_mesh

	_particles_container.add_child(dust)

	# Create fire/explosion flash
	var flash := GPUParticles3D.new()
	flash.name = "ExplosionFlash"
	flash.position = pos
	flash.emitting = true
	flash.one_shot = true
	flash.explosiveness = 1.0
	flash.amount = 20
	flash.lifetime = 0.5

	var flash_mat := ParticleProcessMaterial.new()
	flash_mat.direction = Vector3(0, 1, 0)
	flash_mat.spread = 180.0
	flash_mat.initial_velocity_min = 5.0
	flash_mat.initial_velocity_max = 15.0
	flash_mat.gravity = Vector3(0, 5, 0)
	flash_mat.scale_min = 0.5
	flash_mat.scale_max = 2.0
	flash_mat.color = Color(1.0, 0.6, 0.2, 1.0)

	flash.process_material = flash_mat

	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.4
	flash_mesh.height = 0.8
	flash.draw_pass_1 = flash_mesh

	_particles_container.add_child(flash)

	# Auto-cleanup particles after they finish
	var cleanup_timer := get_tree().create_timer(4.0)
	cleanup_timer.timeout.connect(func():
		if is_instance_valid(debris):
			debris.queue_free()
		if is_instance_valid(dust):
			dust.queue_free()
		if is_instance_valid(flash):
			flash.queue_free()
	)


## Spawn impact sparks when building takes damage.
func _spawn_impact_sparks(pos: Vector3, damage: float) -> void:
	var sparks := GPUParticles3D.new()
	sparks.name = "ImpactSparks"
	sparks.position = pos
	sparks.emitting = true
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.amount = clampi(int(damage * 0.5), 5, 30)
	sparks.lifetime = 0.4

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 20.0
	mat.gravity = Vector3(0, -30, 0)
	mat.damping_min = 5.0
	mat.damping_max = 10.0
	mat.scale_min = 0.1
	mat.scale_max = 0.3
	mat.color = Color(1.0, 0.8, 0.3, 1.0)  # Yellow-orange sparks

	sparks.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	sparks.draw_pass_1 = mesh

	_particles_container.add_child(sparks)

	# Auto-cleanup
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func():
		if is_instance_valid(sparks):
			sparks.queue_free()
	)


## Update fire/smoke effects based on building damage state.
func _update_building_fire_effects(data: BuildingData) -> void:
	match data.damage_state:
		0:  # Intact - no fire
			_cleanup_building_particles(data)
		1:  # Damaged - small fire and smoke
			_create_building_fire(data, 0.5)
		2:  # Critical - large fire and heavy smoke
			_create_building_fire(data, 1.0)


## Create persistent fire particles for a damaged building.
func _create_building_fire(data: BuildingData, intensity: float) -> void:
	# Clean up existing particles first
	_cleanup_building_particles(data)

	var fire_pos: Vector3 = data.position + Vector3(0, data.size.y * 0.6, 0)

	# Fire particles
	var fire := GPUParticles3D.new()
	fire.name = "BuildingFire_%d" % data.id
	fire.position = fire_pos
	fire.emitting = true
	fire.amount = int(15 * intensity)
	fire.lifetime = 0.8
	fire.preprocess = 0.5

	var fire_mat := ParticleProcessMaterial.new()
	fire_mat.direction = Vector3(0, 1, 0)
	fire_mat.spread = 25.0
	fire_mat.initial_velocity_min = 3.0 * intensity
	fire_mat.initial_velocity_max = 8.0 * intensity
	fire_mat.gravity = Vector3(0, 3, 0)  # Fire rises
	fire_mat.damping_min = 1.0
	fire_mat.damping_max = 2.0
	fire_mat.scale_min = 0.3 * intensity
	fire_mat.scale_max = 0.8 * intensity
	fire_mat.color = Color(1.0, 0.5, 0.1, 0.9)  # Orange fire

	fire.process_material = fire_mat

	var fire_mesh := SphereMesh.new()
	fire_mesh.radius = 0.5
	fire_mesh.height = 1.0
	fire.draw_pass_1 = fire_mesh

	_particles_container.add_child(fire)
	data.fire_particles = fire

	# Smoke particles
	var smoke := GPUParticles3D.new()
	smoke.name = "BuildingSmoke_%d" % data.id
	smoke.position = fire_pos + Vector3(0, 2.0, 0)
	smoke.emitting = true
	smoke.amount = int(10 * intensity)
	smoke.lifetime = 2.5
	smoke.preprocess = 1.0

	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.direction = Vector3(0, 1, 0)
	smoke_mat.spread = 30.0
	smoke_mat.initial_velocity_min = 1.0
	smoke_mat.initial_velocity_max = 4.0
	smoke_mat.gravity = Vector3(0.5, 2, 0)  # Drifts slightly
	smoke_mat.damping_min = 0.5
	smoke_mat.damping_max = 1.5
	smoke_mat.scale_min = 1.0 * intensity
	smoke_mat.scale_max = 3.0 * intensity
	smoke_mat.color = Color(0.3, 0.3, 0.3, 0.5)  # Gray smoke

	smoke.process_material = smoke_mat

	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 1.0
	smoke_mesh.height = 2.0
	smoke.draw_pass_1 = smoke_mesh

	_particles_container.add_child(smoke)
	data.smoke_particles = smoke


## Clean up fire/smoke particles for a building.
func _cleanup_building_particles(data: BuildingData) -> void:
	if data.fire_particles != null and is_instance_valid(data.fire_particles):
		data.fire_particles.queue_free()
		data.fire_particles = null
	if data.smoke_particles != null and is_instance_valid(data.smoke_particles):
		data.smoke_particles.queue_free()
		data.smoke_particles = null


## Get building at position (within tolerance).
## Get grid cell key for a position.
func _get_grid_cell_key(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / GRID_CELL_SIZE)), int(floor(pos.z / GRID_CELL_SIZE)))


## Add building to spatial grid.
func _add_building_to_grid(building_id: int, pos: Vector3) -> void:
	var cell_key: Vector2i = _get_grid_cell_key(pos)
	if not _building_grid.has(cell_key):
		_building_grid[cell_key] = []
	_building_grid[cell_key].append(building_id)


## Remove building from spatial grid.
func _remove_building_from_grid(building_id: int, pos: Vector3) -> void:
	var cell_key: Vector2i = _get_grid_cell_key(pos)
	if _building_grid.has(cell_key):
		_building_grid[cell_key].erase(building_id)


func get_building_at_position(pos: Vector3, tolerance: float = 2.0) -> int:
	# Use spatial grid for O(1) lookup instead of O(n)
	var cell_key: Vector2i = _get_grid_cell_key(pos)

	# Check current cell and adjacent cells
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var check_key := Vector2i(cell_key.x + dx, cell_key.y + dz)
			if not _building_grid.has(check_key):
				continue

			for building_id in _building_grid[check_key]:
				if not _buildings.has(building_id):
					continue
				var data: BuildingData = _buildings[building_id]
				var dist: float = Vector2(pos.x, pos.z).distance_to(Vector2(data.position.x, data.position.z))
				if dist <= data.size.x / 2.0 + tolerance:
					return building_id
	return -1


## Get building data by ID.
func get_building_data(building_id: int) -> BuildingData:
	return _buildings.get(building_id)


## Get all buildings in radius (uses spatial grid for performance).
func get_buildings_in_radius(center: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	var center_cell: Vector2i = _get_grid_cell_key(center)
	var cell_radius: int = int(ceil(radius / GRID_CELL_SIZE)) + 1

	# Check all cells that could contain buildings within radius
	for dx in range(-cell_radius, cell_radius + 1):
		for dz in range(-cell_radius, cell_radius + 1):
			var check_key := Vector2i(center_cell.x + dx, center_cell.y + dz)
			if not _building_grid.has(check_key):
				continue

			for building_id in _building_grid[check_key]:
				if not _buildings.has(building_id):
					continue
				var data: BuildingData = _buildings[building_id]
				if center.distance_to(data.position) <= radius:
					result.append(building_id)
	return result


## Get destruction stats.
func get_destruction_stats() -> Dictionary:
	return {
		"buildings_remaining": _buildings.size(),
		"buildings_destroyed": _buildings_destroyed,
		"total_ree_dropped": _total_ree_dropped
	}


## Check if a position collides with any building.
## Returns true if position is inside a building's footprint.
func is_position_blocked(pos: Vector3, radius: float = 1.0) -> bool:
	# Use spatial grid for O(1) lookup
	var cell_key: Vector2i = _get_grid_cell_key(pos)

	# Check current and adjacent cells
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var check_key := Vector2i(cell_key.x + dx, cell_key.y + dz)
			if not _building_grid.has(check_key):
				continue

			for building_id in _building_grid[check_key]:
				if not _buildings.has(building_id):
					continue
				var data: BuildingData = _buildings[building_id]
				# Check XZ collision (ignore Y height)
				var half_x: float = data.size.x / 2.0 + radius
				var half_z: float = data.size.z / 2.0 + radius
				if absf(pos.x - data.position.x) < half_x and absf(pos.z - data.position.z) < half_z:
					return true
	return false


## Get a collision-free position by sliding along building edges.
## Returns the adjusted position that avoids building collision.
func get_collision_adjusted_position(from_pos: Vector3, to_pos: Vector3, radius: float = 1.0) -> Vector3:
	# Check if target position is blocked
	if not is_position_blocked(to_pos, radius):
		return to_pos

	# Use spatial grid to find the building we're colliding with
	var cell_key: Vector2i = _get_grid_cell_key(to_pos)

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var check_key := Vector2i(cell_key.x + dx, cell_key.y + dz)
			if not _building_grid.has(check_key):
				continue

			for building_id in _building_grid[check_key]:
				if not _buildings.has(building_id):
					continue
				var data: BuildingData = _buildings[building_id]
				var half_x: float = data.size.x / 2.0 + radius
				var half_z: float = data.size.z / 2.0 + radius

				# Check if target is in this building
				if absf(to_pos.x - data.position.x) < half_x and absf(to_pos.z - data.position.z) < half_z:
					# Slide along the building edge
					var adjusted := to_pos

					# Determine which edge to slide along
					var bx: float = to_pos.x - data.position.x
					var bz: float = to_pos.z - data.position.z

					# Push out to nearest edge
					if absf(bx) / half_x > absf(bz) / half_z:
						# Closer to X edge - slide along Z
						if bx > 0:
							adjusted.x = data.position.x + half_x + 0.1
						else:
							adjusted.x = data.position.x - half_x - 0.1
					else:
						# Closer to Z edge - slide along X
						if bz > 0:
							adjusted.z = data.position.z + half_z + 0.1
						else:
							adjusted.z = data.position.z - half_z - 0.1

					return adjusted

	return to_pos


## Get all building collision boxes for pathfinding.
func get_collision_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for building_id in _buildings:
		var data: BuildingData = _buildings[building_id]
		boxes.append({
			"id": building_id,
			"position": data.position,
			"size": data.size,
			"min_x": data.position.x - data.size.x / 2.0,
			"max_x": data.position.x + data.size.x / 2.0,
			"min_z": data.position.z - data.size.z / 2.0,
			"max_z": data.position.z + data.size.z / 2.0
		})
	return boxes


## Find a waypoint to navigate around a blocking building.
## Returns a position that goes around the obstacle toward the target.
func find_detour_waypoint(from_pos: Vector3, to_pos: Vector3, radius: float = 2.0) -> Vector3:
	# Find which building is blocking
	var blocking_building: BuildingData = null
	var dir := (to_pos - from_pos).normalized()

	# Ray march to find blocking building
	var check_dist := 0.0
	var max_dist := from_pos.distance_to(to_pos)
	while check_dist < minf(max_dist, 30.0):
		check_dist += 2.0
		var check_pos := from_pos + dir * check_dist
		for building_id in _buildings:
			var data: BuildingData = _buildings[building_id]
			var half_x: float = data.size.x / 2.0 + radius
			var half_z: float = data.size.z / 2.0 + radius
			if absf(check_pos.x - data.position.x) < half_x and absf(check_pos.z - data.position.z) < half_z:
				blocking_building = data
				break
		if blocking_building != null:
			break

	if blocking_building == null:
		return to_pos  # No obstruction found

	# Calculate waypoint around the building
	var bldg_pos := blocking_building.position
	var bldg_half_x: float = blocking_building.size.x / 2.0 + radius + 2.0
	var bldg_half_z: float = blocking_building.size.z / 2.0 + radius + 2.0

	# Determine which corner to go around (pick the one closest to target direction)
	var corners: Array[Vector3] = [
		Vector3(bldg_pos.x - bldg_half_x, 0, bldg_pos.z - bldg_half_z),
		Vector3(bldg_pos.x + bldg_half_x, 0, bldg_pos.z - bldg_half_z),
		Vector3(bldg_pos.x - bldg_half_x, 0, bldg_pos.z + bldg_half_z),
		Vector3(bldg_pos.x + bldg_half_x, 0, bldg_pos.z + bldg_half_z)
	]

	# Find corner that makes most progress toward target and is reachable
	var best_corner := corners[0]
	var best_score := -999999.0

	for corner in corners:
		# Skip if corner is blocked
		if is_position_blocked(corner, radius):
			continue

		# Score based on: distance to target from corner - distance from current pos to corner
		var dist_to_corner := from_pos.distance_to(corner)
		var dist_corner_to_target := corner.distance_to(to_pos)
		var progress := from_pos.distance_to(to_pos) - dist_corner_to_target
		var score := progress - dist_to_corner * 0.3  # Prefer shorter detours

		if score > best_score:
			best_score = score
			best_corner = corner

	return best_corner


## Check if there's a clear line of sight between two positions.
func has_clear_path(from_pos: Vector3, to_pos: Vector3, radius: float = 1.5) -> bool:
	var dir := (to_pos - from_pos).normalized()
	var dist := from_pos.distance_to(to_pos)
	var steps := int(dist / 2.0) + 1

	for i in range(1, steps):
		var check_pos := from_pos + dir * (i * 2.0)
		if is_position_blocked(check_pos, radius):
			return false

	return true


## Render city using Wave Function Collapse algorithm.
## Creates a more realistic city layout with proper zone-based building placement.
## factory_corners: Array of Vector2 positions for the 4 faction factories (in world units)
func render_wfc_city(size: int = 600, offset: Vector3 = Vector3.ZERO, seed_value: int = 0) -> void:
	var start_time := Time.get_ticks_msec()
	_building_count = 0

	# Clear existing
	for child in _buildings_container.get_children():
		child.queue_free()
	for child in _streets_container.get_children():
		child.queue_free()
	for child in _health_bars_container.get_children():
		child.queue_free()
	_buildings.clear()
	_next_building_id = 1

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 12345

	# Factory positions (sides: North/East/South/West) - keep buildings away
	# Factories are positioned on the sides of the map, not corners
	# Note: city coordinates are 0 to size, then offset is applied
	var half_size: float = size / 2.0
	var factory_positions := [
		Vector2(half_size, 50),          # North (faction 1 - Aether Swarm)
		Vector2(size - 50, half_size),   # East (faction 2 - OptiForge Legion)
		Vector2(half_size, size - 50),   # South (faction 3 - Dynapods Vanguard)
		Vector2(50, half_size)           # West (faction 4 - LogiBots Colossus)
	]
	var factory_exclusion_radius := 80.0

	# Generate zone grid (16x16)
	var zone_grid := _generate_zone_grid(size, factory_positions, rng)

	# Store zone grid for visual differentiation lookups
	_current_zone_grid = zone_grid
	_current_city_size = size

	# Generate WFC building grid
	print("CityRenderer: Generating WFC building layout...")
	var wfc := WFCBuildingPlacer.new()
	var wfc_zone_grid := _convert_to_wfc_zones(zone_grid)
	var building_grid: Array = wfc.generate_building_layout(wfc_zone_grid, rng.randi())

	if building_grid.is_empty():
		push_warning("CityRenderer: WFC generation failed, falling back to simple city")
		render_simple_city(size, offset)
		return

	print("CityRenderer: WFC generated %d cells collapsed" % wfc.get_statistics()["cells_collapsed"])

	# Create street grid material
	var street_mat := StandardMaterial3D.new()
	street_mat.albedo_color = Color(0.15, 0.15, 0.18)
	street_mat.roughness = 0.95

	var street_line_mat := StandardMaterial3D.new()
	street_line_mat.albedo_color = Color(0.8, 0.75, 0.3)
	street_line_mat.emission_enabled = true
	street_line_mat.emission = Color(0.4, 0.35, 0.1)
	street_line_mat.emission_energy_multiplier = 0.3

	# Render streets based on road cells in WFC grid
	_render_wfc_streets(building_grid, size, offset, street_mat, street_line_mat, factory_positions, factory_exclusion_radius)

	# Render buildings from WFC grid
	var wfc_grid_size: int = building_grid.size()
	var scale_factor: float = float(size) / float(wfc_grid_size)
	var processed_cells := {}

	# Debug: Count building types in grid
	var type_counts := {}
	var empty_count := 0
	var road_count := 0
	var factory_excluded := 0

	for x in range(0, wfc_grid_size, DOWNSAMPLE):
		for y in range(0, wfc_grid_size, DOWNSAMPLE):
			var cell_key := "%d_%d" % [x, y]
			if processed_cells.has(cell_key):
				continue

			var building_type: int = building_grid[x][y] if y < building_grid[x].size() else 0

			# Track type counts for debugging
			if not type_counts.has(building_type):
				type_counts[building_type] = 0
			type_counts[building_type] += 1

			# Skip empty, roads, and parks (roads are rendered separately)
			if building_type == 0 or building_type == 14:  # EMPTY or ROAD
				if building_type == 0:
					empty_count += 1
				else:
					road_count += 1
				continue

			# Check if near factory
			var world_x: float = x * scale_factor
			var world_y: float = y * scale_factor
			var near_factory := false
			for fp in factory_positions:
				if Vector2(world_x, world_y).distance_to(fp) < factory_exclusion_radius:
					near_factory = true
					break
			if near_factory:
				factory_excluded += 1
				continue

			# Get building properties
			var height: float = BUILDING_HEIGHTS.get(building_type, 4.0)
			var bsize: Vector2i = BUILDING_SIZES.get(building_type, Vector2i(1, 1))
			var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY)

			# Add variation
			height *= rng.randf_range(0.8, 1.2)
			color = color.lightened(rng.randf_range(-0.1, 0.1))

			# Calculate world size and position
			var world_size := Vector3(
				bsize.x * scale_factor * DOWNSAMPLE * 0.85,
				height,
				bsize.y * scale_factor * DOWNSAMPLE * 0.85
			)

			var world_pos := Vector3(
				world_x + world_size.x / 2.0,
				world_size.y / 2.0,
				world_y + world_size.z / 2.0
			) + offset

			# Create building
			_create_building(world_pos, world_size, color, building_type)

			# Mark cells as processed
			for dx in range(0, bsize.x * DOWNSAMPLE, DOWNSAMPLE):
				for dy in range(0, bsize.y * DOWNSAMPLE, DOWNSAMPLE):
					processed_cells["%d_%d" % [x + dx, y + dy]] = true

			_building_count += 1

	# Debug output
	print("CityRenderer: Grid analysis - Empty: %d, Roads: %d, Factory excluded: %d" % [empty_count, road_count, factory_excluded])

	# Fallback: If WFC produced too few buildings, add some manually
	if _building_count < 50:
		print("CityRenderer: WFC produced few buildings (%d), adding fallback buildings..." % _building_count)
		_add_fallback_buildings(size, offset, rng, factory_positions, factory_exclusion_radius)

	_render_time_ms = Time.get_ticks_msec() - start_time
	print("CityRenderer: WFC city created %d buildings in %.1fms" % [_building_count, _render_time_ms])
	city_rendered.emit(_building_count)


## Add fallback buildings when WFC produces too few.
## Creates organic SimCity-style building clusters with varied lot sizes and spacing.
func _add_fallback_buildings(size: int, offset: Vector3, rng: RandomNumberGenerator,
		factory_positions: Array, factory_exclusion_radius: float) -> void:
	var margin := 100.0
	var added := 0

	# Building type categories for different district vibes
	var downtown_types := [4, 5, 7, 10]  # Tall office/commercial buildings
	var residential_types := [1, 2, 11]  # Houses, apartments
	var industrial_types := [3, 8, 9]    # Warehouses, factories
	var mixed_types := [1, 2, 4, 5, 6, 7]

	var center := Vector2(size / 2.0, size / 2.0)

	# PHASE 1: Create downtown core with dense tall buildings (20% of area near center)
	var downtown_radius := size * 0.20
	var downtown_buildings := int(rng.randf_range(60, 90))
	for _i in downtown_buildings:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(50, downtown_radius)
		var bx := center.x + cos(angle) * dist
		var bz := center.y + sin(angle) * dist

		if _is_valid_building_spot(bx, bz, size, margin, factory_positions, factory_exclusion_radius):
			var building_type: int = downtown_types[rng.randi() % downtown_types.size()]
			var height: float = BUILDING_HEIGHTS.get(building_type, 20.0) * rng.randf_range(0.9, 1.8)
			var base_width := rng.randf_range(12.0, 28.0)
			var base_depth := rng.randf_range(12.0, 28.0)
			var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY).lightened(rng.randf_range(-0.2, 0.2))

			_place_organic_building(bx, bz, base_width, base_depth, height, color, building_type, offset, rng)
			added += 1

	# PHASE 2: Create mixed-use ring around downtown
	var mixed_inner := downtown_radius
	var mixed_outer := size * 0.45
	var mixed_buildings := int(rng.randf_range(150, 220))
	for _i in mixed_buildings:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(mixed_inner, mixed_outer)
		var bx := center.x + cos(angle) * dist
		var bz := center.y + sin(angle) * dist

		if _is_valid_building_spot(bx, bz, size, margin, factory_positions, factory_exclusion_radius):
			var building_type: int = mixed_types[rng.randi() % mixed_types.size()]
			var height: float = BUILDING_HEIGHTS.get(building_type, 8.0) * rng.randf_range(0.7, 1.4)
			var base_width := rng.randf_range(8.0, 20.0)
			var base_depth := rng.randf_range(8.0, 20.0)
			var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY).lightened(rng.randf_range(-0.15, 0.2))

			_place_organic_building(bx, bz, base_width, base_depth, height, color, building_type, offset, rng)
			added += 1

	# PHASE 3: Create suburban/industrial edges with scattered buildings
	var outer_buildings := int(rng.randf_range(200, 300))
	for _i in outer_buildings:
		var bx := rng.randf_range(margin, size - margin)
		var bz := rng.randf_range(margin, size - margin)
		var dist_to_center := Vector2(bx, bz).distance_to(center)

		# Only place in outer ring
		if dist_to_center < mixed_outer:
			continue

		if _is_valid_building_spot(bx, bz, size, margin, factory_positions, factory_exclusion_radius):
			# Mix of residential and industrial based on randomness
			var types_to_use: Array = residential_types if rng.randf() < 0.6 else industrial_types
			var building_type: int = types_to_use[rng.randi() % types_to_use.size()]
			var height: float = BUILDING_HEIGHTS.get(building_type, 5.0) * rng.randf_range(0.6, 1.2)
			var base_width := rng.randf_range(6.0, 15.0)
			var base_depth := rng.randf_range(6.0, 15.0)
			var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY).lightened(rng.randf_range(-0.1, 0.15))

			_place_organic_building(bx, bz, base_width, base_depth, height, color, building_type, offset, rng)
			added += 1

	# PHASE 4: Add small filler buildings and shops along "streets" (random lines)
	var street_count := int(rng.randf_range(15, 25))
	for _s in street_count:
		var street_start := Vector2(rng.randf_range(margin, size - margin), rng.randf_range(margin, size - margin))
		var street_angle := rng.randf() * TAU
		var street_length := rng.randf_range(150, 400)
		var buildings_per_street := int(rng.randf_range(8, 20))

		for _b in buildings_per_street:
			var along := rng.randf() * street_length
			var side_offset := rng.randf_range(-35, 35)  # Offset from street center
			var bx := street_start.x + cos(street_angle) * along + cos(street_angle + PI/2) * side_offset
			var bz := street_start.y + sin(street_angle) * along + sin(street_angle + PI/2) * side_offset

			if _is_valid_building_spot(bx, bz, size, margin, factory_positions, factory_exclusion_radius):
				var building_type: int = mixed_types[rng.randi() % mixed_types.size()]
				var height: float = BUILDING_HEIGHTS.get(building_type, 6.0) * rng.randf_range(0.5, 1.0)
				var base_width := rng.randf_range(5.0, 12.0)
				var base_depth := rng.randf_range(5.0, 12.0)
				var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY).lightened(rng.randf_range(-0.1, 0.2))

				_place_organic_building(bx, bz, base_width, base_depth, height, color, building_type, offset, rng)
				added += 1

	# PHASE 5: Sprinkle some landmark buildings (extra tall/wide)
	var landmark_count := int(rng.randf_range(5, 12))
	for _l in landmark_count:
		var bx := rng.randf_range(margin + 100, size - margin - 100)
		var bz := rng.randf_range(margin + 100, size - margin - 100)

		if _is_valid_building_spot(bx, bz, size, margin, factory_positions, factory_exclusion_radius):
			var building_type: int = downtown_types[rng.randi() % downtown_types.size()]
			var height: float = rng.randf_range(35.0, 60.0)  # Extra tall landmarks
			var base_width := rng.randf_range(20.0, 40.0)
			var base_depth := rng.randf_range(20.0, 40.0)
			var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY).lightened(rng.randf_range(-0.1, 0.1))

			_place_organic_building(bx, bz, base_width, base_depth, height, color, building_type, offset, rng)
			added += 1

	print("CityRenderer: Added %d organic fallback buildings" % added)


## Check if a building spot is valid (not near factories or edges).
func _is_valid_building_spot(bx: float, bz: float, size: float, margin: float,
		factory_positions: Array, factory_exclusion_radius: float) -> bool:
	if bx < margin or bx > size - margin or bz < margin or bz > size - margin:
		return false
	for fp in factory_positions:
		if Vector2(bx, bz).distance_to(fp) < factory_exclusion_radius + 30:
			return false
	return true


## Place a building with organic random rotation and slight position jitter.
func _place_organic_building(bx: float, bz: float, width: float, depth: float,
		height: float, color: Color, building_type: int, offset: Vector3, rng: RandomNumberGenerator) -> void:
	# Add position jitter for organic feel
	var jitter_x := rng.randf_range(-5.0, 5.0)
	var jitter_z := rng.randf_range(-5.0, 5.0)

	var world_size := Vector3(width, height, depth)
	var world_pos := Vector3(
		bx + width / 2.0 + jitter_x,
		height / 2.0,
		bz + depth / 2.0 + jitter_z
	) + offset

	_create_building(world_pos, world_size, color, building_type)
	_building_count += 1


## Generate zone grid for WFC input.
## Creates faction-themed zones near factory sides, with mixed zones in center.
func _generate_zone_grid(size: int, factory_positions: Array, rng: RandomNumberGenerator) -> Array:
	const ZONE_GRID_SIZE := 16
	var zone_grid := []

	for x in ZONE_GRID_SIZE:
		var row := []
		for y in ZONE_GRID_SIZE:
			# Convert to world coordinates (center of zone)
			var world_x: float = (x + 0.5) * (size / float(ZONE_GRID_SIZE))
			var world_y: float = (y + 0.5) * (size / float(ZONE_GRID_SIZE))
			var world_pos := Vector2(world_x, world_y)
			var center := Vector2(size / 2.0, size / 2.0)

			# Determine zone type based on position
			var zone_type: int

			# Check if near any factory (on sides: North/East/South/West)
			var nearest_factory := -1
			var nearest_dist := 999999.0
			for i in factory_positions.size():
				var dist: float = world_pos.distance_to(factory_positions[i])
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_factory = i

			# Side zones (near factories on map edges)
			if nearest_dist < size * 0.25:
				match nearest_factory:
					0:  # North: Aether Swarm - dense swarm alleys
						zone_type = WFCBuildingPlacer.ZoneType.ZERG_ALLEY
					1:  # East: OptiForge - industrial factories
						zone_type = WFCBuildingPlacer.ZoneType.INDUSTRIAL
					2:  # South: Dynapods - mixed terrain (agile movement)
						zone_type = WFCBuildingPlacer.ZoneType.MIXED_USE
					3:  # West: LogiBots - wide boulevards for heavy tanks
						zone_type = WFCBuildingPlacer.ZoneType.TANK_BOULEVARD

			# Edge zones (corners not near factories)
			elif x == 0 or x == ZONE_GRID_SIZE - 1 or y == 0 or y == ZONE_GRID_SIZE - 1:
				zone_type = WFCBuildingPlacer.ZoneType.INDUSTRIAL

			# Central zones
			elif world_pos.distance_to(center) < size * 0.2:
				# City center: mix of commercial/residential
				zone_type = [
					WFCBuildingPlacer.ZoneType.TANK_BOULEVARD,
					WFCBuildingPlacer.ZoneType.MIXED_USE
				][rng.randi() % 2]

			# Transition zones
			else:
				zone_type = WFCBuildingPlacer.ZoneType.MIXED_USE

			row.append(zone_type)
		zone_grid.append(row)

	return zone_grid


## Convert zone grid to WFC zone grid format (512x512).
func _convert_to_wfc_zones(zone_grid: Array) -> Array:
	const ZONE_GRID_SIZE := 16
	const WFC_GRID_SIZE := 512
	const CELLS_PER_ZONE := WFC_GRID_SIZE / ZONE_GRID_SIZE  # 32

	var wfc_zones := []
	for x in WFC_GRID_SIZE:
		var row := []
		for y in WFC_GRID_SIZE:
			var zone_x := mini(x / CELLS_PER_ZONE, ZONE_GRID_SIZE - 1)
			var zone_y := mini(y / CELLS_PER_ZONE, ZONE_GRID_SIZE - 1)
			row.append(zone_grid[zone_x][zone_y])
		wfc_zones.append(row)

	return wfc_zones


## Get zone type at world position.
## Returns zone type (0-4) based on the 16x16 zone grid.
func _get_zone_at_world_pos(world_x: float, world_z: float) -> int:
	if _current_zone_grid.is_empty() or _current_city_size <= 0:
		return 2  # Default to MIXED_USE

	const ZONE_GRID_SIZE := 16
	var zone_x := int(world_x / (_current_city_size / float(ZONE_GRID_SIZE)))
	var zone_z := int(world_z / (_current_city_size / float(ZONE_GRID_SIZE)))

	zone_x = clampi(zone_x, 0, ZONE_GRID_SIZE - 1)
	zone_z = clampi(zone_z, 0, ZONE_GRID_SIZE - 1)

	if zone_x < _current_zone_grid.size() and zone_z < _current_zone_grid[zone_x].size():
		return _current_zone_grid[zone_x][zone_z]

	return 2  # Default to MIXED_USE


## Add a zone marker sign at intersections.
## Shows faction colors to help players identify territory.
func _add_zone_marker(pos: Vector3, zone_type: int) -> void:
	var marker := Node3D.new()
	marker.position = pos

	# Post material (dark metal)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.2, 0.22, 0.25)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.5

	# Post
	var post := MeshInstance3D.new()
	var post_cyl := CylinderMesh.new()
	post_cyl.top_radius = 0.12
	post_cyl.bottom_radius = 0.12
	post_cyl.height = 4.0
	post.mesh = post_cyl
	post.position.y = 2.0
	post.set_surface_override_material(0, post_mat)
	marker.add_child(post)

	# Sign panel with zone color
	var zone_color: Color = ZONE_COLORS.get(zone_type, Color(0.5, 0.5, 0.5))

	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = zone_color
	sign_mat.emission_enabled = true
	sign_mat.emission = zone_color
	sign_mat.emission_energy_multiplier = 0.8

	var sign_panel := MeshInstance3D.new()
	var sign_box := BoxMesh.new()
	sign_box.size = Vector3(1.2, 0.8, 0.1)
	sign_panel.mesh = sign_box
	sign_panel.position = Vector3(0, 3.8, 0)
	sign_panel.set_surface_override_material(0, sign_mat)
	marker.add_child(sign_panel)

	# Add faction symbol indicator (colored strip on top)
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = zone_color.lightened(0.3)
	strip_mat.emission_enabled = true
	strip_mat.emission = zone_color
	strip_mat.emission_energy_multiplier = 1.2

	var strip := MeshInstance3D.new()
	var strip_box := BoxMesh.new()
	strip_box.size = Vector3(1.3, 0.15, 0.12)
	strip.mesh = strip_box
	strip.position = Vector3(0, 4.3, 0)
	strip.set_surface_override_material(0, strip_mat)
	marker.add_child(strip)

	_streets_container.add_child(marker)


## Render streets from WFC road cells.
func _render_wfc_streets(building_grid: Array, size: int, offset: Vector3,
		street_mat: StandardMaterial3D, line_mat: StandardMaterial3D,
		factory_positions: Array, factory_exclusion_radius: float) -> void:
	var grid_size: int = building_grid.size()
	var scale_factor: float = float(size) / float(grid_size)
	var street_width: float = scale_factor * DOWNSAMPLE * 0.9

	# Create main arterial streets - balanced for performance
	# With grid_size=64, interval=16 gives 4 streets per axis (manageable)
	var arterial_interval := 16
	var margin := 80

	# Sidewalk material
	var sidewalk_mat := StandardMaterial3D.new()
	sidewalk_mat.albedo_color = Color(0.35, 0.35, 0.38)
	sidewalk_mat.roughness = 0.85

	# Horizontal arterials
	for y_cell in range(0, grid_size, arterial_interval):
		var world_y: float = y_cell * scale_factor
		if world_y < margin or world_y > size - margin:
			continue

		# Check factory proximity
		var skip := false
		for fp in factory_positions:
			if absf(world_y - fp.y) < factory_exclusion_radius:
				skip = true
				break
		if skip:
			continue

		var street := CSGBox3D.new()
		street.size = Vector3(size - margin * 2, 0.05, street_width * 1.5)
		street.position = Vector3(size / 2.0, 0.02, world_y) + offset
		street.material = street_mat
		_streets_container.add_child(street)

		# Sidewalks on both sides
		for side in [-1, 1]:
			var sidewalk := CSGBox3D.new()
			sidewalk.size = Vector3(size - margin * 2, 0.08, 3.0)
			sidewalk.position = Vector3(size / 2.0, 0.04, world_y + (street_width * 0.8 + 2.0) * side) + offset
			sidewalk.material = sidewalk_mat
			_streets_container.add_child(sidewalk)

		# Center lines (sparser for perf)
		for lx in range(margin + 10, size - margin - 10, 50):
			var line := CSGBox3D.new()
			line.size = Vector3(25.0, 0.06, 0.4)
			line.position = Vector3(lx + 12.5, 0.05, world_y) + offset
			line.material = line_mat
			_streets_container.add_child(line)

		# Add street lamps along horizontal streets (sparse - one side only)
		for lamp_x in range(margin + 80, size - margin - 80, 150):
			var lamp_near_factory := false
			for fp in factory_positions:
				if Vector2(lamp_x, world_y).distance_to(fp) < factory_exclusion_radius:
					lamp_near_factory = true
					break
			if not lamp_near_factory:
				var zone := _get_zone_at_world_pos(lamp_x, world_y)
				var lamp_side := 1 if randi() % 2 == 0 else -1
				_add_street_lamp(Vector3(lamp_x, 0, world_y + street_width * 0.9 * lamp_side) + offset, zone)

		# Add parked vehicles along horizontal streets (sparse)
		for veh_x in range(margin + 100, size - margin - 100, 200):
			var veh_near_factory := false
			for fp in factory_positions:
				if Vector2(veh_x, world_y).distance_to(fp) < factory_exclusion_radius + 20:
					veh_near_factory = true
					break
			if not veh_near_factory and randf() < 0.4:
				var veh_side: float = street_width * 0.6 * (1 if randi() % 2 == 0 else -1)
				var is_truck: bool = randf() < 0.25
				_add_parked_vehicle(Vector3(veh_x + randf_range(-5, 5), 0, world_y + veh_side) + offset, PI / 2 + randf_range(-0.1, 0.1), is_truck)

		# Add street furniture along horizontal sidewalks (very sparse for perf)
		for furn_x in range(margin + 100, size - margin - 100, 300):
			var furn_near_factory := false
			for fp in factory_positions:
				if Vector2(furn_x, world_y).distance_to(fp) < factory_exclusion_radius:
					furn_near_factory = true
					break
			if not furn_near_factory:
				var sidewalk_offset: float = street_width * 0.9 + 1.5
				# Only spawn ONE type of furniture per location
				var furniture_type := randi() % 6
				match furniture_type:
					0: _add_street_bench(Vector3(furn_x, 0, world_y + sidewalk_offset) + offset, 0)
					1: _add_street_trash_bin(Vector3(furn_x, 0, world_y - sidewalk_offset) + offset)
					2: _add_street_planter(Vector3(furn_x, 0, world_y + sidewalk_offset) + offset, randi() % 3)
					3: _add_fire_hydrant(Vector3(furn_x, 0, world_y - sidewalk_offset + 0.5) + offset)
					4: _add_mailbox(Vector3(furn_x, 0, world_y - sidewalk_offset) + offset, 0)
					5: _add_bush(Vector3(furn_x, 0, world_y + sidewalk_offset) + offset, randi() % 4)

		# Add trees along horizontal streets (sparse)
		for tree_x in range(margin + 150, size - margin - 150, 250):
			var tree_near_factory := false
			for fp in factory_positions:
				if Vector2(tree_x, world_y).distance_to(fp) < factory_exclusion_radius + 15:
					tree_near_factory = true
					break
			if not tree_near_factory and randf() < 0.35:
				var tree_offset: float = street_width * 0.9 + 3.0
				var tree_side: int = 1 if randi() % 2 == 0 else -1
				var tree_type := randi() % 2
				if tree_type == 0:
					_add_pine_tree(Vector3(tree_x, 0, world_y + tree_offset * tree_side) + offset, randf_range(0.8, 1.2))
				else:
					_add_palm_tree(Vector3(tree_x, 0, world_y + tree_offset * tree_side) + offset, randf_range(0.7, 1.0))

	# Vertical arterials
	for x_cell in range(0, grid_size, arterial_interval):
		var world_x: float = x_cell * scale_factor
		if world_x < margin or world_x > size - margin:
			continue

		var skip := false
		for fp in factory_positions:
			if absf(world_x - fp.x) < factory_exclusion_radius:
				skip = true
				break
		if skip:
			continue

		var street := CSGBox3D.new()
		street.size = Vector3(street_width * 1.5, 0.05, size - margin * 2)
		street.position = Vector3(world_x, 0.02, size / 2.0) + offset
		street.material = street_mat
		_streets_container.add_child(street)

		# Sidewalks
		for side in [-1, 1]:
			var sidewalk := CSGBox3D.new()
			sidewalk.size = Vector3(3.0, 0.08, size - margin * 2)
			sidewalk.position = Vector3(world_x + (street_width * 0.8 + 2.0) * side, 0.04, size / 2.0) + offset
			sidewalk.material = sidewalk_mat
			_streets_container.add_child(sidewalk)

		# Center lines (sparser for perf)
		for lz in range(margin + 10, size - margin - 10, 50):
			var line := CSGBox3D.new()
			line.size = Vector3(0.4, 0.06, 25.0)
			line.position = Vector3(world_x, 0.05, lz + 12.5) + offset
			line.material = line_mat
			_streets_container.add_child(line)

		# Add street lamps along vertical streets (sparse - one side only)
		for lamp_z in range(margin + 80, size - margin - 80, 150):
			var lamp_near_factory := false
			for fp in factory_positions:
				if Vector2(world_x, lamp_z).distance_to(fp) < factory_exclusion_radius:
					lamp_near_factory = true
					break
			if not lamp_near_factory:
				var zone := _get_zone_at_world_pos(world_x, lamp_z)
				var lamp_side := 1 if randi() % 2 == 0 else -1
				_add_street_lamp(Vector3(world_x + street_width * 0.9 * lamp_side, 0, lamp_z) + offset, zone)

		# Add parked vehicles along vertical streets (sparse)
		for veh_z in range(margin + 100, size - margin - 100, 200):
			var veh_near_factory := false
			for fp in factory_positions:
				if Vector2(world_x, veh_z).distance_to(fp) < factory_exclusion_radius + 20:
					veh_near_factory = true
					break
			if not veh_near_factory and randf() < 0.4:
				var veh_side: float = street_width * 0.6 * (1 if randi() % 2 == 0 else -1)
				var is_truck: bool = randf() < 0.25
				_add_parked_vehicle(Vector3(world_x + veh_side, 0, veh_z + randf_range(-5, 5)) + offset, randf_range(-0.1, 0.1), is_truck)

		# Add street furniture along vertical sidewalks (very sparse for perf)
		for furn_z in range(margin + 100, size - margin - 100, 300):
			var furn_near_factory := false
			for fp in factory_positions:
				if Vector2(world_x, furn_z).distance_to(fp) < factory_exclusion_radius:
					furn_near_factory = true
					break
			if not furn_near_factory:
				var sidewalk_offset: float = street_width * 0.9 + 1.5
				# Only spawn ONE type of furniture per location
				var furniture_type := randi() % 6
				match furniture_type:
					0: _add_street_bench(Vector3(world_x + sidewalk_offset, 0, furn_z) + offset, PI / 2)
					1: _add_street_trash_bin(Vector3(world_x - sidewalk_offset, 0, furn_z) + offset)
					2: _add_street_planter(Vector3(world_x + sidewalk_offset, 0, furn_z) + offset, randi() % 3)
					3: _add_fire_hydrant(Vector3(world_x - sidewalk_offset + 0.5, 0, furn_z) + offset)
					4: _add_mailbox(Vector3(world_x - sidewalk_offset, 0, furn_z) + offset, PI / 2)
					5: _add_bush(Vector3(world_x + sidewalk_offset, 0, furn_z) + offset, randi() % 4)

		# Add trees along vertical streets (sparse)
		for tree_z in range(margin + 150, size - margin - 150, 250):
			var tree_near_factory := false
			for fp in factory_positions:
				if Vector2(world_x, tree_z).distance_to(fp) < factory_exclusion_radius + 15:
					tree_near_factory = true
					break
			if not tree_near_factory and randf() < 0.35:
				var tree_offset: float = street_width * 0.9 + 3.0
				var tree_side: int = 1 if randi() % 2 == 0 else -1
				var tree_type := randi() % 2
				if tree_type == 0:
					_add_pine_tree(Vector3(world_x + tree_offset * tree_side, 0, tree_z) + offset, randf_range(0.8, 1.2))
				else:
					_add_palm_tree(Vector3(world_x + tree_offset * tree_side, 0, tree_z) + offset, randf_range(0.7, 1.0))

	# Add zone markers at major intersections
	_add_zone_markers_at_intersections(size, offset, factory_positions, factory_exclusion_radius, arterial_interval, margin)

	# Debug: count street assets
	print("[CityRenderer] Street assets: %d total, %d bushes" % [_streets_container.get_child_count(), _bush_count])


## Add zone markers at arterial street intersections.
func _add_zone_markers_at_intersections(size: int, offset: Vector3,
		factory_positions: Array, factory_exclusion_radius: float,
		arterial_interval: int, margin: int) -> void:
	var grid_size := 512  # WFC grid size
	var scale_factor: float = float(size) / float(grid_size)
	var DOWNSAMPLE_LOCAL := DOWNSAMPLE

	# Find all intersections of horizontal and vertical arterials
	var horizontal_streets := []
	var vertical_streets := []

	for y_cell in range(0, grid_size, arterial_interval):
		var world_y: float = y_cell * scale_factor
		if world_y >= margin and world_y <= size - margin:
			horizontal_streets.append(world_y)

	for x_cell in range(0, grid_size, arterial_interval):
		var world_x: float = x_cell * scale_factor
		if world_x >= margin and world_x <= size - margin:
			vertical_streets.append(world_x)

	# Add zone markers at intersection corners
	for world_y in horizontal_streets:
		for world_x in vertical_streets:
			# Skip if near factory
			var near_factory := false
			for fp in factory_positions:
				if Vector2(world_x, world_y).distance_to(fp) < factory_exclusion_radius + 20:
					near_factory = true
					break

			if near_factory:
				continue

			# Get zone at this position
			var zone := _get_zone_at_world_pos(world_x, world_y)

			# Add marker at one corner of intersection (offset from center)
			var marker_offset := 18.0  # Distance from intersection center
			_add_zone_marker(Vector3(world_x + marker_offset, 0, world_y + marker_offset) + offset, zone)

			# Add decorative green spaces at intersections
			if randf() < 0.4:
				# Add flower beds at some intersection corners
				var corner := randi() % 4
				var corner_offset := Vector3.ZERO
				match corner:
					0: corner_offset = Vector3(marker_offset + 5, 0, marker_offset + 5)
					1: corner_offset = Vector3(-marker_offset - 5, 0, marker_offset + 5)
					2: corner_offset = Vector3(marker_offset + 5, 0, -marker_offset - 5)
					3: corner_offset = Vector3(-marker_offset - 5, 0, -marker_offset - 5)
				_add_flower_bed(Vector3(world_x, 0, world_y) + corner_offset + offset, Vector2(randf_range(2.5, 4.0), randf_range(1.5, 2.5)))

			if randf() < 0.25:
				# Add hedges along some intersection edges
				var hedge_side := randi() % 2
				var hedge_offset := marker_offset + 8
				if hedge_side == 0:
					_add_hedge(Vector3(world_x + hedge_offset, 0, world_y) + offset, randf_range(4.0, 8.0), 0)
				else:
					_add_hedge(Vector3(world_x, 0, world_y + hedge_offset) + offset, randf_range(4.0, 8.0), PI / 2)


## Get list of damaged buildings that can be salvaged.
## Returns array of dictionaries with building info.
func get_damaged_buildings() -> Array:
	var damaged: Array = []

	for building_id in _buildings.keys():
		var data: BuildingData = _buildings[building_id]
		# Include buildings that are damaged (< 100% HP) but not destroyed
		if data.current_hp > 0 and data.current_hp < data.max_hp:
			damaged.append({
				"id": building_id,
				"position": data.position,
				"hp_percent": data.get_hp_percent(),
				"ree_remaining": _calculate_building_ree(data)
			})

	return damaged


## Get list of ALL buildings that can be salvaged (including intact ones).
## Used by harvesters to actively demolish buildings for REE.
## Returns array of dictionaries with building info.
func get_all_salvageable_buildings() -> Array:
	var salvageable: Array = []

	for building_id in _buildings.keys():
		var data: BuildingData = _buildings[building_id]
		# Include any building with HP > 0
		if data.current_hp > 0:
			salvageable.append({
				"id": building_id,
				"position": data.position,
				"hp_percent": data.get_hp_percent(),
				"ree_remaining": _calculate_building_ree(data)
			})

	return salvageable


## Check if a building can be salvaged (exists and has HP).
func is_building_salvageable(building_id: int) -> bool:
	if not _buildings.has(building_id):
		return false
	var data: BuildingData = _buildings[building_id]
	return data.current_hp > 0


## Calculate remaining REE in a building based on HP.
func _calculate_building_ree(data: BuildingData) -> float:
	var base_ree: float = BUILDING_REE_DROPS.get(data.type, 10.0)
	var hp_percent: float = data.get_hp_percent() / 100.0
	return base_ree * hp_percent


## Salvage a building - extract REE and reduce its HP.
## Returns dictionary with ree amount extracted and whether building was destroyed.
func salvage_building(building_id: int, salvage_amount: float) -> Dictionary:
	if not _buildings.has(building_id):
		return {"ree": 0.0, "destroyed": false}

	var data: BuildingData = _buildings[building_id]

	# Calculate how much REE per HP
	var base_ree: float = BUILDING_REE_DROPS.get(data.type, 10.0)
	var ree_per_hp: float = base_ree / data.max_hp

	# Calculate damage to deal for requested salvage amount
	var hp_to_remove: float = salvage_amount / ree_per_hp
	var actual_hp_removed: float = minf(hp_to_remove, data.current_hp)
	var ree_extracted: float = actual_hp_removed * ree_per_hp

	# Deal damage to the building
	data.current_hp -= actual_hp_removed

	# Update visual damage state
	var hp_percent: float = data.get_hp_percent()
	var old_state: int = data.damage_state

	if data.current_hp <= 0:
		# Building destroyed by salvage
		_cleanup_building_particles(data)
		_destroy_building(building_id)
		return {"ree": ree_extracted, "destroyed": true}
	elif hp_percent < 33:
		data.damage_state = 2  # Critical
	elif hp_percent < 66:
		data.damage_state = 1  # Damaged
	else:
		data.damage_state = 0  # Intact

	# Update visual if state changed
	if data.damage_state != old_state:
		_update_building_visual(data)
		_update_building_fire_effects(data)

	# Update health bar
	_update_building_health_bar(data)

	building_damaged.emit(building_id, hp_percent)
	return {"ree": ree_extracted, "destroyed": false}


## Add lit windows to a building.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D with cached materials instead of CSG.
func _add_building_windows(body: Node3D, size: Vector3, building_type: int) -> void:
	# Use cached materials (created once in _initialize_cached_meshes)
	var window_mat: StandardMaterial3D = _cached_window_lit_mat
	var dark_window_mat: StandardMaterial3D = _cached_window_dark_mat

	# Calculate window grid
	var floor_height := 3.0
	var num_floors := int(size.y / floor_height)
	var windows_per_side := maxi(1, int(size.x / 3.0))

	# Window dimensions
	var window_width := minf(1.2, size.x / (windows_per_side + 1))
	var window_height := 1.5
	var window_depth := 0.15

	# Add windows to front and back faces (Z axis)
	for floor_idx in range(num_floors):
		var floor_y: float = -size.y / 2.0 + (floor_idx + 0.5) * floor_height + 0.5

		for w in range(windows_per_side):
			var window_x: float = -size.x / 2.0 + (w + 1) * (size.x / (windows_per_side + 1))

			# Randomly lit or dark
			var is_lit: bool = randf() < 0.4
			var mat: StandardMaterial3D = window_mat if is_lit else dark_window_mat

			# Front face windows - PERFORMANCE: MeshInstance3D instead of CSGBox3D
			var front_window := MeshInstance3D.new()
			var front_box := BoxMesh.new()
			front_box.size = Vector3(window_width, window_height, window_depth)
			front_window.mesh = front_box
			front_window.position = Vector3(window_x, floor_y, size.z / 2.0 + 0.05)
			front_window.set_surface_override_material(0, mat)
			body.add_child(front_window)

			# Back face windows (different lit pattern)
			is_lit = randf() < 0.35
			mat = window_mat if is_lit else dark_window_mat
			var back_window := MeshInstance3D.new()
			var back_box := BoxMesh.new()
			back_box.size = Vector3(window_width, window_height, window_depth)
			back_window.mesh = back_box
			back_window.position = Vector3(window_x, floor_y, -size.z / 2.0 - 0.05)
			back_window.set_surface_override_material(0, mat)
			body.add_child(back_window)

	# Add windows to side faces (X axis) for larger buildings
	if size.z > 6.0:
		var side_windows := maxi(1, int(size.z / 3.5))
		for floor_idx in range(num_floors):
			var floor_y: float = -size.y / 2.0 + (floor_idx + 0.5) * floor_height + 0.5

			for w in range(side_windows):
				var window_z: float = -size.z / 2.0 + (w + 1) * (size.z / (side_windows + 1))
				var is_lit: bool = randf() < 0.35
				var mat: StandardMaterial3D = window_mat if is_lit else dark_window_mat

				# Left side - PERFORMANCE: MeshInstance3D instead of CSGBox3D
				var left_window := MeshInstance3D.new()
				var left_box := BoxMesh.new()
				left_box.size = Vector3(window_depth, window_height, window_width)
				left_window.mesh = left_box
				left_window.position = Vector3(-size.x / 2.0 - 0.05, floor_y, window_z)
				left_window.set_surface_override_material(0, mat)
				body.add_child(left_window)

				# Right side
				is_lit = randf() < 0.35
				mat = window_mat if is_lit else dark_window_mat
				var right_window := MeshInstance3D.new()
				var right_box := BoxMesh.new()
				right_box.size = Vector3(window_depth, window_height, window_width)
				right_window.mesh = right_box
				right_window.position = Vector3(size.x / 2.0 + 0.05, floor_y, window_z)
				right_window.set_surface_override_material(0, mat)
				body.add_child(right_window)


## Add rooftop details (AC units, antennas, etc.)
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D with cached materials instead of CSG.
func _add_rooftop_details(body: Node3D, size: Vector3, building_type: int) -> void:
	var roof_y: float = size.y / 2.0

	# Use cached AC material
	var ac_mat: StandardMaterial3D = _cached_ac_mat

	# Add AC units - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var num_ac := randi_range(1, 3)
	for i in range(num_ac):
		var ac := MeshInstance3D.new()
		var ac_size := Vector3(randf_range(1.5, 2.5), randf_range(1.0, 1.5), randf_range(1.5, 2.5))
		var ac_box := BoxMesh.new()
		ac_box.size = ac_size
		ac.mesh = ac_box
		ac.position = Vector3(
			randf_range(-size.x / 3.0, size.x / 3.0),
			roof_y + ac_size.y / 2.0,
			randf_range(-size.z / 3.0, size.z / 3.0)
		)
		ac.set_surface_override_material(0, ac_mat)
		body.add_child(ac)

	# Add antenna for taller buildings - PERFORMANCE: MeshInstance3D instead of CSGCylinder3D
	if size.y > 15.0 and randf() < 0.5:
		var antenna_mat: StandardMaterial3D = _cached_antenna_mat
		var antenna_height := randf_range(3.0, 6.0)

		var antenna := MeshInstance3D.new()
		var antenna_cyl := CylinderMesh.new()
		antenna_cyl.top_radius = 0.15
		antenna_cyl.bottom_radius = 0.15
		antenna_cyl.height = antenna_height
		antenna.mesh = antenna_cyl
		var antenna_pos := Vector3(
			randf_range(-size.x / 4.0, size.x / 4.0),
			roof_y + antenna_height / 2.0,
			randf_range(-size.z / 4.0, size.z / 4.0)
		)
		antenna.position = antenna_pos
		antenna.set_surface_override_material(0, antenna_mat)
		body.add_child(antenna)

		# Red warning light on top - PERFORMANCE: MeshInstance3D instead of CSGSphere3D
		var light := MeshInstance3D.new()
		var light_sphere := SphereMesh.new()
		light_sphere.radius = 0.3
		light_sphere.height = 0.6
		light.mesh = light_sphere
		light.position = antenna_pos + Vector3(0, antenna_height / 2.0 + 0.2, 0)
		# Create red warning light material (not cached since it's rare)
		var light_mat := StandardMaterial3D.new()
		light_mat.albedo_color = Color(1.0, 0.2, 0.1)
		light_mat.emission_enabled = true
		light_mat.emission = Color(1.0, 0.1, 0.0)
		light_mat.emission_energy_multiplier = 2.0
		light.set_surface_override_material(0, light_mat)
		body.add_child(light)

	# Add water tank for industrial buildings - PERFORMANCE: MeshInstance3D instead of CSGCylinder3D
	if building_type >= 7 and building_type <= 12 and randf() < 0.4:
		var tank_mat: StandardMaterial3D = _cached_tank_mat
		var tank_radius := randf_range(1.5, 2.5)
		var tank_height := randf_range(2.0, 4.0)

		var tank := MeshInstance3D.new()
		var tank_cyl := CylinderMesh.new()
		tank_cyl.top_radius = tank_radius
		tank_cyl.bottom_radius = tank_radius
		tank_cyl.height = tank_height
		tank.mesh = tank_cyl
		tank.position = Vector3(
			randf_range(-size.x / 4.0, size.x / 4.0),
			roof_y + tank_height / 2.0,
			randf_range(-size.z / 4.0, size.z / 4.0)
		)
		tank.set_surface_override_material(0, tank_mat)
		body.add_child(tank)


## Add street lamp at position with zone-specific coloring.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D with cached materials instead of CSG.
func _add_street_lamp(pos: Vector3, zone_type: int = -1) -> void:
	var lamp := Node3D.new()
	lamp.position = pos

	# Use cached pole material
	var pole_mat: StandardMaterial3D = _cached_pole_mat

	# Pole - PERFORMANCE: MeshInstance3D instead of CSGCylinder3D
	var pole := MeshInstance3D.new()
	var pole_cyl := CylinderMesh.new()
	pole_cyl.top_radius = 0.15
	pole_cyl.bottom_radius = 0.15
	pole_cyl.height = 6.0
	pole.mesh = pole_cyl
	pole.position.y = 3.0
	pole.set_surface_override_material(0, pole_mat)
	lamp.add_child(pole)

	# Arm extending out - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var arm := MeshInstance3D.new()
	var arm_box := BoxMesh.new()
	arm_box.size = Vector3(2.0, 0.1, 0.1)
	arm.mesh = arm_box
	arm.position = Vector3(1.0, 5.8, 0)
	arm.set_surface_override_material(0, pole_mat)
	lamp.add_child(arm)

	# Light fixture - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var fixture := MeshInstance3D.new()
	var fixture_box := BoxMesh.new()
	fixture_box.size = Vector3(0.8, 0.3, 0.4)
	fixture.mesh = fixture_box
	fixture.position = Vector3(1.8, 5.6, 0)
	fixture.set_surface_override_material(0, pole_mat)
	lamp.add_child(fixture)

	# Light glow - zone-specific color if zone provided
	var glow_color: Color
	if zone_type >= 0 and ZONE_COLORS.has(zone_type):
		glow_color = ZONE_COLORS[zone_type]
	else:
		glow_color = Color(1.0, 0.9, 0.7)  # Default warm yellow

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = glow_color
	glow_mat.emission_enabled = true
	glow_mat.emission = glow_color
	glow_mat.emission_energy_multiplier = 1.5

	var light_glow := MeshInstance3D.new()
	var glow_sphere := SphereMesh.new()
	glow_sphere.radius = 0.25
	glow_sphere.height = 0.5
	light_glow.mesh = glow_sphere
	light_glow.position = Vector3(1.8, 5.4, 0)
	light_glow.set_surface_override_material(0, glow_mat)
	lamp.add_child(light_glow)

	_streets_container.add_child(lamp)


## Add parked vehicle at position.
func _add_parked_vehicle(pos: Vector3, rotation_y: float, is_truck: bool = false) -> void:
	var vehicle := Node3D.new()
	vehicle.position = pos
	vehicle.rotation.y = rotation_y

	if is_truck:
		_create_truck(vehicle)
	else:
		_create_car(vehicle)

	_streets_container.add_child(vehicle)


## Create a parked car.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSG.
func _create_car(parent: Node3D) -> void:
	# Random car colors
	var car_colors := [
		Color(0.7, 0.1, 0.1),   # Red
		Color(0.1, 0.2, 0.6),   # Blue
		Color(0.15, 0.15, 0.15), # Black
		Color(0.85, 0.85, 0.85), # White
		Color(0.6, 0.6, 0.6),   # Silver
		Color(0.2, 0.4, 0.2),   # Green
	]
	var car_color: Color = car_colors[randi() % car_colors.size()]

	# Body material
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = car_color
	body_mat.metallic = 0.6
	body_mat.roughness = 0.3

	# Main body - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(1.8, 0.8, 4.0)
	body.mesh = body_box
	body.position.y = 0.6
	body.set_surface_override_material(0, body_mat)
	parent.add_child(body)

	# Cabin/roof - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var cabin := MeshInstance3D.new()
	var cabin_box := BoxMesh.new()
	cabin_box.size = Vector3(1.6, 0.6, 2.0)
	cabin.mesh = cabin_box
	cabin.position = Vector3(0, 1.2, -0.3)
	cabin.set_surface_override_material(0, body_mat)
	parent.add_child(cabin)

	# Windows (dark)
	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.1, 0.15, 0.2)
	window_mat.metallic = 0.3
	window_mat.roughness = 0.1

	# Windshield - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var windshield := MeshInstance3D.new()
	var ws_box := BoxMesh.new()
	ws_box.size = Vector3(1.5, 0.5, 0.1)
	windshield.mesh = ws_box
	windshield.position = Vector3(0, 1.1, 0.75)
	windshield.rotation.x = -0.3
	windshield.set_surface_override_material(0, window_mat)
	parent.add_child(windshield)

	# Wheels (black cylinders)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.1, 0.1, 0.1)
	wheel_mat.roughness = 0.9

	var wheel_positions := [
		Vector3(-0.9, 0.3, 1.2),
		Vector3(0.9, 0.3, 1.2),
		Vector3(-0.9, 0.3, -1.2),
		Vector3(0.9, 0.3, -1.2)
	]

	for wp in wheel_positions:
		# PERFORMANCE: MeshInstance3D instead of CSGCylinder3D
		var wheel := MeshInstance3D.new()
		var wheel_cyl := CylinderMesh.new()
		wheel_cyl.top_radius = 0.35
		wheel_cyl.bottom_radius = 0.35
		wheel_cyl.height = 0.25
		wheel.mesh = wheel_cyl
		wheel.rotation.z = PI / 2
		wheel.position = wp
		wheel.set_surface_override_material(0, wheel_mat)
		parent.add_child(wheel)

	# Headlights
	var headlight_mat := StandardMaterial3D.new()
	headlight_mat.albedo_color = Color(1.0, 1.0, 0.9)
	headlight_mat.emission_enabled = true
	headlight_mat.emission = Color(1.0, 0.95, 0.8)
	headlight_mat.emission_energy_multiplier = 0.3

	for side in [-0.6, 0.6]:
		# PERFORMANCE: MeshInstance3D instead of CSGBox3D
		var headlight := MeshInstance3D.new()
		var hl_box := BoxMesh.new()
		hl_box.size = Vector3(0.3, 0.2, 0.1)
		headlight.mesh = hl_box
		headlight.position = Vector3(side, 0.5, 2.0)
		headlight.set_surface_override_material(0, headlight_mat)
		parent.add_child(headlight)

	# Taillights (red)
	var taillight_mat := StandardMaterial3D.new()
	taillight_mat.albedo_color = Color(0.8, 0.1, 0.1)
	taillight_mat.emission_enabled = true
	taillight_mat.emission = Color(0.8, 0.0, 0.0)
	taillight_mat.emission_energy_multiplier = 0.4

	for side in [-0.7, 0.7]:
		# PERFORMANCE: MeshInstance3D instead of CSGBox3D
		var taillight := MeshInstance3D.new()
		var tl_box := BoxMesh.new()
		tl_box.size = Vector3(0.25, 0.15, 0.1)
		taillight.mesh = tl_box
		taillight.position = Vector3(side, 0.6, -2.0)
		taillight.set_surface_override_material(0, taillight_mat)
		parent.add_child(taillight)


## Create a parked truck/van.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSG.
func _create_truck(parent: Node3D) -> void:
	var truck_colors := [
		Color(0.85, 0.85, 0.85),  # White
		Color(0.2, 0.3, 0.5),     # Blue
		Color(0.6, 0.4, 0.2),     # Brown/tan
		Color(0.15, 0.15, 0.15),  # Black
	]
	var truck_color: Color = truck_colors[randi() % truck_colors.size()]

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = truck_color
	body_mat.metallic = 0.3
	body_mat.roughness = 0.5

	# Cab - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var cab := MeshInstance3D.new()
	var cab_box := BoxMesh.new()
	cab_box.size = Vector3(2.0, 1.8, 2.0)
	cab.mesh = cab_box
	cab.position = Vector3(0, 1.1, 2.0)
	cab.set_surface_override_material(0, body_mat)
	parent.add_child(cab)

	# Cargo area - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var cargo := MeshInstance3D.new()
	var cargo_box := BoxMesh.new()
	cargo_box.size = Vector3(2.2, 2.2, 4.0)
	cargo.mesh = cargo_box
	cargo.position = Vector3(0, 1.3, -1.0)
	cargo.set_surface_override_material(0, body_mat)
	parent.add_child(cargo)

	# Wheels
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.1, 0.1, 0.1)
	wheel_mat.roughness = 0.9

	var wheel_positions := [
		Vector3(-1.0, 0.4, 2.0),
		Vector3(1.0, 0.4, 2.0),
		Vector3(-1.0, 0.4, -1.5),
		Vector3(1.0, 0.4, -1.5),
		Vector3(-1.0, 0.4, -2.5),
		Vector3(1.0, 0.4, -2.5)
	]

	for wp in wheel_positions:
		# PERFORMANCE: MeshInstance3D instead of CSGCylinder3D
		var wheel := MeshInstance3D.new()
		var wheel_cyl := CylinderMesh.new()
		wheel_cyl.top_radius = 0.45
		wheel_cyl.bottom_radius = 0.45
		wheel_cyl.height = 0.3
		wheel.mesh = wheel_cyl
		wheel.rotation.z = PI / 2
		wheel.position = wp
		wheel.set_surface_override_material(0, wheel_mat)
		parent.add_child(wheel)

	# Windows
	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.1, 0.15, 0.2)
	window_mat.metallic = 0.3

	# Windshield - PERFORMANCE: MeshInstance3D instead of CSGBox3D
	var windshield := MeshInstance3D.new()
	var ws_box := BoxMesh.new()
	ws_box.size = Vector3(1.8, 0.8, 0.1)
	windshield.mesh = ws_box
	windshield.position = Vector3(0, 1.6, 3.0)
	windshield.set_surface_override_material(0, window_mat)
	parent.add_child(windshield)


## Add park details like trees and benches.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D with simple meshes.
func _add_park_details(body: Node3D, size: Vector3) -> void:
	# Tree trunk material
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
	trunk_mat.roughness = 0.9

	# Tree foliage material
	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.15, 0.45, 0.15)
	foliage_mat.roughness = 0.8

	# Bench material
	var bench_mat := StandardMaterial3D.new()
	bench_mat.albedo_color = Color(0.4, 0.3, 0.2)
	bench_mat.roughness = 0.7

	# Metal bench legs
	var bench_metal_mat := StandardMaterial3D.new()
	bench_metal_mat.albedo_color = Color(0.25, 0.25, 0.28)
	bench_metal_mat.metallic = 0.7
	bench_metal_mat.roughness = 0.4

	# Calculate how many trees based on park size
	var park_area := size.x * size.z
	var num_trees := maxi(1, int(park_area / 80.0))
	num_trees = mini(num_trees, 8)  # Cap at 8 trees per park

	# Add trees
	for i in range(num_trees):
		var tree_x := randf_range(-size.x / 2.5, size.x / 2.5)
		var tree_z := randf_range(-size.z / 2.5, size.z / 2.5)
		var tree_scale := randf_range(0.8, 1.4)

		_create_tree(body, Vector3(tree_x, size.y / 2.0, tree_z), tree_scale, trunk_mat, foliage_mat)

	# Add benches (1-2 per park)
	var num_benches := randi_range(1, 2)
	for i in range(num_benches):
		var bench_x := randf_range(-size.x / 3.0, size.x / 3.0)
		var bench_z := randf_range(-size.z / 3.0, size.z / 3.0)
		var bench_rot := randf_range(0, PI * 2)

		_create_bench(body, Vector3(bench_x, size.y / 2.0, bench_z), bench_rot, bench_mat, bench_metal_mat)

	# Add a trash bin
	if randf() < 0.7:
		var bin_x := randf_range(-size.x / 3.0, size.x / 3.0)
		var bin_z := randf_range(-size.z / 3.0, size.z / 3.0)
		_create_trash_bin(body, Vector3(bin_x, size.y / 2.0, bin_z))


## Create a tree at position.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSG.
func _create_tree(parent: Node3D, pos: Vector3, tree_scale: float, trunk_mat: StandardMaterial3D, foliage_mat: StandardMaterial3D) -> void:
	var tree := Node3D.new()
	tree.position = pos

	# Tree trunk
	var trunk := MeshInstance3D.new()
	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.top_radius = 0.25 * tree_scale
	trunk_cyl.bottom_radius = 0.35 * tree_scale
	trunk_cyl.height = 3.0 * tree_scale
	trunk.mesh = trunk_cyl
	trunk.position.y = 1.5 * tree_scale
	trunk.set_surface_override_material(0, trunk_mat)
	tree.add_child(trunk)

	# Tree foliage (use sphere for simplicity, looks like a cartoon tree)
	var foliage := MeshInstance3D.new()
	var foliage_sphere := SphereMesh.new()
	foliage_sphere.radius = 2.0 * tree_scale
	foliage_sphere.height = 3.5 * tree_scale
	foliage.mesh = foliage_sphere
	foliage.position.y = 4.0 * tree_scale
	foliage.set_surface_override_material(0, foliage_mat)
	tree.add_child(foliage)

	# Add some variation with a second smaller foliage cluster
	if randf() < 0.6:
		var foliage2 := MeshInstance3D.new()
		var foliage2_sphere := SphereMesh.new()
		foliage2_sphere.radius = 1.2 * tree_scale
		foliage2_sphere.height = 2.0 * tree_scale
		foliage2.mesh = foliage2_sphere
		foliage2.position = Vector3(randf_range(-0.8, 0.8), 3.0, randf_range(-0.8, 0.8)) * tree_scale
		foliage2.set_surface_override_material(0, foliage_mat)
		tree.add_child(foliage2)

	parent.add_child(tree)


## Create a park bench.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSG.
func _create_bench(parent: Node3D, pos: Vector3, rotation_y: float, wood_mat: StandardMaterial3D, metal_mat: StandardMaterial3D) -> void:
	var bench := Node3D.new()
	bench.position = pos
	bench.rotation.y = rotation_y

	# Seat
	var seat := MeshInstance3D.new()
	var seat_box := BoxMesh.new()
	seat_box.size = Vector3(1.8, 0.1, 0.5)
	seat.mesh = seat_box
	seat.position.y = 0.45
	seat.set_surface_override_material(0, wood_mat)
	bench.add_child(seat)

	# Backrest
	var back := MeshInstance3D.new()
	var back_box := BoxMesh.new()
	back_box.size = Vector3(1.8, 0.5, 0.08)
	back.mesh = back_box
	back.position = Vector3(0, 0.7, -0.22)
	back.rotation.x = -0.15
	back.set_surface_override_material(0, wood_mat)
	bench.add_child(back)

	# Legs (metal)
	for side in [-0.7, 0.7]:
		var leg := MeshInstance3D.new()
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.08, 0.45, 0.4)
		leg.mesh = leg_box
		leg.position = Vector3(side, 0.225, 0)
		leg.set_surface_override_material(0, metal_mat)
		bench.add_child(leg)

	parent.add_child(bench)


## Create a trash bin.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSG.
func _create_trash_bin(parent: Node3D, pos: Vector3) -> void:
	var bin := Node3D.new()
	bin.position = pos

	# Bin body (green cylinder)
	var bin_mat := StandardMaterial3D.new()
	bin_mat.albedo_color = Color(0.15, 0.35, 0.15)
	bin_mat.roughness = 0.7

	var body := MeshInstance3D.new()
	var body_cyl := CylinderMesh.new()
	body_cyl.top_radius = 0.35
	body_cyl.bottom_radius = 0.3
	body_cyl.height = 0.9
	body.mesh = body_cyl
	body.position.y = 0.45
	body.set_surface_override_material(0, bin_mat)
	bin.add_child(body)

	# Bin rim (darker)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.1, 0.25, 0.1)
	rim_mat.roughness = 0.6

	var rim := MeshInstance3D.new()
	var rim_cyl := CylinderMesh.new()
	rim_cyl.top_radius = 0.38
	rim_cyl.bottom_radius = 0.38
	rim_cyl.height = 0.08
	rim.mesh = rim_cyl
	rim.position.y = 0.92
	rim.set_surface_override_material(0, rim_mat)
	bin.add_child(rim)

	parent.add_child(bin)


## Add a billboard to a commercial building.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSG.
func _add_billboard(body: Node3D, size: Vector3) -> void:
	# Billboard colors (neon-ish)
	var billboard_colors := [
		Color(0.9, 0.2, 0.2),   # Red
		Color(0.2, 0.7, 0.9),   # Cyan
		Color(0.9, 0.8, 0.2),   # Yellow
		Color(0.5, 0.2, 0.8),   # Purple
		Color(0.2, 0.9, 0.4),   # Green
	]
	var color: Color = billboard_colors[randi() % billboard_colors.size()]

	# Billboard frame material
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.2, 0.2, 0.22)
	frame_mat.metallic = 0.6
	frame_mat.roughness = 0.5

	# Billboard face material (emissive)
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = color
	face_mat.emission_enabled = true
	face_mat.emission = color
	face_mat.emission_energy_multiplier = 1.5

	# Determine billboard size based on building
	var bb_width := minf(size.x * 0.8, 6.0)
	var bb_height := minf(3.0, size.y * 0.2)

	# Position at top of building, on front face
	var bb_y: float = size.y * 0.35  # Upper portion of building
	var bb_z: float = size.z / 2.0 + 0.3

	var billboard := Node3D.new()
	billboard.position = Vector3(0, bb_y, bb_z)

	# Frame
	var frame := MeshInstance3D.new()
	var frame_box := BoxMesh.new()
	frame_box.size = Vector3(bb_width + 0.3, bb_height + 0.3, 0.15)
	frame.mesh = frame_box
	frame.set_surface_override_material(0, frame_mat)
	billboard.add_child(frame)

	# Face (lit panel)
	var face := MeshInstance3D.new()
	var face_box := BoxMesh.new()
	face_box.size = Vector3(bb_width, bb_height, 0.1)
	face.mesh = face_box
	face.position.z = 0.1
	face.set_surface_override_material(0, face_mat)
	billboard.add_child(face)

	# Support poles
	for side in [-bb_width / 2.5, bb_width / 2.5]:
		var pole := MeshInstance3D.new()
		var pole_cyl := CylinderMesh.new()
		pole_cyl.top_radius = 0.08
		pole_cyl.bottom_radius = 0.08
		pole_cyl.height = bb_height + 0.5
		pole.mesh = pole_cyl
		pole.position = Vector3(side, -(bb_height + 0.5) / 2.0 + 0.1, -0.1)
		pole.set_surface_override_material(0, frame_mat)
		billboard.add_child(pole)

	body.add_child(billboard)


## Add a street bench at position.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSG.
func _add_street_bench(pos: Vector3, rotation_y: float) -> void:
	var bench := Node3D.new()
	bench.position = pos
	bench.rotation.y = rotation_y

	# Bench materials
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.3, 0.2)
	wood_mat.roughness = 0.7

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.25, 0.25, 0.28)
	metal_mat.metallic = 0.7
	metal_mat.roughness = 0.4

	# Seat
	var seat := MeshInstance3D.new()
	var seat_box := BoxMesh.new()
	seat_box.size = Vector3(1.8, 0.1, 0.5)
	seat.mesh = seat_box
	seat.position.y = 0.45
	seat.set_surface_override_material(0, wood_mat)
	bench.add_child(seat)

	# Backrest
	var back := MeshInstance3D.new()
	var back_box := BoxMesh.new()
	back_box.size = Vector3(1.8, 0.5, 0.08)
	back.mesh = back_box
	back.position = Vector3(0, 0.7, -0.22)
	back.rotation.x = -0.15
	back.set_surface_override_material(0, wood_mat)
	bench.add_child(back)

	# Legs (metal)
	for side in [-0.7, 0.7]:
		var leg := MeshInstance3D.new()
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.08, 0.45, 0.4)
		leg.mesh = leg_box
		leg.position = Vector3(side, 0.225, 0)
		leg.set_surface_override_material(0, metal_mat)
		bench.add_child(leg)

	_streets_container.add_child(bench)


## Add a street trash bin at position.
## PERFORMANCE OPTIMIZED: Uses MeshInstance3D instead of CSG.
func _add_street_trash_bin(pos: Vector3) -> void:
	var bin := Node3D.new()
	bin.position = pos

	# Bin body (dark gray metal)
	var bin_mat := StandardMaterial3D.new()
	bin_mat.albedo_color = Color(0.25, 0.27, 0.3)
	bin_mat.metallic = 0.5
	bin_mat.roughness = 0.6

	var body := MeshInstance3D.new()
	var body_cyl := CylinderMesh.new()
	body_cyl.top_radius = 0.3
	body_cyl.bottom_radius = 0.28
	body_cyl.height = 0.8
	body.mesh = body_cyl
	body.position.y = 0.4
	body.set_surface_override_material(0, bin_mat)
	bin.add_child(body)

	# Dome lid
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.2, 0.22, 0.25)
	lid_mat.metallic = 0.6

	var lid := MeshInstance3D.new()
	var lid_sphere := SphereMesh.new()
	lid_sphere.radius = 0.32
	lid_sphere.height = 0.3
	lid_sphere.is_hemisphere = true
	lid.mesh = lid_sphere
	lid.position.y = 0.82
	lid.set_surface_override_material(0, lid_mat)
	bin.add_child(lid)

	_streets_container.add_child(bin)


# =============================================================================
# ADDITIONAL URBAN ASSETS - Nature & Street Props
# =============================================================================

## Add a bush/shrub at position.
var _bush_count: int = 0
var _urban_prop_count: int = 0

func _add_bush(pos: Vector3, bush_type: int = 0) -> void:
	_bush_count += 1
	var bush := Node3D.new()
	bush.name = "Bush_%d" % _bush_count
	bush.position = pos

	# Bush foliage material (visible green)
	var bush_mat := StandardMaterial3D.new()
	var green_variants := [
		Color(0.18, 0.5, 0.14),   # Medium green
		Color(0.22, 0.55, 0.18),  # Grass green
		Color(0.25, 0.6, 0.2),    # Light green
		Color(0.2, 0.52, 0.16),   # Forest green
	]
	bush_mat.albedo_color = green_variants[bush_type % green_variants.size()]
	bush_mat.roughness = 0.8

	# Reasonable sizes for RTS view (1.5x original)
	match bush_type % 3:
		0:  # Round bush
			var foliage := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = randf_range(1.0, 1.5)
			sphere.height = randf_range(1.6, 2.4)
			foliage.mesh = sphere
			foliage.position.y = sphere.height / 2.0
			foliage.set_surface_override_material(0, bush_mat)
			bush.add_child(foliage)
		1:  # Multi-cluster bush (simplified to 2 clusters for perf)
			for i in range(2):
				var cluster := MeshInstance3D.new()
				var cluster_sphere := SphereMesh.new()
				cluster_sphere.radius = randf_range(0.7, 1.1)
				cluster_sphere.height = randf_range(1.2, 1.8)
				cluster.mesh = cluster_sphere
				cluster.position = Vector3(
					randf_range(-0.7, 0.7),
					cluster_sphere.height / 2.0,
					randf_range(-0.7, 0.7)
				)
				cluster.set_surface_override_material(0, bush_mat)
				bush.add_child(cluster)
		2:  # Low spreading bush
			var spread := MeshInstance3D.new()
			var spread_mesh := SphereMesh.new()
			spread_mesh.radius = randf_range(1.2, 1.8)
			spread_mesh.height = randf_range(0.8, 1.2)
			spread.mesh = spread_mesh
			spread.position.y = spread_mesh.height / 2.0
			spread.set_surface_override_material(0, bush_mat)
			bush.add_child(spread)

	_streets_container.add_child(bush)


## Add a fire hydrant at position.
func _add_fire_hydrant(pos: Vector3) -> void:
	var hydrant := Node3D.new()
	hydrant.position = pos

	# Red hydrant material (no emission for perf)
	var red_mat := StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.85, 0.18, 0.12)
	red_mat.metallic = 0.3
	red_mat.roughness = 0.5

	# Silver cap material
	var silver_mat := StandardMaterial3D.new()
	silver_mat.albedo_color = Color(0.75, 0.77, 0.8)
	silver_mat.metallic = 0.7
	silver_mat.roughness = 0.3

	# Main body - reasonable size (1.5x original)
	var body := MeshInstance3D.new()
	var body_cyl := CylinderMesh.new()
	body_cyl.top_radius = 0.27
	body_cyl.bottom_radius = 0.33
	body_cyl.height = 1.05
	body.mesh = body_cyl
	body.position.y = 0.525
	body.set_surface_override_material(0, red_mat)
	hydrant.add_child(body)

	# Top cap
	var cap := MeshInstance3D.new()
	var cap_cyl := CylinderMesh.new()
	cap_cyl.top_radius = 0.18
	cap_cyl.bottom_radius = 0.22
	cap_cyl.height = 0.22
	cap.mesh = cap_cyl
	cap.position.y = 1.17
	cap.set_surface_override_material(0, silver_mat)
	hydrant.add_child(cap)

	# Side outlet (simplified - just one visual indicator)
	var outlet := MeshInstance3D.new()
	var outlet_cyl := CylinderMesh.new()
	outlet_cyl.top_radius = 0.09
	outlet_cyl.bottom_radius = 0.09
	outlet_cyl.height = 0.18
	outlet.mesh = outlet_cyl
	outlet.position = Vector3(0.3, 0.65, 0)
	outlet.rotation.z = PI / 2
	outlet.set_surface_override_material(0, silver_mat)
	hydrant.add_child(outlet)

	_streets_container.add_child(hydrant)


## Add a mailbox at position.
func _add_mailbox(pos: Vector3, rotation_y: float = 0) -> void:
	var mailbox := Node3D.new()
	mailbox.position = pos
	mailbox.rotation.y = rotation_y

	# Blue mailbox material
	var blue_mat := StandardMaterial3D.new()
	blue_mat.albedo_color = Color(0.15, 0.25, 0.55)
	blue_mat.metallic = 0.4
	blue_mat.roughness = 0.5

	# Post
	var post := MeshInstance3D.new()
	var post_cyl := CylinderMesh.new()
	post_cyl.top_radius = 0.08
	post_cyl.bottom_radius = 0.08
	post_cyl.height = 1.0
	post.mesh = post_cyl
	post.position.y = 0.5
	post.set_surface_override_material(0, blue_mat)
	mailbox.add_child(post)

	# Box body
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.4, 0.5, 0.35)
	box.mesh = box_mesh
	box.position.y = 1.25
	box.set_surface_override_material(0, blue_mat)
	mailbox.add_child(box)

	# Slot (darker)
	var slot_mat := StandardMaterial3D.new()
	slot_mat.albedo_color = Color(0.05, 0.08, 0.15)

	var slot := MeshInstance3D.new()
	var slot_box := BoxMesh.new()
	slot_box.size = Vector3(0.25, 0.03, 0.02)
	slot.mesh = slot_box
	slot.position = Vector3(0, 1.35, 0.18)
	slot.set_surface_override_material(0, slot_mat)
	mailbox.add_child(slot)

	_streets_container.add_child(mailbox)


## Add a newspaper box at position.
func _add_newspaper_box(pos: Vector3) -> void:
	var newsbox := Node3D.new()
	newsbox.position = pos

	# Box colors (various newspaper brands)
	var box_colors := [
		Color(0.75, 0.2, 0.15),   # Red
		Color(0.2, 0.35, 0.6),    # Blue
		Color(0.7, 0.55, 0.1),    # Yellow/gold
		Color(0.2, 0.5, 0.25),    # Green
	]
	var color: Color = box_colors[randi() % box_colors.size()]

	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = color
	box_mat.metallic = 0.4
	box_mat.roughness = 0.5

	# Main box body
	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.45, 1.0, 0.4)
	body.mesh = body_box
	body.position.y = 0.5
	body.set_surface_override_material(0, box_mat)
	newsbox.add_child(body)

	# Window (glass-like)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.6, 0.65, 0.7, 0.7)
	glass_mat.metallic = 0.2
	glass_mat.roughness = 0.1

	var window := MeshInstance3D.new()
	var window_box := BoxMesh.new()
	window_box.size = Vector3(0.35, 0.35, 0.02)
	window.mesh = window_box
	window.position = Vector3(0, 0.7, 0.21)
	window.set_surface_override_material(0, glass_mat)
	newsbox.add_child(window)

	_streets_container.add_child(newsbox)


## Add a street planter at position.
func _add_street_planter(pos: Vector3, planter_type: int = 0) -> void:
	var planter := Node3D.new()
	planter.position = pos

	# Concrete planter material
	var concrete_mat := StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.55, 0.53, 0.5)
	concrete_mat.roughness = 0.85

	# Soil material
	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color(0.32, 0.23, 0.16)
	soil_mat.roughness = 0.95

	# Flower colors
	var flower_colors := [
		Color(0.9, 0.2, 0.3),
		Color(0.95, 0.8, 0.2),
		Color(0.6, 0.2, 0.7),
		Color(0.95, 0.5, 0.6),
		Color(0.95, 0.6, 0.2),
	]

	match planter_type % 3:
		0:  # Square planter
			var box := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(1.5, 0.75, 1.5)
			box.mesh = box_mesh
			box.position.y = 0.375
			box.set_surface_override_material(0, concrete_mat)
			planter.add_child(box)

			# Soil top
			var soil := MeshInstance3D.new()
			var soil_box := BoxMesh.new()
			soil_box.size = Vector3(1.3, 0.1, 1.3)
			soil.mesh = soil_box
			soil.position.y = 0.78
			soil.set_surface_override_material(0, soil_mat)
			planter.add_child(soil)

			_add_flowers_to_planter(planter, Vector3(0, 0.82, 0), 0.5, flower_colors)

		1:  # Round planter
			var cyl := MeshInstance3D.new()
			var cyl_mesh := CylinderMesh.new()
			cyl_mesh.top_radius = 0.8
			cyl_mesh.bottom_radius = 0.7
			cyl_mesh.height = 0.65
			cyl.mesh = cyl_mesh
			cyl.position.y = 0.325
			cyl.set_surface_override_material(0, concrete_mat)
			planter.add_child(cyl)

			# Soil top
			var soil := MeshInstance3D.new()
			var soil_cyl := CylinderMesh.new()
			soil_cyl.top_radius = 0.7
			soil_cyl.bottom_radius = 0.7
			soil_cyl.height = 0.1
			soil.mesh = soil_cyl
			soil.position.y = 0.68
			soil.set_surface_override_material(0, soil_mat)
			planter.add_child(soil)

			_add_flowers_to_planter(planter, Vector3(0, 0.72, 0), 0.45, flower_colors)

		2:  # Tall planter with small tree
			var box := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(1.2, 1.0, 1.2)
			box.mesh = box_mesh
			box.position.y = 0.5
			box.set_surface_override_material(0, concrete_mat)
			planter.add_child(box)

			# Add ornamental tree
			var trunk_mat := StandardMaterial3D.new()
			trunk_mat.albedo_color = Color(0.38, 0.28, 0.16)
			trunk_mat.roughness = 0.9

			var foliage_mat := StandardMaterial3D.new()
			foliage_mat.albedo_color = Color(0.2, 0.5, 0.16)
			foliage_mat.roughness = 0.8

			var trunk := MeshInstance3D.new()
			var trunk_cyl := CylinderMesh.new()
			trunk_cyl.top_radius = 0.1
			trunk_cyl.bottom_radius = 0.12
			trunk_cyl.height = 2.0
			trunk.mesh = trunk_cyl
			trunk.position.y = 2.0
			trunk.set_surface_override_material(0, trunk_mat)
			planter.add_child(trunk)

			var foliage := MeshInstance3D.new()
			var foliage_sphere := SphereMesh.new()
			foliage_sphere.radius = 0.9
			foliage_sphere.height = 1.5
			foliage.mesh = foliage_sphere
			foliage.position.y = 3.5
			foliage.set_surface_override_material(0, foliage_mat)
			planter.add_child(foliage)

	_streets_container.add_child(planter)


## Helper function to add flowers to a planter.
func _add_flowers_to_planter(parent: Node3D, base_pos: Vector3, radius: float, colors: Array) -> void:
	var num_flowers := randi_range(4, 8)
	for i in range(num_flowers):
		var flower := MeshInstance3D.new()
		var flower_sphere := SphereMesh.new()
		flower_sphere.radius = randf_range(0.08, 0.15)
		flower_sphere.height = flower_sphere.radius * 1.5
		flower.mesh = flower_sphere

		var angle := randf() * TAU
		var dist := randf() * radius
		flower.position = base_pos + Vector3(
			cos(angle) * dist,
			randf_range(0.1, 0.25),
			sin(angle) * dist
		)

		var flower_mat := StandardMaterial3D.new()
		flower_mat.albedo_color = colors[randi() % colors.size()]
		flower_mat.roughness = 0.7
		flower.set_surface_override_material(0, flower_mat)
		parent.add_child(flower)

	# Add some green foliage
	for i in range(randi_range(3, 5)):
		var leaf := MeshInstance3D.new()
		var leaf_sphere := SphereMesh.new()
		leaf_sphere.radius = randf_range(0.12, 0.2)
		leaf_sphere.height = leaf_sphere.radius * 0.8
		leaf.mesh = leaf_sphere

		var angle := randf() * TAU
		var dist := randf() * radius * 0.8
		leaf.position = base_pos + Vector3(
			cos(angle) * dist,
			randf_range(0.05, 0.15),
			sin(angle) * dist
		)

		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = Color(0.2, 0.45, 0.18)
		leaf_mat.roughness = 0.85
		leaf.set_surface_override_material(0, leaf_mat)
		parent.add_child(leaf)


## Add a hedge section at position.
func _add_hedge(pos: Vector3, length: float, rotation_y: float = 0) -> void:
	var hedge := Node3D.new()
	hedge.position = pos
	hedge.rotation.y = rotation_y

	var hedge_mat := StandardMaterial3D.new()
	hedge_mat.albedo_color = Color(0.15, 0.38, 0.12)
	hedge_mat.roughness = 0.85

	# Main hedge body (stretched box)
	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(length, 1.2, 0.8)
	body.mesh = body_box
	body.position.y = 0.6
	body.set_surface_override_material(0, hedge_mat)
	hedge.add_child(body)

	# Add some variation bumps on top
	for i in range(int(length / 1.5)):
		var bump := MeshInstance3D.new()
		var bump_sphere := SphereMesh.new()
		bump_sphere.radius = randf_range(0.3, 0.5)
		bump_sphere.height = randf_range(0.4, 0.6)
		bump.mesh = bump_sphere
		bump.position = Vector3(
			-length / 2 + 0.75 + i * 1.5 + randf_range(-0.3, 0.3),
			1.2 + randf_range(0, 0.1),
			randf_range(-0.2, 0.2)
		)
		bump.set_surface_override_material(0, hedge_mat)
		hedge.add_child(bump)

	_streets_container.add_child(hedge)


## Add a bollard at position.
func _add_bollard(pos: Vector3) -> void:
	var bollard := Node3D.new()
	bollard.position = pos

	var bollard_mat := StandardMaterial3D.new()
	bollard_mat.albedo_color = Color(0.3, 0.32, 0.35)
	bollard_mat.metallic = 0.6
	bollard_mat.roughness = 0.4

	# Main post
	var post := MeshInstance3D.new()
	var post_cyl := CylinderMesh.new()
	post_cyl.top_radius = 0.12
	post_cyl.bottom_radius = 0.15
	post_cyl.height = 0.9
	post.mesh = post_cyl
	post.position.y = 0.45
	post.set_surface_override_material(0, bollard_mat)
	bollard.add_child(post)

	# Reflective band
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.9, 0.85, 0.2)
	band_mat.emission_enabled = true
	band_mat.emission = Color(0.5, 0.45, 0.1)
	band_mat.emission_energy_multiplier = 0.3

	var band := MeshInstance3D.new()
	var band_cyl := CylinderMesh.new()
	band_cyl.top_radius = 0.13
	band_cyl.bottom_radius = 0.13
	band_cyl.height = 0.08
	band.mesh = band_cyl
	band.position.y = 0.75
	band.set_surface_override_material(0, band_mat)
	bollard.add_child(band)

	# Top cap
	var cap := MeshInstance3D.new()
	var cap_sphere := SphereMesh.new()
	cap_sphere.radius = 0.14
	cap_sphere.height = 0.15
	cap_sphere.is_hemisphere = true
	cap.mesh = cap_sphere
	cap.position.y = 0.92
	cap.set_surface_override_material(0, bollard_mat)
	bollard.add_child(cap)

	_streets_container.add_child(bollard)


## Add a utility pole at position.
func _add_utility_pole(pos: Vector3) -> void:
	var pole := Node3D.new()
	pole.position = pos

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.32, 0.22)
	wood_mat.roughness = 0.9

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.35, 0.37, 0.4)
	metal_mat.metallic = 0.6
	metal_mat.roughness = 0.5

	# Main pole
	var main := MeshInstance3D.new()
	var main_cyl := CylinderMesh.new()
	main_cyl.top_radius = 0.15
	main_cyl.bottom_radius = 0.2
	main_cyl.height = 10.0
	main.mesh = main_cyl
	main.position.y = 5.0
	main.set_surface_override_material(0, wood_mat)
	pole.add_child(main)

	# Cross arm
	var arm := MeshInstance3D.new()
	var arm_box := BoxMesh.new()
	arm_box.size = Vector3(4.0, 0.15, 0.15)
	arm.mesh = arm_box
	arm.position.y = 9.0
	arm.set_surface_override_material(0, wood_mat)
	pole.add_child(arm)

	# Insulators
	for side in [-1.5, -0.5, 0.5, 1.5]:
		var insulator := MeshInstance3D.new()
		var ins_cyl := CylinderMesh.new()
		ins_cyl.top_radius = 0.08
		ins_cyl.bottom_radius = 0.1
		ins_cyl.height = 0.25
		insulator.mesh = ins_cyl
		insulator.position = Vector3(side, 9.2, 0)
		insulator.set_surface_override_material(0, metal_mat)
		pole.add_child(insulator)

	# Transformer box (sometimes)
	if randf() < 0.3:
		var transformer := MeshInstance3D.new()
		var trans_cyl := CylinderMesh.new()
		trans_cyl.top_radius = 0.4
		trans_cyl.bottom_radius = 0.4
		trans_cyl.height = 0.8
		transformer.mesh = trans_cyl
		transformer.position = Vector3(0.4, 7.5, 0)
		transformer.set_surface_override_material(0, metal_mat)
		pole.add_child(transformer)

	_streets_container.add_child(pole)


## Add a pine/conifer tree at position.
func _add_pine_tree(pos: Vector3, scale_factor: float = 1.0) -> void:
	var tree := Node3D.new()
	tree.position = pos

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
	trunk_mat.roughness = 0.9

	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.1, 0.32, 0.12)
	foliage_mat.roughness = 0.85

	# Trunk
	var trunk := MeshInstance3D.new()
	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.top_radius = 0.2 * scale_factor
	trunk_cyl.bottom_radius = 0.35 * scale_factor
	trunk_cyl.height = 2.5 * scale_factor
	trunk.mesh = trunk_cyl
	trunk.position.y = 1.25 * scale_factor
	trunk.set_surface_override_material(0, trunk_mat)
	tree.add_child(trunk)

	# Conical foliage layers
	var base_y: float = 2.0 * scale_factor
	for i in range(4):
		var layer := MeshInstance3D.new()
		var layer_cyl := CylinderMesh.new()
		var layer_radius: float = (2.2 - i * 0.45) * scale_factor
		layer_cyl.top_radius = 0.1 * scale_factor
		layer_cyl.bottom_radius = layer_radius
		layer_cyl.height = 2.0 * scale_factor
		layer.mesh = layer_cyl
		layer.position.y = base_y + i * 1.3 * scale_factor
		layer.set_surface_override_material(0, foliage_mat)
		tree.add_child(layer)

	_streets_container.add_child(tree)


## Add a palm tree at position (for variety).
func _add_palm_tree(pos: Vector3, scale_factor: float = 1.0) -> void:
	var tree := Node3D.new()
	tree.position = pos

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.45, 0.38, 0.28)
	trunk_mat.roughness = 0.85

	var frond_mat := StandardMaterial3D.new()
	frond_mat.albedo_color = Color(0.15, 0.45, 0.18)
	frond_mat.roughness = 0.8

	# Curved trunk (simplified as tapered cylinder)
	var trunk := MeshInstance3D.new()
	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.top_radius = 0.25 * scale_factor
	trunk_cyl.bottom_radius = 0.4 * scale_factor
	trunk_cyl.height = 8.0 * scale_factor
	trunk.mesh = trunk_cyl
	trunk.position.y = 4.0 * scale_factor
	trunk.rotation.x = 0.05  # Slight lean
	trunk.set_surface_override_material(0, trunk_mat)
	tree.add_child(trunk)

	# Crown of fronds (simplified as spheres arranged in a pattern)
	var crown_y: float = 8.2 * scale_factor
	for i in range(8):
		var frond := MeshInstance3D.new()
		var frond_box := BoxMesh.new()
		frond_box.size = Vector3(0.3 * scale_factor, 0.1 * scale_factor, 3.0 * scale_factor)
		frond.mesh = frond_box

		var angle := i * TAU / 8
		frond.position = Vector3(
			cos(angle) * 0.5 * scale_factor,
			crown_y - 0.3,
			sin(angle) * 0.5 * scale_factor
		)
		frond.rotation.y = angle
		frond.rotation.x = 0.5  # Droop
		frond.set_surface_override_material(0, frond_mat)
		tree.add_child(frond)

	# Central crown tuft
	var crown := MeshInstance3D.new()
	var crown_sphere := SphereMesh.new()
	crown_sphere.radius = 0.8 * scale_factor
	crown_sphere.height = 1.2 * scale_factor
	crown.mesh = crown_sphere
	crown.position.y = crown_y
	crown.set_surface_override_material(0, frond_mat)
	tree.add_child(crown)

	_streets_container.add_child(tree)


## Add a decorative flower bed at position.
func _add_flower_bed(pos: Vector3, size: Vector2 = Vector2(3, 2)) -> void:
	var bed := Node3D.new()
	bed.position = pos

	# Border material (stone/brick)
	var border_mat := StandardMaterial3D.new()
	border_mat.albedo_color = Color(0.45, 0.4, 0.35)
	border_mat.roughness = 0.85

	# Soil
	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color(0.28, 0.2, 0.12)
	soil_mat.roughness = 0.95

	# Border edges
	for edge in [
		Vector3(0, 0.1, size.y / 2), Vector3(size.x, 0.2, 0.15),  # Front
		Vector3(0, 0.1, -size.y / 2), Vector3(size.x, 0.2, 0.15),  # Back
		Vector3(size.x / 2, 0.1, 0), Vector3(0.15, 0.2, size.y),  # Right
		Vector3(-size.x / 2, 0.1, 0), Vector3(0.15, 0.2, size.y),  # Left
	]:
		pass  # Skip complex border, use simple fill

	# Soil bed
	var soil := MeshInstance3D.new()
	var soil_box := BoxMesh.new()
	soil_box.size = Vector3(size.x, 0.15, size.y)
	soil.mesh = soil_box
	soil.position.y = 0.08
	soil.set_surface_override_material(0, soil_mat)
	bed.add_child(soil)

	# Add varied flowers
	var flower_colors := [
		Color(0.9, 0.2, 0.25),
		Color(0.95, 0.75, 0.1),
		Color(0.85, 0.4, 0.65),
		Color(0.95, 0.55, 0.2),
		Color(0.4, 0.2, 0.7),
	]

	var num_flowers := int(size.x * size.y * 2)
	for i in range(num_flowers):
		var flower := MeshInstance3D.new()
		var flower_sphere := SphereMesh.new()
		flower_sphere.radius = randf_range(0.1, 0.18)
		flower_sphere.height = flower_sphere.radius * 1.4
		flower.mesh = flower_sphere
		flower.position = Vector3(
			randf_range(-size.x / 2 + 0.2, size.x / 2 - 0.2),
			0.15 + randf_range(0.08, 0.2),
			randf_range(-size.y / 2 + 0.2, size.y / 2 - 0.2)
		)

		var flower_mat := StandardMaterial3D.new()
		flower_mat.albedo_color = flower_colors[randi() % flower_colors.size()]
		flower_mat.roughness = 0.7
		flower.set_surface_override_material(0, flower_mat)
		bed.add_child(flower)

	# Add green foliage
	for i in range(num_flowers / 2):
		var leaf := MeshInstance3D.new()
		var leaf_sphere := SphereMesh.new()
		leaf_sphere.radius = randf_range(0.15, 0.25)
		leaf_sphere.height = leaf_sphere.radius * 0.6
		leaf.mesh = leaf_sphere
		leaf.position = Vector3(
			randf_range(-size.x / 2 + 0.2, size.x / 2 - 0.2),
			0.15 + randf_range(0.02, 0.1),
			randf_range(-size.y / 2 + 0.2, size.y / 2 - 0.2)
		)

		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = Color(0.18, 0.42, 0.15)
		leaf_mat.roughness = 0.85
		leaf.set_surface_override_material(0, leaf_mat)
		bed.add_child(leaf)

	_streets_container.add_child(bed)


## Add a bike rack at position.
func _add_bike_rack(pos: Vector3, rotation_y: float = 0) -> void:
	var rack := Node3D.new()
	rack.position = pos
	rack.rotation.y = rotation_y

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.35, 0.38, 0.42)
	metal_mat.metallic = 0.7
	metal_mat.roughness = 0.4

	# Multiple U-shaped holders
	for i in range(3):
		var offset_x: float = (i - 1) * 0.8

		# Left vertical
		var left := MeshInstance3D.new()
		var left_cyl := CylinderMesh.new()
		left_cyl.top_radius = 0.04
		left_cyl.bottom_radius = 0.04
		left_cyl.height = 0.8
		left.mesh = left_cyl
		left.position = Vector3(offset_x - 0.25, 0.4, 0)
		left.set_surface_override_material(0, metal_mat)
		rack.add_child(left)

		# Right vertical
		var right := MeshInstance3D.new()
		right.mesh = left_cyl.duplicate()
		right.position = Vector3(offset_x + 0.25, 0.4, 0)
		right.set_surface_override_material(0, metal_mat)
		rack.add_child(right)

		# Top horizontal (curved would be better but box is simpler)
		var top := MeshInstance3D.new()
		var top_box := BoxMesh.new()
		top_box.size = Vector3(0.5, 0.08, 0.08)
		top.mesh = top_box
		top.position = Vector3(offset_x, 0.85, 0)
		top.set_surface_override_material(0, metal_mat)
		rack.add_child(top)

	_streets_container.add_child(rack)
