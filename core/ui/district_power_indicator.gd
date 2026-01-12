class_name DistrictPowerIndicator
extends RefCounted
## DistrictPowerIndicator shows power status for a single district.

signal blackout_started(district_id: int)
signal power_restored(district_id: int)

## Indicator colors
const POWERED_COLOR := Color.GREEN
const LOW_POWER_COLOR := Color.YELLOW
const BLACKOUT_COLOR := Color.RED

## Low power threshold
const LOW_POWER_THRESHOLD := 0.5  ## 50% power ratio

## Indicator sizing
const INDICATOR_SIZE := Vector2(16, 16)
const PULSE_SPEED := 2.0

## State
var _district_id := 0
var _is_powered := true
var _power_ratio := 1.0
var _was_powered := true

## UI components
var _container: Control = null
var _indicator: ColorRect = null
var _pulse_tween: Tween = null


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, district_id: int, position: Vector2 = Vector2.ZERO) -> Control:
	_district_id = district_id

	# Container
	_container = Control.new()
	_container.name = "DistrictPowerIndicator_%d" % district_id
	_container.custom_minimum_size = INDICATOR_SIZE
	_container.position = position
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Indicator
	_indicator = ColorRect.new()
	_indicator.custom_minimum_size = INDICATOR_SIZE
	_indicator.color = POWERED_COLOR
	_container.add_child(_indicator)

	parent.add_child(_container)
	return _container


## Set power status.
func set_powered(powered: bool, power_ratio: float = 1.0) -> void:
	_was_powered = _is_powered
	_is_powered = powered
	_power_ratio = clampf(power_ratio, 0.0, 1.0)

	_update_display()

	# Emit signals on state change
	if not _is_powered and _was_powered:
		blackout_started.emit(_district_id)
	elif _is_powered and not _was_powered:
		power_restored.emit(_district_id)


## Update display.
func _update_display() -> void:
	if _indicator == null:
		return

	if not _is_powered:
		_indicator.color = BLACKOUT_COLOR
		_start_blackout_pulse()
	elif _power_ratio < LOW_POWER_THRESHOLD:
		_indicator.color = LOW_POWER_COLOR.lerp(BLACKOUT_COLOR, 1.0 - _power_ratio / LOW_POWER_THRESHOLD)
		_stop_pulse()
	else:
		_indicator.color = POWERED_COLOR.lerp(LOW_POWER_COLOR, 1.0 - (_power_ratio - LOW_POWER_THRESHOLD) / (1.0 - LOW_POWER_THRESHOLD))
		_stop_pulse()


## Start blackout pulse animation.
func _start_blackout_pulse() -> void:
	if _indicator == null or not is_instance_valid(_indicator):
		return

	_stop_pulse()

	_pulse_tween = _indicator.create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(_indicator, "modulate:a", 0.3, 0.5 / PULSE_SPEED)
	_pulse_tween.tween_property(_indicator, "modulate:a", 1.0, 0.5 / PULSE_SPEED)


## Stop pulse animation.
func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null

	if _indicator != null:
		_indicator.modulate.a = 1.0


## Set position.
func set_position(pos: Vector2) -> void:
	if _container != null:
		_container.position = pos


## Get district ID.
func get_district_id() -> int:
	return _district_id


## Is powered.
func is_powered() -> bool:
	return _is_powered


## Get power ratio.
func get_power_ratio() -> float:
	return _power_ratio


## Is in blackout.
func is_blackout() -> bool:
	return not _is_powered


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	_stop_pulse()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
