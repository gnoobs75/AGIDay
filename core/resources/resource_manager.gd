class_name ResourceManagerClass
extends Node
## ResourceManager is the central authority for faction resource state.
## Manages REE resources for all factions and provides transaction methods.

signal faction_ree_changed(faction_id: int, amount: float, change: float, source: String)
signal faction_insufficient_ree(faction_id: int, requested: float, available: float)
signal resource_state_loaded()

## Faction REE states (faction_id -> FactionREEState)
var _faction_states: Dictionary = {}

## Default starting REE by faction (can be overridden by faction config)
var _default_starting_ree: Dictionary = {
	1: 500.0,   # Aether Swarm
	2: 400.0,   # OptiForge Legion
	3: 450.0,   # Dynapods Vanguard
	4: 600.0,   # LogiBots Colossus
	5: 300.0    # Human Remnant
}

## Default max storage
var _default_max_storage: float = 10000.0


func _ready() -> void:
	print("ResourceManager: Initialized")


func _process(delta: float) -> void:
	# Apply generation for all factions
	for faction_id in _faction_states:
		var state: FactionREEState = _faction_states[faction_id]
		state.apply_generation(delta)


## Initialize resource state for a faction.
func initialize_faction(faction_id: int, starting_ree: float = -1.0, max_storage: float = -1.0) -> FactionREEState:
	if starting_ree < 0:
		starting_ree = _default_starting_ree.get(faction_id, 500.0)

	if max_storage < 0:
		max_storage = _default_max_storage

	var state := FactionREEState.new(faction_id, starting_ree, max_storage)

	# Connect signals
	state.ree_changed.connect(_on_faction_ree_changed.bind(faction_id))
	state.insufficient_ree.connect(_on_faction_insufficient_ree.bind(faction_id))

	_faction_states[faction_id] = state
	print("ResourceManager: Initialized faction %d with %.0f REE" % [faction_id, starting_ree])

	return state


## Get REE state for a faction (creates if not exists).
func get_faction_state(faction_id: int) -> FactionREEState:
	if not _faction_states.has(faction_id):
		initialize_faction(faction_id)
	return _faction_states[faction_id]


## Check if faction state exists.
func has_faction_state(faction_id: int) -> bool:
	return _faction_states.has(faction_id)


## Add REE to a faction.
func add_ree(faction_id: int, amount: float, source: String = "unknown") -> float:
	var state := get_faction_state(faction_id)
	return state.add_ree(amount, source)


## Consume REE from a faction.
func consume_ree(faction_id: int, amount: float, category: String = "unknown") -> bool:
	var state := get_faction_state(faction_id)
	return state.consume_ree(amount, category)


## Check if faction can afford REE cost.
func can_afford(faction_id: int, amount: float) -> bool:
	var state := get_faction_state(faction_id)
	return state.can_afford(amount)


## Get current REE for a faction.
func get_current_ree(faction_id: int) -> float:
	var state := get_faction_state(faction_id)
	return state.get_available_ree()


## Get max storage for a faction.
func get_max_storage(faction_id: int) -> float:
	var state := get_faction_state(faction_id)
	return state.max_ree_storage


## Get storage percentage for a faction.
func get_storage_percentage(faction_id: int) -> float:
	var state := get_faction_state(faction_id)
	return state.get_storage_percentage()


## Set generation rate for a faction.
func set_generation_rate(faction_id: int, rate: float) -> void:
	var state := get_faction_state(faction_id)
	state.set_generation_rate(rate)


## Get generation rate for a faction.
func get_generation_rate(faction_id: int) -> float:
	var state := get_faction_state(faction_id)
	return state.ree_generation_rate


## Increase max storage for a faction.
func increase_max_storage(faction_id: int, amount: float) -> void:
	var state := get_faction_state(faction_id)
	state.increase_max_storage(amount)


## Get analytics for a faction.
func get_faction_analytics(faction_id: int) -> Dictionary:
	var state := get_faction_state(faction_id)
	return state.get_analytics()


## Get analytics for all factions.
func get_all_analytics() -> Dictionary:
	var result := {}
	for faction_id in _faction_states:
		result[faction_id] = get_faction_analytics(faction_id)
	return result


## Transfer REE between factions (if allowed).
func transfer_ree(from_faction: int, to_faction: int, amount: float) -> bool:
	if not can_afford(from_faction, amount):
		return false

	consume_ree(from_faction, amount, "transfer_out")
	add_ree(to_faction, amount, "transfer_in")
	return true


## Handle faction REE change signal.
func _on_faction_ree_changed(amount: float, change: float, source: String, faction_id: int) -> void:
	faction_ree_changed.emit(faction_id, amount, change, source)


## Handle faction insufficient REE signal.
func _on_faction_insufficient_ree(requested: float, available: float, faction_id: int) -> void:
	faction_insufficient_ree.emit(faction_id, requested, available)


## Reset all faction states.
func reset_all() -> void:
	for faction_id in _faction_states:
		var state: FactionREEState = _faction_states[faction_id]
		var starting_ree: float = _default_starting_ree.get(faction_id, 500.0)
		state.reset(starting_ree)


## Clear all faction states.
func clear_all() -> void:
	_faction_states.clear()


## Get all faction IDs with states.
func get_faction_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in _faction_states.keys():
		ids.append(int(id))
	return ids


## Serialize all faction states.
func to_dict() -> Dictionary:
	var states := {}
	for faction_id in _faction_states:
		var state: FactionREEState = _faction_states[faction_id]
		states[faction_id] = state.to_dict()

	return {
		"faction_states": states
	}


## Deserialize all faction states.
func from_dict(data: Dictionary) -> void:
	_faction_states.clear()

	var states_data: Dictionary = data.get("faction_states", {})
	for faction_id_str in states_data:
		var faction_id := int(faction_id_str)
		var state := FactionREEState.new(faction_id)
		state.from_dict(states_data[faction_id_str])

		# Connect signals
		state.ree_changed.connect(_on_faction_ree_changed.bind(faction_id))
		state.insufficient_ree.connect(_on_faction_insufficient_ree.bind(faction_id))

		_faction_states[faction_id] = state

	resource_state_loaded.emit()


## Get compact summary for debugging.
func get_summary() -> Dictionary:
	var factions := {}
	for faction_id in _faction_states:
		var state: FactionREEState = _faction_states[faction_id]
		factions[faction_id] = state.get_summary()

	return {
		"faction_count": _faction_states.size(),
		"factions": factions
	}
