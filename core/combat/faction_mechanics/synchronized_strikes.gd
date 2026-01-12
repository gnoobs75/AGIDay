class_name SynchronizedStrikes
extends RefCounted
## SynchronizedStrikes implements LogiBots' damage bonus when attacking same target.
## 10% damage per ally attacking same target within 10.0m, max 50% at 5+ allies.

signal sync_bonus_changed(unit_id: int, old_bonus: float, new_bonus: float)
signal synchronized_attack(unit_id: int, target_id: int, allies_synced: int)

## Configuration
const SYNC_RADIUS := 10.0
const DAMAGE_PER_ALLY := 0.10  ## 10% per ally
const MAX_ALLIES := 5
const MAX_BONUS := 0.50  ## 50% max bonus

## Unit sync data (unit_id -> sync_data)
var _unit_sync: Dictionary = {}

## Attack targets (unit_id -> target_id)
var _attack_targets: Dictionary = {}

## Spatial grid
var _spatial_grid: Dictionary = {}
const CELL_SIZE := 10.0


func _init() -> void:
	pass


## Register unit.
func register_unit(unit_id: int) -> void:
	_unit_sync[unit_id] = {
		"synced_allies": 0,
		"sync_bonus": 0.0,
		"target_id": -1
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_sync.erase(unit_id)
	_attack_targets.erase(unit_id)


## Set attack target for unit.
func set_attack_target(unit_id: int, target_id: int) -> void:
	_attack_targets[unit_id] = target_id
	if _unit_sync.has(unit_id):
		_unit_sync[unit_id]["target_id"] = target_id


## Clear attack target for unit.
func clear_attack_target(unit_id: int) -> void:
	_attack_targets.erase(unit_id)
	if _unit_sync.has(unit_id):
		_unit_sync[unit_id]["target_id"] = -1


## Update sync bonuses for all units.
func update(positions: Dictionary) -> void:
	# Rebuild spatial grid
	_rebuild_spatial_grid(positions)

	# Update each unit's sync bonus
	for unit_id in _unit_sync:
		_update_unit_sync(unit_id, positions)


## Rebuild spatial grid.
func _rebuild_spatial_grid(positions: Dictionary) -> void:
	_spatial_grid.clear()

	for unit_id in positions:
		var pos: Vector3 = positions[unit_id]
		var cell_key := _get_cell_key(pos)

		if not _spatial_grid.has(cell_key):
			_spatial_grid[cell_key] = []

		_spatial_grid[cell_key].append(unit_id)


## Get cell key from position.
func _get_cell_key(position: Vector3) -> String:
	var cx := int(position.x / CELL_SIZE)
	var cz := int(position.z / CELL_SIZE)
	return "%d,%d" % [cx, cz]


## Update sync bonus for single unit.
func _update_unit_sync(unit_id: int, positions: Dictionary) -> void:
	if not positions.has(unit_id):
		return

	var data: Dictionary = _unit_sync[unit_id]
	var target_id: int = _attack_targets.get(unit_id, -1)
	data["target_id"] = target_id

	var old_bonus: float = data["sync_bonus"]

	if target_id == -1:
		data["synced_allies"] = 0
		data["sync_bonus"] = 0.0
	else:
		var unit_pos: Vector3 = positions[unit_id]
		var synced := _count_synced_allies(unit_id, target_id, unit_pos, positions)
		data["synced_allies"] = synced
		data["sync_bonus"] = _calculate_bonus(synced)

	if absf(old_bonus - data["sync_bonus"]) > 0.001:
		sync_bonus_changed.emit(unit_id, old_bonus, data["sync_bonus"])


## Count allies attacking same target within sync radius.
func _count_synced_allies(unit_id: int, target_id: int, unit_pos: Vector3, positions: Dictionary) -> int:
	var count := 0
	var cell_key := _get_cell_key(unit_pos)

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var parts := cell_key.split(",")
			var cx := int(parts[0]) + dx
			var cz := int(parts[1]) + dz
			var neighbor_key := "%d,%d" % [cx, cz]

			if not _spatial_grid.has(neighbor_key):
				continue

			for other_id in _spatial_grid[neighbor_key]:
				if other_id == unit_id:
					continue

				if not _unit_sync.has(other_id):
					continue

				# Check if attacking same target
				var other_target: int = _attack_targets.get(other_id, -1)
				if other_target != target_id:
					continue

				if not positions.has(other_id):
					continue

				# Check distance
				var other_pos: Vector3 = positions[other_id]
				if unit_pos.distance_to(other_pos) <= SYNC_RADIUS:
					count += 1

	return count


## Calculate sync bonus from ally count.
func _calculate_bonus(synced_allies: int) -> float:
	var clamped_count := mini(synced_allies, MAX_ALLIES)
	return minf(clamped_count * DAMAGE_PER_ALLY, MAX_BONUS)


## Get sync bonus for unit.
func get_sync_bonus(unit_id: int) -> float:
	if not _unit_sync.has(unit_id):
		return 0.0
	return _unit_sync[unit_id]["sync_bonus"]


## Get synced ally count for unit.
func get_synced_count(unit_id: int) -> int:
	if not _unit_sync.has(unit_id):
		return 0
	return _unit_sync[unit_id]["synced_allies"]


## Apply sync bonus to damage.
func apply_to_damage(unit_id: int, base_damage: float) -> float:
	var bonus := get_sync_bonus(unit_id)
	var synced := get_synced_count(unit_id)

	if synced > 0:
		var target_id: int = _attack_targets.get(unit_id, -1)
		synchronized_attack.emit(unit_id, target_id, synced)

	return base_damage * (1.0 + bonus)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var sync_data: Dictionary = {}
	for unit_id in _unit_sync:
		sync_data[str(unit_id)] = _unit_sync[unit_id].duplicate()

	var targets_data: Dictionary = {}
	for unit_id in _attack_targets:
		targets_data[str(unit_id)] = _attack_targets[unit_id]

	return {
		"unit_sync": sync_data,
		"attack_targets": targets_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_sync.clear()
	for unit_id_str in data.get("unit_sync", {}):
		_unit_sync[int(unit_id_str)] = data["unit_sync"][unit_id_str].duplicate()

	_attack_targets.clear()
	for unit_id_str in data.get("attack_targets", {}):
		_attack_targets[int(unit_id_str)] = data["attack_targets"][unit_id_str]


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_bonus := 0.0
	var max_bonus := 0.0
	var units_with_target := 0

	for unit_id in _unit_sync:
		var data: Dictionary = _unit_sync[unit_id]
		total_bonus += data["sync_bonus"]
		max_bonus = maxf(max_bonus, data["sync_bonus"])
		if data["target_id"] != -1:
			units_with_target += 1

	return {
		"tracked_units": _unit_sync.size(),
		"units_with_target": units_with_target,
		"avg_bonus": "%.1f%%" % (total_bonus / maxf(1.0, _unit_sync.size()) * 100),
		"max_bonus": "%.1f%%" % (max_bonus * 100),
		"radius": SYNC_RADIUS
	}
