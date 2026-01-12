class_name FactionResearchState
extends RefCounted
## FactionResearchState tracks all research progress for a single faction.

signal tech_completed(tech_id: String, technology: Technology)
signal tech_started(tech_id: String)
signal research_queued(tech_id: String)
signal facility_added(facility_id: int)
signal facility_destroyed(facility_id: int)

## Faction ID
var faction_id: int = 0

## Technology tree (tech_id -> Technology)
var tech_tree: Dictionary = {}

## Completed technologies (tech_ids)
var completed_techs: Array[String] = []

## Research facilities (facility_id -> research_rate)
var research_facilities: Dictionary = {}

## Current research queue (tech_ids in order)
var current_research_queue: Array[String] = []

## Active research progress (tech_id -> ResearchProgress)
var active_research: Dictionary = {}

## Total research points generated
var total_research_generated: float = 0.0


func _init(p_faction_id: int = 0) -> void:
	faction_id = p_faction_id


## Register a technology in the tech tree.
func register_technology(tech: Technology) -> void:
	tech_tree[tech.tech_id] = tech


## Register multiple technologies.
func register_technologies(techs: Array[Technology]) -> void:
	for tech in techs:
		register_technology(tech)


## Get a technology by ID.
func get_technology(tech_id: String) -> Technology:
	return tech_tree.get(tech_id)


## Check if a technology can be researched.
func can_research(tech_id: String) -> bool:
	if tech_id in completed_techs:
		return false  # Already completed

	if tech_id in current_research_queue:
		return false  # Already queued

	var tech := get_technology(tech_id)
	if tech == null:
		return false

	return tech.can_research(completed_techs)


## Queue a technology for research.
func queue_research(tech_id: String) -> bool:
	if not can_research(tech_id):
		return false

	current_research_queue.append(tech_id)
	research_queued.emit(tech_id)

	# Start research if this is the first in queue
	if current_research_queue.size() == 1:
		_start_research(tech_id)

	return true


## Start researching a technology.
func _start_research(tech_id: String) -> void:
	var tech := get_technology(tech_id)
	if tech == null:
		return

	var progress := ResearchProgress.new(tech_id, tech.research_points_cost)
	active_research[tech_id] = progress
	tech_started.emit(tech_id)


## Add research points from a facility.
func add_research_points(facility_id: int, amount: float) -> void:
	if current_research_queue.is_empty():
		return

	var current_tech_id: String = current_research_queue[0]
	if not active_research.has(current_tech_id):
		_start_research(current_tech_id)

	var progress: ResearchProgress = active_research.get(current_tech_id)
	if progress == null:
		return

	total_research_generated += amount
	var completed := progress.add_research(amount, facility_id)

	if completed:
		_complete_research(current_tech_id)


## Complete a technology research.
func _complete_research(tech_id: String) -> void:
	var tech := get_technology(tech_id)
	if tech == null:
		return

	# Add to completed
	if tech_id not in completed_techs:
		completed_techs.append(tech_id)

	# Remove from queue and active
	var idx := current_research_queue.find(tech_id)
	if idx >= 0:
		current_research_queue.remove_at(idx)
	active_research.erase(tech_id)

	tech_completed.emit(tech_id, tech)

	# Start next research if queue not empty
	if not current_research_queue.is_empty():
		_start_research(current_research_queue[0])


## Cancel a queued research.
func cancel_research(tech_id: String) -> bool:
	var idx := current_research_queue.find(tech_id)
	if idx < 0:
		return false

	current_research_queue.remove_at(idx)
	active_research.erase(tech_id)

	# If we cancelled the first item, start the next
	if idx == 0 and not current_research_queue.is_empty():
		_start_research(current_research_queue[0])

	return true


## Add a research facility.
func add_research_facility(facility_id: int, research_rate: float) -> void:
	research_facilities[facility_id] = research_rate
	facility_added.emit(facility_id)


## Remove a research facility (destroyed).
func remove_research_facility(facility_id: int) -> void:
	research_facilities.erase(facility_id)

	# Remove from any active research
	for tech_id in active_research:
		var progress: ResearchProgress = active_research[tech_id]
		progress.remove_facility(facility_id)

	facility_destroyed.emit(facility_id)


## Get total research rate from all facilities.
func get_total_research_rate() -> float:
	var total := 0.0
	for rate in research_facilities.values():
		total += rate
	return total


## Get current research progress.
func get_current_research_progress() -> ResearchProgress:
	if current_research_queue.is_empty():
		return null
	return active_research.get(current_research_queue[0])


## Check if a technology is completed.
func is_tech_completed(tech_id: String) -> bool:
	return tech_id in completed_techs


## Check if a technology is in queue.
func is_tech_queued(tech_id: String) -> bool:
	return tech_id in current_research_queue


## Get available technologies (can be researched now).
func get_available_technologies() -> Array[String]:
	var available: Array[String] = []
	for tech_id in tech_tree:
		if can_research(tech_id):
			available.append(tech_id)
	return available


## Get technologies by tier.
func get_technologies_by_tier(tier: int) -> Array[Technology]:
	var result: Array[Technology] = []
	for tech_id in tech_tree:
		var tech: Technology = tech_tree[tech_id]
		if tech.tier == tier:
			result.append(tech)
	return result


## Process a frame (apply research from facilities).
func process(delta: float) -> void:
	if current_research_queue.is_empty():
		return

	# Apply research from all facilities
	for facility_id in research_facilities:
		var rate: float = research_facilities[facility_id]
		add_research_points(facility_id, rate * delta)


## Serialize state.
func to_dict() -> Dictionary:
	var active_data := {}
	for tech_id in active_research:
		active_data[tech_id] = active_research[tech_id].to_dict()

	return {
		"faction_id": faction_id,
		"completed_techs": completed_techs.duplicate(),
		"research_facilities": research_facilities.duplicate(),
		"current_research_queue": current_research_queue.duplicate(),
		"active_research": active_data,
		"total_research_generated": total_research_generated
	}


## Deserialize state.
func from_dict(data: Dictionary) -> void:
	faction_id = data.get("faction_id", 0)

	completed_techs.clear()
	for tech_id in data.get("completed_techs", []):
		completed_techs.append(str(tech_id))

	research_facilities = data.get("research_facilities", {}).duplicate()

	current_research_queue.clear()
	for tech_id in data.get("current_research_queue", []):
		current_research_queue.append(str(tech_id))

	active_research.clear()
	var active_data: Dictionary = data.get("active_research", {})
	for tech_id in active_data:
		active_research[tech_id] = ResearchProgress.from_dict(active_data[tech_id])

	total_research_generated = data.get("total_research_generated", 0.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var current_progress: ResearchProgress = get_current_research_progress()
	var current_info: Dictionary = {}
	if current_progress != null:
		current_info = current_progress.get_summary()

	return {
		"faction_id": faction_id,
		"tech_tree_size": tech_tree.size(),
		"completed_count": completed_techs.size(),
		"facility_count": research_facilities.size(),
		"queue_size": current_research_queue.size(),
		"total_research_rate": get_total_research_rate(),
		"current_research": current_info
	}
