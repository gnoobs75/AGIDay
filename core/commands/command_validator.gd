class_name CommandValidator
extends RefCounted
## CommandValidator checks if commands can be executed.

## Cooldown check callback (ability_id) -> bool
var _cooldown_check: Callable

## Resource check callback (faction_id, ree, power) -> bool
var _resource_check: Callable

## Prerequisite check callback (faction_id, prereq_id) -> bool
var _prerequisite_check: Callable

## Ability config callback (ability_id) -> AbilityConfig
var _ability_config_callback: Callable


func _init() -> void:
	pass


## Set callbacks.
func set_cooldown_check(callback: Callable) -> void:
	_cooldown_check = callback


func set_resource_check(callback: Callable) -> void:
	_resource_check = callback


func set_prerequisite_check(callback: Callable) -> void:
	_prerequisite_check = callback


func set_ability_config_callback(callback: Callable) -> void:
	_ability_config_callback = callback


## Validate command.
func validate(command: Command) -> Dictionary:
	var result := {
		"valid": true,
		"reason": "",
		"warnings": []
	}

	match command.command_type:
		Command.CommandType.ABILITY:
			result = _validate_ability_command(command)
		Command.CommandType.FORMATION:
			result = _validate_formation_command(command)
		Command.CommandType.MOVEMENT:
			result = _validate_movement_command(command)
		Command.CommandType.ATTACK:
			result = _validate_attack_command(command)
		Command.CommandType.STOP, Command.CommandType.CANCEL:
			# Always valid
			pass

	command.is_validated = true
	command.validation_result = result

	return result


## Validate ability command.
func _validate_ability_command(command: Command) -> Dictionary:
	var result := {
		"valid": true,
		"reason": "",
		"warnings": []
	}

	# Check ability exists
	var config: AbilityConfig = _get_ability_config(command.ability_id)
	if config == null:
		result["valid"] = false
		result["reason"] = "Unknown ability: %s" % command.ability_id
		return result

	# Check faction match
	if not config.faction_id.is_empty() and config.faction_id != command.faction_id:
		result["valid"] = false
		result["reason"] = "Ability not available to faction"
		return result

	# Check cooldown
	if _is_on_cooldown(command.ability_id):
		result["valid"] = false
		result["reason"] = "Ability on cooldown"
		return result

	# Check resources
	if not _has_resources(command.faction_id, config.get_ree_cost(), config.get_power_cost()):
		result["valid"] = false
		result["reason"] = "Insufficient resources"
		return result

	# Check prerequisites
	for prereq in config.prerequisites:
		if not _has_prerequisite(command.faction_id, prereq):
			result["valid"] = false
			result["reason"] = "Missing prerequisite: %s" % prereq
			return result

	# Check target requirements
	if config.requires_target():
		if not command.has_target_position() and not command.has_target_unit():
			result["valid"] = false
			result["reason"] = "Ability requires target"
			return result

	return result


## Validate formation command.
func _validate_formation_command(command: Command) -> Dictionary:
	var result := {
		"valid": true,
		"reason": "",
		"warnings": []
	}

	# Need target position
	if not command.has_target_position():
		result["valid"] = false
		result["reason"] = "Formation requires target position"
		return result

	# Need selected units
	if not command.has_selected_units():
		result["valid"] = false
		result["reason"] = "Formation requires selected units"
		return result

	# Validate as ability if has ability_id
	if not command.ability_id.is_empty():
		var ability_result := _validate_ability_command(command)
		if not ability_result["valid"]:
			return ability_result

	return result


## Validate movement command.
func _validate_movement_command(command: Command) -> Dictionary:
	var result := {
		"valid": true,
		"reason": "",
		"warnings": []
	}

	if not command.has_target_position():
		result["valid"] = false
		result["reason"] = "Movement requires target position"
		return result

	if not command.has_selected_units():
		result["warnings"].append("No units selected for movement")

	return result


## Validate attack command.
func _validate_attack_command(command: Command) -> Dictionary:
	var result := {
		"valid": true,
		"reason": "",
		"warnings": []
	}

	if not command.has_target_unit():
		result["valid"] = false
		result["reason"] = "Attack requires target unit"
		return result

	if not command.has_selected_units():
		result["warnings"].append("No units selected for attack")

	return result


## Get ability config via callback.
func _get_ability_config(ability_id: String) -> AbilityConfig:
	if _ability_config_callback.is_valid():
		return _ability_config_callback.call(ability_id)
	return null


## Check cooldown via callback.
func _is_on_cooldown(ability_id: String) -> bool:
	if _cooldown_check.is_valid():
		return _cooldown_check.call(ability_id)
	return false


## Check resources via callback.
func _has_resources(faction_id: String, ree: float, power: float) -> bool:
	if _resource_check.is_valid():
		return _resource_check.call(faction_id, ree, power)
	return true


## Check prerequisite via callback.
func _has_prerequisite(faction_id: String, prereq_id: String) -> bool:
	if _prerequisite_check.is_valid():
		return _prerequisite_check.call(faction_id, prereq_id)
	return true
