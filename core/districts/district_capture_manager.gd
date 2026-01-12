class_name DistrictCaptureManager
extends RefCounted
## DistrictCaptureManager coordinates capture progress across all districts.
## Uses event-driven updates for performance optimization.

signal district_captured(district_id: int, new_owner: String, old_owner: String)
signal district_contested(district_id: int, factions: Array)
signal capture_progress_updated(district_id: int, faction_id: String, progress: float)

## Sync interval for multiplayer (seconds)
const SYNC_INTERVAL := 0.5

## Reference to district manager
var _district_manager: DistrictManager = null

## Capture progress trackers (district_id -> CaptureProgressTracker)
var _trackers: Dictionary = {}

## Unit-district associations (unit_id -> district_id)
var _unit_districts: Dictionary = {}

## Time since last sync
var _sync_accumulator: float = 0.0

## Performance tracking
var _last_process_time_us: int = 0


func _init(district_manager: DistrictManager = null) -> void:
	if district_manager != null:
		set_district_manager(district_manager)


## Set district manager and initialize trackers.
func set_district_manager(manager: DistrictManager) -> void:
	_district_manager = manager
	_initialize_trackers()


## Initialize trackers for all districts.
func _initialize_trackers() -> void:
	_trackers.clear()

	if _district_manager == null:
		return

	for i in _district_manager.get_total_district_count():
		var tracker := CaptureProgressTracker.new(i)

		# Set initial owner from district
		var district := _district_manager.get_district(i)
		if district != null:
			tracker.owner_faction = district.owner_faction

		# Connect signals
		tracker.capture_complete.connect(_on_capture_complete.bind(i))
		tracker.contested_status_changed.connect(_on_contested_changed.bind(i))
		tracker.progress_changed.connect(_on_progress_changed.bind(i))

		_trackers[i] = tracker


## Handle capture completion.
func _on_capture_complete(new_owner: String, old_owner: String, district_id: int) -> void:
	# Update district manager
	if _district_manager != null:
		_district_manager.set_district_owner(district_id, new_owner)

	district_captured.emit(district_id, new_owner, old_owner)


## Handle contested status change.
func _on_contested_changed(is_contested: bool, district_id: int) -> void:
	var tracker: CaptureProgressTracker = _trackers.get(district_id)
	if tracker == null:
		return

	if is_contested:
		district_contested.emit(district_id, tracker.unit_counts.keys())


## Handle progress change.
func _on_progress_changed(faction_id: String, progress: float, district_id: int) -> void:
	capture_progress_updated.emit(district_id, faction_id, progress)


## Unit entered a district (event-driven).
func on_unit_entered_district(unit_id: int, faction_id: String, position: Vector3) -> void:
	if _district_manager == null:
		return

	var district_id := _district_manager.get_district_id_at_position(position)
	if district_id < 0:
		return

	# Update unit-district association
	var old_district: int = _unit_districts.get(unit_id, -1)
	if old_district == district_id:
		return  # Same district

	# Remove from old district
	if old_district >= 0:
		var old_tracker: CaptureProgressTracker = _trackers.get(old_district)
		if old_tracker != null:
			old_tracker.unit_exited(faction_id)

	# Add to new district
	var tracker: CaptureProgressTracker = _trackers.get(district_id)
	if tracker != null:
		tracker.unit_entered(faction_id)

	_unit_districts[unit_id] = district_id


## Unit exited game (destroyed, etc.).
func on_unit_removed(unit_id: int, faction_id: String) -> void:
	var district_id: int = _unit_districts.get(unit_id, -1)
	if district_id < 0:
		return

	var tracker: CaptureProgressTracker = _trackers.get(district_id)
	if tracker != null:
		tracker.unit_exited(faction_id)

	_unit_districts.erase(unit_id)


## Batch update unit positions (for initialization or reconnection).
func update_all_unit_positions(unit_positions: Dictionary) -> void:
	# unit_positions: {unit_id: {faction_id: String, position: Vector3}}
	if _district_manager == null:
		return

	# Reset all trackers
	for tracker in _trackers.values():
		tracker.unit_counts.clear()

	_unit_districts.clear()

	# Count units per district per faction
	var district_counts: Dictionary = {}  # district_id -> {faction_id -> count}

	for unit_id in unit_positions:
		var data: Dictionary = unit_positions[unit_id]
		var faction_id: String = data.get("faction_id", "")
		var position: Vector3 = data.get("position", Vector3.ZERO)

		var district_id := _district_manager.get_district_id_at_position(position)
		if district_id < 0:
			continue

		_unit_districts[unit_id] = district_id

		if not district_counts.has(district_id):
			district_counts[district_id] = {}
		if not district_counts[district_id].has(faction_id):
			district_counts[district_id][faction_id] = 0

		district_counts[district_id][faction_id] += 1

	# Update trackers
	for district_id in district_counts:
		var tracker: CaptureProgressTracker = _trackers.get(district_id)
		if tracker != null:
			tracker.update_unit_counts(district_counts[district_id])


## Process all trackers.
func process(delta: float) -> void:
	var start_time := Time.get_ticks_usec()

	for tracker in _trackers.values():
		tracker.process(delta)

	_sync_accumulator += delta
	if _sync_accumulator >= SYNC_INTERVAL:
		_sync_accumulator -= SYNC_INTERVAL
		# Sync point - could emit sync data here for multiplayer

	_last_process_time_us = Time.get_ticks_usec() - start_time


## Get tracker for a district.
func get_tracker(district_id: int) -> CaptureProgressTracker:
	return _trackers.get(district_id)


## Get capture progress for a faction in a district.
func get_capture_progress(district_id: int, faction_id: String) -> float:
	var tracker: CaptureProgressTracker = _trackers.get(district_id)
	if tracker != null:
		return tracker.get_progress(faction_id)
	return 0.0


## Check if a district is contested.
func is_district_contested(district_id: int) -> bool:
	var tracker: CaptureProgressTracker = _trackers.get(district_id)
	if tracker != null:
		return tracker.is_contested
	return false


## Get all contested districts.
func get_contested_districts() -> Array[int]:
	var result: Array[int] = []
	for district_id in _trackers:
		var tracker: CaptureProgressTracker = _trackers[district_id]
		if tracker.is_contested:
			result.append(district_id)
	return result


## Get districts being captured by a faction.
func get_capturing_districts(faction_id: String) -> Array[int]:
	var result: Array[int] = []
	for district_id in _trackers:
		var tracker: CaptureProgressTracker = _trackers[district_id]
		if tracker.leading_faction == faction_id and tracker.get_progress(faction_id) > 0:
			result.append(district_id)
	return result


## Force capture (for testing).
func force_capture(district_id: int, faction_id: String) -> void:
	var tracker: CaptureProgressTracker = _trackers.get(district_id)
	if tracker != null:
		tracker._complete_capture(faction_id)


## Get performance stats.
func get_performance_stats() -> Dictionary:
	return {
		"last_process_us": _last_process_time_us,
		"tracker_count": _trackers.size(),
		"unit_associations": _unit_districts.size()
	}


## Serialize state.
func to_dict() -> Dictionary:
	var trackers_data := {}
	for district_id in _trackers:
		trackers_data[district_id] = _trackers[district_id].to_dict()

	return {
		"trackers": trackers_data,
		"unit_districts": _unit_districts.duplicate(),
		"sync_accumulator": _sync_accumulator
	}


## Deserialize state.
func from_dict(data: Dictionary) -> void:
	var trackers_data: Dictionary = data.get("trackers", {})
	for district_id_str in trackers_data:
		var district_id := int(district_id_str)
		if _trackers.has(district_id):
			var tracker := CaptureProgressTracker.from_dict(trackers_data[district_id_str])
			tracker.capture_complete.connect(_on_capture_complete.bind(district_id))
			tracker.contested_status_changed.connect(_on_contested_changed.bind(district_id))
			tracker.progress_changed.connect(_on_progress_changed.bind(district_id))
			_trackers[district_id] = tracker

	_unit_districts = data.get("unit_districts", {}).duplicate()
	_sync_accumulator = data.get("sync_accumulator", 0.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var contested_count := 0
	var capturing_factions := {}

	for tracker in _trackers.values():
		if tracker.is_contested:
			contested_count += 1
		if not tracker.leading_faction.is_empty() and tracker.get_progress(tracker.leading_faction) > 0:
			if not capturing_factions.has(tracker.leading_faction):
				capturing_factions[tracker.leading_faction] = 0
			capturing_factions[tracker.leading_faction] += 1

	return {
		"tracker_count": _trackers.size(),
		"contested_districts": contested_count,
		"unit_associations": _unit_districts.size(),
		"capturing_factions": capturing_factions
	}
