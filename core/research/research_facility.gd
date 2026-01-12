class_name ResearchFacility
extends RefCounted
## ResearchFacility represents a building that generates research points.

signal research_generated(amount: float)
signal facility_destroyed()
signal research_assigned(tech_id: String)
signal health_changed(current: float, max_health: float)

## Facility types
enum FacilityType {
	RESEARCH_LAB = 0,
	DATA_CENTER = 1,
	ADVANCED_LAB = 2
}

## Unique facility ID
var id: int = -1

## Faction ID this facility belongs to
var faction_id: int = 0

## Facility type
var facility_type: int = FacilityType.RESEARCH_LAB

## World position
var position: Vector3 = Vector3.ZERO

## Research rate (points per second)
var research_rate: float = 1.0

## Health management
var current_health: float = 100.0
var max_health: float = 100.0

## Currently assigned research (tech_id, empty if auto-contributing)
var assigned_research: String = ""

## Whether facility is active
var is_active: bool = true

## Total research points generated
var total_research_generated: float = 0.0

## Static ID counter
static var _next_id: int = 1


func _init() -> void:
	id = _next_id
	_next_id += 1


## Initialize facility with properties.
func initialize(p_faction_id: int, p_type: int, p_position: Vector3, p_research_rate: float = 1.0) -> void:
	faction_id = p_faction_id
	facility_type = p_type
	position = p_position
	research_rate = p_research_rate

	# Set health based on type
	match facility_type:
		FacilityType.RESEARCH_LAB:
			max_health = 100.0
		FacilityType.DATA_CENTER:
			max_health = 150.0
		FacilityType.ADVANCED_LAB:
			max_health = 200.0

	current_health = max_health


## Generate research points (called per tick).
func generate_research(delta: float) -> float:
	if not is_active or current_health <= 0:
		return 0.0

	var amount := research_rate * delta
	total_research_generated += amount
	research_generated.emit(amount)
	return amount


## Apply damage to facility.
func take_damage(amount: float) -> float:
	var actual_damage := minf(amount, current_health)
	current_health -= actual_damage
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		_destroy()

	return actual_damage


## Heal facility.
func heal(amount: float) -> float:
	var actual_heal := minf(amount, max_health - current_health)
	current_health += actual_heal
	health_changed.emit(current_health, max_health)
	return actual_heal


## Destroy facility.
func _destroy() -> void:
	is_active = false
	current_health = 0.0
	facility_destroyed.emit()


## Check if facility is destroyed.
func is_destroyed() -> bool:
	return current_health <= 0


## Get health percentage.
func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return current_health / max_health


## Assign to a specific research.
func assign_research(tech_id: String) -> void:
	assigned_research = tech_id
	research_assigned.emit(tech_id)


## Clear research assignment.
func clear_assignment() -> void:
	assigned_research = ""


## Get facility type name.
func get_type_name() -> String:
	match facility_type:
		FacilityType.RESEARCH_LAB:
			return "Research Lab"
		FacilityType.DATA_CENTER:
			return "Data Center"
		FacilityType.ADVANCED_LAB:
			return "Advanced Lab"
		_:
			return "Unknown"


## Serialize state.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"faction_id": faction_id,
		"facility_type": facility_type,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"research_rate": research_rate,
		"current_health": current_health,
		"max_health": max_health,
		"assigned_research": assigned_research,
		"is_active": is_active,
		"total_research_generated": total_research_generated
	}


## Deserialize state.
static func from_dict(data: Dictionary) -> ResearchFacility:
	var facility := ResearchFacility.new()
	facility.id = data.get("id", -1)
	facility.faction_id = data.get("faction_id", 0)
	facility.facility_type = data.get("facility_type", FacilityType.RESEARCH_LAB)

	var pos_data: Dictionary = data.get("position", {})
	facility.position = Vector3(
		pos_data.get("x", 0.0),
		pos_data.get("y", 0.0),
		pos_data.get("z", 0.0)
	)

	facility.research_rate = data.get("research_rate", 1.0)
	facility.current_health = data.get("current_health", 100.0)
	facility.max_health = data.get("max_health", 100.0)
	facility.assigned_research = data.get("assigned_research", "")
	facility.is_active = data.get("is_active", true)
	facility.total_research_generated = data.get("total_research_generated", 0.0)

	return facility


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"type": get_type_name(),
		"faction_id": faction_id,
		"research_rate": research_rate,
		"health": "%.0f/%.0f" % [current_health, max_health],
		"is_active": is_active,
		"assigned_research": assigned_research if not assigned_research.is_empty() else "none"
	}


## Create a research lab.
static func create_research_lab(faction_id: int, position: Vector3) -> ResearchFacility:
	var facility := ResearchFacility.new()
	facility.initialize(faction_id, FacilityType.RESEARCH_LAB, position, 1.0)
	return facility


## Create a data center.
static func create_data_center(faction_id: int, position: Vector3) -> ResearchFacility:
	var facility := ResearchFacility.new()
	facility.initialize(faction_id, FacilityType.DATA_CENTER, position, 2.0)
	return facility


## Create an advanced lab.
static func create_advanced_lab(faction_id: int, position: Vector3) -> ResearchFacility:
	var facility := ResearchFacility.new()
	facility.initialize(faction_id, FacilityType.ADVANCED_LAB, position, 3.0)
	return facility
