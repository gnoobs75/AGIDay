class_name MinimapFogRenderer
extends RefCounted
## MinimapFogRenderer generates fog of war texture for minimap display.
## Creates 512x512 pixel texture from 16x16 chunk visibility grid.

signal texture_updated()
signal chunk_rendered(chunk_x: int, chunk_z: int)

## Texture configuration
const TEXTURE_SIZE := 512  ## Total pixels
const CHUNK_SIZE := 32  ## Pixels per chunk
const CHUNK_COUNT := 16  ## Chunks per side

## Visibility colors
const COLOR_UNEXPLORED := Color(0.0, 0.0, 0.0, 1.0)  ## Black
const COLOR_EXPLORED := Color(0.3, 0.3, 0.3, 0.7)  ## Dark gray, 70% opacity
const COLOR_VISIBLE := Color(0.0, 0.0, 0.0, 0.0)  ## Transparent

## Fog texture
var _fog_image: Image = null
var _fog_texture: ImageTexture = null

## Dirty chunks tracking
var _dirty_chunks: Array[Vector2i] = []

## Reference to fog of war grid
var _fog_grid: FogOfWarGrid = null

## Current faction being rendered
var _faction_id: String = ""

## Performance tracking
var _last_render_time_ms := 0.0


func _init() -> void:
	_create_texture()


## Create initial texture.
func _create_texture() -> void:
	_fog_image = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	_fog_image.fill(COLOR_UNEXPLORED)

	_fog_texture = ImageTexture.create_from_image(_fog_image)


## Set fog of war grid reference.
func set_fog_grid(grid: FogOfWarGrid) -> void:
	_fog_grid = grid
	_faction_id = grid.faction_id if grid != null else ""

	# Full redraw when grid changes
	mark_all_dirty()


## Get fog texture for rendering.
func get_texture() -> ImageTexture:
	return _fog_texture


## Mark chunk as dirty (needs redraw).
func mark_chunk_dirty(chunk_x: int, chunk_z: int) -> void:
	var coords := Vector2i(chunk_x, chunk_z)
	if coords not in _dirty_chunks:
		_dirty_chunks.append(coords)


## Mark all chunks as dirty.
func mark_all_dirty() -> void:
	_dirty_chunks.clear()
	for cx in CHUNK_COUNT:
		for cz in CHUNK_COUNT:
			_dirty_chunks.append(Vector2i(cx, cz))


## Update texture with current visibility.
func update_texture() -> void:
	if _fog_grid == null:
		return

	if _dirty_chunks.is_empty():
		return

	var start_time := Time.get_ticks_usec()

	# Process dirty chunks
	for coords in _dirty_chunks:
		_render_chunk(coords.x, coords.y)

	_dirty_chunks.clear()

	# Update GPU texture
	_fog_texture.update(_fog_image)

	_last_render_time_ms = float(Time.get_ticks_usec() - start_time) / 1000.0

	texture_updated.emit()


## Render single chunk to texture.
func _render_chunk(chunk_x: int, chunk_z: int) -> void:
	if _fog_grid == null:
		return

	var chunk := _fog_grid.get_chunk(chunk_x, chunk_z)
	if chunk == null:
		return

	# Calculate pixel region for this chunk
	var pixel_x := chunk_x * CHUNK_SIZE
	var pixel_z := chunk_z * CHUNK_SIZE

	# Render each cell in chunk
	for local_x in FogChunk.CHUNK_SIZE:
		for local_z in FogChunk.CHUNK_SIZE:
			var state := chunk.get_visibility(local_x, local_z)
			var color := _get_color_for_state(state)

			# Calculate pixel position (downscaled from voxel grid)
			# Each voxel maps to 1 pixel (32 voxels * 16 chunks = 512 pixels)
			var px := pixel_x + local_x
			var pz := pixel_z + local_z

			if px < TEXTURE_SIZE and pz < TEXTURE_SIZE:
				_fog_image.set_pixel(px, pz, color)

	chunk_rendered.emit(chunk_x, chunk_z)


## Get color for visibility state.
func _get_color_for_state(state: int) -> Color:
	match state:
		VisibilityState.State.UNEXPLORED:
			return COLOR_UNEXPLORED
		VisibilityState.State.EXPLORED:
			return COLOR_EXPLORED
		VisibilityState.State.VISIBLE:
			return COLOR_VISIBLE
	return COLOR_UNEXPLORED


## Incremental update - only update changed chunks.
func update_from_changes(changed_chunks: Array[FogChunk]) -> void:
	if changed_chunks.is_empty():
		return

	var start_time := Time.get_ticks_usec()

	for chunk in changed_chunks:
		_render_chunk(chunk.chunk_x, chunk.chunk_z)

	_fog_texture.update(_fog_image)

	_last_render_time_ms = float(Time.get_ticks_usec() - start_time) / 1000.0

	texture_updated.emit()


## Get visibility at pixel coordinates.
func get_visibility_at_pixel(px: int, pz: int) -> int:
	if _fog_grid == null:
		return VisibilityState.State.UNEXPLORED

	# Convert pixel to chunk coordinates
	var chunk_x := px / CHUNK_SIZE
	var chunk_z := pz / CHUNK_SIZE
	var local_x := px % CHUNK_SIZE
	var local_z := pz % CHUNK_SIZE

	var chunk := _fog_grid.get_chunk(chunk_x, chunk_z)
	if chunk == null:
		return VisibilityState.State.UNEXPLORED

	return chunk.get_visibility(local_x, local_z)


## Get visibility at world position (for minimap mouse queries).
func get_visibility_at_world(world_x: float, world_z: float) -> int:
	# Convert world to pixel coordinates
	var px := int(world_x) % TEXTURE_SIZE
	var pz := int(world_z) % TEXTURE_SIZE

	return get_visibility_at_pixel(px, pz)


## Check if position is visible on minimap.
func is_position_visible(world_x: float, world_z: float) -> bool:
	return get_visibility_at_world(world_x, world_z) == VisibilityState.State.VISIBLE


## Check if position is explored on minimap.
func is_position_explored(world_x: float, world_z: float) -> bool:
	return get_visibility_at_world(world_x, world_z) >= VisibilityState.State.EXPLORED


## Clear texture to unexplored.
func clear() -> void:
	_fog_image.fill(COLOR_UNEXPLORED)
	_fog_texture.update(_fog_image)
	texture_updated.emit()


## Get current faction.
func get_faction_id() -> String:
	return _faction_id


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"faction_id": _faction_id,
		"texture_size": TEXTURE_SIZE,
		"chunk_size": CHUNK_SIZE,
		"chunk_count": CHUNK_COUNT,
		"dirty_chunks": _dirty_chunks.size(),
		"last_render_time_ms": _last_render_time_ms,
		"has_grid": _fog_grid != null
	}
