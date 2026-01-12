class_name PowerConsumer
extends RefCounted
## PowerConsumer represents any building or system that consumes power.

signal power_state_changed(consumer_id: int, is_powered: bool)
signal blackout_effect_applied(consumer_id: int, penalty: float)
signal power_consumption_changed(consumer_id: int, new_consumption: float)

## Consumer types
enum ConsumerType {
	FACTORY,
	INFRASTRUCTURE,
	DEFENSE,
	RESEARCH
}

## Default power requirements by type
const FACTORY_POWER := 50.0
const INFRASTRUCTURE_POWER := 20.0
const DEFENSE_POWER := 30.0
const RESEARCH_POWER := 40.0

## Blackout production penalty
const BLACKOUT_PENALTY := 0.50  ## 50% production reduction during blackout

## Consumer identity
var consumer_id: int = -1
var faction_id: String = ""
var consumer_type: int = ConsumerType.FACTORY
var consumer_name: String = ""

## Power properties
var power_requirement: float = 0.0
var current_power: float = 0.0
var is_powered: bool = false
var is_in_blackout: bool = false

## Production modifier (affected by blackout)
var production_multiplier: float = 1.0

## Position for grid association
var position: Vector3 = Vector3.ZERO
var district_id: int = -1


func _init() -> void:
	pass


## Initialize as factory.
func init_as_factory(p_id: int, p_faction: String, p_name: String = "") -> void:
	consumer_id = p_id
	faction_id = p_faction
	consumer_type = ConsumerType.FACTORY
	consumer_name = p_name if not p_name.is_empty() else "Factory_%d" % p_id
	power_requirement = FACTORY_POWER
	production_multiplier = 1.0


## Initialize as infrastructure.
func init_as_infrastructure(p_id: int, p_faction: String, p_name: String = "") -> void:
	consumer_id = p_id
	faction_id = p_faction
	consumer_type = ConsumerType.INFRASTRUCTURE
	consumer_name = p_name if not p_name.is_empty() else "Infrastructure_%d" % p_id
	power_requirement = INFRASTRUCTURE_POWER
	production_multiplier = 1.0


## Initialize as defense.
func init_as_defense(p_id: int, p_faction: String, p_name: String = "") -> void:
	consumer_id = p_id
	faction_id = p_faction
	consumer_type = ConsumerType.DEFENSE
	consumer_name = p_name if not p_name.is_empty() else "Defense_%d" % p_id
	power_requirement = DEFENSE_POWER
	production_multiplier = 1.0


## Initialize as research.
func init_as_research(p_id: int, p_faction: String, p_name: String = "") -> void:
	consumer_id = p_id
	faction_id = p_faction
	consumer_type = ConsumerType.RESEARCH
	consumer_name = p_name if not p_name.is_empty() else "Research_%d" % p_id
	power_requirement = RESEARCH_POWER
	production_multiplier = 1.0


## Set custom power requirement.
func set_power_requirement(power: float) -> void:
	var old := power_requirement
	power_requirement = maxf(0.0, power)
	if power_requirement != old:
		power_consumption_changed.emit(consumer_id, power_requirement)


## Update power state.
func update_power_state(available_power: float, in_blackout: bool) -> void:
	var was_powered := is_powered
	var was_in_blackout := is_in_blackout

	current_power = available_power
	is_powered = available_power >= power_requirement * 0.5  # At least 50% power
	is_in_blackout = in_blackout

	# Calculate production multiplier
	if is_in_blackout:
		production_multiplier = 1.0 - BLACKOUT_PENALTY
		blackout_effect_applied.emit(consumer_id, BLACKOUT_PENALTY)
	elif not is_powered:
		production_multiplier = 0.0  # No power = no production
	else:
		production_multiplier = 1.0

	if is_powered != was_powered:
		power_state_changed.emit(consumer_id, is_powered)


## Get production multiplier (0.0 to 1.0).
func get_production_multiplier() -> float:
	return production_multiplier


## Check if operating at full capacity.
func is_full_capacity() -> bool:
	return is_powered and not is_in_blackout


## Check if operating at reduced capacity.
func is_reduced_capacity() -> bool:
	return is_powered and is_in_blackout


## Check if offline.
func is_offline() -> bool:
	return not is_powered


## Get consumer type name.
func get_type_name() -> String:
	match consumer_type:
		ConsumerType.FACTORY:
			return "factory"
		ConsumerType.INFRASTRUCTURE:
			return "infrastructure"
		ConsumerType.DEFENSE:
			return "defense"
		ConsumerType.RESEARCH:
			return "research"
		_:
			return "unknown"


## Serialization.
func to_dict() -> Dictionary:
	return {
		"consumer_id": consumer_id,
		"faction_id": faction_id,
		"consumer_type": consumer_type,
		"consumer_name": consumer_name,
		"power_requirement": power_requirement,
		"current_power": current_power,
		"is_powered": is_powered,
		"is_in_blackout": is_in_blackout,
		"production_multiplier": production_multiplier,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"district_id": district_id
	}


func from_dict(data: Dictionary) -> void:
	consumer_id = data.get("consumer_id", -1)
	faction_id = data.get("faction_id", "")
	consumer_type = data.get("consumer_type", ConsumerType.FACTORY)
	consumer_name = data.get("consumer_name", "")
	power_requirement = data.get("power_requirement", 0.0)
	current_power = data.get("current_power", 0.0)
	is_powered = data.get("is_powered", false)
	is_in_blackout = data.get("is_in_blackout", false)
	production_multiplier = data.get("production_multiplier", 1.0)
	district_id = data.get("district_id", -1)

	var pos: Dictionary = data.get("position", {})
	position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": consumer_id,
		"name": consumer_name,
		"faction": faction_id,
		"type": get_type_name(),
		"power_requirement": power_requirement,
		"current_power": current_power,
		"is_powered": is_powered,
		"is_in_blackout": is_in_blackout,
		"production_multiplier": production_multiplier,
		"district": district_id
	}
