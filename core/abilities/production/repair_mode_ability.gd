class_name RepairModeAbility
extends RefCounted
## RepairModeAbility enables builder units to prioritize repairing damaged buildings.
## E hotkey, 50 REE cost, 10s cooldown, toggleable duration.

signal repair_mode_started(unit_id: int, target_building_id: int)
signal repair_mode_ended(unit_id: int)
signal repair_completed(unit_id: int, building_id: int)
signal building_repaired(building_id: int, amount: float)

## Configuration
const ABILITY_ID := "repair_mode"
const HOTKEY := "E"
const REE_COST := 50.0
const COOLDOWN := 10.0
const REPAIR_RATE := 5.0  ## HP per second
const REPAIR_RANGE := 15.0
const SEARCH_RADIUS := 50.0

## Active repair assignments (unit_id -> repair_data)
var _active_repairs: Dictionary = {}

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## Callbacks
var _get_unit_position: Callable  ## (unit_id) -> Vector3
var _get_building_health: Callable  ## (building_id) -> Dictionary {current, max}
var _get_nearby_buildings: Callable  ## (position, radius, faction_id) -> Array[int]
var _apply_repair: Callable  ## (building_id, amount) -> void
var _set_unit_target: Callable  ## (unit_id, target_position) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_building_health(callback: Callable) -> void:
	_get_building_health = callback


func set_get_nearby_buildings(callback: Callable) -> void:
	_get_nearby_buildings = callback


func set_apply_repair(callback: Callable) -> void:
	_apply_repair = callback


func set_unit_target(callback: Callable) -> void:
	_set_unit_target = callback


## Check if ability can be activated.
func can_activate() -> Dictionary:
	var result := {
		"can_activate": true,
		"reason": ""
	}

	if _cooldown_remaining > 0:
		result["can_activate"] = false
		result["reason"] = "On cooldown (%.1fs)" % _cooldown_remaining
		return result

	return result


## Activate repair mode for units.
func activate(unit_ids: Array[int], faction_id: String) -> int:
	var validation := can_activate()
	if not validation["can_activate"]:
		return 0

	if unit_ids.is_empty():
		return 0

	var activated_count := 0

	for unit_id in unit_ids:
		if _active_repairs.has(unit_id):
			# Toggle off
			_deactivate_unit(unit_id)
		else:
			# Find nearby damaged building
			var target := _find_repair_target(unit_id, faction_id)
			if target != -1:
				_active_repairs[unit_id] = {
					"target_building": target,
					"faction_id": faction_id,
					"repair_progress": 0.0
				}
				repair_mode_started.emit(unit_id, target)
				activated_count += 1

	if activated_count > 0:
		_cooldown_remaining = COOLDOWN

	return activated_count


## Find nearest damaged building for repair.
func _find_repair_target(unit_id: int, faction_id: String) -> int:
	if not _get_unit_position.is_valid() or not _get_nearby_buildings.is_valid():
		return -1

	var unit_pos: Vector3 = _get_unit_position.call(unit_id)
	var buildings: Array = _get_nearby_buildings.call(unit_pos, SEARCH_RADIUS, faction_id)

	var best_target := -1
	var best_distance := INF
	var best_damage := 0.0

	for building_id in buildings:
		if not _get_building_health.is_valid():
			continue

		var health: Dictionary = _get_building_health.call(building_id)
		var damage: float = health.get("max", 100.0) - health.get("current", 100.0)

		if damage <= 0:
			continue

		var building_pos: Vector3 = health.get("position", Vector3.ZERO)
		var distance := unit_pos.distance_to(building_pos)

		# Prioritize by damage amount and distance
		var priority: float = damage / maxf(1.0, distance)
		if priority > best_damage / maxf(1.0, best_distance):
			best_target = building_id
			best_distance = distance
			best_damage = damage

	return best_target


## Deactivate unit from repair mode.
func _deactivate_unit(unit_id: int) -> void:
	if _active_repairs.has(unit_id):
		_active_repairs.erase(unit_id)
		repair_mode_ended.emit(unit_id)


## Update all repair operations.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update active repairs
	var to_remove: Array[int] = []

	for unit_id in _active_repairs:
		var data: Dictionary = _active_repairs[unit_id]
		var building_id: int = data["target_building"]

		# Check if building still needs repair
		if _get_building_health.is_valid():
			var health: Dictionary = _get_building_health.call(building_id)
			var current: float = health.get("current", 0.0)
			var max_health: float = health.get("max", 100.0)

			if current >= max_health:
				# Building fully repaired, find next target
				repair_completed.emit(unit_id, building_id)
				var new_target := _find_repair_target(unit_id, data["faction_id"])
				if new_target != -1:
					data["target_building"] = new_target
					repair_mode_started.emit(unit_id, new_target)
				else:
					to_remove.append(unit_id)
				continue

			# Check distance to building
			if _get_unit_position.is_valid():
				var unit_pos: Vector3 = _get_unit_position.call(unit_id)
				var building_pos: Vector3 = health.get("position", Vector3.ZERO)
				var distance := unit_pos.distance_to(building_pos)

				if distance <= REPAIR_RANGE:
					# In range, apply repair
					var repair_amount := REPAIR_RATE * delta
					if _apply_repair.is_valid():
						_apply_repair.call(building_id, repair_amount)
						building_repaired.emit(building_id, repair_amount)
				else:
					# Move toward building
					if _set_unit_target.is_valid():
						_set_unit_target.call(unit_id, building_pos)

	# Remove completed units
	for unit_id in to_remove:
		_deactivate_unit(unit_id)


## Cancel repair mode for unit.
func cancel_unit(unit_id: int) -> void:
	_deactivate_unit(unit_id)


## Check if unit is in repair mode.
func is_repairing(unit_id: int) -> bool:
	return _active_repairs.has(unit_id)


## Get repair target for unit.
func get_repair_target(unit_id: int) -> int:
	var data: Dictionary = _active_repairs.get(unit_id, {})
	return data.get("target_building", -1)


## Get active repair count.
func get_active_count() -> int:
	return _active_repairs.size()


## Get cooldown remaining.
func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_remaining)


## Is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"hotkey": HOTKEY,
		"ree_cost": REE_COST,
		"cooldown": COOLDOWN,
		"repair_rate": REPAIR_RATE,
		"repair_range": REPAIR_RANGE,
		"search_radius": SEARCH_RADIUS
	}


## Create AbilityConfig for registration.
func create_ability_config() -> AbilityConfig:
	var config := AbilityConfig.new()
	config.ability_id = ABILITY_ID
	config.faction_id = "human_remnant"  ## Builder faction
	config.display_name = "Repair Mode"
	config.description = "Builder units prioritize repairing nearby damaged buildings"
	config.hotkey = HOTKEY
	config.ability_type = AbilityConfig.AbilityType.INSTANT
	config.target_type = AbilityConfig.TargetType.NONE
	config.cooldown = COOLDOWN
	config.resource_cost = {"ree": REE_COST, "power": 0.0}
	config.execution_params = {
		"repair_rate": REPAIR_RATE,
		"repair_range": REPAIR_RANGE,
		"search_radius": SEARCH_RADIUS
	}
	config.feedback = {
		"visual_effect": "repair_mode",
		"sound_effect": "repair_activate",
		"ui_notification": "Repair Mode activated!"
	}
	return config


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var repairs_data: Dictionary = {}
	for unit_id in _active_repairs:
		var data: Dictionary = _active_repairs[unit_id]
		repairs_data[str(unit_id)] = {
			"target_building": data["target_building"],
			"faction_id": data["faction_id"],
			"repair_progress": data["repair_progress"]
		}

	return {
		"cooldown_remaining": _cooldown_remaining,
		"active_repairs": repairs_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)

	_active_repairs.clear()
	for unit_id_str in data.get("active_repairs", {}):
		var repair_data: Dictionary = data["active_repairs"][unit_id_str]
		_active_repairs[int(unit_id_str)] = {
			"target_building": repair_data["target_building"],
			"faction_id": repair_data["faction_id"],
			"repair_progress": repair_data.get("repair_progress", 0.0)
		}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var repair_summaries: Array[Dictionary] = []
	for unit_id in _active_repairs:
		var data: Dictionary = _active_repairs[unit_id]
		repair_summaries.append({
			"unit": unit_id,
			"target": data["target_building"]
		})

	return {
		"active_repairs": _active_repairs.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"repairs": repair_summaries
	}
