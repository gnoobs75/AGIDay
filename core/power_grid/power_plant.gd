class_name PowerPlant
extends RefCounted
## PowerPlant represents a power generation facility in the power grid network.

signal power_changed(plant_id: int, new_power: float)
signal plant_destroyed(plant_id: int)
signal plant_repaired(plant_id: int)

## Plant types
enum PlantType {
	SOLAR,
	FUSION
}

## Plant configurations
const SOLAR_GENERATION := 100.0
const SOLAR_HEALTH := 200.0
const FUSION_GENERATION := 200.0
const FUSION_HEALTH := 300.0

## Plant identity
var id: int = -1
var faction_id: String = ""
var plant_type: int = PlantType.SOLAR
var position: Vector3 = Vector3.ZERO

## Power properties
var power_generation: float = 0.0
var current_output: float = 0.0

## Health tracking
var max_health: float = 0.0
var current_health: float = 0.0
var is_destroyed: bool = false

## Network connections
var network_id: int = -1
var connected_line_ids: Array[int] = []

## Solar-specific
var daylight_multiplier: float = 1.0


func _init() -> void:
	pass


## Initialize as solar plant.
func init_as_solar(p_id: int, p_faction_id: String, p_position: Vector3) -> void:
	id = p_id
	faction_id = p_faction_id
	position = p_position
	plant_type = PlantType.SOLAR
	power_generation = SOLAR_GENERATION
	max_health = SOLAR_HEALTH
	current_health = max_health
	is_destroyed = false


## Initialize as fusion plant.
func init_as_fusion(p_id: int, p_faction_id: String, p_position: Vector3) -> void:
	id = p_id
	faction_id = p_faction_id
	position = p_position
	plant_type = PlantType.FUSION
	power_generation = FUSION_GENERATION
	max_health = FUSION_HEALTH
	current_health = max_health
	is_destroyed = false


## Generate power based on plant type and state.
func generate_power() -> float:
	if is_destroyed:
		current_output = 0.0
		return 0.0

	match plant_type:
		PlantType.SOLAR:
			current_output = power_generation * daylight_multiplier
		PlantType.FUSION:
			current_output = power_generation
		_:
			current_output = 0.0

	return current_output


## Set daylight multiplier for solar plants.
func set_daylight_multiplier(multiplier: float) -> void:
	var old_output := current_output
	daylight_multiplier = clampf(multiplier, 0.0, 1.0)

	if plant_type == PlantType.SOLAR and not is_destroyed:
		current_output = power_generation * daylight_multiplier
		if current_output != old_output:
			power_changed.emit(id, current_output)


## Apply damage to plant.
func apply_damage(damage: float) -> void:
	if is_destroyed:
		return

	current_health = maxf(0.0, current_health - damage)

	if current_health <= 0.0:
		_destroy()


## Destroy the plant.
func _destroy() -> void:
	is_destroyed = true
	current_health = 0.0
	current_output = 0.0
	plant_destroyed.emit(id)
	power_changed.emit(id, 0.0)


## Repair the plant.
func repair(amount: float) -> void:
	if not is_destroyed and current_health >= max_health:
		return

	current_health = minf(max_health, current_health + amount)

	if is_destroyed and current_health > 0.0:
		is_destroyed = false
		plant_repaired.emit(id)
		generate_power()
		power_changed.emit(id, current_output)


## Full repair.
func full_repair() -> void:
	current_health = max_health
	if is_destroyed:
		is_destroyed = false
		plant_repaired.emit(id)
		generate_power()
		power_changed.emit(id, current_output)


## Add connected line.
func add_connected_line(line_id: int) -> void:
	if not connected_line_ids.has(line_id):
		connected_line_ids.append(line_id)


## Remove connected line.
func remove_connected_line(line_id: int) -> void:
	var idx := connected_line_ids.find(line_id)
	if idx != -1:
		connected_line_ids.remove_at(idx)


## Get health percentage.
func get_health_percent() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health


## Check if operational.
func is_operational() -> bool:
	return not is_destroyed and current_health > 0.0


## Serialization.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"faction_id": faction_id,
		"plant_type": plant_type,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"power_generation": power_generation,
		"current_output": current_output,
		"max_health": max_health,
		"current_health": current_health,
		"is_destroyed": is_destroyed,
		"network_id": network_id,
		"connected_line_ids": connected_line_ids.duplicate(),
		"daylight_multiplier": daylight_multiplier
	}


func from_dict(data: Dictionary) -> void:
	id = data.get("id", -1)
	faction_id = data.get("faction_id", "")
	plant_type = data.get("plant_type", PlantType.SOLAR)

	var pos: Dictionary = data.get("position", {})
	position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	power_generation = data.get("power_generation", 0.0)
	current_output = data.get("current_output", 0.0)
	max_health = data.get("max_health", 0.0)
	current_health = data.get("current_health", 0.0)
	is_destroyed = data.get("is_destroyed", false)
	network_id = data.get("network_id", -1)
	daylight_multiplier = data.get("daylight_multiplier", 1.0)

	connected_line_ids.clear()
	var lines: Array = data.get("connected_line_ids", [])
	for line_id in lines:
		connected_line_ids.append(int(line_id))


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_name := "solar" if plant_type == PlantType.SOLAR else "fusion"
	return {
		"id": id,
		"faction": faction_id,
		"type": type_name,
		"output": current_output,
		"max_output": power_generation,
		"health_percent": get_health_percent(),
		"is_destroyed": is_destroyed,
		"connected_lines": connected_line_ids.size()
	}
