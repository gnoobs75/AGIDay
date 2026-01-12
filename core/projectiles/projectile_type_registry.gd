class_name ProjectileTypeRegistry
extends RefCounted
## ProjectileTypeRegistry loads and manages projectile type configurations.

## Registered projectile types (type_id -> ProjectileType)
var _types: Dictionary = {}


func _init() -> void:
	_register_default_types()


## Register default projectile types.
func _register_default_types() -> void:
	# Homing Blizzard - Glacius faction homing projectile
	var homing_blizzard := ProjectileType.new()
	homing_blizzard.type_id = "homing_blizzard"
	homing_blizzard.display_name = "Homing Blizzard"
	homing_blizzard.movement_type = ProjectileType.MovementType.HOMING
	homing_blizzard.speed = 300.0
	homing_blizzard.homing_strength = 0.8
	homing_blizzard.max_turn_rate = 120.0
	homing_blizzard.damage = 15.0
	homing_blizzard.hit_radius = 8.0
	homing_blizzard.pierce_count = 0
	homing_blizzard.lifetime = 6.0
	homing_blizzard.visual_effect = "ice_trail"
	homing_blizzard.trail_enabled = true
	homing_blizzard.scale = 1.2
	_types["homing_blizzard"] = homing_blizzard

	# Ring Wash - Expansion ring projectile
	var ring_wash := ProjectileType.new()
	ring_wash.type_id = "ring_wash"
	ring_wash.display_name = "Ring Wash"
	ring_wash.movement_type = ProjectileType.MovementType.BALLISTIC
	ring_wash.speed = 400.0
	ring_wash.homing_strength = 0.0
	ring_wash.max_turn_rate = 0.0
	ring_wash.damage = 8.0
	ring_wash.hit_radius = 6.0
	ring_wash.pierce_count = 3  # Can hit multiple targets
	ring_wash.lifetime = 4.0
	ring_wash.visual_effect = "energy_ring"
	ring_wash.trail_enabled = false
	ring_wash.scale = 1.0
	_types["ring_wash"] = ring_wash

	# Standard Bullet - Basic ballistic projectile
	var standard_bullet := ProjectileType.new()
	standard_bullet.type_id = "standard_bullet"
	standard_bullet.display_name = "Standard Bullet"
	standard_bullet.movement_type = ProjectileType.MovementType.BALLISTIC
	standard_bullet.speed = 600.0
	standard_bullet.damage = 10.0
	standard_bullet.hit_radius = 4.0
	standard_bullet.pierce_count = 0
	standard_bullet.lifetime = 3.0
	standard_bullet.visual_effect = "bullet_tracer"
	_types["standard_bullet"] = standard_bullet

	# Plasma Bolt - Medium speed energy projectile
	var plasma_bolt := ProjectileType.new()
	plasma_bolt.type_id = "plasma_bolt"
	plasma_bolt.display_name = "Plasma Bolt"
	plasma_bolt.movement_type = ProjectileType.MovementType.BALLISTIC
	plasma_bolt.speed = 450.0
	plasma_bolt.damage = 20.0
	plasma_bolt.hit_radius = 10.0
	plasma_bolt.pierce_count = 1
	plasma_bolt.lifetime = 5.0
	plasma_bolt.visual_effect = "plasma_glow"
	plasma_bolt.trail_enabled = true
	plasma_bolt.scale = 1.5
	_types["plasma_bolt"] = plasma_bolt

	# Seeker Missile - Strong homing projectile
	var seeker_missile := ProjectileType.new()
	seeker_missile.type_id = "seeker_missile"
	seeker_missile.display_name = "Seeker Missile"
	seeker_missile.movement_type = ProjectileType.MovementType.HOMING
	seeker_missile.speed = 250.0
	seeker_missile.homing_strength = 0.95
	seeker_missile.max_turn_rate = 180.0
	seeker_missile.damage = 35.0
	seeker_missile.hit_radius = 12.0
	seeker_missile.pierce_count = 0
	seeker_missile.lifetime = 8.0
	seeker_missile.visual_effect = "missile_exhaust"
	seeker_missile.trail_enabled = true
	seeker_missile.scale = 2.0
	_types["seeker_missile"] = seeker_missile


## Register projectile type.
func register_type(proj_type: ProjectileType) -> void:
	_types[proj_type.type_id] = proj_type


## Get projectile type by ID.
func get_type(type_id: String) -> ProjectileType:
	return _types.get(type_id)


## Check if type exists.
func has_type(type_id: String) -> bool:
	return _types.has(type_id)


## Get all type IDs.
func get_all_type_ids() -> Array[String]:
	var ids: Array[String] = []
	for type_id in _types:
		ids.append(type_id)
	return ids


## Load types from JSON file.
func load_from_json(json_path: String) -> bool:
	if not FileAccess.file_exists(json_path):
		return false

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		return false

	var data: Dictionary = json.data
	if not data.has("projectile_types"):
		return false

	for type_data in data["projectile_types"]:
		var proj_type := ProjectileType.from_dict(type_data)
		if not proj_type.type_id.is_empty():
			register_type(proj_type)

	return true


## Save types to JSON file.
func save_to_json(json_path: String) -> bool:
	var types_array: Array = []

	for type_id in _types:
		types_array.append(_types[type_id].to_dict())

	var data := {"projectile_types": types_array}

	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	return true


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_names: Array[String] = []
	for type_id in _types:
		type_names.append(type_id)

	return {
		"registered_types": _types.size(),
		"types": type_names
	}
