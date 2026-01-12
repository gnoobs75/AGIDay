class_name FactionOverclockManager
extends RefCounted
## FactionOverclockManager applies faction profiles to factory overclock states.

signal faction_profile_applied(factory_id: int, faction_id: String)

## Factory to faction mapping
var _factory_factions: Dictionary = {}  ## factory_id -> faction_id

## Factory to profile mapping
var _factory_profiles: Dictionary = {}  ## factory_id -> FactionOverclockProfile

## Overclock system reference
var _overclock_system: OverclockSystem = null


func _init() -> void:
	pass


## Set overclock system reference.
func set_overclock_system(system: OverclockSystem) -> void:
	_overclock_system = system


## Assign faction to factory.
func assign_faction(factory_id: int, faction_id: String) -> void:
	_factory_factions[factory_id] = faction_id

	# Get or create profile
	var profile := FactionOverclockProfile.get_profile(faction_id)
	_factory_profiles[factory_id] = profile

	# Apply to factory overclock if exists
	_apply_profile_to_factory(factory_id, profile)

	faction_profile_applied.emit(factory_id, faction_id)


## Apply profile to a factory's overclock.
func _apply_profile_to_factory(factory_id: int, profile: FactionOverclockProfile) -> void:
	if _overclock_system == null:
		return

	var overclock := _overclock_system.get_factory_overclock(factory_id)
	if overclock == null:
		return

	# Validate current overclock level against faction max
	if overclock.overclock_level > profile.max_overclock_level:
		overclock.set_overclock(profile.max_overclock_level)


## Get faction for factory.
func get_factory_faction(factory_id: int) -> String:
	return _factory_factions.get(factory_id, "")


## Get profile for factory.
func get_factory_profile(factory_id: int) -> FactionOverclockProfile:
	return _factory_profiles.get(factory_id)


## Calculate effective heat generation for factory.
func get_effective_heat_generation(factory_id: int, base_rate: float) -> float:
	var profile := _factory_profiles.get(factory_id)
	if profile != null:
		return profile.get_effective_heat_generation(base_rate)
	return base_rate


## Calculate effective heat dissipation for factory.
func get_effective_heat_dissipation(factory_id: int, base_rate: float) -> float:
	var profile := _factory_profiles.get(factory_id)
	if profile != null:
		return profile.get_effective_heat_dissipation(base_rate)
	return base_rate


## Get effective meltdown duration for factory.
func get_meltdown_duration(factory_id: int) -> float:
	var profile := _factory_profiles.get(factory_id)
	if profile != null:
		return profile.meltdown_duration
	return 30.0


## Get max overclock level for factory.
func get_max_overclock(factory_id: int) -> float:
	var profile := _factory_profiles.get(factory_id)
	if profile != null:
		return profile.max_overclock_level
	return 2.0


## Get effective production multiplier for factory.
func get_production_multiplier(factory_id: int, overclock_level: float) -> float:
	var profile := _factory_profiles.get(factory_id)
	if profile != null:
		return profile.get_effective_production_multiplier(overclock_level)
	return overclock_level


## Validate overclock level for factory.
func validate_overclock(factory_id: int, level: float) -> float:
	var profile := _factory_profiles.get(factory_id)
	if profile != null:
		return profile.validate_overclock_level(level)
	return clampf(level, 1.0, 2.0)


## Set overclock with faction validation.
func set_factory_overclock(factory_id: int, level: float) -> void:
	var validated_level := validate_overclock(factory_id, level)

	if _overclock_system != null:
		_overclock_system.set_overclock(factory_id, validated_level)


## Remove factory from manager.
func remove_factory(factory_id: int) -> void:
	_factory_factions.erase(factory_id)
	_factory_profiles.erase(factory_id)


## Clear all data.
func clear() -> void:
	_factory_factions.clear()
	_factory_profiles.clear()


## Get all factories for a faction.
func get_faction_factories(faction_id: String) -> Array[int]:
	var factories: Array[int] = []
	for factory_id in _factory_factions:
		if _factory_factions[factory_id] == faction_id:
			factories.append(factory_id)
	return factories


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_counts: Dictionary = {}
	for factory_id in _factory_factions:
		var faction: String = _factory_factions[factory_id]
		faction_counts[faction] = faction_counts.get(faction, 0) + 1

	return {
		"factory_count": _factory_factions.size(),
		"faction_distribution": faction_counts,
		"has_overclock_system": _overclock_system != null
	}
