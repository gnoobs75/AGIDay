class_name UnitFactory
extends RefCounted
## UnitFactory creates Unit instances from templates with faction multipliers applied.
## Optimized for mass unit creation with template caching and component pooling.

signal unit_created(unit: Unit)
signal unit_creation_failed(template_id: String, reason: String)

## Reference to template manager (set at initialization)
var _template_manager: UnitTemplateManagerClass = null

## Reference to faction manager (set at initialization)
var _faction_manager: FactionManagerClass = null

## Stats cache to avoid recalculating (template_id -> faction_id -> stats)
var _stats_cache: Dictionary = {}

## Cache expiry time in milliseconds
var _cache_expiry_ms: int = 60000  # 1 minute

## Timestamp of last cache clear
var _last_cache_clear: int = 0


func _init(template_manager: UnitTemplateManagerClass = null, faction_manager: FactionManagerClass = null) -> void:
	_template_manager = template_manager
	_faction_manager = faction_manager
	_last_cache_clear = Time.get_ticks_msec()


## Set the template manager reference.
func set_template_manager(manager: UnitTemplateManagerClass) -> void:
	_template_manager = manager
	clear_cache()


## Set the faction manager reference.
func set_faction_manager(manager: FactionManagerClass) -> void:
	_faction_manager = manager
	clear_cache()


## Create a unit from a template ID.
func create_unit(template_id: String, position: Vector3 = Vector3.ZERO) -> Unit:
	if _template_manager == null:
		unit_creation_failed.emit(template_id, "Template manager not set")
		return null

	var template := _template_manager.get_template(template_id)
	if template == null:
		unit_creation_failed.emit(template_id, "Template not found: %s" % template_id)
		return null

	return create_from_template(template, position)


## Create a unit from a template and position.
func create_from_template(template: UnitTemplate, position: Vector3 = Vector3.ZERO) -> Unit:
	if not template.is_valid:
		unit_creation_failed.emit(template.template_id, "Template is invalid")
		return null

	# Get faction config for multipliers
	var faction_config: FactionConfig = null
	if _faction_manager != null:
		faction_config = _faction_manager.get_faction_by_key(template.faction_key)

	# Get faction ID
	var faction_id := 0
	if faction_config != null:
		faction_id = faction_config.faction_id

	# Create the unit
	var unit := Unit.new()
	var unit_id := Unit.generate_unit_id()
	unit.initialize_unit(unit_id, faction_id, template.unit_type)

	# Get stats with faction multipliers applied
	var stats := _get_cached_stats(template, faction_config)

	# Create and configure health component
	var health := HealthComponent.new()
	health.set_max_health(stats.get("max_health", 100.0))
	health.set_current_health(stats.get("max_health", 100.0))
	health.data["regeneration_rate"] = stats.get("health_regen", 0.0)
	unit.add_component(health)

	# Create and configure movement component
	var movement := MovementComponent.new()
	movement.set_position(position)
	movement.data["max_speed"] = stats.get("max_speed", 10.0)
	movement.data["acceleration"] = stats.get("acceleration", 50.0)
	movement.data["turn_rate"] = stats.get("turn_rate", 5.0)
	unit.add_component(movement)

	# Create combat component if unit has combat stats
	if stats.get("base_damage", 0.0) > 0:
		var combat := CombatComponent.new()
		combat.data["base_damage"] = stats.get("base_damage", 10.0)
		combat.data["attack_speed"] = stats.get("attack_speed", 1.0)
		combat.data["attack_range"] = stats.get("attack_range", 10.0)
		combat.data["armor"] = stats.get("armor", 0.0)
		unit.add_component(combat)

	# Create faction component
	var faction_comp := FactionComponent.new()
	faction_comp.data["faction_id"] = faction_id
	faction_comp.data["faction_key"] = template.faction_key
	unit.add_component(faction_comp)

	unit_created.emit(unit)
	return unit


## Create multiple units from the same template (optimized for batch creation).
func create_units_batch(template_id: String, count: int, positions: Array[Vector3] = []) -> Array[Unit]:
	var units: Array[Unit] = []

	if _template_manager == null:
		unit_creation_failed.emit(template_id, "Template manager not set")
		return units

	var template := _template_manager.get_template(template_id)
	if template == null:
		unit_creation_failed.emit(template_id, "Template not found: %s" % template_id)
		return units

	# Pre-cache stats for this template
	var faction_config: FactionConfig = null
	if _faction_manager != null:
		faction_config = _faction_manager.get_faction_by_key(template.faction_key)

	var stats := _get_cached_stats(template, faction_config)
	var faction_id := faction_config.faction_id if faction_config != null else 0

	# Create units in batch
	for i in range(count):
		var position := Vector3.ZERO
		if i < positions.size():
			position = positions[i]

		var unit := _create_unit_internal(template, faction_id, stats, position)
		if unit != null:
			units.append(unit)
			unit_created.emit(unit)

	return units


## Internal unit creation with pre-computed stats.
func _create_unit_internal(template: UnitTemplate, faction_id: int, stats: Dictionary, position: Vector3) -> Unit:
	var unit := Unit.new()
	var unit_id := Unit.generate_unit_id()
	unit.initialize_unit(unit_id, faction_id, template.unit_type)

	# Create and configure health component
	var health := HealthComponent.new()
	health.set_max_health(stats.get("max_health", 100.0))
	health.set_current_health(stats.get("max_health", 100.0))
	health.data["regeneration_rate"] = stats.get("health_regen", 0.0)
	unit.add_component(health)

	# Create and configure movement component
	var movement := MovementComponent.new()
	movement.set_position(position)
	movement.data["max_speed"] = stats.get("max_speed", 10.0)
	movement.data["acceleration"] = stats.get("acceleration", 50.0)
	movement.data["turn_rate"] = stats.get("turn_rate", 5.0)
	unit.add_component(movement)

	# Create combat component if unit has combat stats
	if stats.get("base_damage", 0.0) > 0:
		var combat := CombatComponent.new()
		combat.data["base_damage"] = stats.get("base_damage", 10.0)
		combat.data["attack_speed"] = stats.get("attack_speed", 1.0)
		combat.data["attack_range"] = stats.get("attack_range", 10.0)
		combat.data["armor"] = stats.get("armor", 0.0)
		unit.add_component(combat)

	# Create faction component
	var faction_comp := FactionComponent.new()
	faction_comp.data["faction_id"] = faction_id
	faction_comp.data["faction_key"] = template.faction_key
	unit.add_component(faction_comp)

	return unit


## Get cached stats for a template and faction.
func _get_cached_stats(template: UnitTemplate, faction_config: FactionConfig) -> Dictionary:
	_maybe_clear_expired_cache()

	var faction_id := faction_config.faction_id if faction_config != null else 0
	var cache_key := "%s_%d" % [template.template_id, faction_id]

	if _stats_cache.has(cache_key):
		return _stats_cache[cache_key]

	# Calculate stats with multipliers
	var stats := template.get_stats_with_multipliers(faction_config)
	_stats_cache[cache_key] = stats

	return stats


## Clear expired cache entries.
func _maybe_clear_expired_cache() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_cache_clear > _cache_expiry_ms:
		_stats_cache.clear()
		_last_cache_clear = now


## Clear the stats cache.
func clear_cache() -> void:
	_stats_cache.clear()
	_last_cache_clear = Time.get_ticks_msec()


## Get the number of cached stat entries.
func get_cache_size() -> int:
	return _stats_cache.size()


## Create unit for a specific faction and unit type.
func create_faction_unit(faction_key: String, unit_type: String, position: Vector3 = Vector3.ZERO) -> Unit:
	var template_id := "%s_%s" % [faction_key, unit_type]
	return create_unit(template_id, position)


## Create units spread around a center position.
func create_units_around(template_id: String, count: int, center: Vector3, spread: float) -> Array[Unit]:
	var positions: Array[Vector3] = []

	for i in range(count):
		var angle := (float(i) / count) * TAU
		var offset := Vector3(cos(angle) * spread, 0, sin(angle) * spread)
		positions.append(center + offset)

	return create_units_batch(template_id, count, positions)


## Create units in a grid formation.
func create_units_grid(template_id: String, rows: int, cols: int, origin: Vector3, spacing: float) -> Array[Unit]:
	var positions: Array[Vector3] = []

	for row in range(rows):
		for col in range(cols):
			var pos := origin + Vector3(col * spacing, 0, row * spacing)
			positions.append(pos)

	return create_units_batch(template_id, rows * cols, positions)
