class_name ResearchProgress
extends RefCounted
## ResearchProgress tracks the progress of a single technology being researched.

signal progress_updated(tech_id: String, progress: float, total: float)
signal research_completed(tech_id: String)

## Technology being researched
var tech_id: String = ""

## Total research points needed
var total_research_needed: float = 0.0

## Current accumulated research points
var current_research: float = 0.0

## Facility IDs contributing to this research
var contributing_facilities: Array[int] = []

## Timestamp when research started
var start_time: int = 0


func _init(p_tech_id: String = "", p_total_needed: float = 0.0) -> void:
	tech_id = p_tech_id
	total_research_needed = p_total_needed
	start_time = Time.get_ticks_msec()


## Add research points from a facility.
## Returns true if research is now complete.
func add_research(amount: float, facility_id: int = -1) -> bool:
	if is_complete():
		return true

	current_research += amount

	# Track contributing facility
	if facility_id >= 0 and facility_id not in contributing_facilities:
		contributing_facilities.append(facility_id)

	progress_updated.emit(tech_id, current_research, total_research_needed)

	if current_research >= total_research_needed:
		current_research = total_research_needed
		research_completed.emit(tech_id)
		return true

	return false


## Get progress percentage (0.0 to 1.0).
func get_progress_percent() -> float:
	if total_research_needed <= 0:
		return 1.0
	return clampf(current_research / total_research_needed, 0.0, 1.0)


## Get remaining research points needed.
func get_remaining() -> float:
	return maxf(0.0, total_research_needed - current_research)


## Check if research is complete.
func is_complete() -> bool:
	return current_research >= total_research_needed


## Add a contributing facility.
func add_facility(facility_id: int) -> void:
	if facility_id not in contributing_facilities:
		contributing_facilities.append(facility_id)


## Remove a contributing facility.
func remove_facility(facility_id: int) -> void:
	var idx := contributing_facilities.find(facility_id)
	if idx >= 0:
		contributing_facilities.remove_at(idx)


## Get facility count.
func get_facility_count() -> int:
	return contributing_facilities.size()


## Estimate time remaining (seconds) based on current rate.
func estimate_time_remaining(research_rate_per_second: float) -> float:
	if research_rate_per_second <= 0:
		return INF
	return get_remaining() / research_rate_per_second


## Serialize state.
func to_dict() -> Dictionary:
	return {
		"tech_id": tech_id,
		"total_research_needed": total_research_needed,
		"current_research": current_research,
		"contributing_facilities": contributing_facilities.duplicate(),
		"start_time": start_time
	}


## Deserialize state.
static func from_dict(data: Dictionary) -> ResearchProgress:
	var progress := ResearchProgress.new()
	progress.tech_id = data.get("tech_id", "")
	progress.total_research_needed = data.get("total_research_needed", 0.0)
	progress.current_research = data.get("current_research", 0.0)
	progress.start_time = data.get("start_time", 0)

	progress.contributing_facilities.clear()
	for fid in data.get("contributing_facilities", []):
		progress.contributing_facilities.append(int(fid))

	return progress


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"tech_id": tech_id,
		"progress": "%.1f/%.1f (%.0f%%)" % [current_research, total_research_needed, get_progress_percent() * 100],
		"facilities": contributing_facilities.size(),
		"is_complete": is_complete()
	}
