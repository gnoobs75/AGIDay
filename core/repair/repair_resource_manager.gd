class_name RepairResourceManager
extends RefCounted
## RepairResourceManager manages REE consumption for repair operations.

signal repair_approved(builder_id: int, position: Vector3i, cost: int)
signal repair_denied(builder_id: int, position: Vector3i, required: int, available: int)
signal repair_completed(builder_id: int, position: Vector3i, cost_deducted: int)
signal resources_depleted(faction_id: String)

## Resource deduction states
enum DeductionResult {
	SUCCESS,
	INSUFFICIENT_RESOURCES,
	INVALID_FACTION,
	INVALID_COST
}

## Cost calculator
var _cost_calculator: RepairCostCalculator

## Callbacks for resource system integration
var _get_ree_callback: Callable = Callable()  ## func(faction_id: String) -> int
var _deduct_ree_callback: Callable = Callable()  ## func(faction_id: String, amount: int) -> bool
var _has_ree_callback: Callable = Callable()  ## func(faction_id: String, amount: int) -> bool

## Pending repairs tracking (for atomic operations)
var _pending_repairs: Dictionary = {}  ## "builder_id" -> {position, cost, faction}

## Builder faction assignments
var _builder_factions: Dictionary = {}  ## builder_id -> faction_id


func _init() -> void:
	_cost_calculator = RepairCostCalculator.new()


## Set resource system callbacks.
func set_resource_callbacks(
	get_ree: Callable,
	deduct_ree: Callable,
	has_ree: Callable
) -> void:
	_get_ree_callback = get_ree
	_deduct_ree_callback = deduct_ree
	_has_ree_callback = has_ree


## Set power node callback for cost calculations.
func set_power_node_callback(callback: Callable) -> void:
	_cost_calculator.set_power_node_callback(callback)


## Assign faction to builder.
func assign_builder_faction(builder_id: int, faction_id: String) -> void:
	_builder_factions[builder_id] = faction_id


## Get builder's faction.
func get_builder_faction(builder_id: int) -> String:
	return _builder_factions.get(builder_id, "")


## Remove builder.
func remove_builder(builder_id: int) -> void:
	_builder_factions.erase(builder_id)
	_pending_repairs.erase(builder_id)


## Check if builder can afford repair.
func can_afford_repair(
	builder_id: int,
	position: Vector3i,
	damage_stage: int
) -> bool:
	var faction_id := get_builder_faction(builder_id)
	if faction_id.is_empty():
		return false

	var cost := _cost_calculator.calculate_repair_cost(position, damage_stage, faction_id)
	if cost <= 0:
		return false

	return _check_resources(faction_id, cost)


## Check if builder can afford repair target.
func can_afford_target(
	builder_id: int,
	target: RepairTargetSelector.RepairTarget
) -> bool:
	if target == null:
		return false
	return can_afford_repair(builder_id, target.position, target.damage_stage)


## Request repair approval (checks resources, reserves if available).
func request_repair_approval(
	builder_id: int,
	position: Vector3i,
	damage_stage: int
) -> bool:
	var faction_id := get_builder_faction(builder_id)
	if faction_id.is_empty():
		repair_denied.emit(builder_id, position, 0, 0)
		return false

	var cost := _cost_calculator.calculate_repair_cost(position, damage_stage, faction_id)
	if cost <= 0:
		repair_denied.emit(builder_id, position, 0, 0)
		return false

	var available := _get_available_ree(faction_id)

	if not _check_resources(faction_id, cost):
		repair_denied.emit(builder_id, position, cost, available)
		return false

	# Track pending repair
	_pending_repairs[builder_id] = {
		"position": position,
		"cost": cost,
		"faction_id": faction_id,
		"damage_stage": damage_stage
	}

	repair_approved.emit(builder_id, position, cost)
	return true


## Request repair approval using target.
func request_target_approval(
	builder_id: int,
	target: RepairTargetSelector.RepairTarget
) -> bool:
	if target == null:
		return false
	return request_repair_approval(builder_id, target.position, target.damage_stage)


## Complete repair and deduct resources.
func complete_repair(builder_id: int) -> DeductionResult:
	if not _pending_repairs.has(builder_id):
		return DeductionResult.INVALID_COST

	var pending: Dictionary = _pending_repairs[builder_id]
	var faction_id: String = pending["faction_id"]
	var cost: int = pending["cost"]
	var position: Vector3i = pending["position"]

	# Verify resources still available
	if not _check_resources(faction_id, cost):
		var available := _get_available_ree(faction_id)
		repair_denied.emit(builder_id, position, cost, available)
		_pending_repairs.erase(builder_id)
		return DeductionResult.INSUFFICIENT_RESOURCES

	# Deduct resources
	var success := _deduct_resources(faction_id, cost)
	if not success:
		_pending_repairs.erase(builder_id)
		return DeductionResult.INSUFFICIENT_RESOURCES

	# Clear pending
	_pending_repairs.erase(builder_id)

	repair_completed.emit(builder_id, position, cost)

	# Check if faction is now depleted
	if _get_available_ree(faction_id) <= 0:
		resources_depleted.emit(faction_id)

	return DeductionResult.SUCCESS


## Cancel pending repair.
func cancel_repair(builder_id: int) -> void:
	_pending_repairs.erase(builder_id)


## Get pending repair info.
func get_pending_repair(builder_id: int) -> Dictionary:
	return _pending_repairs.get(builder_id, {})


## Check if builder has pending repair.
func has_pending_repair(builder_id: int) -> bool:
	return _pending_repairs.has(builder_id)


## Get repair cost for position.
func get_repair_cost(
	position: Vector3i,
	damage_stage: int,
	faction_id: String
) -> int:
	return _cost_calculator.calculate_repair_cost(position, damage_stage, faction_id)


## Get repair cost breakdown.
func get_cost_breakdown(
	position: Vector3i,
	damage_stage: int,
	faction_id: String
) -> Dictionary:
	return _cost_calculator.get_cost_breakdown(position, damage_stage, faction_id)


## Get available REE for faction.
func get_faction_ree(faction_id: String) -> int:
	return _get_available_ree(faction_id)


## Check resources via callback.
func _check_resources(faction_id: String, amount: int) -> bool:
	if _has_ree_callback.is_valid():
		return _has_ree_callback.call(faction_id, amount)

	# Fallback to get and compare
	if _get_ree_callback.is_valid():
		var available: int = _get_ree_callback.call(faction_id)
		return available >= amount

	# No callback - allow by default (for testing)
	return true


## Get available REE via callback.
func _get_available_ree(faction_id: String) -> int:
	if _get_ree_callback.is_valid():
		return _get_ree_callback.call(faction_id)
	return 0


## Deduct resources via callback.
func _deduct_resources(faction_id: String, amount: int) -> bool:
	if _deduct_ree_callback.is_valid():
		return _deduct_ree_callback.call(faction_id, amount)
	# No callback - assume success (for testing)
	return true


## Calculate how many repairs can be afforded.
func get_affordable_repair_count(
	scan_results: Array,
	faction_id: String
) -> int:
	var available := _get_available_ree(faction_id)
	var count := 0
	var running_cost := 0

	for info in scan_results:
		var cost := 0
		if info is DamageScanner.DamagedVoxelInfo:
			cost = _cost_calculator.calculate_repair_cost(
				info.position, info.damage_stage, faction_id
			)
		elif info is Dictionary:
			var pos: Vector3i = info.get("position", Vector3i.ZERO)
			var stage: int = info.get("damage_stage", 1)
			cost = _cost_calculator.calculate_repair_cost(pos, stage, faction_id)

		if running_cost + cost <= available:
			running_cost += cost
			count += 1
		else:
			break

	return count


## Get total pending costs for faction.
func get_pending_costs(faction_id: String) -> int:
	var total := 0
	for builder_id in _pending_repairs:
		var pending: Dictionary = _pending_repairs[builder_id]
		if pending.get("faction_id", "") == faction_id:
			total += pending.get("cost", 0)
	return total


## Get cost calculator for direct access.
func get_cost_calculator() -> RepairCostCalculator:
	return _cost_calculator


## Clear all data.
func clear() -> void:
	_pending_repairs.clear()
	_builder_factions.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"builder_count": _builder_factions.size(),
		"pending_repairs": _pending_repairs.size(),
		"has_get_ree_callback": _get_ree_callback.is_valid(),
		"has_deduct_ree_callback": _deduct_ree_callback.is_valid(),
		"has_has_ree_callback": _has_ree_callback.is_valid()
	}
