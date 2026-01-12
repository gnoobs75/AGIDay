class_name DefeatEvent
extends RefCounted
## DefeatEvent captures defeat/elimination data for persistence and analytics.

## Defeat reasons
enum Reason {
	FACTORY_DESTROYED = 0,
	UNITS_ELIMINATED = 1,
	TIME_EXPIRED = 2,
	SURRENDER = 3,
	DISCONNECTED = 4
}

## Timestamp when defeat occurred
var timestamp: int = 0

## Defeated faction
var faction_id: String = ""

## Defeat reason
var defeat_reason: int = Reason.FACTORY_DESTROYED

## Game duration in seconds
var duration: float = 0.0

## Wave number at defeat
var wave_number: int = 0

## Performance metrics at defeat
var performance_metrics: Dictionary = {}

## Faction that caused defeat (if applicable)
var defeated_by: String = ""


func _init() -> void:
	timestamp = Time.get_ticks_msec()


## Create from faction status.
static func create(
	faction_status: FactionStatus,
	reason: int,
	duration: float,
	wave: int,
	victor: String = ""
) -> DefeatEvent:
	var event := DefeatEvent.new()
	event.faction_id = faction_status.faction_id
	event.defeat_reason = reason
	event.duration = duration
	event.wave_number = wave
	event.performance_metrics = faction_status.get_performance_metrics()
	event.defeated_by = victor
	return event


## Get defeat reason name.
func get_reason_name() -> String:
	match defeat_reason:
		Reason.FACTORY_DESTROYED: return "Factory Destroyed"
		Reason.UNITS_ELIMINATED: return "Units Eliminated"
		Reason.TIME_EXPIRED: return "Time Expired"
		Reason.SURRENDER: return "Surrendered"
		Reason.DISCONNECTED: return "Disconnected"
	return "Unknown"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"timestamp": timestamp,
		"faction_id": faction_id,
		"defeat_reason": defeat_reason,
		"duration": duration,
		"wave_number": wave_number,
		"performance_metrics": performance_metrics.duplicate(),
		"defeated_by": defeated_by
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> DefeatEvent:
	var event := DefeatEvent.new()
	event.timestamp = data.get("timestamp", 0)
	event.faction_id = data.get("faction_id", "")
	event.defeat_reason = data.get("defeat_reason", 0)
	event.duration = data.get("duration", 0.0)
	event.wave_number = data.get("wave_number", 0)
	event.performance_metrics = data.get("performance_metrics", {}).duplicate()
	event.defeated_by = data.get("defeated_by", "")
	return event
