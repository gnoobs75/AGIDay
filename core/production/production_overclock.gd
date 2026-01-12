class_name ProductionOverclock
extends RefCounted
## ProductionOverclock manages factory speed boosts with heat mechanics.
## Enables risk-reward overclocking with potential meltdown.

signal overclock_started(multiplier: float)
signal overclock_stopped()
signal heat_warning(heat_percent: float)
signal meltdown_started()
signal meltdown_recovered()
signal heat_changed(heat: float, max_heat: float)

## Overclock states
enum State {
	NORMAL = 0,       ## Operating at normal speed
	OVERCLOCKED = 1,  ## Operating at increased speed
	MELTDOWN = 2,     ## Disabled due to overheating
	COOLDOWN = 3      ## Cooling down after meltdown
}

## Speed multiplier range
const MIN_MULTIPLIER := 1.0
const MAX_MULTIPLIER := 2.0

## Heat thresholds
const HEAT_WARNING_THRESHOLD := 0.7   ## 70% heat warning
const HEAT_MELTDOWN_THRESHOLD := 1.0  ## 100% causes meltdown

## Current state
var state: int = State.NORMAL

## Current speed multiplier
var speed_multiplier: float = 1.0

## Target multiplier (set by player)
var target_multiplier: float = 1.0

## Current heat level
var heat: float = 0.0

## Maximum heat capacity
var max_heat: float = 100.0

## Heat generation rate per second at 2x speed
var heat_generation_rate: float = 10.0

## Heat dissipation rate per second at normal operation
var heat_dissipation_rate: float = 5.0

## Meltdown duration (seconds)
var meltdown_duration: float = 10.0

## Time remaining in meltdown
var meltdown_timer: float = 0.0

## Whether heat warning has been emitted
var _warning_emitted: bool = false


func _init() -> void:
	pass


## Set overclock target multiplier.
func set_overclock(multiplier: float) -> void:
	target_multiplier = clampf(multiplier, MIN_MULTIPLIER, MAX_MULTIPLIER)

	if target_multiplier > MIN_MULTIPLIER and state == State.NORMAL:
		state = State.OVERCLOCKED
		overclock_started.emit(target_multiplier)
	elif target_multiplier <= MIN_MULTIPLIER and state == State.OVERCLOCKED:
		state = State.NORMAL
		overclock_stopped.emit()


## Stop overclocking.
func stop_overclock() -> void:
	set_overclock(MIN_MULTIPLIER)


## Process overclock system.
func process(delta: float) -> float:
	match state:
		State.NORMAL:
			_process_normal(delta)
		State.OVERCLOCKED:
			_process_overclocked(delta)
		State.MELTDOWN:
			_process_meltdown(delta)
		State.COOLDOWN:
			_process_cooldown(delta)

	return speed_multiplier


## Process normal operation.
func _process_normal(delta: float) -> void:
	speed_multiplier = MIN_MULTIPLIER

	# Dissipate heat
	if heat > 0:
		heat = maxf(0.0, heat - heat_dissipation_rate * delta)
		heat_changed.emit(heat, max_heat)

	_warning_emitted = false


## Process overclocked operation.
func _process_overclocked(delta: float) -> void:
	# Ramp up to target multiplier
	speed_multiplier = move_toward(speed_multiplier, target_multiplier, delta)

	# Generate heat based on overclock level
	var heat_factor := (speed_multiplier - MIN_MULTIPLIER) / (MAX_MULTIPLIER - MIN_MULTIPLIER)
	heat += heat_generation_rate * heat_factor * delta
	heat_changed.emit(heat, max_heat)

	# Check heat warnings
	var heat_percent := heat / max_heat

	if heat_percent >= HEAT_WARNING_THRESHOLD and not _warning_emitted:
		heat_warning.emit(heat_percent)
		_warning_emitted = true

	# Check meltdown
	if heat >= max_heat:
		_trigger_meltdown()


## Process meltdown state.
func _process_meltdown(delta: float) -> void:
	speed_multiplier = 0.0
	meltdown_timer -= delta

	# Heat stays at max during meltdown
	heat = max_heat

	if meltdown_timer <= 0:
		state = State.COOLDOWN
		heat = max_heat * 0.5  # Start cooldown at 50% heat
		heat_changed.emit(heat, max_heat)


## Process cooldown after meltdown.
func _process_cooldown(delta: float) -> void:
	speed_multiplier = MIN_MULTIPLIER

	# Rapid cooling after meltdown
	heat = maxf(0.0, heat - heat_dissipation_rate * 2.0 * delta)
	heat_changed.emit(heat, max_heat)

	# Return to normal when cooled
	if heat <= 0:
		state = State.NORMAL
		_warning_emitted = false
		meltdown_recovered.emit()


## Trigger meltdown.
func _trigger_meltdown() -> void:
	state = State.MELTDOWN
	meltdown_timer = meltdown_duration
	target_multiplier = MIN_MULTIPLIER
	meltdown_started.emit()


## Force cool down (emergency measure).
func emergency_cooldown() -> void:
	if state == State.OVERCLOCKED:
		state = State.NORMAL
		target_multiplier = MIN_MULTIPLIER
		overclock_stopped.emit()


## Get heat percentage.
func get_heat_percent() -> float:
	if max_heat <= 0:
		return 0.0
	return heat / max_heat


## Check if overclocked.
func is_overclocked() -> bool:
	return state == State.OVERCLOCKED


## Check if in meltdown.
func is_melted_down() -> bool:
	return state == State.MELTDOWN


## Check if operational.
func is_operational() -> bool:
	return state == State.NORMAL or state == State.OVERCLOCKED


## Check if cooling down.
func is_cooling_down() -> bool:
	return state == State.COOLDOWN


## Get state name.
func get_state_name() -> String:
	match state:
		State.NORMAL: return "Normal"
		State.OVERCLOCKED: return "Overclocked"
		State.MELTDOWN: return "Meltdown"
		State.COOLDOWN: return "Cooldown"
	return "Unknown"


## Get current effective multiplier.
func get_effective_multiplier() -> float:
	return speed_multiplier


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"state": state,
		"speed_multiplier": speed_multiplier,
		"target_multiplier": target_multiplier,
		"heat": heat,
		"max_heat": max_heat,
		"heat_generation_rate": heat_generation_rate,
		"heat_dissipation_rate": heat_dissipation_rate,
		"meltdown_duration": meltdown_duration,
		"meltdown_timer": meltdown_timer
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> ProductionOverclock:
	var overclock := ProductionOverclock.new()
	overclock.state = data.get("state", State.NORMAL)
	overclock.speed_multiplier = data.get("speed_multiplier", 1.0)
	overclock.target_multiplier = data.get("target_multiplier", 1.0)
	overclock.heat = data.get("heat", 0.0)
	overclock.max_heat = data.get("max_heat", 100.0)
	overclock.heat_generation_rate = data.get("heat_generation_rate", 10.0)
	overclock.heat_dissipation_rate = data.get("heat_dissipation_rate", 5.0)
	overclock.meltdown_duration = data.get("meltdown_duration", 10.0)
	overclock.meltdown_timer = data.get("meltdown_timer", 0.0)
	return overclock


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"state": get_state_name(),
		"multiplier": "%.1fx" % speed_multiplier,
		"heat": "%.0f%%" % (get_heat_percent() * 100),
		"meltdown_timer": "%.1fs" % meltdown_timer if state == State.MELTDOWN else "n/a"
	}
