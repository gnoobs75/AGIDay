class_name FactionStatus
extends RefCounted
## FactionStatus tracks a faction's state for victory/defeat detection.
## Uses efficient O(1) data structures for status queries.

signal elimination_detected(faction_id: String)
signal victory_achieved(faction_id: String, victory_type: int)
signal district_control_changed(faction_id: String, districts: int)
signal factory_destroyed(faction_id: String, remaining: int)

## Faction identifier
var faction_id: String = ""

## Whether faction is eliminated
var is_eliminated: bool = false

## Elimination timestamp
var elimination_time: int = 0

## Factory status
var factory_count: int = 0
var factories_destroyed: int = 0

## Unit counts
var total_units: int = 0
var units_killed: int = 0
var units_produced: int = 0

## District control
var districts_controlled: int = 0
var districts_captured: int = 0
var districts_lost: int = 0

## Victory status
var has_achieved_victory: bool = false
var victory_type: int = -1
var victory_time: int = 0
var victory_wave: int = 0

## Performance metrics
var resources_earned: float = 0.0
var research_completed: int = 0
var damage_dealt: float = 0.0
var damage_taken: float = 0.0


func _init(p_faction_id: String = "") -> void:
	faction_id = p_faction_id


## Update factory count (O(1)).
func set_factory_count(count: int) -> void:
	var delta := factory_count - count
	if delta > 0:
		factories_destroyed += delta
		factory_destroyed.emit(faction_id, count)

	factory_count = count
	_check_elimination()


## Update unit count (O(1)).
func set_unit_count(count: int) -> void:
	total_units = count
	_check_elimination()


## Register unit killed.
func unit_killed() -> void:
	units_killed += 1


## Register unit produced.
func unit_produced() -> void:
	units_produced += 1


## Update district control (O(1)).
func set_districts_controlled(count: int) -> void:
	var delta := count - districts_controlled

	if delta > 0:
		districts_captured += delta
	elif delta < 0:
		districts_lost += -delta

	districts_controlled = count
	district_control_changed.emit(faction_id, count)


## Check for elimination.
func _check_elimination() -> void:
	if is_eliminated:
		return

	# Eliminated if no factories AND no units
	if factory_count <= 0 and total_units <= 0:
		is_eliminated = true
		elimination_time = Time.get_ticks_msec()
		elimination_detected.emit(faction_id)


## Set victory achieved.
func set_victory(type: int, wave: int) -> void:
	if has_achieved_victory:
		return

	has_achieved_victory = true
	victory_type = type
	victory_time = Time.get_ticks_msec()
	victory_wave = wave
	victory_achieved.emit(faction_id, type)


## Get kill/death ratio.
func get_kd_ratio() -> float:
	if units_killed <= 0:
		return 0.0
	return float(units_produced) / float(units_killed) if units_killed > 0 else INF


## Get performance metrics.
func get_performance_metrics() -> Dictionary:
	return {
		"units_killed": units_killed,
		"units_produced": units_produced,
		"resources_earned": resources_earned,
		"districts_captured": districts_captured,
		"research_completed": research_completed,
		"kd_ratio": get_kd_ratio(),
		"damage_dealt": damage_dealt,
		"damage_taken": damage_taken
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"faction_id": faction_id,
		"is_eliminated": is_eliminated,
		"elimination_time": elimination_time,
		"factory_count": factory_count,
		"factories_destroyed": factories_destroyed,
		"total_units": total_units,
		"units_killed": units_killed,
		"units_produced": units_produced,
		"districts_controlled": districts_controlled,
		"districts_captured": districts_captured,
		"districts_lost": districts_lost,
		"has_achieved_victory": has_achieved_victory,
		"victory_type": victory_type,
		"victory_time": victory_time,
		"victory_wave": victory_wave,
		"resources_earned": resources_earned,
		"research_completed": research_completed,
		"damage_dealt": damage_dealt,
		"damage_taken": damage_taken
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> FactionStatus:
	var status := FactionStatus.new(data.get("faction_id", ""))
	status.is_eliminated = data.get("is_eliminated", false)
	status.elimination_time = data.get("elimination_time", 0)
	status.factory_count = data.get("factory_count", 0)
	status.factories_destroyed = data.get("factories_destroyed", 0)
	status.total_units = data.get("total_units", 0)
	status.units_killed = data.get("units_killed", 0)
	status.units_produced = data.get("units_produced", 0)
	status.districts_controlled = data.get("districts_controlled", 0)
	status.districts_captured = data.get("districts_captured", 0)
	status.districts_lost = data.get("districts_lost", 0)
	status.has_achieved_victory = data.get("has_achieved_victory", false)
	status.victory_type = data.get("victory_type", -1)
	status.victory_time = data.get("victory_time", 0)
	status.victory_wave = data.get("victory_wave", 0)
	status.resources_earned = data.get("resources_earned", 0.0)
	status.research_completed = data.get("research_completed", 0)
	status.damage_dealt = data.get("damage_dealt", 0.0)
	status.damage_taken = data.get("damage_taken", 0.0)
	return status


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"faction": faction_id,
		"eliminated": is_eliminated,
		"victory": has_achieved_victory,
		"factories": factory_count,
		"units": total_units,
		"districts": districts_controlled,
		"kd": "%.2f" % get_kd_ratio()
	}
