class_name UnitPool
extends RefCounted
## UnitPool manages object pools for different unit types.
## Pre-allocates units to handle 10,000+ unit peak capacity.

signal unit_acquired(unit_type: String, unit_id: int)
signal unit_released(unit_type: String, unit_id: int)
signal pool_warning(unit_type: String, message: String)
signal pools_initialized()

## Configuration
const MAX_TOTAL_UNITS := 10000
const INITIAL_POOL_SIZE := 100
const EXPANSION_SIZE := 50

## Default pool sizes per unit type
const DEFAULT_POOL_SIZES := {
	# Aether Swarm - many small units
	"aether_drone": 500,
	"aether_scout": 200,
	"aether_infiltrator": 100,
	"aether_phaser": 150,

	# OptiForge Legion - balanced horde
	"opti_grunt": 400,
	"opti_soldier": 300,
	"opti_heavy": 100,
	"opti_elite": 50,

	# Dynapods Vanguard - agile units
	"dyna_runner": 250,
	"dyna_striker": 200,
	"dyna_acrobat": 150,
	"dyna_juggernaut": 50,

	# LogiBots Colossus - fewer heavy units
	"logi_worker": 200,
	"logi_defender": 100,
	"logi_artillery": 75,
	"logi_titan": 25,

	# Human Remnant (NPC)
	"human_soldier": 150,
	"human_heavy": 50,
	"human_vehicle": 25
}

## Unit type to faction mapping
const FACTION_UNITS := {
	0: ["aether_drone", "aether_scout", "aether_infiltrator", "aether_phaser"],
	1: ["opti_grunt", "opti_soldier", "opti_heavy", "opti_elite"],
	2: ["dyna_runner", "dyna_striker", "dyna_acrobat", "dyna_juggernaut"],
	3: ["logi_worker", "logi_defender", "logi_artillery", "logi_titan"],
	4: ["human_soldier", "human_heavy", "human_vehicle"]
}

## Pools per unit type
var _pools: Dictionary = {}  ## unit_type -> ObjectPool

## Unit ID tracking
var _next_unit_id := 1
var _active_units: Dictionary = {}  ## unit_id -> {type, unit}

## Factory functions per type
var _unit_factories: Dictionary = {}

## Statistics
var _total_units_created := 0
var _peak_active_units := 0
var _current_active_units := 0


func _init() -> void:
	pass


## Initialize unit pools.
func initialize() -> void:
	_create_pools()
	pools_initialized.emit()


## Create pools for all unit types.
func _create_pools() -> void:
	for unit_type in DEFAULT_POOL_SIZES:
		var pool_size: int = DEFAULT_POOL_SIZES[unit_type]
		_create_pool_for_type(unit_type, pool_size)


## Create pool for specific unit type.
func _create_pool_for_type(unit_type: String, initial_size: int) -> void:
	var pool := ObjectPool.new(initial_size, MAX_TOTAL_UNITS)

	# Set up factory function
	var factory := func() -> Dictionary:
		return _create_unit_data(unit_type)

	# Set up reset function
	var reset := func(unit_data: Dictionary) -> void:
		_reset_unit_data(unit_data)

	pool.initialize(factory, reset, false)

	# Connect signals
	pool.pool_exhausted.connect(func(): _on_pool_exhausted(unit_type))
	pool.pool_expanded.connect(func(size): _on_pool_expanded(unit_type, size))

	_pools[unit_type] = pool


## Create unit data dictionary.
func _create_unit_data(unit_type: String) -> Dictionary:
	_total_units_created += 1

	return {
		"id": 0,  ## Assigned when acquired
		"type": unit_type,
		"faction_id": _get_faction_for_type(unit_type),
		"position": Vector3.ZERO,
		"rotation": 0.0,
		"health": 100.0,
		"max_health": 100.0,
		"is_alive": true,
		"is_active": false,
		"components": {},
		"state": "idle",
		"target_id": -1,
		"velocity": Vector3.ZERO,
		"created_at": 0,
		"last_updated": 0
	}


## Reset unit data for reuse.
func _reset_unit_data(unit_data: Dictionary) -> void:
	unit_data["id"] = 0
	unit_data["position"] = Vector3.ZERO
	unit_data["rotation"] = 0.0
	unit_data["health"] = unit_data.get("max_health", 100.0)
	unit_data["is_alive"] = true
	unit_data["is_active"] = false
	unit_data["components"] = {}
	unit_data["state"] = "idle"
	unit_data["target_id"] = -1
	unit_data["velocity"] = Vector3.ZERO
	unit_data["created_at"] = 0
	unit_data["last_updated"] = 0


## Get faction ID for unit type.
func _get_faction_for_type(unit_type: String) -> int:
	for faction_id in FACTION_UNITS:
		if unit_type in FACTION_UNITS[faction_id]:
			return faction_id
	return -1


## Acquire unit from pool.
func get_unit(unit_type: String) -> Dictionary:
	if not _pools.has(unit_type):
		push_error("UnitPool: Unknown unit type '%s'" % unit_type)
		return {}

	var pool: ObjectPool = _pools[unit_type]
	var unit_data = pool.acquire()

	if unit_data == null:
		pool_warning.emit(unit_type, "Failed to acquire unit")
		return {}

	# Assign unique ID
	var unit_id := _next_unit_id
	_next_unit_id += 1
	unit_data["id"] = unit_id
	unit_data["is_active"] = true
	unit_data["created_at"] = Time.get_ticks_msec()

	# Track active unit
	_active_units[unit_id] = {
		"type": unit_type,
		"unit": unit_data
	}

	_current_active_units += 1
	_peak_active_units = maxi(_peak_active_units, _current_active_units)

	unit_acquired.emit(unit_type, unit_id)
	return unit_data


## Return unit to pool.
func return_unit(unit_id: int) -> void:
	if not _active_units.has(unit_id):
		push_warning("UnitPool: Unit %d not found in active units" % unit_id)
		return

	var unit_info: Dictionary = _active_units[unit_id]
	var unit_type: String = unit_info["type"]
	var unit_data: Dictionary = unit_info["unit"]

	if not _pools.has(unit_type):
		push_error("UnitPool: Pool not found for type '%s'" % unit_type)
		return

	var pool: ObjectPool = _pools[unit_type]
	pool.release(unit_data)

	_active_units.erase(unit_id)
	_current_active_units -= 1

	unit_released.emit(unit_type, unit_id)


## Return unit by data reference.
func return_unit_by_data(unit_data: Dictionary) -> void:
	var unit_id: int = unit_data.get("id", -1)
	if unit_id > 0:
		return_unit(unit_id)


## Warm pools for specific faction.
func warm_faction_pools(faction_id: int, multiplier: float = 1.0) -> void:
	if not FACTION_UNITS.has(faction_id):
		return

	var unit_types: Array = FACTION_UNITS[faction_id]
	for unit_type in unit_types:
		if _pools.has(unit_type):
			var default_size: int = DEFAULT_POOL_SIZES.get(unit_type, INITIAL_POOL_SIZE)
			var target_size := int(default_size * multiplier)
			_pools[unit_type].warm(target_size)


## Warm all pools.
func warm_all_pools() -> void:
	for unit_type in _pools:
		var pool: ObjectPool = _pools[unit_type]
		var default_size: int = DEFAULT_POOL_SIZES.get(unit_type, INITIAL_POOL_SIZE)
		pool.warm(default_size)


## Get unit by ID.
func get_unit_by_id(unit_id: int) -> Dictionary:
	if _active_units.has(unit_id):
		return _active_units[unit_id]["unit"]
	return {}


## Get all active units of type.
func get_active_units_of_type(unit_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit_id in _active_units:
		var info: Dictionary = _active_units[unit_id]
		if info["type"] == unit_type:
			result.append(info["unit"])
	return result


## Get all active units of faction.
func get_active_units_of_faction(faction_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit_id in _active_units:
		var info: Dictionary = _active_units[unit_id]
		var unit_data: Dictionary = info["unit"]
		if unit_data.get("faction_id", -1) == faction_id:
			result.append(unit_data)
	return result


## Get pool for unit type.
func get_pool(unit_type: String) -> ObjectPool:
	return _pools.get(unit_type, null)


## Register custom unit type.
func register_unit_type(unit_type: String, initial_size: int = INITIAL_POOL_SIZE) -> void:
	if _pools.has(unit_type):
		push_warning("UnitPool: Unit type '%s' already registered" % unit_type)
		return

	_create_pool_for_type(unit_type, initial_size)


## Handle pool exhaustion.
func _on_pool_exhausted(unit_type: String) -> void:
	pool_warning.emit(unit_type, "Pool exhausted")


## Handle pool expansion.
func _on_pool_expanded(unit_type: String, new_size: int) -> void:
	pool_warning.emit(unit_type, "Pool expanded to %d" % new_size)


## Get statistics.
func get_statistics() -> Dictionary:
	var pool_stats: Dictionary = {}
	for unit_type in _pools:
		pool_stats[unit_type] = _pools[unit_type].get_statistics()

	return {
		"total_units_created": _total_units_created,
		"current_active_units": _current_active_units,
		"peak_active_units": _peak_active_units,
		"pool_count": _pools.size(),
		"pools": pool_stats
	}


## Get summary statistics.
func get_summary() -> Dictionary:
	var total_available := 0
	var total_active := 0

	for unit_type in _pools:
		var pool: ObjectPool = _pools[unit_type]
		total_available += pool.get_available_count()
		total_active += pool.get_active_count()

	return {
		"total_available": total_available,
		"total_active": total_active,
		"peak_active": _peak_active_units,
		"utilization": float(total_active) / float(total_available + total_active) if (total_available + total_active) > 0 else 0.0
	}


## Clear all pools.
func clear_all() -> void:
	for unit_type in _pools:
		_pools[unit_type].clear()
	_active_units.clear()
	_current_active_units = 0
	_next_unit_id = 1


## Release all active units.
func release_all_units() -> void:
	var unit_ids := _active_units.keys()
	for unit_id in unit_ids:
		return_unit(unit_id)


## Cleanup.
func cleanup() -> void:
	release_all_units()
	clear_all()
