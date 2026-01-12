class_name UnitTemplate
extends Resource
## UnitTemplate defines the base configuration for a unit type.
## Templates are loaded from JSON and define stats, abilities, rendering, and AI behavior.

## Template identifier (e.g., "aether_swarm_drone", "optiforge_forge_walker")
@export var template_id: String = ""

## Faction key this template belongs to
@export var faction_key: String = ""

## Unit type identifier (e.g., "drone", "forge_walker")
@export var unit_type: String = ""

## Display name for UI
@export var display_name: String = ""

## Description for UI
@export var description: String = ""

## Base stats before faction multipliers
@export var base_stats: Dictionary = {
	"max_health": 100.0,
	"health_regen": 0.0,
	"max_speed": 10.0,
	"acceleration": 50.0,
	"turn_rate": 5.0,
	"armor": 0.0,
	"base_damage": 10.0,
	"attack_speed": 1.0,
	"attack_range": 10.0,
	"vision_range": 20.0
}

## Production cost
@export var production_cost: Dictionary = {
	"ree": 100,
	"energy": 20,
	"time": 5.0
}

## Rendering configuration
@export var rendering: Dictionary = {
	"mesh_path": "",
	"material_path": "",
	"scale": Vector3.ONE,
	"use_multimesh": true,
	"lod_distances": [50.0, 100.0, 200.0]
}

## AI behavior configuration
@export var ai_behavior: Dictionary = {
	"behavior_type": "aggressive",
	"aggro_range": 15.0,
	"flee_health_percent": 0.2,
	"preferred_target": "",
	"formation_type": "none"
}

## Ability keys this unit can use
@export var abilities: Array[String] = []

## Tags for categorization and queries
@export var tags: Array[String] = []

## Whether this unit uses heavy physics (RigidBody3D)
@export var uses_heavy_physics: bool = false

## Whether this template is valid and can be used
var is_valid: bool = false

## Validation errors if any
var validation_errors: Array[String] = []


func _init() -> void:
	pass


## Create template from dictionary data.
static func from_dict(data: Dictionary) -> UnitTemplate:
	var template := UnitTemplate.new()

	template.template_id = data.get("template_id", "")
	template.faction_key = data.get("faction_key", data.get("faction", ""))
	template.unit_type = data.get("unit_type", "")
	template.display_name = data.get("display_name", template.unit_type.capitalize())
	template.description = data.get("description", "")

	# Parse base stats
	var stats_data: Dictionary = data.get("stats", data.get("base_stats", {}))
	if not stats_data.is_empty():
		for key in stats_data:
			template.base_stats[key] = stats_data[key]

	# Parse production cost
	var cost_data: Dictionary = data.get("production_cost", {})
	if not cost_data.is_empty():
		template.production_cost = cost_data.duplicate()

	# Parse rendering config
	var render_data: Dictionary = data.get("rendering", {})
	if not render_data.is_empty():
		for key in render_data:
			if key == "scale" and render_data[key] is Array:
				var arr: Array = render_data[key]
				template.rendering["scale"] = Vector3(arr[0], arr[1], arr[2])
			else:
				template.rendering[key] = render_data[key]

	# Parse AI behavior
	var ai_data: Dictionary = data.get("ai_behavior", {})
	if not ai_data.is_empty():
		for key in ai_data:
			template.ai_behavior[key] = ai_data[key]

	# Parse abilities
	var abilities_data = data.get("abilities", [])
	for ability in abilities_data:
		template.abilities.append(str(ability))

	# Parse tags
	var tags_data = data.get("tags", [])
	for tag in tags_data:
		template.tags.append(str(tag))

	template.uses_heavy_physics = data.get("uses_heavy_physics", false)

	# Validate the template
	template._validate()

	return template


## Convert template to dictionary for saving.
func to_dict() -> Dictionary:
	var scale_arr := [rendering["scale"].x, rendering["scale"].y, rendering["scale"].z]
	var render_copy := rendering.duplicate()
	render_copy["scale"] = scale_arr

	return {
		"template_id": template_id,
		"faction_key": faction_key,
		"unit_type": unit_type,
		"display_name": display_name,
		"description": description,
		"base_stats": base_stats.duplicate(),
		"production_cost": production_cost.duplicate(),
		"rendering": render_copy,
		"ai_behavior": ai_behavior.duplicate(),
		"abilities": abilities.duplicate(),
		"tags": tags.duplicate(),
		"uses_heavy_physics": uses_heavy_physics
	}


## Validate the template and set is_valid flag.
func _validate() -> void:
	validation_errors.clear()

	# Required fields
	if template_id.is_empty():
		validation_errors.append("template_id is required")

	if faction_key.is_empty():
		validation_errors.append("faction_key is required")

	if unit_type.is_empty():
		validation_errors.append("unit_type is required")

	# Stat validation
	var max_health: float = base_stats.get("max_health", 0.0)
	if max_health <= 0:
		validation_errors.append("max_health must be greater than 0")

	var max_speed: float = base_stats.get("max_speed", 0.0)
	if max_speed < 0:
		validation_errors.append("max_speed cannot be negative")

	var attack_range: float = base_stats.get("attack_range", 0.0)
	if attack_range < 0:
		validation_errors.append("attack_range cannot be negative")

	# Cost validation
	var ree_cost: int = production_cost.get("ree", 0)
	if ree_cost < 0:
		validation_errors.append("ree cost cannot be negative")

	is_valid = validation_errors.is_empty()


## Get validation result.
func get_validation_result() -> Dictionary:
	return {
		"valid": is_valid,
		"errors": validation_errors.duplicate()
	}


## Apply faction multipliers to get final stats.
func get_stats_with_multipliers(faction_config: FactionConfig) -> Dictionary:
	var result := base_stats.duplicate()

	if faction_config != null:
		# Apply multipliers
		if result.has("max_health"):
			result["max_health"] *= faction_config.unit_health_multiplier
		if result.has("max_speed"):
			result["max_speed"] *= faction_config.unit_speed_multiplier
		if result.has("base_damage"):
			result["base_damage"] *= faction_config.unit_damage_multiplier

	return result


## Get a specific stat value.
func get_stat(stat_name: String, default_value: float = 0.0) -> float:
	return base_stats.get(stat_name, default_value)


## Get production time.
func get_production_time() -> float:
	return production_cost.get("time", 5.0)


## Get resource cost.
func get_resource_cost(resource_type: String) -> int:
	return production_cost.get(resource_type, 0)


## Check if unit has a specific tag.
func has_tag(tag: String) -> bool:
	return tag in tags


## Check if unit has a specific ability.
func has_ability(ability_key: String) -> bool:
	return ability_key in abilities


## Get mesh path for rendering.
func get_mesh_path() -> String:
	return rendering.get("mesh_path", "")


## Check if should use MultiMesh rendering.
func should_use_multimesh() -> bool:
	return rendering.get("use_multimesh", true)


## Get a compact summary for debugging.
func get_summary() -> Dictionary:
	return {
		"template_id": template_id,
		"faction_key": faction_key,
		"unit_type": unit_type,
		"display_name": display_name,
		"max_health": base_stats.get("max_health", 0),
		"base_damage": base_stats.get("base_damage", 0),
		"max_speed": base_stats.get("max_speed", 0),
		"abilities_count": abilities.size(),
		"is_valid": is_valid
	}
