class_name UnitHackingComponent
extends RefCounted
## UnitHackingComponent provides hacking functionality integration for Unit class.
## Bridges state machine with AI and visual components.

signal hacking_state_changed(unit_id: int, old_state: int, new_state: int)
signal ai_behavior_changed(unit_id: int, behavior_type: String)
signal visual_appearance_changed(unit_id: int, faction_id: String)

## Hacking state
var _state: UnitHackingState = null

## Reference to AI component (set by Unit)
var ai_component = null

## Reference to visual component (set by Unit)
var visual_component = null

## Behavior configurations per state
var _behavior_configs: Dictionary = {
	"original": {},
	"hacker": {"aggressive": true, "target_original_faction": true},
	"controller": {"aggressive": true, "target_original_faction": true, "permanent": true}
}


func _init(unit_id: int = -1, faction_id: String = "") -> void:
	_state = UnitHackingState.new(unit_id, faction_id)

	# Connect state signals
	_state.behavior_switch_requested.connect(_on_behavior_switch_requested)
	_state.visual_switch_requested.connect(_on_visual_switch_requested)
	_state.state_entered.connect(_on_state_entered)


## Set AI component reference.
func set_ai_component(component) -> void:
	ai_component = component


## Set visual component reference.
func set_visual_component(component) -> void:
	visual_component = component


## Attempt to hack this unit.
func hack(hacker_faction: String) -> bool:
	if _state.is_enemy_controlled():
		return false

	var success := _state.transition_state(UnitHackingState.UnitState.HACKED, hacker_faction)

	if success:
		hacking_state_changed.emit(_state.unit_id, UnitHackingState.UnitState.OWNED, UnitHackingState.UnitState.HACKED)

	return success


## Attempt to mind control this unit.
func mind_control(controller_faction: String) -> bool:
	if _state.is_mind_controlled():
		return false

	var old_state := _state.current_state
	var success := _state.transition_state(UnitHackingState.UnitState.MIND_CONTROLLED, controller_faction)

	if success:
		hacking_state_changed.emit(_state.unit_id, old_state, UnitHackingState.UnitState.MIND_CONTROLLED)

	return success


## Restore unit to original owner.
func restore_to_owner() -> bool:
	if _state.is_owned():
		return false

	var old_state := _state.current_state
	var success := _state.transition_state(UnitHackingState.UnitState.OWNED)

	if success:
		hacking_state_changed.emit(_state.unit_id, old_state, UnitHackingState.UnitState.OWNED)

	return success


## Handle behavior switch request.
func _on_behavior_switch_requested(behavior_type: String) -> void:
	if ai_component != null and ai_component.has_method("switch_behavior"):
		var config: Dictionary = _behavior_configs.get(behavior_type, {})
		ai_component.switch_behavior(behavior_type, config)

	ai_behavior_changed.emit(_state.unit_id, behavior_type)


## Handle visual switch request.
func _on_visual_switch_requested(faction_id: String) -> void:
	if visual_component != null and visual_component.has_method("set_faction_appearance"):
		visual_component.set_faction_appearance(faction_id)

	visual_appearance_changed.emit(_state.unit_id, faction_id)


## Handle state entered.
func _on_state_entered(state: int) -> void:
	# Additional state entry logic can go here
	pass


## Get current state.
func get_state() -> int:
	return _state.current_state


## Get state object.
func get_state_object() -> UnitHackingState:
	return _state


## Check if owned.
func is_owned() -> bool:
	return _state.is_owned()


## Check if hacked.
func is_hacked() -> bool:
	return _state.is_hacked()


## Check if mind controlled.
func is_mind_controlled() -> bool:
	return _state.is_mind_controlled()


## Check if enemy controlled.
func is_enemy_controlled() -> bool:
	return _state.is_enemy_controlled()


## Get original faction.
func get_original_faction() -> String:
	return _state.original_faction


## Get current owner faction.
func get_current_owner() -> String:
	return _state.current_owner_faction


## Get controller faction.
func get_controller() -> String:
	return _state.controller_faction


## Get time in current state.
func get_time_in_state() -> int:
	return _state.get_time_in_state()


## Set behavior config.
func set_behavior_config(behavior_type: String, config: Dictionary) -> void:
	_behavior_configs[behavior_type] = config


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"state": _state.to_dict(),
		"behavior_configs": _behavior_configs.duplicate(true)
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_state = UnitHackingState.from_dict(data.get("state", {}))

	# Reconnect signals
	_state.behavior_switch_requested.connect(_on_behavior_switch_requested)
	_state.visual_switch_requested.connect(_on_visual_switch_requested)
	_state.state_entered.connect(_on_state_entered)

	_behavior_configs = data.get("behavior_configs", _behavior_configs).duplicate(true)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"state": _state.get_summary(),
		"has_ai": ai_component != null,
		"has_visual": visual_component != null
	}
