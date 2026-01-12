class_name VictoryConditionChecker
extends RefCounted
## VictoryConditionChecker monitors district control for victory conditions.
## Victory is achieved when one faction controls all districts.

signal victory_achieved(faction_id: String, victory_type: String)
signal victory_progress_changed(faction_id: String, progress: float)
signal domination_warning(faction_id: String, districts_remaining: int)

## Victory types
enum VictoryType {
	TOTAL_DOMINATION = 0,  ## Control all districts
	MAJORITY_CONTROL = 1,   ## Control more than half
	ELIMINATION = 2         ## Eliminate all other factions
}

## Reference to district manager
var _district_manager: DistrictManager = null

## Current victory type mode
var victory_type: int = VictoryType.TOTAL_DOMINATION

## Domination warning threshold (districts remaining)
var domination_warning_threshold: int = 2

## Victory achieved flag
var victory_achieved: bool = false

## Winning faction
var winning_faction: String = ""

## Progress per faction (0.0 to 1.0)
var faction_progress: Dictionary = {}

## Districts controlled per faction
var faction_district_counts: Dictionary = {}


func _init(district_manager: DistrictManager = null) -> void:
	_district_manager = district_manager


## Set district manager.
func set_district_manager(manager: DistrictManager) -> void:
	_district_manager = manager


## Check victory conditions.
func check_victory() -> Dictionary:
	if _district_manager == null or victory_achieved:
		return {"victory": false}

	_update_faction_counts()

	match victory_type:
		VictoryType.TOTAL_DOMINATION:
			return _check_total_domination()
		VictoryType.MAJORITY_CONTROL:
			return _check_majority_control()
		VictoryType.ELIMINATION:
			return _check_elimination()

	return {"victory": false}


## Update faction district counts.
func _update_faction_counts() -> void:
	faction_district_counts.clear()
	faction_progress.clear()

	if _district_manager == null:
		return

	var total_districts := _district_manager.get_total_district_count()
	var neutral_count := _district_manager.get_district_count_by_owner("")

	# Count districts per faction
	for i in total_districts:
		var district := _district_manager.get_district(i)
		if district == null or district.is_neutral():
			continue

		var faction := district.owner_faction
		if not faction_district_counts.has(faction):
			faction_district_counts[faction] = 0
		faction_district_counts[faction] += 1

	# Calculate progress
	for faction in faction_district_counts:
		faction_progress[faction] = float(faction_district_counts[faction]) / float(total_districts)
		victory_progress_changed.emit(faction, faction_progress[faction])


## Check total domination victory.
func _check_total_domination() -> Dictionary:
	var total_districts := _district_manager.get_total_district_count()

	for faction in faction_district_counts:
		var count: int = faction_district_counts[faction]

		# Check domination warning
		var remaining := total_districts - count
		if remaining <= domination_warning_threshold and remaining > 0:
			domination_warning.emit(faction, remaining)

		# Check victory
		if count >= total_districts:
			_declare_victory(faction, "TOTAL_DOMINATION")
			return {
				"victory": true,
				"faction": faction,
				"type": "TOTAL_DOMINATION"
			}

	return {"victory": false}


## Check majority control victory.
func _check_majority_control() -> Dictionary:
	var total_districts := _district_manager.get_total_district_count()
	var majority := (total_districts / 2) + 1

	for faction in faction_district_counts:
		var count: int = faction_district_counts[faction]

		if count >= majority:
			_declare_victory(faction, "MAJORITY_CONTROL")
			return {
				"victory": true,
				"faction": faction,
				"type": "MAJORITY_CONTROL"
			}

	return {"victory": false}


## Check elimination victory (only one faction has units/districts).
func _check_elimination() -> Dictionary:
	# Only one faction has districts
	if faction_district_counts.size() == 1:
		var faction: String = faction_district_counts.keys()[0]
		_declare_victory(faction, "ELIMINATION")
		return {
			"victory": true,
			"faction": faction,
			"type": "ELIMINATION"
		}

	return {"victory": false}


## Declare victory.
func _declare_victory(faction_id: String, type: String) -> void:
	victory_achieved = true
	winning_faction = faction_id
	victory_achieved.emit(faction_id, type)


## Reset victory state.
func reset() -> void:
	victory_achieved = false
	winning_faction = ""
	faction_progress.clear()
	faction_district_counts.clear()


## Get faction with most districts.
func get_leading_faction() -> String:
	var max_count := 0
	var leader := ""

	for faction in faction_district_counts:
		if faction_district_counts[faction] > max_count:
			max_count = faction_district_counts[faction]
			leader = faction

	return leader


## Get victory progress for a faction.
func get_progress(faction_id: String) -> float:
	return faction_progress.get(faction_id, 0.0)


## Get districts needed for victory.
func get_districts_needed(faction_id: String) -> int:
	if _district_manager == null:
		return -1

	var total := _district_manager.get_total_district_count()
	var owned: int = faction_district_counts.get(faction_id, 0)

	match victory_type:
		VictoryType.TOTAL_DOMINATION:
			return total - owned
		VictoryType.MAJORITY_CONTROL:
			var majority := (total / 2) + 1
			return maxi(0, majority - owned)

	return -1


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"victory_type": victory_type,
		"victory_achieved": victory_achieved,
		"winning_faction": winning_faction,
		"faction_progress": faction_progress.duplicate(),
		"faction_district_counts": faction_district_counts.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	victory_type = data.get("victory_type", VictoryType.TOTAL_DOMINATION)
	victory_achieved = data.get("victory_achieved", false)
	winning_faction = data.get("winning_faction", "")
	faction_progress = data.get("faction_progress", {}).duplicate()
	faction_district_counts = data.get("faction_district_counts", {}).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"victory_type": ["TOTAL_DOMINATION", "MAJORITY_CONTROL", "ELIMINATION"][victory_type],
		"victory_achieved": victory_achieved,
		"winning_faction": winning_faction,
		"leading_faction": get_leading_faction(),
		"faction_counts": faction_district_counts.duplicate()
	}
