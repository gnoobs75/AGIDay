class_name ResearchManager
extends RefCounted
## ResearchManager coordinates research progression across all factions.

signal research_started(faction_id: String, tech_id: String)
signal research_progress(faction_id: String, tech_id: String, progress: float, total: float)
signal research_completed(faction_id: String, tech_id: String)
signal technology_unlocked(faction_id: String, tech_id: String)
signal research_queue_updated(faction_id: String, queue: Array)
signal facility_assigned(faction_id: String, facility_id: int, tech_id: String)
signal research_interrupted(faction_id: String, tech_id: String, reason: String)

## Faction research states (faction_id -> FactionResearchState)
var _faction_states: Dictionary = {}

## All technologies (tech_id -> ResearchTechnology)
var _technologies: Dictionary = {}

## All facilities (facility_id -> ResearchFacility)
var _facilities: Dictionary = {}

## Facilities by faction (faction_id -> Array[int])
var _faction_facilities: Dictionary = {}

## Research queues (faction_id -> Array[String])
var _research_queues: Dictionary = {}

## Completed technologies per faction (faction_id -> Array[String])
var _completed_techs: Dictionary = {}

## Next IDs
var _next_facility_id: int = 1

## Analytics
var _research_analytics: Dictionary = {}


func _init() -> void:
	pass


# ============================================
# FACTION STATE MANAGEMENT
# ============================================

## Initialize faction research state.
func init_faction(faction_id: String) -> void:
	if not _faction_states.has(faction_id):
		_faction_states[faction_id] = {
			"current_tech": "",
			"total_points_accumulated": 0.0,
			"research_rate": 0.0
		}
		_faction_facilities[faction_id] = []
		_research_queues[faction_id] = []
		_completed_techs[faction_id] = []


## Get faction research state.
func get_faction_state(faction_id: String) -> Dictionary:
	return _faction_states.get(faction_id, {})


## Get current research for faction.
func get_current_research(faction_id: String) -> String:
	return _faction_states.get(faction_id, {}).get("current_tech", "")


# ============================================
# TECHNOLOGY MANAGEMENT
# ============================================

## Register a technology.
func register_technology(tech: ResearchTechnology) -> void:
	_technologies[tech.tech_id] = tech

	# Connect signals
	tech.research_completed.connect(_on_tech_completed)


## Get technology by ID.
func get_technology(tech_id: String) -> ResearchTechnology:
	return _technologies.get(tech_id)


## Get technologies for faction.
func get_faction_technologies(faction_id: String) -> Array[ResearchTechnology]:
	var techs: Array[ResearchTechnology] = []
	for tech_id in _technologies:
		var tech: ResearchTechnology = _technologies[tech_id]
		if tech.faction_id == faction_id:
			techs.append(tech)
	return techs


## Get available technologies for faction.
func get_available_technologies(faction_id: String) -> Array[ResearchTechnology]:
	var techs: Array[ResearchTechnology] = []
	var completed := get_completed_technologies(faction_id)

	for tech in get_faction_technologies(faction_id):
		if not tech.is_completed and tech.check_prerequisites(completed):
			tech.unlock()
			techs.append(tech)

	return techs


## Get completed technologies for faction.
func get_completed_technologies(faction_id: String) -> Array[String]:
	var result: Array[String] = []
	for tech_id in _completed_techs.get(faction_id, []):
		result.append(tech_id)
	return result


# ============================================
# FACILITY MANAGEMENT
# ============================================

## Register a research facility.
func register_facility(faction_id: String, facility_type: int, position: Vector3, research_rate: float = 1.0) -> ResearchFacility:
	init_faction(faction_id)

	var facility := ResearchFacility.new()
	facility.initialize(faction_id as int, facility_type, position, research_rate)

	_facilities[facility.id] = facility

	_faction_facilities[faction_id].append(facility.id)

	# Connect signals
	facility.facility_destroyed.connect(_on_facility_destroyed.bind(facility.id))

	_update_research_rate(faction_id)

	return facility


## Unregister facility.
func unregister_facility(facility_id: int) -> void:
	if not _facilities.has(facility_id):
		return

	var facility: ResearchFacility = _facilities[facility_id]
	var faction_id := str(facility.faction_id)

	if _faction_facilities.has(faction_id):
		var idx := _faction_facilities[faction_id].find(facility_id)
		if idx != -1:
			_faction_facilities[faction_id].remove_at(idx)

	_facilities.erase(facility_id)

	_update_research_rate(faction_id)


## Get facility by ID.
func get_facility(facility_id: int) -> ResearchFacility:
	return _facilities.get(facility_id)


## Get facilities for faction.
func get_faction_facilities(faction_id: String) -> Array[ResearchFacility]:
	var facilities: Array[ResearchFacility] = []
	if not _faction_facilities.has(faction_id):
		return facilities

	for facility_id in _faction_facilities[faction_id]:
		var facility: ResearchFacility = _facilities.get(facility_id)
		if facility != null:
			facilities.append(facility)

	return facilities


## Get active facilities for faction.
func get_active_facilities(faction_id: String) -> Array[ResearchFacility]:
	var result: Array[ResearchFacility] = []
	for facility in get_faction_facilities(faction_id):
		if facility.is_active and not facility.is_destroyed():
			result.append(facility)
	return result


## Update faction research rate.
func _update_research_rate(faction_id: String) -> void:
	var total_rate := 0.0

	for facility in get_active_facilities(faction_id):
		total_rate += facility.research_rate

	if _faction_states.has(faction_id):
		_faction_states[faction_id]["research_rate"] = total_rate


# ============================================
# RESEARCH ASSIGNMENT & QUEUE
# ============================================

## Start researching a technology.
func start_research(faction_id: String, tech_id: String) -> bool:
	init_faction(faction_id)

	var tech := get_technology(tech_id)
	if tech == null:
		return false

	if tech.is_completed:
		return false

	# Check prerequisites
	var completed := get_completed_technologies(faction_id)
	if not tech.check_prerequisites(completed):
		return false

	tech.unlock()
	if not tech.start_research():
		return false

	_faction_states[faction_id]["current_tech"] = tech_id

	# Assign all unassigned facilities to this research
	for facility in get_active_facilities(faction_id):
		if facility.assigned_research.is_empty():
			facility.assign_research(tech_id)
			facility_assigned.emit(faction_id, facility.id, tech_id)

	research_started.emit(faction_id, tech_id)
	return true


## Cancel current research.
func cancel_research(faction_id: String) -> void:
	var state: Dictionary = _faction_states.get(faction_id, {})
	var current_tech: String = state.get("current_tech", "")

	if current_tech.is_empty():
		return

	var tech := get_technology(current_tech)
	if tech != null:
		tech.cancel_research()

	# Unassign facilities
	for facility in get_faction_facilities(faction_id):
		if facility.assigned_research == current_tech:
			facility.clear_assignment()

	state["current_tech"] = ""
	research_interrupted.emit(faction_id, current_tech, "cancelled")


## Add technology to research queue.
func add_to_queue(faction_id: String, tech_id: String) -> bool:
	init_faction(faction_id)

	var tech := get_technology(tech_id)
	if tech == null or tech.is_completed:
		return false

	var queue: Array = _research_queues[faction_id]
	if queue.has(tech_id):
		return false

	queue.append(tech_id)
	research_queue_updated.emit(faction_id, queue)
	return true


## Remove technology from queue.
func remove_from_queue(faction_id: String, tech_id: String) -> void:
	if not _research_queues.has(faction_id):
		return

	var queue: Array = _research_queues[faction_id]
	var idx := queue.find(tech_id)
	if idx != -1:
		queue.remove_at(idx)
		research_queue_updated.emit(faction_id, queue)


## Get research queue for faction.
func get_research_queue(faction_id: String) -> Array:
	return _research_queues.get(faction_id, [])


## Process next in queue.
func _process_queue(faction_id: String) -> void:
	var queue: Array = _research_queues.get(faction_id, [])
	if queue.is_empty():
		return

	var next_tech: String = queue.pop_front()
	research_queue_updated.emit(faction_id, queue)

	start_research(faction_id, next_tech)


# ============================================
# RESEARCH UPDATE LOOP
# ============================================

## Update all faction research (call each frame).
func update(delta: float) -> void:
	for faction_id in _faction_states:
		_update_faction_research(faction_id, delta)

	_update_analytics()


## Update research for a single faction.
func _update_faction_research(faction_id: String, delta: float) -> void:
	var state: Dictionary = _faction_states.get(faction_id, {})
	var current_tech: String = state.get("current_tech", "")

	if current_tech.is_empty():
		return

	var tech := get_technology(current_tech)
	if tech == null:
		return

	# Accumulate research from all active facilities
	var total_points := 0.0

	for facility in get_active_facilities(faction_id):
		if facility.assigned_research == current_tech or facility.assigned_research.is_empty():
			total_points += facility.generate_research(delta)

	if total_points > 0:
		state["total_points_accumulated"] = state.get("total_points_accumulated", 0.0) + total_points

		var completed := tech.add_research_points(total_points)

		research_progress.emit(faction_id, current_tech, tech.research_points_accumulated, tech.research_points_required)

		if completed:
			_on_research_completed(faction_id, tech)


## Handle research completion.
func _on_research_completed(faction_id: String, tech: ResearchTechnology) -> void:
	# Add to completed list
	if not _completed_techs.has(faction_id):
		_completed_techs[faction_id] = []
	_completed_techs[faction_id].append(tech.tech_id)

	# Clear current research
	_faction_states[faction_id]["current_tech"] = ""

	# Unassign facilities
	for facility in get_faction_facilities(faction_id):
		if facility.assigned_research == tech.tech_id:
			facility.clear_assignment()

	research_completed.emit(faction_id, tech.tech_id)

	# Unlock dependent technologies
	_check_technology_unlocks(faction_id)

	# Start next in queue
	_process_queue(faction_id)


func _on_tech_completed(tech_id: String) -> void:
	var tech := get_technology(tech_id)
	if tech != null:
		technology_unlocked.emit(tech.faction_id, tech_id)


## Check and unlock technologies whose prerequisites are now met.
func _check_technology_unlocks(faction_id: String) -> void:
	var completed := get_completed_technologies(faction_id)

	for tech in get_faction_technologies(faction_id):
		if not tech.is_unlocked and not tech.is_completed:
			if tech.check_prerequisites(completed):
				tech.unlock()
				technology_unlocked.emit(faction_id, tech.tech_id)


## Handle facility destroyed.
func _on_facility_destroyed(facility_id: int) -> void:
	var facility := get_facility(facility_id)
	if facility == null:
		return

	var faction_id := str(facility.faction_id)
	var assigned := facility.assigned_research

	# Check if this interrupts research
	var remaining := get_active_facilities(faction_id).size() - 1
	if remaining == 0 and not assigned.is_empty():
		research_interrupted.emit(faction_id, assigned, "no_facilities")

	_update_research_rate(faction_id)


# ============================================
# ANALYTICS
# ============================================

## Get research analytics for faction.
func get_research_analytics(faction_id: String) -> Dictionary:
	init_faction(faction_id)

	var state: Dictionary = _faction_states.get(faction_id, {})
	var current_tech: String = state.get("current_tech", "")
	var tech := get_technology(current_tech) if not current_tech.is_empty() else null

	var facilities := get_faction_facilities(faction_id)
	var active_facilities := get_active_facilities(faction_id)

	return {
		"faction_id": faction_id,
		"current_research": current_tech,
		"progress_percent": tech.get_progress_percent() if tech != null else 0.0,
		"points_accumulated": tech.research_points_accumulated if tech != null else 0.0,
		"points_required": tech.research_points_required if tech != null else 0.0,
		"research_rate": state.get("research_rate", 0.0),
		"total_facilities": facilities.size(),
		"active_facilities": active_facilities.size(),
		"queue_size": _research_queues.get(faction_id, []).size(),
		"completed_count": _completed_techs.get(faction_id, []).size(),
		"eta_seconds": _calculate_eta(tech, state.get("research_rate", 0.0))
	}


## Calculate estimated time to completion.
func _calculate_eta(tech: ResearchTechnology, rate: float) -> float:
	if tech == null or rate <= 0.0:
		return -1.0

	var remaining := tech.get_remaining_points()
	return remaining / rate


## Update analytics cache.
func _update_analytics() -> void:
	for faction_id in _faction_states:
		_research_analytics[faction_id] = get_research_analytics(faction_id)


# ============================================
# VALIDATION
# ============================================

## Validate research assignment.
func validate_research_assignment(faction_id: String, tech_id: String) -> Dictionary:
	var result := {
		"valid": false,
		"errors": []
	}

	var tech := get_technology(tech_id)
	if tech == null:
		result["errors"].append("Technology not found")
		return result

	if tech.is_completed:
		result["errors"].append("Technology already completed")
		return result

	if tech.faction_id != faction_id:
		result["errors"].append("Technology belongs to different faction")
		return result

	var completed := get_completed_technologies(faction_id)
	if not tech.check_prerequisites(completed):
		result["errors"].append("Prerequisites not met")
		return result

	var facilities := get_active_facilities(faction_id)
	if facilities.is_empty():
		result["errors"].append("No active research facilities")
		return result

	result["valid"] = true
	return result


## Validate queue configuration.
func validate_queue(faction_id: String, queue: Array) -> Dictionary:
	var result := {
		"valid": true,
		"errors": []
	}

	var will_complete: Array[String] = get_completed_technologies(faction_id).duplicate()

	for tech_id in queue:
		var tech := get_technology(tech_id)
		if tech == null:
			result["errors"].append("Unknown technology: %s" % tech_id)
			result["valid"] = false
			continue

		if not tech.check_prerequisites(will_complete):
			result["errors"].append("Prerequisites not met for: %s" % tech_id)
			result["valid"] = false

		will_complete.append(tech_id)

	return result


# ============================================
# SERIALIZATION
# ============================================

func to_dict() -> Dictionary:
	var techs_data: Dictionary = {}
	for tech_id in _technologies:
		techs_data[tech_id] = _technologies[tech_id].to_dict()

	var facilities_data: Dictionary = {}
	for facility_id in _facilities:
		facilities_data[str(facility_id)] = _facilities[facility_id].to_dict()

	return {
		"faction_states": _faction_states.duplicate(true),
		"technologies": techs_data,
		"facilities": facilities_data,
		"research_queues": _research_queues.duplicate(true),
		"completed_techs": _completed_techs.duplicate(true),
		"next_facility_id": _next_facility_id
	}


func from_dict(data: Dictionary) -> void:
	_faction_states = data.get("faction_states", {}).duplicate(true)
	_research_queues = data.get("research_queues", {}).duplicate(true)
	_completed_techs = data.get("completed_techs", {}).duplicate(true)
	_next_facility_id = data.get("next_facility_id", 1)

	# Load technologies
	_technologies.clear()
	var techs_data: Dictionary = data.get("technologies", {})
	for tech_id in techs_data:
		var tech := ResearchTechnology.new()
		tech.from_dict(techs_data[tech_id])
		_technologies[tech_id] = tech
		tech.research_completed.connect(_on_tech_completed)

	# Load facilities
	_facilities.clear()
	_faction_facilities.clear()
	var facilities_data: Dictionary = data.get("facilities", {})
	for facility_id_str in facilities_data:
		var facility := ResearchFacility.from_dict(facilities_data[facility_id_str])
		_facilities[int(facility_id_str)] = facility
		facility.facility_destroyed.connect(_on_facility_destroyed.bind(facility.id))

		var faction_id := str(facility.faction_id)
		if not _faction_facilities.has(faction_id):
			_faction_facilities[faction_id] = []
		_faction_facilities[faction_id].append(facility.id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"factions": _faction_states.size(),
		"technologies": _technologies.size(),
		"facilities": _facilities.size(),
		"total_completed": _count_total_completed(),
		"analytics": _research_analytics.size()
	}


func _count_total_completed() -> int:
	var total := 0
	for faction_id in _completed_techs:
		total += _completed_techs[faction_id].size()
	return total
