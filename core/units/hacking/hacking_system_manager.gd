class_name HackingSystemManager
extends RefCounted
## HackingSystemManager coordinates hacking across all units.
## Provides high-level API for hacking operations.

signal unit_hacked(unit_id: int, original_faction: String, hacker_faction: String)
signal unit_unhacked(unit_id: int, faction: String)
signal unit_mind_controlled(unit_id: int, original_faction: String, controller_faction: String)
signal mass_hack_completed(unit_ids: Array[int], hacker_faction: String)

## Registered units (unit_id -> UnitHackingComponent)
var _units: Dictionary = {}

## Statistics
var _stats: Dictionary = {
	"total_hacks": 0,
	"active_hacked": 0,
	"total_mind_controls": 0,
	"active_mind_controlled": 0,
	"total_restorations": 0
}


func _init() -> void:
	pass


## Register unit for hacking.
func register_unit(unit_id: int, faction_id: String) -> UnitHackingComponent:
	var component := UnitHackingComponent.new(unit_id, faction_id)

	# Connect signals
	component.hacking_state_changed.connect(_on_unit_state_changed)

	_units[unit_id] = component
	return component


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	if _units.has(unit_id):
		var component: UnitHackingComponent = _units[unit_id]
		if component.is_hacked():
			_stats["active_hacked"] -= 1
		elif component.is_mind_controlled():
			_stats["active_mind_controlled"] -= 1

		_units.erase(unit_id)


## Hack unit.
func hack_unit(unit_id: int, hacker_faction: String) -> bool:
	var component: UnitHackingComponent = _units.get(unit_id)
	if component == null:
		return false

	var original := component.get_original_faction()
	var success := component.hack(hacker_faction)

	if success:
		_stats["total_hacks"] += 1
		_stats["active_hacked"] += 1
		unit_hacked.emit(unit_id, original, hacker_faction)

	return success


## Mind control unit.
func mind_control_unit(unit_id: int, controller_faction: String) -> bool:
	var component: UnitHackingComponent = _units.get(unit_id)
	if component == null:
		return false

	var original := component.get_original_faction()
	var was_hacked := component.is_hacked()
	var success := component.mind_control(controller_faction)

	if success:
		_stats["total_mind_controls"] += 1
		_stats["active_mind_controlled"] += 1

		if was_hacked:
			_stats["active_hacked"] -= 1

		unit_mind_controlled.emit(unit_id, original, controller_faction)

	return success


## Restore unit to original owner.
func restore_unit(unit_id: int) -> bool:
	var component: UnitHackingComponent = _units.get(unit_id)
	if component == null:
		return false

	var was_hacked := component.is_hacked()
	var was_mind_controlled := component.is_mind_controlled()
	var faction := component.get_original_faction()
	var success := component.restore_to_owner()

	if success:
		_stats["total_restorations"] += 1

		if was_hacked:
			_stats["active_hacked"] -= 1
		elif was_mind_controlled:
			_stats["active_mind_controlled"] -= 1

		unit_unhacked.emit(unit_id, faction)

	return success


## Mass hack multiple units.
func mass_hack(unit_ids: Array[int], hacker_faction: String) -> Array[int]:
	var successfully_hacked: Array[int] = []

	for unit_id in unit_ids:
		if hack_unit(unit_id, hacker_faction):
			successfully_hacked.append(unit_id)

	if not successfully_hacked.is_empty():
		mass_hack_completed.emit(successfully_hacked, hacker_faction)

	return successfully_hacked


## Restore all hacked units by faction.
func restore_all_by_hacker(hacker_faction: String) -> Array[int]:
	var restored: Array[int] = []

	for unit_id in _units:
		var component: UnitHackingComponent = _units[unit_id]
		if component.is_hacked() and component.get_controller() == hacker_faction:
			if restore_unit(unit_id):
				restored.append(unit_id)

	return restored


## Get unit component.
func get_unit_component(unit_id: int) -> UnitHackingComponent:
	return _units.get(unit_id)


## Check if unit is hacked.
func is_unit_hacked(unit_id: int) -> bool:
	var component: UnitHackingComponent = _units.get(unit_id)
	return component.is_hacked() if component != null else false


## Check if unit is mind controlled.
func is_unit_mind_controlled(unit_id: int) -> bool:
	var component: UnitHackingComponent = _units.get(unit_id)
	return component.is_mind_controlled() if component != null else false


## Get current owner of unit.
func get_unit_owner(unit_id: int) -> String:
	var component: UnitHackingComponent = _units.get(unit_id)
	return component.get_current_owner() if component != null else ""


## Get all hacked units.
func get_hacked_units() -> Array[int]:
	var hacked: Array[int] = []
	for unit_id in _units:
		if _units[unit_id].is_hacked():
			hacked.append(unit_id)
	return hacked


## Get all mind controlled units.
func get_mind_controlled_units() -> Array[int]:
	var controlled: Array[int] = []
	for unit_id in _units:
		if _units[unit_id].is_mind_controlled():
			controlled.append(unit_id)
	return controlled


## Get units controlled by faction.
func get_units_controlled_by(faction_id: String) -> Array[int]:
	var result: Array[int] = []
	for unit_id in _units:
		var component: UnitHackingComponent = _units[unit_id]
		if component.get_current_owner() == faction_id:
			result.append(unit_id)
	return result


## Handle unit state change.
func _on_unit_state_changed(unit_id: int, old_state: int, new_state: int) -> void:
	# Stats are updated in individual methods
	pass


## Get statistics.
func get_stats() -> Dictionary:
	return _stats.duplicate()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var units_data: Dictionary = {}
	for unit_id in _units:
		units_data[str(unit_id)] = _units[unit_id].to_dict()

	return {
		"units": units_data,
		"stats": _stats.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_units.clear()

	for unit_id_str in data.get("units", {}):
		var unit_id := int(unit_id_str)
		var component := UnitHackingComponent.new()
		component.from_dict(data["units"][unit_id_str])
		component.hacking_state_changed.connect(_on_unit_state_changed)
		_units[unit_id] = component

	_stats = data.get("stats", _stats).duplicate()

	# Recalculate active counts
	_stats["active_hacked"] = 0
	_stats["active_mind_controlled"] = 0
	for unit_id in _units:
		var component: UnitHackingComponent = _units[unit_id]
		if component.is_hacked():
			_stats["active_hacked"] += 1
		elif component.is_mind_controlled():
			_stats["active_mind_controlled"] += 1


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"registered_units": _units.size(),
		"stats": _stats
	}
