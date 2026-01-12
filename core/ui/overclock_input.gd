class_name OverclockInput
extends RefCounted
## OverclockInput handles keyboard controls for overclock adjustment.

signal overclock_increase_requested()
signal overclock_decrease_requested()
signal overclock_level_changed(level: float)

## Overclock range
const MIN_OVERCLOCK := 1.0
const MAX_OVERCLOCK := 2.0
const OVERCLOCK_STEP := 0.1

## Current state
var _current_level := 1.0
var _is_enabled := true
var _target_display: FactoryHeatDisplay = null


func _init() -> void:
	pass


## Bind to a FactoryHeatDisplay for direct control.
func bind_to_display(display: FactoryHeatDisplay) -> void:
	_target_display = display


## Unbind from display.
func unbind_display() -> void:
	_target_display = null


## Process input event. Call this from _input or _unhandled_input.
func handle_input(event: InputEvent) -> bool:
	if not _is_enabled:
		return false

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_UP:
					increase_overclock()
					return true
				KEY_DOWN:
					decrease_overclock()
					return true

	return false


## Increase overclock by one step.
func increase_overclock() -> void:
	if not _is_enabled:
		return

	var new_level := minf(_current_level + OVERCLOCK_STEP, MAX_OVERCLOCK)
	if not is_equal_approx(new_level, _current_level):
		_current_level = new_level
		_apply_overclock()
		overclock_increase_requested.emit()
		overclock_level_changed.emit(_current_level)


## Decrease overclock by one step.
func decrease_overclock() -> void:
	if not _is_enabled:
		return

	var new_level := maxf(_current_level - OVERCLOCK_STEP, MIN_OVERCLOCK)
	if not is_equal_approx(new_level, _current_level):
		_current_level = new_level
		_apply_overclock()
		overclock_decrease_requested.emit()
		overclock_level_changed.emit(_current_level)


## Apply current overclock to bound display.
func _apply_overclock() -> void:
	if _target_display != null:
		_target_display.set_overclock_multiplier(_current_level)


## Set overclock level directly.
func set_overclock_level(level: float) -> void:
	_current_level = clampf(level, MIN_OVERCLOCK, MAX_OVERCLOCK)
	_apply_overclock()
	overclock_level_changed.emit(_current_level)


## Get current overclock level.
func get_overclock_level() -> float:
	return _current_level


## Enable input handling.
func set_enabled(enabled: bool) -> void:
	_is_enabled = enabled


## Is input handling enabled.
func is_enabled() -> bool:
	return _is_enabled


## Handle factory melted down - disable controls.
func on_factory_melted_down() -> void:
	_is_enabled = false


## Handle factory recovered - re-enable controls.
func on_factory_recovered() -> void:
	_is_enabled = true


## Reset to default overclock level.
func reset() -> void:
	_current_level = MIN_OVERCLOCK
	_apply_overclock()
	overclock_level_changed.emit(_current_level)


## Cleanup.
func cleanup() -> void:
	_target_display = null
