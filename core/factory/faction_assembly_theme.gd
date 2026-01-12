class_name FactionAssemblyTheme
extends RefCounted
## FactionAssemblyTheme defines faction-specific assembly aesthetics.

## Default factions
const AETHER_SWARM := "AETHER_SWARM"
const OPTIFORGE_LEGION := "OPTIFORGE_LEGION"
const DYNAPODS_VANGUARD := "DYNAPODS_VANGUARD"
const LOGIBOTS_COLOSSUS := "LOGIBOTS_COLOSSUS"

## Theme identity
var faction_id: String = ""

## Colors
var primary_color: Color = Color.WHITE
var secondary_color: Color = Color.GRAY
var glow_color: Color = Color.WHITE
var particle_color: Color = Color.WHITE

## Particle settings
var particle_type: String = "weld_sparks"
var particle_intensity_multiplier: float = 1.0
var particle_scale: float = 1.0

## Assembly speed
var assembly_speed_multiplier: float = 1.0

## Sound settings
var assembly_sound_set: String = "default"
var sound_volume_multiplier: float = 1.0

## Visual effects
var glow_intensity: float = 1.0
var trail_enabled: bool = true
var trail_color: Color = Color.WHITE


func _init() -> void:
	pass


## Create theme for faction.
static func create_for_faction(faction_id: String) -> FactionAssemblyTheme:
	var theme := FactionAssemblyTheme.new()
	theme.faction_id = faction_id

	match faction_id:
		AETHER_SWARM:
			theme._configure_aether_swarm()
		OPTIFORGE_LEGION:
			theme._configure_optiforge_legion()
		DYNAPODS_VANGUARD:
			theme._configure_dynapods_vanguard()
		LOGIBOTS_COLOSSUS:
			theme._configure_logibots_colossus()
		_:
			theme._configure_default()

	return theme


## Configure Aether Swarm theme (organic, purple/cyan).
func _configure_aether_swarm() -> void:
	primary_color = Color(0.6, 0.2, 0.8)  # Purple
	secondary_color = Color(0.2, 0.8, 0.8)  # Cyan
	glow_color = Color(0.8, 0.4, 1.0)
	particle_color = Color(0.5, 0.0, 1.0)

	particle_type = "organic_mist"
	particle_intensity_multiplier = 1.2
	particle_scale = 1.1

	assembly_speed_multiplier = 1.1  # Slightly faster (swarm efficiency)
	assembly_sound_set = "organic"
	glow_intensity = 1.3

	trail_color = Color(0.6, 0.2, 0.8, 0.5)


## Configure OptiForge Legion theme (industrial, orange/yellow).
func _configure_optiforge_legion() -> void:
	primary_color = Color(0.9, 0.5, 0.1)  # Orange
	secondary_color = Color(0.3, 0.3, 0.3)  # Dark gray
	glow_color = Color(1.0, 0.7, 0.2)
	particle_color = Color(1.0, 0.5, 0.0)

	particle_type = "weld_sparks"
	particle_intensity_multiplier = 1.5
	particle_scale = 1.0

	assembly_speed_multiplier = 0.9  # Slightly slower (heavy construction)
	assembly_sound_set = "industrial"
	glow_intensity = 1.0

	trail_color = Color(1.0, 0.6, 0.1, 0.5)


## Configure Dynapods Vanguard theme (tech, blue/white).
func _configure_dynapods_vanguard() -> void:
	primary_color = Color(0.2, 0.5, 0.9)  # Blue
	secondary_color = Color(0.9, 0.9, 1.0)  # White
	glow_color = Color(0.4, 0.7, 1.0)
	particle_color = Color(0.3, 0.6, 1.0)

	particle_type = "energy_pulse"
	particle_intensity_multiplier = 1.0
	particle_scale = 0.9

	assembly_speed_multiplier = 1.0  # Standard speed
	assembly_sound_set = "tech"
	glow_intensity = 1.2

	trail_color = Color(0.3, 0.6, 1.0, 0.5)


## Configure LogiBots Colossus theme (mechanical, green/gray).
func _configure_logibots_colossus() -> void:
	primary_color = Color(0.2, 0.7, 0.3)  # Green
	secondary_color = Color(0.4, 0.4, 0.4)  # Gray
	glow_color = Color(0.3, 0.9, 0.4)
	particle_color = Color(0.1, 0.8, 0.2)

	particle_type = "circuit_sparks"
	particle_intensity_multiplier = 0.8
	particle_scale = 1.2

	assembly_speed_multiplier = 0.85  # Slower (heavy units)
	assembly_sound_set = "mechanical"
	glow_intensity = 0.9

	trail_color = Color(0.2, 0.7, 0.3, 0.5)


## Configure default theme.
func _configure_default() -> void:
	primary_color = Color.WHITE
	secondary_color = Color.GRAY
	glow_color = Color.WHITE
	particle_color = Color.WHITE

	particle_type = "weld_sparks"
	particle_intensity_multiplier = 1.0
	particle_scale = 1.0

	assembly_speed_multiplier = 1.0
	assembly_sound_set = "default"
	glow_intensity = 1.0

	trail_color = Color(1.0, 1.0, 1.0, 0.5)


## Apply theme to an assembly part.
func apply_to_part(part: AssemblyPart) -> void:
	# Modify particle settings
	if part.particle_type.is_empty():
		part.particle_type = particle_type

	part.particle_intensity *= particle_intensity_multiplier

	# Apply speed multiplier to assembly time
	part.assembly_time /= assembly_speed_multiplier


## Apply theme to entire assembly sequence.
func apply_to_assembly(sequence: AssemblySequence) -> void:
	for part in sequence.parts:
		apply_to_part(part)

	# Recalculate total time
	sequence._calculate_total_time()


## Get color for a specific purpose.
func get_color(purpose: String) -> Color:
	match purpose:
		"primary":
			return primary_color
		"secondary":
			return secondary_color
		"glow":
			return glow_color
		"particle":
			return particle_color
		"trail":
			return trail_color
		_:
			return primary_color


## Serialization.
func to_dict() -> Dictionary:
	return {
		"faction_id": faction_id,
		"primary_color": _color_to_dict(primary_color),
		"secondary_color": _color_to_dict(secondary_color),
		"glow_color": _color_to_dict(glow_color),
		"particle_color": _color_to_dict(particle_color),
		"particle_type": particle_type,
		"particle_intensity_multiplier": particle_intensity_multiplier,
		"particle_scale": particle_scale,
		"assembly_speed_multiplier": assembly_speed_multiplier,
		"assembly_sound_set": assembly_sound_set,
		"sound_volume_multiplier": sound_volume_multiplier,
		"glow_intensity": glow_intensity,
		"trail_enabled": trail_enabled,
		"trail_color": _color_to_dict(trail_color)
	}


func from_dict(data: Dictionary) -> void:
	faction_id = data.get("faction_id", "")
	primary_color = _dict_to_color(data.get("primary_color", {}))
	secondary_color = _dict_to_color(data.get("secondary_color", {}))
	glow_color = _dict_to_color(data.get("glow_color", {}))
	particle_color = _dict_to_color(data.get("particle_color", {}))
	particle_type = data.get("particle_type", "weld_sparks")
	particle_intensity_multiplier = data.get("particle_intensity_multiplier", 1.0)
	particle_scale = data.get("particle_scale", 1.0)
	assembly_speed_multiplier = data.get("assembly_speed_multiplier", 1.0)
	assembly_sound_set = data.get("assembly_sound_set", "default")
	sound_volume_multiplier = data.get("sound_volume_multiplier", 1.0)
	glow_intensity = data.get("glow_intensity", 1.0)
	trail_enabled = data.get("trail_enabled", true)
	trail_color = _dict_to_color(data.get("trail_color", {}))


func _color_to_dict(c: Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}


func _dict_to_color(d: Dictionary) -> Color:
	if d.is_empty():
		return Color.WHITE
	return Color(d.get("r", 1.0), d.get("g", 1.0), d.get("b", 1.0), d.get("a", 1.0))


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"faction": faction_id,
		"speed_mult": assembly_speed_multiplier,
		"particle_type": particle_type,
		"sound_set": assembly_sound_set
	}
