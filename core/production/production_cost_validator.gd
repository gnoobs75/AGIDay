class_name ProductionCostValidator
extends RefCounted
## ProductionCostValidator validates and consumes REE for unit production.
## Ensures atomic resource transactions and deterministic production.

signal production_validated(faction_id: int, unit_type: String, cost: float)
signal production_approved(faction_id: int, unit_type: String, cost: float)
signal production_denied(faction_id: int, unit_type: String, cost: float, available: float)
signal ree_consumed(faction_id: int, unit_type: String, cost: float)
signal production_failed(faction_id: int, unit_type: String, reason: String)
signal cost_config_loaded(unit_count: int)

## Default production costs (loaded from config or set manually)
var _unit_costs: Dictionary = {
	# Aether Swarm units
	"drone": {"ree": 50.0, "time": 3.0, "power": 2.0},
	"swarmling": {"ree": 30.0, "time": 2.0, "power": 1.0},
	"nanite_cloud": {"ree": 100.0, "time": 8.0, "power": 5.0},
	"hive_node": {"ree": 200.0, "time": 15.0, "power": 10.0},

	# OptiForge Legion units
	"grunt": {"ree": 40.0, "time": 4.0, "power": 2.0},
	"optimizer": {"ree": 80.0, "time": 6.0, "power": 3.0},
	"forge_walker": {"ree": 150.0, "time": 10.0, "power": 7.0},
	"forge_titan": {"ree": 350.0, "time": 20.0, "power": 15.0},

	# Dynapods Vanguard units
	"leaper": {"ree": 60.0, "time": 4.0, "power": 3.0},
	"dynaquad": {"ree": 120.0, "time": 8.0, "power": 5.0},
	"behemoth": {"ree": 300.0, "time": 18.0, "power": 12.0},
	"ravager": {"ree": 250.0, "time": 14.0, "power": 10.0},

	# LogiBots Colossus units
	"bulkripper": {"ree": 70.0, "time": 5.0, "power": 3.0},
	"haulforge": {"ree": 90.0, "time": 6.0, "power": 4.0},
	"crushkin": {"ree": 100.0, "time": 7.0, "power": 5.0},
	"forge_stomper": {"ree": 180.0, "time": 12.0, "power": 8.0},
	"titanclad": {"ree": 400.0, "time": 25.0, "power": 18.0},
	"siegehaul": {"ree": 280.0, "time": 16.0, "power": 12.0},
	"colossus_cart": {"ree": 200.0, "time": 12.0, "power": 6.0},
	"payload_slinger": {"ree": 220.0, "time": 14.0, "power": 8.0},
	"gridbreaker": {"ree": 150.0, "time": 10.0, "power": 6.0},
	"logieye": {"ree": 80.0, "time": 8.0, "power": 4.0},

	# Generic units
	"harvester": {"ree": 80.0, "time": 6.0, "power": 3.0},
	"infantry": {"ree": 50.0, "time": 5.0, "power": 2.0},
	"tank": {"ree": 200.0, "time": 15.0, "power": 10.0},
	"artillery": {"ree": 300.0, "time": 20.0, "power": 15.0},
	"medic": {"ree": 80.0, "time": 8.0, "power": 3.0},
	"engineer": {"ree": 100.0, "time": 12.0, "power": 4.0},
	"scout": {"ree": 30.0, "time": 4.0, "power": 1.0}
}

## Faction-specific cost modifiers
var _faction_modifiers: Dictionary = {}   ## faction_id -> modifier

## Production analytics
var _production_analytics: Dictionary = {}  ## faction_id -> ProductionAnalytics

## Resource manager reference
var _resource_manager = null

## Pending productions (for atomic transactions)
var _pending_productions: Dictionary = {}   ## transaction_id -> PendingProduction

## Transaction ID counter
var _next_transaction_id: int = 1


func _init() -> void:
	pass


## Set resource manager reference.
func set_resource_manager(manager) -> void:
	_resource_manager = manager


## Load unit costs from configuration dictionary.
func load_costs_from_config(config: Dictionary) -> void:
	for unit_type in config:
		var cost_data: Dictionary = config[unit_type]
		_unit_costs[unit_type] = {
			"ree": cost_data.get("ree", cost_data.get("ree_cost", 100.0)),
			"time": cost_data.get("time", cost_data.get("production_time", 5.0)),
			"power": cost_data.get("power", cost_data.get("power_cost", 2.0))
		}

	cost_config_loaded.emit(_unit_costs.size())


## Load unit costs from JSON file.
func load_costs_from_file(file_path: String) -> bool:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("ProductionCostValidator: Cannot open config file: %s" % file_path)
		return false

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("ProductionCostValidator: JSON parse error: %s" % json.get_error_message())
		return false

	var data = json.data
	if data is Dictionary:
		load_costs_from_config(data)
		return true

	return false


## Set cost for a unit type.
func set_unit_cost(unit_type: String, ree: float, time: float, power: float = 0.0) -> void:
	_unit_costs[unit_type] = {
		"ree": ree,
		"time": time,
		"power": power
	}


## Get cost for a unit type.
func get_unit_cost(unit_type: String) -> Dictionary:
	return _unit_costs.get(unit_type, {"ree": 0.0, "time": 0.0, "power": 0.0}).duplicate()


## Get REE cost for a unit type.
func get_ree_cost(unit_type: String) -> float:
	var cost: Dictionary = _unit_costs.get(unit_type, {})
	return cost.get("ree", 0.0)


## Get production time for a unit type.
func get_production_time(unit_type: String) -> float:
	var cost: Dictionary = _unit_costs.get(unit_type, {})
	return cost.get("time", 5.0)


## Set faction cost modifier.
func set_faction_modifier(faction_id: int, modifier: float) -> void:
	_faction_modifiers[faction_id] = modifier


## Get effective cost for faction.
func get_effective_cost(faction_id: int, unit_type: String) -> float:
	var base_cost := get_ree_cost(unit_type)
	var modifier: float = _faction_modifiers.get(faction_id, 1.0)
	return base_cost * modifier


# ============================================
# VALIDATION
# ============================================

## Validate if faction can afford unit production.
func validate_production(faction_id: int, unit_type: String) -> ValidationResult:
	var result := ValidationResult.new()
	result.faction_id = faction_id
	result.unit_type = unit_type

	# Check if unit type exists
	if not _unit_costs.has(unit_type):
		result.is_valid = false
		result.reason = "Unknown unit type: %s" % unit_type
		production_failed.emit(faction_id, unit_type, result.reason)
		return result

	# Get effective cost
	var cost := get_effective_cost(faction_id, unit_type)
	result.ree_cost = cost

	# Check resource availability
	var available_ree := _get_available_ree(faction_id)
	result.available_ree = available_ree

	if available_ree < cost:
		result.is_valid = false
		result.reason = "Insufficient REE: need %.0f, have %.0f" % [cost, available_ree]
		production_denied.emit(faction_id, unit_type, cost, available_ree)
		_log_failed_production(faction_id, unit_type, cost, available_ree)
		return result

	result.is_valid = true
	result.reason = "Production approved"
	production_validated.emit(faction_id, unit_type, cost)

	return result


## Check if faction can afford (simple boolean).
func can_afford(faction_id: int, unit_type: String) -> bool:
	var cost := get_effective_cost(faction_id, unit_type)
	var available := _get_available_ree(faction_id)
	return available >= cost


# ============================================
# ATOMIC TRANSACTIONS
# ============================================

## Begin production transaction (reserves resources).
func begin_production(faction_id: int, unit_type: String) -> int:
	var result := validate_production(faction_id, unit_type)

	if not result.is_valid:
		return -1

	# Create pending production
	var transaction_id := _next_transaction_id
	_next_transaction_id += 1

	var pending := PendingProduction.new()
	pending.transaction_id = transaction_id
	pending.faction_id = faction_id
	pending.unit_type = unit_type
	pending.ree_cost = result.ree_cost
	pending.timestamp = Time.get_ticks_msec()

	_pending_productions[transaction_id] = pending

	production_approved.emit(faction_id, unit_type, result.ree_cost)
	return transaction_id


## Commit production transaction (consumes resources).
func commit_production(transaction_id: int) -> bool:
	if not _pending_productions.has(transaction_id):
		push_error("ProductionCostValidator: Invalid transaction ID: %d" % transaction_id)
		return false

	var pending: PendingProduction = _pending_productions[transaction_id]

	# Consume resources
	var success := _consume_ree(pending.faction_id, pending.ree_cost, pending.unit_type)

	if success:
		ree_consumed.emit(pending.faction_id, pending.unit_type, pending.ree_cost)
		_record_production(pending.faction_id, pending.unit_type, pending.ree_cost)

	# Remove pending transaction
	_pending_productions.erase(transaction_id)

	return success


## Cancel production transaction (releases reserved resources).
func cancel_production(transaction_id: int) -> bool:
	if not _pending_productions.has(transaction_id):
		return false

	var pending: PendingProduction = _pending_productions[transaction_id]
	_log_cancelled_production(pending.faction_id, pending.unit_type)

	_pending_productions.erase(transaction_id)
	return true


## Validate and consume in single atomic operation.
func validate_and_consume(faction_id: int, unit_type: String) -> bool:
	var transaction_id := begin_production(faction_id, unit_type)

	if transaction_id < 0:
		return false

	return commit_production(transaction_id)


# ============================================
# RESOURCE INTERACTION
# ============================================

## Get available REE for faction.
func _get_available_ree(faction_id: int) -> float:
	if _resource_manager != null:
		return _resource_manager.get_current_ree(faction_id)
	return INF  ## If no manager, assume unlimited resources


## Consume REE from faction.
func _consume_ree(faction_id: int, amount: float, unit_type: String) -> bool:
	if _resource_manager != null:
		return _resource_manager.consume_ree(faction_id, amount, "production:" + unit_type)
	return true  ## If no manager, always succeed


# ============================================
# ANALYTICS
# ============================================

## Get or create analytics for faction.
func _get_analytics(faction_id: int) -> ProductionAnalytics:
	if not _production_analytics.has(faction_id):
		_production_analytics[faction_id] = ProductionAnalytics.new()
	return _production_analytics[faction_id]


## Record successful production.
func _record_production(faction_id: int, unit_type: String, cost: float) -> void:
	var analytics := _get_analytics(faction_id)
	analytics.total_produced += 1
	analytics.total_ree_spent += cost

	if not analytics.units_produced.has(unit_type):
		analytics.units_produced[unit_type] = 0
	analytics.units_produced[unit_type] += 1


## Log failed production attempt.
func _log_failed_production(faction_id: int, unit_type: String, cost: float, available: float) -> void:
	var analytics := _get_analytics(faction_id)
	analytics.failed_attempts += 1

	var log_entry := {
		"timestamp": Time.get_ticks_msec(),
		"unit_type": unit_type,
		"cost": cost,
		"available": available,
		"deficit": cost - available
	}
	analytics.failed_production_log.append(log_entry)

	# Limit log size
	if analytics.failed_production_log.size() > 100:
		analytics.failed_production_log.pop_front()


## Log cancelled production.
func _log_cancelled_production(faction_id: int, unit_type: String) -> void:
	var analytics := _get_analytics(faction_id)
	analytics.cancelled_productions += 1


## Get production analytics for faction.
func get_analytics(faction_id: int) -> Dictionary:
	var analytics := _get_analytics(faction_id)
	return analytics.to_dict()


## Get all analytics.
func get_all_analytics() -> Dictionary:
	var result := {}
	for faction_id in _production_analytics:
		result[faction_id] = get_analytics(faction_id)
	return result


# ============================================
# QUERY METHODS
# ============================================

## Get all unit types.
func get_all_unit_types() -> Array[String]:
	var types: Array[String] = []
	for unit_type in _unit_costs:
		types.append(unit_type)
	return types


## Check if unit type exists.
func has_unit_type(unit_type: String) -> bool:
	return _unit_costs.has(unit_type)


## Get pending production count.
func get_pending_count() -> int:
	return _pending_productions.size()


## Get statistics.
func get_statistics() -> Dictionary:
	var total_produced := 0
	var total_failed := 0
	var total_spent := 0.0

	for faction_id in _production_analytics:
		var analytics: ProductionAnalytics = _production_analytics[faction_id]
		total_produced += analytics.total_produced
		total_failed += analytics.failed_attempts
		total_spent += analytics.total_ree_spent

	return {
		"unit_types_configured": _unit_costs.size(),
		"factions_tracked": _production_analytics.size(),
		"pending_transactions": _pending_productions.size(),
		"total_produced": total_produced,
		"total_failed": total_failed,
		"total_ree_spent": total_spent
	}


# ============================================
# SERIALIZATION
# ============================================

## Serialize to dictionary.
func to_dict() -> Dictionary:
	var analytics_data := {}
	for faction_id in _production_analytics:
		analytics_data[str(faction_id)] = _production_analytics[faction_id].to_dict()

	return {
		"unit_costs": _unit_costs.duplicate(true),
		"faction_modifiers": _faction_modifiers.duplicate(),
		"production_analytics": analytics_data,
		"next_transaction_id": _next_transaction_id
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_costs = data.get("unit_costs", _unit_costs).duplicate(true)
	_faction_modifiers = data.get("faction_modifiers", {}).duplicate()
	_next_transaction_id = data.get("next_transaction_id", 1)

	_production_analytics.clear()
	var analytics_data: Dictionary = data.get("production_analytics", {})
	for key in analytics_data:
		var analytics := ProductionAnalytics.new()
		analytics.from_dict(analytics_data[key])
		_production_analytics[int(key)] = analytics


## ValidationResult class.
class ValidationResult:
	var is_valid: bool = false
	var faction_id: int = 0
	var unit_type: String = ""
	var ree_cost: float = 0.0
	var available_ree: float = 0.0
	var reason: String = ""


## PendingProduction class.
class PendingProduction:
	var transaction_id: int = 0
	var faction_id: int = 0
	var unit_type: String = ""
	var ree_cost: float = 0.0
	var timestamp: int = 0


## ProductionAnalytics class.
class ProductionAnalytics:
	var total_produced: int = 0
	var total_ree_spent: float = 0.0
	var failed_attempts: int = 0
	var cancelled_productions: int = 0
	var units_produced: Dictionary = {}
	var failed_production_log: Array = []

	func to_dict() -> Dictionary:
		return {
			"total_produced": total_produced,
			"total_ree_spent": total_ree_spent,
			"failed_attempts": failed_attempts,
			"cancelled_productions": cancelled_productions,
			"units_produced": units_produced.duplicate(),
			"failed_production_log": failed_production_log.duplicate()
		}

	func from_dict(data: Dictionary) -> void:
		total_produced = data.get("total_produced", 0)
		total_ree_spent = data.get("total_ree_spent", 0.0)
		failed_attempts = data.get("failed_attempts", 0)
		cancelled_productions = data.get("cancelled_productions", 0)
		units_produced = data.get("units_produced", {}).duplicate()
		failed_production_log = data.get("failed_production_log", []).duplicate()
