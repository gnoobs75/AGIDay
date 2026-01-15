class_name EtherCloakAbility
extends RefCounted
## EtherCloakAbility makes Aether Swarm units temporarily invisible and untargetable.
## C hotkey, 50 REE cost, 20s cooldown, 4s duration.
## Cloaked units cannot be targeted by enemies but can still attack.

signal cloak_started(unit_ids: Array[int], duration: float)
signal cloak_ended(unit_ids: Array[int])
signal unit_cloaked(unit_id: int)
signal unit_revealed(unit_id: int)

## Configuration
const ABILITY_ID := "ether_cloak"
const HOTKEY := "C"
const REE_COST := 50.0
const COOLDOWN := 20.0
const DURATION := 4.0
const CLOAK_ALPHA := 0.15  ## Visual transparency when cloaked
const MAX_CLOAKED_UNITS := 100

## Cloaked units (unit_id -> cloak_data)
var _cloaked_units: Dictionary = {}

## Cooldown remaining
var _cooldown_remaining: float = 0.0

## Stats tracking
var _total_cloaks: int = 0
var _total_attacks_while_cloaked: int = 0

## Callbacks
var _get_faction_units: Callable  ## (faction_id) -> Array[int]
var _set_unit_targetable: Callable  ## (unit_id, targetable: bool) -> void
var _set_unit_visual_cloak: Callable  ## (unit_id, cloaked: bool, alpha: float) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_faction_units(callback: Callable) -> void:
	_get_faction_units = callback


func set_unit_targetable(callback: Callable) -> void:
	_set_unit_targetable = callback


func set_unit_visual_cloak(callback: Callable) -> void:
	_set_unit_visual_cloak = callback


## Check if ability can be used.
func can_activate() -> Dictionary:
	var result := {
		"can_activate": true,
		"reason": ""
	}

	if _cooldown_remaining > 0:
		result["can_activate"] = false
		result["reason"] = "On cooldown (%.1fs)" % _cooldown_remaining
		return result

	return result


## Activate ether cloak for all Aether Swarm units.
func activate(faction_id: String) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	# Get all faction units
	var unit_ids: Array[int] = []
	if _get_faction_units.is_valid():
		var result: Array = _get_faction_units.call(faction_id)
		for u in result:
			if unit_ids.size() < MAX_CLOAKED_UNITS:
				unit_ids.append(u)

	if unit_ids.is_empty():
		return false

	# Cloak all units
	for unit_id in unit_ids:
		_cloak_unit(unit_id)

	# Start cooldown
	_cooldown_remaining = COOLDOWN
	_total_cloaks += 1

	cloak_started.emit(unit_ids, DURATION)

	return true


## Activate cloak for specific units.
func activate_for_units(unit_ids: Array[int]) -> bool:
	var validation := can_activate()
	if not validation["can_activate"]:
		return false

	if unit_ids.is_empty():
		return false

	# Cloak specified units
	for unit_id in unit_ids:
		if _cloaked_units.size() < MAX_CLOAKED_UNITS:
			_cloak_unit(unit_id)

	# Start cooldown
	_cooldown_remaining = COOLDOWN
	_total_cloaks += 1

	cloak_started.emit(unit_ids, DURATION)

	return true


## Cloak a unit.
func _cloak_unit(unit_id: int) -> void:
	if _cloaked_units.has(unit_id):
		# Refresh duration if already cloaked
		_cloaked_units[unit_id]["remaining"] = DURATION
		return

	_cloaked_units[unit_id] = {
		"remaining": DURATION,
		"attacks_while_cloaked": 0
	}

	# Make unit untargetable
	if _set_unit_targetable.is_valid():
		_set_unit_targetable.call(unit_id, false)

	# Set visual effect (transparent/shimmer)
	if _set_unit_visual_cloak.is_valid():
		_set_unit_visual_cloak.call(unit_id, true, CLOAK_ALPHA)

	unit_cloaked.emit(unit_id)


## Reveal a unit (end cloak).
func _reveal_unit(unit_id: int) -> void:
	if not _cloaked_units.has(unit_id):
		return

	_total_attacks_while_cloaked += _cloaked_units[unit_id]["attacks_while_cloaked"]
	_cloaked_units.erase(unit_id)

	# Make unit targetable again
	if _set_unit_targetable.is_valid():
		_set_unit_targetable.call(unit_id, true)

	# Reset visual effect
	if _set_unit_visual_cloak.is_valid():
		_set_unit_visual_cloak.call(unit_id, false, 1.0)

	unit_revealed.emit(unit_id)


## Check if unit is cloaked.
func is_cloaked(unit_id: int) -> bool:
	return _cloaked_units.has(unit_id)


## Record attack while cloaked (for stats).
func record_attack(unit_id: int) -> void:
	if _cloaked_units.has(unit_id):
		_cloaked_units[unit_id]["attacks_while_cloaked"] += 1


## Update cloak durations.
func update(delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Update cloaked units
	var to_reveal: Array[int] = []

	for unit_id in _cloaked_units:
		var data: Dictionary = _cloaked_units[unit_id]
		data["remaining"] -= delta

		if data["remaining"] <= 0:
			to_reveal.append(unit_id)

	# Reveal expired cloaks
	for unit_id in to_reveal:
		_reveal_unit(unit_id)

	if not to_reveal.is_empty():
		cloak_ended.emit(to_reveal)


## Cancel all cloaks.
func cancel_all(reason: String = "manual") -> void:
	var unit_ids: Array[int] = []
	for unit_id in _cloaked_units:
		unit_ids.append(unit_id)

	for unit_id in unit_ids:
		_reveal_unit(unit_id)


## Get cloaked unit count.
func get_cloaked_count() -> int:
	return _cloaked_units.size()


## Get remaining cooldown.
func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_remaining)


## Is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0


## Get remaining cloak time for unit.
func get_cloak_remaining(unit_id: int) -> float:
	if not _cloaked_units.has(unit_id):
		return 0.0
	return maxf(0.0, _cloaked_units[unit_id]["remaining"])


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"hotkey": HOTKEY,
		"ree_cost": REE_COST,
		"cooldown": COOLDOWN,
		"duration": DURATION,
		"cloak_alpha": CLOAK_ALPHA,
		"max_cloaked_units": MAX_CLOAKED_UNITS
	}


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"total_cloaks": _total_cloaks,
		"total_attacks_while_cloaked": _total_attacks_while_cloaked,
		"avg_attacks_per_cloak": float(_total_attacks_while_cloaked) / maxf(1.0, _total_cloaks)
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var cloaked_data: Dictionary = {}
	for unit_id in _cloaked_units:
		cloaked_data[str(unit_id)] = _cloaked_units[unit_id].duplicate()

	return {
		"cooldown_remaining": _cooldown_remaining,
		"cloaked_units": cloaked_data,
		"total_cloaks": _total_cloaks,
		"total_attacks_while_cloaked": _total_attacks_while_cloaked
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_cooldown_remaining = data.get("cooldown_remaining", 0.0)
	_total_cloaks = data.get("total_cloaks", 0)
	_total_attacks_while_cloaked = data.get("total_attacks_while_cloaked", 0)

	_cloaked_units.clear()
	for unit_id_str in data.get("cloaked_units", {}):
		_cloaked_units[int(unit_id_str)] = data["cloaked_units"][unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"cloaked_units": _cloaked_units.size(),
		"cooldown": "%.1fs" % _cooldown_remaining if _cooldown_remaining > 0 else "Ready",
		"total_cloaks": _total_cloaks
	}
