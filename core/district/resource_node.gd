class_name ResourceNode
extends RefCounted
## ResourceNode represents a resource generation point in a district.

signal output_changed(node_id: int, new_output: float)
signal node_damaged(node_id: int, damage: float)
signal node_destroyed(node_id: int)
signal node_repaired(node_id: int)
signal resource_generated(node_id: int, resource_type: int, amount: float)

## Resource types
enum ResourceType {
	REE,
	POWER
}

## Default generation rates
const DEFAULT_REE_RATE := 10.0
const DEFAULT_POWER_RATE := 50.0

## Node identity
var node_id: int = -1
var district_id: int = -1
var resource_type: int = ResourceType.REE

## Position
var position: Vector3 = Vector3.ZERO

## Generation
var base_rate: float = 0.0
var current_rate: float = 0.0
var efficiency: float = 1.0

## Health
var max_health: float = 100.0
var current_health: float = 100.0
var is_destroyed: bool = false

## Ownership
var owning_faction: String = ""


func _init() -> void:
	pass


## Initialize as REE node.
func init_as_ree(p_id: int, p_district_id: int, p_position: Vector3, rate: float = DEFAULT_REE_RATE) -> void:
	node_id = p_id
	district_id = p_district_id
	position = p_position
	resource_type = ResourceType.REE
	base_rate = rate
	current_rate = rate
	max_health = 150.0
	current_health = max_health


## Initialize as power node.
func init_as_power(p_id: int, p_district_id: int, p_position: Vector3, rate: float = DEFAULT_POWER_RATE) -> void:
	node_id = p_id
	district_id = p_district_id
	position = p_position
	resource_type = ResourceType.POWER
	base_rate = rate
	current_rate = rate
	max_health = 100.0
	current_health = max_health


## Update output rate.
func update_output() -> void:
	var old_rate := current_rate

	if is_destroyed:
		current_rate = 0.0
	else:
		current_rate = base_rate * efficiency * (current_health / max_health)

	if current_rate != old_rate:
		output_changed.emit(node_id, current_rate)


## Set efficiency.
func set_efficiency(new_efficiency: float) -> void:
	efficiency = clampf(new_efficiency, 0.0, 1.0)
	update_output()


## Set owning faction.
func set_owning_faction(faction_id: String) -> void:
	owning_faction = faction_id


## Apply damage.
func apply_damage(damage: float) -> void:
	if is_destroyed:
		return

	current_health = maxf(0.0, current_health - damage)
	node_damaged.emit(node_id, damage)

	if current_health <= 0.0:
		is_destroyed = true
		current_rate = 0.0
		node_destroyed.emit(node_id)
	else:
		update_output()


## Repair node.
func repair(amount: float) -> void:
	var was_destroyed := is_destroyed

	current_health = minf(max_health, current_health + amount)

	if is_destroyed and current_health > 0.0:
		is_destroyed = false

	update_output()

	if was_destroyed and not is_destroyed:
		node_repaired.emit(node_id)


## Full repair.
func full_repair() -> void:
	var was_destroyed := is_destroyed
	current_health = max_health
	is_destroyed = false
	update_output()

	if was_destroyed:
		node_repaired.emit(node_id)


## Generate resources (call each frame).
func generate(delta: float) -> float:
	if is_destroyed or owning_faction.is_empty():
		return 0.0

	var amount := current_rate * delta
	if amount > 0.0:
		resource_generated.emit(node_id, resource_type, amount)

	return amount


## Check if producing.
func is_producing() -> bool:
	return not is_destroyed and current_rate > 0.0


## Get health percent.
func get_health_percent() -> float:
	return current_health / max_health if max_health > 0 else 0.0


## Get type name.
func get_type_name() -> String:
	match resource_type:
		ResourceType.REE:
			return "ree"
		ResourceType.POWER:
			return "power"
		_:
			return "unknown"


## Serialization.
func to_dict() -> Dictionary:
	return {
		"node_id": node_id,
		"district_id": district_id,
		"resource_type": resource_type,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"base_rate": base_rate,
		"current_rate": current_rate,
		"efficiency": efficiency,
		"max_health": max_health,
		"current_health": current_health,
		"is_destroyed": is_destroyed,
		"owning_faction": owning_faction
	}


func from_dict(data: Dictionary) -> void:
	node_id = data.get("node_id", -1)
	district_id = data.get("district_id", -1)
	resource_type = data.get("resource_type", ResourceType.REE)

	var pos: Dictionary = data.get("position", {})
	position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	base_rate = data.get("base_rate", 0.0)
	current_rate = data.get("current_rate", 0.0)
	efficiency = data.get("efficiency", 1.0)
	max_health = data.get("max_health", 100.0)
	current_health = data.get("current_health", 100.0)
	is_destroyed = data.get("is_destroyed", false)
	owning_faction = data.get("owning_faction", "")


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": node_id,
		"district": district_id,
		"type": get_type_name(),
		"rate": current_rate,
		"health_percent": get_health_percent(),
		"is_producing": is_producing(),
		"faction": owning_faction
	}
