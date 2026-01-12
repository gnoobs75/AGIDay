class_name VictoryMonitor
extends RefCounted
## VictoryMonitor checks victory conditions and manages faction status.
## Uses efficient O(1) operations for status queries.

signal victory_declared(faction_id: String, event: VictoryEvent)
signal defeat_declared(faction_id: String, event: DefeatEvent)
signal game_ended(winner_faction: String, victory_type: int)

## Victory condition
var victory_condition: VictoryCondition = null

## Faction statuses (faction_id -> FactionStatus)
var faction_statuses: Dictionary = {}

## Total districts on map
var total_districts: int = 64

## Game start time
var game_start_time: int = 0

## Current wave number
var current_wave: int = 0

## Whether game has ended
var game_ended_flag: bool = false

## Winning faction
var winner_faction: String = ""

## Victory events
var victory_events: Array[VictoryEvent] = []

## Defeat events
var defeat_events: Array[DefeatEvent] = []


func _init() -> void:
	victory_condition = VictoryCondition.new()


## Initialize monitor.
func initialize(condition: VictoryCondition, factions: Array[String], districts: int = 64) -> void:
	victory_condition = condition
	total_districts = districts
	game_start_time = Time.get_ticks_msec()
	game_ended_flag = false
	winner_faction = ""

	faction_statuses.clear()
	for faction_id in factions:
		faction_statuses[faction_id] = FactionStatus.new(faction_id)

	victory_events.clear()
	defeat_events.clear()


## Register faction.
func register_faction(faction_id: String) -> FactionStatus:
	if not faction_statuses.has(faction_id):
		faction_statuses[faction_id] = FactionStatus.new(faction_id)
	return faction_statuses[faction_id]


## Get faction status (O(1)).
func get_faction_status(faction_id: String) -> FactionStatus:
	return faction_statuses.get(faction_id)


## Update faction factory count (O(1)).
func update_factory_count(faction_id: String, count: int) -> void:
	var status := get_faction_status(faction_id)
	if status != null:
		status.set_factory_count(count)
		_check_victory_conditions()


## Update faction unit count (O(1)).
func update_unit_count(faction_id: String, count: int) -> void:
	var status := get_faction_status(faction_id)
	if status != null:
		status.set_unit_count(count)
		_check_victory_conditions()


## Update faction district control (O(1)).
func update_district_control(faction_id: String, count: int) -> void:
	var status := get_faction_status(faction_id)
	if status != null:
		status.set_districts_controlled(count)
		_check_victory_conditions()


## Set current wave.
func set_current_wave(wave: int) -> void:
	current_wave = wave
	_check_victory_conditions()


## Get game duration in seconds.
func get_game_duration() -> float:
	return float(Time.get_ticks_msec() - game_start_time) / 1000.0


## Check all victory conditions (called after updates).
func _check_victory_conditions() -> void:
	if game_ended_flag and not victory_condition.survival_mode:
		return

	# Check for eliminations first
	_check_eliminations()

	# Check victory for each faction
	for faction_id in faction_statuses:
		var status: FactionStatus = faction_statuses[faction_id]

		if status.is_eliminated or status.has_achieved_victory:
			continue

		# Calculate enemy factory count
		var enemy_factories := _get_enemy_factory_count(faction_id)
		var enemy_factories_destroyed := _get_total_enemy_factories(faction_id) - enemy_factories

		# Check victory condition
		var victory_achieved := victory_condition.check_victory(
			status.districts_controlled,
			total_districts,
			enemy_factories_destroyed,
			_get_total_enemy_factories(faction_id),
			get_game_duration(),
			current_wave
		)

		if victory_achieved:
			_declare_victory(faction_id)


## Check for faction eliminations.
func _check_eliminations() -> void:
	for faction_id in faction_statuses:
		var status: FactionStatus = faction_statuses[faction_id]

		if not status.is_eliminated:
			continue

		# Check if this is a new elimination (defeat event not yet created)
		var already_recorded := false
		for event in defeat_events:
			if event.faction_id == faction_id:
				already_recorded = true
				break

		if not already_recorded:
			var event := DefeatEvent.create(
				status,
				DefeatEvent.Reason.FACTORY_DESTROYED,
				get_game_duration(),
				current_wave
			)
			defeat_events.append(event)
			defeat_declared.emit(faction_id, event)


## Get enemy factory count for faction.
func _get_enemy_factory_count(faction_id: String) -> int:
	var count := 0
	for other_id in faction_statuses:
		if other_id != faction_id:
			var status: FactionStatus = faction_statuses[other_id]
			count += status.factory_count
	return count


## Get total enemy factories (original count).
func _get_total_enemy_factories(faction_id: String) -> int:
	var count := 0
	for other_id in faction_statuses:
		if other_id != faction_id:
			var status: FactionStatus = faction_statuses[other_id]
			count += status.factory_count + status.factories_destroyed
	return count


## Declare victory for faction.
func _declare_victory(faction_id: String) -> void:
	var status := get_faction_status(faction_id)
	if status == null:
		return

	status.set_victory(victory_condition.victory_type, current_wave)

	var event := VictoryEvent.create(
		status,
		victory_condition.victory_type,
		get_game_duration(),
		current_wave
	)

	# Record defeated opponents
	for other_id in faction_statuses:
		if other_id != faction_id:
			var other_status: FactionStatus = faction_statuses[other_id]
			if other_status.is_eliminated:
				event.opponents_defeated.append(other_id)

	victory_events.append(event)
	victory_declared.emit(faction_id, event)

	if not game_ended_flag:
		game_ended_flag = true
		winner_faction = faction_id
		game_ended.emit(faction_id, victory_condition.victory_type)


## Check if game has ended.
func is_game_ended() -> bool:
	return game_ended_flag


## Get active factions (not eliminated).
func get_active_factions() -> Array[String]:
	var active: Array[String] = []
	for faction_id in faction_statuses:
		var status: FactionStatus = faction_statuses[faction_id]
		if not status.is_eliminated:
			active.append(faction_id)
	return active


## Get leading faction (most districts).
func get_leading_faction() -> String:
	var leader := ""
	var max_districts := -1

	for faction_id in faction_statuses:
		var status: FactionStatus = faction_statuses[faction_id]
		if not status.is_eliminated and status.districts_controlled > max_districts:
			max_districts = status.districts_controlled
			leader = faction_id

	return leader


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var statuses_data: Dictionary = {}
	for faction_id in faction_statuses:
		statuses_data[faction_id] = faction_statuses[faction_id].to_dict()

	var victory_data: Array = []
	for event in victory_events:
		victory_data.append(event.to_dict())

	var defeat_data: Array = []
	for event in defeat_events:
		defeat_data.append(event.to_dict())

	return {
		"victory_condition": victory_condition.to_dict(),
		"faction_statuses": statuses_data,
		"total_districts": total_districts,
		"game_start_time": game_start_time,
		"current_wave": current_wave,
		"game_ended_flag": game_ended_flag,
		"winner_faction": winner_faction,
		"victory_events": victory_data,
		"defeat_events": defeat_data
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> VictoryMonitor:
	var monitor := VictoryMonitor.new()
	monitor.victory_condition = VictoryCondition.from_dict(data.get("victory_condition", {}))
	monitor.total_districts = data.get("total_districts", 64)
	monitor.game_start_time = data.get("game_start_time", 0)
	monitor.current_wave = data.get("current_wave", 0)
	monitor.game_ended_flag = data.get("game_ended_flag", false)
	monitor.winner_faction = data.get("winner_faction", "")

	monitor.faction_statuses.clear()
	for faction_id in data.get("faction_statuses", {}):
		monitor.faction_statuses[faction_id] = FactionStatus.from_dict(data["faction_statuses"][faction_id])

	monitor.victory_events.clear()
	for event_data in data.get("victory_events", []):
		monitor.victory_events.append(VictoryEvent.from_dict(event_data))

	monitor.defeat_events.clear()
	for event_data in data.get("defeat_events", []):
		monitor.defeat_events.append(DefeatEvent.from_dict(event_data))

	return monitor


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_summaries: Dictionary = {}
	for faction_id in faction_statuses:
		faction_summaries[faction_id] = faction_statuses[faction_id].get_summary()

	return {
		"game_ended": game_ended_flag,
		"winner": winner_faction if not winner_faction.is_empty() else "none",
		"duration": "%.1fs" % get_game_duration(),
		"wave": current_wave,
		"condition": victory_condition.get_type_name(),
		"factions": faction_summaries
	}
