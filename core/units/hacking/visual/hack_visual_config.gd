class_name HackVisualConfig
extends RefCounted
## HackVisualConfig defines visual parameters for hack effects.

## Color transition duration (seconds)
var transition_duration: float = 0.3

## Emission/glow intensity
var emission_intensity: float = 2.0

## Indicator height above unit
var indicator_height: float = 3.0

## Indicator text
var indicator_text: String = "HACKED"

## Indicator font size
var indicator_font_size: int = 24

## Faction colors (faction_id -> Color)
var faction_colors: Dictionary = {
	"aether_swarm": Color.html("#00ffcc"),
	"glacius": Color.html("#00d9ff"),
	"ferron_horde": Color.html("#ff6600"),
	"human_remnant": Color.html("#00ff00"),
	"dynapods": Color.html("#ff00ff")
}


func _init() -> void:
	pass


## Get faction color.
func get_faction_color(faction_id: String) -> Color:
	return faction_colors.get(faction_id, Color.WHITE)


## Set faction color.
func set_faction_color(faction_id: String, color: Color) -> void:
	faction_colors[faction_id] = color


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var colors_data: Dictionary = {}
	for faction_id in faction_colors:
		colors_data[faction_id] = faction_colors[faction_id].to_html()

	return {
		"transition_duration": transition_duration,
		"emission_intensity": emission_intensity,
		"indicator_height": indicator_height,
		"indicator_text": indicator_text,
		"indicator_font_size": indicator_font_size,
		"faction_colors": colors_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	transition_duration = data.get("transition_duration", 0.3)
	emission_intensity = data.get("emission_intensity", 2.0)
	indicator_height = data.get("indicator_height", 3.0)
	indicator_text = data.get("indicator_text", "HACKED")
	indicator_font_size = data.get("indicator_font_size", 24)

	faction_colors.clear()
	for faction_id in data.get("faction_colors", {}):
		faction_colors[faction_id] = Color.html(data["faction_colors"][faction_id])
