class_name ZoneType
extends RefCounted
## ZoneType defines the classification of city zones for strategic gameplay.

## Zone type enumeration
enum Type {
	ZERG_ALLEY = 0,      ## Narrow passages favoring swarm units
	TANK_BOULEVARD = 1,  ## Wide roads for heavy vehicles
	MIXED_ZONE = 2,      ## Balanced areas for all unit types
	INDUSTRIAL = 3,      ## Factory and manufacturing areas
	RESIDENTIAL = 4,     ## Housing districts
	COMMERCIAL = 5,      ## Market and trade areas
	POWER_HUB = 6        ## Power generation facilities
}

## Get display name for type.
static func get_name(type: int) -> String:
	match type:
		Type.ZERG_ALLEY: return "Zerg Alley"
		Type.TANK_BOULEVARD: return "Tank Boulevard"
		Type.MIXED_ZONE: return "Mixed Zone"
		Type.INDUSTRIAL: return "Industrial"
		Type.RESIDENTIAL: return "Residential"
		Type.COMMERCIAL: return "Commercial"
		Type.POWER_HUB: return "Power Hub"
	return "Unknown"


## Get faction affinities for zone type.
static func get_faction_affinities(type: int) -> Dictionary:
	match type:
		Type.ZERG_ALLEY:
			return {"swarm": 1.8, "heavy": 0.3, "ranged": 0.7}
		Type.TANK_BOULEVARD:
			return {"swarm": 0.5, "heavy": 2.0, "ranged": 1.2}
		Type.MIXED_ZONE:
			return {"swarm": 1.0, "heavy": 1.0, "ranged": 1.0}
		Type.INDUSTRIAL:
			return {"swarm": 0.8, "heavy": 1.5, "ranged": 0.9}
		Type.RESIDENTIAL:
			return {"swarm": 1.3, "heavy": 0.6, "ranged": 1.1}
		Type.COMMERCIAL:
			return {"swarm": 1.1, "heavy": 0.8, "ranged": 1.2}
		Type.POWER_HUB:
			return {"swarm": 0.7, "heavy": 1.3, "ranged": 1.0}
	return {}


## Get default density for zone type.
static func get_default_density(type: int) -> float:
	match type:
		Type.ZERG_ALLEY: return 0.9
		Type.TANK_BOULEVARD: return 0.4
		Type.MIXED_ZONE: return 0.7
		Type.INDUSTRIAL: return 0.6
		Type.RESIDENTIAL: return 0.8
		Type.COMMERCIAL: return 0.75
		Type.POWER_HUB: return 0.5
	return 0.5


## Get all zone types.
static func get_all_types() -> Array[int]:
	return [
		Type.ZERG_ALLEY,
		Type.TANK_BOULEVARD,
		Type.MIXED_ZONE,
		Type.INDUSTRIAL,
		Type.RESIDENTIAL,
		Type.COMMERCIAL,
		Type.POWER_HUB
	]


## Get zone type from string.
static func from_string(name: String) -> int:
	match name.to_lower():
		"zerg_alley", "zerg alley": return Type.ZERG_ALLEY
		"tank_boulevard", "tank boulevard": return Type.TANK_BOULEVARD
		"mixed_zone", "mixed zone", "mixed": return Type.MIXED_ZONE
		"industrial": return Type.INDUSTRIAL
		"residential": return Type.RESIDENTIAL
		"commercial": return Type.COMMERCIAL
		"power_hub", "power hub": return Type.POWER_HUB
	return Type.MIXED_ZONE
