class_name DistrictIntegration
extends RefCounted
## DistrictIntegration connects district system with power, pathfinding, fog, resources, and research.
## Provides cohesive gameplay through district control mechanics.

signal power_grid_updated(districts_powered: int, districts_blacked_out: int)
signal district_visibility_changed(district_id: int, visible_to: Array[String])
signal resource_bonus_changed(district_id: int, bonus_type: String, value: float)
signal unit_district_changed(unit_id: int, old_district: int, new_district: int)

## Power chain blackout settings
const BLACKOUT_CHAIN_DELAY := 0.5  ## Seconds between chain blackouts
const POWER_TRANSMISSION_RANGE := 100.0

## Pathfinding preference weights
const FRIENDLY_DISTRICT_WEIGHT := 0.8   ## Prefer friendly districts
const ENEMY_DISTRICT_WEIGHT := 1.5      ## Avoid enemy districts
const NEUTRAL_DISTRICT_WEIGHT := 1.0

## REE destruction bonus
const REE_DISTRICT_DESTRUCTION_BONUS := 1.5

## Research acceleration
const RESEARCH_DISTRICT_BONUS := 0.2  ## 20% faster research per research district

## System references
var _district_manager: DistrictManager = null
var _power_system = null  ## Power grid system
var _pathfinding_system = null  ## Navigation system
var _fog_system = null  ## Fog of war system
var _resource_system = null  ## Resource management
var _research_system = null  ## Research/tech tree

## Unit-district tracking
var _unit_districts: Dictionary = {}  ## unit_id -> district_id

## District visibility per faction
var _district_visibility: Dictionary = {}  ## district_id -> Array[faction_id]

## Power grid connections
var _power_connections: Dictionary = {}  ## district_id -> Array[district_id]

## Pending blackout chain
var _blackout_queue: Array[int] = []
var _blackout_timer: float = 0.0


func _init() -> void:
	pass


## Initialize with district manager.
func initialize(district_manager: DistrictManager) -> void:
	_district_manager = district_manager

	# Connect to district signals
	_district_manager.district_captured.connect(_on_district_captured)


## Set system references.
func set_power_system(system) -> void:
	_power_system = system


func set_pathfinding_system(system) -> void:
	_pathfinding_system = system


func set_fog_system(system) -> void:
	_fog_system = system


func set_resource_system(system) -> void:
	_resource_system = system


func set_research_system(system) -> void:
	_research_system = system


## Update integration systems (call every frame).
func update(delta: float) -> void:
	# Process blackout chain
	if not _blackout_queue.is_empty():
		_blackout_timer += delta
		if _blackout_timer >= BLACKOUT_CHAIN_DELAY:
			_blackout_timer = 0.0
			_process_blackout_chain()


## POWER GRID INTEGRATION

## Connect district to power grid.
func connect_district_power(district_id: int, connected_districts: Array[int]) -> void:
	_power_connections[district_id] = connected_districts


## Handle power plant destruction.
func on_power_plant_destroyed(district_id: int) -> void:
	var district := _district_manager.get_district(district_id)
	if district == null:
		return

	# Trigger chain blackout
	district.set_power_state(false, 0.0)
	_trigger_chain_blackout(district_id)


## Trigger chain blackout from district.
func _trigger_chain_blackout(source_district_id: int) -> void:
	if not _power_connections.has(source_district_id):
		return

	for connected_id in _power_connections[source_district_id]:
		if not _blackout_queue.has(connected_id):
			var district := _district_manager.get_district(connected_id)
			if district != null and district.has_power:
				_blackout_queue.append(connected_id)


## Process blackout chain.
func _process_blackout_chain() -> void:
	if _blackout_queue.is_empty():
		return

	var district_id: int = _blackout_queue.pop_front()
	var district := _district_manager.get_district(district_id)

	if district != null and district.has_power:
		# Check if district has its own power
		if district.power_generation_rate <= 0:
			district.set_power_state(false, 0.0)
			# Chain to connected districts
			_trigger_chain_blackout(district_id)


## Update power distribution.
func update_power_distribution() -> void:
	var powered := 0
	var blacked_out := 0

	for district_id in range(1, _district_manager._next_district_id):
		var district := _district_manager.get_district(district_id)
		if district == null:
			continue

		if district.has_power:
			powered += 1
		else:
			blacked_out += 1

	power_grid_updated.emit(powered, blacked_out)


## PATHFINDING INTEGRATION

## Get pathfinding weight for district.
func get_district_pathfinding_weight(district_id: int, faction_id: String) -> float:
	var district := _district_manager.get_district(district_id)
	if district == null:
		return NEUTRAL_DISTRICT_WEIGHT

	if district.owning_faction == faction_id:
		return FRIENDLY_DISTRICT_WEIGHT
	elif district.owning_faction.is_empty():
		return NEUTRAL_DISTRICT_WEIGHT
	else:
		return ENEMY_DISTRICT_WEIGHT


## Get path cost modifier for position.
func get_path_cost_modifier(position: Vector3, faction_id: String) -> float:
	var district := _district_manager.get_district_at_position(position)
	if district == null:
		return 1.0

	return get_district_pathfinding_weight(district.district_id, faction_id)


## Register pathfinding callback.
func register_pathfinding_cost_callback() -> Callable:
	return get_path_cost_modifier


## FOG OF WAR INTEGRATION

## Update district visibility for faction.
func update_district_visibility(faction_id: String, visible_districts: Array[int]) -> void:
	for district_id in visible_districts:
		if not _district_visibility.has(district_id):
			_district_visibility[district_id] = []

		if not _district_visibility[district_id].has(faction_id):
			_district_visibility[district_id].append(faction_id)
			district_visibility_changed.emit(district_id, _district_visibility[district_id])


## Check if district is visible to faction.
func is_district_visible(district_id: int, faction_id: String) -> bool:
	if not _district_visibility.has(district_id):
		return false
	return _district_visibility[district_id].has(faction_id)


## Get visibility status for district.
func get_district_visibility_status(district_id: int, faction_id: String) -> String:
	var district := _district_manager.get_district(district_id)
	if district == null:
		return "unknown"

	if is_district_visible(district_id, faction_id):
		return "visible"
	elif _district_visibility.has(district_id):
		return "explored"
	else:
		return "unknown"


## Reveal district to faction (via unit or ability).
func reveal_district(district_id: int, faction_id: String) -> void:
	update_district_visibility(faction_id, [district_id])


## RESOURCE NODE INTEGRATION

## Get REE destruction bonus for district.
func get_destruction_ree_bonus(district_id: int) -> float:
	var district := _district_manager.get_district(district_id)
	if district == null:
		return 1.0

	# REE districts (edge type) give bonus
	if district.district_type == District.DistrictType.EDGE:
		return REE_DISTRICT_DESTRUCTION_BONUS

	return 1.0


## Handle building destroyed in district.
func on_building_destroyed(position: Vector3, base_ree: float) -> float:
	var district := _district_manager.get_district_at_position(position)
	if district == null:
		return base_ree

	var bonus := get_destruction_ree_bonus(district.district_id)
	var total_ree := base_ree * bonus

	resource_bonus_changed.emit(district.district_id, "destruction_ree", bonus)

	return total_ree


## RESEARCH INTEGRATION

## Get research acceleration for faction.
func get_research_acceleration(faction_id: String) -> float:
	var acceleration := 1.0
	var districts := _district_manager.get_faction_districts(faction_id)

	for district in districts:
		# Center districts (research) provide bonus
		if district.district_type == District.DistrictType.CENTER:
			acceleration += RESEARCH_DISTRICT_BONUS

	return acceleration


## Apply research bonus.
func apply_research_bonus(faction_id: String, base_research: float) -> float:
	var acceleration := get_research_acceleration(faction_id)
	return base_research * acceleration


## UNIT-DISTRICT TRACKING

## Update unit district.
func update_unit_district(unit_id: int, position: Vector3) -> void:
	var district := _district_manager.get_district_at_position(position)
	var new_district_id := district.district_id if district != null else -1

	var old_district_id: int = _unit_districts.get(unit_id, -1)

	if old_district_id != new_district_id:
		_unit_districts[unit_id] = new_district_id
		unit_district_changed.emit(unit_id, old_district_id, new_district_id)

		# Update district unit counts
		if old_district_id > 0:
			var old_d := _district_manager.get_district(old_district_id)
			if old_d != null:
				# Would need faction info to update properly
				pass

		if new_district_id > 0:
			# Reveal district to unit's faction
			# Would need faction info
			pass


## Get unit's current district.
func get_unit_district(unit_id: int) -> int:
	return _unit_districts.get(unit_id, -1)


## Remove unit from tracking.
func remove_unit(unit_id: int) -> void:
	_unit_districts.erase(unit_id)


## EVENT HANDLERS

## Handle district captured.
func _on_district_captured(district_id: int, old_faction: String, new_faction: String) -> void:
	# Update power grid
	update_power_distribution()

	# Update fog of war - capturing faction now sees district
	if not new_faction.is_empty():
		reveal_district(district_id, new_faction)

	# Update research bonuses
	if _research_system != null:
		# Would call research system update
		pass


## Get integration statistics.
func get_statistics() -> Dictionary:
	return {
		"tracked_units": _unit_districts.size(),
		"visible_districts": _district_visibility.size(),
		"power_connections": _power_connections.size(),
		"pending_blackouts": _blackout_queue.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"unit_districts": _unit_districts.duplicate(),
		"district_visibility": _district_visibility.duplicate(true),
		"power_connections": _power_connections.duplicate(true),
		"blackout_queue": _blackout_queue.duplicate(),
		"blackout_timer": _blackout_timer
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_districts = data.get("unit_districts", {}).duplicate()
	_district_visibility = data.get("district_visibility", {}).duplicate(true)
	_power_connections = data.get("power_connections", {}).duplicate(true)
	_blackout_queue = data.get("blackout_queue", []).duplicate()
	_blackout_timer = data.get("blackout_timer", 0.0)
