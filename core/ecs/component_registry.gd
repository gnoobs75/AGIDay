class_name ComponentRegistryBase
extends RefCounted
## ComponentRegistry manages component type registration, schema validation, and factory creation.
## Used for deserializing entities with their components from save files.
## Supports schema-based validation for type safety.

## Dictionary mapping component type names to factory callables
var _factories: Dictionary = {}

## Dictionary mapping component type names to component class scripts
var _scripts: Dictionary = {}

## Dictionary mapping component type names to ComponentSchema instances
var _schemas: Dictionary = {}

## Validation cache for component types
var _validation_cache: Dictionary = {}

## Last validation errors
var _last_errors: Array[String] = []


## Register a component type with a factory function.
## The factory should return a new instance of the component.
func register(type_name: String, factory: Callable, schema: ComponentSchema = null) -> void:
	_factories[type_name] = factory
	if schema != null:
		_schemas[type_name] = schema
	_validation_cache.erase(type_name)


## Register a component type using its script.
## The script must extend Component and have a parameterless _init.
func register_script(type_name: String, script: GDScript, schema: ComponentSchema = null) -> void:
	_scripts[type_name] = script
	if schema != null:
		_schemas[type_name] = schema
	_validation_cache.erase(type_name)


## Register a schema for an existing component type.
func register_schema(type_name: String, schema: ComponentSchema) -> void:
	_schemas[type_name] = schema
	_validation_cache.erase(type_name)


## Unregister a component type.
func unregister(type_name: String) -> void:
	_factories.erase(type_name)
	_scripts.erase(type_name)
	_schemas.erase(type_name)
	_validation_cache.erase(type_name)


## Check if a component type is registered.
func is_registered(type_name: String) -> bool:
	return _factories.has(type_name) or _scripts.has(type_name)


## Check if a component type has a schema.
func has_schema(type_name: String) -> bool:
	return _schemas.has(type_name)


## Get the schema for a component type.
func get_schema(type_name: String) -> ComponentSchema:
	return _schemas.get(type_name)


## Create a new component instance by type name.
## Returns null if type is not registered.
func create_component(type_name: String) -> Component:
	if _factories.has(type_name):
		var component = _factories[type_name].call()
		if component is Component:
			return component
		push_error("ComponentRegistry: Factory for '%s' did not return a Component" % type_name)
		return null

	if _scripts.has(type_name):
		var script: GDScript = _scripts[type_name]
		var component = script.new()
		if component is Component:
			return component
		push_error("ComponentRegistry: Script for '%s' did not create a Component" % type_name)
		return null

	push_error("ComponentRegistry: Unknown component type '%s'" % type_name)
	return null


## Create and initialize a component from dictionary data.
## Validates against schema if available.
## Returns null if type is not registered, validation fails, or initialization fails.
func create_from_dict(data: Dictionary, validate_schema: bool = true) -> Component:
	_last_errors.clear()

	var type_name: String = data.get("type", "")
	if type_name.is_empty():
		_last_errors.append("Missing 'type' in component data")
		push_error("ComponentRegistry: Missing 'type' in component data")
		return null

	# Validate against schema if available and validation requested
	if validate_schema and _schemas.has(type_name):
		var schema: ComponentSchema = _schemas[type_name]
		if not schema.validate(data):
			_last_errors = schema.get_errors()
			for error in _last_errors:
				push_error("ComponentRegistry: Schema validation failed for '%s': %s" % [type_name, error])
			return null

	var component := create_component(type_name)
	if component == null:
		_last_errors.append("Failed to create component of type '%s'" % type_name)
		return null

	component._from_dict(data)
	return component


## Validate component data against its schema without creating.
## Returns true if valid or no schema exists.
func validate_data(type_name: String, data: Dictionary) -> bool:
	_last_errors.clear()

	if not _schemas.has(type_name):
		return true  # No schema means no validation

	var schema: ComponentSchema = _schemas[type_name]
	var is_valid := schema.validate(data)
	if not is_valid:
		_last_errors = schema.get_errors()

	return is_valid


## Get validation errors from last operation.
func get_errors() -> Array[String]:
	return _last_errors.duplicate()


## Get all registered component type names.
func get_registered_types() -> Array[String]:
	var types: Array[String] = []

	for type_name in _factories.keys():
		types.append(type_name)

	for type_name in _scripts.keys():
		if type_name not in types:
			types.append(type_name)

	return types


## Validate a component type by creating a test instance.
## Results are cached for performance.
func validate_type(type_name: String) -> bool:
	if _validation_cache.has(type_name):
		return _validation_cache[type_name]

	var component := create_component(type_name)
	if component == null:
		_validation_cache[type_name] = false
		return false

	var is_valid := component.validate()
	_validation_cache[type_name] = is_valid
	return is_valid


## Clear validation cache (call after modifying registrations).
func clear_validation_cache() -> void:
	_validation_cache.clear()


## Get registration count.
func get_count() -> int:
	var types := get_registered_types()
	return types.size()


## Batch register multiple component scripts from a dictionary.
## Dictionary should map type names to GDScript resources.
func register_scripts_batch(scripts: Dictionary) -> void:
	for type_name in scripts:
		var script = scripts[type_name]
		if script is GDScript:
			register_script(type_name, script)
		else:
			push_warning("ComponentRegistry: Skipping non-GDScript entry '%s'" % type_name)


## Apply schema defaults to component data.
func apply_defaults(type_name: String, data: Dictionary) -> Dictionary:
	if not _schemas.has(type_name):
		return data

	var schema: ComponentSchema = _schemas[type_name]
	return schema.apply_defaults(data)


## Serialize registry information (for debugging).
func to_dict() -> Dictionary:
	var schema_info: Dictionary = {}
	for type_name in _schemas:
		schema_info[type_name] = _schemas[type_name].to_dict()

	return {
		"factory_count": _factories.size(),
		"script_count": _scripts.size(),
		"schema_count": _schemas.size(),
		"registered_types": get_registered_types(),
		"schemas": schema_info
	}
