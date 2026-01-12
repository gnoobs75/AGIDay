class_name AbilityManager
extends RefCounted
## AbilityManager handles ability execution, cooldowns, and validation.

signal ability_executed(ability_id: String, faction_id: String, target: Variant)
signal ability_failed(ability_id: String, faction_id: String, reason: String)
signal ability_cooldown_started(ability_id: String, duration: float)
signal ability_cooldown_ready(ability_id: String)
signal channeled_ability_started(ability_id: String, faction_id: String)
signal channeled_ability_ended(ability_id: String, faction_id: String)
signal feedback_triggered(ability_id: String, feedback: Dictionary)

## Registered abilities (ability_id -> AbilityConfig)
var _abilities: Dictionary = {}

## Abilities by faction (faction_id -> Array[ability_id])
var _faction_abilities: Dictionary = {}

## Cooldown tracker
var _cooldowns: AbilityCooldown = null

## Active channeled abilities (ability_id -> channel_data)
var _channeled: Dictionary = {}

## Resource check callback (faction_id, ree, power) -> bool
var _resource_check_callback: Callable

## Resource consume callback (faction_id, ree, power) -> void
var _resource_consume_callback: Callable

## Prerequisite check callback (faction_id, prereq_id) -> bool
var _prerequisite_check_callback: Callable

## Ability execution callback (ability_id, faction_id, target, params) -> bool
var _execution_callback: Callable


func _init() -> void:
	_cooldowns = AbilityCooldown.new()


## Register ability configuration.
func register_ability(config: AbilityConfig) -> void:
	_abilities[config.ability_id] = config
	_cooldowns.register_ability(config.ability_id, config.cooldown)

	# Track by faction
	if not _faction_abilities.has(config.faction_id):
		_faction_abilities[config.faction_id] = []
	_faction_abilities[config.faction_id].append(config.ability_id)


## Load abilities from JSON file.
func load_from_json(json_path: String) -> bool:
	if not FileAccess.file_exists(json_path):
		return false

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return false

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		return false

	var data: Dictionary = json.data
	for ability_data in data.get("abilities", []):
		var config := AbilityConfig.from_dict(ability_data)
		if not config.ability_id.is_empty():
			register_ability(config)

	return true


## Set resource check callback.
func set_resource_check_callback(callback: Callable) -> void:
	_resource_check_callback = callback


## Set resource consume callback.
func set_resource_consume_callback(callback: Callable) -> void:
	_resource_consume_callback = callback


## Set prerequisite check callback.
func set_prerequisite_check_callback(callback: Callable) -> void:
	_prerequisite_check_callback = callback


## Set execution callback.
func set_execution_callback(callback: Callable) -> void:
	_execution_callback = callback


## Validate ability can be used.
func can_use_ability(ability_id: String, faction_id: String) -> Dictionary:
	var result := {
		"can_use": true,
		"reason": ""
	}

	# Check ability exists
	var config: AbilityConfig = _abilities.get(ability_id)
	if config == null:
		result["can_use"] = false
		result["reason"] = "Ability not found"
		return result

	# Check faction match
	if config.faction_id != faction_id and not config.faction_id.is_empty():
		result["can_use"] = false
		result["reason"] = "Ability not available to faction"
		return result

	# Check enabled
	if not config.is_enabled:
		result["can_use"] = false
		result["reason"] = "Ability is disabled"
		return result

	# Check cooldown
	if _cooldowns.is_on_cooldown(ability_id):
		var remaining := _cooldowns.get_remaining(ability_id)
		result["can_use"] = false
		result["reason"] = "On cooldown (%.1fs)" % remaining
		return result

	# Check prerequisites
	for prereq in config.prerequisites:
		if not _check_prerequisite(faction_id, prereq):
			result["can_use"] = false
			result["reason"] = "Missing prerequisite: %s" % prereq
			return result

	# Check resources
	if not _check_resources(faction_id, config.get_ree_cost(), config.get_power_cost()):
		result["can_use"] = false
		result["reason"] = "Insufficient resources"
		return result

	return result


## Execute ability.
func execute_ability(ability_id: String, faction_id: String, target: Variant = null) -> bool:
	# Validate
	var validation := can_use_ability(ability_id, faction_id)
	if not validation["can_use"]:
		ability_failed.emit(ability_id, faction_id, validation["reason"])
		return false

	var config: AbilityConfig = _abilities[ability_id]

	# Consume resources
	_consume_resources(faction_id, config.get_ree_cost(), config.get_power_cost())

	# Start cooldown
	_cooldowns.start_cooldown(ability_id)
	ability_cooldown_started.emit(ability_id, config.cooldown)

	# Execute
	var success := true
	if _execution_callback.is_valid():
		success = _execution_callback.call(ability_id, faction_id, target, config.execution_params)

	if success:
		# Handle channeled abilities
		if config.is_channeled():
			_start_channeled(ability_id, faction_id, config.channel_duration)

		# Trigger feedback
		_trigger_feedback(ability_id, config.feedback)

		ability_executed.emit(ability_id, faction_id, target)

	return success


## Update manager (cooldowns, channeled abilities).
func update(delta: float) -> void:
	# Update cooldowns
	var ready := _cooldowns.update(delta)
	for ability_id in ready:
		ability_cooldown_ready.emit(ability_id)

	# Update channeled abilities
	_update_channeled(delta)


## Start channeled ability.
func _start_channeled(ability_id: String, faction_id: String, duration: float) -> void:
	_channeled[ability_id] = {
		"faction_id": faction_id,
		"remaining": duration,
		"total": duration
	}
	channeled_ability_started.emit(ability_id, faction_id)


## Update channeled abilities.
func _update_channeled(delta: float) -> void:
	var to_end: Array[String] = []

	for ability_id in _channeled:
		_channeled[ability_id]["remaining"] -= delta

		if _channeled[ability_id]["remaining"] <= 0:
			to_end.append(ability_id)

	for ability_id in to_end:
		var faction_id: String = _channeled[ability_id]["faction_id"]
		_channeled.erase(ability_id)
		channeled_ability_ended.emit(ability_id, faction_id)


## Trigger feedback.
func _trigger_feedback(ability_id: String, feedback_config: Dictionary) -> void:
	if not feedback_config.is_empty():
		feedback_triggered.emit(ability_id, feedback_config)


## Check prerequisite via callback.
func _check_prerequisite(faction_id: String, prereq_id: String) -> bool:
	if _prerequisite_check_callback.is_valid():
		return _prerequisite_check_callback.call(faction_id, prereq_id)
	return true  # Default to allowed


## Check resources via callback.
func _check_resources(faction_id: String, ree: float, power: float) -> bool:
	if _resource_check_callback.is_valid():
		return _resource_check_callback.call(faction_id, ree, power)
	return true


## Consume resources via callback.
func _consume_resources(faction_id: String, ree: float, power: float) -> void:
	if _resource_consume_callback.is_valid():
		_resource_consume_callback.call(faction_id, ree, power)


## Get ability configuration.
func get_ability(ability_id: String) -> AbilityConfig:
	return _abilities.get(ability_id)


## Get faction abilities.
func get_faction_abilities(faction_id: String) -> Array[AbilityConfig]:
	var result: Array[AbilityConfig] = []
	var ids: Array = _faction_abilities.get(faction_id, [])

	for ability_id in ids:
		var config: AbilityConfig = _abilities.get(ability_id)
		if config != null:
			result.append(config)

	return result


## Get ability by hotkey.
func get_ability_by_hotkey(faction_id: String, hotkey: String) -> AbilityConfig:
	var ids: Array = _faction_abilities.get(faction_id, [])

	for ability_id in ids:
		var config: AbilityConfig = _abilities.get(ability_id)
		if config != null and config.hotkey == hotkey:
			return config

	return null


## Get cooldown tracker.
func get_cooldowns() -> AbilityCooldown:
	return _cooldowns


## Check if channeled ability is active.
func is_channeled_active(ability_id: String) -> bool:
	return _channeled.has(ability_id)


## Cancel channeled ability.
func cancel_channeled(ability_id: String) -> void:
	if _channeled.has(ability_id):
		var faction_id: String = _channeled[ability_id]["faction_id"]
		_channeled.erase(ability_id)
		channeled_ability_ended.emit(ability_id, faction_id)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var abilities_data: Array = []
	for ability_id in _abilities:
		abilities_data.append(_abilities[ability_id].to_dict())

	return {
		"abilities": abilities_data,
		"cooldowns": _cooldowns.to_dict(),
		"channeled": _channeled.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_abilities.clear()
	_faction_abilities.clear()

	for ability_data in data.get("abilities", []):
		var config := AbilityConfig.from_dict(ability_data)
		if not config.ability_id.is_empty():
			register_ability(config)

	_cooldowns.from_dict(data.get("cooldowns", {}))
	_channeled = data.get("channeled", {}).duplicate(true)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"registered_abilities": _abilities.size(),
		"factions": _faction_abilities.size(),
		"cooldowns": _cooldowns.get_summary(),
		"active_channeled": _channeled.size()
	}
