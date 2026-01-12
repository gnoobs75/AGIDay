class_name RepairCostCalculator
extends RefCounted
## RepairCostCalculator calculates REE costs for repair operations.

signal cost_calculated(position: Vector3i, cost: int)
signal insufficient_resources(position: Vector3i, required: int, available: int)

## Faction-specific base REE costs per voxel
const FACTION_BASE_COSTS := {
	"AETHER_SWARM": 25,
	"OPTIFORGE_LEGION": 30,
	"DYNAPODS_VANGUARD": 28,
	"LOGIBOTS_COLOSSUS": 35
}

## Default cost for unknown factions
const DEFAULT_BASE_COST := 30

## Damage stage multipliers
const DAMAGE_STAGE_MULTIPLIERS := {
	0: 0.0,  ## Intact - no repair needed
	1: 1.0,  ## Cracked
	2: 1.5,  ## Rubble
	3: 0.0   ## Crater - not repairable
}

## Power infrastructure cost multiplier
const POWER_INFRASTRUCTURE_MULTIPLIER := 1.5

## Callback for checking power infrastructure
var _is_power_node_callback: Callable = Callable()


func _init() -> void:
	pass


## Set power node detection callback.
## Callback signature: func(position: Vector3i) -> bool
func set_power_node_callback(callback: Callable) -> void:
	_is_power_node_callback = callback


## Get base cost for faction.
func get_faction_base_cost(faction_id: String) -> int:
	return FACTION_BASE_COSTS.get(faction_id, DEFAULT_BASE_COST)


## Get damage stage multiplier.
func get_damage_multiplier(damage_stage: int) -> float:
	return DAMAGE_STAGE_MULTIPLIERS.get(damage_stage, 0.0)


## Check if position is power infrastructure.
func is_power_infrastructure(position: Vector3i) -> bool:
	if _is_power_node_callback.is_valid():
		return _is_power_node_callback.call(position)
	return false


## Calculate repair cost for a single voxel.
func calculate_repair_cost(
	position: Vector3i,
	damage_stage: int,
	faction_id: String
) -> int:
	# Get base cost for faction
	var base_cost := get_faction_base_cost(faction_id)

	# Apply damage multiplier
	var damage_mult := get_damage_multiplier(damage_stage)
	if damage_mult == 0.0:
		return 0  # Not repairable

	var cost := base_cost * damage_mult

	# Apply power infrastructure multiplier
	if is_power_infrastructure(position):
		cost *= POWER_INFRASTRUCTURE_MULTIPLIER

	return roundi(cost)


## Calculate repair cost using RepairTarget.
func calculate_target_cost(
	target: RepairTargetSelector.RepairTarget,
	faction_id: String
) -> int:
	if target == null:
		return 0

	return calculate_repair_cost(target.position, target.damage_stage, faction_id)


## Calculate total cost for multiple voxels.
func calculate_bulk_cost(
	positions: Array,
	damage_stages: Dictionary,
	faction_id: String
) -> int:
	var total := 0

	for pos in positions:
		if not pos is Vector3i:
			continue

		var damage_stage: int = damage_stages.get(pos, 1)
		total += calculate_repair_cost(pos, damage_stage, faction_id)

	return total


## Calculate cost from damaged voxel info array.
func calculate_cost_from_scan_results(
	scan_results: Array,
	faction_id: String
) -> int:
	var total := 0

	for info in scan_results:
		if info is DamageScanner.DamagedVoxelInfo:
			total += calculate_repair_cost(info.position, info.damage_stage, faction_id)
		elif info is Dictionary:
			var pos: Vector3i = info.get("position", Vector3i.ZERO)
			var stage: int = info.get("damage_stage", 1)
			total += calculate_repair_cost(pos, stage, faction_id)

	return total


## Get cost breakdown for a position.
func get_cost_breakdown(
	position: Vector3i,
	damage_stage: int,
	faction_id: String
) -> Dictionary:
	var base_cost := get_faction_base_cost(faction_id)
	var damage_mult := get_damage_multiplier(damage_stage)
	var is_power := is_power_infrastructure(position)
	var power_mult := POWER_INFRASTRUCTURE_MULTIPLIER if is_power else 1.0

	var final_cost := roundi(base_cost * damage_mult * power_mult)

	return {
		"position": position,
		"faction_id": faction_id,
		"base_cost": base_cost,
		"damage_stage": damage_stage,
		"damage_multiplier": damage_mult,
		"is_power_infrastructure": is_power,
		"power_multiplier": power_mult,
		"final_cost": final_cost
	}


## Get all faction base costs.
static func get_all_faction_costs() -> Dictionary:
	return FACTION_BASE_COSTS.duplicate()


## Get all damage multipliers.
static func get_all_damage_multipliers() -> Dictionary:
	return DAMAGE_STAGE_MULTIPLIERS.duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"faction_costs": FACTION_BASE_COSTS,
		"damage_multipliers": DAMAGE_STAGE_MULTIPLIERS,
		"power_multiplier": POWER_INFRASTRUCTURE_MULTIPLIER,
		"has_power_callback": _is_power_node_callback.is_valid()
	}
