class_name ProjectileCollisionSystem
extends RefCounted
## ProjectileCollisionSystem integrates collision detection with projectile management.
## Provides high-level API for bullet hell collision handling.

signal projectile_hit(projectile_id: int, unit_id: int, damage: float)
signal unit_damaged(unit_id: int, damage: float, attacker_faction: String)
signal projectile_destroyed(projectile_id: int, reason: String)

## Collision detector
var _detector: CollisionDetector = null

## Reference to projectile manager
var _projectile_manager = null  ## Weak reference to avoid circular dependency

## Damage application callback
var _damage_callback: Callable

## Hit effect callback
var _hit_effect_callback: Callable

## Collision results from last frame
var _last_frame_results: Array[CollisionResult] = []

## Statistics
var _stats: Dictionary = {
	"hits_this_frame": 0,
	"damage_this_frame": 0.0,
	"total_hits": 0,
	"total_damage": 0.0
}


func _init() -> void:
	_detector = CollisionDetector.new()


## Set projectile manager reference.
func set_projectile_manager(manager) -> void:
	_projectile_manager = manager


## Set damage application callback.
func set_damage_callback(callback: Callable) -> void:
	_damage_callback = callback


## Set hit effect callback.
func set_hit_effect_callback(callback: Callable) -> void:
	_hit_effect_callback = callback


## Register unit for collision.
func register_unit(unit_id: int, position: Vector3, radius: float, faction_id: String) -> void:
	_detector.register_unit(unit_id, position, radius, faction_id)


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	_detector.unregister_unit(unit_id)


## Update unit position.
func update_unit(unit_id: int, position: Vector3) -> void:
	_detector.update_unit_position(unit_id, position)


## Batch update unit positions.
func update_units_batch(updates: Array[Dictionary]) -> void:
	for update in updates:
		_detector.update_unit_position(update["id"], update["position"])


## Process collisions for frame.
func process_collisions(projectiles: Array[Projectile]) -> Array[CollisionResult]:
	_stats["hits_this_frame"] = 0
	_stats["damage_this_frame"] = 0.0

	# Check all collisions
	var results := _detector.check_collisions(projectiles)
	_last_frame_results = results

	# Process each collision
	var to_despawn: Array[int] = []

	for result in results:
		_stats["hits_this_frame"] += 1
		_stats["damage_this_frame"] += result.damage
		_stats["total_hits"] += 1
		_stats["total_damage"] += result.damage

		# Apply damage
		if _damage_callback.is_valid():
			_damage_callback.call(result.unit_id, result.damage, result.projectile_faction)

		unit_damaged.emit(result.unit_id, result.damage, result.projectile_faction)
		projectile_hit.emit(result.projectile_id, result.unit_id, result.damage)

		# Trigger hit effect
		if _hit_effect_callback.is_valid() and not result.hit_effect.is_empty():
			_hit_effect_callback.call(result.hit_effect, result.position)

		# Queue despawn
		if result.despawn_projectile:
			to_despawn.append(result.projectile_id)

	# Despawn projectiles
	for proj_id in to_despawn:
		projectile_destroyed.emit(proj_id, "collision")

	return results


## Get projectiles that would hit position.
func get_projectiles_at(
	position: Vector3,
	radius: float,
	exclude_faction: String = ""
) -> Array[Projectile]:
	if _projectile_manager == null:
		return []

	var projectiles := _projectile_manager.get_projectiles_in_radius(position, radius)
	var result: Array[Projectile] = []

	for proj in projectiles:
		if not exclude_faction.is_empty() and proj.faction_id == exclude_faction:
			continue
		result.append(proj)

	return result


## Get units in area (for AoE).
func get_units_in_area(
	center: Vector3,
	radius: float,
	target_faction: String = "",
	exclude_faction: String = ""
) -> Array[int]:
	return _detector.get_units_in_radius(center, radius, target_faction, exclude_faction)


## Apply area damage.
func apply_area_damage(
	center: Vector3,
	radius: float,
	damage: float,
	attacker_faction: String,
	falloff: bool = true
) -> Array[int]:
	var affected: Array[int] = []
	var units := _detector.get_units_in_radius(center, radius, "", attacker_faction)

	for unit_id in units:
		var unit_pos := _detector.get_unit_position(unit_id)
		var distance := center.distance_to(unit_pos)

		var final_damage := damage
		if falloff:
			var factor := 1.0 - (distance / radius)
			final_damage = damage * maxf(0.0, factor)

		if final_damage > 0:
			if _damage_callback.is_valid():
				_damage_callback.call(unit_id, final_damage, attacker_faction)

			unit_damaged.emit(unit_id, final_damage, attacker_faction)
			affected.append(unit_id)

	return affected


## Get closest enemy to position.
func get_closest_enemy(position: Vector3, max_radius: float, my_faction: String) -> int:
	return _detector.get_closest_unit(position, max_radius, my_faction)


## Get last frame collision results.
func get_last_frame_results() -> Array[CollisionResult]:
	return _last_frame_results


## Clear all units.
func clear_units() -> void:
	_detector.clear_units()


## Get detector (for direct access).
func get_detector() -> CollisionDetector:
	return _detector


## Get statistics.
func get_stats() -> Dictionary:
	var detector_stats := _detector.get_stats()
	return {
		"hits_this_frame": _stats["hits_this_frame"],
		"damage_this_frame": _stats["damage_this_frame"],
		"total_hits": _stats["total_hits"],
		"total_damage": _stats["total_damage"],
		"collision_checks": detector_stats["checks_this_frame"],
		"registered_units": _detector.get_summary()["registered_units"]
	}


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"stats": get_stats(),
		"detector": _detector.get_summary(),
		"last_frame_collisions": _last_frame_results.size()
	}
