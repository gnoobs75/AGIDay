class_name Squad
extends RefCounted
## Squad represents a group of units that move and fight together.

signal unit_added(unit_id: int)
signal unit_removed(unit_id: int)
signal squad_disbanded()

## Squad ID
var squad_id: int = -1

## Faction ID
var faction_id: String = ""

## Unit IDs in squad
var _unit_ids: Array[int] = []

## Formation behavior
var behavior: FormationBehavior = null

## Casualty tracker
var casualty_tracker: CasualtyTracker = null

## Threat level (0.0 to 1.0)
var threat_level: float = 0.0

## Maximum squad size
const MAX_SQUAD_SIZE := 50

## Proximity threshold for auto-grouping (meters)
const PROXIMITY_THRESHOLD := 15.0


func _init(id: int = -1) -> void:
	squad_id = id
	behavior = FormationBehavior.new()
	casualty_tracker = CasualtyTracker.new()


## Configure squad for faction.
func configure_for_faction(faction: String) -> void:
	faction_id = faction
	behavior.configure_for_faction(faction)


## Add unit to squad.
func add_unit(unit_id: int) -> bool:
	if _unit_ids.size() >= MAX_SQUAD_SIZE:
		return false

	if unit_id in _unit_ids:
		return false

	_unit_ids.append(unit_id)
	unit_added.emit(unit_id)
	return true


## Remove unit from squad.
func remove_unit(unit_id: int) -> void:
	if unit_id in _unit_ids:
		_unit_ids.erase(unit_id)
		behavior.remove_unit(unit_id)
		unit_removed.emit(unit_id)

		if _unit_ids.is_empty():
			squad_disbanded.emit()


## Check if unit is in squad.
func has_unit(unit_id: int) -> bool:
	return unit_id in _unit_ids


## Get unit count.
func get_unit_count() -> int:
	return _unit_ids.size()


## Get all unit IDs.
func get_unit_ids() -> Array[int]:
	return _unit_ids.duplicate()


## Update squad with unit positions.
func update_positions(positions: Dictionary) -> void:
	# Filter to only squad units
	var squad_positions: Dictionary = {}
	for unit_id in _unit_ids:
		if positions.has(unit_id):
			squad_positions[unit_id] = positions[unit_id]

	behavior.update_center(squad_positions)


## Update squad (called each frame).
func update(delta: float, unit_positions: Dictionary) -> void:
	update_positions(unit_positions)
	behavior.update(delta)
	casualty_tracker.update(delta, _unit_ids.size())

	# Update tightness based on threat and casualties
	_update_adaptive_tightness()


## Update formation tightness adaptively.
func _update_adaptive_tightness() -> void:
	var casualty_rate := casualty_tracker.get_casualty_rate()

	# Prioritize threat over casualties for tightness
	if threat_level > 0.7 or casualty_rate > 0.3:
		behavior.set_tightness(0.8)
	elif threat_level > 0.4 or casualty_rate > 0.15:
		behavior.set_tightness(0.6)
	else:
		behavior.set_tightness(0.3)


## Set threat level.
func set_threat_level(level: float) -> void:
	threat_level = clampf(level, 0.0, 1.0)


## Get squad center.
func get_center() -> Vector3:
	return behavior.squad_center


## Get desired positions for all units.
func get_desired_positions() -> Dictionary:
	return behavior.get_all_desired_positions()


## Get desired position for specific unit.
func get_desired_position(unit_id: int) -> Vector3:
	return behavior.get_desired_position(unit_id)


## Record unit death.
func record_death(unit_id: int) -> void:
	remove_unit(unit_id)
	casualty_tracker.record_death()


## Check if position is within squad proximity.
func is_within_proximity(position: Vector3) -> bool:
	var distance := behavior.squad_center.distance_to(position)
	return distance <= PROXIMITY_THRESHOLD


## Merge another squad into this one.
func merge(other: Squad) -> void:
	for unit_id in other.get_unit_ids():
		if _unit_ids.size() < MAX_SQUAD_SIZE:
			add_unit(unit_id)


## Split squad at position (units past position go to new squad).
func split(split_position: Vector3, new_squad_id: int) -> Squad:
	var new_squad := Squad.new(new_squad_id)
	new_squad.configure_for_faction(faction_id)

	var to_move: Array[int] = []

	for unit_id in _unit_ids:
		if behavior.has_unit(unit_id):
			var pos: Vector3 = behavior._unit_positions.get(unit_id, Vector3.ZERO)
			if pos.distance_to(split_position) > PROXIMITY_THRESHOLD / 2.0:
				to_move.append(unit_id)

	for unit_id in to_move:
		remove_unit(unit_id)
		new_squad.add_unit(unit_id)

	return new_squad


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"squad_id": squad_id,
		"faction_id": faction_id,
		"unit_ids": _unit_ids.duplicate(),
		"behavior": behavior.to_dict(),
		"casualty_tracker": casualty_tracker.to_dict(),
		"threat_level": threat_level
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	squad_id = data.get("squad_id", -1)
	faction_id = data.get("faction_id", "")

	_unit_ids.clear()
	for unit_id in data.get("unit_ids", []):
		_unit_ids.append(unit_id)

	behavior.from_dict(data.get("behavior", {}))
	casualty_tracker.from_dict(data.get("casualty_tracker", {}))
	threat_level = data.get("threat_level", 0.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"squad_id": squad_id,
		"faction": faction_id,
		"units": _unit_ids.size(),
		"center": "%.1f, %.1f" % [behavior.squad_center.x, behavior.squad_center.z],
		"threat": "%.0f%%" % (threat_level * 100),
		"tightness": "%.0f%%" % (behavior.tightness * 100),
		"casualties": "%.0f%%" % (casualty_tracker.get_casualty_rate() * 100)
	}
