class_name FactoryOverclock
extends RefCounted
## FactoryOverclock tracks overclock level, heat, and meltdown state for a factory.

signal heat_changed(factory_id: int, heat_level: float)
signal overclock_changed(factory_id: int, multiplier: float)
signal meltdown_started(factory_id: int)
signal meltdown_recovered(factory_id: int)

## Overclock limits
const MIN_OVERCLOCK := 1.0
const MAX_OVERCLOCK := 2.0

## Heat limits
const MIN_HEAT := 0.0
const MAX_HEAT := 1.0
const MELTDOWN_THRESHOLD := 1.0

## Heat rates (per second)
const HEAT_GENERATION_RATE := 0.15  ## At 2x overclock
const HEAT_DISSIPATION_RATE := 0.08  ## When at normal speed

## Meltdown settings
const MELTDOWN_DURATION := 30.0
const POST_MELTDOWN_HEAT := 0.5

## Factory identity
var factory_id: int = -1

## Overclock state
var overclock_level: float = 1.0
var heat_level: float = 0.0

## Meltdown state
var is_meltdown: bool = false
var meltdown_timer: float = 0.0

## Production state
var is_production_enabled: bool = true


func _init() -> void:
	pass


## Initialize for a factory.
func initialize(p_factory_id: int) -> void:
	factory_id = p_factory_id
	overclock_level = MIN_OVERCLOCK
	heat_level = MIN_HEAT
	is_meltdown = false
	meltdown_timer = 0.0
	is_production_enabled = true


## Set overclock level.
func set_overclock(level: float) -> void:
	if is_meltdown:
		return

	var old_level := overclock_level
	overclock_level = clampf(level, MIN_OVERCLOCK, MAX_OVERCLOCK)

	if old_level != overclock_level:
		overclock_changed.emit(factory_id, overclock_level)


## Update heat (called by system).
func update_heat(delta: float) -> void:
	if is_meltdown:
		_update_meltdown(delta)
		return

	# Calculate heat change
	var heat_change := 0.0

	if overclock_level > MIN_OVERCLOCK:
		# Generate heat when overclocked
		var heat_factor := _calculate_heat_factor()
		heat_change = HEAT_GENERATION_RATE * heat_factor * delta
	else:
		# Dissipate heat when at normal speed
		heat_change = -HEAT_DISSIPATION_RATE * delta

	# Apply heat change
	var old_heat := heat_level
	heat_level = clampf(heat_level + heat_change, MIN_HEAT, MAX_HEAT)

	if not is_equal_approx(old_heat, heat_level):
		heat_changed.emit(factory_id, heat_level)

	# Check for meltdown
	if heat_level >= MELTDOWN_THRESHOLD:
		_trigger_meltdown()


## Calculate heat generation factor based on overclock level.
## Non-linear curve: 0% at 1.0x, 30% at 1.5x, 100% at 2.0x
func _calculate_heat_factor() -> float:
	# Normalize overclock to 0-1 range
	var normalized := (overclock_level - MIN_OVERCLOCK) / (MAX_OVERCLOCK - MIN_OVERCLOCK)

	# Apply non-linear curve (quadratic)
	# At 0.5 (1.5x): should be ~0.3
	# At 1.0 (2.0x): should be 1.0
	# Use: factor = normalized^1.7 gives approximately right curve
	return pow(normalized, 1.7)


## Trigger meltdown.
func _trigger_meltdown() -> void:
	is_meltdown = true
	meltdown_timer = MELTDOWN_DURATION
	is_production_enabled = false
	overclock_level = MIN_OVERCLOCK

	meltdown_started.emit(factory_id)
	overclock_changed.emit(factory_id, overclock_level)


## Update meltdown recovery.
func _update_meltdown(delta: float) -> void:
	meltdown_timer -= delta

	if meltdown_timer <= 0.0:
		_recover_from_meltdown()


## Recover from meltdown.
func _recover_from_meltdown() -> void:
	is_meltdown = false
	meltdown_timer = 0.0
	heat_level = POST_MELTDOWN_HEAT
	is_production_enabled = true

	meltdown_recovered.emit(factory_id)
	heat_changed.emit(factory_id, heat_level)


## Force meltdown (for testing/events).
func force_meltdown() -> void:
	if not is_meltdown:
		heat_level = MAX_HEAT
		_trigger_meltdown()


## Force recovery (for testing/events).
func force_recovery() -> void:
	if is_meltdown:
		_recover_from_meltdown()


## Get heat percentage (0-100).
func get_heat_percentage() -> float:
	return heat_level * 100.0


## Get overclock percentage above normal (0-100).
func get_overclock_percentage() -> float:
	return (overclock_level - MIN_OVERCLOCK) / (MAX_OVERCLOCK - MIN_OVERCLOCK) * 100.0


## Get remaining meltdown time.
func get_meltdown_remaining() -> float:
	return meltdown_timer if is_meltdown else 0.0


## Get meltdown progress (0-1, 1 = recovered).
func get_meltdown_progress() -> float:
	if not is_meltdown:
		return 1.0
	return 1.0 - (meltdown_timer / MELTDOWN_DURATION)


## Check if can overclock.
func can_overclock() -> bool:
	return not is_meltdown


## Check if production is enabled.
func can_produce() -> bool:
	return is_production_enabled and not is_meltdown


## Reset to default state.
func reset() -> void:
	overclock_level = MIN_OVERCLOCK
	heat_level = MIN_HEAT
	is_meltdown = false
	meltdown_timer = 0.0
	is_production_enabled = true


## Serialization.
func to_dict() -> Dictionary:
	return {
		"factory_id": factory_id,
		"overclock_level": overclock_level,
		"heat_level": heat_level,
		"is_meltdown": is_meltdown,
		"meltdown_timer": meltdown_timer,
		"is_production_enabled": is_production_enabled
	}


func from_dict(data: Dictionary) -> void:
	factory_id = data.get("factory_id", -1)
	overclock_level = data.get("overclock_level", MIN_OVERCLOCK)
	heat_level = data.get("heat_level", MIN_HEAT)
	is_meltdown = data.get("is_meltdown", false)
	meltdown_timer = data.get("meltdown_timer", 0.0)
	is_production_enabled = data.get("is_production_enabled", true)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"factory_id": factory_id,
		"overclock": overclock_level,
		"heat": heat_level,
		"heat_percent": get_heat_percentage(),
		"is_meltdown": is_meltdown,
		"meltdown_remaining": get_meltdown_remaining(),
		"can_produce": can_produce()
	}
