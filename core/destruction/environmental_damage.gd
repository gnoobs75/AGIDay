class_name EnvironmentalDamage
extends RefCounted
## EnvironmentalDamage handles damage from blackouts, collapse, and subsidence.

signal blackout_damage_applied(positions: Array[Vector3i], total_damage: float)
signal structural_collapse(origin: Vector3i, affected: Array[Vector3i])
signal terrain_subsidence(crater_origin: Vector3i, expanded_positions: Array[Vector3i])

## Damage types
enum DamageType {
	BLACKOUT = 0,       ## Power grid failure
	COLLAPSE = 1,       ## Structural failure
	SUBSIDENCE = 2      ## Crater expansion
}

## Default damage amounts
const BLACKOUT_DAMAGE_PER_TICK := 10.0
const COLLAPSE_DAMAGE := 50.0
const SUBSIDENCE_DAMAGE := 75.0

## Spread patterns
const COLLAPSE_RADIUS := 2
const SUBSIDENCE_RADIUS := 1

## Reference to damage system
var damage_system: VoxelDamageSystem = null

## Active blackout zones (zone_id -> Array of positions)
var _blackout_zones: Dictionary = {}


func _init() -> void:
	pass


## Set damage system.
func set_damage_system(system: VoxelDamageSystem) -> void:
	damage_system = system


## Apply blackout damage to zone.
func apply_blackout_damage(zone_id: int, positions: Array[Vector3i], damage: float = BLACKOUT_DAMAGE_PER_TICK) -> void:
	if damage_system == null:
		return

	var total_damage := 0.0

	for position in positions:
		damage_system.apply_environmental_damage(position, damage, "blackout")
		total_damage += damage

	blackout_damage_applied.emit(positions, total_damage)


## Register blackout zone.
func register_blackout_zone(zone_id: int, positions: Array[Vector3i]) -> void:
	_blackout_zones[zone_id] = positions.duplicate()


## Clear blackout zone.
func clear_blackout_zone(zone_id: int) -> void:
	_blackout_zones.erase(zone_id)


## Process blackout tick.
func process_blackouts(delta: float) -> void:
	for zone_id in _blackout_zones:
		var positions: Array = _blackout_zones[zone_id]
		var typed_positions: Array[Vector3i] = []
		for pos in positions:
			typed_positions.append(pos)

		apply_blackout_damage(zone_id, typed_positions, BLACKOUT_DAMAGE_PER_TICK * delta)


## Trigger structural collapse.
func trigger_collapse(origin: Vector3i) -> Array[Vector3i]:
	if damage_system == null:
		return []

	var affected: Array[Vector3i] = []

	# Get adjacent positions
	for dx in range(-COLLAPSE_RADIUS, COLLAPSE_RADIUS + 1):
		for dy in range(-COLLAPSE_RADIUS, COLLAPSE_RADIUS + 1):
			for dz in range(-COLLAPSE_RADIUS, COLLAPSE_RADIUS + 1):
				if dx == 0 and dy == 0 and dz == 0:
					continue

				var pos := Vector3i(
					origin.x + dx,
					origin.y + dy,
					origin.z + dz
				)

				# Distance-based damage falloff
				var distance := Vector3(dx, dy, dz).length()
				var falloff := 1.0 - (distance / (COLLAPSE_RADIUS + 1))
				var damage := COLLAPSE_DAMAGE * falloff

				if damage > 0:
					damage_system.apply_environmental_damage(pos, damage, "collapse")
					affected.append(pos)

	structural_collapse.emit(origin, affected)
	return affected


## Trigger terrain subsidence (crater expansion).
func trigger_subsidence(crater_origin: Vector3i) -> Array[Vector3i]:
	if damage_system == null:
		return []

	var expanded: Array[Vector3i] = []

	# Get adjacent positions
	for dx in range(-SUBSIDENCE_RADIUS, SUBSIDENCE_RADIUS + 1):
		for dz in range(-SUBSIDENCE_RADIUS, SUBSIDENCE_RADIUS + 1):
			if dx == 0 and dz == 0:
				continue

			var pos := Vector3i(
				crater_origin.x + dx,
				0,
				crater_origin.z + dz
			)

			# Check if position is not already a crater
			var current_stage := damage_system.get_voxel_stage(pos)
			if current_stage != VoxelStage.Stage.CRATER:
				damage_system.apply_environmental_damage(pos, SUBSIDENCE_DAMAGE, "subsidence")
				expanded.append(pos)

	terrain_subsidence.emit(crater_origin, expanded)
	return expanded


## Apply area damage.
func apply_area_damage(
	center: Vector3i,
	radius: int,
	base_damage: float,
	damage_type: String,
	falloff: bool = true
) -> Array[Vector3i]:
	if damage_system == null:
		return []

	var affected: Array[Vector3i] = []

	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var pos := Vector3i(
					center.x + dx,
					center.y + dy,
					center.z + dz
				)

				var distance := Vector3(dx, dy, dz).length()
				if distance > radius:
					continue

				var damage := base_damage
				if falloff:
					damage *= (1.0 - distance / (radius + 1))

				if damage > 0:
					damage_system.apply_environmental_damage(pos, damage, damage_type)
					affected.append(pos)

	return affected


## Get active blackout zones.
func get_blackout_zones() -> Dictionary:
	return _blackout_zones.duplicate(true)


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var zones_data: Dictionary = {}
	for zone_id in _blackout_zones:
		var positions: Array = []
		for pos in _blackout_zones[zone_id]:
			positions.append({"x": pos.x, "y": pos.y, "z": pos.z})
		zones_data[str(zone_id)] = positions

	return {"blackout_zones": zones_data}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_blackout_zones.clear()

	for zone_id_str in data.get("blackout_zones", {}):
		var zone_id := int(zone_id_str)
		var positions: Array[Vector3i] = []

		for pos_data in data["blackout_zones"][zone_id_str]:
			positions.append(Vector3i(
				pos_data.get("x", 0),
				pos_data.get("y", 0),
				pos_data.get("z", 0)
			))

		_blackout_zones[zone_id] = positions


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"blackout_zones": _blackout_zones.size()
	}
