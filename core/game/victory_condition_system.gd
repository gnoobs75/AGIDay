class_name VictoryConditionSystem
extends RefCounted
## VictoryConditionSystem provides continuous monitoring of victory and defeat conditions.
## Integrates district domination and factory elimination with EndGameManager.
## Supports endless gameplay continuation after initial victory.

signal victory_condition_met(faction_id: int, condition_type: int)
signal defeat_condition_met(faction_id: int, reason: int)
signal faction_eliminated(faction_id: int)
signal domination_progress_changed(faction_id: int, progress: float)
signal domination_warning(faction_id: int, districts_remaining: int)
signal last_faction_standing(faction_id: int)
signal endless_mode_started()
signal condition_check_completed(results: Dictionary)

## Victory condition types
enum VictoryType {
	DISTRICT_DOMINATION,    ## Control all districts
	FACTORY_ELIMINATION,    ## Destroy all enemy factories
	LAST_STANDING           ## Be last surviving faction
}

## Defeat reason types
enum DefeatReason {
	FACTORY_DESTROYED,      ## All factories destroyed
	ALL_UNITS_LOST,         ## No units remaining (with no factories)
	ELIMINATED,             ## Combined: no factories and no units
	SURRENDERED             ## Player surrendered
}

## Check intervals for performance optimization
const CHECK_INTERVAL_FAST := 0.5    ## When close to victory
const CHECK_INTERVAL_NORMAL := 1.0  ## Normal gameplay
const CHECK_INTERVAL_SLOW := 2.0    ## Early game or far from victory

## Domination warning thresholds
const DOMINATION_WARNING_THRESHOLD := 3   ## Warn when 3 districts remaining
const CLOSE_TO_VICTORY_THRESHOLD := 0.8   ## 80% progress = close to victory

## Faction data tracking
var _faction_districts: Dictionary = {}      ## faction_id -> district count
var _faction_factories: Dictionary = {}      ## faction_id -> factory count
var _faction_units: Dictionary = {}          ## faction_id -> unit count
var _faction_eliminated: Dictionary = {}     ## faction_id -> bool
var _faction_victory: Dictionary = {}        ## faction_id -> bool

## Map configuration
var _total_districts: int = 64
var _active_faction_ids: Array[int] = []
var _player_faction_id: int = 0

## Monitoring state
var _is_monitoring: bool = false
var _check_timer: float = 0.0
var _current_check_interval: float = CHECK_INTERVAL_NORMAL
var _last_check_results: Dictionary = {}

## Victory state
var _victory_achieved: bool = false
var _winning_faction_id: int = -1
var _victory_type: VictoryType = VictoryType.DISTRICT_DOMINATION
var _endless_mode_active: bool = false

## Performance tracking
var _checks_performed: int = 0
var _last_check_time_ms: float = 0.0


func _init() -> void:
	pass


## Initialize the victory condition system.
func initialize(player_faction: int, faction_ids: Array[int], total_districts: int = 64) -> void:
	_player_faction_id = player_faction
	_active_faction_ids = faction_ids.duplicate()
	_total_districts = total_districts

	# Initialize tracking dictionaries
	_faction_districts.clear()
	_faction_factories.clear()
	_faction_units.clear()
	_faction_eliminated.clear()
	_faction_victory.clear()

	for faction_id in faction_ids:
		_faction_districts[faction_id] = 0
		_faction_factories[faction_id] = 1  # Start with 1 factory
		_faction_units[faction_id] = 0
		_faction_eliminated[faction_id] = false
		_faction_victory[faction_id] = false

	_victory_achieved = false
	_winning_faction_id = -1
	_endless_mode_active = false
	_checks_performed = 0


## Start continuous monitoring.
func start_monitoring() -> void:
	_is_monitoring = true
	_check_timer = 0.0


## Stop monitoring.
func stop_monitoring() -> void:
	_is_monitoring = false


## Update (called each frame).
func update(delta: float) -> void:
	if not _is_monitoring:
		return

	_check_timer += delta

	if _check_timer >= _current_check_interval:
		_check_timer = 0.0
		_perform_condition_check()


## Manually trigger a condition check.
func check_now() -> Dictionary:
	_perform_condition_check()
	return _last_check_results


## Perform all condition checks.
func _perform_condition_check() -> void:
	var start_time := Time.get_ticks_usec()
	_checks_performed += 1

	var results := {
		"victory_achieved": false,
		"winner_faction": -1,
		"victory_type": -1,
		"eliminations": [],
		"domination_leader": -1,
		"domination_progress": 0.0,
		"active_factions": 0
	}

	# Skip checks if already in endless mode and victory achieved
	if _victory_achieved and _endless_mode_active:
		_last_check_results = results
		condition_check_completed.emit(results)
		return

	# Check for eliminations first
	var eliminations := _check_eliminations()
	results["eliminations"] = eliminations

	# Count active factions
	var active_count := _get_active_faction_count()
	results["active_factions"] = active_count

	# Check last faction standing
	if active_count == 1:
		var last_faction := _get_last_active_faction()
		if last_faction >= 0 and not _victory_achieved:
			_declare_victory(last_faction, VictoryType.LAST_STANDING)
			results["victory_achieved"] = true
			results["winner_faction"] = last_faction
			results["victory_type"] = VictoryType.LAST_STANDING

	# Check district domination
	var domination_result := _check_district_domination()
	results["domination_leader"] = domination_result.leader
	results["domination_progress"] = domination_result.progress

	if domination_result.achieved and not _victory_achieved:
		_declare_victory(domination_result.leader, VictoryType.DISTRICT_DOMINATION)
		results["victory_achieved"] = true
		results["winner_faction"] = domination_result.leader
		results["victory_type"] = VictoryType.DISTRICT_DOMINATION

	# Update check interval based on proximity to victory
	_update_check_interval(domination_result.progress)

	# Track performance
	_last_check_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
	_last_check_results = results

	condition_check_completed.emit(results)


## Check for faction eliminations.
func _check_eliminations() -> Array[int]:
	var newly_eliminated: Array[int] = []

	for faction_id in _active_faction_ids:
		if _faction_eliminated.get(faction_id, false):
			continue

		var has_factory: bool = _faction_factories.get(faction_id, 0) > 0
		var has_units: bool = _faction_units.get(faction_id, 0) > 0

		# Elimination conditions
		var reason: DefeatReason = -1

		if not has_factory and not has_units:
			reason = DefeatReason.ELIMINATED
		elif not has_factory:
			reason = DefeatReason.FACTORY_DESTROYED

		if reason >= 0:
			_eliminate_faction(faction_id, reason)
			newly_eliminated.append(faction_id)

	return newly_eliminated


## Eliminate a faction.
func _eliminate_faction(faction_id: int, reason: DefeatReason) -> void:
	if _faction_eliminated.get(faction_id, false):
		return

	_faction_eliminated[faction_id] = true

	faction_eliminated.emit(faction_id)
	defeat_condition_met.emit(faction_id, reason)


## Check district domination victory.
func _check_district_domination() -> Dictionary:
	var result := {
		"achieved": false,
		"leader": -1,
		"progress": 0.0,
		"districts_needed": _total_districts
	}

	var max_districts := 0
	var leader_faction := -1

	for faction_id in _active_faction_ids:
		if _faction_eliminated.get(faction_id, false):
			continue

		var districts: int = _faction_districts.get(faction_id, 0)

		if districts > max_districts:
			max_districts = districts
			leader_faction = faction_id

	if leader_faction >= 0:
		result["leader"] = leader_faction
		result["progress"] = float(max_districts) / float(_total_districts)
		result["districts_needed"] = _total_districts - max_districts

		# Emit domination progress
		domination_progress_changed.emit(leader_faction, result["progress"])

		# Check for warning
		if result["districts_needed"] <= DOMINATION_WARNING_THRESHOLD and result["districts_needed"] > 0:
			domination_warning.emit(leader_faction, result["districts_needed"])

		# Check for victory
		if max_districts >= _total_districts:
			result["achieved"] = true

	return result


## Declare victory for a faction.
func _declare_victory(faction_id: int, victory_type: VictoryType) -> void:
	if _victory_achieved:
		return

	_victory_achieved = true
	_winning_faction_id = faction_id
	_victory_type = victory_type
	_faction_victory[faction_id] = true

	victory_condition_met.emit(faction_id, victory_type)

	if _get_active_faction_count() == 1:
		last_faction_standing.emit(faction_id)


## Get active (non-eliminated) faction count.
func _get_active_faction_count() -> int:
	var count := 0
	for faction_id in _active_faction_ids:
		if not _faction_eliminated.get(faction_id, false):
			count += 1
	return count


## Get the last active faction.
func _get_last_active_faction() -> int:
	for faction_id in _active_faction_ids:
		if not _faction_eliminated.get(faction_id, false):
			return faction_id
	return -1


## Update check interval based on game state.
func _update_check_interval(domination_progress: float) -> void:
	if domination_progress >= CLOSE_TO_VICTORY_THRESHOLD:
		_current_check_interval = CHECK_INTERVAL_FAST
	elif domination_progress >= 0.5:
		_current_check_interval = CHECK_INTERVAL_NORMAL
	else:
		_current_check_interval = CHECK_INTERVAL_SLOW


## Enable endless mode (continue after victory).
func enable_endless_mode() -> void:
	if not _victory_achieved:
		return

	_endless_mode_active = true
	endless_mode_started.emit()


## Check if endless mode is active.
func is_endless_mode() -> bool:
	return _endless_mode_active


# ============================================
# DATA UPDATE METHODS
# ============================================

## Update district count for faction.
func update_faction_districts(faction_id: int, count: int) -> void:
	_faction_districts[faction_id] = count


## Update factory count for faction.
func update_faction_factories(faction_id: int, count: int) -> void:
	var previous: int = _faction_factories.get(faction_id, 0)
	_faction_factories[faction_id] = count

	# Immediate elimination check if factories hit zero
	if count == 0 and previous > 0:
		_perform_condition_check()


## Update unit count for faction.
func update_faction_units(faction_id: int, count: int) -> void:
	_faction_units[faction_id] = count


## Batch update all faction data.
func update_all_factions(districts: Dictionary, factories: Dictionary, units: Dictionary) -> void:
	_faction_districts = districts.duplicate()
	_faction_factories = factories.duplicate()
	_faction_units = units.duplicate()


## Handle player surrender.
func player_surrender() -> void:
	if _faction_eliminated.get(_player_faction_id, false):
		return

	_eliminate_faction(_player_faction_id, DefeatReason.SURRENDERED)
	_perform_condition_check()


# ============================================
# QUERY METHODS
# ============================================

## Check if victory has been achieved.
func is_victory_achieved() -> bool:
	return _victory_achieved


## Get the winning faction ID.
func get_winning_faction() -> int:
	return _winning_faction_id


## Get the victory type.
func get_victory_type() -> VictoryType:
	return _victory_type


## Check if faction is eliminated.
func is_faction_eliminated(faction_id: int) -> bool:
	return _faction_eliminated.get(faction_id, false)


## Check if faction achieved victory.
func is_faction_victorious(faction_id: int) -> bool:
	return _faction_victory.get(faction_id, false)


## Get domination progress for faction.
func get_domination_progress(faction_id: int) -> float:
	var districts: int = _faction_districts.get(faction_id, 0)
	return float(districts) / float(_total_districts)


## Get districts needed for domination victory.
func get_districts_needed(faction_id: int) -> int:
	var districts: int = _faction_districts.get(faction_id, 0)
	return maxi(0, _total_districts - districts)


## Get active factions.
func get_active_factions() -> Array[int]:
	var active: Array[int] = []
	for faction_id in _active_faction_ids:
		if not _faction_eliminated.get(faction_id, false):
			active.append(faction_id)
	return active


## Get eliminated factions.
func get_eliminated_factions() -> Array[int]:
	var eliminated: Array[int] = []
	for faction_id in _active_faction_ids:
		if _faction_eliminated.get(faction_id, false):
			eliminated.append(faction_id)
	return eliminated


## Get leading faction in district control.
func get_domination_leader() -> int:
	var max_districts := 0
	var leader := -1

	for faction_id in _active_faction_ids:
		if _faction_eliminated.get(faction_id, false):
			continue

		var districts: int = _faction_districts.get(faction_id, 0)
		if districts > max_districts:
			max_districts = districts
			leader = faction_id

	return leader


## Get victory type name.
static func get_victory_type_name(type: VictoryType) -> String:
	match type:
		VictoryType.DISTRICT_DOMINATION: return "District Domination"
		VictoryType.FACTORY_ELIMINATION: return "Factory Elimination"
		VictoryType.LAST_STANDING: return "Last Standing"
	return "Unknown"


## Get defeat reason name.
static func get_defeat_reason_name(reason: DefeatReason) -> String:
	match reason:
		DefeatReason.FACTORY_DESTROYED: return "Factory Destroyed"
		DefeatReason.ALL_UNITS_LOST: return "All Units Lost"
		DefeatReason.ELIMINATED: return "Eliminated"
		DefeatReason.SURRENDERED: return "Surrendered"
	return "Unknown"


# ============================================
# STATISTICS
# ============================================

## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"is_monitoring": _is_monitoring,
		"victory_achieved": _victory_achieved,
		"winning_faction": _winning_faction_id,
		"victory_type": get_victory_type_name(_victory_type) if _victory_achieved else "none",
		"endless_mode": _endless_mode_active,
		"active_factions": _get_active_faction_count(),
		"eliminated_factions": get_eliminated_factions().size(),
		"total_districts": _total_districts,
		"checks_performed": _checks_performed,
		"last_check_time_ms": _last_check_time_ms,
		"check_interval": _current_check_interval
	}


# ============================================
# SERIALIZATION
# ============================================

## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"player_faction_id": _player_faction_id,
		"active_faction_ids": _active_faction_ids.duplicate(),
		"total_districts": _total_districts,
		"faction_districts": _faction_districts.duplicate(),
		"faction_factories": _faction_factories.duplicate(),
		"faction_units": _faction_units.duplicate(),
		"faction_eliminated": _faction_eliminated.duplicate(),
		"faction_victory": _faction_victory.duplicate(),
		"victory_achieved": _victory_achieved,
		"winning_faction_id": _winning_faction_id,
		"victory_type": _victory_type,
		"endless_mode_active": _endless_mode_active,
		"is_monitoring": _is_monitoring,
		"current_check_interval": _current_check_interval,
		"checks_performed": _checks_performed
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_player_faction_id = data.get("player_faction_id", 0)
	_total_districts = data.get("total_districts", 64)

	_active_faction_ids.clear()
	var faction_ids: Array = data.get("active_faction_ids", [])
	for faction_id in faction_ids:
		_active_faction_ids.append(faction_id)

	_faction_districts = data.get("faction_districts", {}).duplicate()
	_faction_factories = data.get("faction_factories", {}).duplicate()
	_faction_units = data.get("faction_units", {}).duplicate()
	_faction_eliminated = data.get("faction_eliminated", {}).duplicate()
	_faction_victory = data.get("faction_victory", {}).duplicate()

	_victory_achieved = data.get("victory_achieved", false)
	_winning_faction_id = data.get("winning_faction_id", -1)
	_victory_type = data.get("victory_type", VictoryType.DISTRICT_DOMINATION)
	_endless_mode_active = data.get("endless_mode_active", false)
	_is_monitoring = data.get("is_monitoring", false)
	_current_check_interval = data.get("current_check_interval", CHECK_INTERVAL_NORMAL)
	_checks_performed = data.get("checks_performed", 0)
