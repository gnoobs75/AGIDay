class_name EndGameManager
extends RefCounted
## EndGameManager orchestrates victory/defeat flow and game state transitions.
## Handles user experience when victory/defeat occurs and coordinates external systems.

signal victory_achieved(faction_id: int, statistics: Dictionary)
signal defeat_occurred(faction_id: int, statistics: Dictionary, reason: String)
signal faction_eliminated(faction_id: int)
signal game_ended(final_statistics: Dictionary)
signal continue_playing_started(faction_id: int)
signal spectator_mode_started(faction_id: int)
signal return_to_menu_requested()
signal leaderboard_submission_ready(data: Dictionary)
signal replay_save_ready(game_state: Dictionary)
signal state_transition_started(from_state: int, to_state: int)
signal state_transition_completed(new_state: int)

## Game states
enum GameState {
	PLAYING,
	VICTORY_SCREEN,
	DEFEAT_SCREEN,
	SPECTATING,
	SURVIVAL_MODE,
	ENDED,
	TRANSITIONING
}

## Defeat reasons
enum DefeatReason {
	FACTORY_DESTROYED,
	ALL_UNITS_LOST,
	ELIMINATED,
	SURRENDERED,
	TIMEOUT
}

## Current state
var _current_state: GameState = GameState.PLAYING
var _player_faction_id: int = 0
var _is_transitioning: bool = false

## Faction status tracking
var _faction_status: Dictionary = {}    ## faction_id -> EndGameFactionStatus
var _eliminated_factions: Array[int] = []
var _victorious_factions: Array[int] = []

## Statistics tracking
var _match_statistics: Dictionary = {}
var _faction_statistics: Dictionary = {}  ## faction_id -> Dictionary

## Victory/defeat timestamps
var _victory_timestamp: int = 0
var _defeat_timestamp: int = 0
var _game_start_time: int = 0
var _waves_survived: int = 0

## External system readiness
var _leaderboard_ready: bool = false
var _replay_ready: bool = false


func _init() -> void:
	_game_start_time = Time.get_ticks_msec()


## Initialize with player faction.
func initialize(player_faction: int, all_faction_ids: Array[int]) -> void:
	_player_faction_id = player_faction

	for faction_id in all_faction_ids:
		var status := EndGameFactionStatus.new()
		status.faction_id = faction_id
		status.is_player = (faction_id == player_faction)
		status.is_alive = true
		status.is_victorious = false
		_faction_status[faction_id] = status

		_faction_statistics[faction_id] = _create_empty_statistics()


## Create empty statistics dictionary.
func _create_empty_statistics() -> Dictionary:
	return {
		"units_killed": 0,
		"units_lost": 0,
		"resources_earned": 0,
		"resources_spent": 0,
		"districts_captured": 0,
		"districts_lost": 0,
		"waves_survived": 0,
		"damage_dealt": 0.0,
		"damage_taken": 0.0,
		"buildings_destroyed": 0,
		"time_played_ms": 0
	}


## Handle victory event for faction.
func handle_victory(faction_id: int) -> void:
	if _is_transitioning:
		return

	var status: EndGameFactionStatus = _faction_status.get(faction_id)
	if status == null or status.is_victorious:
		return

	status.is_victorious = true
	_victorious_factions.append(faction_id)
	_victory_timestamp = Time.get_ticks_msec()

	# Update statistics
	var stats := _compile_faction_statistics(faction_id)
	stats["victory_timestamp"] = _victory_timestamp
	stats["waves_survived"] = _waves_survived
	stats["match_duration_ms"] = _victory_timestamp - _game_start_time

	# Transition state
	if faction_id == _player_faction_id:
		_transition_to_state(GameState.VICTORY_SCREEN)
		victory_achieved.emit(faction_id, stats)

		# Prepare external system data
		_prepare_leaderboard_data(faction_id, stats)
		_prepare_replay_data()


## Handle defeat event for faction.
func handle_defeat(faction_id: int, reason: DefeatReason) -> void:
	if _is_transitioning:
		return

	var status: EndGameFactionStatus = _faction_status.get(faction_id)
	if status == null or not status.is_alive:
		return

	status.is_alive = false
	status.defeat_reason = reason
	_eliminated_factions.append(faction_id)
	_defeat_timestamp = Time.get_ticks_msec()

	faction_eliminated.emit(faction_id)

	# Update statistics
	var stats := _compile_faction_statistics(faction_id)
	stats["defeat_timestamp"] = _defeat_timestamp
	stats["defeat_reason"] = _get_defeat_reason_name(reason)
	stats["waves_survived"] = _waves_survived
	stats["match_duration_ms"] = _defeat_timestamp - _game_start_time

	# Transition state if player defeated
	if faction_id == _player_faction_id:
		_transition_to_state(GameState.DEFEAT_SCREEN)
		defeat_occurred.emit(faction_id, stats, _get_defeat_reason_name(reason))

	# Check if game should end (all factions eliminated)
	_check_game_end()


## Check if faction is eliminated (factory destroyed AND no units).
func check_elimination(faction_id: int, has_factory: bool, unit_count: int) -> bool:
	if not has_factory and unit_count <= 0:
		handle_defeat(faction_id, DefeatReason.ELIMINATED)
		return true
	elif not has_factory:
		handle_defeat(faction_id, DefeatReason.FACTORY_DESTROYED)
		return true
	elif unit_count <= 0:
		# Only units lost but factory remains - not eliminated yet
		pass
	return false


## Compile statistics for faction.
func _compile_faction_statistics(faction_id: int) -> Dictionary:
	var stats: Dictionary = _faction_statistics.get(faction_id, {}).duplicate()
	stats["time_played_ms"] = Time.get_ticks_msec() - _game_start_time
	return stats


## Transition to new game state.
func _transition_to_state(new_state: GameState) -> void:
	if _current_state == new_state:
		return

	_is_transitioning = true
	var old_state := _current_state

	state_transition_started.emit(old_state, new_state)

	_current_state = new_state
	_is_transitioning = false

	state_transition_completed.emit(new_state)


## Continue playing after victory (survival mode).
func continue_playing(faction_id: int) -> void:
	if faction_id != _player_faction_id:
		return

	if _current_state != GameState.VICTORY_SCREEN:
		return

	_transition_to_state(GameState.SURVIVAL_MODE)
	continue_playing_started.emit(faction_id)


## Enter spectator mode after defeat.
func enter_spectator_mode(faction_id: int) -> void:
	if faction_id != _player_faction_id:
		return

	if _current_state != GameState.DEFEAT_SCREEN:
		return

	_transition_to_state(GameState.SPECTATING)
	spectator_mode_started.emit(faction_id)


## Return to main menu.
func return_to_menu() -> void:
	_transition_to_state(GameState.ENDED)
	return_to_menu_requested.emit()


## Check if game should end.
func _check_game_end() -> void:
	var alive_factions := 0
	for faction_id in _faction_status:
		var status: EndGameFactionStatus = _faction_status[faction_id]
		if status.is_alive:
			alive_factions += 1

	# Game ends when 0 or 1 factions remain
	if alive_factions <= 1:
		_end_game()


## End the game.
func _end_game() -> void:
	_transition_to_state(GameState.ENDED)

	var final_stats := {
		"match_duration_ms": Time.get_ticks_msec() - _game_start_time,
		"waves_survived": _waves_survived,
		"victorious_factions": _victorious_factions.duplicate(),
		"eliminated_factions": _eliminated_factions.duplicate(),
		"faction_statistics": _faction_statistics.duplicate()
	}

	game_ended.emit(final_stats)


## Prepare leaderboard submission data.
func _prepare_leaderboard_data(faction_id: int, stats: Dictionary) -> void:
	var data := {
		"faction_id": faction_id,
		"score": _calculate_score(stats),
		"waves_survived": stats.get("waves_survived", 0),
		"match_duration_ms": stats.get("match_duration_ms", 0),
		"units_killed": stats.get("units_killed", 0),
		"districts_captured": stats.get("districts_captured", 0),
		"timestamp": Time.get_ticks_msec()
	}

	_leaderboard_ready = true
	leaderboard_submission_ready.emit(data)


## Calculate score for leaderboard.
func _calculate_score(stats: Dictionary) -> int:
	var score := 0
	score += stats.get("units_killed", 0) * 10
	score += stats.get("districts_captured", 0) * 100
	score += stats.get("waves_survived", 0) * 50
	score += int(stats.get("damage_dealt", 0.0) / 100.0)
	return score


## Prepare replay data.
func _prepare_replay_data() -> void:
	var replay_data := {
		"player_faction": _player_faction_id,
		"faction_status": {},
		"match_statistics": _match_statistics.duplicate(),
		"faction_statistics": _faction_statistics.duplicate(),
		"game_start_time": _game_start_time,
		"timestamp": Time.get_ticks_msec()
	}

	for faction_id in _faction_status:
		var status: EndGameFactionStatus = _faction_status[faction_id]
		replay_data["faction_status"][faction_id] = status.to_dict()

	_replay_ready = true
	replay_save_ready.emit(replay_data)


## Update statistics for faction.
func update_statistic(faction_id: int, stat_name: String, value) -> void:
	if not _faction_statistics.has(faction_id):
		return

	var stats: Dictionary = _faction_statistics[faction_id]
	if stats.has(stat_name):
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			stats[stat_name] += value
		else:
			stats[stat_name] = value


## Set wave count.
func set_waves_survived(waves: int) -> void:
	_waves_survived = waves


## Revert districts to neutral when faction eliminated.
func get_districts_to_revert(faction_id: int) -> Array[int]:
	# Would be populated by district manager
	return []


## Get defeat reason name.
func _get_defeat_reason_name(reason: DefeatReason) -> String:
	match reason:
		DefeatReason.FACTORY_DESTROYED: return "Factory Destroyed"
		DefeatReason.ALL_UNITS_LOST: return "All Units Lost"
		DefeatReason.ELIMINATED: return "Eliminated"
		DefeatReason.SURRENDERED: return "Surrendered"
		DefeatReason.TIMEOUT: return "Time Out"
	return "Unknown"


## Get current game state.
func get_current_state() -> GameState:
	return _current_state


## Get state name.
static func get_state_name(state: GameState) -> String:
	match state:
		GameState.PLAYING: return "Playing"
		GameState.VICTORY_SCREEN: return "Victory"
		GameState.DEFEAT_SCREEN: return "Defeat"
		GameState.SPECTATING: return "Spectating"
		GameState.SURVIVAL_MODE: return "Survival"
		GameState.ENDED: return "Ended"
		GameState.TRANSITIONING: return "Transitioning"
	return "Unknown"


## Check if faction is alive.
func is_faction_alive(faction_id: int) -> bool:
	if _faction_status.has(faction_id):
		return _faction_status[faction_id].is_alive
	return false


## Check if faction is victorious.
func is_faction_victorious(faction_id: int) -> bool:
	if _faction_status.has(faction_id):
		return _faction_status[faction_id].is_victorious
	return false


## Get alive faction count.
func get_alive_faction_count() -> int:
	var count := 0
	for faction_id in _faction_status:
		if _faction_status[faction_id].is_alive:
			count += 1
	return count


## Get faction statistics.
func get_faction_statistics(faction_id: int) -> Dictionary:
	return _faction_statistics.get(faction_id, {}).duplicate()


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"current_state": get_state_name(_current_state),
		"player_faction": _player_faction_id,
		"alive_factions": get_alive_faction_count(),
		"eliminated_factions": _eliminated_factions.size(),
		"victorious_factions": _victorious_factions.size(),
		"waves_survived": _waves_survived,
		"match_duration_ms": Time.get_ticks_msec() - _game_start_time,
		"leaderboard_ready": _leaderboard_ready,
		"replay_ready": _replay_ready
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var statuses := {}
	for faction_id in _faction_status:
		var status: EndGameFactionStatus = _faction_status[faction_id]
		statuses[str(faction_id)] = status.to_dict()

	return {
		"current_state": _current_state,
		"player_faction_id": _player_faction_id,
		"is_transitioning": _is_transitioning,
		"faction_status": statuses,
		"eliminated_factions": _eliminated_factions.duplicate(),
		"victorious_factions": _victorious_factions.duplicate(),
		"faction_statistics": _faction_statistics.duplicate(),
		"victory_timestamp": _victory_timestamp,
		"defeat_timestamp": _defeat_timestamp,
		"game_start_time": _game_start_time,
		"waves_survived": _waves_survived
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_current_state = data.get("current_state", GameState.PLAYING)
	_player_faction_id = data.get("player_faction_id", 0)
	_is_transitioning = data.get("is_transitioning", false)
	_victory_timestamp = data.get("victory_timestamp", 0)
	_defeat_timestamp = data.get("defeat_timestamp", 0)
	_game_start_time = data.get("game_start_time", 0)
	_waves_survived = data.get("waves_survived", 0)

	_eliminated_factions.clear()
	var eliminated: Array = data.get("eliminated_factions", [])
	for f_id in eliminated:
		_eliminated_factions.append(f_id)

	_victorious_factions.clear()
	var victorious: Array = data.get("victorious_factions", [])
	for f_id in victorious:
		_victorious_factions.append(f_id)

	_faction_status.clear()
	var statuses: Dictionary = data.get("faction_status", {})
	for key in statuses:
		var status := EndGameFactionStatus.new()
		status.from_dict(statuses[key])
		_faction_status[int(key)] = status

	_faction_statistics = data.get("faction_statistics", {}).duplicate()


## EndGameFactionStatus inner class.
class EndGameFactionStatus:
	var faction_id: int = -1
	var is_player: bool = false
	var is_alive: bool = true
	var is_victorious: bool = false
	var defeat_reason: int = -1  ## DefeatReason enum

	func to_dict() -> Dictionary:
		return {
			"faction_id": faction_id,
			"is_player": is_player,
			"is_alive": is_alive,
			"is_victorious": is_victorious,
			"defeat_reason": defeat_reason
		}

	func from_dict(data: Dictionary) -> void:
		faction_id = data.get("faction_id", -1)
		is_player = data.get("is_player", false)
		is_alive = data.get("is_alive", true)
		is_victorious = data.get("is_victorious", false)
		defeat_reason = data.get("defeat_reason", -1)
