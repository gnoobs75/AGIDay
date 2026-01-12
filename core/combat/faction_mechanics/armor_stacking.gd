class_name ArmorStacking
extends RefCounted
## ArmorStacking implements Tank faction's shared armor and damage distribution.
## Nearby tanks share 30% of incoming damage, armor stacks up to 80% reduction.

signal armor_changed(unit_id: int, old_armor: float, new_armor: float)
signal damage_distributed(primary_id: int, distributed_ids: Array[int], damage_each: float)

## Configuration
const STACKING_RADIUS := 8.0
const ARMOR_SHARE_RATE := 0.25  ## 25% of nearby tank's base armor added
const DAMAGE_DISTRIBUTION := 0.30  ## 30% distributed to nearby tanks
const MAX_EFFECTIVE_ARMOR := 0.80  ## 80% max damage reduction

## Unit armor data (unit_id -> armor_data)
var _unit_armor: Dictionary = {}

## Spatial grid
var _spatial_grid: Dictionary = {}
const CELL_SIZE := 8.0


func _init() -> void:
	pass


## Register unit with base armor.
func register_unit(unit_id: int, base_armor: float) -> void:
	_unit_armor[unit_id] = {
		"base_armor": base_armor,
		"effective_armor": base_armor,
		"nearby_tanks": []
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_armor.erase(unit_id)


## Update armor stacking for all units.
func update(positions: Dictionary) -> void:
	# Rebuild spatial grid
	_rebuild_spatial_grid(positions)

	# Update each unit's effective armor
	for unit_id in _unit_armor:
		_update_unit_armor(unit_id, positions)


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


## Update armor for single unit.
func _update_unit_armor(unit_id: int, positions: Dictionary) -> void:
	if not positions.has(unit_id) or not _unit_armor.has(unit_id):
		return

	var unit_pos: Vector3 = positions[unit_id]
	var data: Dictionary = _unit_armor[unit_id]
	var old_armor: float = data["effective_armor"]

	# Find nearby tanks
	var nearby := _find_nearby_tanks(unit_id, unit_pos, positions)
	data["nearby_tanks"] = nearby

	# Calculate shared armor
	var shared_armor := 0.0
	for other_id in nearby:
		if _unit_armor.has(other_id):
			var other_base: float = _unit_armor[other_id]["base_armor"]
			shared_armor += other_base * ARMOR_SHARE_RATE

	# Calculate effective armor (capped)
	data["effective_armor"] = minf(data["base_armor"] + shared_armor, MAX_EFFECTIVE_ARMOR)

	if absf(old_armor - data["effective_armor"]) > 0.001:
		armor_changed.emit(unit_id, old_armor, data["effective_armor"])


## Find nearby tanks within stacking radius.
func _find_nearby_tanks(unit_id: int, unit_pos: Vector3, positions: Dictionary) -> Array[int]:
	var nearby: Array[int] = []
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

				if not _unit_armor.has(other_id):
					continue

				if not positions.has(other_id):
					continue

				var other_pos: Vector3 = positions[other_id]
				if unit_pos.distance_to(other_pos) <= STACKING_RADIUS:
					nearby.append(other_id)

	return nearby


## Get effective armor for unit.
func get_effective_armor(unit_id: int) -> float:
	if not _unit_armor.has(unit_id):
		return 0.0
	return _unit_armor[unit_id]["effective_armor"]


## Process incoming damage with distribution.
func process_damage(target_id: int, incoming_damage: float) -> Dictionary:
	if not _unit_armor.has(target_id):
		return {"primary_damage": incoming_damage, "distributed": {}}

	var data: Dictionary = _unit_armor[target_id]
	var nearby: Array = data["nearby_tanks"]

	# Calculate armor reduction
	var armor := data["effective_armor"]
	var reduced_damage := incoming_damage * (1.0 - armor)

	# If no nearby tanks, primary takes all
	if nearby.is_empty():
		return {"primary_damage": reduced_damage, "distributed": {}}

	# Distribute damage
	var primary_damage := reduced_damage * (1.0 - DAMAGE_DISTRIBUTION)
	var distributed_total := reduced_damage * DAMAGE_DISTRIBUTION
	var damage_per_tank := distributed_total / float(nearby.size())

	var distributed: Dictionary = {}
	var distributed_array: Array[int] = []

	for other_id in nearby:
		distributed[other_id] = damage_per_tank
		distributed_array.append(other_id)

	damage_distributed.emit(target_id, distributed_array, damage_per_tank)

	return {
		"primary_damage": primary_damage,
		"distributed": distributed
	}


## Set base armor for unit.
func set_base_armor(unit_id: int, base_armor: float) -> void:
	if _unit_armor.has(unit_id):
		_unit_armor[unit_id]["base_armor"] = base_armor


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var armor_data: Dictionary = {}
	for unit_id in _unit_armor:
		var data: Dictionary = _unit_armor[unit_id]
		armor_data[str(unit_id)] = {
			"base_armor": data["base_armor"],
			"effective_armor": data["effective_armor"],
			"nearby_tanks": data["nearby_tanks"].duplicate()
		}

	return {"unit_armor": armor_data}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_armor.clear()
	for unit_id_str in data.get("unit_armor", {}):
		var armor_data: Dictionary = data["unit_armor"][unit_id_str]
		var nearby: Array[int] = []
		for n in armor_data.get("nearby_tanks", []):
			nearby.append(n)

		_unit_armor[int(unit_id_str)] = {
			"base_armor": armor_data["base_armor"],
			"effective_armor": armor_data["effective_armor"],
			"nearby_tanks": nearby
		}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_armor := 0.0
	var max_armor := 0.0

	for unit_id in _unit_armor:
		var armor: float = _unit_armor[unit_id]["effective_armor"]
		total_armor += armor
		max_armor = maxf(max_armor, armor)

	return {
		"tracked_units": _unit_armor.size(),
		"avg_armor": "%.1f%%" % (total_armor / maxf(1.0, _unit_armor.size()) * 100),
		"max_armor": "%.1f%%" % (max_armor * 100),
		"radius": STACKING_RADIUS
	}
