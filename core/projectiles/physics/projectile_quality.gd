class_name ProjectileQuality
extends RefCounted
## ProjectileQuality defines adaptive quality settings for projectile system.

## Quality levels
enum Level {
	LOW = 0,     ## Linear projectiles, no physics
	MEDIUM = 1,  ## Gravity-only physics
	HIGH = 2     ## Full physics (gravity + bounce + collision)
}

## Quality configuration
class Config:
	var level: int = Level.MEDIUM
	var max_projectiles: int = 7500
	var update_rate: int = 60  ## Hz
	var physics_enabled: bool = true
	var gravity_enabled: bool = true
	var bounce_enabled: bool = false
	var collision_enabled: bool = true
	var despawn_distance: float = 200.0  ## Units

	func _init() -> void:
		pass


## Current quality level
var current_level: int = Level.MEDIUM

## Quality configurations
var _configs: Dictionary = {}

## User-configurable despawn distance (50-400 units)
var despawn_distance: float = 200.0


func _init() -> void:
	_initialize_configs()


## Initialize quality configurations.
func _initialize_configs() -> void:
	# LOW quality
	var low := Config.new()
	low.level = Level.LOW
	low.max_projectiles = 5000
	low.update_rate = 30
	low.physics_enabled = false
	low.gravity_enabled = false
	low.bounce_enabled = false
	low.collision_enabled = true
	_configs[Level.LOW] = low

	# MEDIUM quality
	var medium := Config.new()
	medium.level = Level.MEDIUM
	medium.max_projectiles = 7500
	medium.update_rate = 60
	medium.physics_enabled = true
	medium.gravity_enabled = true
	medium.bounce_enabled = false
	medium.collision_enabled = true
	_configs[Level.MEDIUM] = medium

	# HIGH quality
	var high := Config.new()
	high.level = Level.HIGH
	high.max_projectiles = 10000
	high.update_rate = 60
	high.physics_enabled = true
	high.gravity_enabled = true
	high.bounce_enabled = true
	high.collision_enabled = true
	_configs[Level.HIGH] = high


## Set quality level.
func set_quality(level: int) -> void:
	if _configs.has(level):
		current_level = level


## Get current configuration.
func get_config() -> Config:
	var config: Config = _configs.get(current_level, _configs[Level.MEDIUM])
	config.despawn_distance = despawn_distance
	return config


## Get configuration for specific level.
func get_config_for_level(level: int) -> Config:
	return _configs.get(level, _configs[Level.MEDIUM])


## Set despawn distance (clamped to 50-400).
func set_despawn_distance(distance: float) -> void:
	despawn_distance = clampf(distance, 50.0, 400.0)


## Get max projectiles for current quality.
func get_max_projectiles() -> int:
	return get_config().max_projectiles


## Check if physics enabled.
func is_physics_enabled() -> bool:
	return get_config().physics_enabled


## Check if gravity enabled.
func is_gravity_enabled() -> bool:
	return get_config().gravity_enabled


## Check if bounce enabled.
func is_bounce_enabled() -> bool:
	return get_config().bounce_enabled


## Get quality level name.
static func get_level_name(level: int) -> String:
	match level:
		Level.LOW: return "Low"
		Level.MEDIUM: return "Medium"
		Level.HIGH: return "High"
	return "Unknown"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"current_level": current_level,
		"despawn_distance": despawn_distance
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	current_level = data.get("current_level", Level.MEDIUM)
	despawn_distance = data.get("despawn_distance", 200.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var config := get_config()
	return {
		"level": get_level_name(current_level),
		"max_projectiles": config.max_projectiles,
		"update_rate": config.update_rate,
		"physics": config.physics_enabled,
		"gravity": config.gravity_enabled,
		"bounce": config.bounce_enabled,
		"despawn_distance": despawn_distance
	}
