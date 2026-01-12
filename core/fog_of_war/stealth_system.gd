class_name StealthSystem
extends RefCounted
## StealthSystem manages stealth units and detection mechanics.

signal unit_entered_stealth(unit_id: int)
signal unit_exited_stealth(unit_id: int, reason: String)
signal unit_detected(stealth_unit_id: int, detector_id: int)

## Configuration
const STEALTH_DETECTION_RANGE := 2.0  ## Base detection range

## Stealthed units (unit_id -> stealth_data)
var _stealthed_units: Dictionary = {}

## Detector units (unit_id -> detector_data)
var _detectors: Dictionary = {}

## Callbacks
var _get_unit_position: Callable
var _get_unit_faction: Callable


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_faction(callback: Callable) -> void:
	_get_unit_faction = callback


## Enter stealth.
func enter_stealth(unit_id: int) -> bool:
	if _stealthed_units.has(unit_id):
		return false  ## Already stealthed

	_stealthed_units[unit_id] = {
		"enter_time": Time.get_ticks_msec() / 1000.0,
		"last_position": Vector3.ZERO
	}

	unit_entered_stealth.emit(unit_id)
	return true


## Exit stealth.
func exit_stealth(unit_id: int, reason: String = "manual") -> bool:
	if not _stealthed_units.has(unit_id):
		return false

	_stealthed_units.erase(unit_id)
	unit_exited_stealth.emit(unit_id, reason)
	return true


## Check if unit is stealthed.
func is_stealthed(unit_id: int) -> bool:
	return _stealthed_units.has(unit_id)


## Register detector unit.
func register_detector(unit_id: int, detection_range: float = -1.0) -> void:
	_detectors[unit_id] = {
		"detection_range": detection_range if detection_range > 0 else STEALTH_DETECTION_RANGE,
		"can_always_detect": detection_range < 0  ## Negative means always detect
	}


## Unregister detector.
func unregister_detector(unit_id: int) -> void:
	_detectors.erase(unit_id)


## Check if unit is detected by any enemy detector.
func is_detected(unit_id: int) -> bool:
	if not _stealthed_units.has(unit_id):
		return true  ## Not stealthed = always detected

	if not _get_unit_position.is_valid() or not _get_unit_faction.is_valid():
		return false

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	var unit_faction: String = _get_unit_faction.call(unit_id)

	for detector_id in _detectors:
		var detector_faction: String = _get_unit_faction.call(detector_id)

		if detector_faction == unit_faction:
			continue  ## Friendly detector

		var detector_data: Dictionary = _detectors[detector_id]

		if detector_data["can_always_detect"]:
			unit_detected.emit(unit_id, detector_id)
			return true

		var detector_pos: Vector3 = _get_unit_position.call(detector_id)
		var distance := unit_pos.distance_to(detector_pos)

		if distance <= detector_data["detection_range"]:
			unit_detected.emit(unit_id, detector_id)
			return true

	return false


## Check detection and break stealth if detected.
func update_detection(unit_id: int) -> void:
	if not is_stealthed(unit_id):
		return

	if is_detected(unit_id):
		exit_stealth(unit_id, "detected")


## Break stealth on attack.
func on_unit_attacked(unit_id: int) -> void:
	if is_stealthed(unit_id):
		exit_stealth(unit_id, "attack")


## Check if stealthed unit is visible to observer faction.
func is_visible_to_faction(unit_id: int, observer_faction: String) -> bool:
	if not is_stealthed(unit_id):
		return true  ## Not stealthed = visible (subject to fog of war)

	if not _get_unit_faction.is_valid():
		return false

	var unit_faction: String = _get_unit_faction.call(unit_id)

	# Own faction can always see
	if unit_faction == observer_faction:
		return true

	# Check if any friendly detector can see
	if not _get_unit_position.is_valid():
		return false

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)

	for detector_id in _detectors:
		var detector_faction: String = _get_unit_faction.call(detector_id)

		if detector_faction != observer_faction:
			continue

		var detector_data: Dictionary = _detectors[detector_id]

		if detector_data["can_always_detect"]:
			return true

		var detector_pos: Vector3 = _get_unit_position.call(detector_id)
		var distance := unit_pos.distance_to(detector_pos)

		if distance <= detector_data["detection_range"]:
			return true

	return false


## Get all stealthed units.
func get_stealthed_units() -> Array[int]:
	var units: Array[int] = []
	for unit_id in _stealthed_units:
		units.append(unit_id)
	return units


## Get all detectors.
func get_detectors() -> Array[int]:
	var units: Array[int] = []
	for unit_id in _detectors:
		units.append(unit_id)
	return units


## Serialization.
func to_dict() -> Dictionary:
	var stealthed_data: Dictionary = {}
	for unit_id in _stealthed_units:
		stealthed_data[str(unit_id)] = _stealthed_units[unit_id].duplicate()

	var detector_data: Dictionary = {}
	for unit_id in _detectors:
		detector_data[str(unit_id)] = _detectors[unit_id].duplicate()

	return {
		"stealthed_units": stealthed_data,
		"detectors": detector_data
	}


func from_dict(data: Dictionary) -> void:
	_stealthed_units.clear()
	var stealthed_data: Dictionary = data.get("stealthed_units", {})
	for unit_id_str in stealthed_data:
		_stealthed_units[int(unit_id_str)] = stealthed_data[unit_id_str].duplicate()

	_detectors.clear()
	var detector_data: Dictionary = data.get("detectors", {})
	for unit_id_str in detector_data:
		_detectors[int(unit_id_str)] = detector_data[unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"stealthed_count": _stealthed_units.size(),
		"detector_count": _detectors.size(),
		"detection_range": STEALTH_DETECTION_RANGE
	}
