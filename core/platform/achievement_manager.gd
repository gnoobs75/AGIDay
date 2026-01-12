class_name AchievementManager
extends RefCounted
## AchievementManager tracks player milestones and unlocks Steam achievements.
## Handles progress tracking, offline storage, and Steam synchronization.

signal achievement_unlocked(achievement_id: String, achievement_data: Dictionary)
signal achievement_progress(achievement_id: String, current: int, target: int)
signal all_achievements_loaded()

## Steam reference
var _steam_manager: SteamManager = null

## Achievement data
var _achievements: Dictionary = {}          ## achievement_id -> AchievementData
var _progress: Dictionary = {}              ## achievement_id -> current progress
var _unlocked: Dictionary = {}              ## achievement_id -> unlock timestamp
var _pending_unlocks: Array[String] = []

## Statistics for achievements
var _stats: Dictionary = {
	"total_kills": 0,
	"total_deaths": 0,
	"total_damage_dealt": 0,
	"total_damage_taken": 0,
	"units_produced": 0,
	"buildings_destroyed": 0,
	"factories_captured": 0,
	"districts_controlled": 0,
	"resources_collected": 0,
	"games_won": 0,
	"games_played": 0,
	"fastest_win_time": 0,
	"highest_wave": 0,
	"faction_kills": {},  ## faction_id -> kill count
	"ability_uses": 0,
	"perfect_waves": 0    ## Waves completed without losing units
}

## Local storage for offline mode
const SAVE_PATH := "user://achievements.json"


func _init() -> void:
	_register_default_achievements()


## Initialize with Steam manager.
func initialize(steam_manager: SteamManager) -> void:
	_steam_manager = steam_manager

	# Load local progress
	_load_local_progress()

	# Sync with Steam if available
	if _steam_manager != null and _steam_manager.is_initialized():
		_sync_with_steam()


## Register default achievements.
func _register_default_achievements() -> void:
	# Kill achievements
	register_achievement("zerg_lord", "Zerg Lord", "Kill 10,000 enemy units", 10000, "kills")
	register_achievement("first_blood", "First Blood", "Kill your first enemy unit", 1, "kills")
	register_achievement("century_club", "Century Club", "Kill 100 enemy units in a single game", 100, "kills_single_game")
	register_achievement("genocide", "Genocide", "Eliminate an entire faction", 1, "factions_eliminated")

	# Production achievements
	register_achievement("factory_master", "Factory Master", "Produce 1,000 units", 1000, "units_produced")
	register_achievement("industrial_revolution", "Industrial Revolution", "Control 4 factories simultaneously", 4, "factories_controlled")
	register_achievement("overclock_king", "Overclock King", "Produce 50 units while overclocked", 50, "overclock_productions")

	# Destruction achievements
	register_achievement("demolition_expert", "Demolition Expert", "Destroy 500 buildings", 500, "buildings_destroyed")
	register_achievement("city_destroyer", "City Destroyer", "Destroy an entire district", 1, "districts_destroyed")

	# Victory achievements
	register_achievement("first_victory", "First Victory", "Win your first game", 1, "games_won")
	register_achievement("domination", "Domination", "Win 10 games", 10, "games_won")
	register_achievement("speed_runner", "Speed Runner", "Win a game in under 30 minutes", 1, "fast_wins")
	register_achievement("perfect_game", "Perfect Game", "Win without losing your starting factory", 1, "perfect_wins")

	# Faction achievements
	register_achievement("swarm_master", "Swarm Master", "Win as Aether Swarm", 1, "wins_aether_swarm")
	register_achievement("legion_commander", "Legion Commander", "Win as OptiForge Legion", 1, "wins_optiforge")
	register_achievement("vanguard_leader", "Vanguard Leader", "Win as Dynapods Vanguard", 1, "wins_dynapods")
	register_achievement("colossus_pilot", "Colossus Pilot", "Win as LogiBots Colossus", 1, "wins_logibots")
	register_achievement("faction_master", "Faction Master", "Win with all factions", 4, "unique_faction_wins")

	# Wave achievements
	register_achievement("survivor", "Survivor", "Survive wave 10", 10, "highest_wave")
	register_achievement("endurance", "Endurance", "Survive wave 25", 25, "highest_wave")
	register_achievement("unstoppable", "Unstoppable", "Survive wave 50", 50, "highest_wave")
	register_achievement("flawless_wave", "Flawless Wave", "Complete a wave without losing any units", 1, "perfect_waves")

	# Special achievements
	register_achievement("human_hunter", "Human Hunter", "Kill 1,000 Human Resistance units", 1000, "human_kills")
	register_achievement("hacker_bane", "Hacker Bane", "Destroy 10 hacking drones", 10, "hackers_killed")
	register_achievement("resource_mogul", "Resource Mogul", "Collect 100,000 REE", 100000, "resources_collected")


## Register an achievement.
func register_achievement(id: String, name: String, description: String,
						   target: int, stat_key: String) -> void:
	_achievements[id] = AchievementData.new(id, name, description, target, stat_key)


## Check and update achievement progress.
func check_progress(stat_key: String, value: int = 1, set_absolute: bool = false) -> void:
	# Update stat
	if set_absolute:
		_stats[stat_key] = value
	else:
		if not _stats.has(stat_key):
			_stats[stat_key] = 0
		_stats[stat_key] += value

	# Check all achievements that use this stat
	for achievement_id in _achievements:
		var achievement: AchievementData = _achievements[achievement_id]
		if achievement.stat_key != stat_key:
			continue

		if _unlocked.has(achievement_id):
			continue  ## Already unlocked

		var current: int = _stats.get(stat_key, 0)
		var target: int = achievement.target

		# Update progress
		_progress[achievement_id] = current
		achievement_progress.emit(achievement_id, current, target)

		# Check for unlock
		if current >= target:
			_unlock_achievement(achievement_id)


## Report a kill.
func report_kill(victim_faction: String = "") -> void:
	check_progress("total_kills")
	check_progress("kills")
	check_progress("kills_single_game")

	if victim_faction == "human_remnant":
		check_progress("human_kills")

	if not _stats.has("faction_kills"):
		_stats["faction_kills"] = {}
	if not _stats["faction_kills"].has(victim_faction):
		_stats["faction_kills"][victim_faction] = 0
	_stats["faction_kills"][victim_faction] += 1


## Report a death.
func report_death() -> void:
	check_progress("total_deaths")


## Report unit production.
func report_unit_produced(was_overclocked: bool = false) -> void:
	check_progress("units_produced")
	if was_overclocked:
		check_progress("overclock_productions")


## Report building destroyed.
func report_building_destroyed() -> void:
	check_progress("buildings_destroyed")


## Report factory captured.
func report_factory_captured(total_controlled: int) -> void:
	check_progress("factories_captured")
	check_progress("factories_controlled", total_controlled, true)


## Report game won.
func report_game_won(faction_id: String, time_seconds: float, starting_factory_lost: bool) -> void:
	check_progress("games_won")
	check_progress("games_played")

	# Faction-specific win
	match faction_id:
		"aether_swarm":
			check_progress("wins_aether_swarm")
		"optiforge_legion":
			check_progress("wins_optiforge")
		"dynapods_vanguard":
			check_progress("wins_dynapods")
		"logibots_colossus":
			check_progress("wins_logibots")

	# Track unique faction wins
	if not _stats.has("faction_wins_unique"):
		_stats["faction_wins_unique"] = {}
	if not _stats["faction_wins_unique"].has(faction_id):
		_stats["faction_wins_unique"][faction_id] = true
		check_progress("unique_faction_wins")

	# Speed run check (30 minutes = 1800 seconds)
	if time_seconds > 0 and time_seconds < 1800:
		check_progress("fast_wins")

	# Perfect game check
	if not starting_factory_lost:
		check_progress("perfect_wins")


## Report wave completed.
func report_wave_completed(wave_number: int, units_lost: int) -> void:
	check_progress("highest_wave", wave_number, true)

	if units_lost == 0:
		check_progress("perfect_waves")


## Report resources collected.
func report_resources_collected(amount: int) -> void:
	check_progress("resources_collected", amount)


## Unlock an achievement.
func _unlock_achievement(achievement_id: String) -> void:
	if _unlocked.has(achievement_id):
		return

	_unlocked[achievement_id] = Time.get_ticks_msec()

	var achievement: AchievementData = _achievements.get(achievement_id)
	if achievement == null:
		return

	# Unlock on Steam
	if _steam_manager != null:
		_steam_manager.set_achievement(achievement_id)
		_steam_manager.store_stats()
	else:
		_pending_unlocks.append(achievement_id)

	# Save locally
	_save_local_progress()

	achievement_unlocked.emit(achievement_id, achievement.to_dict())


## Get achievement info.
func get_achievement(achievement_id: String) -> Dictionary:
	if not _achievements.has(achievement_id):
		return {}

	var achievement: AchievementData = _achievements[achievement_id]
	var info := achievement.to_dict()
	info["unlocked"] = _unlocked.has(achievement_id)
	info["current_progress"] = _progress.get(achievement_id, 0)
	info["unlock_time"] = _unlocked.get(achievement_id, 0)
	return info


## Get all achievements.
func get_all_achievements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for achievement_id in _achievements:
		result.append(get_achievement(achievement_id))
	return result


## Get unlocked count.
func get_unlocked_count() -> int:
	return _unlocked.size()


## Get total count.
func get_total_count() -> int:
	return _achievements.size()


## Get completion percentage.
func get_completion_percentage() -> float:
	if _achievements.is_empty():
		return 0.0
	return float(_unlocked.size()) / float(_achievements.size()) * 100.0


## Sync with Steam.
func _sync_with_steam() -> void:
	if _steam_manager == null:
		return

	# Sync pending unlocks
	for achievement_id in _pending_unlocks:
		_steam_manager.set_achievement(achievement_id)
	_pending_unlocks.clear()

	# Sync stats
	for stat_key in _stats:
		var value = _stats[stat_key]
		if value is int:
			_steam_manager.set_stat_int(stat_key, value)
		elif value is float:
			_steam_manager.set_stat_float(stat_key, value)

	_steam_manager.store_stats()


## Save progress locally.
func _save_local_progress() -> void:
	var save_data := {
		"stats": _stats,
		"progress": _progress,
		"unlocked": _unlocked,
		"pending_unlocks": _pending_unlocks
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(save_data))
		file.close()


## Load progress locally.
func _load_local_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var json_string := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_string)
	if parsed is Dictionary:
		_stats = parsed.get("stats", {})
		_progress = parsed.get("progress", {})
		_unlocked = parsed.get("unlocked", {})
		_pending_unlocks.assign(parsed.get("pending_unlocks", []))

	all_achievements_loaded.emit()


## Reset single game stats (call at game start).
func reset_single_game_stats() -> void:
	_stats["kills_single_game"] = 0


## AchievementData helper class.
class AchievementData:
	var id: String
	var name: String
	var description: String
	var target: int
	var stat_key: String

	func _init(p_id: String, p_name: String, p_desc: String, p_target: int, p_stat: String) -> void:
		id = p_id
		name = p_name
		description = p_desc
		target = p_target
		stat_key = p_stat

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"description": description,
			"target": target,
			"stat_key": stat_key
		}
