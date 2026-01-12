class_name EntityTypes
extends RefCounted
## EntityTypes defines the standard entity type prefixes and ID generation.
## Entity IDs follow UPPER_SNAKE_CASE with type prefix (e.g., UNIT_12345).

## Standard entity type prefixes
enum Type {
	UNIT,
	BUILDING,
	PROJECTILE,
	EFFECT,
	DISTRICT,
	RESOURCE,
	FACTORY,
	CUSTOM
}

## Type prefix strings for ID generation
const TYPE_PREFIXES: Dictionary = {
	Type.UNIT: "UNIT",
	Type.BUILDING: "BUILDING",
	Type.PROJECTILE: "PROJECTILE",
	Type.EFFECT: "EFFECT",
	Type.DISTRICT: "DISTRICT",
	Type.RESOURCE: "RESOURCE",
	Type.FACTORY: "FACTORY",
	Type.CUSTOM: "CUSTOM"
}

## PascalCase type names for entity_type field
const TYPE_NAMES: Dictionary = {
	Type.UNIT: "Unit",
	Type.BUILDING: "Building",
	Type.PROJECTILE: "Projectile",
	Type.EFFECT: "Effect",
	Type.DISTRICT: "District",
	Type.RESOURCE: "Resource",
	Type.FACTORY: "Factory",
	Type.CUSTOM: "Custom"
}

## Reverse lookup from prefix to type
static var _prefix_to_type: Dictionary = {}


static func _static_init() -> void:
	for type in TYPE_PREFIXES:
		_prefix_to_type[TYPE_PREFIXES[type]] = type


## Generate a formatted entity ID string.
## Example: UNIT_12345
static func generate_id_string(type: Type, numeric_id: int) -> String:
	var prefix: String = TYPE_PREFIXES.get(type, "CUSTOM")
	return "%s_%d" % [prefix, numeric_id]


## Parse an entity ID string to extract type and numeric ID.
## Returns dictionary with "type" and "numeric_id" keys, or null if invalid.
static func parse_id_string(id_string: String) -> Variant:
	var parts := id_string.split("_", false, 1)
	if parts.size() != 2:
		return null

	var prefix := parts[0]
	var numeric_str := parts[1]

	if not numeric_str.is_valid_int():
		return null

	var type: Type = _prefix_to_type.get(prefix, Type.CUSTOM)

	return {
		"type": type,
		"numeric_id": int(numeric_str),
		"prefix": prefix
	}


## Get the PascalCase type name for an entity type.
static func get_type_name(type: Type) -> String:
	return TYPE_NAMES.get(type, "Custom")


## Get the type enum from a PascalCase type name.
static func get_type_from_name(type_name: String) -> Type:
	for type in TYPE_NAMES:
		if TYPE_NAMES[type] == type_name:
			return type
	return Type.CUSTOM


## Get the prefix string for an entity type.
static func get_prefix(type: Type) -> String:
	return TYPE_PREFIXES.get(type, "CUSTOM")


## Validate that an ID string is properly formatted.
static func is_valid_id(id_string: String) -> bool:
	return parse_id_string(id_string) != null
