class_name ResearchTechnology
extends RefCounted
## ResearchTechnology represents a technology that can be researched.

signal research_started(tech_id: String)
signal research_progress(tech_id: String, progress: float, total: float)
signal research_completed(tech_id: String)

## Technology identity
var tech_id: String = ""
var tech_name: String = ""
var tech_description: String = ""
var faction_id: String = ""

## Research requirements
var research_points_required: float = 100.0
var research_points_accumulated: float = 0.0
var prerequisites: Array[String] = []

## State
var is_unlocked: bool = false
var is_researching: bool = false
var is_completed: bool = false

## Rewards (applied on completion)
var buff_ids: Array[String] = []
var unlock_building_ids: Array[String] = []
var unlock_unit_ids: Array[String] = []
var unlock_ability_ids: Array[String] = []


func _init() -> void:
	pass


## Initialize technology.
func initialize(p_id: String, p_name: String, p_faction: String, points_required: float) -> void:
	tech_id = p_id
	tech_name = p_name
	faction_id = p_faction
	research_points_required = points_required


## Add prerequisite technology.
func add_prerequisite(prerequisite_id: String) -> void:
	if not prerequisites.has(prerequisite_id):
		prerequisites.append(prerequisite_id)


## Set rewards.
func set_rewards(buffs: Array[String] = [], buildings: Array[String] = [], units: Array[String] = [], abilities: Array[String] = []) -> void:
	buff_ids = buffs
	unlock_building_ids = buildings
	unlock_unit_ids = units
	unlock_ability_ids = abilities


## Start researching.
func start_research() -> bool:
	if is_completed or is_researching:
		return false

	if not is_unlocked:
		return false

	is_researching = true
	research_started.emit(tech_id)
	return true


## Add research points.
func add_research_points(points: float) -> bool:
	if not is_researching or is_completed:
		return false

	research_points_accumulated = minf(research_points_accumulated + points, research_points_required)

	research_progress.emit(tech_id, research_points_accumulated, research_points_required)

	if research_points_accumulated >= research_points_required:
		_complete()
		return true

	return false


## Complete research.
func _complete() -> void:
	is_completed = true
	is_researching = false
	research_points_accumulated = research_points_required
	research_completed.emit(tech_id)


## Cancel research.
func cancel_research() -> void:
	is_researching = false


## Get progress percentage.
func get_progress_percent() -> float:
	if research_points_required <= 0.0:
		return 100.0 if is_completed else 0.0
	return (research_points_accumulated / research_points_required) * 100.0


## Get remaining points.
func get_remaining_points() -> float:
	return maxf(0.0, research_points_required - research_points_accumulated)


## Check if all prerequisites are met.
func check_prerequisites(completed_techs: Array[String]) -> bool:
	for prereq in prerequisites:
		if not completed_techs.has(prereq):
			return false
	return true


## Unlock technology (after prerequisites met).
func unlock() -> void:
	if not is_unlocked:
		is_unlocked = true


## Serialization.
func to_dict() -> Dictionary:
	return {
		"tech_id": tech_id,
		"tech_name": tech_name,
		"tech_description": tech_description,
		"faction_id": faction_id,
		"research_points_required": research_points_required,
		"research_points_accumulated": research_points_accumulated,
		"prerequisites": prerequisites.duplicate(),
		"is_unlocked": is_unlocked,
		"is_researching": is_researching,
		"is_completed": is_completed,
		"buff_ids": buff_ids.duplicate(),
		"unlock_building_ids": unlock_building_ids.duplicate(),
		"unlock_unit_ids": unlock_unit_ids.duplicate(),
		"unlock_ability_ids": unlock_ability_ids.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	tech_id = data.get("tech_id", "")
	tech_name = data.get("tech_name", "")
	tech_description = data.get("tech_description", "")
	faction_id = data.get("faction_id", "")
	research_points_required = data.get("research_points_required", 100.0)
	research_points_accumulated = data.get("research_points_accumulated", 0.0)
	is_unlocked = data.get("is_unlocked", false)
	is_researching = data.get("is_researching", false)
	is_completed = data.get("is_completed", false)

	prerequisites.clear()
	for prereq in data.get("prerequisites", []):
		prerequisites.append(prereq)

	buff_ids.clear()
	for buff in data.get("buff_ids", []):
		buff_ids.append(buff)

	unlock_building_ids.clear()
	for building in data.get("unlock_building_ids", []):
		unlock_building_ids.append(building)

	unlock_unit_ids.clear()
	for unit in data.get("unlock_unit_ids", []):
		unlock_unit_ids.append(unit)

	unlock_ability_ids.clear()
	for ability in data.get("unlock_ability_ids", []):
		unlock_ability_ids.append(ability)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": tech_id,
		"name": tech_name,
		"faction": faction_id,
		"progress": get_progress_percent(),
		"is_unlocked": is_unlocked,
		"is_researching": is_researching,
		"is_completed": is_completed,
		"prerequisites": prerequisites.size(),
		"rewards": buff_ids.size() + unlock_building_ids.size() + unlock_unit_ids.size() + unlock_ability_ids.size()
	}
