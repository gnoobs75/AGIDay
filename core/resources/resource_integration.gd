class_name ResourceIntegration
extends RefCounted
## ResourceIntegration connects Resource Management with districts, factions, and factories.
## Manages passive income, economic scaling, and cross-system resource coordination.

signal district_income_updated(faction_id: int, district_count: int, income_rate: float)
signal production_validated(faction_id: int, unit_type: String, can_produce: bool)
signal resource_deducted(faction_id: int, unit_type: String, cost: float)
signal economic_metrics_updated(faction_id: int, metrics: Dictionary)
signal scaling_applied(new_multiplier: float)
signal power_status_changed(faction_id: int, has_power: bool, production_modifier: float)

## Base income per district per tick
const BASE_REE_PER_DISTRICT := 10.0
const BASE_POWER_PER_DISTRICT := 50.0
const TICK_INTERVAL := 1.0  ## Seconds between income ticks

## Economic scaling over match duration
const SCALING_START_TIME := 0.0            ## Start at 1.0x
const SCALING_END_TIME := 1800.0           ## 30 minutes
const SCALING_MIN := 1.0
const SCALING_MAX := 1.5

## Blackout production penalty
const BLACKOUT_PRODUCTION_MODIFIER := 0.5  ## 50% production during blackout

## Unit production costs (default values)
const DEFAULT_UNIT_COSTS := {
	# Aether Swarm
	"drone": 50.0,
	"swarmling": 30.0,
	"nanite_cloud": 100.0,
	"hive_node": 200.0,
	# OptiForge Legion
	"grunt": 40.0,
	"optimizer": 80.0,
	"forge_walker": 150.0,
	# Dynapods Vanguard
	"leaper": 60.0,
	"dynaquad": 120.0,
	"behemoth": 300.0,
	# LogiBots Colossus
	"bulkripper": 70.0,
	"haulforge": 90.0,
	"crushkin": 100.0,
	"titanclad": 400.0,
	# Generic
	"harvester": 80.0,
	"turret": 150.0,
	"factory": 500.0
}

## State tracking
var _faction_district_counts: Dictionary = {}   ## faction_id -> district count
var _faction_income_rates: Dictionary = {}      ## faction_id -> REE/sec
var _faction_power_income: Dictionary = {}      ## faction_id -> Power/sec
var _faction_has_power: Dictionary = {}         ## faction_id -> bool
var _faction_buffs: Dictionary = {}             ## faction_id -> buff data

## Economic metrics per faction
var _faction_metrics: Dictionary = {}           ## faction_id -> EconomicMetrics

## Match state
var _match_duration: float = 0.0
var _current_scaling: float = 1.0
var _tick_timer: float = 0.0

## Custom unit costs (can override defaults)
var _unit_costs: Dictionary = {}

## Resource manager reference (optional)
var _resource_manager = null


func _init() -> void:
	_unit_costs = DEFAULT_UNIT_COSTS.duplicate()


## Set resource manager reference for direct integration.
func set_resource_manager(manager) -> void:
	_resource_manager = manager


## Initialize faction tracking.
func initialize_faction(faction_id: int) -> void:
	_faction_district_counts[faction_id] = 0
	_faction_income_rates[faction_id] = 0.0
	_faction_power_income[faction_id] = 0.0
	_faction_has_power[faction_id] = true
	_faction_buffs[faction_id] = {
		"income_multiplier": 1.0,
		"production_multiplier": 1.0
	}

	_faction_metrics[faction_id] = EconomicMetrics.new()


## Update (call every frame).
func update(delta: float) -> void:
	_match_duration += delta
	_update_scaling()

	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_process_income_tick()


## Update economic scaling based on match duration.
func _update_scaling() -> void:
	if _match_duration <= SCALING_START_TIME:
		_current_scaling = SCALING_MIN
	elif _match_duration >= SCALING_END_TIME:
		_current_scaling = SCALING_MAX
	else:
		var progress := (_match_duration - SCALING_START_TIME) / (SCALING_END_TIME - SCALING_START_TIME)
		_current_scaling = lerpf(SCALING_MIN, SCALING_MAX, progress)


## Process income tick for all factions.
func _process_income_tick() -> void:
	for faction_id in _faction_district_counts:
		var district_count: int = _faction_district_counts[faction_id]
		if district_count <= 0:
			continue

		var base_ree := district_count * BASE_REE_PER_DISTRICT
		var base_power := district_count * BASE_POWER_PER_DISTRICT

		# Apply faction buffs
		var buff_data: Dictionary = _faction_buffs.get(faction_id, {})
		var income_multiplier: float = buff_data.get("income_multiplier", 1.0)

		# Apply match duration scaling
		var scaled_ree := base_ree * income_multiplier * _current_scaling
		var scaled_power := base_power * income_multiplier * _current_scaling

		# Store rates
		_faction_income_rates[faction_id] = scaled_ree
		_faction_power_income[faction_id] = scaled_power

		# Apply to resource manager if connected
		if _resource_manager != null:
			_resource_manager.add_ree(faction_id, scaled_ree, "district_income")

		# Update metrics
		var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
		if metrics != null:
			metrics.total_generated += scaled_ree
			metrics.tick_count += 1


# ============================================
# DISTRICT INTEGRATION
# ============================================

## Handle district captured event.
func on_district_captured(faction_id: int, district_id: int) -> void:
	if not _faction_district_counts.has(faction_id):
		initialize_faction(faction_id)

	_faction_district_counts[faction_id] += 1
	_recalculate_income_rate(faction_id)

	# Update metrics
	var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
	if metrics != null:
		metrics.districts_captured += 1


## Handle district lost event.
func on_district_lost(faction_id: int, district_id: int) -> void:
	if not _faction_district_counts.has(faction_id):
		return

	_faction_district_counts[faction_id] = maxi(0, _faction_district_counts[faction_id] - 1)
	_recalculate_income_rate(faction_id)

	# Update metrics
	var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
	if metrics != null:
		metrics.districts_lost += 1


## Set district count directly (batch update).
func set_district_count(faction_id: int, count: int) -> void:
	if not _faction_district_counts.has(faction_id):
		initialize_faction(faction_id)

	_faction_district_counts[faction_id] = count
	_recalculate_income_rate(faction_id)


## Recalculate income rate for faction.
func _recalculate_income_rate(faction_id: int) -> void:
	var district_count: int = _faction_district_counts.get(faction_id, 0)
	var buff_data: Dictionary = _faction_buffs.get(faction_id, {})
	var income_multiplier: float = buff_data.get("income_multiplier", 1.0)

	var income_rate := district_count * BASE_REE_PER_DISTRICT * income_multiplier * _current_scaling
	_faction_income_rates[faction_id] = income_rate

	district_income_updated.emit(faction_id, district_count, income_rate)


# ============================================
# FACTION BUFF INTEGRATION
# ============================================

## Apply faction experience buff to income.
func apply_faction_income_buff(faction_id: int, multiplier: float) -> void:
	if not _faction_buffs.has(faction_id):
		_faction_buffs[faction_id] = {}

	_faction_buffs[faction_id]["income_multiplier"] = multiplier
	_recalculate_income_rate(faction_id)


## Apply faction production speed buff.
func apply_faction_production_buff(faction_id: int, multiplier: float) -> void:
	if not _faction_buffs.has(faction_id):
		_faction_buffs[faction_id] = {}

	_faction_buffs[faction_id]["production_multiplier"] = multiplier


## Get production speed modifier for faction.
func get_production_modifier(faction_id: int) -> float:
	var base_multiplier: float = _faction_buffs.get(faction_id, {}).get("production_multiplier", 1.0)

	# Apply blackout penalty if no power
	if not _faction_has_power.get(faction_id, true):
		base_multiplier *= BLACKOUT_PRODUCTION_MODIFIER

	return base_multiplier


# ============================================
# FACTORY PRODUCTION INTEGRATION
# ============================================

## Validate if faction can afford to produce unit.
func validate_production(faction_id: int, unit_type: String) -> bool:
	var cost := get_unit_cost(unit_type)
	if cost <= 0:
		production_validated.emit(faction_id, unit_type, false)
		return false

	var can_afford := false

	if _resource_manager != null:
		can_afford = _resource_manager.can_afford(faction_id, cost)
	else:
		# Default to true if no manager connected
		can_afford = true

	production_validated.emit(faction_id, unit_type, can_afford)
	return can_afford


## Deduct resources for unit production (atomic operation).
func deduct_production_cost(faction_id: int, unit_type: String) -> bool:
	var cost := get_unit_cost(unit_type)
	if cost <= 0:
		return false

	var success := false

	if _resource_manager != null:
		success = _resource_manager.consume_ree(faction_id, cost, "production:" + unit_type)
	else:
		# Default to true if no manager connected
		success = true

	if success:
		resource_deducted.emit(faction_id, unit_type, cost)

		# Update metrics
		var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
		if metrics != null:
			metrics.total_spent += cost
			metrics.units_produced += 1

	return success


## Get unit production cost.
func get_unit_cost(unit_type: String) -> float:
	return _unit_costs.get(unit_type, 0.0)


## Set custom unit cost.
func set_unit_cost(unit_type: String, cost: float) -> void:
	_unit_costs[unit_type] = cost


## Set all unit costs.
func set_all_unit_costs(costs: Dictionary) -> void:
	_unit_costs = costs.duplicate()


# ============================================
# POWER GRID INTEGRATION
# ============================================

## Handle power status change for faction.
func on_power_status_changed(faction_id: int, has_power: bool) -> void:
	var previous_status: bool = _faction_has_power.get(faction_id, true)
	_faction_has_power[faction_id] = has_power

	if previous_status != has_power:
		var production_modifier := 1.0 if has_power else BLACKOUT_PRODUCTION_MODIFIER
		power_status_changed.emit(faction_id, has_power, production_modifier)

		# Update metrics
		var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
		if metrics != null:
			if not has_power:
				metrics.blackout_count += 1


## Check if faction has power.
func has_power(faction_id: int) -> bool:
	return _faction_has_power.get(faction_id, true)


# ============================================
# HARVESTING INTEGRATION
# ============================================

## Handle harvesting completion event.
func on_harvesting_completed(faction_id: int, ree_amount: float, source: String) -> void:
	if _resource_manager != null:
		_resource_manager.add_ree(faction_id, ree_amount, "harvesting:" + source)

	# Update metrics
	var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
	if metrics != null:
		metrics.total_generated += ree_amount
		metrics.harvesting_income += ree_amount


# ============================================
# ECONOMIC METRICS
# ============================================

## Get economic metrics for faction.
func get_economic_metrics(faction_id: int) -> Dictionary:
	var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
	if metrics == null:
		return {}

	return metrics.to_dict()


## Get income vs consumption rate.
func get_income_consumption_ratio(faction_id: int) -> float:
	var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
	if metrics == null or metrics.total_spent <= 0:
		return 1.0

	return metrics.total_generated / metrics.total_spent


## Get economic performance score.
func get_economic_score(faction_id: int) -> float:
	var metrics: EconomicMetrics = _faction_metrics.get(faction_id)
	if metrics == null:
		return 0.0

	var district_count: int = _faction_district_counts.get(faction_id, 0)
	var income_rate: float = _faction_income_rates.get(faction_id, 0.0)

	# Score based on districts, income, and efficiency
	var score := 0.0
	score += district_count * 100.0
	score += income_rate * 10.0
	score += metrics.units_produced * 5.0
	score -= metrics.blackout_count * 50.0

	return maxf(0.0, score)


# ============================================
# QUERY METHODS
# ============================================

## Get current district count for faction.
func get_district_count(faction_id: int) -> int:
	return _faction_district_counts.get(faction_id, 0)


## Get current income rate for faction.
func get_income_rate(faction_id: int) -> float:
	return _faction_income_rates.get(faction_id, 0.0)


## Get power income rate for faction.
func get_power_income_rate(faction_id: int) -> float:
	return _faction_power_income.get(faction_id, 0.0)


## Get current economic scaling multiplier.
func get_current_scaling() -> float:
	return _current_scaling


## Get match duration.
func get_match_duration() -> float:
	return _match_duration


## Get statistics.
func get_statistics() -> Dictionary:
	var faction_data := {}
	for faction_id in _faction_district_counts:
		faction_data[faction_id] = {
			"districts": _faction_district_counts.get(faction_id, 0),
			"income_rate": _faction_income_rates.get(faction_id, 0.0),
			"power_rate": _faction_power_income.get(faction_id, 0.0),
			"has_power": _faction_has_power.get(faction_id, true),
			"production_modifier": get_production_modifier(faction_id)
		}

	return {
		"match_duration": _match_duration,
		"current_scaling": _current_scaling,
		"faction_count": _faction_district_counts.size(),
		"factions": faction_data
	}


# ============================================
# SERIALIZATION
# ============================================

## Serialize to dictionary.
func to_dict() -> Dictionary:
	var metrics_data := {}
	for faction_id in _faction_metrics:
		var m: EconomicMetrics = _faction_metrics[faction_id]
		metrics_data[str(faction_id)] = m.to_dict()

	return {
		"faction_district_counts": _faction_district_counts.duplicate(),
		"faction_income_rates": _faction_income_rates.duplicate(),
		"faction_power_income": _faction_power_income.duplicate(),
		"faction_has_power": _faction_has_power.duplicate(),
		"faction_buffs": _faction_buffs.duplicate(true),
		"faction_metrics": metrics_data,
		"match_duration": _match_duration,
		"current_scaling": _current_scaling,
		"unit_costs": _unit_costs.duplicate()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_faction_district_counts = data.get("faction_district_counts", {}).duplicate()
	_faction_income_rates = data.get("faction_income_rates", {}).duplicate()
	_faction_power_income = data.get("faction_power_income", {}).duplicate()
	_faction_has_power = data.get("faction_has_power", {}).duplicate()
	_faction_buffs = data.get("faction_buffs", {}).duplicate(true)
	_match_duration = data.get("match_duration", 0.0)
	_current_scaling = data.get("current_scaling", 1.0)
	_unit_costs = data.get("unit_costs", DEFAULT_UNIT_COSTS.duplicate()).duplicate()

	_faction_metrics.clear()
	var metrics_data: Dictionary = data.get("faction_metrics", {})
	for key in metrics_data:
		var m := EconomicMetrics.new()
		m.from_dict(metrics_data[key])
		_faction_metrics[int(key)] = m


## EconomicMetrics inner class.
class EconomicMetrics:
	var total_generated: float = 0.0
	var total_spent: float = 0.0
	var harvesting_income: float = 0.0
	var districts_captured: int = 0
	var districts_lost: int = 0
	var units_produced: int = 0
	var blackout_count: int = 0
	var tick_count: int = 0

	func to_dict() -> Dictionary:
		return {
			"total_generated": total_generated,
			"total_spent": total_spent,
			"harvesting_income": harvesting_income,
			"districts_captured": districts_captured,
			"districts_lost": districts_lost,
			"units_produced": units_produced,
			"blackout_count": blackout_count,
			"tick_count": tick_count
		}

	func from_dict(data: Dictionary) -> void:
		total_generated = data.get("total_generated", 0.0)
		total_spent = data.get("total_spent", 0.0)
		harvesting_income = data.get("harvesting_income", 0.0)
		districts_captured = data.get("districts_captured", 0)
		districts_lost = data.get("districts_lost", 0)
		units_produced = data.get("units_produced", 0)
		blackout_count = data.get("blackout_count", 0)
		tick_count = data.get("tick_count", 0)
