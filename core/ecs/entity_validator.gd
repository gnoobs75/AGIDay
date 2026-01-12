class_name EntityValidator
extends RefCounted
## EntityValidator ensures entities have required fields and valid data.
## Validates entity structure, component presence, and reference integrity.

## Required entity fields
const REQUIRED_FIELDS: Array[String] = ["id", "entity_type"]

## Reference to EntityManager for reference validation
var entity_manager: EntityManager

## Last validation errors
var _last_errors: Array[String] = []


func _init(manager: EntityManager = null) -> void:
	entity_manager = manager


## Set the EntityManager reference.
func set_entity_manager(manager: EntityManager) -> void:
	entity_manager = manager


## Validate an entity has all required fields.
## Returns true if valid, false otherwise.
func validate_entity(entity: Entity) -> bool:
	_last_errors.clear()

	if entity == null:
		_last_errors.append("Entity is null")
		return false

	# Check ID
	if entity.id < 0:
		_last_errors.append("Entity has invalid ID: %d" % entity.id)

	# Check entity type
	if entity.entity_type.is_empty():
		_last_errors.append("Entity has empty entity_type")

	# Validate all components
	for component in entity.get_all_components():
		if not component.validate():
			_last_errors.append("Component '%s' failed validation" % component.get_component_type())

	return _last_errors.is_empty()


## Validate entity data dictionary before deserialization.
func validate_entity_data(data: Dictionary) -> bool:
	_last_errors.clear()

	# Check required fields
	for field in REQUIRED_FIELDS:
		if not data.has(field):
			_last_errors.append("Missing required field: %s" % field)

	# Validate ID if present
	if data.has("id"):
		var id = data["id"]
		if typeof(id) != TYPE_INT or id < 0:
			_last_errors.append("Invalid ID value: %s" % str(id))

	# Validate entity_type if present
	if data.has("entity_type"):
		var entity_type = data["entity_type"]
		if typeof(entity_type) != TYPE_STRING or entity_type.is_empty():
			_last_errors.append("Invalid entity_type: %s" % str(entity_type))

	# Validate components structure if present
	if data.has("components"):
		var components = data["components"]
		if typeof(components) != TYPE_DICTIONARY:
			_last_errors.append("Components must be a Dictionary")
		else:
			for type_name in components:
				if typeof(type_name) != TYPE_STRING:
					_last_errors.append("Component type name must be String: %s" % str(type_name))
				var comp_data = components[type_name]
				if typeof(comp_data) != TYPE_DICTIONARY:
					_last_errors.append("Component data must be Dictionary: %s" % type_name)

	return _last_errors.is_empty()


## Validate that all entity references in a component are valid.
## Returns dictionary of field_name -> referenced_entity_id for invalid references.
func validate_references(entity: Entity) -> Dictionary:
	var invalid_refs: Dictionary = {}

	if entity_manager == null:
		return invalid_refs

	for component in entity.get_all_components():
		var data := component._to_dict()
		_find_invalid_refs(data, component.get_component_type(), invalid_refs)

	return invalid_refs


## Recursively find entity ID references in component data.
func _find_invalid_refs(data: Dictionary, prefix: String, invalid_refs: Dictionary) -> void:
	for key in data:
		var value = data[key]

		# Check for entity_id fields (convention: fields ending in _id or _entity_id)
		if key.ends_with("_id") or key.ends_with("entity_id"):
			if typeof(value) == TYPE_INT and value > 0:
				if not entity_manager.has_entity(value):
					var field_path := "%s.%s" % [prefix, key]
					invalid_refs[field_path] = value

		# Recurse into nested dictionaries
		elif typeof(value) == TYPE_DICTIONARY:
			_find_invalid_refs(value, "%s.%s" % [prefix, key], invalid_refs)

		# Check arrays for entity IDs
		elif typeof(value) == TYPE_ARRAY:
			for i in range(value.size()):
				var item = value[i]
				if typeof(item) == TYPE_DICTIONARY:
					_find_invalid_refs(item, "%s.%s[%d]" % [prefix, key, i], invalid_refs)
				elif typeof(item) == TYPE_INT and key.ends_with("_ids"):
					if item > 0 and not entity_manager.has_entity(item):
						var field_path := "%s.%s[%d]" % [prefix, key, i]
						invalid_refs[field_path] = item


## Validate all entities in EntityManager for reference integrity.
## Returns dictionary mapping entity_id -> invalid_references.
func validate_all_references() -> Dictionary:
	var all_invalid: Dictionary = {}

	if entity_manager == null:
		return all_invalid

	for entity in entity_manager.get_all_entities():
		var invalid := validate_references(entity)
		if not invalid.is_empty():
			all_invalid[entity.id] = invalid

	return all_invalid


## Clean dangling references by setting them to -1 (invalid).
## Returns the number of references cleaned.
func clean_dangling_references(entity: Entity) -> int:
	var cleaned := 0

	if entity_manager == null:
		return cleaned

	for component in entity.get_all_components():
		var data := component._to_dict()
		cleaned += _clean_refs_in_dict(data)
		component._from_dict(data)

	return cleaned


## Recursively clean dangling references in a dictionary.
func _clean_refs_in_dict(data: Dictionary) -> int:
	var cleaned := 0

	for key in data:
		var value = data[key]

		if key.ends_with("_id") or key.ends_with("entity_id"):
			if typeof(value) == TYPE_INT and value > 0:
				if not entity_manager.has_entity(value):
					data[key] = -1
					cleaned += 1

		elif typeof(value) == TYPE_DICTIONARY:
			cleaned += _clean_refs_in_dict(value)

		elif typeof(value) == TYPE_ARRAY:
			for i in range(value.size()):
				var item = value[i]
				if typeof(item) == TYPE_DICTIONARY:
					cleaned += _clean_refs_in_dict(item)
				elif typeof(item) == TYPE_INT and key.ends_with("_ids"):
					if item > 0 and not entity_manager.has_entity(item):
						value[i] = -1
						cleaned += 1

	return cleaned


## Clean all dangling references across all entities.
## Returns total number of references cleaned.
func clean_all_dangling_references() -> int:
	var total_cleaned := 0

	if entity_manager == null:
		return total_cleaned

	for entity in entity_manager.get_all_entities():
		total_cleaned += clean_dangling_references(entity)

	return total_cleaned


## Get validation errors from last validate call.
func get_errors() -> Array[String]:
	return _last_errors.duplicate()


## Validate entity ID string format (TYPE_12345).
func validate_id_string(id_string: String) -> bool:
	return EntityTypes.is_valid_id(id_string)
