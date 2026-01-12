class_name HackVisualManager
extends RefCounted
## HackVisualManager coordinates visual feedback for all hacked units.
## Provides high-level API for rendering integration.

signal visual_update_required(unit_id: int, visual_data: Dictionary)
signal indicator_update_required(indicators: Dictionary)

## Visual handler
var _visuals: HackedUnitVisuals = null

## Pending visual updates
var _pending_updates: Array[Dictionary] = []

## Performance tracking
var _last_update_time_ms: float = 0.0


func _init() -> void:
	_visuals = HackedUnitVisuals.new()

	# Connect signals
	_visuals.visual_transition_started.connect(_on_transition_started)
	_visuals.visual_transition_completed.connect(_on_transition_completed)


## Set configuration.
func set_config(config: HackVisualConfig) -> void:
	_visuals.set_config(config)


## Apply hack visuals.
func apply_hack_visuals(
	unit_id: int,
	hacker_faction: String,
	original_color: Color = Color.WHITE
) -> void:
	var visual_data := _visuals.apply_hack_visuals(unit_id, hacker_faction, original_color)
	_pending_updates.append(visual_data)
	visual_update_required.emit(unit_id, visual_data)


## Remove hack visuals.
func remove_hack_visuals(unit_id: int) -> void:
	var visual_data := _visuals.remove_hack_visuals(unit_id)
	if not visual_data.is_empty():
		_pending_updates.append(visual_data)
		visual_update_required.emit(unit_id, visual_data)


## Update all visuals.
func update(delta: float) -> void:
	var start_time := Time.get_ticks_usec()

	var completed := _visuals.update(delta)

	for data in completed:
		visual_update_required.emit(data["unit_id"], data)

	_last_update_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0

	# Clear pending updates after processing
	_pending_updates.clear()


## Handle unit destroyed.
func on_unit_destroyed(unit_id: int) -> void:
	_visuals.remove_unit(unit_id)


## Get visual state for unit.
func get_visual_state(unit_id: int) -> Dictionary:
	return _visuals.get_visual_state(unit_id)


## Get all indicators for rendering.
func get_indicators() -> Dictionary:
	return _visuals.get_all_indicators()


## Check if unit has hack visuals.
func has_hack_visuals(unit_id: int) -> bool:
	return _visuals.has_visuals(unit_id)


## Get visuals handler.
func get_visuals() -> HackedUnitVisuals:
	return _visuals


## Get pending updates.
func get_pending_updates() -> Array[Dictionary]:
	return _pending_updates


## Get update time.
func get_last_update_time_ms() -> float:
	return _last_update_time_ms


## Handle transition started.
func _on_transition_started(unit_id: int, target_faction: String) -> void:
	pass


## Handle transition completed.
func _on_transition_completed(unit_id: int) -> void:
	# Emit indicator update
	indicator_update_required.emit(_visuals.get_all_indicators())


## Clear all.
func clear() -> void:
	_visuals.clear()
	_pending_updates.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"visuals": _visuals.get_summary(),
		"pending_updates": _pending_updates.size(),
		"last_update_ms": _last_update_time_ms
	}
