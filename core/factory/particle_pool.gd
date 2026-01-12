class_name ParticlePool
extends RefCounted
## ParticlePool manages a pool of particle emitters to avoid allocation overhead.

signal pool_exhausted()
signal emitter_returned(particle_type: String)

## Pool configuration
const DEFAULT_POOL_SIZE := 20
const MAX_POOL_SIZE := 50

## Pool storage by type
var _pools: Dictionary = {}  ## particle_type -> Array[AssemblyParticleEmitter]
var _active: Dictionary = {}  ## particle_type -> Array[AssemblyParticleEmitter]

## Pool sizes per type
var _pool_sizes: Dictionary = {}  ## particle_type -> int

## Parent node for emitters
var _parent_node: Node3D = null

## Faction theme
var _current_theme: FactionAssemblyTheme = null


func _init() -> void:
	# Initialize pools for standard types
	_init_pool(AssemblyParticleEmitter.TYPE_WELDING)
	_init_pool(AssemblyParticleEmitter.TYPE_SPARKS)
	_init_pool(AssemblyParticleEmitter.TYPE_ENERGY)


## Initialize a pool for a particle type.
func _init_pool(particle_type: String, size: int = DEFAULT_POOL_SIZE) -> void:
	_pools[particle_type] = []
	_active[particle_type] = []
	_pool_sizes[particle_type] = size


## Set parent node for particle emitters.
func set_parent(parent: Node3D) -> void:
	_parent_node = parent


## Set faction theme for all emitters.
func set_theme(theme: FactionAssemblyTheme) -> void:
	_current_theme = theme

	# Apply to all existing emitters
	for particle_type in _pools:
		for emitter in _pools[particle_type]:
			emitter.apply_theme(theme)

	for particle_type in _active:
		for emitter in _active[particle_type]:
			emitter.apply_theme(theme)


## Get a particle emitter from the pool.
func get_particle_emitter(particle_type: String) -> AssemblyParticleEmitter:
	# Ensure pool exists
	if not _pools.has(particle_type):
		_init_pool(particle_type)

	var pool: Array = _pools[particle_type]
	var active_list: Array = _active[particle_type]

	# Try to get from pool
	if not pool.is_empty():
		var emitter: AssemblyParticleEmitter = pool.pop_back()
		emitter.reset()
		active_list.append(emitter)
		return emitter

	# Check if we can create new
	var total_count := pool.size() + active_list.size()
	var max_size: int = _pool_sizes.get(particle_type, DEFAULT_POOL_SIZE)

	if total_count < max_size:
		var emitter := _create_emitter(particle_type)
		active_list.append(emitter)
		return emitter

	# Pool exhausted
	pool_exhausted.emit()

	# Try to reuse oldest active emitter that's not emitting
	for emitter in active_list:
		if not emitter.is_emitting():
			emitter.reset()
			return emitter

	# Fallback: create one anyway (over limit)
	if total_count < MAX_POOL_SIZE:
		var emitter := _create_emitter(particle_type)
		active_list.append(emitter)
		return emitter

	return null


## Return a particle emitter to the pool.
func return_particle_emitter(emitter: AssemblyParticleEmitter) -> void:
	if emitter == null:
		return

	var particle_type := emitter.get_type()

	# Remove from active
	if _active.has(particle_type):
		var active_list: Array = _active[particle_type]
		var idx := active_list.find(emitter)
		if idx != -1:
			active_list.remove_at(idx)

	# Reset and add to pool
	emitter.reset()

	if _pools.has(particle_type):
		_pools[particle_type].append(emitter)

	emitter_returned.emit(particle_type)


## Create a new emitter.
func _create_emitter(particle_type: String) -> AssemblyParticleEmitter:
	var emitter := AssemblyParticleEmitter.new()
	emitter.create_emitter(particle_type, _parent_node)

	if _current_theme != null:
		emitter.apply_theme(_current_theme)

	return emitter


## Update pool - reclaim inactive emitters.
func update(_delta: float) -> void:
	for particle_type in _active:
		var active_list: Array = _active[particle_type]
		var to_return: Array = []

		for emitter in active_list:
			if not emitter.is_emitting():
				to_return.append(emitter)

		for emitter in to_return:
			return_particle_emitter(emitter)


## Pre-warm pool with emitters.
func prewarm(particle_type: String, count: int) -> void:
	if not _pools.has(particle_type):
		_init_pool(particle_type)

	for i in count:
		var emitter := _create_emitter(particle_type)
		_pools[particle_type].append(emitter)


## Pre-warm all pools.
func prewarm_all(count_per_type: int = 5) -> void:
	prewarm(AssemblyParticleEmitter.TYPE_WELDING, count_per_type)
	prewarm(AssemblyParticleEmitter.TYPE_SPARKS, count_per_type)
	prewarm(AssemblyParticleEmitter.TYPE_ENERGY, count_per_type)


## Set pool size for a type.
func set_pool_size(particle_type: String, size: int) -> void:
	_pool_sizes[particle_type] = clampi(size, 1, MAX_POOL_SIZE)


## Get available emitter count for type.
func get_available_count(particle_type: String) -> int:
	if _pools.has(particle_type):
		return _pools[particle_type].size()
	return 0


## Get active emitter count for type.
func get_active_count(particle_type: String) -> int:
	if _active.has(particle_type):
		return _active[particle_type].size()
	return 0


## Get total count for type.
func get_total_count(particle_type: String) -> int:
	return get_available_count(particle_type) + get_active_count(particle_type)


## Clear all pools.
func clear() -> void:
	# Cleanup active emitters
	for particle_type in _active:
		for emitter in _active[particle_type]:
			emitter.cleanup()
		_active[particle_type].clear()

	# Cleanup pooled emitters
	for particle_type in _pools:
		for emitter in _pools[particle_type]:
			emitter.cleanup()
		_pools[particle_type].clear()


## Cleanup.
func cleanup() -> void:
	clear()
	_pools.clear()
	_active.clear()
	_pool_sizes.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var pool_stats: Dictionary = {}

	for particle_type in _pools:
		pool_stats[particle_type] = {
			"available": get_available_count(particle_type),
			"active": get_active_count(particle_type),
			"total": get_total_count(particle_type),
			"max_size": _pool_sizes.get(particle_type, DEFAULT_POOL_SIZE)
		}

	return {
		"has_parent": _parent_node != null,
		"has_theme": _current_theme != null,
		"pools": pool_stats
	}
