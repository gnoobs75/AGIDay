class_name OverclockPersistence
extends RefCounted
## OverclockPersistence handles save/load of overclock system state.

signal save_completed(factory_count: int)
signal load_completed(factory_count: int)
signal save_error(message: String)
signal load_error(message: String)

## Maximum size limit for save data (1MB)
const MAX_SAVE_SIZE_BYTES := 1_048_576

## Estimated bytes per factory
const BYTES_PER_FACTORY := 200

## Maximum factories that fit in size limit
const MAX_FACTORIES_IN_SAVE := MAX_SAVE_SIZE_BYTES / BYTES_PER_FACTORY


func _init() -> void:
	pass


## Save all overclock states to dictionary.
func save_overclock_system(system: OverclockSystem, faction_manager: FactionOverclockManager = null) -> Dictionary:
	var states: Array = []

	for factory_id in system.get_all_factory_ids():
		var overclock := system.get_factory_overclock(factory_id)
		if overclock == null:
			continue

		var faction := ""
		if faction_manager != null:
			faction = faction_manager.get_factory_faction(factory_id)

		var state := OverclockState.create_from_overclock(overclock, faction)
		states.append(state.to_dict())

	var save_data := {
		"version": 1,
		"timestamp": Time.get_unix_time_from_system(),
		"factory_count": states.size(),
		"states": states
	}

	# Validate size
	var estimated_size := states.size() * BYTES_PER_FACTORY
	if estimated_size > MAX_SAVE_SIZE_BYTES:
		push_warning("Save data may exceed size limit: %d bytes estimated" % estimated_size)

	save_completed.emit(states.size())

	return save_data


## Load overclock states from dictionary.
func load_overclock_system(
	data: Dictionary,
	system: OverclockSystem,
	faction_manager: FactionOverclockManager = null
) -> int:
	var version: int = data.get("version", 0)
	if version != 1:
		load_error.emit("Unsupported save version: %d" % version)
		return 0

	var states: Array = data.get("states", [])
	var loaded_count := 0

	for state_data in states:
		if not state_data is Dictionary:
			continue

		var state := OverclockState.create_from_dict(state_data)
		if not state.is_valid():
			push_warning("Invalid overclock state for factory %d" % state.factory_id)
			continue

		# Get or create factory overclock
		var overclock := system.get_factory_overclock(state.factory_id)
		if overclock == null:
			overclock = system.register_factory(state.factory_id)

		if overclock != null:
			state.apply_to_overclock(overclock)
			loaded_count += 1

			# Restore faction assignment
			if faction_manager != null and not state.faction_id.is_empty():
				faction_manager.assign_faction(state.factory_id, state.faction_id)

	load_completed.emit(loaded_count)

	return loaded_count


## Save to file.
func save_to_file(system: OverclockSystem, file_path: String, faction_manager: FactionOverclockManager = null) -> bool:
	var save_data := save_overclock_system(system, faction_manager)

	var json := JSON.stringify(save_data, "\t")
	if json.length() > MAX_SAVE_SIZE_BYTES:
		save_error.emit("Save data exceeds size limit")
		return false

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		save_error.emit("Failed to open file: %s" % file_path)
		return false

	file.store_string(json)
	file.close()

	return true


## Load from file.
func load_from_file(
	file_path: String,
	system: OverclockSystem,
	faction_manager: FactionOverclockManager = null
) -> int:
	if not FileAccess.file_exists(file_path):
		load_error.emit("File not found: %s" % file_path)
		return 0

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		load_error.emit("Failed to open file: %s" % file_path)
		return 0

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		load_error.emit("Failed to parse JSON: %s" % json.get_error_message())
		return 0

	var data: Dictionary = json.data
	return load_overclock_system(data, system, faction_manager)


## Validate save data.
func validate_save_data(data: Dictionary) -> bool:
	if not data.has("version"):
		return false
	if not data.has("states"):
		return false
	if not data["states"] is Array:
		return false
	return true


## Get estimated save size for a number of factories.
static func estimate_save_size(factory_count: int) -> int:
	# Base overhead + per-factory data
	return 100 + (factory_count * BYTES_PER_FACTORY)


## Check if factory count fits within size limit.
static func can_save_factories(factory_count: int) -> bool:
	return factory_count <= MAX_FACTORIES_IN_SAVE


## Create snapshot of current state (for comparison/debugging).
func create_snapshot(system: OverclockSystem) -> Dictionary:
	var snapshot: Dictionary = {}

	for factory_id in system.get_all_factory_ids():
		var overclock := system.get_factory_overclock(factory_id)
		if overclock != null:
			snapshot[factory_id] = {
				"overclock": overclock.overclock_level,
				"heat": overclock.heat_level,
				"meltdown": overclock.is_meltdown,
				"timer": overclock.meltdown_timer
			}

	return snapshot


## Compare two snapshots.
func compare_snapshots(snapshot1: Dictionary, snapshot2: Dictionary) -> Dictionary:
	var diff: Dictionary = {
		"added": [],
		"removed": [],
		"changed": []
	}

	# Find added and changed
	for factory_id in snapshot2:
		if not snapshot1.has(factory_id):
			diff["added"].append(factory_id)
		else:
			var s1: Dictionary = snapshot1[factory_id]
			var s2: Dictionary = snapshot2[factory_id]
			if s1 != s2:
				diff["changed"].append(factory_id)

	# Find removed
	for factory_id in snapshot1:
		if not snapshot2.has(factory_id):
			diff["removed"].append(factory_id)

	return diff


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"max_save_size": MAX_SAVE_SIZE_BYTES,
		"bytes_per_factory": BYTES_PER_FACTORY,
		"max_factories": MAX_FACTORIES_IN_SAVE
	}
