class_name HackedUnitVisuals
extends RefCounted
## HackedUnitVisuals manages visual feedback for hacked units.
## Handles color changes, glow effects, and indicators.

signal visual_transition_started(unit_id: int, target_faction: String)
signal visual_transition_completed(unit_id: int)
signal indicator_created(unit_id: int)
signal indicator_removed(unit_id: int)

## Visual configuration
var _config: HackVisualConfig = null

## Active visual states (unit_id -> visual_state)
var _visual_states: Dictionary = {}

## Indicator data (unit_id -> indicator_data)
var _indicators: Dictionary = {}


## Visual state data
class VisualState:
	var unit_id: int = -1
	var original_color: Color = Color.WHITE
	var original_emission: Color = Color.BLACK
	var current_color: Color = Color.WHITE
	var target_color: Color = Color.WHITE
	var transition_progress: float = 0.0
	var is_transitioning: bool = false
	var is_hacked: bool = false
	var hacker_faction: String = ""

	func _init() -> void:
		pass


func _init() -> void:
	_config = HackVisualConfig.new()


## Set configuration.
func set_config(config: HackVisualConfig) -> void:
	_config = config


## Get configuration.
func get_config() -> HackVisualConfig:
	return _config


## Apply hack visuals to unit.
func apply_hack_visuals(
	unit_id: int,
	hacker_faction: String,
	original_color: Color = Color.WHITE
) -> Dictionary:
	var state: VisualState

	if _visual_states.has(unit_id):
		state = _visual_states[unit_id]
	else:
		state = VisualState.new()
		state.unit_id = unit_id
		state.original_color = original_color
		_visual_states[unit_id] = state

	state.target_color = _config.get_faction_color(hacker_faction)
	state.transition_progress = 0.0
	state.is_transitioning = true
	state.is_hacked = true
	state.hacker_faction = hacker_faction

	visual_transition_started.emit(unit_id, hacker_faction)

	# Create indicator
	_create_indicator(unit_id, hacker_faction)

	# Return visual data for renderer
	return {
		"unit_id": unit_id,
		"target_color": state.target_color,
		"emission_color": state.target_color,
		"emission_intensity": _config.emission_intensity,
		"transition_duration": _config.transition_duration
	}


## Remove hack visuals from unit.
func remove_hack_visuals(unit_id: int) -> Dictionary:
	var state: VisualState = _visual_states.get(unit_id)
	if state == null:
		return {}

	state.target_color = state.original_color
	state.transition_progress = 0.0
	state.is_transitioning = true
	state.is_hacked = false
	state.hacker_faction = ""

	visual_transition_started.emit(unit_id, "")

	# Remove indicator
	_remove_indicator(unit_id)

	return {
		"unit_id": unit_id,
		"target_color": state.original_color,
		"emission_color": Color.BLACK,
		"emission_intensity": 0.0,
		"transition_duration": _config.transition_duration
	}


## Update transitions.
func update(delta: float) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []

	for unit_id in _visual_states:
		var state: VisualState = _visual_states[unit_id]

		if not state.is_transitioning:
			continue

		# Update progress
		state.transition_progress += delta / _config.transition_duration
		state.transition_progress = minf(state.transition_progress, 1.0)

		# Interpolate color (CUBIC EASE_OUT approximation)
		var t := state.transition_progress
		var eased := 1.0 - pow(1.0 - t, 3)  # Cubic ease out

		state.current_color = state.current_color.lerp(state.target_color, eased)

		# Check completion
		if state.transition_progress >= 1.0:
			state.is_transitioning = false
			state.current_color = state.target_color
			visual_transition_completed.emit(unit_id)

			completed.append({
				"unit_id": unit_id,
				"final_color": state.current_color,
				"is_hacked": state.is_hacked
			})

	return completed


## Create indicator for unit.
func _create_indicator(unit_id: int, hacker_faction: String) -> void:
	var indicator_data := {
		"unit_id": unit_id,
		"text": _config.indicator_text,
		"color": _config.get_faction_color(hacker_faction),
		"height": _config.indicator_height,
		"font_size": _config.indicator_font_size,
		"visible": true
	}

	_indicators[unit_id] = indicator_data
	indicator_created.emit(unit_id)


## Remove indicator for unit.
func _remove_indicator(unit_id: int) -> void:
	if _indicators.has(unit_id):
		_indicators.erase(unit_id)
		indicator_removed.emit(unit_id)


## Get current visual state for unit.
func get_visual_state(unit_id: int) -> Dictionary:
	var state: VisualState = _visual_states.get(unit_id)
	if state == null:
		return {}

	return {
		"unit_id": state.unit_id,
		"current_color": state.current_color,
		"target_color": state.target_color,
		"is_transitioning": state.is_transitioning,
		"is_hacked": state.is_hacked,
		"hacker_faction": state.hacker_faction,
		"transition_progress": state.transition_progress
	}


## Get indicator data for unit.
func get_indicator(unit_id: int) -> Dictionary:
	return _indicators.get(unit_id, {})


## Get all indicators.
func get_all_indicators() -> Dictionary:
	return _indicators.duplicate(true)


## Check if unit has visuals applied.
func has_visuals(unit_id: int) -> bool:
	return _visual_states.has(unit_id) and _visual_states[unit_id].is_hacked


## Remove unit completely (destroyed).
func remove_unit(unit_id: int) -> void:
	_visual_states.erase(unit_id)
	_remove_indicator(unit_id)


## Clear all visuals.
func clear() -> void:
	_visual_states.clear()
	_indicators.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var transitioning := 0
	var hacked := 0

	for unit_id in _visual_states:
		var state: VisualState = _visual_states[unit_id]
		if state.is_transitioning:
			transitioning += 1
		if state.is_hacked:
			hacked += 1

	return {
		"total_states": _visual_states.size(),
		"transitioning": transitioning,
		"hacked": hacked,
		"indicators": _indicators.size()
	}
