class_name UnitOwnershipManager
extends RefCounted
## UnitOwnershipManager coordinates ownership for all units.
## Provides efficient batch operations and faction queries.

signal unit_hacked(unit_id: int, original_faction: String, hacker_faction: String)
signal unit_mind_controlled(unit_id: int, original_faction: String, controller_faction: String)
signal unit_ownership_restored(unit_id: int, faction: String)
signal hack_expired(unit_id: int)
signal unhack_succeeded(unit_id: int)
signal mass_hack_completed(unit_ids: Array[int], hacker_faction: String)
signal visual_update_batch(unit_ids: Array[int], faction_id: String)

## Unit state machines (unit_id -> UnitStateMachine)
var _unit_machines: Dictionary = {}

## Faction unit lists (faction_id -> Array[int] of unit_ids)
var _faction_units: Dictionary = {}

## Hacked units per faction (faction_id -> Array[int] of hacked unit_ids)
var _hacked_by_faction: Dictionary = {}

## Statistics
var _stats: Dictionary = {
	"total_hacks": 0,
	"total_mind_controls": 0,
	"total_unhacks": 0,
	"hack_expirations": 0
}


func _init() -> void:
	pass


## Register unit for ownership tracking.
func register_unit(unit_id: int, faction_id: String) -> UnitStateMachine:
	var machine := UnitStateMachine.new(unit_id, faction_id)

	# Connect signals
	machine.state_changed.connect(_on_unit_state_changed.bind(unit_id))
	machine.hacking_expired.connect(_on_hacking_expired)
	machine.unhack_attempted.connect(_on_unhack_attempted)

	_unit_machines[unit_id] = machine

	# Add to faction list
	if not _faction_units.has(faction_id):
		_faction_units[faction_id] = []
	_faction_units[faction_id].append(unit_id)

	return machine


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	var machine: UnitStateMachine = _unit_machines.get(unit_id)
	if machine == null:
		return

	# Remove from faction lists
	var original := machine.original_faction
	if _faction_units.has(original):
		_faction_units[original].erase(unit_id)

	# Remove from hacked lists
	for faction_id in _hacked_by_faction:
		_hacked_by_faction[faction_id].erase(unit_id)

	_unit_machines.erase(unit_id)


## Process all unit state machines.
func process(delta: float) -> void:
	for unit_id in _unit_machines:
		var machine: UnitStateMachine = _unit_machines[unit_id]
		machine.process(delta)


## Hack a unit.
func hack_unit(unit_id: int, hacker_faction: String) -> bool:
	var machine: UnitStateMachine = _unit_machines.get(unit_id)
	if machine == null:
		return false

	var original := machine.original_faction
	var success := machine.attempt_hack(hacker_faction)

	if success:
		_stats["total_hacks"] += 1
		_track_hacked_unit(unit_id, hacker_faction)
		unit_hacked.emit(unit_id, original, hacker_faction)

	return success


## Mind control a unit.
func mind_control_unit(unit_id: int, controller_faction: String) -> bool:
	var machine: UnitStateMachine = _unit_machines.get(unit_id)
	if machine == null:
		return false

	var original := machine.original_faction
	var was_hacked := machine.is_hacked()
	var success := machine.attempt_mind_control(controller_faction)

	if success:
		_stats["total_mind_controls"] += 1

		# Remove from hacked tracking if was hacked
		if was_hacked:
			_untrack_hacked_unit(unit_id)

		unit_mind_controlled.emit(unit_id, original, controller_faction)

	return success


## Attempt unhack via damage.
func process_damage_for_unhack(unit_id: int, attacker_faction: String) -> bool:
	var machine: UnitStateMachine = _unit_machines.get(unit_id)
	if machine == null:
		return false

	return machine.on_damage_received(attacker_faction)


## Hack multiple units at once.
func mass_hack(unit_ids: Array[int], hacker_faction: String) -> Array[int]:
	var successfully_hacked: Array[int] = []

	for unit_id in unit_ids:
		if hack_unit(unit_id, hacker_faction):
			successfully_hacked.append(unit_id)

	if not successfully_hacked.is_empty():
		mass_hack_completed.emit(successfully_hacked, hacker_faction)
		visual_update_batch.emit(successfully_hacked, hacker_faction)

	return successfully_hacked


## Force release all units hacked by a faction.
func release_all_hacked_by(hacker_faction: String) -> Array[int]:
	var released: Array[int] = []
	var hacked_units: Array = _hacked_by_faction.get(hacker_faction, []).duplicate()

	for unit_id in hacked_units:
		var machine: UnitStateMachine = _unit_machines.get(unit_id)
		if machine != null and machine.is_hacked():
			machine.force_return_to_owner()
			released.append(unit_id)
			unit_ownership_restored.emit(unit_id, machine.original_faction)

	_hacked_by_faction[hacker_faction] = []

	return released


## Get unit state machine.
func get_unit_machine(unit_id: int) -> UnitStateMachine:
	return _unit_machines.get(unit_id)


## Get current owner of unit.
func get_unit_owner(unit_id: int) -> String:
	var machine: UnitStateMachine = _unit_machines.get(unit_id)
	return machine.owner_faction if machine != null else ""


## Get original owner of unit.
func get_original_owner(unit_id: int) -> String:
	var machine: UnitStateMachine = _unit_machines.get(unit_id)
	return machine.original_faction if machine != null else ""


## Check if unit is controlled by enemy.
func is_unit_controlled(unit_id: int) -> bool:
	var machine: UnitStateMachine = _unit_machines.get(unit_id)
	return machine.is_controlled() if machine != null else false


## Get all units owned by faction (original ownership).
func get_faction_units(faction_id: String) -> Array[int]:
	var result: Array[int] = []
	var units: Array = _faction_units.get(faction_id, [])
	for unit_id in units:
		result.append(unit_id)
	return result


## Get all units currently controlled by faction.
func get_units_controlled_by(faction_id: String) -> Array[int]:
	var controlled: Array[int] = []

	for unit_id in _unit_machines:
		var machine: UnitStateMachine = _unit_machines[unit_id]
		if machine.owner_faction == faction_id:
			controlled.append(unit_id)

	return controlled


## Get all hacked units.
func get_all_hacked_units() -> Array[int]:
	var hacked: Array[int] = []

	for unit_id in _unit_machines:
		var machine: UnitStateMachine = _unit_machines[unit_id]
		if machine.is_hacked():
			hacked.append(unit_id)

	return hacked


## Get units hacked by specific faction.
func get_units_hacked_by(hacker_faction: String) -> Array[int]:
	var result: Array[int] = []
	var units: Array = _hacked_by_faction.get(hacker_faction, [])
	for unit_id in units:
		result.append(unit_id)
	return result


## Track hacked unit.
func _track_hacked_unit(unit_id: int, hacker_faction: String) -> void:
	if not _hacked_by_faction.has(hacker_faction):
		_hacked_by_faction[hacker_faction] = []
	_hacked_by_faction[hacker_faction].append(unit_id)


## Untrack hacked unit.
func _untrack_hacked_unit(unit_id: int) -> void:
	for faction_id in _hacked_by_faction:
		_hacked_by_faction[faction_id].erase(unit_id)


## Handle unit state change.
func _on_unit_state_changed(old_state: int, new_state: int, unit_id: int) -> void:
	var machine: UnitStateMachine = _unit_machines.get(unit_id)
	if machine == null:
		return

	# Track ownership restoration
	if new_state == UnitOwnershipState.State.OWNED:
		if old_state == UnitOwnershipState.State.HACKED:
			_untrack_hacked_unit(unit_id)


## Handle hacking expiration.
func _on_hacking_expired(unit_id: int) -> void:
	_stats["hack_expirations"] += 1
	_untrack_hacked_unit(unit_id)
	hack_expired.emit(unit_id)


## Handle unhack attempt.
func _on_unhack_attempted(unit_id: int, success: bool) -> void:
	if success:
		_stats["total_unhacks"] += 1
		_untrack_hacked_unit(unit_id)
		unhack_succeeded.emit(unit_id)


## Get statistics.
func get_stats() -> Dictionary:
	return _stats.duplicate()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var machines_data: Dictionary = {}
	for unit_id in _unit_machines:
		machines_data[str(unit_id)] = _unit_machines[unit_id].to_dict()

	return {
		"unit_machines": machines_data,
		"stats": _stats.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_machines.clear()
	_faction_units.clear()
	_hacked_by_faction.clear()

	for unit_id_str in data.get("unit_machines", {}):
		var unit_id := int(unit_id_str)
		var machine := UnitStateMachine.from_dict(data["unit_machines"][unit_id_str])

		# Connect signals
		machine.state_changed.connect(_on_unit_state_changed.bind(unit_id))
		machine.hacking_expired.connect(_on_hacking_expired)
		machine.unhack_attempted.connect(_on_unhack_attempted)

		_unit_machines[unit_id] = machine

		# Rebuild faction lists
		var original := machine.original_faction
		if not _faction_units.has(original):
			_faction_units[original] = []
		_faction_units[original].append(unit_id)

		# Rebuild hacked lists
		if machine.is_hacked():
			_track_hacked_unit(unit_id, machine.hacker_faction)

	_stats = data.get("stats", {
		"total_hacks": 0,
		"total_mind_controls": 0,
		"total_unhacks": 0,
		"hack_expirations": 0
	}).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var hacked_count := 0
	var mind_controlled_count := 0

	for unit_id in _unit_machines:
		var machine: UnitStateMachine = _unit_machines[unit_id]
		if machine.is_hacked():
			hacked_count += 1
		elif machine.is_mind_controlled():
			mind_controlled_count += 1

	return {
		"total_units": _unit_machines.size(),
		"factions": _faction_units.size(),
		"hacked_units": hacked_count,
		"mind_controlled_units": mind_controlled_count,
		"stats": _stats
	}
