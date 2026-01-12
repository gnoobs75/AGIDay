class_name ComponentRegistrar
extends RefCounted
## ComponentRegistrar registers all game components with the ComponentRegistry.
## Call register_all() during game initialization.

## Register all game components with the global ComponentRegistry.
static func register_all(registry: Node) -> void:
	print("ComponentRegistrar: Registering all game components...")

	# Health Component
	registry.register(
		"HealthComponent",
		func() -> Component: return HealthComponent.new(),
		HealthComponent.get_schema(),
		1
	)

	# Movement Component
	registry.register(
		"MovementComponent",
		func() -> Component: return MovementComponent.new(),
		MovementComponent.get_schema(),
		1
	)

	# Combat Component
	registry.register(
		"CombatComponent",
		func() -> Component: return CombatComponent.new(),
		CombatComponent.get_schema(),
		1
	)

	# Faction Component
	registry.register(
		"FactionComponent",
		func() -> Component: return FactionComponent.new(),
		FactionComponent.get_schema(),
		1
	)

	# Register version migrators
	_register_migrators(registry)

	print("ComponentRegistrar: Registered %d component types" % registry.get_count())


## Register version migrators for backward compatibility.
static func _register_migrators(registry: Node) -> void:
	# HealthComponent migrator (example for future version changes)
	registry.register_migrator("HealthComponent", func(data: Dictionary, from_v: int, to_v: int) -> Dictionary:
		var migrated := data.duplicate(true)

		# Example: if upgrading from v1 to v2, add new field
		if from_v < 2 and to_v >= 2:
			if not migrated.get("data", {}).has("shield"):
				migrated["data"]["shield"] = 0.0

		return migrated
	)

	# MovementComponent migrator
	registry.register_migrator("MovementComponent", func(data: Dictionary, from_v: int, to_v: int) -> Dictionary:
		var migrated := data.duplicate(true)

		# Example: if upgrading from v1 to v2, convert position format
		if from_v < 2 and to_v >= 2:
			var component_data: Dictionary = migrated.get("data", {})
			# Handle any schema changes here

		return migrated
	)


## Validate all registered components have valid schemas.
static func validate_all(registry: Node) -> bool:
	var all_valid := true

	for type_name in registry.get_registered_types():
		var component = registry.create_component(type_name)
		if component != null:
			if not registry.validate_component_instance(component):
				push_error("ComponentRegistrar: Validation failed for '%s'" % type_name)
				all_valid = false
		else:
			push_error("ComponentRegistrar: Failed to create '%s'" % type_name)
			all_valid = false

	return all_valid


## Get a summary of registered components.
static func get_summary(registry: Node) -> Dictionary:
	var types := registry.get_registered_types()
	var summary: Dictionary = {
		"count": types.size(),
		"types": types,
		"schemas": {}
	}

	for type_name in types:
		var info := registry.get_schema_info(type_name)
		summary["schemas"][type_name] = info

	return summary
