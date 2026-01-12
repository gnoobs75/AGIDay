class_name CaptureProgressTracker
extends RefCounted
## CaptureProgressTracker tracks capture progress for a single district.
## Uses point-based system: 100 points to capture, 1 point/sec/unit.

signal progress_changed(faction_id: String, progress: float)
signal capture_complete(new_owner: String, old_owner: String)
signal contested_status_changed(is_contested: bool)

## Points required to capture
const CAPTURE_POINTS_REQUIRED := 100.0

## Points per unit per second
const POINTS_PER_UNIT_PER_SEC := 1.0

## Points reduction rate for contested factions
const CONTESTED_REDUCTION_RATE := 0.5

## Clear control timer (seconds with no enemies)
const CLEAR_CONTROL_TIME := 5.0

## District ID this tracker is for
var district_id: int = -1

## Current owner faction
var owner_faction: String = ""

## Capture progress by faction (faction_id -> points 0-100)
var capture_progress: Dictionary = {}

## Units in district by faction
var unit_counts: Dictionary = {}

## Whether district is contested
var is_contested: bool = false

## Leading faction (most units)
var leading_faction: String = ""

## Time since district had no enemy units
var clear_control_timer: float = 0.0

## Whether progress is frozen (leading faction left)
var is_frozen: bool = false

## Last owner before capture started
var last_owner: String = ""


func _init(p_district_id: int = -1) -> void:
	district_id = p_district_id


## Update unit counts (called on unit enter/exit events).
func update_unit_counts(counts: Dictionary) -> void:
	unit_counts = counts.duplicate()
	_recalculate_state()


## Add unit to district.
func unit_entered(faction_id: String) -> void:
	if not unit_counts.has(faction_id):
		unit_counts[faction_id] = 0
	unit_counts[faction_id] += 1
	_recalculate_state()


## Remove unit from district.
func unit_exited(faction_id: String) -> void:
	if unit_counts.has(faction_id):
		unit_counts[faction_id] -= 1
		if unit_counts[faction_id] <= 0:
			unit_counts.erase(faction_id)
	_recalculate_state()


## Recalculate contested status and leading faction.
func _recalculate_state() -> void:
	var old_contested := is_contested

	# Determine contested status
	var faction_count := unit_counts.size()
	is_contested = faction_count > 1

	# Find leading faction
	var max_units := 0
	var new_leading := ""
	var tied := false

	for faction_id in unit_counts:
		var count: int = unit_counts[faction_id]
		if count > max_units:
			max_units = count
			new_leading = faction_id
			tied = false
		elif count == max_units and count > 0:
			tied = true

	# Handle tie case
	if tied:
		new_leading = ""  # No clear leader

	# Check if leading faction changed
	if new_leading != leading_faction:
		if leading_faction.is_empty() and not new_leading.is_empty():
			is_frozen = false  # New leader, unfreeze
		elif not leading_faction.is_empty() and new_leading.is_empty():
			is_frozen = true  # Leader left, freeze
		leading_faction = new_leading

	# Emit contested status change
	if is_contested != old_contested:
		contested_status_changed.emit(is_contested)


## Process capture progress for a time delta.
func process(delta: float) -> void:
	if is_frozen or unit_counts.is_empty():
		# Update clear control timer if owner has no enemies
		if not owner_faction.is_empty():
			var enemy_present := false
			for faction_id in unit_counts:
				if faction_id != owner_faction:
					enemy_present = true
					break

			if not enemy_present:
				clear_control_timer += delta
			else:
				clear_control_timer = 0.0
		return

	# Leading faction gains progress
	if not leading_faction.is_empty():
		var leader_units: int = unit_counts.get(leading_faction, 0)
		var progress_gain := POINTS_PER_UNIT_PER_SEC * leader_units * delta

		if not capture_progress.has(leading_faction):
			capture_progress[leading_faction] = 0.0

		capture_progress[leading_faction] = minf(
			capture_progress[leading_faction] + progress_gain,
			CAPTURE_POINTS_REQUIRED
		)

		progress_changed.emit(leading_faction, capture_progress[leading_faction])

		# Check for capture
		if capture_progress[leading_faction] >= CAPTURE_POINTS_REQUIRED:
			_complete_capture(leading_faction)
			return

	# Contested factions reduce other factions' progress
	if is_contested:
		for faction_id in unit_counts:
			if faction_id == leading_faction:
				continue

			var contesting_units: int = unit_counts[faction_id]
			var reduction := CONTESTED_REDUCTION_RATE * contesting_units * delta

			# Reduce leading faction's progress
			if capture_progress.has(leading_faction):
				capture_progress[leading_faction] = maxf(
					capture_progress[leading_faction] - reduction,
					0.0
				)

	# Update clear control timer
	if not owner_faction.is_empty():
		var enemy_present := false
		for faction_id in unit_counts:
			if faction_id != owner_faction:
				enemy_present = true
				break

		if not enemy_present:
			clear_control_timer += delta
		else:
			clear_control_timer = 0.0


## Complete a capture.
func _complete_capture(new_owner: String) -> void:
	var old_owner := owner_faction
	last_owner = old_owner
	owner_faction = new_owner

	# Reset all progress
	capture_progress.clear()
	is_frozen = false
	clear_control_timer = 0.0

	capture_complete.emit(new_owner, old_owner)


## Get capture progress for a faction (0-100).
func get_progress(faction_id: String) -> float:
	return capture_progress.get(faction_id, 0.0)


## Get capture progress percentage (0.0-1.0).
func get_progress_percentage(faction_id: String) -> float:
	return get_progress(faction_id) / CAPTURE_POINTS_REQUIRED


## Get total units in district.
func get_total_units() -> int:
	var total := 0
	for count in unit_counts.values():
		total += count
	return total


## Get estimated time to capture for a faction.
func get_estimated_capture_time(faction_id: String) -> float:
	var units: int = unit_counts.get(faction_id, 0)
	if units <= 0:
		return INF

	var remaining := CAPTURE_POINTS_REQUIRED - get_progress(faction_id)

	# Account for contested reduction
	var effective_rate := POINTS_PER_UNIT_PER_SEC * units
	if is_contested:
		var other_units := get_total_units() - units
		effective_rate -= CONTESTED_REDUCTION_RATE * other_units

	if effective_rate <= 0:
		return INF

	return remaining / effective_rate


## Check if district has clear control (no enemies for 5 seconds).
func has_clear_control() -> bool:
	return clear_control_timer >= CLEAR_CONTROL_TIME


## Reset tracker state.
func reset() -> void:
	capture_progress.clear()
	unit_counts.clear()
	is_contested = false
	leading_faction = ""
	is_frozen = false
	clear_control_timer = 0.0


## Serialize state.
func to_dict() -> Dictionary:
	return {
		"district_id": district_id,
		"owner_faction": owner_faction,
		"capture_progress": capture_progress.duplicate(),
		"unit_counts": unit_counts.duplicate(),
		"is_contested": is_contested,
		"leading_faction": leading_faction,
		"is_frozen": is_frozen,
		"clear_control_timer": clear_control_timer,
		"last_owner": last_owner
	}


## Deserialize state.
static func from_dict(data: Dictionary) -> CaptureProgressTracker:
	var tracker := CaptureProgressTracker.new()
	tracker.district_id = data.get("district_id", -1)
	tracker.owner_faction = data.get("owner_faction", "")
	tracker.capture_progress = data.get("capture_progress", {}).duplicate()
	tracker.unit_counts = data.get("unit_counts", {}).duplicate()
	tracker.is_contested = data.get("is_contested", false)
	tracker.leading_faction = data.get("leading_faction", "")
	tracker.is_frozen = data.get("is_frozen", false)
	tracker.clear_control_timer = data.get("clear_control_timer", 0.0)
	tracker.last_owner = data.get("last_owner", "")
	return tracker


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"district_id": district_id,
		"owner": owner_faction if not owner_faction.is_empty() else "neutral",
		"contested": is_contested,
		"leading": leading_faction,
		"frozen": is_frozen,
		"progress": capture_progress,
		"units": unit_counts,
		"clear_timer": "%.1fs" % clear_control_timer
	}
