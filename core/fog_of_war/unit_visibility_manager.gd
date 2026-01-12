class_name UnitVisibilityManager
extends RefCounted
## UnitVisibilityManager controls unit visibility based on fog of war.
## Bridges fog of war grid with unit rendering and interaction.

signal unit_became_visible(observer_faction: String, unit_id: int)
signal unit_became_hidden(observer_faction: String, unit_id: int)
signal last_known_updated(faction_id: String, unit_id: int, position: Vector3)

## Configuration
const LAST_KNOWN_EXPIRE_TIME := 120.0  ## Seconds before last-known expires
const BATCH_SIZE := 100  ## Units to process per frame

## Unit data (unit_id -> data)
var _units: Dictionary = {}

## Visibility per faction (faction_id -> {unit_id -> is_visible})
var _visibility_states: Dictionary = {}

## Last known positions (faction_id -> {unit_id -> {position, type, time}})
var _last_known: Dictionary = {}

## Pending visibility updates queue
var _pending_updates: Array[int] = []

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _get_unit_faction: Callable  ## (unit_id) -> String
var _get_unit_type: Callable  ## (unit_id) -> String
var _is_visible_to_faction: Callable  ## (faction_id, voxel_x, voxel_z) -> bool
var _show_unit: Callable  ## (unit_id) -> void
var _hide_unit: Callable  ## (unit_id) -> void

## Fog of war reference
var _fog_system: FogOfWarSystem = null


func _init() -> void:
	pass


## Set fog of war system reference.
func set_fog_system(system: FogOfWarSystem) -> void:
	_fog_system = system


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_faction(callback: Callable) -> void:
	_get_unit_faction = callback


func set_get_unit_type(callback: Callable) -> void:
	_get_unit_type = callback


func set_is_visible_to_faction(callback: Callable) -> void:
	_is_visible_to_faction = callback


func set_show_unit(callback: Callable) -> void:
	_show_unit = callback


func set_hide_unit(callback: Callable) -> void:
	_hide_unit = callback


## Register unit.
func register_unit(unit_id: int, faction_id: String, unit_type: String) -> void:
	_units[unit_id] = {
		"faction_id": faction_id,
		"unit_type": unit_type,
		"position": Vector3.ZERO
	}

	_pending_updates.append(unit_id)


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	var data: Dictionary = _units.get(unit_id, {})

	_units.erase(unit_id)

	# Clear visibility states for this unit
	for faction_id in _visibility_states:
		_visibility_states[faction_id].erase(unit_id)

	# Keep last-known for enemies
	if not data.is_empty():
		_record_last_known(unit_id, data)

	var idx := _pending_updates.find(unit_id)
	if idx != -1:
		_pending_updates.remove_at(idx)


## Update unit position.
func update_unit_position(unit_id: int, position: Vector3) -> void:
	if not _units.has(unit_id):
		return

	var old_pos: Vector3 = _units[unit_id]["position"]
	_units[unit_id]["position"] = position

	# Queue update if moved significantly
	if old_pos.distance_to(position) > 1.0:
		if unit_id not in _pending_updates:
			_pending_updates.append(unit_id)


## Check if unit is visible to faction.
func is_unit_visible_to_faction(unit_id: int, observer_faction: String) -> bool:
	if not _units.has(unit_id):
		return false

	var unit_data: Dictionary = _units[unit_id]
	var unit_faction: String = unit_data["faction_id"]

	# Own faction units always visible
	if unit_faction == observer_faction:
		return true

	# Check visibility state
	if not _visibility_states.has(observer_faction):
		return false

	return _visibility_states[observer_faction].get(unit_id, false)


## Check if unit can be targeted by faction.
func can_target_unit(unit_id: int, attacker_faction: String) -> bool:
	return is_unit_visible_to_faction(unit_id, attacker_faction)


## Check if unit can be selected by faction.
func can_select_unit(unit_id: int, selector_faction: String) -> bool:
	if not _units.has(unit_id):
		return false

	var unit_faction: String = _units[unit_id]["faction_id"]

	# Can always select own units
	if unit_faction == selector_faction:
		return true

	# Can only select visible enemy units
	return is_unit_visible_to_faction(unit_id, selector_faction)


## Process pending visibility updates.
func process_updates() -> int:
	if _pending_updates.is_empty():
		return 0

	var processed := 0
	var batch_end := mini(BATCH_SIZE, _pending_updates.size())

	for i in batch_end:
		var unit_id: int = _pending_updates[0]
		_pending_updates.remove_at(0)

		if _units.has(unit_id):
			_update_unit_visibility(unit_id)
			processed += 1

	return processed


## Update visibility for single unit.
func _update_unit_visibility(unit_id: int) -> void:
	if not _units.has(unit_id):
		return

	var unit_data: Dictionary = _units[unit_id]
	var unit_faction: String = unit_data["faction_id"]
	var position: Vector3 = unit_data["position"]

	# Get voxel coordinates
	var voxel_x := int(floor(position.x))
	var voxel_z := int(floor(position.z))

	# Check visibility for each faction
	for observer_faction in _get_all_factions():
		if observer_faction == unit_faction:
			continue  ## Own units always visible

		var was_visible := _get_visibility_state(observer_faction, unit_id)
		var is_visible := _check_visibility(observer_faction, voxel_x, voxel_z)

		if is_visible != was_visible:
			_set_visibility_state(observer_faction, unit_id, is_visible)

			if is_visible:
				unit_became_visible.emit(observer_faction, unit_id)
				_apply_visibility(unit_id, observer_faction, true)
			else:
				unit_became_hidden.emit(observer_faction, unit_id)
				_apply_visibility(unit_id, observer_faction, false)
				_record_last_known(unit_id, unit_data)


## Check fog of war visibility.
func _check_visibility(faction_id: String, voxel_x: int, voxel_z: int) -> bool:
	if _is_visible_to_faction.is_valid():
		return _is_visible_to_faction.call(faction_id, voxel_x, voxel_z)

	if _fog_system != null:
		return _fog_system.is_visible_to_faction(faction_id, voxel_x, voxel_z)

	return true  ## Default visible if no fog system


## Get visibility state from cache.
func _get_visibility_state(faction_id: String, unit_id: int) -> bool:
	if not _visibility_states.has(faction_id):
		return false
	return _visibility_states[faction_id].get(unit_id, false)


## Set visibility state in cache.
func _set_visibility_state(faction_id: String, unit_id: int, is_visible: bool) -> void:
	if not _visibility_states.has(faction_id):
		_visibility_states[faction_id] = {}
	_visibility_states[faction_id][unit_id] = is_visible


## Apply visibility (show/hide unit).
func _apply_visibility(unit_id: int, observer_faction: String, visible: bool) -> void:
	if visible:
		if _show_unit.is_valid():
			_show_unit.call(unit_id)
	else:
		if _hide_unit.is_valid():
			_hide_unit.call(unit_id)


## Record last known position.
func _record_last_known(unit_id: int, unit_data: Dictionary) -> void:
	var unit_faction: String = unit_data["faction_id"]
	var position: Vector3 = unit_data["position"]
	var unit_type: String = unit_data["unit_type"]
	var current_time := Time.get_ticks_msec() / 1000.0

	for observer_faction in _get_all_factions():
		if observer_faction == unit_faction:
			continue

		if not _last_known.has(observer_faction):
			_last_known[observer_faction] = {}

		_last_known[observer_faction][unit_id] = {
			"position": position,
			"unit_type": unit_type,
			"time": current_time
		}

		last_known_updated.emit(observer_faction, unit_id, position)


## Get last known position for unit.
func get_last_known(observer_faction: String, unit_id: int) -> Dictionary:
	if not _last_known.has(observer_faction):
		return {}

	if not _last_known[observer_faction].has(unit_id):
		return {}

	var data: Dictionary = _last_known[observer_faction][unit_id]
	var age := (Time.get_ticks_msec() / 1000.0) - data["time"]

	if age > LAST_KNOWN_EXPIRE_TIME:
		_last_known[observer_faction].erase(unit_id)
		return {}

	return data


## Get all last known positions for faction.
func get_all_last_known(observer_faction: String) -> Dictionary:
	if not _last_known.has(observer_faction):
		return {}

	var result: Dictionary = {}
	var current_time := Time.get_ticks_msec() / 1000.0

	for unit_id in _last_known[observer_faction]:
		var data: Dictionary = _last_known[observer_faction][unit_id]
		var age := current_time - data["time"]

		if age <= LAST_KNOWN_EXPIRE_TIME:
			result[unit_id] = data.duplicate()
			result[unit_id]["age"] = age

	return result


## Clear expired last-known entries.
func cleanup_last_known() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0

	for faction_id in _last_known:
		var to_remove: Array[int] = []

		for unit_id in _last_known[faction_id]:
			var age := current_time - _last_known[faction_id][unit_id]["time"]
			if age > LAST_KNOWN_EXPIRE_TIME:
				to_remove.append(unit_id)

		for unit_id in to_remove:
			_last_known[faction_id].erase(unit_id)


## Get all factions.
func _get_all_factions() -> Array[String]:
	var factions: Array[String] = []

	for unit_id in _units:
		var faction: String = _units[unit_id]["faction_id"]
		if faction not in factions:
			factions.append(faction)

	return factions


## Get visible units for faction.
func get_visible_units(observer_faction: String) -> Array[int]:
	var visible: Array[int] = []

	for unit_id in _units:
		if is_unit_visible_to_faction(unit_id, observer_faction):
			visible.append(unit_id)

	return visible


## Get hidden enemy units for faction.
func get_hidden_enemy_units(observer_faction: String) -> Array[int]:
	var hidden: Array[int] = []

	for unit_id in _units:
		var unit_faction: String = _units[unit_id]["faction_id"]

		if unit_faction == observer_faction:
			continue

		if not is_unit_visible_to_faction(unit_id, observer_faction):
			hidden.append(unit_id)

	return hidden


## Serialization.
func to_dict() -> Dictionary:
	var last_known_data: Dictionary = {}
	for faction_id in _last_known:
		last_known_data[faction_id] = {}
		for unit_id in _last_known[faction_id]:
			var data: Dictionary = _last_known[faction_id][unit_id]
			last_known_data[faction_id][str(unit_id)] = {
				"position": {"x": data["position"].x, "y": data["position"].y, "z": data["position"].z},
				"unit_type": data["unit_type"],
				"time": data["time"]
			}

	return {
		"visibility_states": _visibility_states.duplicate(true),
		"last_known": last_known_data
	}


func from_dict(data: Dictionary) -> void:
	_visibility_states = data.get("visibility_states", {}).duplicate(true)

	_last_known.clear()
	var last_known_data: Dictionary = data.get("last_known", {})
	for faction_id in last_known_data:
		_last_known[faction_id] = {}
		for unit_id_str in last_known_data[faction_id]:
			var unit_data: Dictionary = last_known_data[faction_id][unit_id_str]
			var pos: Dictionary = unit_data["position"]
			_last_known[faction_id][int(unit_id_str)] = {
				"position": Vector3(pos["x"], pos["y"], pos["z"]),
				"unit_type": unit_data["unit_type"],
				"time": unit_data["time"]
			}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_visible_counts: Dictionary = {}

	for faction_id in _visibility_states:
		var visible_count := 0
		for unit_id in _visibility_states[faction_id]:
			if _visibility_states[faction_id][unit_id]:
				visible_count += 1
		faction_visible_counts[faction_id] = visible_count

	return {
		"registered_units": _units.size(),
		"pending_updates": _pending_updates.size(),
		"visibility_by_faction": faction_visible_counts,
		"last_known_entries": _last_known.size()
	}
