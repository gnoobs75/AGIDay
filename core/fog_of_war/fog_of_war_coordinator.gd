class_name FogOfWarCoordinator
extends RefCounted
## FogOfWarCoordinator orchestrates all fog of war components.
## Manages vision updates, performance optimization, and system integration.

signal update_completed(units_processed: int, time_ms: float)
signal fog_cleared(faction_id: String, voxel_count: int)
signal ambush_detected(attacker_id: int, target_id: int)

## Update configuration
const DEFAULT_UPDATE_INTERVAL := 0.1  ## Seconds between vision updates
const MAX_UPDATE_TIME_MS := 5.0  ## Max time per update cycle

## Core systems
var fog_system: FogOfWarSystem = null
var vision_system: VisionSystem = null
var visibility_manager: UnitVisibilityManager = null
var vision_source_manager: VisionSourceManager = null
var stealth_system: StealthSystem = null
var ambush_system: AmbushSystem = null
var minimap_renderer: MinimapFogRenderer = null

## Update timing
var _update_interval: float = DEFAULT_UPDATE_INTERVAL
var _accumulated_time: float = 0.0

## Performance tracking
var _last_update_time_ms := 0.0
var _total_updates := 0

## Callbacks for external integration
var _get_unit_position: Callable
var _get_unit_faction: Callable
var _is_blocking_voxel: Callable
var _show_unit: Callable
var _hide_unit: Callable


func _init() -> void:
	_initialize_systems()


## Initialize all subsystems.
func _initialize_systems() -> void:
	fog_system = FogOfWarSystem.new()
	fog_system.initialize_default_factions()

	vision_system = VisionSystem.new()
	visibility_manager = UnitVisibilityManager.new()
	vision_source_manager = VisionSourceManager.new()
	stealth_system = StealthSystem.new()
	ambush_system = AmbushSystem.new()

	# Wire up references
	visibility_manager.set_fog_system(fog_system)
	vision_source_manager.set_stealth_system(stealth_system)
	ambush_system.set_fog_system(fog_system)
	ambush_system.set_stealth_system(stealth_system)


## Set update interval.
func set_update_interval(interval: float) -> void:
	_update_interval = maxf(0.016, interval)  ## Minimum 60fps


## Set callbacks.
func set_callbacks(
	get_position: Callable,
	get_faction: Callable,
	is_blocking: Callable,
	show_unit: Callable,
	hide_unit: Callable
) -> void:
	_get_unit_position = get_position
	_get_unit_faction = get_faction
	_is_blocking_voxel = is_blocking
	_show_unit = show_unit
	_hide_unit = hide_unit

	# Propagate to subsystems
	vision_system.set_get_unit_position(get_position)
	vision_system.set_blocking_voxel_check(is_blocking)

	visibility_manager.set_get_unit_position(get_position)
	visibility_manager.set_get_unit_faction(get_faction)
	visibility_manager.set_show_unit(show_unit)
	visibility_manager.set_hide_unit(hide_unit)

	stealth_system.set_get_unit_position(get_position)
	stealth_system.set_get_unit_faction(get_faction)

	ambush_system.set_get_unit_position(get_position)
	ambush_system.set_get_unit_faction(get_faction)


## Register unit with all systems.
func register_unit(unit_id: int, faction_id: String, unit_type: String) -> void:
	# Register with vision system
	vision_system.register_unit(unit_id, faction_id, unit_type)

	# Register with visibility manager
	visibility_manager.register_unit(unit_id, faction_id, unit_type)

	# Register as vision source
	var component := vision_system.get_component(unit_id)
	if component != null:
		vision_source_manager.register_unit(unit_id, faction_id, component.vision_range)


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	vision_system.unregister_unit(unit_id)
	visibility_manager.unregister_unit(unit_id)
	vision_source_manager.unregister_source(unit_id)
	stealth_system.exit_stealth(unit_id, "unregistered")


## Register structure.
func register_structure(structure_id: int, faction_id: String, structure_type: String, position: Vector3) -> void:
	vision_source_manager.register_structure(structure_id, faction_id, structure_type, position)


## Unregister structure.
func unregister_structure(structure_id: int) -> void:
	vision_source_manager.unregister_source(structure_id)


## Update position for unit.
func update_unit_position(unit_id: int, position: Vector3) -> void:
	vision_system.update_unit_position(unit_id, position)
	visibility_manager.update_unit_position(unit_id, position)
	vision_source_manager.update_position(unit_id, position)


## Main update - call each frame.
func update(delta: float) -> void:
	_accumulated_time += delta

	if _accumulated_time < _update_interval:
		return

	_accumulated_time = 0.0
	_perform_update()


## Perform full update cycle.
func _perform_update() -> void:
	var start_time := Time.get_ticks_usec()
	var current_time := Time.get_ticks_msec() / 1000.0

	# 1. Process vision calculations
	var units_processed := vision_system.process_updates()

	# 2. Update fog of war grids from vision data
	_update_fog_from_vision(current_time)

	# 3. Process visibility updates
	visibility_manager.process_updates()

	# 4. Process periodic scans (radar stations)
	vision_source_manager.process_scans()

	# 5. Cleanup expired sources
	vision_source_manager.cleanup_expired()

	# 6. Cleanup old last-known positions
	visibility_manager.cleanup_last_known()

	# 7. Update minimap if available
	if minimap_renderer != null:
		minimap_renderer.update_texture()

	# Track performance
	_last_update_time_ms = float(Time.get_ticks_usec() - start_time) / 1000.0
	_total_updates += 1

	update_completed.emit(units_processed, _last_update_time_ms)


## Update fog grids from vision data.
func _update_fog_from_vision(current_time: float) -> void:
	# Clear all visible (set to explored)
	fog_system.clear_all_visible()

	# For each faction, reveal areas from vision sources
	for faction_id in FogOfWarSystem.DEFAULT_FACTIONS:
		var sources := vision_source_manager.get_faction_sources(faction_id)
		var cleared := 0

		for source in sources:
			if not source.is_providing_vision():
				continue

			var voxel_x := int(floor(source.position.x))
			var voxel_z := int(floor(source.position.z))
			var range_voxels := int(ceil(source.vision_range))

			cleared += fog_system.reveal_area(faction_id, voxel_x, voxel_z, range_voxels, current_time)

		if cleared > 0:
			fog_cleared.emit(faction_id, cleared)


## Process attack for ambush detection.
func process_attack(attacker_id: int, target_id: int, base_damage: float, base_accuracy: float = 0.8, base_crit: float = 0.05) -> Dictionary:
	var result := ambush_system.process_attack(attacker_id, target_id, base_damage, base_accuracy, base_crit)

	if result["is_ambush"]:
		ambush_detected.emit(attacker_id, target_id)

	return result


## Enter stealth for unit.
func enter_stealth(unit_id: int) -> bool:
	if stealth_system.enter_stealth(unit_id):
		vision_source_manager.set_stealthed(unit_id, true)
		return true
	return false


## Exit stealth for unit.
func exit_stealth(unit_id: int, reason: String = "manual") -> bool:
	if stealth_system.exit_stealth(unit_id, reason):
		vision_source_manager.set_stealthed(unit_id, false)
		return true
	return false


## Check if unit is visible to faction.
func is_unit_visible(unit_id: int, observer_faction: String) -> bool:
	# Check stealth first
	if not stealth_system.is_visible_to_faction(unit_id, observer_faction):
		return false

	# Then check fog of war
	return visibility_manager.is_unit_visible_to_faction(unit_id, observer_faction)


## Find ambush positions.
func find_ambush_positions(target_pos: Vector3, radius: float, attacker_faction: String, target_faction: String) -> Array[Dictionary]:
	return ambush_system.find_ambush_positions(target_pos, radius, attacker_faction, target_faction)


## Set minimap renderer.
func set_minimap_renderer(renderer: MinimapFogRenderer, faction_id: String) -> void:
	minimap_renderer = renderer
	var grid := fog_system.get_faction_grid(faction_id)
	if grid != null:
		minimap_renderer.set_fog_grid(grid)


## Invalidate vision caches (call when terrain changes).
func invalidate_vision_caches() -> void:
	vision_system.invalidate_all_caches()


## Serialization.
func to_dict() -> Dictionary:
	return {
		"fog_system": fog_system.to_dict(),
		"visibility_manager": visibility_manager.to_dict(),
		"vision_source_manager": vision_source_manager.to_dict(),
		"stealth_system": stealth_system.to_dict(),
		"update_interval": _update_interval
	}


func from_dict(data: Dictionary) -> void:
	if data.has("fog_system"):
		fog_system.from_dict(data["fog_system"])

	if data.has("visibility_manager"):
		visibility_manager.from_dict(data["visibility_manager"])

	if data.has("vision_source_manager"):
		vision_source_manager.from_dict(data["vision_source_manager"])

	if data.has("stealth_system"):
		stealth_system.from_dict(data["stealth_system"])

	_update_interval = data.get("update_interval", DEFAULT_UPDATE_INTERVAL)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"update_interval": _update_interval,
		"last_update_time_ms": _last_update_time_ms,
		"total_updates": _total_updates,
		"fog_system": fog_system.get_summary(),
		"vision_system": vision_system.get_summary(),
		"visibility_manager": visibility_manager.get_summary(),
		"vision_sources": vision_source_manager.get_summary(),
		"stealth_system": stealth_system.get_summary(),
		"ambush_system": ambush_system.get_summary()
	}
