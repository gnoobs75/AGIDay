class_name Command
extends RefCounted
## Command represents a player action to be executed.

## Command types
enum CommandType {
	ABILITY = 0,      ## Activate ability
	FORMATION = 1,    ## Formation command
	MOVEMENT = 2,     ## Unit movement
	ATTACK = 3,       ## Attack target
	STOP = 4,         ## Stop units
	CANCEL = 5        ## Cancel current action
}

## Unique command ID
var command_id: int = -1

## Command type
var command_type: int = CommandType.ABILITY

## Ability ID (for ABILITY type)
var ability_id: String = ""

## Faction that issued command
var faction_id: String = ""

## Timestamp when command was created
var timestamp: int = 0

## Frame number when command was created
var frame_number: int = 0

## Target position (for position-based commands)
var target_position: Vector3 = Vector3.INF

## Target unit ID (for unit-based commands)
var target_unit: int = -1

## Selected units (for group commands)
var selected_units: Array[int] = []

## Additional parameters
var parameters: Dictionary = {}

## Input source
var input_source: String = "keyboard"

## Is validated
var is_validated: bool = false

## Validation result
var validation_result: Dictionary = {}


func _init() -> void:
	timestamp = Time.get_ticks_msec()


## Create ability command.
static func create_ability(
	id: int,
	ability: String,
	faction: String,
	frame: int,
	target_pos: Vector3 = Vector3.INF,
	target: int = -1
) -> Command:
	var cmd := Command.new()
	cmd.command_id = id
	cmd.command_type = CommandType.ABILITY
	cmd.ability_id = ability
	cmd.faction_id = faction
	cmd.frame_number = frame
	cmd.target_position = target_pos
	cmd.target_unit = target
	return cmd


## Create formation command.
static func create_formation(
	id: int,
	formation_type: String,
	faction: String,
	frame: int,
	target_pos: Vector3,
	units: Array[int]
) -> Command:
	var cmd := Command.new()
	cmd.command_id = id
	cmd.command_type = CommandType.FORMATION
	cmd.ability_id = formation_type
	cmd.faction_id = faction
	cmd.frame_number = frame
	cmd.target_position = target_pos
	cmd.selected_units = units.duplicate()
	return cmd


## Create movement command.
static func create_movement(
	id: int,
	faction: String,
	frame: int,
	target_pos: Vector3,
	units: Array[int]
) -> Command:
	var cmd := Command.new()
	cmd.command_id = id
	cmd.command_type = CommandType.MOVEMENT
	cmd.faction_id = faction
	cmd.frame_number = frame
	cmd.target_position = target_pos
	cmd.selected_units = units.duplicate()
	return cmd


## Create attack command.
static func create_attack(
	id: int,
	faction: String,
	frame: int,
	target: int,
	units: Array[int]
) -> Command:
	var cmd := Command.new()
	cmd.command_id = id
	cmd.command_type = CommandType.ATTACK
	cmd.faction_id = faction
	cmd.frame_number = frame
	cmd.target_unit = target
	cmd.selected_units = units.duplicate()
	return cmd


## Check if command has target position.
func has_target_position() -> bool:
	return target_position != Vector3.INF


## Check if command has target unit.
func has_target_unit() -> bool:
	return target_unit >= 0


## Check if command has selected units.
func has_selected_units() -> bool:
	return not selected_units.is_empty()


## Get command type name.
static func get_type_name(type: int) -> String:
	match type:
		CommandType.ABILITY: return "Ability"
		CommandType.FORMATION: return "Formation"
		CommandType.MOVEMENT: return "Movement"
		CommandType.ATTACK: return "Attack"
		CommandType.STOP: return "Stop"
		CommandType.CANCEL: return "Cancel"
	return "Unknown"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"command_id": command_id,
		"command_type": command_type,
		"ability_id": ability_id,
		"faction_id": faction_id,
		"timestamp": timestamp,
		"frame_number": frame_number,
		"target_position": {
			"x": target_position.x,
			"y": target_position.y,
			"z": target_position.z
		} if target_position != Vector3.INF else null,
		"target_unit": target_unit,
		"selected_units": selected_units.duplicate(),
		"parameters": parameters.duplicate(true),
		"input_source": input_source
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> Command:
	var cmd := Command.new()
	cmd.command_id = data.get("command_id", -1)
	cmd.command_type = data.get("command_type", CommandType.ABILITY)
	cmd.ability_id = data.get("ability_id", "")
	cmd.faction_id = data.get("faction_id", "")
	cmd.timestamp = data.get("timestamp", 0)
	cmd.frame_number = data.get("frame_number", 0)

	var pos_data = data.get("target_position")
	if pos_data != null:
		cmd.target_position = Vector3(
			pos_data.get("x", 0),
			pos_data.get("y", 0),
			pos_data.get("z", 0)
		)

	cmd.target_unit = data.get("target_unit", -1)

	cmd.selected_units.clear()
	for unit_id in data.get("selected_units", []):
		cmd.selected_units.append(unit_id)

	cmd.parameters = data.get("parameters", {}).duplicate(true)
	cmd.input_source = data.get("input_source", "keyboard")

	return cmd
