class_name CityRenderer
extends Node3D
## CityRenderer creates visual 3D city from WFC building layout.
## Uses CSGBox3D for buildings with different sizes and colors per district.
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
	var mesh: CSGBox3D = null
	var material: StandardMaterial3D = null
	var health_bar: Node3D = null
	var health_bar_fill: CSGBox3D = null
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
func _create_building(pos: Vector3, size: Vector3, color: Color, building_type: int) -> int:
	# Create a StaticBody3D container for physics collision
	var body := StaticBody3D.new()
	body.position = pos
	body.set_meta("building_type", building_type)

	# Create the visual mesh
	var mesh := CSGBox3D.new()
	mesh.size = size
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

	mesh.material = material
	body.add_child(mesh)

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
func _create_building_health_bar(pos: Vector3, size: Vector3) -> Dictionary:
	var bar := Node3D.new()
	bar.position = pos + Vector3(0, size.y + 1.0, 0)

	# Background (dark)
	var bar_width: float = minf(size.x, 4.0)
	var bg := CSGBox3D.new()
	bg.size = Vector3(bar_width, 0.3, 0.1)
	bg.position.y = 0.15
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.1, 0.1)
	bg.material = bg_mat
	bar.add_child(bg)

	# Fill (green -> yellow -> red based on HP)
	var fill := CSGBox3D.new()
	fill.name = "Fill"
	fill.size = Vector3(bar_width, 0.3, 0.1)
	fill.position.y = 0.15
	fill.position.z = 0.05
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.2, 0.8, 0.2)
	fill_mat.emission_enabled = true
	fill_mat.emission = Color(0.1, 0.4, 0.1)
	fill_mat.emission_energy_multiplier = 0.5
	fill.material = fill_mat
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
func _update_building_health_bar(data: BuildingData) -> void:
	if data.health_bar_fill == null:
		return

	var hp_percent: float = data.get_hp_percent() / 100.0
	var bar_width: float = data.health_bar_fill.size.x

	# Scale fill based on HP
	data.health_bar_fill.scale.x = maxf(0.01, hp_percent)
	data.health_bar_fill.position.x = -bar_width * (1.0 - hp_percent) / 2.0

	# Color based on HP (green -> yellow -> red)
	var fill_mat: StandardMaterial3D = data.health_bar_fill.material
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
## Creates a grid of buildings to ensure the city has visual content.
func _add_fallback_buildings(size: int, offset: Vector3, rng: RandomNumberGenerator,
		factory_positions: Array, factory_exclusion_radius: float) -> void:
	var block_size := 80.0  # Size of each city block (doubled for larger map)
	var building_margin := 5.0  # Space between buildings
	var margin := 100.0  # Edge margin (increased for larger map)

	var building_types := [1, 2, 4, 5, 7, 10]  # Various building types
	var added := 0

	# Create a grid of buildings throughout the city
	var bx := margin
	while bx < size - margin:
		var bz := margin
		while bz < size - margin:
			# Check if near factory
			var near_factory := false
			for fp in factory_positions:
				if Vector2(bx, bz).distance_to(fp) < factory_exclusion_radius + 20:
					near_factory = true
					break

			if not near_factory:
				# Select random building type
				var building_type: int = building_types[rng.randi() % building_types.size()]

				# Get building properties
				var height: float = BUILDING_HEIGHTS.get(building_type, 6.0)
				height *= rng.randf_range(0.8, 1.3)

				var base_width: float = rng.randf_range(8.0, 16.0)
				var base_depth: float = rng.randf_range(8.0, 16.0)

				var color: Color = BUILDING_COLORS.get(building_type, Color.GRAY)
				color = color.lightened(rng.randf_range(-0.15, 0.15))

				var world_size := Vector3(base_width, height, base_depth)
				var world_pos := Vector3(
					bx + base_width / 2.0,
					height / 2.0,
					bz + base_depth / 2.0
				) + offset

				_create_building(world_pos, world_size, color, building_type)
				_building_count += 1
				added += 1

			bz += block_size
		bx += block_size

	print("CityRenderer: Added %d fallback buildings" % added)


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


## Render streets from WFC road cells.
func _render_wfc_streets(building_grid: Array, size: int, offset: Vector3,
		street_mat: StandardMaterial3D, line_mat: StandardMaterial3D,
		factory_positions: Array, factory_exclusion_radius: float) -> void:
	var grid_size: int = building_grid.size()
	var scale_factor: float = float(size) / float(grid_size)
	var street_width: float = scale_factor * DOWNSAMPLE * 0.9

	# Create main arterial streets (every 32 cells = every zone boundary)
	var arterial_interval := 32 * DOWNSAMPLE
	var margin := 60

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

		# Center lines
		for lx in range(margin + 5, size - margin - 5, 20):
			var line := CSGBox3D.new()
			line.size = Vector3(12.0, 0.06, 0.4)
			line.position = Vector3(lx + 6.0, 0.05, world_y) + offset
			line.material = line_mat
			_streets_container.add_child(line)

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

		for lz in range(margin + 5, size - margin - 5, 20):
			var line := CSGBox3D.new()
			line.size = Vector3(0.4, 0.06, 12.0)
			line.position = Vector3(world_x, 0.05, lz + 6.0) + offset
			line.material = line_mat
			_streets_container.add_child(line)


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
