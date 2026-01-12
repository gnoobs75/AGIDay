class_name DistrictType
extends RefCounted
## DistrictType defines district types and their configurations.

## District type enumeration
enum Type {
	POWER_HUB = 0,    ## High power generation
	INDUSTRIAL = 1,   ## High REE generation
	RESEARCH = 2,     ## High research generation
	RESIDENTIAL = 3,  ## Balanced, unit spawning bonus
	MIXED = 4         ## Average of all resources
}

## Get type name string.
static func get_type_name(type: int) -> String:
	match type:
		Type.POWER_HUB: return "Power Hub"
		Type.INDUSTRIAL: return "Industrial"
		Type.RESEARCH: return "Research"
		Type.RESIDENTIAL: return "Residential"
		Type.MIXED: return "Mixed"
		_: return "Unknown"


## Get type from name.
static func get_type_from_name(name: String) -> int:
	match name.to_lower():
		"power hub", "power_hub": return Type.POWER_HUB
		"industrial": return Type.INDUSTRIAL
		"research": return Type.RESEARCH
		"residential": return Type.RESIDENTIAL
		"mixed": return Type.MIXED
		_: return Type.MIXED
