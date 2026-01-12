class_name ThreatCalculator
extends RefCounted
## ThreatCalculator tracks and calculates threat values for enemies.

signal threat_level_changed(unit_id: int, old_level: float, new_level: float)
signal high_threat_detected(unit_id: int, threat: float)

## Configuration
const DPS_WEIGHT := 0.6
const RECENT_DAMAGE_WEIGHT := 0.4
const DAMAGE_MEMORY_WINDOW := 10.0  ## Seconds
const THREAT_DECAY_TIME := 5.0  ## 50% decay per 5 seconds
const HIGH_THREAT_THRESHOLD := 50.0
const ENGAGEMENT_RANGE := 30.0

## Threat data per enemy (enemy_id -> threat_data)
var _threat_data: Dictionary = {}

## Damage history (enemy_id -> Array of {timestamp, damage})
var _damage_history: Dictionary = {}

## Configurable decay rate
var threat_decay_rate: float = 5.0


func _init() -> void:
	pass


## Record damage from enemy unit.
func record_damage(enemy_id: int, damage: float, enemy_dps: float = 0.0) -> void:
	_ensure_threat_data(enemy_id)

	var current_time := Time.get_ticks_msec() / 1000.0

	# Add to damage history
	if not _damage_history.has(enemy_id):
		_damage_history[enemy_id] = []

	_damage_history[enemy_id].append({
		"timestamp": current_time,
		"damage": damage
	})

	# Update DPS if provided
	if enemy_dps > 0:
		_threat_data[enemy_id]["current_dps"] = enemy_dps

	# Recalculate threat
	_update_threat(enemy_id)


## Update DPS for enemy.
func update_enemy_dps(enemy_id: int, damage_per_hit: float, attack_speed: float) -> void:
	_ensure_threat_data(enemy_id)
	_threat_data[enemy_id]["current_dps"] = damage_per_hit * attack_speed
	_update_threat(enemy_id)


## Update all threats (called each frame).
func update(delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0

	# Clean old damage history and apply decay
	for enemy_id in _threat_data.keys():
		_clean_damage_history(enemy_id, current_time)
		_apply_threat_decay(enemy_id, delta)
		_update_threat(enemy_id)


## Ensure threat data exists for enemy.
func _ensure_threat_data(enemy_id: int) -> void:
	if not _threat_data.has(enemy_id):
		_threat_data[enemy_id] = {
			"current_dps": 0.0,
			"recent_damage": 0.0,
			"total_threat": 0.0,
			"last_damage_time": 0.0
		}


## Clean old damage history.
func _clean_damage_history(enemy_id: int, current_time: float) -> void:
	if not _damage_history.has(enemy_id):
		return

	var history: Array = _damage_history[enemy_id]
	var cutoff := current_time - DAMAGE_MEMORY_WINDOW

	while not history.is_empty() and history[0]["timestamp"] < cutoff:
		history.pop_front()


## Apply threat decay.
func _apply_threat_decay(enemy_id: int, delta: float) -> void:
	var data: Dictionary = _threat_data[enemy_id]
	var current_time := Time.get_ticks_msec() / 1000.0
	var time_since_damage := current_time - data["last_damage_time"]

	if time_since_damage > threat_decay_rate:
		# Apply exponential decay
		var decay_factor := pow(0.5, delta / threat_decay_rate)
		data["recent_damage"] *= decay_factor


## Update threat calculation.
func _update_threat(enemy_id: int) -> void:
	var data: Dictionary = _threat_data[enemy_id]
	var old_threat: float = data["total_threat"]

	# Calculate recent damage total
	var recent_damage := 0.0
	if _damage_history.has(enemy_id):
		for entry in _damage_history[enemy_id]:
			recent_damage += entry["damage"]

	data["recent_damage"] = recent_damage

	# Calculate hybrid threat
	var dps_threat: float = data["current_dps"]
	var damage_threat: float = data["recent_damage"]

	data["total_threat"] = dps_threat * DPS_WEIGHT + damage_threat * RECENT_DAMAGE_WEIGHT

	# Emit signals if significant change
	if absf(old_threat - data["total_threat"]) > 1.0:
		threat_level_changed.emit(enemy_id, old_threat, data["total_threat"])

		if data["total_threat"] >= HIGH_THREAT_THRESHOLD:
			high_threat_detected.emit(enemy_id, data["total_threat"])


## Get threat value for enemy.
func get_threat(enemy_id: int) -> float:
	if not _threat_data.has(enemy_id):
		return 0.0
	return _threat_data[enemy_id]["total_threat"]


## Get highest threat enemy from list.
func get_highest_threat(enemy_ids: Array[int]) -> int:
	var highest_threat := 0.0
	var highest_id := -1

	for enemy_id in enemy_ids:
		var threat := get_threat(enemy_id)
		if threat > highest_threat:
			highest_threat = threat
			highest_id = enemy_id

	return highest_id


## Get enemies sorted by threat.
func get_enemies_by_threat(enemy_ids: Array[int]) -> Array[int]:
	var threat_list: Array[Dictionary] = []

	for enemy_id in enemy_ids:
		threat_list.append({
			"id": enemy_id,
			"threat": get_threat(enemy_id)
		})

	threat_list.sort_custom(func(a, b): return a["threat"] > b["threat"])

	var sorted: Array[int] = []
	for entry in threat_list:
		sorted.append(entry["id"])

	return sorted


## Clear threat data for enemy.
func clear_enemy(enemy_id: int) -> void:
	_threat_data.erase(enemy_id)
	_damage_history.erase(enemy_id)


## Reset all threat data.
func reset() -> void:
	_threat_data.clear()
	_damage_history.clear()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var threat_data_serialized: Dictionary = {}
	for enemy_id in _threat_data:
		threat_data_serialized[str(enemy_id)] = _threat_data[enemy_id].duplicate()

	var history_serialized: Dictionary = {}
	for enemy_id in _damage_history:
		history_serialized[str(enemy_id)] = _damage_history[enemy_id].duplicate()

	return {
		"threat_data": threat_data_serialized,
		"damage_history": history_serialized,
		"threat_decay_rate": threat_decay_rate
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_threat_data.clear()
	for enemy_id_str in data.get("threat_data", {}):
		_threat_data[int(enemy_id_str)] = data["threat_data"][enemy_id_str].duplicate()

	_damage_history.clear()
	for enemy_id_str in data.get("damage_history", {}):
		_damage_history[int(enemy_id_str)] = data["damage_history"][enemy_id_str].duplicate()

	threat_decay_rate = data.get("threat_decay_rate", 5.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var high_threats := 0
	var total_threat := 0.0

	for enemy_id in _threat_data:
		var threat: float = _threat_data[enemy_id]["total_threat"]
		total_threat += threat
		if threat >= HIGH_THREAT_THRESHOLD:
			high_threats += 1

	return {
		"tracked_enemies": _threat_data.size(),
		"high_threat_count": high_threats,
		"total_threat": "%.1f" % total_threat,
		"decay_rate": "%.1fs" % threat_decay_rate
	}
