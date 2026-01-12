class_name REEDrop
extends RefCounted
## REEDrop represents a collectible REE resource drop in the game world.
## Spawned from destroyed buildings or salvaged units.

signal collected(collector_faction: String, amount: float)
signal expired()
signal amount_changed(new_amount: float)

## Default values
const DEFAULT_LIFETIME := 60.0      ## 60 second lifetime
const DEFAULT_COLLECTION_RADIUS := 2.0  ## 2.0 unit radius

## Unique drop ID
var id: int = 0

## World position
var position: Vector3 = Vector3.ZERO

## REE amount in this drop
var amount: float = 0.0

## Maximum amount (for tracking partial collection)
var max_amount: float = 0.0

## Faction that owns this drop (can collect)
var faction_id: String = ""

## Source of the drop
var source_type: String = ""  # "building", "unit", "harvester"
var source_id: int = -1

## Remaining lifetime (seconds)
var lifetime: float = DEFAULT_LIFETIME

## Collection radius
var collection_radius: float = DEFAULT_COLLECTION_RADIUS

## Whether drop has been fully collected
var is_collected: bool = false

## Whether drop has expired
var is_expired: bool = false

## Time since spawn
var age: float = 0.0

## Custom metadata
var metadata: Dictionary = {}


func _init(p_amount: float = 0.0, p_faction: String = "") -> void:
	amount = p_amount
	max_amount = p_amount
	faction_id = p_faction


## Initialize drop.
func initialize(
	p_position: Vector3,
	p_amount: float,
	p_faction: String,
	p_source_type: String = "",
	p_source_id: int = -1
) -> void:
	position = p_position
	amount = p_amount
	max_amount = p_amount
	faction_id = p_faction
	source_type = p_source_type
	source_id = p_source_id
	lifetime = DEFAULT_LIFETIME
	is_collected = false
	is_expired = false
	age = 0.0


## Update drop (called every frame).
func update(delta: float) -> void:
	if is_collected or is_expired:
		return

	age += delta
	lifetime -= delta

	if lifetime <= 0:
		is_expired = true
		expired.emit()


## Attempt to collect REE from this drop.
func collect(collector_faction: String, max_collect: float = INF) -> float:
	if is_collected or is_expired:
		return 0.0

	# Validate faction ownership
	if not can_be_collected_by(collector_faction):
		return 0.0

	# Calculate collection amount
	var collect_amount := minf(amount, max_collect)

	if collect_amount <= 0:
		return 0.0

	# Reduce drop amount
	amount -= collect_amount
	amount_changed.emit(amount)

	# Check if fully collected
	if amount <= 0:
		is_collected = true
		collected.emit(collector_faction, max_amount)

	return collect_amount


## Check if faction can collect this drop.
func can_be_collected_by(collector_faction: String) -> bool:
	# Only owning faction can collect
	return faction_id == collector_faction


## Check if position is within collection radius.
func is_in_range(pos: Vector3) -> bool:
	var distance := position.distance_to(pos)
	return distance <= collection_radius


## Check if drop is still valid.
func is_valid() -> bool:
	return not is_collected and not is_expired and amount > 0


## Get remaining lifetime percentage.
func get_lifetime_percent() -> float:
	return clampf(lifetime / DEFAULT_LIFETIME, 0.0, 1.0)


## Get collection percentage.
func get_collected_percent() -> float:
	if max_amount <= 0:
		return 1.0
	return 1.0 - (amount / max_amount)


## Set custom lifetime.
func set_lifetime(duration: float) -> void:
	lifetime = maxf(0.0, duration)


## Set custom collection radius.
func set_collection_radius(radius: float) -> void:
	collection_radius = maxf(0.1, radius)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"amount": amount,
		"max_amount": max_amount,
		"faction_id": faction_id,
		"source_type": source_type,
		"source_id": source_id,
		"lifetime": lifetime,
		"collection_radius": collection_radius,
		"is_collected": is_collected,
		"is_expired": is_expired,
		"age": age,
		"metadata": metadata.duplicate()
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> REEDrop:
	var drop := REEDrop.new()
	drop.id = data.get("id", 0)

	var pos_data: Dictionary = data.get("position", {})
	drop.position = Vector3(
		pos_data.get("x", 0.0),
		pos_data.get("y", 0.0),
		pos_data.get("z", 0.0)
	)

	drop.amount = data.get("amount", 0.0)
	drop.max_amount = data.get("max_amount", 0.0)
	drop.faction_id = data.get("faction_id", "")
	drop.source_type = data.get("source_type", "")
	drop.source_id = data.get("source_id", -1)
	drop.lifetime = data.get("lifetime", DEFAULT_LIFETIME)
	drop.collection_radius = data.get("collection_radius", DEFAULT_COLLECTION_RADIUS)
	drop.is_collected = data.get("is_collected", false)
	drop.is_expired = data.get("is_expired", false)
	drop.age = data.get("age", 0.0)
	drop.metadata = data.get("metadata", {}).duplicate()

	return drop


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": id,
		"amount": "%.1f/%.1f" % [amount, max_amount],
		"faction": faction_id,
		"lifetime": "%.1fs" % lifetime,
		"valid": is_valid()
	}
