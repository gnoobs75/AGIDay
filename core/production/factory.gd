class_name Factory
extends RefCounted
## Factory produces units for a faction.
## Supports multiple factory types, upgrades, and overclocking.

signal unit_produced(unit_type: String, factory_id: int)
signal factory_destroyed(factory_id: int)
signal factory_upgraded(factory_id: int, upgrade_level: int)
signal production_blocked(reason: String)

## Factory types
enum FactoryType {
	COMBAT = 0,     ## Produces combat units
	HARVESTER = 1,  ## Produces harvester units
	SUPPORT = 2     ## Produces support units
}

## Unique factory ID
var id: int = 0

## Factory type
var type: int = FactoryType.COMBAT

## Owning faction
var faction_id: String = ""

## Position in world
var position: Vector3 = Vector3.ZERO

## District this factory is in
var district_id: int = -1

## Health
var health: float = 1000.0
var max_health: float = 1000.0

## Whether factory is destroyed
var is_destroyed: bool = false

## Production queue
var production_queue: ProductionQueue = null

## Overclock system
var overclock: ProductionOverclock = null

## Base production speed multiplier
var base_speed: float = 1.0

## Upgrade level (0-3)
var upgrade_level: int = 0

## Produceable unit types
var produceable_units: Array[String] = []

## Unit configurations (unit_type -> config dict)
var unit_configs: Dictionary = {}

## Whether factory is operational
var is_operational: bool = true

## Custom metadata
var metadata: Dictionary = {}


func _init(p_type: int = FactoryType.COMBAT) -> void:
	type = p_type
	production_queue = ProductionQueue.new()
	overclock = ProductionOverclock.new()
	_initialize_from_type()


## Initialize settings based on factory type.
func _initialize_from_type() -> void:
	match type:
		FactoryType.COMBAT:
			max_health = 1000.0
			base_speed = 1.0
			production_queue.max_queue_size = 10
			produceable_units = ["infantry", "tank", "artillery"]

		FactoryType.HARVESTER:
			max_health = 800.0
			base_speed = 1.2
			production_queue.max_queue_size = 5
			produceable_units = ["harvester"]

		FactoryType.SUPPORT:
			max_health = 600.0
			base_speed = 0.8
			production_queue.max_queue_size = 8
			produceable_units = ["medic", "engineer", "scout"]

	health = max_health
	_setup_unit_configs()


## Setup unit configurations.
func _setup_unit_configs() -> void:
	unit_configs = {
		"infantry": {"production_time": 5.0, "ree_cost": 50.0, "power_cost": 2.0},
		"tank": {"production_time": 15.0, "ree_cost": 200.0, "power_cost": 10.0},
		"artillery": {"production_time": 20.0, "ree_cost": 300.0, "power_cost": 15.0},
		"harvester": {"production_time": 10.0, "ree_cost": 150.0, "power_cost": 5.0},
		"medic": {"production_time": 8.0, "ree_cost": 80.0, "power_cost": 3.0},
		"engineer": {"production_time": 12.0, "ree_cost": 100.0, "power_cost": 4.0},
		"scout": {"production_time": 4.0, "ree_cost": 30.0, "power_cost": 1.0}
	}


## Queue unit for production.
func queue_unit(unit_type: String) -> UnitProduction:
	if is_destroyed or not is_operational:
		production_blocked.emit("Factory not operational")
		return null

	if unit_type not in produceable_units:
		production_blocked.emit("Cannot produce unit type: " + unit_type)
		return null

	var config: Dictionary = unit_configs.get(unit_type, {})
	var production := production_queue.queue_unit(unit_type, config)

	if production == null:
		production_blocked.emit("Production queue full")

	return production


## Cancel production.
func cancel_production(production_id: int) -> bool:
	return production_queue.cancel(production_id)


## Process factory (called every frame).
func process(delta: float, available_ree: float, available_power: float) -> Dictionary:
	var result := {
		"units_produced": [],
		"ree_consumed": 0.0,
		"power_consumed": 0.0
	}

	if is_destroyed or not is_operational:
		return result

	# Update overclock
	var speed_mult := overclock.process(delta)
	var effective_speed := base_speed * speed_mult * _get_upgrade_speed_bonus()

	# Check if overclock in meltdown
	if overclock.is_melted_down():
		return result

	# Get current production cost
	var current := production_queue.current_production
	var has_resources := true

	if current != null and current.is_in_progress():
		var power_needed := current.power_cost * delta * effective_speed

		if available_ree < current.ree_cost * (1.0 - current.progress) or available_power < power_needed:
			has_resources = false
		else:
			result["power_consumed"] = power_needed

	# Process production
	var completed := production_queue.process(delta, effective_speed, has_resources)

	if completed != null:
		result["units_produced"].append(completed.unit_type)
		result["ree_consumed"] = completed.ree_cost
		unit_produced.emit(completed.unit_type, id)

	return result


## Take damage.
func take_damage(amount: float) -> bool:
	if is_destroyed:
		return false

	health = maxf(0.0, health - amount)

	if health <= 0:
		is_destroyed = true
		is_operational = false
		production_queue.clear()
		factory_destroyed.emit(id)
		return true

	return false


## Repair factory.
func repair(amount: float) -> void:
	if is_destroyed:
		return

	health = minf(max_health, health + amount)


## Upgrade factory.
func upgrade() -> bool:
	if upgrade_level >= 3:
		return false

	upgrade_level += 1

	# Apply upgrade bonuses
	var health_bonus := max_health * 0.2
	max_health += health_bonus
	health += health_bonus

	production_queue.max_queue_size += 2

	factory_upgraded.emit(id, upgrade_level)
	return true


## Get upgrade speed bonus.
func _get_upgrade_speed_bonus() -> float:
	return 1.0 + upgrade_level * 0.15


## Get upgrade queue bonus.
func _get_upgrade_queue_bonus() -> int:
	return upgrade_level * 2


## Set overclock level.
func set_overclock(multiplier: float) -> void:
	overclock.set_overclock(multiplier)


## Stop overclocking.
func stop_overclock() -> void:
	overclock.stop_overclock()


## Get effective production speed.
func get_effective_speed() -> float:
	if is_destroyed or overclock.is_melted_down():
		return 0.0
	return base_speed * overclock.get_effective_multiplier() * _get_upgrade_speed_bonus()


## Get health percentage.
func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return health / max_health


## Can produce unit type.
func can_produce(unit_type: String) -> bool:
	return unit_type in produceable_units and not is_destroyed and is_operational


## Get unit cost.
func get_unit_cost(unit_type: String) -> Dictionary:
	return unit_configs.get(unit_type, {})


## Get factory type name.
func get_type_name() -> String:
	match type:
		FactoryType.COMBAT: return "Combat"
		FactoryType.HARVESTER: return "Harvester"
		FactoryType.SUPPORT: return "Support"
	return "Unknown"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"faction_id": faction_id,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"district_id": district_id,
		"health": health,
		"max_health": max_health,
		"is_destroyed": is_destroyed,
		"production_queue": production_queue.to_dict(),
		"overclock": overclock.to_dict(),
		"base_speed": base_speed,
		"upgrade_level": upgrade_level,
		"produceable_units": produceable_units.duplicate(),
		"is_operational": is_operational,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> Factory:
	var factory := Factory.new(data.get("type", FactoryType.COMBAT))
	factory.id = data.get("id", 0)
	factory.faction_id = data.get("faction_id", "")

	var pos_data: Dictionary = data.get("position", {})
	factory.position = Vector3(
		pos_data.get("x", 0.0),
		pos_data.get("y", 0.0),
		pos_data.get("z", 0.0)
	)

	factory.district_id = data.get("district_id", -1)
	factory.health = data.get("health", 1000.0)
	factory.max_health = data.get("max_health", 1000.0)
	factory.is_destroyed = data.get("is_destroyed", false)
	factory.base_speed = data.get("base_speed", 1.0)
	factory.upgrade_level = data.get("upgrade_level", 0)
	factory.is_operational = data.get("is_operational", true)
	factory.metadata = data.get("metadata", {}).duplicate()

	factory.produceable_units.clear()
	for unit in data.get("produceable_units", []):
		factory.produceable_units.append(unit)

	factory.production_queue = ProductionQueue.from_dict(data.get("production_queue", {}))
	factory.overclock = ProductionOverclock.from_dict(data.get("overclock", {}))

	return factory


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"type": get_type_name(),
		"faction": faction_id,
		"health": "%.0f%%" % (get_health_percent() * 100),
		"destroyed": is_destroyed,
		"upgrade": upgrade_level,
		"speed": "%.1fx" % get_effective_speed(),
		"queue": production_queue.get_summary(),
		"overclock": overclock.get_summary()
	}
