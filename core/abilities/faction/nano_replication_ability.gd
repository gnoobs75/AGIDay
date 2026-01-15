class_name NanoReplicationAbility
extends RefCounted
## NanoReplicationAbility provides passive health regeneration to Aether Swarm units
## when near allies. The more allies nearby, the faster the healing.
## Passive ability - always active for registered units.

signal healing_applied(unit_id: int, amount: float, nearby_count: int)
signal unit_fully_healed(unit_id: int)

## Configuration
const ABILITY_ID := "nano_replication"
const BASE_HEAL_PER_SECOND := 2.0  ## Base HP/s when 1+ allies nearby
const HEAL_PER_ALLY := 0.5  ## Additional HP/s per nearby ally
const MAX_HEAL_PER_SECOND := 15.0  ## Cap on healing rate
const HEAL_RADIUS := 8.0  ## Distance to count allies
const MIN_ALLIES_FOR_HEAL := 1  ## Need at least 1 ally nearby to heal

## Unit data (unit_id -> heal_data)
var _unit_data: Dictionary = {}

## Spatial grid for nearby unit queries
var _spatial_grid: Dictionary = {}
const CELL_SIZE := 8.0

## Stats tracking
var _total_healing_done: float = 0.0
var _units_fully_healed: int = 0

## Callbacks
var _get_unit_health: Callable  ## (unit_id) -> float
var _get_unit_max_health: Callable  ## (unit_id) -> float
var _apply_healing: Callable  ## (unit_id, amount) -> void


func _init() -> void:
	pass


## Set callbacks.
func set_get_unit_health(callback: Callable) -> void:
	_get_unit_health = callback


func set_get_unit_max_health(callback: Callable) -> void:
	_get_unit_max_health = callback


func set_apply_healing(callback: Callable) -> void:
	_apply_healing = callback


## Register unit for nano replication.
func register_unit(unit_id: int) -> void:
	_unit_data[unit_id] = {
		"nearby_count": 0,
		"heal_rate": 0.0,
		"total_healed": 0.0
	}


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_data.erase(unit_id)


## Update healing for all units.
func update(delta: float, positions: Dictionary) -> void:
	# Rebuild spatial grid
	_rebuild_spatial_grid(positions)

	# Update each unit's healing
	for unit_id in _unit_data:
		if not positions.has(unit_id):
			continue

		var unit_pos: Vector3 = positions[unit_id]
		var nearby_count := _count_nearby_allies(unit_id, unit_pos, positions)

		var data: Dictionary = _unit_data[unit_id]
		data["nearby_count"] = nearby_count

		# Calculate heal rate
		if nearby_count >= MIN_ALLIES_FOR_HEAL:
			data["heal_rate"] = minf(
				BASE_HEAL_PER_SECOND + (nearby_count * HEAL_PER_ALLY),
				MAX_HEAL_PER_SECOND
			)
		else:
			data["heal_rate"] = 0.0

		# Apply healing if unit is damaged
		if data["heal_rate"] > 0.0:
			_apply_healing_to_unit(unit_id, data, delta)


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


## Count nearby allies within heal radius.
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
				if unit_pos.distance_to(other_pos) <= HEAL_RADIUS:
					count += 1

	return count


## Apply healing to a unit.
func _apply_healing_to_unit(unit_id: int, data: Dictionary, delta: float) -> void:
	# Check if unit needs healing
	var current_health := 0.0
	var max_health := 100.0

	if _get_unit_health.is_valid():
		current_health = _get_unit_health.call(unit_id)
	if _get_unit_max_health.is_valid():
		max_health = _get_unit_max_health.call(unit_id)

	if current_health >= max_health:
		return  # Already full health

	# Calculate healing amount
	var heal_amount: float = data["heal_rate"] * delta
	var actual_heal: float = minf(heal_amount, max_health - current_health)

	if actual_heal <= 0:
		return

	# Apply healing
	if _apply_healing.is_valid():
		_apply_healing.call(unit_id, actual_heal)

	# Track stats
	data["total_healed"] += actual_heal
	_total_healing_done += actual_heal

	healing_applied.emit(unit_id, actual_heal, data["nearby_count"])

	# Check if fully healed
	if current_health + actual_heal >= max_health:
		_units_fully_healed += 1
		unit_fully_healed.emit(unit_id)


## Get current heal rate for unit.
func get_heal_rate(unit_id: int) -> float:
	if not _unit_data.has(unit_id):
		return 0.0
	return _unit_data[unit_id]["heal_rate"]


## Get nearby ally count for unit.
func get_nearby_count(unit_id: int) -> int:
	if not _unit_data.has(unit_id):
		return 0
	return _unit_data[unit_id]["nearby_count"]


## Check if unit is healing.
func is_healing(unit_id: int) -> bool:
	if not _unit_data.has(unit_id):
		return false
	return _unit_data[unit_id]["heal_rate"] > 0.0


## Get ability configuration.
func get_config() -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"base_heal_per_second": BASE_HEAL_PER_SECOND,
		"heal_per_ally": HEAL_PER_ALLY,
		"max_heal_per_second": MAX_HEAL_PER_SECOND,
		"heal_radius": HEAL_RADIUS,
		"min_allies": MIN_ALLIES_FOR_HEAL
	}


## Get stats for this ability.
func get_stats() -> Dictionary:
	return {
		"total_healing_done": _total_healing_done,
		"units_fully_healed": _units_fully_healed,
		"tracked_units": _unit_data.size()
	}


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var unit_heal_data: Dictionary = {}
	for unit_id in _unit_data:
		unit_heal_data[str(unit_id)] = _unit_data[unit_id].duplicate()

	return {
		"unit_data": unit_heal_data,
		"total_healing_done": _total_healing_done,
		"units_fully_healed": _units_fully_healed
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_total_healing_done = data.get("total_healing_done", 0.0)
	_units_fully_healed = data.get("units_fully_healed", 0)

	_unit_data.clear()
	for unit_id_str in data.get("unit_data", {}):
		_unit_data[int(unit_id_str)] = data["unit_data"][unit_id_str].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var healing_units := 0
	var total_heal_rate := 0.0

	for unit_id in _unit_data:
		if _unit_data[unit_id]["heal_rate"] > 0:
			healing_units += 1
			total_heal_rate += _unit_data[unit_id]["heal_rate"]

	return {
		"tracked_units": _unit_data.size(),
		"healing_units": healing_units,
		"total_heal_rate": "%.1f HP/s" % total_heal_rate,
		"total_healed": "%.0f HP" % _total_healing_done
	}
