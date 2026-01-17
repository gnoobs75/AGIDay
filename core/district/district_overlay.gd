class_name DistrictOverlay
extends Node3D
## DistrictOverlay renders faction ownership tinting on the ground.
## Creates a semi-transparent colored overlay for each district based on owner.

signal capture_flash_completed(district_id: int)

## World dimensions
const WORLD_SIZE := 512.0
const GRID_SIZE := 8  ## 8x8 districts
const DISTRICT_SIZE := WORLD_SIZE / GRID_SIZE  ## 64 units per district

## Visual settings
const TINT_ALPHA := 0.15  ## Subtle tint (15% opacity)
const CAPTURE_FLASH_DURATION := 0.5
const CONTESTED_PULSE_SPEED := 2.0

## Faction colors (matching main.gd)
const FACTION_COLORS := {
	1: Color(0.2, 0.6, 1.0),    # Aether Swarm - Blue
	2: Color(1.0, 0.3, 0.2),    # OptiForge Legion - Red
	3: Color(0.2, 1.0, 0.3),    # Dynapods Vanguard - Green
	4: Color(1.0, 0.8, 0.2),    # LogiBots Colossus - Yellow
	5: Color(0.6, 0.4, 0.2),    # Human Remnant - Brown
}

## Neutral color
const NEUTRAL_COLOR := Color(0.3, 0.3, 0.3, 0.05)

## Overlay mesh
var _overlay_mesh: MeshInstance3D = null
var _overlay_texture: ImageTexture = null
var _overlay_image: Image = null

## District state tracking
var _district_owners: Array[int] = []  # faction_id per district (0 = neutral)
var _contested_districts: Array[bool] = []
var _capture_flashes: Dictionary = {}  # district_id -> flash_time_remaining

## Texture resolution (higher = smoother gradients)
const TEXTURE_SIZE := 256  # 256x256 texture for 64 districts


func _init() -> void:
	_district_owners.resize(GRID_SIZE * GRID_SIZE)
	_contested_districts.resize(GRID_SIZE * GRID_SIZE)
	for i in range(GRID_SIZE * GRID_SIZE):
		_district_owners[i] = 0
		_contested_districts[i] = false


func _ready() -> void:
	_create_overlay_mesh()
	_create_overlay_texture()
	_update_texture()


## Create the ground overlay mesh
func _create_overlay_mesh() -> void:
	_overlay_mesh = MeshInstance3D.new()
	_overlay_mesh.name = "DistrictOverlayMesh"

	# Create plane mesh covering world
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_SIZE, WORLD_SIZE)
	_overlay_mesh.mesh = plane

	# Position at ground level, slightly above to prevent z-fighting
	_overlay_mesh.position = Vector3(WORLD_SIZE / 2.0, 0.1, WORLD_SIZE / 2.0)

	# Create material
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.render_priority = -1  # Render behind other objects
	_overlay_mesh.material_override = mat

	add_child(_overlay_mesh)


## Create the texture for district colors
func _create_overlay_texture() -> void:
	_overlay_image = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	_overlay_image.fill(Color(0, 0, 0, 0))
	_overlay_texture = ImageTexture.create_from_image(_overlay_image)

	# Apply texture to material
	var mat: StandardMaterial3D = _overlay_mesh.material_override
	mat.albedo_texture = _overlay_texture


## Update texture when ownership changes
func _update_texture() -> void:
	if _overlay_image == null:
		return

	var pixels_per_district := TEXTURE_SIZE / GRID_SIZE  # 32 pixels per district

	for dz in GRID_SIZE:
		for dx in GRID_SIZE:
			var district_idx := dz * GRID_SIZE + dx
			var faction_id: int = _district_owners[district_idx]
			var is_contested: bool = _contested_districts[district_idx]

			# Get base color
			var base_color: Color
			if faction_id > 0 and FACTION_COLORS.has(faction_id):
				base_color = FACTION_COLORS[faction_id]
				base_color.a = TINT_ALPHA
			else:
				base_color = NEUTRAL_COLOR

			# Draw district with radial gradient (stronger at center)
			var center_x := dx * pixels_per_district + pixels_per_district / 2
			var center_z := dz * pixels_per_district + pixels_per_district / 2
			var max_dist := pixels_per_district * 0.7  # Gradient radius

			for pz in range(dz * pixels_per_district, (dz + 1) * pixels_per_district):
				for px in range(dx * pixels_per_district, (dx + 1) * pixels_per_district):
					# Calculate distance from center for gradient
					var dist_from_center := sqrt(pow(px - center_x, 2) + pow(pz - center_z, 2))
					var gradient := 1.0 - clampf(dist_from_center / max_dist, 0.0, 1.0)
					gradient = gradient * gradient  # Quadratic falloff

					var pixel_color := base_color
					pixel_color.a *= gradient

					_overlay_image.set_pixel(px, pz, pixel_color)

	_overlay_texture.update(_overlay_image)


## Set district ownership
func set_district_owner(district_x: int, district_z: int, faction_id: int) -> void:
	if district_x < 0 or district_x >= GRID_SIZE or district_z < 0 or district_z >= GRID_SIZE:
		return

	var idx := district_z * GRID_SIZE + district_x
	var old_owner := _district_owners[idx]
	_district_owners[idx] = faction_id

	if old_owner != faction_id:
		# Trigger capture flash
		_capture_flashes[idx] = CAPTURE_FLASH_DURATION
		_update_texture()


## Set district contested state
func set_district_contested(district_x: int, district_z: int, contested: bool) -> void:
	if district_x < 0 or district_x >= GRID_SIZE or district_z < 0 or district_z >= GRID_SIZE:
		return

	var idx := district_z * GRID_SIZE + district_x
	_contested_districts[idx] = contested


## Get district index from world position
func get_district_at(world_pos: Vector3) -> Vector2i:
	var dx := int(world_pos.x / DISTRICT_SIZE)
	var dz := int(world_pos.z / DISTRICT_SIZE)
	return Vector2i(clampi(dx, 0, GRID_SIZE - 1), clampi(dz, 0, GRID_SIZE - 1))


## Update animations
func update(delta: float) -> void:
	var need_texture_update := false

	# Update capture flashes
	var completed_flashes: Array[int] = []
	for district_id: int in _capture_flashes.keys():
		_capture_flashes[district_id] -= delta
		if _capture_flashes[district_id] <= 0:
			completed_flashes.append(district_id)
			capture_flash_completed.emit(district_id)
		else:
			need_texture_update = true

	for district_id in completed_flashes:
		_capture_flashes.erase(district_id)

	# Update contested pulse (handled in shader if we had one, for now just texture)
	if need_texture_update:
		_update_texture_with_flashes()


## Update texture with flash effects
func _update_texture_with_flashes() -> void:
	if _overlay_image == null:
		return

	var pixels_per_district := TEXTURE_SIZE / GRID_SIZE

	for district_id: int in _capture_flashes.keys():
		var flash_progress: float = _capture_flashes[district_id] / CAPTURE_FLASH_DURATION
		var dx := district_id % GRID_SIZE
		var dz := district_id / GRID_SIZE
		var faction_id: int = _district_owners[district_id]

		# Flash color (white blend)
		var base_color: Color
		if faction_id > 0 and FACTION_COLORS.has(faction_id):
			base_color = FACTION_COLORS[faction_id]
		else:
			base_color = Color.WHITE

		var flash_color := base_color.lerp(Color.WHITE, flash_progress * 0.5)
		flash_color.a = TINT_ALPHA + (0.3 * flash_progress)  # Brighter during flash

		# Draw flashing district
		var center_x := dx * pixels_per_district + pixels_per_district / 2
		var center_z := dz * pixels_per_district + pixels_per_district / 2
		var max_dist := pixels_per_district * 0.7

		for pz in range(dz * pixels_per_district, (dz + 1) * pixels_per_district):
			for px in range(dx * pixels_per_district, (dx + 1) * pixels_per_district):
				var dist_from_center := sqrt(pow(px - center_x, 2) + pow(pz - center_z, 2))
				var gradient := 1.0 - clampf(dist_from_center / max_dist, 0.0, 1.0)
				gradient = gradient * gradient

				var pixel_color := flash_color
				pixel_color.a *= gradient

				_overlay_image.set_pixel(px, pz, pixel_color)

	_overlay_texture.update(_overlay_image)


## Initialize from district manager state
func sync_from_districts(districts: Array) -> void:
	for i in range(mini(districts.size(), GRID_SIZE * GRID_SIZE)):
		var district: Dictionary = districts[i]
		var faction_id: int = district.get("owner_faction_id", 0)
		var contested: bool = district.get("is_contested", false)
		_district_owners[i] = faction_id
		_contested_districts[i] = contested

	_update_texture()


## Clear all ownership
func clear() -> void:
	for i in range(GRID_SIZE * GRID_SIZE):
		_district_owners[i] = 0
		_contested_districts[i] = false
	_capture_flashes.clear()
	_update_texture()
