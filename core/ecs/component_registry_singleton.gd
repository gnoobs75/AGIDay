extends Node
## ComponentRegistry Singleton - Global registry for component type definitions.
## Maintains schemas, validation rules, and serialization logic for all components.
## Set as autoload: ComponentRegistry

## Signal emitted when a component type is registered
signal component_registered(type_name: String)

## Signal emitted when a component schema is updated
signal schema_updated(type_name: String, old_version: int, new_version: int)

## Dictionary mapping component type names to factory callables
var _factories: Dictionary = {}

## Dictionary mapping component type names to component class scripts
var _scripts: Dictionary = {}

## Dictionary mapping component type names to ComponentSchema instances
var _schemas: Dictionary = {}

## Dictionary mapping component type names to version numbers
var _versions: Dictionary = {}

## Dictionary mapping component type names to version migrators
## Migrator is a Callable that takes (old_data, old_version, new_version) -> migrated_data
var _migrators: Dictionary = {}

## Validation cache for component types
var _validation_cache: Dictionary = {}

## Last validation errors
var _last_errors: Array[String] = []

## Performance tracking
var _last_validation_time_usec: int = 0
var _last_lookup_time_usec: int = 0


func _ready() -> void:
	print("ComponentRegistry: Initialized")


# =============================================================================
# Registration API
# =============================================================================

## Register a component type with a factory function.
## The factory should return a new instance of the component.
func register(type_name: String, factory: Callable, schema: ComponentSchema = null, version: int = 1) -> void:
	_factories[type_name] = factory
	_versions[type_name] = version
	if schema != null:
		_schemas[type_name] = schema
	_validation_cache.erase(type_name)
	component_registered.emit(type_name)


## Register a component type using its script.
## The script must extend Component and have a parameterless _init.
func register_script(type_name: String, script: GDScript, schema: ComponentSchema = null, version: int = 1) -> void:
	_scripts[type_name] = script
	_versions[type_name] = version
	if schema != null:
		_schemas[type_name] = schema
	_validation_cache.erase(type_name)
	component_registered.emit(type_name)


## Register a schema for an existing component type.
func register_schema(type_name: String, schema: ComponentSchema) -> void:
	_schemas[type_name] = schema
	_validation_cache.erase(type_name)


## Register a version migrator for a component type.
## Migrator signature: func(data: Dictionary, from_version: int, to_version: int) -> Dictionary
func register_migrator(type_name: String, migrator: Callable) -> void:
	_migrators[type_name] = migrator


## Update a component's version (triggers migration on load).
func update_version(type_name: String, new_version: int, new_schema: ComponentSchema = null) -> void:
	var old_version := _versions.get(type_name, 1)
	_versions[type_name] = new_version
	if new_schema != null:
		_schemas[type_name] = new_schema
	_validation_cache.erase(type_name)
	schema_updated.emit(type_name, old_version, new_version)


## Unregister a component type.
func unregister(type_name: String) -> void:
	_factories.erase(type_name)
	_scripts.erase(type_name)
	_schemas.erase(type_name)
	_versions.erase(type_name)
	_migrators.erase(type_name)
	_validation_cache.erase(type_name)


## Check if a component type is registered.
func is_registered(type_name: String) -> bool:
	return _factories.has(type_name) or _scripts.has(type_name)


## Check if a component type has a schema.
func has_schema(type_name: String) -> bool:
	return _schemas.has(type_name)


## Get the schema for a component type.
func get_schema(type_name: String) -> ComponentSchema:
	var start := Time.get_ticks_usec()
	var result: ComponentSchema = _schemas.get(type_name)
	_last_lookup_time_usec = Time.get_ticks_usec() - start
	return result


## Get the version for a component type.
func get_version(type_name: String) -> int:
	return _versions.get(type_name, 1)


## Get all registered component type names.
func get_registered_types() -> Array[String]:
	var types: Array[String] = []

	for type_name in _factories.keys():
		types.append(type_name)

	for type_name in _scripts.keys():
		if type_name not in types:
			types.append(type_name)

	return types


## Get registration count.
func get_count() -> int:
	return get_registered_types().size()


# =============================================================================
# Component Creation API
# =============================================================================

## Create a new component instance by type name.
## Returns null if type is not registered.
func create_component(type_name: String) -> Component:
	if _factories.has(type_name):
		var component = _factories[type_name].call()
		if component is Component:
			component.version = _versions.get(type_name, 1)
			return component
		push_error("ComponentRegistry: Factory for '%s' did not return a Component" % type_name)
		return null

	if _scripts.has(type_name):
		var script: GDScript = _scripts[type_name]
		var component = script.new()
		if component is Component:
			component.version = _versions.get(type_name, 1)
			return component
		push_error("ComponentRegistry: Script for '%s' did not create a Component" % type_name)
		return null

	push_error("ComponentRegistry: Unknown component type '%s'" % type_name)
	return null


# =============================================================================
# Validation API
# =============================================================================

## Validate component data against its schema.
## Returns true if valid, false otherwise.
## Call get_validation_errors() for detailed error messages.
func validate_component(type_name: String, data: Dictionary) -> bool:
	var start := Time.get_ticks_usec()
	_last_errors.clear()

	if not _schemas.has(type_name):
		_last_validation_time_usec = Time.get_ticks_usec() - start
		return true  # No schema means no validation

	var schema: ComponentSchema = _schemas[type_name]
	var is_valid := schema.validate(data)
	if not is_valid:
		_last_errors = schema.get_errors()

	_last_validation_time_usec = Time.get_ticks_usec() - start
	return is_valid


## Validate a component instance.
func validate_component_instance(component: Component) -> bool:
	var type_name := component.get_component_type()
	var data := component._to_dict()
	return validate_component(type_name, data)


## Get validation errors from last validate call.
func get_validation_errors() -> Array[String]:
	return _last_errors.duplicate()


## Clear validation cache (call after modifying registrations).
func clear_validation_cache() -> void:
	_validation_cache.clear()


# =============================================================================
# Serialization API
# =============================================================================

## Serialize a component to dictionary format.
func serialize_component(component: Component) -> Dictionary:
	var data := component._to_dict()
	data["_registry_version"] = _versions.get(component.get_component_type(), 1)
	return data


## Deserialize a component from dictionary format.
## Handles version migration automatically.
func deserialize_component(data: Dictionary) -> Component:
	_last_errors.clear()

	var type_name: String = data.get("type", "")
	if type_name.is_empty():
		_last_errors.append("Missing 'type' in component data")
		return null

	# Check for version migration
	var data_version: int = data.get("_registry_version", data.get("version", 1))
	var current_version: int = _versions.get(type_name, 1)

	var migrated_data := data.duplicate(true)
	migrated_data.erase("_registry_version")

	if data_version < current_version:
		migrated_data = _migrate_data(type_name, migrated_data, data_version, current_version)
		if migrated_data.is_empty():
			_last_errors.append("Migration failed for '%s' from v%d to v%d" % [type_name, data_version, current_version])
			return null

	# Validate against current schema
	if _schemas.has(type_name):
		var schema: ComponentSchema = _schemas[type_name]
		if not schema.validate(migrated_data):
			_last_errors = schema.get_errors()
			return null

	# Create and populate component
	var component := create_component(type_name)
	if component == null:
		_last_errors.append("Failed to create component of type '%s'" % type_name)
		return null

	component._from_dict(migrated_data)
	return component


## Migrate component data from one version to another.
func _migrate_data(type_name: String, data: Dictionary, from_version: int, to_version: int) -> Dictionary:
	if not _migrators.has(type_name):
		# No migrator - return data as-is (may fail validation)
		push_warning("ComponentRegistry: No migrator for '%s', data may be incompatible" % type_name)
		return data

	var migrator: Callable = _migrators[type_name]
	return migrator.call(data, from_version, to_version)


## Create component from dictionary with validation.
func create_from_dict(data: Dictionary, validate_schema: bool = true) -> Component:
	return deserialize_component(data)


# =============================================================================
# Schema Introspection API
# =============================================================================

## Get schema information for debugging/tooling.
func get_schema_info(type_name: String) -> Dictionary:
	if not _schemas.has(type_name):
		return {}

	var schema: ComponentSchema = _schemas[type_name]
	return {
		"type": type_name,
		"version": _versions.get(type_name, 1),
		"has_migrator": _migrators.has(type_name),
		"schema": schema.to_dict()
	}


## Get all schemas information.
func get_all_schema_info() -> Dictionary:
	var info: Dictionary = {}
	for type_name in _schemas:
		info[type_name] = get_schema_info(type_name)
	return info


## Apply schema defaults to component data.
func apply_defaults(type_name: String, data: Dictionary) -> Dictionary:
	if not _schemas.has(type_name):
		return data

	var schema: ComponentSchema = _schemas[type_name]
	return schema.apply_defaults(data)


# =============================================================================
# Performance API
# =============================================================================

## Get last validation time in microseconds.
func get_last_validation_time_usec() -> int:
	return _last_validation_time_usec


## Get last lookup time in microseconds.
func get_last_lookup_time_usec() -> int:
	return _last_lookup_time_usec


## Get registry statistics.
func get_stats() -> Dictionary:
	return {
		"registered_types": get_registered_types().size(),
		"schemas_count": _schemas.size(),
		"migrators_count": _migrators.size(),
		"last_validation_time_usec": _last_validation_time_usec,
		"last_lookup_time_usec": _last_lookup_time_usec
	}


## Serialize registry information (for debugging).
func to_dict() -> Dictionary:
	var schema_info: Dictionary = {}
	for type_name in _schemas:
		schema_info[type_name] = _schemas[type_name].to_dict()

	var version_info: Dictionary = {}
	for type_name in _versions:
		version_info[type_name] = _versions[type_name]

	return {
		"factory_count": _factories.size(),
		"script_count": _scripts.size(),
		"schema_count": _schemas.size(),
		"registered_types": get_registered_types(),
		"versions": version_info,
		"schemas": schema_info
	}
