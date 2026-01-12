class_name HitEffectSystem
extends RefCounted
## HitEffectSystem manages visual effects when projectiles hit targets.
## Supports explosion_on_hit, electric_spark, and shockwave effects.

signal effect_spawned(effect_type: String, position: Vector3)

## Effect types
enum EffectType {
	EXPLOSION_ON_HIT = 0,
	ELECTRIC_SPARK = 1,
	SHOCKWAVE = 2,
	MISSILE_LAUNCH = 3
}

## Effect configurations
var _effect_configs: Dictionary = {}

## Active effects (for pooling)
var _active_effects: Array[Dictionary] = []

## Effect pool
var _effect_pool: Array[Dictionary] = []

## Maximum active effects
const MAX_ACTIVE_EFFECTS := 256


func _init() -> void:
	_initialize_effect_configs()
	_initialize_pool()


## Initialize effect configurations.
func _initialize_effect_configs() -> void:
	# Explosion on hit
	_effect_configs["explosion_on_hit"] = {
		"type": EffectType.EXPLOSION_ON_HIT,
		"duration": 0.3,
		"particle_count": 12,
		"initial_scale": 0.1,
		"final_scale": 1.0,
		"fade_out": true,
		"light_intensity": 2.0,
		"light_range": 3.0
	}

	# Electric spark
	_effect_configs["electric_spark"] = {
		"type": EffectType.ELECTRIC_SPARK,
		"duration": 0.2,
		"particle_count": 8,
		"initial_scale": 0.05,
		"final_scale": 0.3,
		"fade_out": true,
		"light_intensity": 3.0,
		"light_range": 2.0
	}

	# Shockwave
	_effect_configs["shockwave"] = {
		"type": EffectType.SHOCKWAVE,
		"duration": 0.4,
		"particle_count": 1,
		"initial_scale": 0.2,
		"final_scale": 3.0,
		"fade_out": true,
		"light_intensity": 1.0,
		"light_range": 5.0
	}

	# Missile launch
	_effect_configs["missile_launch"] = {
		"type": EffectType.MISSILE_LAUNCH,
		"duration": 0.5,
		"particle_count": 6,
		"initial_scale": 0.1,
		"final_scale": 0.5,
		"fade_out": true,
		"light_intensity": 1.5,
		"light_range": 2.5
	}


## Initialize effect pool.
func _initialize_pool() -> void:
	for i in MAX_ACTIVE_EFFECTS:
		_effect_pool.append({
			"active": false,
			"effect_type": "",
			"position": Vector3.ZERO,
			"color": Color.WHITE,
			"elapsed": 0.0,
			"duration": 0.0,
			"scale": 0.0,
			"config": {}
		})


## Spawn effect.
func spawn_effect(effect_type: String, position: Vector3, color: Color = Color.WHITE) -> int:
	if not _effect_configs.has(effect_type):
		return -1

	# Find free effect slot
	var effect_index := -1
	for i in _effect_pool.size():
		if not _effect_pool[i]["active"]:
			effect_index = i
			break

	if effect_index < 0:
		return -1  # Pool exhausted

	var config: Dictionary = _effect_configs[effect_type]
	var effect: Dictionary = _effect_pool[effect_index]

	effect["active"] = true
	effect["effect_type"] = effect_type
	effect["position"] = position
	effect["color"] = color
	effect["elapsed"] = 0.0
	effect["duration"] = config["duration"]
	effect["scale"] = config["initial_scale"]
	effect["config"] = config

	_active_effects.append(effect)
	effect_spawned.emit(effect_type, position)

	return effect_index


## Update effects.
func update(delta: float) -> void:
	var to_remove: Array[Dictionary] = []

	for effect in _active_effects:
		effect["elapsed"] += delta

		# Update scale
		var progress := effect["elapsed"] / effect["duration"]
		var config: Dictionary = effect["config"]
		effect["scale"] = lerpf(config["initial_scale"], config["final_scale"], progress)

		# Check completion
		if effect["elapsed"] >= effect["duration"]:
			to_remove.append(effect)

	# Remove completed effects
	for effect in to_remove:
		effect["active"] = false
		_active_effects.erase(effect)


## Get active effects for rendering.
func get_active_effects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for effect in _active_effects:
		var progress := effect["elapsed"] / effect["duration"]
		var alpha := 1.0 - progress if effect["config"].get("fade_out", true) else 1.0

		result.append({
			"effect_type": effect["effect_type"],
			"position": effect["position"],
			"color": Color(effect["color"].r, effect["color"].g, effect["color"].b, alpha),
			"scale": effect["scale"],
			"progress": progress,
			"light_intensity": effect["config"].get("light_intensity", 1.0) * (1.0 - progress),
			"light_range": effect["config"].get("light_range", 2.0)
		})

	return result


## Get effect config.
func get_effect_config(effect_type: String) -> Dictionary:
	return _effect_configs.get(effect_type, {})


## Register custom effect.
func register_effect(effect_type: String, config: Dictionary) -> void:
	_effect_configs[effect_type] = config


## Clear all effects.
func clear_all() -> void:
	for effect in _active_effects:
		effect["active"] = false
	_active_effects.clear()


## Get active count.
func get_active_count() -> int:
	return _active_effects.size()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var by_type: Dictionary = {}
	for effect in _active_effects:
		var type_name: String = effect["effect_type"]
		by_type[type_name] = by_type.get(type_name, 0) + 1

	return {
		"active_effects": _active_effects.size(),
		"pool_size": _effect_pool.size(),
		"registered_types": _effect_configs.size(),
		"by_type": by_type
	}
