class_name ResearchIntegration
extends RefCounted
## ResearchIntegration connects the research system with other game systems.

signal buff_applied(faction_id: String, buff_id: String)
signal building_unlocked(faction_id: String, building_type: String)
signal unit_unlocked(faction_id: String, unit_type: String)
signal ability_unlocked(faction_id: String, ability_id: String)
signal facility_damaged(facility_id: int, damage: float)
signal facility_power_changed(facility_id: int, powered: bool)
signal integration_error(system: String, error: String)

## Research manager reference
var _research_manager: ResearchManager = null

## External system references (set via callbacks or direct reference)
var _faction_system = null
var _factory_system = null
var _building_system = null
var _ability_system = null
var _power_grid = null
var _destruction_system = null

## Unlock registries (faction_id -> unlocked items)
var _unlocked_buildings: Dictionary = {}
var _unlocked_units: Dictionary = {}
var _unlocked_abilities: Dictionary = {}
var _applied_buffs: Dictionary = {}

## Facility power states (facility_id -> power_state)
var _facility_power_states: Dictionary = {}

## Callbacks for system integration
var _apply_buff_callback: Callable
var _unlock_building_callback: Callable
var _unlock_unit_callback: Callable
var _unlock_ability_callback: Callable
var _register_power_consumer_callback: Callable


func _init() -> void:
	pass


## Set research manager.
func set_research_manager(manager: ResearchManager) -> void:
	_research_manager = manager

	if _research_manager != null:
		_research_manager.research_completed.connect(_on_research_completed)
		_research_manager.technology_unlocked.connect(_on_technology_unlocked)


## Set faction system reference.
func set_faction_system(system) -> void:
	_faction_system = system


## Set factory system reference.
func set_factory_system(system) -> void:
	_factory_system = system


## Set building system reference.
func set_building_system(system) -> void:
	_building_system = system


## Set ability system reference.
func set_ability_system(system) -> void:
	_ability_system = system


## Set power grid reference.
func set_power_grid(grid) -> void:
	_power_grid = grid


## Set destruction system reference.
func set_destruction_system(system) -> void:
	_destruction_system = system


# ============================================
# CALLBACKS
# ============================================

## Set buff application callback.
func set_apply_buff_callback(callback: Callable) -> void:
	_apply_buff_callback = callback


## Set building unlock callback.
func set_unlock_building_callback(callback: Callable) -> void:
	_unlock_building_callback = callback


## Set unit unlock callback.
func set_unlock_unit_callback(callback: Callable) -> void:
	_unlock_unit_callback = callback


## Set ability unlock callback.
func set_unlock_ability_callback(callback: Callable) -> void:
	_unlock_ability_callback = callback


## Set power consumer registration callback.
func set_register_power_consumer_callback(callback: Callable) -> void:
	_register_power_consumer_callback = callback


# ============================================
# TECHNOLOGY COMPLETION HANDLING
# ============================================

## Handle research completed event.
func _on_research_completed(faction_id: String, tech_id: String) -> void:
	var tech := _research_manager.get_technology(tech_id)
	if tech == null:
		return

	# Apply all rewards
	_apply_technology_rewards(faction_id, tech)


## Handle technology unlocked event.
func _on_technology_unlocked(faction_id: String, tech_id: String) -> void:
	# Technology is now available for research
	# Could trigger UI notification
	pass


## Apply all rewards from a completed technology.
func _apply_technology_rewards(faction_id: String, tech: ResearchTechnology) -> void:
	# Apply buffs
	for buff_id in tech.buff_ids:
		_apply_buff(faction_id, buff_id)

	# Unlock buildings
	for building_id in tech.unlock_building_ids:
		_unlock_building(faction_id, building_id)

	# Unlock units
	for unit_id in tech.unlock_unit_ids:
		_unlock_unit(faction_id, unit_id)

	# Unlock abilities
	for ability_id in tech.unlock_ability_ids:
		_unlock_ability(faction_id, ability_id)


# ============================================
# BUFF INTEGRATION
# ============================================

## Apply buff to faction.
func _apply_buff(faction_id: String, buff_id: String) -> void:
	# Track applied buffs
	if not _applied_buffs.has(faction_id):
		_applied_buffs[faction_id] = []

	if _applied_buffs[faction_id].has(buff_id):
		return  # Already applied

	_applied_buffs[faction_id].append(buff_id)

	# Apply via callback or direct reference
	if _apply_buff_callback.is_valid():
		_apply_buff_callback.call(faction_id, buff_id)
	elif _faction_system != null and _faction_system.has_method("apply_buff"):
		_faction_system.apply_buff(faction_id, buff_id)
	else:
		integration_error.emit("faction", "Cannot apply buff - no faction system")
		return

	buff_applied.emit(faction_id, buff_id)


## Get applied buffs for faction.
func get_applied_buffs(faction_id: String) -> Array:
	return _applied_buffs.get(faction_id, [])


# ============================================
# BUILDING UNLOCK INTEGRATION
# ============================================

## Unlock building type for faction.
func _unlock_building(faction_id: String, building_type: String) -> void:
	if not _unlocked_buildings.has(faction_id):
		_unlocked_buildings[faction_id] = []

	if _unlocked_buildings[faction_id].has(building_type):
		return  # Already unlocked

	_unlocked_buildings[faction_id].append(building_type)

	# Unlock via callback or direct reference
	if _unlock_building_callback.is_valid():
		_unlock_building_callback.call(faction_id, building_type)
	elif _building_system != null and _building_system.has_method("unlock_building"):
		_building_system.unlock_building(faction_id, building_type)

	building_unlocked.emit(faction_id, building_type)


## Check if building is unlocked.
func is_building_unlocked(faction_id: String, building_type: String) -> bool:
	return _unlocked_buildings.get(faction_id, []).has(building_type)


## Get unlocked buildings for faction.
func get_unlocked_buildings(faction_id: String) -> Array:
	return _unlocked_buildings.get(faction_id, [])


# ============================================
# UNIT UNLOCK INTEGRATION
# ============================================

## Unlock unit type for faction.
func _unlock_unit(faction_id: String, unit_type: String) -> void:
	if not _unlocked_units.has(faction_id):
		_unlocked_units[faction_id] = []

	if _unlocked_units[faction_id].has(unit_type):
		return  # Already unlocked

	_unlocked_units[faction_id].append(unit_type)

	# Unlock via callback or direct reference
	if _unlock_unit_callback.is_valid():
		_unlock_unit_callback.call(faction_id, unit_type)
	elif _factory_system != null and _factory_system.has_method("unlock_unit"):
		_factory_system.unlock_unit(faction_id, unit_type)

	unit_unlocked.emit(faction_id, unit_type)


## Check if unit is unlocked.
func is_unit_unlocked(faction_id: String, unit_type: String) -> bool:
	return _unlocked_units.get(faction_id, []).has(unit_type)


## Get unlocked units for faction.
func get_unlocked_units(faction_id: String) -> Array:
	return _unlocked_units.get(faction_id, [])


# ============================================
# ABILITY UNLOCK INTEGRATION
# ============================================

## Unlock ability for faction.
func _unlock_ability(faction_id: String, ability_id: String) -> void:
	if not _unlocked_abilities.has(faction_id):
		_unlocked_abilities[faction_id] = []

	if _unlocked_abilities[faction_id].has(ability_id):
		return  # Already unlocked

	_unlocked_abilities[faction_id].append(ability_id)

	# Unlock via callback or direct reference
	if _unlock_ability_callback.is_valid():
		_unlock_ability_callback.call(faction_id, ability_id)
	elif _ability_system != null and _ability_system.has_method("unlock_ability"):
		_ability_system.unlock_ability(faction_id, ability_id)

	ability_unlocked.emit(faction_id, ability_id)


## Check if ability is unlocked.
func is_ability_unlocked(faction_id: String, ability_id: String) -> bool:
	return _unlocked_abilities.get(faction_id, []).has(ability_id)


## Get unlocked abilities for faction.
func get_unlocked_abilities(faction_id: String) -> Array:
	return _unlocked_abilities.get(faction_id, [])


# ============================================
# DESTRUCTION SYSTEM INTEGRATION
# ============================================

## Register facility with destruction system.
func register_facility_for_destruction(facility_id: int) -> void:
	if _destruction_system == null:
		return

	var facility := _research_manager.get_facility(facility_id)
	if facility == null:
		return

	# Register for damage events
	if _destruction_system.has_method("register_target"):
		_destruction_system.register_target(facility_id, "research_facility", facility.position)


## Handle facility damage from destruction system.
func on_facility_damage(facility_id: int, damage: float) -> void:
	var facility := _research_manager.get_facility(facility_id)
	if facility == null:
		return

	facility.take_damage(damage)
	facility_damaged.emit(facility_id, damage)

	if facility.is_destroyed():
		_on_facility_destroyed(facility_id)


## Handle facility destroyed.
func _on_facility_destroyed(facility_id: int) -> void:
	# Unregister from destruction system
	if _destruction_system != null and _destruction_system.has_method("unregister_target"):
		_destruction_system.unregister_target(facility_id)

	# Unregister from power grid
	if _power_grid != null and _power_grid.has_method("unregister_consumer"):
		_power_grid.unregister_consumer(facility_id)


# ============================================
# POWER GRID INTEGRATION
# ============================================

## Register facility with power grid.
func register_facility_for_power(facility_id: int, power_consumption: float = 50.0) -> void:
	if _research_manager == null:
		return

	var facility := _research_manager.get_facility(facility_id)
	if facility == null:
		return

	_facility_power_states[facility_id] = true

	# Register as power consumer
	if _register_power_consumer_callback.is_valid():
		_register_power_consumer_callback.call(facility_id, power_consumption)
	elif _power_grid != null and _power_grid.has_method("register_consumer"):
		_power_grid.register_consumer(facility_id, "research_facility", power_consumption)


## Handle power state change for facility.
func on_facility_power_change(facility_id: int, powered: bool) -> void:
	_facility_power_states[facility_id] = powered

	var facility := _research_manager.get_facility(facility_id)
	if facility == null:
		return

	facility.is_active = powered
	facility_power_changed.emit(facility_id, powered)


## Get facility power state.
func is_facility_powered(facility_id: int) -> bool:
	return _facility_power_states.get(facility_id, true)


# ============================================
# VALIDATION
# ============================================

## Validate all integrations.
func validate_integrations() -> Dictionary:
	var result := {
		"valid": true,
		"warnings": [],
		"errors": []
	}

	if _research_manager == null:
		result["errors"].append("No research manager set")
		result["valid"] = false

	if _faction_system == null and not _apply_buff_callback.is_valid():
		result["warnings"].append("No faction system or buff callback - buffs will not apply")

	if _factory_system == null and not _unlock_unit_callback.is_valid():
		result["warnings"].append("No factory system or unit callback - units will not unlock")

	if _building_system == null and not _unlock_building_callback.is_valid():
		result["warnings"].append("No building system or building callback - buildings will not unlock")

	if _ability_system == null and not _unlock_ability_callback.is_valid():
		result["warnings"].append("No ability system or ability callback - abilities will not unlock")

	if _power_grid == null and not _register_power_consumer_callback.is_valid():
		result["warnings"].append("No power grid - research facilities will not consume power")

	if _destruction_system == null:
		result["warnings"].append("No destruction system - facilities cannot be damaged")

	return result


## Verify technology unlocks were applied correctly.
func verify_technology_unlocks(faction_id: String, tech_id: String) -> Dictionary:
	var result := {
		"verified": true,
		"missing_buffs": [],
		"missing_buildings": [],
		"missing_units": [],
		"missing_abilities": []
	}

	var tech := _research_manager.get_technology(tech_id)
	if tech == null:
		result["verified"] = false
		return result

	# Check buffs
	var applied := get_applied_buffs(faction_id)
	for buff_id in tech.buff_ids:
		if not applied.has(buff_id):
			result["missing_buffs"].append(buff_id)
			result["verified"] = false

	# Check buildings
	var buildings := get_unlocked_buildings(faction_id)
	for building_id in tech.unlock_building_ids:
		if not buildings.has(building_id):
			result["missing_buildings"].append(building_id)
			result["verified"] = false

	# Check units
	var units := get_unlocked_units(faction_id)
	for unit_id in tech.unlock_unit_ids:
		if not units.has(unit_id):
			result["missing_units"].append(unit_id)
			result["verified"] = false

	# Check abilities
	var abilities := get_unlocked_abilities(faction_id)
	for ability_id in tech.unlock_ability_ids:
		if not abilities.has(ability_id):
			result["missing_abilities"].append(ability_id)
			result["verified"] = false

	return result


# ============================================
# SERIALIZATION
# ============================================

func to_dict() -> Dictionary:
	return {
		"unlocked_buildings": _unlocked_buildings.duplicate(true),
		"unlocked_units": _unlocked_units.duplicate(true),
		"unlocked_abilities": _unlocked_abilities.duplicate(true),
		"applied_buffs": _applied_buffs.duplicate(true),
		"facility_power_states": _facility_power_states.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	_unlocked_buildings = data.get("unlocked_buildings", {}).duplicate(true)
	_unlocked_units = data.get("unlocked_units", {}).duplicate(true)
	_unlocked_abilities = data.get("unlocked_abilities", {}).duplicate(true)
	_applied_buffs = data.get("applied_buffs", {}).duplicate(true)
	_facility_power_states = data.get("facility_power_states", {}).duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_buildings := 0
	var total_units := 0
	var total_abilities := 0
	var total_buffs := 0

	for faction_id in _unlocked_buildings:
		total_buildings += _unlocked_buildings[faction_id].size()
	for faction_id in _unlocked_units:
		total_units += _unlocked_units[faction_id].size()
	for faction_id in _unlocked_abilities:
		total_abilities += _unlocked_abilities[faction_id].size()
	for faction_id in _applied_buffs:
		total_buffs += _applied_buffs[faction_id].size()

	return {
		"has_research_manager": _research_manager != null,
		"has_faction_system": _faction_system != null,
		"has_factory_system": _factory_system != null,
		"has_building_system": _building_system != null,
		"has_ability_system": _ability_system != null,
		"has_power_grid": _power_grid != null,
		"has_destruction_system": _destruction_system != null,
		"total_unlocked_buildings": total_buildings,
		"total_unlocked_units": total_units,
		"total_unlocked_abilities": total_abilities,
		"total_applied_buffs": total_buffs,
		"powered_facilities": _facility_power_states.size()
	}
