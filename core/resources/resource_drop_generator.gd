class_name ResourceDropGenerator
extends RefCounted
## ResourceDropGenerator creates REE drops from voxel destruction.
## Calculates drop amounts based on voxel type and handles multipliers.

signal drop_generated(drop_id: int, amount: float, position: Vector3)

## Base REE per voxel
const BASE_REE_PER_VOXEL := 50.0

## Voxel type multipliers
const TYPE_MULTIPLIERS := {
	"residential": 1.0,
	"commercial": 1.2,
	"industrial": 1.5,
	"power_node": 2.0,
	"power_hub": 2.0,
	"ree_node": 3.0,
	"resource": 3.0,
	"infrastructure": 1.3,
	"default": 1.0
}

## REE drop manager reference
var drop_manager: REEDropManager = null

## Destruction method multipliers
const DESTRUCTION_MULTIPLIERS := {
	"combat": 0.8,      ## Combat destruction loses some REE
	"harvester": 1.0,   ## Harvester gets full REE
	"collapse": 0.5,    ## Structural collapse loses more
	"default": 1.0
}

## Minimum drop amount (smaller amounts are ignored)
const MIN_DROP_AMOUNT := 5.0

## Drop merge distance
const MERGE_DISTANCE := 2.0


func _init() -> void:
	pass


## Set drop manager.
func set_drop_manager(manager: REEDropManager) -> void:
	drop_manager = manager


## Generate drop from voxel destruction.
func generate_from_voxel(
	position: Vector3,
	voxel_type: String,
	faction_id: String,
	destruction_method: String = "default"
) -> REEDrop:
	var amount := calculate_drop_amount(voxel_type, destruction_method)

	if amount < MIN_DROP_AMOUNT:
		return null

	return _spawn_or_merge_drop(position, amount, faction_id, "voxel")


## Generate drop from building destruction.
func generate_from_building(
	position: Vector3,
	building_type: String,
	building_size: int,
	faction_id: String,
	destruction_method: String = "default"
) -> REEDrop:
	# Building REE is based on size and type
	var voxel_count := _estimate_building_voxels(building_size)
	var base_amount := BASE_REE_PER_VOXEL * voxel_count

	var type_mult: float = TYPE_MULTIPLIERS.get(building_type, TYPE_MULTIPLIERS["default"])
	var dest_mult: float = DESTRUCTION_MULTIPLIERS.get(destruction_method, DESTRUCTION_MULTIPLIERS["default"])

	var amount := base_amount * type_mult * dest_mult

	if amount < MIN_DROP_AMOUNT:
		return null

	return _spawn_or_merge_drop(position, amount, faction_id, "building")


## Generate drop from unit salvage.
func generate_from_unit(
	position: Vector3,
	unit_type: String,
	unit_value: float,
	faction_id: String
) -> REEDrop:
	# Units return a portion of their value
	var amount := unit_value * 0.5  # 50% salvage rate

	if amount < MIN_DROP_AMOUNT:
		return null

	return _spawn_or_merge_drop(position, amount, faction_id, "unit")


## Calculate drop amount for voxel.
func calculate_drop_amount(voxel_type: String, destruction_method: String = "default") -> float:
	var type_mult: float = TYPE_MULTIPLIERS.get(voxel_type, TYPE_MULTIPLIERS["default"])
	var dest_mult: float = DESTRUCTION_MULTIPLIERS.get(destruction_method, DESTRUCTION_MULTIPLIERS["default"])

	return BASE_REE_PER_VOXEL * type_mult * dest_mult


## Estimate voxels in building by size category.
func _estimate_building_voxels(size_category: int) -> int:
	match size_category:
		0:  # Small (4x4x4)
			return 64
		1:  # Medium (8x6x8)
			return 384
		2:  # Large (12x8x12)
			return 1152
	return 64


## Spawn new drop or merge with existing.
func _spawn_or_merge_drop(
	position: Vector3,
	amount: float,
	faction_id: String,
	source_type: String
) -> REEDrop:
	if drop_manager == null:
		return null

	# Check for nearby drops to merge
	var nearby := drop_manager.get_drops_in_radius(position, MERGE_DISTANCE)

	for drop in nearby:
		if drop.faction_id == faction_id and drop.is_valid():
			# Merge into existing drop
			drop.amount += amount
			drop.max_amount += amount
			drop.amount_changed.emit(drop.amount)
			drop_generated.emit(drop.id, amount, position)
			return drop

	# Spawn new drop
	var drop := drop_manager.spawn_drop(position, amount, faction_id, source_type)
	if drop != null:
		drop_generated.emit(drop.id, amount, position)

	return drop


## Get multiplier for voxel type.
static func get_type_multiplier(voxel_type: String) -> float:
	return TYPE_MULTIPLIERS.get(voxel_type, TYPE_MULTIPLIERS["default"])


## Get multiplier for destruction method.
static func get_destruction_multiplier(method: String) -> float:
	return DESTRUCTION_MULTIPLIERS.get(method, DESTRUCTION_MULTIPLIERS["default"])


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"base_ree": BASE_REE_PER_VOXEL,
		"min_drop": MIN_DROP_AMOUNT,
		"merge_distance": MERGE_DISTANCE,
		"has_manager": drop_manager != null
	}
