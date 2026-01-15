class_name FractalMovementAbility
extends RefCounted
## FractalMovementAbility gives Aether Swarm units confusing movement patterns.
## Passive ability - units that move erratically gain evasion bonus.
## The faster and more unpredictably a unit moves, the harder it is to hit.

signal evasion_changed(unit_id: int, new_evasion: float)
signal attack_evaded(unit_id: int, attacker_id: int)

## Configuration
const ABILITY_ID := "fractal_movement"
const BASE_EVASION := 0.05  ## 5% base evasion when moving
const EVASION_PER_DIRECTION_CHANGE := 0.03  ## +3% per recent direction change
const MAX_EVASION := 0.35  ## 35% max evasion
const DIRECTION_MEMORY := 5  ## Track last N direction changes
const DIRECTION_CHANGE_THRESHOLD := 0.7  ## Dot product threshold for "direction change"
const MOVEMENT_SPEED_THRESHOLD := 2.0  ## Must be moving faster than this

## Unit data (unit_id -> movement_data)
var _unit_data: Dictionary = {}

## Stats tracking
var _total_evades: int = 0
var _total_attacks_received: int = 0


func _init() -> void:
	pass


## Register unit for fractal movement.
func register_unit(unit_id: int) -> void:
	_unit_data[unit_id] = {
		"last_position": Vector3.ZERO,
		"last_direction": Vector3.ZERO,
		"direction_changes": 0,
		"recent_directions": [],  # Array of recent movement directions
		"current_evasion": 0.0,
		"evades": 0,
		"hits": 0
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_data.erase(unit_id)


## Update movement tracking for all units.
func update(delta: float, positions: Dictionary) -> void:
	for unit_id in _unit_data:
		if not positions.has(unit_id):
			continue

		var data: Dictionary = _unit_data[unit_id]
		var current_pos: Vector3 = positions[unit_id]
		var last_pos: Vector3 = data["last_position"]

		# Calculate movement
		var movement: Vector3 = current_pos - last_pos
		var speed: float = movement.length() / maxf(delta, 0.001)

		if speed > MOVEMENT_SPEED_THRESHOLD:
			var current_direction: Vector3 = movement.normalized()
			var last_direction: Vector3 = data["last_direction"]

			# Check for direction change
			if last_direction.length() > 0.1:
				var dot: float = current_direction.dot(last_direction)
				if dot < DIRECTION_CHANGE_THRESHOLD:
					# Direction changed significantly
					data["direction_changes"] += 1

					# Add to recent directions
					var recent: Array = data["recent_directions"]
					recent.append(current_direction)
					if recent.size() > DIRECTION_MEMORY:
						recent.pop_front()

			data["last_direction"] = current_direction

			# Calculate evasion based on recent direction changes
			var direction_changes: int = data["recent_directions"].size()
			var evasion: float = BASE_EVASION + (direction_changes * EVASION_PER_DIRECTION_CHANGE)
			evasion = minf(evasion, MAX_EVASION)

			if absf(evasion - data["current_evasion"]) > 0.01:
				data["current_evasion"] = evasion
				evasion_changed.emit(unit_id, evasion)
		else:
			# Not moving fast enough - evasion decays
			var current_evasion: float = data["current_evasion"]
			if current_evasion > 0:
				data["current_evasion"] = maxf(0.0, current_evasion - 0.1 * delta)
				# Clear direction history when stationary
				if data["current_evasion"] <= 0:
					data["recent_directions"].clear()

		data["last_position"] = current_pos


## Roll evasion check for incoming attack.
## Returns Dictionary with "evaded" bool and "damage" float.
func roll_evasion(unit_id: int, incoming_damage: float, attacker_id: int = -1) -> Dictionary:
	_total_attacks_received += 1

	if not _unit_data.has(unit_id):
		return {"evaded": false, "damage": incoming_damage}

	var data: Dictionary = _unit_data[unit_id]
	var evasion: float = data["current_evasion"]

	if evasion <= 0:
		data["hits"] += 1
		return {"evaded": false, "damage": incoming_damage}

	# Roll for evasion
	var roll: float = randf()
	if roll < evasion:
		# Evaded!
		data["evades"] += 1
		_total_evades += 1
		attack_evaded.emit(unit_id, attacker_id)
		return {"evaded": true, "damage": 0.0}
	else:
		data["hits"] += 1
		return {"evaded": false, "damage": incoming_damage}


## Get current evasion chance for unit.
func get_evasion_chance(unit_id: int) -> float:
	if not _unit_data.has(unit_id):
		return 0.0
	return _unit_data[unit_id]["current_evasion"]


## Get direction change count for unit.
func get_direction_changes(unit_id: int) -> int:
	if not _unit_data.has(unit_id):
		return 0
	return _unit_data[unit_id]["direction_changes"]


## Check if unit has fractal movement.
func has_fractal_movement(unit_id: int) -> bool:
	return _unit_data.has(unit_id)


## Get evasion stats for unit.
func get_evasion_stats(unit_id: int) -> Dictionary:
	if not _unit_data.has(unit_id):
		return {"evades": 0, "hits": 0, "rate": 0.0}

	var data: Dictionary = _unit_data[unit_id]
	var total: int = data["evades"] + data["hits"]
	var rate: float = 0.0
	if total > 0:
		rate = float(data["evades"]) / float(total)

	return {
		"evades": data["evades"],
		"hits": data["hits"],
		"rate": rate
	}


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"base_evasion": BASE_EVASION,
		"evasion_per_change": EVASION_PER_DIRECTION_CHANGE,
		"max_evasion": MAX_EVASION,
		"direction_memory": DIRECTION_MEMORY
	}


## Get stats for this ability.
func get_stats() -> Dictionary:
	var total: int = _total_evades + (_total_attacks_received - _total_evades)
	var rate: float = 0.0
	if _total_attacks_received > 0:
		rate = float(_total_evades) / float(_total_attacks_received)

	return {
		"total_evades": _total_evades,
		"total_attacks_received": _total_attacks_received,
		"overall_evasion_rate": rate,
		"tracked_units": _unit_data.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var unit_data_export: Dictionary = {}
	for unit_id in _unit_data:
		var data: Dictionary = _unit_data[unit_id].duplicate()
		# Convert Vector3 to arrays for serialization
		data["last_position"] = [data["last_position"].x, data["last_position"].y, data["last_position"].z]
		data["last_direction"] = [data["last_direction"].x, data["last_direction"].y, data["last_direction"].z]
		var recent_dirs: Array = []
		for dir in data["recent_directions"]:
			recent_dirs.append([dir.x, dir.y, dir.z])
		data["recent_directions"] = recent_dirs
		unit_data_export[str(unit_id)] = data

	return {
		"unit_data": unit_data_export,
		"total_evades": _total_evades,
		"total_attacks_received": _total_attacks_received
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_total_evades = data.get("total_evades", 0)
	_total_attacks_received = data.get("total_attacks_received", 0)

	_unit_data.clear()
	for unit_id_str in data.get("unit_data", {}):
		var unit_data: Dictionary = data["unit_data"][unit_id_str].duplicate()
		# Convert arrays back to Vector3
		var pos: Array = unit_data.get("last_position", [0, 0, 0])
		unit_data["last_position"] = Vector3(pos[0], pos[1], pos[2])
		var dir: Array = unit_data.get("last_direction", [0, 0, 0])
		unit_data["last_direction"] = Vector3(dir[0], dir[1], dir[2])
		var recent: Array = []
		for d in unit_data.get("recent_directions", []):
			recent.append(Vector3(d[0], d[1], d[2]))
		unit_data["recent_directions"] = recent
		_unit_data[int(unit_id_str)] = unit_data


## Get summary for debugging.
func get_summary() -> Dictionary:
	var moving_units: int = 0
	var total_evasion: float = 0.0

	for unit_id in _unit_data:
		var evasion: float = _unit_data[unit_id]["current_evasion"]
		if evasion > 0:
			moving_units += 1
			total_evasion += evasion

	return {
		"tracked_units": _unit_data.size(),
		"moving_with_evasion": moving_units,
		"avg_evasion": "%.1f%%" % (total_evasion / maxf(1.0, moving_units) * 100),
		"total_evades": _total_evades
	}
