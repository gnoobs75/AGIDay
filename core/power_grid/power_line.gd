class_name PowerLine
extends RefCounted
## PowerLine represents a power transmission line connecting a plant to a district.

signal line_damaged(line_id: int, damage: float)
signal line_destroyed(line_id: int)
signal line_repaired(line_id: int)
signal power_flow_changed(line_id: int, new_flow: float)

## Line properties
var id: int = -1
var source_plant_id: int = -1
var target_district_id: int = -1

## Power transmission
var power_capacity: float = 100.0
var current_power: float = 0.0

## Health tracking
var max_health: float = 100.0
var current_health: float = 100.0
var is_destroyed: bool = false

## Physical properties
var start_position: Vector3 = Vector3.ZERO
var end_position: Vector3 = Vector3.ZERO
var length: float = 0.0


func _init() -> void:
	pass


## Initialize power line.
func initialize(p_id: int, p_source_plant: int, p_target_district: int, p_capacity: float = 100.0) -> void:
	id = p_id
	source_plant_id = p_source_plant
	target_district_id = p_target_district
	power_capacity = p_capacity
	current_power = 0.0
	max_health = 100.0
	current_health = max_health
	is_destroyed = false


## Set physical positions.
func set_positions(start: Vector3, end: Vector3) -> void:
	start_position = start
	end_position = end
	length = start.distance_to(end)


## Set power flow through line.
func set_power_flow(power: float) -> void:
	var old_power := current_power

	if is_destroyed:
		current_power = 0.0
	else:
		current_power = minf(power, power_capacity)

	if current_power != old_power:
		power_flow_changed.emit(id, current_power)


## Get current power flow.
func get_power_flow() -> float:
	if is_destroyed:
		return 0.0
	return current_power


## Check if line is active (can transmit power).
func is_active() -> bool:
	return not is_destroyed and current_health > 0.0


## Apply damage to line.
func apply_damage(damage: float) -> void:
	if is_destroyed:
		return

	var old_health := current_health
	current_health = maxf(0.0, current_health - damage)

	line_damaged.emit(id, old_health - current_health)

	if current_health <= 0.0:
		_destroy()


## Destroy the line.
func _destroy() -> void:
	is_destroyed = true
	current_health = 0.0
	current_power = 0.0
	line_destroyed.emit(id)
	power_flow_changed.emit(id, 0.0)


## Repair the line.
func repair(amount: float) -> void:
	if not is_destroyed and current_health >= max_health:
		return

	current_health = minf(max_health, current_health + amount)

	if is_destroyed and current_health > 0.0:
		is_destroyed = false
		line_repaired.emit(id)


## Full repair.
func full_repair() -> void:
	current_health = max_health
	if is_destroyed:
		is_destroyed = false
		line_repaired.emit(id)


## Get health percentage.
func get_health_percent() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health


## Get capacity utilization.
func get_utilization() -> float:
	if power_capacity <= 0.0 or is_destroyed:
		return 0.0
	return current_power / power_capacity


## Check if line is overloaded.
func is_overloaded() -> bool:
	return current_power >= power_capacity * 0.9


## Serialization.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"source_plant_id": source_plant_id,
		"target_district_id": target_district_id,
		"power_capacity": power_capacity,
		"current_power": current_power,
		"max_health": max_health,
		"current_health": current_health,
		"is_destroyed": is_destroyed,
		"start_position": {"x": start_position.x, "y": start_position.y, "z": start_position.z},
		"end_position": {"x": end_position.x, "y": end_position.y, "z": end_position.z},
		"length": length
	}


func from_dict(data: Dictionary) -> void:
	id = data.get("id", -1)
	source_plant_id = data.get("source_plant_id", -1)
	target_district_id = data.get("target_district_id", -1)
	power_capacity = data.get("power_capacity", 100.0)
	current_power = data.get("current_power", 0.0)
	max_health = data.get("max_health", 100.0)
	current_health = data.get("current_health", 100.0)
	is_destroyed = data.get("is_destroyed", false)

	var start: Dictionary = data.get("start_position", {})
	start_position = Vector3(start.get("x", 0), start.get("y", 0), start.get("z", 0))

	var end_p: Dictionary = data.get("end_position", {})
	end_position = Vector3(end_p.get("x", 0), end_p.get("y", 0), end_p.get("z", 0))

	length = data.get("length", 0.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"source_plant": source_plant_id,
		"target_district": target_district_id,
		"flow": current_power,
		"capacity": power_capacity,
		"utilization": get_utilization(),
		"health_percent": get_health_percent(),
		"is_active": is_active()
	}
