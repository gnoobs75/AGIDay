class_name GameStateManagerClass
extends Node
## GameStateManager tracks match duration, game status, and faction states.
## Provides the backbone for difficulty scaling, victory conditions, and game flow.

signal game_started()
signal game_paused()
signal game_resumed()
signal game_ended(result: GameResult)
signal faction_eliminated(faction_id: int)
signal faction_status_changed(faction_id: int)
signal match_duration_milestone(minutes: int)

## Game result states
enum GameResult {
	NONE = 0,
	VICTORY = 1,
	DEFEAT = 2,
	DRAW = 3,
	ABANDONED = 4
}

## Match status states
enum MatchStatus {
	NOT_STARTED = 0,
	ACTIVE = 1,
	PAUSED = 2,
	ENDED = 3
}

## Faction status data structure
class FactionStatus:
	var faction_id: int = 0
	var faction_name: String = ""
	var is_player: bool = false
	var is_eliminated: bool = false
	var elimination_time: float = 0.0

	## Unit tracking
	var unit_count: int = 0
	var max_unit_count: int = 0

	## Resource tracking
	var resources: Dictionary = {}  # resource_type -> amount

	## Structure tracking
	var factory_count: int = 0
	var building_count: int = 0
	var district_count: int = 0

	## Combat stats
	var units_created: int = 0
	var units_lost: int = 0
	var units_killed: int = 0
	var damage_dealt: float = 0.0
	var damage_taken: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"faction_id": faction_id,
			"faction_name": faction_name,
			"is_player": is_player,
			"is_eliminated": is_eliminated,
			"elimination_time": elimination_time,
			"unit_count": unit_count,
			"max_unit_count": max_unit_count,
			"resources": resources.duplicate(),
			"factory_count": factory_count,
			"building_count": building_count,
			"district_count": district_count,
			"units_created": units_created,
			"units_lost": units_lost,
			"units_killed": units_killed,
			"damage_dealt": damage_dealt,
			"damage_taken": damage_taken
		}

	static func from_dict(data: Dictionary) -> FactionStatus:
		var status := FactionStatus.new()
		status.faction_id = data.get("faction_id", 0)
		status.faction_name = data.get("faction_name", "")
		status.is_player = data.get("is_player", false)
		status.is_eliminated = data.get("is_eliminated", false)
		status.elimination_time = data.get("elimination_time", 0.0)
		status.unit_count = data.get("unit_count", 0)
		status.max_unit_count = data.get("max_unit_count", 0)
		status.resources = data.get("resources", {}).duplicate()
		status.factory_count = data.get("factory_count", 0)
		status.building_count = data.get("building_count", 0)
		status.district_count = data.get("district_count", 0)
		status.units_created = data.get("units_created", 0)
		status.units_lost = data.get("units_lost", 0)
		status.units_killed = data.get("units_killed", 0)
		status.damage_dealt = data.get("damage_dealt", 0.0)
		status.damage_taken = data.get("damage_taken", 0.0)
		return status


## Current match status
var _match_status: MatchStatus = MatchStatus.NOT_STARTED

## Match timing
var _match_start_time: int = 0  # Unix timestamp when match started
var _match_duration: float = 0.0  # Total duration in seconds
var _pause_start_time: float = 0.0  # When pause started
var _total_pause_time: float = 0.0  # Total time spent paused

## Game result
var _game_result: GameResult = GameResult.NONE

## Player faction ID
var _player_faction_id: int = 0

## Faction statuses (faction_id -> FactionStatus)
var _faction_statuses: Dictionary = {}

## Duration milestone tracking (in minutes)
var _last_duration_milestone: int = 0

## Current wave number
var _current_wave: int = 0

## Difficulty level
var _difficulty: int = 0


func _ready() -> void:
	print("GameStateManager: Initialized")


func _process(delta: float) -> void:
	if _match_status == MatchStatus.ACTIVE:
		_match_duration += delta
		_check_duration_milestones()


## Start a new match
func start_match(player_faction: int, difficulty: int = 1) -> void:
	_match_status = MatchStatus.ACTIVE
	_match_start_time = int(Time.get_unix_time_from_system())
	_match_duration = 0.0
	_total_pause_time = 0.0
	_game_result = GameResult.NONE
	_player_faction_id = player_faction
	_difficulty = difficulty
	_current_wave = 0
	_last_duration_milestone = 0

	_initialize_factions()

	game_started.emit()
	print("GameStateManager: Match started (Player faction: %d, Difficulty: %d)" % [player_faction, difficulty])


## Pause the match
func pause_match() -> void:
	if _match_status != MatchStatus.ACTIVE:
		return

	_match_status = MatchStatus.PAUSED
	_pause_start_time = _match_duration

	game_paused.emit()
	print("GameStateManager: Match paused at %.1fs" % _match_duration)


## Resume the match
func resume_match() -> void:
	if _match_status != MatchStatus.PAUSED:
		return

	_total_pause_time += _match_duration - _pause_start_time
	_match_status = MatchStatus.ACTIVE

	game_resumed.emit()
	print("GameStateManager: Match resumed")


## End the match
func end_match(result: GameResult) -> void:
	if _match_status == MatchStatus.ENDED:
		return

	_match_status = MatchStatus.ENDED
	_game_result = result

	game_ended.emit(result)
	print("GameStateManager: Match ended with result %d after %.1fs" % [result, _match_duration])


## Get current match status
func get_match_status() -> MatchStatus:
	return _match_status


## Check if match is active
func is_match_active() -> bool:
	return _match_status == MatchStatus.ACTIVE


## Check if match is paused
func is_match_paused() -> bool:
	return _match_status == MatchStatus.PAUSED


## Check if match has ended
func is_match_ended() -> bool:
	return _match_status == MatchStatus.ENDED


## Get match duration in seconds
func get_match_duration() -> float:
	return _match_duration


## Get match duration formatted as string
func get_formatted_duration() -> String:
	return SaveFormat.format_play_time(_match_duration)


## Get match start timestamp
func get_match_start_time() -> int:
	return _match_start_time


## Get total pause time
func get_total_pause_time() -> float:
	return _total_pause_time


## Get game result
func get_game_result() -> GameResult:
	return _game_result


## Get player faction ID
func get_player_faction_id() -> int:
	return _player_faction_id


## Get current wave number
func get_current_wave() -> int:
	return _current_wave


## Set current wave number
func set_current_wave(wave: int) -> void:
	_current_wave = wave


## Increment wave number
func advance_wave() -> int:
	_current_wave += 1
	return _current_wave


## Get difficulty level
func get_difficulty() -> int:
	return _difficulty


# ============================================
# FACTION STATUS MANAGEMENT
# ============================================

## Initialize faction statuses
func _initialize_factions() -> void:
	_faction_statuses.clear()

	# Create status for each faction type
	for faction_id in range(1, 6):  # 1-5 from FactionComponent
		var status := FactionStatus.new()
		status.faction_id = faction_id
		status.faction_name = FactionComponent.get_faction_name_for_id(faction_id)
		status.is_player = (faction_id == _player_faction_id)
		_faction_statuses[faction_id] = status


## Get faction status
func get_faction_status(faction_id: int) -> FactionStatus:
	return _faction_statuses.get(faction_id)


## Get all faction statuses
func get_all_faction_statuses() -> Array[FactionStatus]:
	var statuses: Array[FactionStatus] = []
	for id in _faction_statuses:
		statuses.append(_faction_statuses[id])
	return statuses


## Get active (non-eliminated) factions
func get_active_factions() -> Array[FactionStatus]:
	var active: Array[FactionStatus] = []
	for id in _faction_statuses:
		var status: FactionStatus = _faction_statuses[id]
		if not status.is_eliminated:
			active.append(status)
	return active


## Update faction unit count
func update_faction_unit_count(faction_id: int, count: int) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status == null:
		return

	status.unit_count = count
	status.max_unit_count = maxi(status.max_unit_count, count)
	faction_status_changed.emit(faction_id)


## Update faction resource amount
func update_faction_resource(faction_id: int, resource_type: String, amount: float) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status == null:
		return

	status.resources[resource_type] = amount
	faction_status_changed.emit(faction_id)


## Update faction factory count
func update_faction_factory_count(faction_id: int, count: int) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status == null:
		return

	var previous_count := status.factory_count
	status.factory_count = count

	# Check for elimination (no factories = eliminated)
	if count == 0 and previous_count > 0 and not status.is_eliminated:
		eliminate_faction(faction_id)
	else:
		faction_status_changed.emit(faction_id)


## Update faction building count
func update_faction_building_count(faction_id: int, count: int) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status == null:
		return

	status.building_count = count
	faction_status_changed.emit(faction_id)


## Update faction district count
func update_faction_district_count(faction_id: int, count: int) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status == null:
		return

	status.district_count = count
	faction_status_changed.emit(faction_id)


## Record unit created
func record_unit_created(faction_id: int) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status != null:
		status.units_created += 1


## Record unit lost
func record_unit_lost(faction_id: int) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status != null:
		status.units_lost += 1


## Record unit killed (by this faction)
func record_unit_killed(faction_id: int) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status != null:
		status.units_killed += 1


## Record damage dealt
func record_damage_dealt(faction_id: int, damage: float) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status != null:
		status.damage_dealt += damage


## Record damage taken
func record_damage_taken(faction_id: int, damage: float) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status != null:
		status.damage_taken += damage


## Eliminate a faction
func eliminate_faction(faction_id: int) -> void:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	if status == null or status.is_eliminated:
		return

	status.is_eliminated = true
	status.elimination_time = _match_duration

	faction_eliminated.emit(faction_id)
	print("GameStateManager: Faction %d (%s) eliminated at %.1fs" % [
		faction_id, status.faction_name, _match_duration
	])


## Check if faction is eliminated
func is_faction_eliminated(faction_id: int) -> bool:
	var status: FactionStatus = _faction_statuses.get(faction_id)
	return status != null and status.is_eliminated


## Get player faction status
func get_player_status() -> FactionStatus:
	return get_faction_status(_player_faction_id)


# ============================================
# SERIALIZATION
# ============================================

## Export state for saving
func to_dict() -> Dictionary:
	var faction_data := {}
	for id in _faction_statuses:
		faction_data[id] = _faction_statuses[id].to_dict()

	return {
		"match_status": _match_status,
		"match_start_time": _match_start_time,
		"match_duration": _match_duration,
		"total_pause_time": _total_pause_time,
		"game_result": _game_result,
		"player_faction_id": _player_faction_id,
		"current_wave": _current_wave,
		"difficulty": _difficulty,
		"last_duration_milestone": _last_duration_milestone,
		"faction_statuses": faction_data
	}


## Import state from save
func from_dict(data: Dictionary) -> void:
	_match_status = data.get("match_status", MatchStatus.NOT_STARTED)
	_match_start_time = data.get("match_start_time", 0)
	_match_duration = data.get("match_duration", 0.0)
	_total_pause_time = data.get("total_pause_time", 0.0)
	_game_result = data.get("game_result", GameResult.NONE)
	_player_faction_id = data.get("player_faction_id", 0)
	_current_wave = data.get("current_wave", 0)
	_difficulty = data.get("difficulty", 0)
	_last_duration_milestone = data.get("last_duration_milestone", 0)

	_faction_statuses.clear()
	var faction_data: Dictionary = data.get("faction_statuses", {})
	for id in faction_data:
		_faction_statuses[int(id)] = FactionStatus.from_dict(faction_data[id])


## Check and emit duration milestones (every minute)
func _check_duration_milestones() -> void:
	var current_minute := int(_match_duration / 60.0)
	if current_minute > _last_duration_milestone:
		_last_duration_milestone = current_minute
		match_duration_milestone.emit(current_minute)


## Get match summary for end screen
func get_match_summary() -> Dictionary:
	var player_status := get_player_status()

	return {
		"duration": _match_duration,
		"formatted_duration": get_formatted_duration(),
		"result": _game_result,
		"wave_reached": _current_wave,
		"difficulty": _difficulty,
		"player_faction": _player_faction_id,
		"player_stats": player_status.to_dict() if player_status else {},
		"factions_eliminated": get_all_faction_statuses().filter(func(s): return s.is_eliminated).size(),
		"active_factions": get_active_factions().size()
	}
