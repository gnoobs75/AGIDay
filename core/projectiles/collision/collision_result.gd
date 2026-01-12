class_name CollisionResult
extends RefCounted
## CollisionResult contains information about a projectile-unit collision.

## Projectile that hit
var projectile_id: int = -1

## Unit that was hit
var unit_id: int = -1

## Projectile faction
var projectile_faction: String = ""

## Unit faction
var unit_faction: String = ""

## Collision position
var position: Vector3 = Vector3.ZERO

## Damage dealt
var damage: float = 0.0

## Projectile type
var projectile_type: String = ""

## Whether projectile should despawn
var despawn_projectile: bool = true

## Hit effect to trigger
var hit_effect: String = ""


func _init() -> void:
	pass


## Create collision result.
static func create(
	proj_id: int,
	proj_faction: String,
	proj_type: String,
	target_id: int,
	target_faction: String,
	hit_pos: Vector3,
	dmg: float,
	effect: String = "",
	should_despawn: bool = true
) -> CollisionResult:
	var result := CollisionResult.new()
	result.projectile_id = proj_id
	result.projectile_faction = proj_faction
	result.projectile_type = proj_type
	result.unit_id = target_id
	result.unit_faction = target_faction
	result.position = hit_pos
	result.damage = dmg
	result.hit_effect = effect
	result.despawn_projectile = should_despawn
	return result


## Convert to dictionary.
func to_dict() -> Dictionary:
	return {
		"projectile_id": projectile_id,
		"unit_id": unit_id,
		"projectile_faction": projectile_faction,
		"unit_faction": unit_faction,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"damage": damage,
		"projectile_type": projectile_type,
		"despawn_projectile": despawn_projectile,
		"hit_effect": hit_effect
	}
