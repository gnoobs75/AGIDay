class_name HealthComponent
extends Component
## HealthComponent tracks entity health, max health, and damage/healing.

const COMPONENT_TYPE := "HealthComponent"


func _init() -> void:
	component_type = COMPONENT_TYPE
	version = 1
	data = {
		"current_health": 100.0,
		"max_health": 100.0,
		"regeneration_rate": 0.0,
		"is_invulnerable": false,
		"last_damage_time": 0,
		"last_damage_source_id": -1
	}


## Get the component schema for validation.
static func get_schema() -> ComponentSchema:
	var schema := ComponentSchema.new(COMPONENT_TYPE)

	schema.float_field("current_health").set_range(0.0, 100000.0).set_default(100.0)
	schema.float_field("max_health").set_range(1.0, 100000.0).set_default(100.0)
	schema.float_field("regeneration_rate").set_range(0.0, 1000.0).set_default(0.0)
	schema.bool_field("is_invulnerable").set_default(false)
	schema.int_field("last_damage_time").set_required(false).set_default(0)
	schema.int_field("last_damage_source_id").set_required(false).set_default(-1)

	return schema


## Get current health.
func get_current_health() -> float:
	return data.get("current_health", 0.0)


## Get max health.
func get_max_health() -> float:
	return data.get("max_health", 100.0)


## Set current health (clamped to 0-max).
func set_current_health(value: float) -> void:
	var max_hp: float = get_max_health()
	data["current_health"] = clampf(value, 0.0, max_hp)


## Set max health.
func set_max_health(value: float) -> void:
	data["max_health"] = maxf(1.0, value)
	# Clamp current health if needed
	if get_current_health() > value:
		data["current_health"] = value


## Apply damage to the entity.
func apply_damage(amount: float, source_id: int = -1) -> float:
	if data.get("is_invulnerable", false):
		return 0.0

	var actual_damage := minf(amount, get_current_health())
	data["current_health"] = get_current_health() - actual_damage
	data["last_damage_time"] = Time.get_ticks_msec()
	data["last_damage_source_id"] = source_id

	return actual_damage


## Heal the entity.
func heal(amount: float) -> float:
	var current := get_current_health()
	var max_hp := get_max_health()
	var actual_heal := minf(amount, max_hp - current)
	data["current_health"] = current + actual_heal
	return actual_heal


## Check if entity is dead.
func is_dead() -> bool:
	return get_current_health() <= 0.0


## Check if entity is at full health.
func is_full_health() -> bool:
	return get_current_health() >= get_max_health()


## Get health percentage (0.0 to 1.0).
func get_health_percentage() -> float:
	var max_hp := get_max_health()
	if max_hp <= 0:
		return 0.0
	return get_current_health() / max_hp
