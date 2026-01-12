class_name VictoryEvent
extends RefCounted
## VictoryEvent captures victory achievement data for persistence and analytics.

## Timestamp when victory occurred
var timestamp: int = 0

## Winning faction
var faction_id: String = ""

## Victory type achieved
var victory_type: int = VictoryCondition.VictoryType.DUAL_CONDITION

## Game duration in seconds
var duration: float = 0.0

## Wave number at victory
var wave_number: int = 0

## Performance metrics at victory
var performance_metrics: Dictionary = {}

## Opponents defeated
var opponents_defeated: Array[String] = []


func _init() -> void:
	timestamp = Time.get_ticks_msec()


## Create from faction status.
static func create(
	faction_status: FactionStatus,
	victory_type: int,
	duration: float,
	wave: int
) -> VictoryEvent:
	var event := VictoryEvent.new()
	event.faction_id = faction_status.faction_id
	event.victory_type = victory_type
	event.duration = duration
	event.wave_number = wave
	event.performance_metrics = faction_status.get_performance_metrics()
	return event


## Get victory type name.
func get_victory_type_name() -> String:
	match victory_type:
		VictoryCondition.VictoryType.DISTRICT_DOMINATION: return "District Domination"
		VictoryCondition.VictoryType.FACTORY_DESTRUCTION: return "Factory Destruction"
		VictoryCondition.VictoryType.DUAL_CONDITION: return "Total Victory"
		VictoryCondition.VictoryType.TIME_LIMIT: return "Time Victory"
		VictoryCondition.VictoryType.WAVE_LIMIT: return "Survival Victory"
		VictoryCondition.VictoryType.ELIMINATION: return "Elimination"
	return "Unknown"


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"timestamp": timestamp,
		"faction_id": faction_id,
		"victory_type": victory_type,
		"duration": duration,
		"wave_number": wave_number,
		"performance_metrics": performance_metrics.duplicate(),
		"opponents_defeated": opponents_defeated.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> VictoryEvent:
	var event := VictoryEvent.new()
	event.timestamp = data.get("timestamp", 0)
	event.faction_id = data.get("faction_id", "")
	event.victory_type = data.get("victory_type", 0)
	event.duration = data.get("duration", 0.0)
	event.wave_number = data.get("wave_number", 0)
	event.performance_metrics = data.get("performance_metrics", {}).duplicate()

	event.opponents_defeated.clear()
	for opponent in data.get("opponents_defeated", []):
		event.opponents_defeated.append(opponent)

	return event
