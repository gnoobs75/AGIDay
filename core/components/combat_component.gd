class_name CombatComponent
extends Component
## CombatComponent handles entity combat properties like damage, armor, and attack.

const COMPONENT_TYPE := "CombatComponent"


func _init() -> void:
	component_type = COMPONENT_TYPE
	version = 1
	data = {
		"base_damage": 10.0,
		"damage_multiplier": 1.0,
		"attack_speed": 1.0,
		"attack_range": 5.0,
		"armor": 0.0,
		"armor_percentage": 0.0,
		"current_target_id": -1,
		"last_attack_time": 0,
		"is_attacking": false,
		"faction_id": 0
	}


## Get the component schema for validation.
static func get_schema() -> ComponentSchema:
	var schema := ComponentSchema.new(COMPONENT_TYPE)

	schema.float_field("base_damage").set_range(0.0, 10000.0).set_default(10.0)
	schema.float_field("damage_multiplier").set_range(0.1, 10.0).set_default(1.0)
	schema.float_field("attack_speed").set_range(0.1, 20.0).set_default(1.0)
	schema.float_field("attack_range").set_range(0.0, 500.0).set_default(5.0)
	schema.float_field("armor").set_range(0.0, 10000.0).set_default(0.0)
	schema.float_field("armor_percentage").set_range(0.0, 0.99).set_default(0.0)
	schema.int_field("current_target_id").set_default(-1)
	schema.int_field("last_attack_time").set_default(0)
	schema.bool_field("is_attacking").set_default(false)
	schema.int_field("faction_id").set_range(0, 10).set_default(0)

	return schema


## Get effective damage output.
func get_damage() -> float:
	var base: float = data.get("base_damage", 10.0)
	var mult: float = data.get("damage_multiplier", 1.0)
	return base * mult


## Calculate damage reduction from armor.
func calculate_damage_reduction(incoming_damage: float) -> float:
	var flat_armor: float = data.get("armor", 0.0)
	var percent_armor: float = data.get("armor_percentage", 0.0)

	# Apply flat armor reduction first, then percentage
	var after_flat := maxf(0.0, incoming_damage - flat_armor)
	var after_percent := after_flat * (1.0 - percent_armor)

	return after_percent


## Check if can attack (based on attack speed cooldown).
func can_attack() -> bool:
	var attack_speed: float = data.get("attack_speed", 1.0)
	var cooldown_ms := int(1000.0 / attack_speed)
	var last_attack: int = data.get("last_attack_time", 0)
	var current_time := Time.get_ticks_msec()

	return (current_time - last_attack) >= cooldown_ms


## Record an attack.
func record_attack() -> void:
	data["last_attack_time"] = Time.get_ticks_msec()
	data["is_attacking"] = true


## Set current target.
func set_target(target_id: int) -> void:
	data["current_target_id"] = target_id


## Clear current target.
func clear_target() -> void:
	data["current_target_id"] = -1
	data["is_attacking"] = false


## Get current target.
func get_target_id() -> int:
	return data.get("current_target_id", -1)


## Check if has target.
func has_target() -> bool:
	return get_target_id() >= 0


## Get attack range.
func get_attack_range() -> float:
	return data.get("attack_range", 5.0)


## Get faction ID.
func get_faction_id() -> int:
	return data.get("faction_id", 0)


## Set faction ID.
func set_faction_id(faction: int) -> void:
	data["faction_id"] = faction
