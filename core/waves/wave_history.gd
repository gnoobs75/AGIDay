class_name WaveHistory
extends RefCounted
## WaveHistory records completed wave data for analytics and replay.

## Wave number
var wave_number: int = 0

## Timestamp when wave started (msec)
var timestamp: int = 0

## Wave duration (seconds)
var duration: float = 0.0

## Total units spawned
var units_spawned: int = 0

## Total units killed
var units_killed: int = 0

## Units that survived (escaped or wave ended)
var units_survived: int = 0

## Faction performance snapshot
var faction_performance: Dictionary = {}

## Wave configuration used
var configuration_snapshot: Dictionary = {}

## Whether wave was completed successfully
var was_successful: bool = false

## Player damage taken during wave
var player_damage_taken: float = 0.0

## Resources earned from wave
var resources_earned: Dictionary = {}

## Seed used for wave
var seed: int = 0


func _init() -> void:
	pass


## Create from completed wave progress.
static func from_progress(progress: WaveProgress) -> WaveHistory:
	var history := WaveHistory.new()
	history.wave_number = progress.current_wave
	history.timestamp = progress.wave_start_time
	history.duration = progress.elapsed_time
	history.units_spawned = progress.units_spawned
	history.units_killed = progress.units_killed
	history.units_survived = progress.units_remaining
	history.faction_performance = progress.faction_performance.duplicate(true)
	history.was_successful = progress.wave_complete and progress.units_remaining == 0

	if progress.configuration != null:
		history.configuration_snapshot = progress.configuration.to_dict()
		history.seed = progress.configuration.seed

	return history


## Calculate kill rate.
func get_kill_rate() -> float:
	if units_spawned <= 0:
		return 0.0
	return float(units_killed) / float(units_spawned)


## Get best performing faction.
func get_best_faction() -> String:
	var best := ""
	var best_kills := 0

	for faction_id in faction_performance:
		var kills: int = faction_performance[faction_id].get("kills", 0)
		if kills > best_kills:
			best_kills = kills
			best = faction_id

	return best


## Get total damage dealt by all factions.
func get_total_damage_dealt() -> float:
	var total := 0.0
	for faction_id in faction_performance:
		total += faction_performance[faction_id].get("damage_dealt", 0.0)
	return total


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"wave_number": wave_number,
		"timestamp": timestamp,
		"duration": duration,
		"units_spawned": units_spawned,
		"units_killed": units_killed,
		"units_survived": units_survived,
		"faction_performance": faction_performance.duplicate(true),
		"configuration_snapshot": configuration_snapshot.duplicate(true),
		"was_successful": was_successful,
		"player_damage_taken": player_damage_taken,
		"resources_earned": resources_earned.duplicate(),
		"seed": seed
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> WaveHistory:
	var history := WaveHistory.new()
	history.wave_number = data.get("wave_number", 0)
	history.timestamp = data.get("timestamp", 0)
	history.duration = data.get("duration", 0.0)
	history.units_spawned = data.get("units_spawned", 0)
	history.units_killed = data.get("units_killed", 0)
	history.units_survived = data.get("units_survived", 0)
	history.faction_performance = data.get("faction_performance", {}).duplicate(true)
	history.configuration_snapshot = data.get("configuration_snapshot", {}).duplicate(true)
	history.was_successful = data.get("was_successful", false)
	history.player_damage_taken = data.get("player_damage_taken", 0.0)
	history.resources_earned = data.get("resources_earned", {}).duplicate()
	history.seed = data.get("seed", 0)
	return history


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"wave": wave_number,
		"duration": "%.1fs" % duration,
		"spawned": units_spawned,
		"killed": units_killed,
		"kill_rate": "%.0f%%" % (get_kill_rate() * 100),
		"successful": was_successful,
		"best_faction": get_best_faction()
	}
