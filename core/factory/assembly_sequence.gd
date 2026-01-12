class_name AssemblySequence
extends RefCounted
## AssemblySequence manages a collection of parts for unit assembly.

signal sequence_loaded(unit_template: String)
signal part_started(part_index: int, part: AssemblyPart)
signal part_completed(part_index: int, part: AssemblyPart)
signal sequence_completed(unit_template: String)

## Sequence identity
var unit_template: String = ""
var faction_id: String = ""

## Parts collection
var parts: Array[AssemblyPart] = []
var total_assembly_time: float = 0.0

## Caching
static var _sequence_cache: Dictionary = {}
const CACHE_SIZE_LIMIT := 50


func _init() -> void:
	pass


## Initialize for a specific unit template and faction.
func initialize(p_unit_template: String, p_faction_id: String) -> bool:
	unit_template = p_unit_template
	faction_id = p_faction_id

	# Check cache first
	var cache_key := "%s_%s" % [unit_template, faction_id]
	if _sequence_cache.has(cache_key):
		_load_from_cache(cache_key)
		return true

	# Load from configuration
	var loaded := _load_from_config(unit_template, faction_id)
	if loaded:
		_cache_sequence(cache_key)
		sequence_loaded.emit(unit_template)

	return loaded


## Load sequence from JSON configuration.
func _load_from_config(template: String, faction: String) -> bool:
	# Try to load JSON configuration
	var config_path := "res://data/assembly/%s.json" % template

	if not FileAccess.file_exists(config_path):
		# Create default sequence
		_create_default_sequence(template)
		return true

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		_create_default_sequence(template)
		return true

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("Failed to parse assembly config: %s" % config_path)
		_create_default_sequence(template)
		return true

	var data: Dictionary = json.data
	_parse_sequence_data(data, faction)

	return true


## Parse sequence data from JSON.
func _parse_sequence_data(data: Dictionary, faction: String) -> void:
	parts.clear()

	var parts_data: Array = data.get("parts", [])

	for part_data in parts_data:
		if not part_data is Dictionary:
			continue

		# Validate required fields
		if not _validate_part_data(part_data):
			push_warning("Skipping malformed part data")
			continue

		var part := AssemblyPart.from_json(part_data)
		parts.append(part)

	_calculate_total_time()


## Validate part data has required fields.
func _validate_part_data(data: Dictionary) -> bool:
	if not data.has("part_id"):
		push_warning("Part missing part_id")
		return false

	if not data.has("assembly_time"):
		push_warning("Part missing assembly_time")
		return false

	return true


## Create default sequence for unknown templates.
func _create_default_sequence(template: String) -> void:
	parts.clear()

	# Create a basic 3-part assembly
	var base := AssemblyPart.new()
	base.initialize("%s_base" % template, "Base", 0.5)
	base.set_positions(Vector3(0, -2, 0), Vector3(0, 0, 0))
	base.set_effects("weld_sparks", 0.8, "metal_clang")
	parts.append(base)

	var body := AssemblyPart.new()
	body.initialize("%s_body" % template, "Body", 0.75)
	body.set_positions(Vector3(0, 2, 0), Vector3(0, 0.5, 0))
	body.set_effects("weld_sparks", 1.0, "metal_clang")
	parts.append(body)

	var top := AssemblyPart.new()
	top.initialize("%s_top" % template, "Top", 0.5)
	top.set_positions(Vector3(0, 3, 0), Vector3(0, 1, 0))
	top.set_effects("energy_pulse", 0.5, "power_up")
	parts.append(top)

	_calculate_total_time()


## Calculate total assembly time.
func _calculate_total_time() -> void:
	total_assembly_time = 0.0
	for part in parts:
		total_assembly_time += part.assembly_time


## Get part at specific time in the sequence.
func get_part_at_time(elapsed_time: float) -> Dictionary:
	if parts.is_empty():
		return {}

	var accumulated := 0.0
	var part_index := 0

	for i in parts.size():
		var part: AssemblyPart = parts[i]
		var part_end := accumulated + part.assembly_time

		if elapsed_time <= part_end:
			var part_progress := (elapsed_time - accumulated) / part.assembly_time if part.assembly_time > 0 else 1.0

			return {
				"part": part,
				"index": i,
				"progress": clampf(part_progress, 0.0, 1.0),
				"time_in_part": elapsed_time - accumulated,
				"is_complete": part_progress >= 1.0
			}

		accumulated = part_end
		part_index = i

	# Past all parts - return last part as complete
	return {
		"part": parts[parts.size() - 1],
		"index": parts.size() - 1,
		"progress": 1.0,
		"time_in_part": parts[parts.size() - 1].assembly_time,
		"is_complete": true
	}


## Get all parts up to a specific time (for showing assembled parts).
func get_assembled_parts_at_time(elapsed_time: float) -> Array[AssemblyPart]:
	var assembled: Array[AssemblyPart] = []
	var accumulated := 0.0

	for part in parts:
		var part_end := accumulated + part.assembly_time

		if elapsed_time >= part_end:
			assembled.append(part)
		else:
			break

		accumulated = part_end

	return assembled


## Get part count.
func get_part_count() -> int:
	return parts.size()


## Get part by index.
func get_part(index: int) -> AssemblyPart:
	if index >= 0 and index < parts.size():
		return parts[index]
	return null


## Cache management.
func _cache_sequence(cache_key: String) -> void:
	if _sequence_cache.size() >= CACHE_SIZE_LIMIT:
		# Remove oldest entry
		var oldest_key: String = _sequence_cache.keys()[0]
		_sequence_cache.erase(oldest_key)

	_sequence_cache[cache_key] = to_dict()


func _load_from_cache(cache_key: String) -> void:
	var data: Dictionary = _sequence_cache[cache_key]
	from_dict(data)


static func clear_cache() -> void:
	_sequence_cache.clear()


static func get_cache_size() -> int:
	return _sequence_cache.size()


## Serialization.
func to_dict() -> Dictionary:
	var parts_data: Array = []
	for part in parts:
		parts_data.append(part.to_dict())

	return {
		"unit_template": unit_template,
		"faction_id": faction_id,
		"parts": parts_data,
		"total_assembly_time": total_assembly_time
	}


func from_dict(data: Dictionary) -> void:
	unit_template = data.get("unit_template", "")
	faction_id = data.get("faction_id", "")
	total_assembly_time = data.get("total_assembly_time", 0.0)

	parts.clear()
	for part_data in data.get("parts", []):
		var part := AssemblyPart.new()
		part.from_dict(part_data)
		parts.append(part)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"unit_template": unit_template,
		"faction": faction_id,
		"part_count": parts.size(),
		"total_time": total_assembly_time,
		"cached": _sequence_cache.has("%s_%s" % [unit_template, faction_id])
	}
