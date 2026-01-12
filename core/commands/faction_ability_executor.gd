class_name FactionAbilityExecutor
extends RefCounted
## FactionAbilityExecutor processes commands and executes faction abilities.
## Bridges command queue, ability manager, and resource systems.

signal ability_executed(faction_id: String, ability_id: String, target: Variant)
signal ability_failed(faction_id: String, ability_id: String, reason: String)
signal cooldown_started(faction_id: String, ability_id: String, duration: float)
signal resources_consumed(faction_id: String, ree: float, power: float)

## Ability types
enum AbilityScope {
	FORMATION = 0,   ## Affects all faction units in formation
	TARGETED = 1,    ## Affects units in radius of target
	GLOBAL = 2       ## Affects all faction units everywhere
}

## Command queue
var _command_queue: CommandQueue = null

## Ability manager
var _ability_manager: AbilityManager = null

## Cooldowns per faction-ability (faction_id:ability_id -> remaining)
var _cooldowns: Dictionary = {}

## Resource check callback (faction_id, ree, power) -> bool
var _resource_check: Callable

## Resource consume callback (faction_id, ree, power) -> void
var _resource_consume: Callable

## Unit query callbacks
var _get_faction_units: Callable  ## (faction_id) -> Array[int]
var _get_units_in_radius: Callable  ## (position, radius, faction_id) -> Array[int]
var _get_selected_units: Callable  ## () -> Array[int]

## Ability execution callbacks (ability_id, faction_id, units, target, params) -> bool
var _ability_executors: Dictionary = {}


func _init() -> void:
	_command_queue = CommandQueue.new()
	_ability_manager = AbilityManager.new()

	# Set up command execution callback
	_command_queue.set_execution_callback(_execute_command)


## Get command queue.
func get_command_queue() -> CommandQueue:
	return _command_queue


## Get ability manager.
func get_ability_manager() -> AbilityManager:
	return _ability_manager


## Set resource callbacks.
func set_resource_check(callback: Callable) -> void:
	_resource_check = callback
	_ability_manager.set_resource_check_callback(callback)


func set_resource_consume(callback: Callable) -> void:
	_resource_consume = callback
	_ability_manager.set_resource_consume_callback(callback)


## Set unit query callbacks.
func set_get_faction_units(callback: Callable) -> void:
	_get_faction_units = callback


func set_get_units_in_radius(callback: Callable) -> void:
	_get_units_in_radius = callback


func set_get_selected_units(callback: Callable) -> void:
	_get_selected_units = callback


## Register ability executor.
func register_ability_executor(ability_id: String, callback: Callable) -> void:
	_ability_executors[ability_id] = callback


## Process frame.
func process(frame: int, delta: float) -> void:
	# Update cooldowns
	_update_cooldowns(delta)

	# Update ability manager
	_ability_manager.update(delta)

	# Process command queue
	_command_queue.process(frame)


## Execute command (called by command queue).
func _execute_command(command: Command) -> bool:
	match command.command_type:
		Command.CommandType.ABILITY:
			return _execute_ability_command(command)
		Command.CommandType.FORMATION:
			return _execute_formation_command(command)
		Command.CommandType.MOVEMENT:
			return _execute_movement_command(command)
		Command.CommandType.ATTACK:
			return _execute_attack_command(command)
		Command.CommandType.STOP:
			return _execute_stop_command(command)

	return false


## Execute ability command.
func _execute_ability_command(command: Command) -> bool:
	var ability_id := command.ability_id
	var faction_id := command.faction_id

	# Get ability config
	var config := _ability_manager.get_ability(ability_id)
	if config == null:
		ability_failed.emit(faction_id, ability_id, "Unknown ability")
		return false

	# Check cooldown
	var cooldown_key := "%s:%s" % [faction_id, ability_id]
	if _cooldowns.has(cooldown_key) and _cooldowns[cooldown_key] > 0:
		ability_failed.emit(faction_id, ability_id, "On cooldown")
		return false

	# Check resources
	if not _check_resources(faction_id, config.get_ree_cost(), config.get_power_cost()):
		ability_failed.emit(faction_id, ability_id, "Insufficient resources")
		return false

	# Get affected units based on ability type
	var affected_units := _get_affected_units(config, command)

	# Execute ability
	var success := false

	if _ability_executors.has(ability_id):
		success = _ability_executors[ability_id].call(
			ability_id,
			faction_id,
			affected_units,
			command.target_position if command.has_target_position() else null,
			config.execution_params
		)
	else:
		# Default execution through ability manager
		success = _ability_manager.execute_ability(
			ability_id,
			faction_id,
			command.target_position if command.has_target_position() else command.target_unit
		)

	if success:
		# Consume resources
		_consume_resources(faction_id, config.get_ree_cost(), config.get_power_cost())

		# Start cooldown
		_cooldowns[cooldown_key] = config.cooldown
		cooldown_started.emit(faction_id, ability_id, config.cooldown)

		ability_executed.emit(faction_id, ability_id, command.target_position)

	return success


## Execute formation command.
func _execute_formation_command(command: Command) -> bool:
	# Formation commands are essentially ability commands with units
	return _execute_ability_command(command)


## Execute movement command.
func _execute_movement_command(command: Command) -> bool:
	# Movement handled by unit system
	# Emit signal for unit manager to handle
	return true


## Execute attack command.
func _execute_attack_command(command: Command) -> bool:
	# Attack handled by unit system
	return true


## Execute stop command.
func _execute_stop_command(command: Command) -> bool:
	# Stop handled by unit system
	return true


## Get affected units based on ability scope.
func _get_affected_units(config: AbilityConfig, command: Command) -> Array[int]:
	var units: Array[int] = []

	# First check if command has selected units
	if command.has_selected_units():
		return command.selected_units

	# Otherwise determine by ability type
	match config.ability_type:
		AbilityConfig.AbilityType.FORMATION:
			units = _get_all_faction_units(command.faction_id)
		AbilityConfig.AbilityType.TARGETED:
			if command.has_target_position():
				var radius := config.execution_params.get("radius", 10.0)
				units = _get_units_near_position(command.target_position, radius, command.faction_id)
		AbilityConfig.AbilityType.GLOBAL:
			units = _get_all_faction_units(command.faction_id)
		_:
			# Default: selected units or all faction units
			units = _get_selected()
			if units.is_empty():
				units = _get_all_faction_units(command.faction_id)

	return units


## Update cooldowns.
func _update_cooldowns(delta: float) -> void:
	var to_remove: Array[String] = []

	for key in _cooldowns:
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0:
			to_remove.append(key)

	for key in to_remove:
		_cooldowns.erase(key)


## Check resources.
func _check_resources(faction_id: String, ree: float, power: float) -> bool:
	if ree <= 0 and power <= 0:
		return true

	if _resource_check.is_valid():
		return _resource_check.call(faction_id, ree, power)

	return true


## Consume resources.
func _consume_resources(faction_id: String, ree: float, power: float) -> void:
	if _resource_consume.is_valid():
		_resource_consume.call(faction_id, ree, power)
		resources_consumed.emit(faction_id, ree, power)


## Get all faction units.
func _get_all_faction_units(faction_id: String) -> Array[int]:
	if _get_faction_units.is_valid():
		return _get_faction_units.call(faction_id)
	return []


## Get units near position.
func _get_units_near_position(position: Vector3, radius: float, faction_id: String) -> Array[int]:
	if _get_units_in_radius.is_valid():
		return _get_units_in_radius.call(position, radius, faction_id)
	return []


## Get selected units.
func _get_selected() -> Array[int]:
	if _get_selected_units.is_valid():
		return _get_selected_units.call()
	return []


## Get cooldown remaining.
func get_cooldown_remaining(faction_id: String, ability_id: String) -> float:
	var key := "%s:%s" % [faction_id, ability_id]
	return maxf(0.0, _cooldowns.get(key, 0.0))


## Check if ability is on cooldown.
func is_on_cooldown(faction_id: String, ability_id: String) -> bool:
	return get_cooldown_remaining(faction_id, ability_id) > 0


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"command_queue": _command_queue.to_dict(),
		"ability_manager": _ability_manager.to_dict(),
		"cooldowns": _cooldowns.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_command_queue.from_dict(data.get("command_queue", {}))
	_ability_manager.from_dict(data.get("ability_manager", {}))
	_cooldowns = data.get("cooldowns", {}).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var active_cooldowns: Dictionary = {}
	for key in _cooldowns:
		if _cooldowns[key] > 0:
			active_cooldowns[key] = "%.1fs" % _cooldowns[key]

	return {
		"command_queue": _command_queue.get_summary(),
		"ability_manager": _ability_manager.get_summary(),
		"active_cooldowns": active_cooldowns,
		"registered_executors": _ability_executors.size()
	}
