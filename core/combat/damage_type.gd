class_name DamageType
extends RefCounted
## DamageType defines the four universal damage types and their properties.

## Damage type enumeration
enum Type {
	KINETIC = 0,     ## Physical projectile damage
	ENERGY = 1,      ## Laser/plasma energy damage
	EXPLOSIVE = 2,   ## Area of effect blast damage
	NANO_SHRED = 3   ## Armor-piercing nanite damage
}

## Damage types that cause knockback
const KNOCKBACK_TYPES := [Type.KINETIC, Type.EXPLOSIVE]

## Get display name.
static func get_name(type: int) -> String:
	match type:
		Type.KINETIC: return "Kinetic"
		Type.ENERGY: return "Energy"
		Type.EXPLOSIVE: return "Explosive"
		Type.NANO_SHRED: return "Nano-Shred"
	return "Unknown"


## Check if damage type causes knockback.
static func causes_knockback(type: int) -> bool:
	return type in KNOCKBACK_TYPES


## Get all damage types.
static func get_all_types() -> Array[int]:
	return [Type.KINETIC, Type.ENERGY, Type.EXPLOSIVE, Type.NANO_SHRED]


## Get damage type from string.
static func from_string(name: String) -> int:
	match name.to_lower():
		"kinetic": return Type.KINETIC
		"energy": return Type.ENERGY
		"explosive": return Type.EXPLOSIVE
		"nano_shred", "nanoshred", "nano": return Type.NANO_SHRED
	return Type.KINETIC
