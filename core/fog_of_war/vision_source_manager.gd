class_name VisionSourceManager
extends RefCounted
## VisionSourceManager handles all vision sources (units, structures, abilities).

signal source_registered(source_id: int, source_type: int)
signal source_unregistered(source_id: int)
signal structure_vision_updated(structure_id: int)

## Structure vision ranges
const WATCHTOWER_RANGE := 20.0
const RADAR_STATION_RANGE := 25.0
const FACTORY_RANGE := 5.0

## Structure types
const STRUCTURE_WATCHTOWER := "watchtower"
const STRUCTURE_RADAR := "radar_station"
const STRUCTURE_FACTORY := "factory"

## All vision sources (source_id -> VisionSource)
var _sources: Dictionary = {}

## Sources by faction (faction_id -> Array[int])
var _faction_sources: Dictionary = {}

## Sources by type (source_type -> Array[int])
var _type_sources: Dictionary = {}

## Reference to stealth system
var _stealth_system: StealthSystem = null


func _init() -> void:
	# Initialize type arrays
	for source_type in VisionSource.SourceType.values():
		_type_sources[source_type] = []


## Set stealth system reference.
func set_stealth_system(system: StealthSystem) -> void:
	_stealth_system = system


## Register unit as vision source.
func register_unit(unit_id: int, faction_id: String, vision_range: float) -> VisionSource:
	var source := VisionSource.new()
	source.init_as_unit(unit_id, faction_id, vision_range)

	return _register_source(source)


## Register structure as vision source.
func register_structure(structure_id: int, faction_id: String, structure_type: String, position: Vector3) -> VisionSource:
	var source := VisionSource.new()

	match structure_type.to_lower():
		STRUCTURE_WATCHTOWER:
			source.init_as_structure(structure_id, faction_id, WATCHTOWER_RANGE, false)
		STRUCTURE_RADAR:
			source.init_as_structure(structure_id, faction_id, RADAR_STATION_RANGE, true)
		STRUCTURE_FACTORY:
			source.init_as_structure(structure_id, faction_id, FACTORY_RANGE, false)
		_:
			source.init_as_structure(structure_id, faction_id, FACTORY_RANGE, false)

	source.update_position(position)

	return _register_source(source)


## Register ability as temporary vision source.
func register_ability(ability_id: int, faction_id: String, position: Vector3, vision_range: float, duration: float) -> VisionSource:
	var source := VisionSource.new()
	source.init_as_ability(ability_id, faction_id, vision_range, duration)
	source.update_position(position)

	return _register_source(source)


## Internal registration.
func _register_source(source: VisionSource) -> VisionSource:
	_sources[source.source_id] = source

	# Add to faction list
	if not _faction_sources.has(source.faction_id):
		_faction_sources[source.faction_id] = []
	_faction_sources[source.faction_id].append(source.source_id)

	# Add to type list
	_type_sources[source.source_type].append(source.source_id)

	source_registered.emit(source.source_id, source.source_type)

	return source


## Unregister source.
func unregister_source(source_id: int) -> void:
	if not _sources.has(source_id):
		return

	var source: VisionSource = _sources[source_id]

	# Remove from faction list
	if _faction_sources.has(source.faction_id):
		var idx := _faction_sources[source.faction_id].find(source_id)
		if idx != -1:
			_faction_sources[source.faction_id].remove_at(idx)

	# Remove from type list
	var type_list: Array = _type_sources[source.source_type]
	var idx := type_list.find(source_id)
	if idx != -1:
		type_list.remove_at(idx)

	_sources.erase(source_id)

	source_unregistered.emit(source_id)


## Get source.
func get_source(source_id: int) -> VisionSource:
	return _sources.get(source_id)


## Update source position.
func update_position(source_id: int, position: Vector3) -> void:
	var source := get_source(source_id)
	if source != null:
		source.update_position(position)


## Set source stealthed state.
func set_stealthed(source_id: int, is_stealthed: bool) -> void:
	var source := get_source(source_id)
	if source == null:
		return

	if is_stealthed:
		source.enter_stealth()
	else:
		source.exit_stealth()


## Get all active sources for faction.
func get_faction_sources(faction_id: String) -> Array[VisionSource]:
	var sources: Array[VisionSource] = []

	if not _faction_sources.has(faction_id):
		return sources

	for source_id in _faction_sources[faction_id]:
		var source: VisionSource = _sources.get(source_id)
		if source != null and source.is_providing_vision():
			sources.append(source)

	return sources


## Get all sources providing vision at position.
func get_sources_at_position(faction_id: String, position: Vector3) -> Array[VisionSource]:
	var sources: Array[VisionSource] = []
	var faction_sources := get_faction_sources(faction_id)

	for source in faction_sources:
		var distance := source.position.distance_to(position)
		if distance <= source.vision_range:
			sources.append(source)

	return sources


## Check if position is visible to faction from any source.
func is_position_visible(faction_id: String, position: Vector3) -> bool:
	return not get_sources_at_position(faction_id, position).is_empty()


## Get structure sources.
func get_structure_sources() -> Array[VisionSource]:
	var sources: Array[VisionSource] = []

	for source_id in _type_sources[VisionSource.SourceType.STRUCTURE]:
		var source: VisionSource = _sources.get(source_id)
		if source != null:
			sources.append(source)

	return sources


## Process periodic scans (call each frame).
func process_scans() -> Array[VisionSource]:
	var scanned: Array[VisionSource] = []

	for source_id in _sources:
		var source: VisionSource = _sources[source_id]

		if source.should_scan():
			source.mark_scanned()
			scanned.append(source)

			if source.source_type == VisionSource.SourceType.STRUCTURE:
				structure_vision_updated.emit(source_id)

	return scanned


## Cleanup expired temporary sources.
func cleanup_expired() -> int:
	var expired: Array[int] = []

	for source_id in _sources:
		var source: VisionSource = _sources[source_id]
		if source.is_expired():
			expired.append(source_id)

	for source_id in expired:
		unregister_source(source_id)

	return expired.size()


## Serialization.
func to_dict() -> Dictionary:
	var sources_data: Dictionary = {}
	for source_id in _sources:
		sources_data[str(source_id)] = _sources[source_id].to_dict()

	return {
		"sources": sources_data
	}


func from_dict(data: Dictionary) -> void:
	_sources.clear()
	_faction_sources.clear()

	for source_type in VisionSource.SourceType.values():
		_type_sources[source_type] = []

	var sources_data: Dictionary = data.get("sources", {})
	for source_id_str in sources_data:
		var source := VisionSource.new()
		source.from_dict(sources_data[source_id_str])
		_register_source(source)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var type_counts: Dictionary = {}
	for source_type in VisionSource.SourceType.values():
		var type_name: String
		match source_type:
			VisionSource.SourceType.UNIT:
				type_name = "units"
			VisionSource.SourceType.STRUCTURE:
				type_name = "structures"
			VisionSource.SourceType.ABILITY:
				type_name = "abilities"
			VisionSource.SourceType.CONSUMABLE:
				type_name = "consumables"

		type_counts[type_name] = _type_sources[source_type].size()

	var active_count := 0
	for source_id in _sources:
		if _sources[source_id].is_providing_vision():
			active_count += 1

	return {
		"total_sources": _sources.size(),
		"active_sources": active_count,
		"sources_by_type": type_counts,
		"factions": _faction_sources.size()
	}
