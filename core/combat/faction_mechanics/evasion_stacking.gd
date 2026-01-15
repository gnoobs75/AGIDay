class_name EvasionStacking
extends RefCounted
## EvasionStacking implements Dynapods' dodge chance based on nearby allies.
## 2% dodge chance per nearby ally within 7.0m, max 40% at 20+ allies.

signal evasion_changed(unit_id: int, old_chance: float, new_chance: float)
signal dodge_occurred(unit_id: int, avoided_damage: float)
signal dodge_failed(unit_id: int, damage_taken: float)

## Configuration
const EVASION_RADIUS := 7.0
const DODGE_PER_ALLY := 0.02  ## 2% per ally
const MAX_ALLIES := 20
const MAX_DODGE_CHANCE := 0.40  ## 40% max

## Unit evasion data (unit_id -> evasion_data)
var _unit_evasion: Dictionary = {}

## Spatial grid
var _spatial_grid: Dictionary = {}
const CELL_SIZE := 7.0

## RNG for dodge rolls
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Register unit.
func register_unit(unit_id: int) -> void:
	_unit_evasion[unit_id] = {
		"nearby_count": 0,
		"evasion_chance": 0.0,
		"total_dodges": 0,
		"total_hits": 0
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_evasion.erase(unit_id)


## Update evasion for all units.
func update(positions: Dictionary) -> void:
	# Rebuild spatial grid
	_rebuild_spatial_grid(positions)

	# Update each unit's evasion
	for unit_id in _unit_evasion:
		_update_unit_evasion(unit_id, positions)


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


## Update evasion for single unit.
func _update_unit_evasion(unit_id: int, positions: Dictionary) -> void:
	if not positions.has(unit_id):
		return

	var unit_pos: Vector3 = positions[unit_id]
	var nearby_count := _count_nearby_allies(unit_id, unit_pos, positions)

	var data: Dictionary = _unit_evasion[unit_id]
	var old_chance: float = data["evasion_chance"]

	data["nearby_count"] = nearby_count
	data["evasion_chance"] = _calculate_evasion(nearby_count)

	if absf(old_chance - data["evasion_chance"]) > 0.001:
		evasion_changed.emit(unit_id, old_chance, data["evasion_chance"])


## Count nearby allies within evasion radius.
func _count_nearby_allies(unit_id: int, unit_pos: Vector3, positions: Dictionary) -> int:
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

				if not positions.has(other_id):
					continue

				var other_pos: Vector3 = positions[other_id]
				if unit_pos.distance_to(other_pos) <= EVASION_RADIUS:
					count += 1

	return count


## Calculate evasion chance from nearby count.
func _calculate_evasion(nearby_count: int) -> float:
	var clamped_count := mini(nearby_count, MAX_ALLIES)
	return minf(clamped_count * DODGE_PER_ALLY, MAX_DODGE_CHANCE)


## Get evasion chance for unit.
func get_evasion_chance(unit_id: int) -> float:
	if not _unit_evasion.has(unit_id):
		return 0.0
	return _unit_evasion[unit_id]["evasion_chance"]


## Roll for dodge.
func roll_dodge(unit_id: int, incoming_damage: float) -> Dictionary:
	if not _unit_evasion.has(unit_id):
		return {"dodged": false, "damage": incoming_damage}

	var data: Dictionary = _unit_evasion[unit_id]
	var evasion_chance: float = data["evasion_chance"]

	var roll := _rng.randf()

	if roll < evasion_chance:
		# Dodge successful
		data["total_dodges"] += 1
		dodge_occurred.emit(unit_id, incoming_damage)
		return {"dodged": true, "damage": 0.0}
	else:
		# Dodge failed
		data["total_hits"] += 1
		dodge_failed.emit(unit_id, incoming_damage)
		return {"dodged": false, "damage": incoming_damage}


## Get dodge statistics for unit.
func get_dodge_stats(unit_id: int) -> Dictionary:
	if not _unit_evasion.has(unit_id):
		return {"dodges": 0, "hits": 0, "rate": 0.0}

	var data: Dictionary = _unit_evasion[unit_id]
	var total: int = data["total_dodges"] + data["total_hits"]
	var rate := 0.0
	if total > 0:
		rate = float(data["total_dodges"]) / float(total)

	return {
		"dodges": data["total_dodges"],
		"hits": data["total_hits"],
		"rate": rate
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var evasion_data: Dictionary = {}
	for unit_id in _unit_evasion:
		evasion_data[str(unit_id)] = _unit_evasion[unit_id].duplicate()

	return {
		"unit_evasion": evasion_data,
		"rng_state": _rng.state
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_evasion.clear()
	for unit_id_str in data.get("unit_evasion", {}):
		_unit_evasion[int(unit_id_str)] = data["unit_evasion"][unit_id_str].duplicate()

	if data.has("rng_state"):
		_rng.state = data["rng_state"]


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_chance := 0.0
	var max_chance := 0.0
	var total_dodges := 0
	var total_hits := 0

	for unit_id in _unit_evasion:
		var data: Dictionary = _unit_evasion[unit_id]
		total_chance += data["evasion_chance"]
		max_chance = maxf(max_chance, data["evasion_chance"])
		total_dodges += data["total_dodges"]
		total_hits += data["total_hits"]

	return {
		"tracked_units": _unit_evasion.size(),
		"avg_evasion": "%.1f%%" % (total_chance / maxf(1.0, _unit_evasion.size()) * 100),
		"max_evasion": "%.1f%%" % (max_chance * 100),
		"total_dodges": total_dodges,
		"total_hits": total_hits,
		"radius": EVASION_RADIUS
	}
