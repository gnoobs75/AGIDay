class_name ParticleVisualConfig
extends RefCounted
## ParticleVisualConfig defines visual properties for projectile particle rendering.

## Projectile type ID
var type_id: String = ""

## Color settings
var color: Color = Color.WHITE
var color_variation: float = 0.0
var emission_color: Color = Color.WHITE
var emission_strength: float = 1.0

## Size settings
var size: float = 0.2
var size_variation: float = 0.0
var size_over_lifetime: Curve = null

## Trail settings
var trail_enabled: bool = false
var trail_length: float = 0.5
var trail_color: Color = Color.WHITE

## Effect settings
var hit_effect: String = ""  ## explosion_on_hit, electric_spark, shockwave
var spawn_effect: String = ""

## Billboard mode
var billboard_mode: int = 0  ## 0=none, 1=y, 2=full

## Glow/bloom
var glow_enabled: bool = false
var glow_strength: float = 1.0


func _init() -> void:
	pass


## Load from dictionary.
static func from_dict(data: Dictionary) -> ParticleVisualConfig:
	var config := ParticleVisualConfig.new()

	config.type_id = data.get("type_id", "")

	# Color
	if data.has("color"):
		config.color = Color.html(data["color"])
	config.color_variation = data.get("color_variation", 0.0)
	if data.has("emission_color"):
		config.emission_color = Color.html(data["emission_color"])
	config.emission_strength = data.get("emission_strength", 1.0)

	# Size
	config.size = data.get("size", 0.2)
	config.size_variation = data.get("size_variation", 0.0)

	# Trail
	config.trail_enabled = data.get("trail_enabled", false)
	config.trail_length = data.get("trail_length", 0.5)
	if data.has("trail_color"):
		config.trail_color = Color.html(data["trail_color"])

	# Effects
	config.hit_effect = data.get("hit_effect", "")
	config.spawn_effect = data.get("spawn_effect", "")

	# Billboard
	config.billboard_mode = data.get("billboard_mode", 2)

	# Glow
	config.glow_enabled = data.get("glow_enabled", false)
	config.glow_strength = data.get("glow_strength", 1.0)

	return config


## Convert to dictionary.
func to_dict() -> Dictionary:
	return {
		"type_id": type_id,
		"color": color.to_html(),
		"color_variation": color_variation,
		"emission_color": emission_color.to_html(),
		"emission_strength": emission_strength,
		"size": size,
		"size_variation": size_variation,
		"trail_enabled": trail_enabled,
		"trail_length": trail_length,
		"trail_color": trail_color.to_html(),
		"hit_effect": hit_effect,
		"spawn_effect": spawn_effect,
		"billboard_mode": billboard_mode,
		"glow_enabled": glow_enabled,
		"glow_strength": glow_strength
	}


## Create default configs for built-in projectile types.
static func create_defaults() -> Dictionary:
	var configs: Dictionary = {}

	# Homing Blizzard - Ice blue
	var blizzard := ParticleVisualConfig.new()
	blizzard.type_id = "homing_blizzard"
	blizzard.color = Color.html("#00d9ff")
	blizzard.emission_color = Color.html("#00d9ff")
	blizzard.emission_strength = 2.0
	blizzard.size = 0.2
	blizzard.trail_enabled = true
	blizzard.trail_length = 0.8
	blizzard.trail_color = Color.html("#80ecff")
	blizzard.hit_effect = "electric_spark"
	blizzard.glow_enabled = true
	blizzard.glow_strength = 1.5
	configs["homing_blizzard"] = blizzard

	# Ring Wash - Orange
	var ring_wash := ParticleVisualConfig.new()
	ring_wash.type_id = "ring_wash"
	ring_wash.color = Color.html("#ff6b35")
	ring_wash.emission_color = Color.html("#ff6b35")
	ring_wash.emission_strength = 1.5
	ring_wash.size = 1.5
	ring_wash.trail_enabled = false
	ring_wash.hit_effect = "shockwave"
	ring_wash.glow_enabled = true
	ring_wash.glow_strength = 1.0
	configs["ring_wash"] = ring_wash

	# Standard Bullet - Yellow tracer
	var bullet := ParticleVisualConfig.new()
	bullet.type_id = "standard_bullet"
	bullet.color = Color.html("#ffdd00")
	bullet.emission_color = Color.html("#ffdd00")
	bullet.size = 0.1
	bullet.trail_enabled = true
	bullet.trail_length = 0.3
	bullet.hit_effect = "explosion_on_hit"
	configs["standard_bullet"] = bullet

	# Plasma Bolt - Purple
	var plasma := ParticleVisualConfig.new()
	plasma.type_id = "plasma_bolt"
	plasma.color = Color.html("#9933ff")
	plasma.emission_color = Color.html("#cc66ff")
	plasma.emission_strength = 2.5
	plasma.size = 0.3
	plasma.trail_enabled = true
	plasma.trail_length = 0.6
	plasma.trail_color = Color.html("#cc99ff")
	plasma.hit_effect = "explosion_on_hit"
	plasma.glow_enabled = true
	plasma.glow_strength = 2.0
	configs["plasma_bolt"] = plasma

	# Seeker Missile - Red
	var missile := ParticleVisualConfig.new()
	missile.type_id = "seeker_missile"
	missile.color = Color.html("#ff3333")
	missile.emission_color = Color.html("#ff6666")
	missile.emission_strength = 1.8
	missile.size = 0.4
	missile.trail_enabled = true
	missile.trail_length = 1.2
	missile.trail_color = Color.html("#ff9999")
	missile.hit_effect = "explosion_on_hit"
	missile.spawn_effect = "missile_launch"
	missile.glow_enabled = true
	missile.glow_strength = 1.2
	configs["seeker_missile"] = missile

	return configs
