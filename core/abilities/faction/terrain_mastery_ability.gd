class_name TerrainMasteryAbility
extends RefCounted
## TerrainMasteryAbility allows Dynapods Vanguard units to ignore terrain penalties.
## Passive ability - always active for registered units.
## Units with terrain mastery move at full speed regardless of terrain type.

signal terrain_bonus_applied(unit_id: int, terrain_type: String, normal_penalty: float)

## Configuration
const ABILITY_ID := "terrain_mastery"
const TERRAIN_TYPES := ["rubble", "water", "mud", "crater", "debris"]
const DEFAULT_PENALTIES := {
	"rubble": 0.5,   ## 50% speed on rubble
	"water": 0.6,    ## 60% speed in water
	"mud": 0.4,      ## 40% speed in mud
	"crater": 0.7,   ## 70% speed in craters
	"debris": 0.6    ## 60% speed through debris
}

## Unit data (unit_id -> mastery_data)
var _unit_data: Dictionary = {}

## Terrain grid (cell_key -> terrain_type)
var _terrain_grid: Dictionary = {}
const CELL_SIZE := 4.0

## Stats tracking
var _terrain_crossings: Dictionary = {}  ## terrain_type -> count
var _total_distance_bonus: float = 0.0

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _get_unit_base_speed: Callable  ## (unit_id) -> float


func _init() -> void:
	for terrain_type in TERRAIN_TYPES:
		_terrain_crossings[terrain_type] = 0


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_base_speed(callback: Callable) -> void:
	_get_unit_base_speed = callback


## Register unit for terrain mastery.
func register_unit(unit_id: int) -> void:
	_unit_data[unit_id] = {
		"current_terrain": "normal",
		"speed_multiplier": 1.0,
		"distance_saved": 0.0
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_data.erase(unit_id)


## Set terrain type at position.
func set_terrain(position: Vector3, terrain_type: String) -> void:
	var cell_key := _get_cell_key(position)
	if terrain_type == "normal" or terrain_type.is_empty():
		_terrain_grid.erase(cell_key)
	else:
		_terrain_grid[cell_key] = terrain_type


## Set terrain in area.
func set_terrain_area(center: Vector3, radius: float, terrain_type: String) -> void:
	var cells_radius := int(radius / CELL_SIZE) + 1
	var center_cx := int(center.x / CELL_SIZE)
	var center_cz := int(center.z / CELL_SIZE)

	for dx in range(-cells_radius, cells_radius + 1):
		for dz in range(-cells_radius, cells_radius + 1):
			var cell_pos := Vector3(
				(center_cx + dx) * CELL_SIZE + CELL_SIZE / 2,
				0,
				(center_cz + dz) * CELL_SIZE + CELL_SIZE / 2
			)
			if center.distance_to(cell_pos) <= radius:
				set_terrain(cell_pos, terrain_type)


## Get terrain at position.
func get_terrain_at(position: Vector3) -> String:
	var cell_key := _get_cell_key(position)
	return _terrain_grid.get(cell_key, "normal")


## Get cell key from position.
func _get_cell_key(position: Vector3) -> String:
	var cx := int(position.x / CELL_SIZE)
	var cz := int(position.z / CELL_SIZE)
	return "%d,%d" % [cx, cz]


## Get speed multiplier for unit (1.0 = full speed, <1.0 = penalized).
## Units with terrain mastery always return 1.0.
func get_speed_multiplier(unit_id: int, position: Vector3) -> float:
	var terrain_type := get_terrain_at(position)

	# Units with terrain mastery ignore penalties
	if _unit_data.has(unit_id):
		if terrain_type != "normal":
			var normal_penalty: float = DEFAULT_PENALTIES.get(terrain_type, 1.0)
			# Track stats
			if _unit_data[unit_id]["current_terrain"] != terrain_type:
				_terrain_crossings[terrain_type] = _terrain_crossings.get(terrain_type, 0) + 1
				terrain_bonus_applied.emit(unit_id, terrain_type, normal_penalty)
			_unit_data[unit_id]["current_terrain"] = terrain_type
			_unit_data[unit_id]["speed_multiplier"] = 1.0
		return 1.0  # Full speed regardless of terrain

	# Non-mastery units get penalized
	return DEFAULT_PENALTIES.get(terrain_type, 1.0)


## Update terrain tracking for all units.
func update(delta: float, positions: Dictionary) -> void:
	for unit_id in _unit_data:
		if not positions.has(unit_id):
			continue

		var unit_pos: Vector3 = positions[unit_id]
		var terrain_type := get_terrain_at(unit_pos)
		var data: Dictionary = _unit_data[unit_id]

		# Track terrain changes
		if data["current_terrain"] != terrain_type:
			if terrain_type != "normal":
				_terrain_crossings[terrain_type] = _terrain_crossings.get(terrain_type, 0) + 1
				var normal_penalty: float = DEFAULT_PENALTIES.get(terrain_type, 1.0)
				terrain_bonus_applied.emit(unit_id, terrain_type, normal_penalty)
			data["current_terrain"] = terrain_type

		# Track distance bonus (speed difference * delta * base_speed)
		if terrain_type != "normal":
			var normal_penalty: float = DEFAULT_PENALTIES.get(terrain_type, 1.0)
			var bonus_factor: float = 1.0 - normal_penalty  # How much faster we're going
			var base_speed := 10.0
			if _get_unit_base_speed.is_valid():
				base_speed = _get_unit_base_speed.call(unit_id)
			var distance_saved: float = bonus_factor * base_speed * delta
			data["distance_saved"] += distance_saved
			_total_distance_bonus += distance_saved


## Check if unit has terrain mastery.
func has_mastery(unit_id: int) -> bool:
	return _unit_data.has(unit_id)


## Get unit's current terrain.
func get_unit_terrain(unit_id: int) -> String:
	if not _unit_data.has(unit_id):
		return "normal"
	return _unit_data[unit_id]["current_terrain"]


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"terrain_types": TERRAIN_TYPES,
		"default_penalties": DEFAULT_PENALTIES.duplicate(),
		"cell_size": CELL_SIZE
	}


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"terrain_crossings": _terrain_crossings.duplicate(),
		"total_distance_bonus": _total_distance_bonus,
		"tracked_units": _unit_data.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var unit_data_export: Dictionary = {}
	for unit_id in _unit_data:
		unit_data_export[str(unit_id)] = _unit_data[unit_id].duplicate()

	return {
		"unit_data": unit_data_export,
		"terrain_grid": _terrain_grid.duplicate(),
		"terrain_crossings": _terrain_crossings.duplicate(),
		"total_distance_bonus": _total_distance_bonus
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_total_distance_bonus = data.get("total_distance_bonus", 0.0)

	_terrain_crossings.clear()
	for terrain_type in data.get("terrain_crossings", {}):
		_terrain_crossings[terrain_type] = data["terrain_crossings"][terrain_type]

	_terrain_grid.clear()
	for cell_key in data.get("terrain_grid", {}):
		_terrain_grid[cell_key] = data["terrain_grid"][cell_key]

	_unit_data.clear()
	for unit_id_str in data.get("unit_data", {}):
		_unit_data[int(unit_id_str)] = data["unit_data"][unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var in_difficult_terrain := 0
	for unit_id in _unit_data:
		if _unit_data[unit_id]["current_terrain"] != "normal":
			in_difficult_terrain += 1

	return {
		"tracked_units": _unit_data.size(),
		"in_difficult_terrain": in_difficult_terrain,
		"total_distance_saved": "%.1fm" % _total_distance_bonus,
		"terrain_cells": _terrain_grid.size()
	}
