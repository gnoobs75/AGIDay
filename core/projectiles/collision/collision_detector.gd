class_name CollisionDetector
extends RefCounted
## CollisionDetector handles efficient collision detection between projectiles and units.
## Uses spatial partitioning to achieve O(region) complexity instead of O(n*m).

signal collision_detected(result: CollisionResult)
signal damage_applied(unit_id: int, damage: float, attacker_faction: String)

## Spatial grid for units
var _unit_grid: SpatialGrid = null

## Unit collision radii (unit_id -> radius)
var _unit_radii: Dictionary = {}

## Unit factions (unit_id -> faction_id)
var _unit_factions: Dictionary = {}

## Collision statistics
var _stats: Dictionary = {
	"collisions_this_frame": 0,
	"checks_this_frame": 0,
	"total_collisions": 0
}

## Grid cell size (should be larger than max projectile range)
const GRID_CELL_SIZE := 32.0


func _init() -> void:
	_unit_grid = SpatialGrid.new(GRID_CELL_SIZE)


## Register unit for collision detection.
func register_unit(unit_id: int, position: Vector3, radius: float, faction_id: String) -> void:
	_unit_grid.insert(unit_id, position)
	_unit_radii[unit_id] = radius
	_unit_factions[unit_id] = faction_id


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_unit_grid.remove(unit_id)
	_unit_radii.erase(unit_id)
	_unit_factions.erase(unit_id)


## Update unit position.
func update_unit_position(unit_id: int, position: Vector3) -> void:
	_unit_grid.update(unit_id, position)


## Update unit faction.
func update_unit_faction(unit_id: int, faction_id: String) -> void:
	_unit_factions[unit_id] = faction_id


## Check collisions for all projectiles.
func check_collisions(projectiles: Array[Projectile]) -> Array[CollisionResult]:
	var results: Array[CollisionResult] = []
	_stats["collisions_this_frame"] = 0
	_stats["checks_this_frame"] = 0

	for proj in projectiles:
		if not proj.is_active:
			continue

		var collision := _check_projectile_collision(proj)
		if collision != null:
			results.append(collision)
			collision_detected.emit(collision)
			_stats["collisions_this_frame"] += 1
			_stats["total_collisions"] += 1

	return results


## Check collision for single projectile.
func _check_projectile_collision(proj: Projectile) -> CollisionResult:
	# Query units near projectile
	var query_radius := proj.hit_radius + 10.0  # Add buffer for unit radii
	var nearby_units := _unit_grid.query_radius(proj.position, query_radius)

	_stats["checks_this_frame"] += nearby_units.size()

	for unit_id in nearby_units:
		# Skip same faction
		var unit_faction: String = _unit_factions.get(unit_id, "")
		if unit_faction == proj.faction_id:
			continue

		# Skip already hit (for piercing projectiles)
		if unit_id in proj.hit_units:
			continue

		# Check actual collision
		var unit_pos := _unit_grid.get_position(unit_id)
		var unit_radius: float = _unit_radii.get(unit_id, 1.0)
		var combined_radius := proj.hit_radius + unit_radius

		var distance := proj.position.distance_to(unit_pos)
		if distance <= combined_radius:
			# Collision detected
			var should_despawn := proj.should_despawn_on_hit()

			# Record hit for piercing projectiles
			proj.record_hit(unit_id)

			return CollisionResult.create(
				proj.id,
				proj.faction_id,
				proj.projectile_type,
				unit_id,
				unit_faction,
				proj.position,
				proj.damage,
				proj.visual_effect,
				should_despawn
			)

	return null


## Check collision at specific position (for area effects).
func check_collision_at_position(
	position: Vector3,
	radius: float,
	exclude_faction: String = ""
) -> Array[int]:
	var nearby_units := _unit_grid.query_radius(position, radius)
	var result: Array[int] = []

	for unit_id in nearby_units:
		var unit_faction: String = _unit_factions.get(unit_id, "")
		if not exclude_faction.is_empty() and unit_faction == exclude_faction:
			continue

		var unit_pos := _unit_grid.get_position(unit_id)
		var unit_radius: float = _unit_radii.get(unit_id, 1.0)
		var combined_radius := radius + unit_radius

		var distance := position.distance_to(unit_pos)
		if distance <= combined_radius:
			result.append(unit_id)

	return result


## Get units in radius (for targeting).
func get_units_in_radius(
	center: Vector3,
	radius: float,
	filter_faction: String = "",
	exclude_faction: String = ""
) -> Array[int]:
	var nearby_units := _unit_grid.query_radius(center, radius)
	var result: Array[int] = []

	for unit_id in nearby_units:
		var unit_faction: String = _unit_factions.get(unit_id, "")

		# Filter by faction if specified
		if not filter_faction.is_empty() and unit_faction != filter_faction:
			continue

		# Exclude faction if specified
		if not exclude_faction.is_empty() and unit_faction == exclude_faction:
			continue

		result.append(unit_id)

	return result


## Get closest unit to position.
func get_closest_unit(
	position: Vector3,
	max_radius: float,
	exclude_faction: String = ""
) -> int:
	var nearby_units := _unit_grid.query_radius(position, max_radius)
	var closest_id := -1
	var closest_dist := INF

	for unit_id in nearby_units:
		var unit_faction: String = _unit_factions.get(unit_id, "")
		if not exclude_faction.is_empty() and unit_faction == exclude_faction:
			continue

		var unit_pos := _unit_grid.get_position(unit_id)
		var dist := position.distance_to(unit_pos)

		if dist < closest_dist:
			closest_dist = dist
			closest_id = unit_id

	return closest_id


## Get unit position.
func get_unit_position(unit_id: int) -> Vector3:
	return _unit_grid.get_position(unit_id)


## Get unit faction.
func get_unit_faction(unit_id: int) -> String:
	return _unit_factions.get(unit_id, "")


## Clear all units.
func clear_units() -> void:
	_unit_grid.clear()
	_unit_radii.clear()
	_unit_factions.clear()


## Reset frame stats.
func reset_frame_stats() -> void:
	_stats["collisions_this_frame"] = 0
	_stats["checks_this_frame"] = 0


## Get statistics.
func get_stats() -> Dictionary:
	return _stats.duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"registered_units": _unit_radii.size(),
		"grid": _unit_grid.get_summary(),
		"stats": _stats.duplicate()
	}
