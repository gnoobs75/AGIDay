class_name ResourceCollector
extends RefCounted
## ResourceCollector handles REE collection for units.
## Supports cooldowns, harvester priority, and batch collection.

signal collection_started(collector_id: int, drop_id: int)
signal collection_complete(collector_id: int, amount: float)
signal collection_failed(collector_id: int, reason: String)

## Collection cooldown (seconds)
const COLLECTION_COOLDOWN := 0.5

## Harvester priority bonus (multiplier for collection order)
const HARVESTER_PRIORITY := 2.0

## Maximum drops per collection batch
const MAX_BATCH_SIZE := 10

## Collection rate (REE per second)
const COLLECTION_RATE := 100.0

## REE drop manager reference
var drop_manager: REEDropManager = null

## Collector cooldowns (collector_id -> remaining cooldown)
var _cooldowns: Dictionary = {}

## Active collections (collector_id -> {drop_id, progress})
var _active_collections: Dictionary = {}


func _init() -> void:
	pass


## Set drop manager.
func set_drop_manager(manager: REEDropManager) -> void:
	drop_manager = manager


## Update collection system.
func update(delta: float) -> void:
	# Update cooldowns
	var to_remove: Array = []
	for collector_id in _cooldowns:
		_cooldowns[collector_id] -= delta
		if _cooldowns[collector_id] <= 0:
			to_remove.append(collector_id)

	for id in to_remove:
		_cooldowns.erase(id)


## Try to collect nearby drops for unit.
func collect_nearby(
	collector_id: int,
	position: Vector3,
	faction_id: String,
	is_harvester: bool = false,
	max_amount: float = INF
) -> float:
	if drop_manager == null:
		collection_failed.emit(collector_id, "No drop manager")
		return 0.0

	# Check cooldown
	if _cooldowns.has(collector_id):
		return 0.0

	# Get collection radius (harvesters have larger radius)
	var radius := REEDrop.DEFAULT_COLLECTION_RADIUS
	if is_harvester:
		radius *= 1.5

	# Get nearby drops
	var nearby := drop_manager.get_drops_in_radius(position, radius)

	if nearby.is_empty():
		return 0.0

	# Sort by priority (harvesters first, then by distance)
	nearby.sort_custom(func(a, b):
		var dist_a := position.distance_to(a.position)
		var dist_b := position.distance_to(b.position)
		return dist_a < dist_b
	)

	# Batch collection
	var total_collected := 0.0
	var remaining := max_amount
	var drops_processed := 0

	for drop in nearby:
		if drops_processed >= MAX_BATCH_SIZE:
			break

		if remaining <= 0:
			break

		if not drop.can_be_collected_by(faction_id):
			continue

		collection_started.emit(collector_id, drop.id)

		var collected := drop.collect(faction_id, remaining)
		if collected > 0:
			total_collected += collected
			remaining -= collected
			drops_processed += 1

	if total_collected > 0:
		collection_complete.emit(collector_id, total_collected)
		_cooldowns[collector_id] = COLLECTION_COOLDOWN

	return total_collected


## Start harvester direct collection (no drops).
func harvester_direct_collect(
	collector_id: int,
	target_position: Vector3,
	voxel_type: String,
	faction_id: String
) -> float:
	# Harvesters get REE directly without drops
	var type_mult: float = ResourceDropGenerator.get_type_multiplier(voxel_type)
	var amount := ResourceDropGenerator.BASE_REE_PER_VOXEL * type_mult

	# Add to faction resources via drop manager
	if drop_manager != null and drop_manager.resource_manager != null:
		if drop_manager.resource_manager.has_method("add_faction_ree"):
			drop_manager.resource_manager.add_faction_ree(faction_id, amount)

	collection_complete.emit(collector_id, amount)
	return amount


## Check if collector is on cooldown.
func is_on_cooldown(collector_id: int) -> bool:
	return _cooldowns.has(collector_id)


## Get remaining cooldown.
func get_cooldown(collector_id: int) -> float:
	return _cooldowns.get(collector_id, 0.0)


## Get collectors collecting from drop.
func get_collectors_at_drop(drop_id: int) -> Array[int]:
	var result: Array[int] = []
	for collector_id in _active_collections:
		if _active_collections[collector_id].get("drop_id") == drop_id:
			result.append(collector_id)
	return result


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"cooldowns": _cooldowns.duplicate(),
		"active_collections": _active_collections.duplicate(true)
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> ResourceCollector:
	var collector := ResourceCollector.new()
	collector._cooldowns = data.get("cooldowns", {}).duplicate()
	collector._active_collections = data.get("active_collections", {}).duplicate(true)
	return collector


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"collectors_on_cooldown": _cooldowns.size(),
		"active_collections": _active_collections.size()
	}
