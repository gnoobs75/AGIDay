class_name FactionOverclockProfile
extends RefCounted
## FactionOverclockProfile defines faction-specific overclock characteristics.

## Faction constants
const AETHER_SWARM := "AETHER_SWARM"
const OPTIFORGE_LEGION := "OPTIFORGE_LEGION"
const DYNAPODS_VANGUARD := "DYNAPODS_VANGUARD"
const LOGIBOTS_COLOSSUS := "LOGIBOTS_COLOSSUS"

## Profile properties
var faction_id: String = ""
var heat_generation_multiplier: float = 1.0
var heat_dissipation_multiplier: float = 1.0
var meltdown_duration: float = 30.0
var max_overclock_level: float = 2.0
var overclock_bonus: float = 1.0

## Description for UI
var description: String = ""


func _init() -> void:
	pass


## Create profile for a faction.
static func create_for_faction(faction: String) -> FactionOverclockProfile:
	var profile := FactionOverclockProfile.new()
	profile.faction_id = faction

	match faction:
		AETHER_SWARM:
			profile._configure_aether_swarm()
		OPTIFORGE_LEGION:
			profile._configure_optiforge_legion()
		DYNAPODS_VANGUARD:
			profile._configure_dynapods_vanguard()
		LOGIBOTS_COLOSSUS:
			profile._configure_logibots_colossus()
		_:
			profile._configure_default()

	return profile


## Configure Aether Swarm profile.
## Fast and risky - high heat but quick recovery.
func _configure_aether_swarm() -> void:
	heat_generation_multiplier = 1.2
	heat_dissipation_multiplier = 1.1
	meltdown_duration = 20.0
	max_overclock_level = 2.2
	overclock_bonus = 1.1
	description = "Volatile swarm tech: Higher heat but faster recovery"


## Configure OptiForge Legion profile.
## Slow and steady - efficient but longer downtime.
func _configure_optiforge_legion() -> void:
	heat_generation_multiplier = 0.9
	heat_dissipation_multiplier = 0.9
	meltdown_duration = 40.0
	max_overclock_level = 2.0
	overclock_bonus = 1.0
	description = "Industrial efficiency: Lower heat but slow recovery"


## Configure Dynapods Vanguard profile.
## Balanced with good cooling.
func _configure_dynapods_vanguard() -> void:
	heat_generation_multiplier = 1.0
	heat_dissipation_multiplier = 1.2
	meltdown_duration = 25.0
	max_overclock_level = 2.1
	overclock_bonus = 1.05
	description = "Advanced cooling: Standard heat, faster dissipation"


## Configure LogiBots Colossus profile.
## Very efficient but conservative limits.
func _configure_logibots_colossus() -> void:
	heat_generation_multiplier = 0.8
	heat_dissipation_multiplier = 0.8
	meltdown_duration = 45.0
	max_overclock_level = 1.9
	overclock_bonus = 0.95
	description = "Heavy construction: Very efficient but limited overclock"


## Configure default profile.
func _configure_default() -> void:
	heat_generation_multiplier = 1.0
	heat_dissipation_multiplier = 1.0
	meltdown_duration = 30.0
	max_overclock_level = 2.0
	overclock_bonus = 1.0
	description = "Standard configuration"


## Get effective heat generation rate.
func get_effective_heat_generation(base_rate: float) -> float:
	return base_rate * heat_generation_multiplier


## Get effective heat dissipation rate.
func get_effective_heat_dissipation(base_rate: float) -> float:
	return base_rate * heat_dissipation_multiplier


## Get effective production multiplier at given overclock level.
func get_effective_production_multiplier(overclock_level: float) -> float:
	return overclock_level * overclock_bonus


## Validate overclock level against faction max.
func validate_overclock_level(level: float) -> float:
	return clampf(level, 1.0, max_overclock_level)


## Check if overclock level is valid for this faction.
func is_valid_overclock_level(level: float) -> bool:
	return level >= 1.0 and level <= max_overclock_level


## Serialization.
func to_dict() -> Dictionary:
	return {
		"faction_id": faction_id,
		"heat_generation_multiplier": heat_generation_multiplier,
		"heat_dissipation_multiplier": heat_dissipation_multiplier,
		"meltdown_duration": meltdown_duration,
		"max_overclock_level": max_overclock_level,
		"overclock_bonus": overclock_bonus,
		"description": description
	}


func from_dict(data: Dictionary) -> void:
	faction_id = data.get("faction_id", "")
	heat_generation_multiplier = data.get("heat_generation_multiplier", 1.0)
	heat_dissipation_multiplier = data.get("heat_dissipation_multiplier", 1.0)
	meltdown_duration = data.get("meltdown_duration", 30.0)
	max_overclock_level = data.get("max_overclock_level", 2.0)
	overclock_bonus = data.get("overclock_bonus", 1.0)
	description = data.get("description", "")


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"faction": faction_id,
		"heat_gen_mult": heat_generation_multiplier,
		"heat_diss_mult": heat_dissipation_multiplier,
		"meltdown_dur": meltdown_duration,
		"max_overclock": max_overclock_level,
		"overclock_bonus": overclock_bonus
	}


## Static cache of faction profiles.
static var _profile_cache: Dictionary = {}


## Get cached profile for faction.
static func get_profile(faction_id: String) -> FactionOverclockProfile:
	if not _profile_cache.has(faction_id):
		_profile_cache[faction_id] = create_for_faction(faction_id)
	return _profile_cache[faction_id]


## Clear profile cache.
static func clear_cache() -> void:
	_profile_cache.clear()


## Get all faction IDs.
static func get_all_faction_ids() -> Array[String]:
	return [AETHER_SWARM, OPTIFORGE_LEGION, DYNAPODS_VANGUARD, LOGIBOTS_COLOSSUS]
