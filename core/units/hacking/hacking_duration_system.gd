class_name HackingDurationSystem
extends RefCounted
## HackingDurationSystem coordinates timers and unhacking mechanics.
## Provides unified API for hack duration management.

signal hack_timer_started(unit_id: int, duration: float)
signal hack_timer_expired(unit_id: int)
signal hack_timer_cancelled(unit_id: int)
signal unhack_by_damage(unit_id: int, attacker_faction: String)
signal hack_progress_changed(unit_id: int, progress: float)

## Timer manager
var _timer: HackedUnitTimer = null

## Unhacking mechanic
var _unhacking: UnhackingMechanic = null

## Hacking system manager reference
var _hacking_manager: HackingSystemManager = null

## Hack duration
var hack_duration: float = 30.0


func _init() -> void:
	_timer = HackedUnitTimer.new()
	_unhacking = UnhackingMechanic.new()

	# Connect timer signals
	_timer.hack_expired.connect(_on_hack_expired)
	_timer.hack_progress_updated.connect(_on_progress_updated)

	# Connect unhacking signals
	_unhacking.unit_unhacked.connect(_on_unit_unhacked_by_damage)


## Set hacking manager reference.
func set_hacking_manager(manager: HackingSystemManager) -> void:
	_hacking_manager = manager

	# Set unhack callback
	_unhacking.set_unhack_callback(func(unit_id: int):
		if _hacking_manager != null:
			_hacking_manager.restore_unit(unit_id)
	)

	# Set unit info callback
	_unhacking.set_unit_info_callback(func(unit_id: int) -> Dictionary:
		if _hacking_manager == null:
			return {}

		var component := _hacking_manager.get_unit_component(unit_id)
		if component == null:
			return {}

		return {
			"original_faction": component.get_original_faction(),
			"current_owner": component.get_current_owner(),
			"is_hacked": component.is_hacked()
		}
	)


## Start hack timer for unit.
func start_hack_timer(unit_id: int, duration: float = -1.0) -> void:
	var actual_duration := duration if duration > 0 else hack_duration
	_timer.start_timer(unit_id, actual_duration)
	hack_timer_started.emit(unit_id, actual_duration)


## Cancel hack timer (unit destroyed, mind controlled, etc).
func cancel_timer(unit_id: int) -> void:
	if _timer.has_timer(unit_id):
		_timer.stop_timer(unit_id)
		hack_timer_cancelled.emit(unit_id)


## Process damage event.
func process_damage(unit_id: int, attacker_faction: String, damage: float) -> bool:
	var unhacked := _unhacking.process_damage(unit_id, attacker_faction, damage)

	if unhacked:
		# Timer will be cancelled when state changes
		_timer.stop_timer(unit_id)
		unhack_by_damage.emit(unit_id, attacker_faction)

	return unhacked


## Update system.
func update(delta: float) -> void:
	var expired := _timer.update(delta)

	for unit_id in expired:
		# Auto-unhack expired units
		if _hacking_manager != null:
			_hacking_manager.restore_unit(unit_id)


## Handle timer expiration.
func _on_hack_expired(unit_id: int) -> void:
	hack_timer_expired.emit(unit_id)


## Handle progress update.
func _on_progress_updated(unit_id: int, progress: float, _remaining: float) -> void:
	hack_progress_changed.emit(unit_id, progress)


## Handle unhacking by damage.
func _on_unit_unhacked_by_damage(unit_id: int, _by_damage: bool) -> void:
	# Timer already stopped in process_damage
	pass


## Get remaining time for unit.
func get_remaining_time(unit_id: int) -> float:
	return _timer.get_remaining_time(unit_id)


## Get hack progress (0-1).
func get_hack_progress(unit_id: int) -> float:
	return _timer.get_hack_progress(unit_id)


## Check if unit has active timer.
func is_timed(unit_id: int) -> bool:
	return _timer.has_timer(unit_id)


## Get timer manager.
func get_timer() -> HackedUnitTimer:
	return _timer


## Get unhacking mechanic.
func get_unhacking() -> UnhackingMechanic:
	return _unhacking


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"hack_duration": hack_duration,
		"timer": _timer.to_dict(),
		"unhacking": _unhacking.to_dict()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	hack_duration = data.get("hack_duration", 30.0)
	_timer.from_dict(data.get("timer", {}))
	_unhacking.from_dict(data.get("unhacking", {}))


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"hack_duration": hack_duration,
		"timer": _timer.get_summary(),
		"unhacking": _unhacking.get_summary()
	}
