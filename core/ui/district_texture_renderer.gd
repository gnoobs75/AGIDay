class_name DistrictTextureRenderer
extends RefCounted
## DistrictTextureRenderer generates a 128x128 texture for district display on minimap.
## Uses Image.create() for dynamic generation at 30Hz.

signal texture_updated()

## Texture dimensions
const TEXTURE_SIZE := 128
const GRID_SIZE := 8       ## 8x8 grid = 64 districts (or 16 for 256)
const PIXELS_PER_DISTRICT := TEXTURE_SIZE / GRID_SIZE  ## 16 pixels per district

## Faction colors (RGBA bytes)
const FACTION_COLOR_BYTES := {
	"aether_swarm": Color("#00d9ff"),      ## Cyan
	"optiforge": Color("#ff6b35"),          ## Orange
	"dynapods": Color("#c0c0c0"),           ## Silver/Gray
	"logibots": Color("#d4af37"),           ## Gold
	"human_remnant": Color("#556b2f"),      ## Olive green
	"neutral": Color("#555555")             ## Gray
}

## Update rate
const UPDATE_INTERVAL := 1.0 / 30.0  ## 30Hz

## Image and texture
var _image: Image = null
var _texture: ImageTexture = null

## District data
var _districts: Dictionary = {}  ## district_id -> {owner, capturing, capture_progress}

## Update timer
var _update_timer := 0.0
var _needs_update := true


func _init() -> void:
	_create_image()


## Create the image and texture.
func _create_image() -> void:
	_image = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	_image.fill(FACTION_COLOR_BYTES["neutral"])

	_texture = ImageTexture.create_from_image(_image)


## Update the renderer (call each frame).
func update(delta: float) -> void:
	_update_timer += delta

	if _update_timer >= UPDATE_INTERVAL and _needs_update:
		_update_timer = 0.0
		_render_districts()
		_needs_update = false


## Set district data.
func set_district(district_id: int, owner: String, capturing: bool = false, capture_progress: float = 0.0) -> void:
	_districts[district_id] = {
		"owner": owner,
		"capturing": capturing,
		"capture_progress": capture_progress
	}
	_needs_update = true


## Set multiple districts at once (batch update).
func set_districts_batch(district_data: Dictionary) -> void:
	for district_id in district_data:
		_districts[district_id] = district_data[district_id]
	_needs_update = true


## Render all districts to texture.
func _render_districts() -> void:
	if _image == null:
		return

	# Clear to neutral
	_image.fill(FACTION_COLOR_BYTES["neutral"])

	# Draw each district
	for district_id in _districts:
		_draw_district(district_id)

	# Update texture from image
	_texture.update(_image)
	texture_updated.emit()


## Draw a single district.
func _draw_district(district_id: int) -> void:
	var data: Dictionary = _districts[district_id]
	var owner: String = data.get("owner", "")
	var capturing: bool = data.get("capturing", false)
	var progress: float = data.get("capture_progress", 0.0)

	# Calculate pixel position
	var grid_x := district_id % GRID_SIZE
	var grid_y := district_id / GRID_SIZE
	var pixel_x := grid_x * PIXELS_PER_DISTRICT
	var pixel_y := grid_y * PIXELS_PER_DISTRICT

	# Get fill color
	var fill_color: Color
	if owner.is_empty():
		fill_color = FACTION_COLOR_BYTES["neutral"]
	else:
		fill_color = FACTION_COLOR_BYTES.get(owner, FACTION_COLOR_BYTES["neutral"])

	# Fill district area
	for y in range(PIXELS_PER_DISTRICT):
		for x in range(PIXELS_PER_DISTRICT):
			_image.set_pixel(pixel_x + x, pixel_y + y, fill_color)

	# Draw border if capturing
	if capturing:
		var border_color := Color.YELLOW
		_draw_district_border(pixel_x, pixel_y, border_color)

		# Draw capture progress bar at bottom
		if progress > 0:
			var bar_width := int((progress / 100.0) * (PIXELS_PER_DISTRICT - 2))
			var bar_y := pixel_y + PIXELS_PER_DISTRICT - 3
			for x in range(bar_width):
				_image.set_pixel(pixel_x + 1 + x, bar_y, Color.WHITE)


## Draw district border.
func _draw_district_border(pixel_x: int, pixel_y: int, color: Color) -> void:
	# Top and bottom edges
	for x in range(PIXELS_PER_DISTRICT):
		_image.set_pixel(pixel_x + x, pixel_y, color)
		_image.set_pixel(pixel_x + x, pixel_y + PIXELS_PER_DISTRICT - 1, color)

	# Left and right edges
	for y in range(PIXELS_PER_DISTRICT):
		_image.set_pixel(pixel_x, pixel_y + y, color)
		_image.set_pixel(pixel_x + PIXELS_PER_DISTRICT - 1, pixel_y + y, color)


## Get the texture.
func get_texture() -> ImageTexture:
	return _texture


## Get image for direct manipulation.
func get_image() -> Image:
	return _image


## Force immediate update.
func force_update() -> void:
	_render_districts()


## Clear all districts.
func clear() -> void:
	_districts.clear()
	_image.fill(FACTION_COLOR_BYTES["neutral"])
	_texture.update(_image)
	texture_updated.emit()


## Convert world position to district ID.
func world_to_district(world_x: float, world_z: float, world_size: float = 512.0) -> int:
	var grid_x := int((world_x / world_size) * GRID_SIZE)
	var grid_y := int((world_z / world_size) * GRID_SIZE)

	grid_x = clampi(grid_x, 0, GRID_SIZE - 1)
	grid_y = clampi(grid_y, 0, GRID_SIZE - 1)

	return grid_y * GRID_SIZE + grid_x


## Convert district ID to world position (center).
func district_to_world(district_id: int, world_size: float = 512.0) -> Vector3:
	var grid_x := district_id % GRID_SIZE
	var grid_y := district_id / GRID_SIZE
	var cell_size := world_size / GRID_SIZE

	return Vector3(
		(grid_x + 0.5) * cell_size,
		0,
		(grid_y + 0.5) * cell_size
	)


## Get district at texture coordinate.
func texture_to_district(tex_x: int, tex_y: int) -> int:
	var grid_x := tex_x / PIXELS_PER_DISTRICT
	var grid_y := tex_y / PIXELS_PER_DISTRICT

	grid_x = clampi(grid_x, 0, GRID_SIZE - 1)
	grid_y = clampi(grid_y, 0, GRID_SIZE - 1)

	return grid_y * GRID_SIZE + grid_x


## Get statistics.
func get_statistics() -> Dictionary:
	var owner_counts: Dictionary = {}
	var capturing_count := 0

	for district_id in _districts:
		var data: Dictionary = _districts[district_id]
		var owner: String = data.get("owner", "neutral")
		if owner.is_empty():
			owner = "neutral"
		owner_counts[owner] = owner_counts.get(owner, 0) + 1

		if data.get("capturing", false):
			capturing_count += 1

	return {
		"total_districts": _districts.size(),
		"texture_size": TEXTURE_SIZE,
		"grid_size": GRID_SIZE,
		"owner_counts": owner_counts,
		"capturing_count": capturing_count
	}
