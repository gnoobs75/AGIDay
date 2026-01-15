class_name DistrictControlSystem
extends RefCounted
## DistrictControlSystem manages territorial control with tick-based passive income.
## Handles starting district assignment and capture mechanics.

signal income_tick(faction_id: String, ree: float, power: float)
signal district_captured(district_id: int, old_faction: String, new_faction: String)
signal starting_districts_assigned(faction_count: int)

## Income generation interval
const INCOME_TICK_INTERVAL := 1.0  ## 1 second

## Base income per district per tick
const BASE_REE_PER_DISTRICT := 10.0
const BASE_POWER_PER_DISTRICT := 50.0

## Starting positions for factions (corners)
const FACTION_STARTING_POSITIONS := {
	"aether_swarm": Vector3i(0, 0, 0),        ## Top-left
	"optiforge": Vector3i(448, 0, 0),         ## Top-right
	"dynapods": Vector3i(0, 0, 448),          ## Bottom-left
	"logibots": Vector3i(448, 0, 448)         ## Bottom-right
}

## District manager reference
var _district_manager: DistrictZoneManager = null

## Resource system callbacks
var _add_ree_callback: Callable = Callable()
var _add_power_callback: Callable = Callable()

## Timing
var _income_timer: float = 0.0
var _is_paused: bool = false

## Active factions
var _active_factions: Array[String] = []


func _init() -> void:
	pass


## Initialize with district manager.
func initialize(district_manager: DistrictZoneManager) -> void:
	_district_manager = district_manager
	_district_manager.district_captured.connect(_on_district_captured)


## Set resource callbacks.
func set_resource_callbacks(add_ree: Callable, add_power: Callable) -> void:
	_add_ree_callback = add_ree
	_add_power_callback = add_power


## Assign starting districts to factions.
func assign_starting_districts(faction_ids: Array[String]) -> void:
	_active_factions = faction_ids.duplicate()

	var faction_positions := ["aether_swarm", "optiforge", "dynapods", "logibots"]

	for i in faction_ids.size():
		var faction_id: String = faction_ids[i]

		# Get starting position (map faction to corner)
		var corner := i % 4
		var corner_faction: String = faction_positions[corner]
		var position: Vector3i = FACTION_STARTING_POSITIONS.get(corner_faction, Vector3i.ZERO)

		# Create starting district
		var name := "%s_start" % faction_id
		var district: DistrictZone = _district_manager.create_corner_district(name, corner, faction_id)

		# Ensure district is powered and generating
		district.set_power_state(true, district.power_consumption)

	starting_districts_assigned.emit(faction_ids.size())


## Update system (call every frame).
func update(delta: float) -> void:
	if _is_paused:
		return

	_income_timer += delta

	if _income_timer >= INCOME_TICK_INTERVAL:
		_income_timer -= INCOME_TICK_INTERVAL
		_generate_income_tick()


## Generate income tick for all factions.
func _generate_income_tick() -> void:
	for faction_id in _active_factions:
		var districts: Array[DistrictZone] = _district_manager.get_faction_districts(faction_id)
		if districts.is_empty():
			continue

		var total_ree := 0.0
		var total_power := 0.0

		for district in districts:
			# Only generate if district has power and isn't contested
			var multiplier: float = district.get_income_multiplier()

			total_ree += BASE_REE_PER_DISTRICT * multiplier
			total_power += BASE_POWER_PER_DISTRICT * multiplier

			# Add district-specific bonuses
			total_ree += district.ree_generation_rate * multiplier / INCOME_TICK_INTERVAL
			total_power += district.power_generation_rate * multiplier / INCOME_TICK_INTERVAL

		# Apply to resource system
		if _add_ree_callback.is_valid() and total_ree > 0:
			_add_ree_callback.call(faction_id, total_ree)

		if _add_power_callback.is_valid() and total_power > 0:
			_add_power_callback.call(faction_id, total_power)

		income_tick.emit(faction_id, total_ree, total_power)


## Set paused state.
func set_paused(paused: bool) -> void:
	_is_paused = paused


## Attempt to capture district.
func attempt_capture(district_id: int, attacking_faction: String) -> bool:
	var district := _district_manager.get_district(district_id)
	if district == null:
		return false

	# Check capture conditions
	if district.check_capture_conditions(attacking_faction):
		_district_manager.capture_district(district_id, attacking_faction)
		return true

	return false


## Get income breakdown for faction.
func get_faction_income_breakdown(faction_id: String) -> Dictionary:
	var districts: Array[DistrictZone] = _district_manager.get_faction_districts(faction_id)

	var breakdown := {
		"district_count": districts.size(),
		"base_ree": districts.size() * BASE_REE_PER_DISTRICT,
		"base_power": districts.size() * BASE_POWER_PER_DISTRICT,
		"bonus_ree": 0.0,
		"bonus_power": 0.0,
		"contested_reduction": 0.0
	}

	for district in districts:
		var multiplier: float = district.get_income_multiplier()

		if multiplier < 1.0:
			breakdown["contested_reduction"] += BASE_REE_PER_DISTRICT * (1.0 - multiplier)

		breakdown["bonus_ree"] += district.ree_generation_rate
		breakdown["bonus_power"] += district.power_generation_rate

	breakdown["total_ree"] = breakdown["base_ree"] + breakdown["bonus_ree"] - breakdown["contested_reduction"]
	breakdown["total_power"] = breakdown["base_power"] + breakdown["bonus_power"]

	return breakdown


## Get districts available for capture by faction.
func get_capturable_districts(faction_id: String) -> Array[DistrictZone]:
	var capturable: Array[DistrictZone] = []

	for district_id in range(1, _district_manager._next_district_id):
		var district := _district_manager.get_district(district_id)
		if district == null:
			continue

		if district.owning_faction != faction_id:
			if district.check_capture_conditions(faction_id):
				capturable.append(district)

	return capturable


## Handle district captured signal.
func _on_district_captured(district_id: int, old_faction: String, new_faction: String) -> void:
	# Add new faction to active list if not present
	if not new_faction.is_empty() and not _active_factions.has(new_faction):
		_active_factions.append(new_faction)

	district_captured.emit(district_id, old_faction, new_faction)


## Get statistics.
func get_statistics() -> Dictionary:
	var faction_districts: Dictionary = {}

	for faction_id in _active_factions:
		faction_districts[faction_id] = _district_manager.get_faction_districts(faction_id).size()

	return {
		"active_factions": _active_factions.size(),
		"faction_districts": faction_districts,
		"income_interval": INCOME_TICK_INTERVAL,
		"base_ree_per_district": BASE_REE_PER_DISTRICT,
		"base_power_per_district": BASE_POWER_PER_DISTRICT,
		"is_paused": _is_paused
	}
