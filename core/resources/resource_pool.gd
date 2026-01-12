class_name ResourcePool
extends RefCounted
## ResourcePool manages both REE and Power resources for a faction.
## Provides atomic operations with overflow/underflow protection.

signal ree_changed(amount: float, change: float, source: String)
signal power_changed(amount: float, change: float, source: String)
signal storage_full(resource_type: String)
signal insufficient_resources(resource_type: String, requested: float, available: float)
signal transaction_failed(reason: String)

## Resource types
enum ResourceType {
	REE = 0,
	POWER = 1
}

## Faction ID
var faction_id: int = 0

## REE resources
var current_ree: float = 0.0
var max_ree: float = 10000.0
var ree_generation_rate: float = 0.0

## Power resources
var current_power: float = 0.0
var max_power: float = 50000.0
var power_generation_rate: float = 0.0

## Analytics
var total_ree_generated: float = 0.0
var total_ree_consumed: float = 0.0
var total_power_generated: float = 0.0
var total_power_consumed: float = 0.0

## Resource multipliers (from buffs)
var ree_multiplier: float = 1.0
var power_multiplier: float = 1.0
var income_multiplier: float = 1.0

## Thread safety (for future networking)
var _transaction_lock: bool = false


func _init(p_faction_id: int = 0) -> void:
	faction_id = p_faction_id


## Initialize with starting resources.
func initialize(starting_ree: float = 1000.0, starting_power: float = 5000.0) -> void:
	current_ree = clampf(starting_ree, 0.0, max_ree)
	current_power = clampf(starting_power, 0.0, max_power)
	total_ree_generated = starting_ree
	total_power_generated = starting_power


## Add REE with overflow protection.
func add_ree(amount: float, source: String = "unknown") -> float:
	if amount <= 0:
		return 0.0

	var actual := minf(amount * ree_multiplier, max_ree - current_ree)
	if actual > 0:
		current_ree += actual
		total_ree_generated += actual
		ree_changed.emit(current_ree, actual, source)

	if current_ree >= max_ree:
		storage_full.emit("ree")

	return actual


## Add Power with overflow protection.
func add_power(amount: float, source: String = "unknown") -> float:
	if amount <= 0:
		return 0.0

	var actual := minf(amount * power_multiplier, max_power - current_power)
	if actual > 0:
		current_power += actual
		total_power_generated += actual
		power_changed.emit(current_power, actual, source)

	if current_power >= max_power:
		storage_full.emit("power")

	return actual


## Deduct REE with underflow protection.
func deduct_ree(amount: float, category: String = "unknown") -> bool:
	if amount <= 0:
		return true

	if current_ree < amount:
		insufficient_resources.emit("ree", amount, current_ree)
		return false

	current_ree -= amount
	total_ree_consumed += amount
	ree_changed.emit(current_ree, -amount, category)
	return true


## Deduct Power with underflow protection.
func deduct_power(amount: float, category: String = "unknown") -> bool:
	if amount <= 0:
		return true

	if current_power < amount:
		insufficient_resources.emit("power", amount, current_power)
		return false

	current_power -= amount
	total_power_consumed += amount
	power_changed.emit(current_power, -amount, category)
	return true


## Atomic transaction for consuming both REE and Power.
## Returns true if successful, false if insufficient resources.
func consume_resources(ree_cost: float, power_cost: float, category: String = "unknown") -> bool:
	if _transaction_lock:
		transaction_failed.emit("Transaction in progress")
		return false

	_transaction_lock = true

	# Validate both resources
	if current_ree < ree_cost or current_power < power_cost:
		_transaction_lock = false
		if current_ree < ree_cost:
			insufficient_resources.emit("ree", ree_cost, current_ree)
		if current_power < power_cost:
			insufficient_resources.emit("power", power_cost, current_power)
		return false

	# Perform atomic deduction
	current_ree -= ree_cost
	current_power -= power_cost
	total_ree_consumed += ree_cost
	total_power_consumed += power_cost

	ree_changed.emit(current_ree, -ree_cost, category)
	power_changed.emit(current_power, -power_cost, category)

	_transaction_lock = false
	return true


## Validate cost without consuming.
func can_afford(ree_cost: float, power_cost: float) -> bool:
	return current_ree >= ree_cost and current_power >= power_cost


## Validate and get missing resources.
func validate_cost(ree_cost: float, power_cost: float) -> Dictionary:
	return {
		"can_afford": can_afford(ree_cost, power_cost),
		"ree_missing": maxf(0.0, ree_cost - current_ree),
		"power_missing": maxf(0.0, power_cost - current_power),
		"ree_available": current_ree,
		"power_available": current_power
	}


## Set generation rates.
func set_generation_rates(ree_rate: float, power_rate: float) -> void:
	ree_generation_rate = maxf(0.0, ree_rate)
	power_generation_rate = maxf(0.0, power_rate)


## Apply generation tick.
func apply_generation(delta: float) -> Dictionary:
	var ree_added := 0.0
	var power_added := 0.0

	if ree_generation_rate > 0:
		ree_added = add_ree(ree_generation_rate * delta * income_multiplier, "generation")

	if power_generation_rate > 0:
		power_added = add_power(power_generation_rate * delta * income_multiplier, "generation")

	return {"ree": ree_added, "power": power_added}


## Set multipliers from buffs.
func set_multipliers(ree_mult: float = 1.0, power_mult: float = 1.0, income_mult: float = 1.0) -> void:
	ree_multiplier = maxf(0.0, ree_mult)
	power_multiplier = maxf(0.0, power_mult)
	income_multiplier = maxf(0.0, income_mult)


## Get storage percentages.
func get_storage_percentages() -> Dictionary:
	return {
		"ree": current_ree / max_ree if max_ree > 0 else 0.0,
		"power": current_power / max_power if max_power > 0 else 0.0
	}


## Increase max storage.
func increase_max_storage(ree_increase: float = 0.0, power_increase: float = 0.0) -> void:
	max_ree += ree_increase
	max_power += power_increase


## Set max storage directly.
func set_max_storage(ree_max: float, power_max: float) -> void:
	max_ree = maxf(0.0, ree_max)
	max_power = maxf(0.0, power_max)
	# Clamp current values
	current_ree = minf(current_ree, max_ree)
	current_power = minf(current_power, max_power)


## Reset pool to initial state.
func reset(starting_ree: float = 1000.0, starting_power: float = 5000.0) -> void:
	current_ree = clampf(starting_ree, 0.0, max_ree)
	current_power = clampf(starting_power, 0.0, max_power)
	ree_generation_rate = 0.0
	power_generation_rate = 0.0
	total_ree_generated = starting_ree
	total_ree_consumed = 0.0
	total_power_generated = starting_power
	total_power_consumed = 0.0
	ree_multiplier = 1.0
	power_multiplier = 1.0
	income_multiplier = 1.0


## Serialize state.
func to_dict() -> Dictionary:
	return {
		"faction_id": faction_id,
		"current_ree": current_ree,
		"max_ree": max_ree,
		"ree_generation_rate": ree_generation_rate,
		"current_power": current_power,
		"max_power": max_power,
		"power_generation_rate": power_generation_rate,
		"total_ree_generated": total_ree_generated,
		"total_ree_consumed": total_ree_consumed,
		"total_power_generated": total_power_generated,
		"total_power_consumed": total_power_consumed,
		"ree_multiplier": ree_multiplier,
		"power_multiplier": power_multiplier,
		"income_multiplier": income_multiplier
	}


## Deserialize state.
func from_dict(data: Dictionary) -> void:
	faction_id = data.get("faction_id", 0)
	current_ree = data.get("current_ree", 0.0)
	max_ree = data.get("max_ree", 10000.0)
	ree_generation_rate = data.get("ree_generation_rate", 0.0)
	current_power = data.get("current_power", 0.0)
	max_power = data.get("max_power", 50000.0)
	power_generation_rate = data.get("power_generation_rate", 0.0)
	total_ree_generated = data.get("total_ree_generated", 0.0)
	total_ree_consumed = data.get("total_ree_consumed", 0.0)
	total_power_generated = data.get("total_power_generated", 0.0)
	total_power_consumed = data.get("total_power_consumed", 0.0)
	ree_multiplier = data.get("ree_multiplier", 1.0)
	power_multiplier = data.get("power_multiplier", 1.0)
	income_multiplier = data.get("income_multiplier", 1.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"faction_id": faction_id,
		"ree": "%.0f/%.0f (%.0f/s)" % [current_ree, max_ree, ree_generation_rate],
		"power": "%.0f/%.0f (%.0f/s)" % [current_power, max_power, power_generation_rate],
		"income_mult": income_multiplier
	}
