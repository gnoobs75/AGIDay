class_name BlackoutCascade
extends RefCounted
## BlackoutCascade handles cascade effects when power infrastructure is damaged.
## Tracks affected districts and applies production penalties.

signal cascade_started(source_id: int, affected_districts: Array)
signal cascade_propagated(district_id: int, effect_level: float)
signal cascade_resolved(district_id: int)
signal production_penalty_applied(district_id: int, penalty: float)

## Cascade configuration
const PARTIAL_POWER_THRESHOLD := 0.75  ## Below this = partial blackout
const FULL_BLACKOUT_THRESHOLD := 0.5    ## Below this = full blackout (from DistrictPowerState)
const CRITICAL_THRESHOLD := 0.25        ## Below this = critical blackout

## Production penalties by blackout severity
const PARTIAL_PRODUCTION_PENALTY := 0.25   ## 25% production reduction
const FULL_PRODUCTION_PENALTY := 0.75       ## 75% production reduction
const CRITICAL_PRODUCTION_PENALTY := 1.0    ## 100% production halt

## Blackout severity levels
enum BlackoutSeverity {
	NONE,
	PARTIAL,
	FULL,
	CRITICAL
}

## Active cascades (district_id -> cascade_data)
var _active_cascades: Dictionary = {}

## District production penalties (district_id -> penalty 0.0-1.0)
var _production_penalties: Dictionary = {}

## Reference to power grid manager
var _grid_manager: PowerGridManager = null


func _init() -> void:
	pass


## Set grid manager reference.
func set_grid_manager(manager: PowerGridManager) -> void:
	_grid_manager = manager


## Process cascade effects for a destroyed plant.
func on_plant_destroyed(plant_id: int) -> void:
	if _grid_manager == null:
		return

	var plant := _grid_manager.get_plant(plant_id)
	if plant == null:
		return

	var affected_districts: Array[int] = []

	# Find all districts connected through this plant's lines
	for line_id in plant.connected_line_ids:
		var line := _grid_manager.get_line(line_id)
		if line != null:
			affected_districts.append(line.target_district_id)

	if not affected_districts.is_empty():
		_start_cascade(plant_id, affected_districts)


## Process cascade effects for a destroyed line.
func on_line_destroyed(line_id: int) -> void:
	if _grid_manager == null:
		return

	var line := _grid_manager.get_line(line_id)
	if line == null:
		return

	_start_cascade(line_id, [line.target_district_id])


## Start a cascade from infrastructure destruction.
func _start_cascade(source_id: int, affected_districts: Array[int]) -> void:
	cascade_started.emit(source_id, affected_districts)

	for district_id in affected_districts:
		_propagate_to_district(district_id)


## Propagate cascade effects to a district.
func _propagate_to_district(district_id: int) -> void:
	var district := _grid_manager.get_district(district_id)
	if district == null:
		return

	var severity := _calculate_blackout_severity(district)
	var penalty := _get_production_penalty(severity)

	_active_cascades[district_id] = {
		"severity": severity,
		"start_time": Time.get_ticks_msec() / 1000.0,
		"penalty": penalty
	}

	_production_penalties[district_id] = penalty

	var effect_level := 1.0 - district.get_power_ratio()
	cascade_propagated.emit(district_id, effect_level)
	production_penalty_applied.emit(district_id, penalty)


## Calculate blackout severity for a district.
func _calculate_blackout_severity(district: DistrictPowerState) -> int:
	var ratio := district.get_power_ratio()

	if ratio >= PARTIAL_POWER_THRESHOLD:
		return BlackoutSeverity.NONE
	elif ratio >= FULL_BLACKOUT_THRESHOLD:
		return BlackoutSeverity.PARTIAL
	elif ratio >= CRITICAL_THRESHOLD:
		return BlackoutSeverity.FULL
	else:
		return BlackoutSeverity.CRITICAL


## Get production penalty for severity level.
func _get_production_penalty(severity: int) -> float:
	match severity:
		BlackoutSeverity.NONE:
			return 0.0
		BlackoutSeverity.PARTIAL:
			return PARTIAL_PRODUCTION_PENALTY
		BlackoutSeverity.FULL:
			return FULL_PRODUCTION_PENALTY
		BlackoutSeverity.CRITICAL:
			return CRITICAL_PRODUCTION_PENALTY
		_:
			return 0.0


## Update cascade states after power grid changes.
func update_cascades() -> void:
	if _grid_manager == null:
		return

	var resolved: Array[int] = []

	for district_id in _active_cascades:
		var district := _grid_manager.get_district(district_id)
		if district == null:
			resolved.append(district_id)
			continue

		var new_severity := _calculate_blackout_severity(district)
		var old_severity: int = _active_cascades[district_id]["severity"]

		if new_severity == BlackoutSeverity.NONE:
			resolved.append(district_id)
		elif new_severity != old_severity:
			# Update severity and penalty
			var penalty := _get_production_penalty(new_severity)
			_active_cascades[district_id]["severity"] = new_severity
			_active_cascades[district_id]["penalty"] = penalty
			_production_penalties[district_id] = penalty
			production_penalty_applied.emit(district_id, penalty)

	# Resolve completed cascades
	for district_id in resolved:
		_active_cascades.erase(district_id)
		_production_penalties.erase(district_id)
		cascade_resolved.emit(district_id)


## Get production penalty for district.
func get_production_penalty(district_id: int) -> float:
	return _production_penalties.get(district_id, 0.0)


## Get production multiplier for district (1.0 - penalty).
func get_production_multiplier(district_id: int) -> float:
	return 1.0 - get_production_penalty(district_id)


## Get blackout severity for district.
func get_blackout_severity(district_id: int) -> int:
	if not _active_cascades.has(district_id):
		return BlackoutSeverity.NONE
	return _active_cascades[district_id]["severity"]


## Get severity name.
func get_severity_name(severity: int) -> String:
	match severity:
		BlackoutSeverity.NONE:
			return "none"
		BlackoutSeverity.PARTIAL:
			return "partial"
		BlackoutSeverity.FULL:
			return "full"
		BlackoutSeverity.CRITICAL:
			return "critical"
		_:
			return "unknown"


## Check if district is affected by cascade.
func is_district_affected(district_id: int) -> bool:
	return _active_cascades.has(district_id)


## Get all affected districts.
func get_affected_districts() -> Array[int]:
	var districts: Array[int] = []
	for district_id in _active_cascades:
		districts.append(district_id)
	return districts


## Get cascade data for district.
func get_cascade_data(district_id: int) -> Dictionary:
	return _active_cascades.get(district_id, {})


## Serialization.
func to_dict() -> Dictionary:
	var cascades_data: Dictionary = {}
	for district_id in _active_cascades:
		cascades_data[str(district_id)] = _active_cascades[district_id].duplicate()

	var penalties_data: Dictionary = {}
	for district_id in _production_penalties:
		penalties_data[str(district_id)] = _production_penalties[district_id]

	return {
		"active_cascades": cascades_data,
		"production_penalties": penalties_data
	}


func from_dict(data: Dictionary) -> void:
	_active_cascades.clear()
	var cascades_data: Dictionary = data.get("active_cascades", {})
	for district_id_str in cascades_data:
		_active_cascades[int(district_id_str)] = cascades_data[district_id_str].duplicate()

	_production_penalties.clear()
	var penalties_data: Dictionary = data.get("production_penalties", {})
	for district_id_str in penalties_data:
		_production_penalties[int(district_id_str)] = penalties_data[district_id_str]


## Get summary for debugging.
func get_summary() -> Dictionary:
	var severity_counts: Dictionary = {}
	for sev in BlackoutSeverity.values():
		severity_counts[get_severity_name(sev)] = 0

	for district_id in _active_cascades:
		var severity: int = _active_cascades[district_id]["severity"]
		var name := get_severity_name(severity)
		severity_counts[name] += 1

	return {
		"affected_districts": _active_cascades.size(),
		"severity_breakdown": severity_counts,
		"total_production_loss": _calculate_total_production_loss()
	}


func _calculate_total_production_loss() -> float:
	var total := 0.0
	for district_id in _production_penalties:
		total += _production_penalties[district_id]
	return total
