class_name ReferenceTracker
extends RefCounted
## ReferenceTracker monitors entity references and handles dangling reference cleanup.
## Provides graceful handling when referenced entities are deleted.

## Signal emitted when a dangling reference is detected
signal dangling_reference_detected(source_entity_id: int, target_entity_id: int, field_path: String)

## Signal emitted when a reference is cleaned
signal reference_cleaned(source_entity_id: int, field_path: String)

## Reference to EntityManager
var entity_manager: EntityManager

## Tracks which entities reference which other entities
## Maps target_entity_id -> Array of {source_id, field_path}
var _reference_graph: Dictionary = {}

## Whether to automatically clean dangling references
var auto_clean: bool = true


func _init(manager: EntityManager = null) -> void:
	entity_manager = manager
	if entity_manager:
		_connect_signals()


## Set the EntityManager and connect to its signals.
func set_entity_manager(manager: EntityManager) -> void:
	if entity_manager:
		_disconnect_signals()

	entity_manager = manager

	if entity_manager:
		_connect_signals()


## Connect to EntityManager signals.
func _connect_signals() -> void:
	if not entity_manager.entity_destroyed.is_connected(_on_entity_destroyed):
		entity_manager.entity_destroyed.connect(_on_entity_destroyed)


## Disconnect from EntityManager signals.
func _disconnect_signals() -> void:
	if entity_manager.entity_destroyed.is_connected(_on_entity_destroyed):
		entity_manager.entity_destroyed.disconnect(_on_entity_destroyed)


## Register a reference from one entity to another.
func register_reference(source_entity_id: int, target_entity_id: int, field_path: String) -> void:
	if target_entity_id < 0:
		return  # Don't track invalid references

	if not _reference_graph.has(target_entity_id):
		_reference_graph[target_entity_id] = []

	var ref_info := {
		"source_id": source_entity_id,
		"field_path": field_path
	}

	# Avoid duplicates
	for existing in _reference_graph[target_entity_id]:
		if existing.source_id == source_entity_id and existing.field_path == field_path:
			return

	_reference_graph[target_entity_id].append(ref_info)


## Unregister a reference.
func unregister_reference(source_entity_id: int, target_entity_id: int, field_path: String) -> void:
	if not _reference_graph.has(target_entity_id):
		return

	var refs: Array = _reference_graph[target_entity_id]
	for i in range(refs.size() - 1, -1, -1):
		var ref = refs[i]
		if ref.source_id == source_entity_id and ref.field_path == field_path:
			refs.remove_at(i)

	if refs.is_empty():
		_reference_graph.erase(target_entity_id)


## Unregister all references from a source entity.
func unregister_all_from_source(source_entity_id: int) -> void:
	for target_id in _reference_graph.keys():
		var refs: Array = _reference_graph[target_id]
		for i in range(refs.size() - 1, -1, -1):
			if refs[i].source_id == source_entity_id:
				refs.remove_at(i)

		if refs.is_empty():
			_reference_graph.erase(target_id)


## Get all entities that reference a target entity.
func get_referencing_entities(target_entity_id: int) -> Array[int]:
	var result: Array[int] = []

	if not _reference_graph.has(target_entity_id):
		return result

	var seen: Dictionary = {}
	for ref in _reference_graph[target_entity_id]:
		var source_id: int = ref.source_id
		if not seen.has(source_id):
			result.append(source_id)
			seen[source_id] = true

	return result


## Get detailed reference information for a target entity.
func get_reference_details(target_entity_id: int) -> Array:
	if not _reference_graph.has(target_entity_id):
		return []

	return _reference_graph[target_entity_id].duplicate()


## Check if an entity is referenced by any other entity.
func is_referenced(target_entity_id: int) -> bool:
	return _reference_graph.has(target_entity_id) and not _reference_graph[target_entity_id].is_empty()


## Handle entity destruction - clean up dangling references.
func _on_entity_destroyed(entity_id: int) -> void:
	if not _reference_graph.has(entity_id):
		return

	var refs: Array = _reference_graph[entity_id]

	for ref in refs:
		var source_id: int = ref.source_id
		var field_path: String = ref.field_path

		dangling_reference_detected.emit(source_id, entity_id, field_path)

		if auto_clean:
			_clean_reference(source_id, field_path)
			reference_cleaned.emit(source_id, field_path)

	_reference_graph.erase(entity_id)


## Clean a specific reference by setting it to -1.
func _clean_reference(source_entity_id: int, field_path: String) -> bool:
	if entity_manager == null:
		return false

	var entity := entity_manager.get_entity(source_entity_id)
	if entity == null:
		return false

	# Parse field path: "ComponentType.field.subfield"
	var parts := field_path.split(".")
	if parts.size() < 2:
		return false

	var component_type := parts[0]
	var component := entity.get_component(component_type)
	if component == null:
		return false

	var data := component._to_dict()
	if _set_nested_value(data, parts.slice(1), -1):
		component._from_dict(data)
		return true

	return false


## Set a nested value in a dictionary using a path array.
func _set_nested_value(data: Dictionary, path: Array, value: Variant) -> bool:
	if path.is_empty():
		return false

	var current = data
	for i in range(path.size() - 1):
		var key = path[i]

		# Handle array index notation: field[0]
		var array_match := _parse_array_index(key)
		if array_match.has("name"):
			var arr_name: String = array_match.name
			var arr_index: int = array_match.index

			if not current.has(arr_name) or typeof(current[arr_name]) != TYPE_ARRAY:
				return false

			var arr: Array = current[arr_name]
			if arr_index < 0 or arr_index >= arr.size():
				return false

			current = arr[arr_index]
		else:
			if not current.has(key):
				return false
			current = current[key]

		if typeof(current) != TYPE_DICTIONARY:
			return false

	# Set the final value
	var final_key = path[path.size() - 1]
	var array_match := _parse_array_index(final_key)

	if array_match.has("name"):
		var arr_name: String = array_match.name
		var arr_index: int = array_match.index

		if current.has(arr_name) and typeof(current[arr_name]) == TYPE_ARRAY:
			var arr: Array = current[arr_name]
			if arr_index >= 0 and arr_index < arr.size():
				arr[arr_index] = value
				return true
		return false
	else:
		current[final_key] = value
		return true


## Parse array index from field name like "field[0]".
func _parse_array_index(field: String) -> Dictionary:
	var bracket_pos := field.find("[")
	if bracket_pos < 0:
		return {}

	var name := field.substr(0, bracket_pos)
	var index_str := field.substr(bracket_pos + 1, field.length() - bracket_pos - 2)

	if not index_str.is_valid_int():
		return {}

	return {"name": name, "index": int(index_str)}


## Scan an entity and register all its references.
func scan_entity_references(entity: Entity) -> void:
	for component in entity.get_all_components():
		var data := component._to_dict()
		_scan_dict_for_refs(entity.id, component.get_component_type(), data)


## Recursively scan dictionary for entity references.
func _scan_dict_for_refs(source_id: int, prefix: String, data: Dictionary) -> void:
	for key in data:
		var value = data[key]
		var field_path := "%s.%s" % [prefix, key]

		if key.ends_with("_id") or key.ends_with("entity_id"):
			if typeof(value) == TYPE_INT and value > 0:
				register_reference(source_id, value, field_path)

		elif typeof(value) == TYPE_DICTIONARY:
			_scan_dict_for_refs(source_id, field_path, value)

		elif typeof(value) == TYPE_ARRAY:
			for i in range(value.size()):
				var item = value[i]
				if typeof(item) == TYPE_DICTIONARY:
					_scan_dict_for_refs(source_id, "%s[%d]" % [field_path, i], item)
				elif typeof(item) == TYPE_INT and key.ends_with("_ids"):
					if item > 0:
						register_reference(source_id, item, "%s[%d]" % [field_path, i])


## Clear all tracked references.
func clear() -> void:
	_reference_graph.clear()


## Get statistics about tracked references.
func get_stats() -> Dictionary:
	var total_refs := 0
	for refs in _reference_graph.values():
		total_refs += refs.size()

	return {
		"tracked_targets": _reference_graph.size(),
		"total_references": total_refs,
		"auto_clean": auto_clean
	}
