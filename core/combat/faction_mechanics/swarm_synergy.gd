class_name SwarmSynergy
extends RefCounted
## SwarmSynergy implements Aether Swarm's damage bonus based on nearby allies.
## 1% damage per ally within 10.0m, max 50% at 50+ allies.

signal synergy_changed(unit_id: int, old_bonus: float, new_bonus: float)

## Configuration
const SYNERGY_RADIUS := 10.0
const DAMAGE_PER_ALLY := 0.01  ## 1% per ally
const MAX_ALLIES := 50
const MAX_BONUS := 0.50  ## 50% max bonus

## Unit synergy data (unit_id -> synergy_data)
var _unit_synergy: Dictionary = {}

## Spatial grid for nearby unit queries
var _spatial_grid: Dictionary = {}
const CELL_SIZE := 10.0

## Callbacks
var _get_unit_position: Callable
var _get_unit_faction: Callable


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_faction(callback: Callable) -> void:
	_get_unit_faction = callback


## Register unit.
func register_unit(unit_id: int) -> void:
	_unit_synergy[unit_id] = {
		"nearby_count": 0,
		"synergy_bonus": 0.0
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_synergy.erase(unit_id)


## Update synergy for all units.
func update(positions: Dictionary) -> void:
	# Rebuild spatial grid
	_rebuild_spatial_grid(positions)

	# Update each unit's synergy
	for unit_id in _unit_synergy:
		_update_unit_synergy(unit_id, positions)


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


## Update synergy for single unit.
func _update_unit_synergy(unit_id: int, positions: Dictionary) -> void:
	if not positions.has(unit_id):
		return

	var unit_pos: Vector3 = positions[unit_id]
	var nearby_count := _count_nearby_allies(unit_id, unit_pos, positions)

	var data: Dictionary = _unit_synergy[unit_id]
	var old_bonus: float = data["synergy_bonus"]

	data["nearby_count"] = nearby_count
	data["synergy_bonus"] = _calculate_bonus(nearby_count)

	if absf(old_bonus - data["synergy_bonus"]) > 0.001:
		synergy_changed.emit(unit_id, old_bonus, data["synergy_bonus"])


## Count nearby allies within synergy radius.
func _count_nearby_allies(unit_id: int, unit_pos: Vector3, positions: Dictionary) -> int:
	var count := 0
	var cell_key := _get_cell_key(unit_pos)

	# Check surrounding cells
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

				# Check distance
				var other_pos: Vector3 = positions[other_id]
				if unit_pos.distance_to(other_pos) <= SYNERGY_RADIUS:
					count += 1

	return count


## Calculate synergy bonus from nearby count.
func _calculate_bonus(nearby_count: int) -> float:
	var clamped_count := mini(nearby_count, MAX_ALLIES)
	return minf(clamped_count * DAMAGE_PER_ALLY, MAX_BONUS)


## Get synergy bonus for unit.
func get_synergy_bonus(unit_id: int) -> float:
	if not _unit_synergy.has(unit_id):
		return 0.0
	return _unit_synergy[unit_id]["synergy_bonus"]


## Get nearby ally count for unit.
func get_nearby_count(unit_id: int) -> int:
	if not _unit_synergy.has(unit_id):
		return 0
	return _unit_synergy[unit_id]["nearby_count"]


## Apply synergy bonus to damage.
func apply_to_damage(unit_id: int, base_damage: float) -> float:
	var bonus := get_synergy_bonus(unit_id)
	return base_damage * (1.0 + bonus)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var synergy_data: Dictionary = {}
	for unit_id in _unit_synergy:
		synergy_data[str(unit_id)] = _unit_synergy[unit_id].duplicate()

	return {"unit_synergy": synergy_data}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_synergy.clear()
	for unit_id_str in data.get("unit_synergy", {}):
		_unit_synergy[int(unit_id_str)] = data["unit_synergy"][unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_bonus := 0.0
	var max_bonus := 0.0

	for unit_id in _unit_synergy:
		var bonus: float = _unit_synergy[unit_id]["synergy_bonus"]
		total_bonus += bonus
		max_bonus = maxf(max_bonus, bonus)

	return {
		"tracked_units": _unit_synergy.size(),
		"avg_bonus": "%.1f%%" % (total_bonus / maxf(1.0, _unit_synergy.size()) * 100),
		"max_bonus": "%.1f%%" % (max_bonus * 100),
		"radius": SYNERGY_RADIUS
	}
