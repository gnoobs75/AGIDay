class_name AmbushSystem
extends RefCounted
## AmbushSystem detects and applies ambush bonuses for attacks from hidden positions.

signal ambush_attack(attacker_id: int, target_id: int, bonuses: Dictionary)
signal unit_revealed_by_attack(unit_id: int)
signal ambush_position_found(position: Vector3, score: float)

## Ambush bonuses
const AMBUSH_DAMAGE_BONUS := 0.50  ## 50% damage increase
const AMBUSH_ACCURACY_BONUS := 0.20  ## +20% accuracy
const AMBUSH_CRIT_BONUS := 0.15  ## +15% critical chance

## References
var _fog_system: FogOfWarSystem = null
var _vision_system: VisionSystem = null
var _stealth_system: StealthSystem = null

## Callbacks
var _get_unit_position: Callable
var _get_unit_faction: Callable
var _reveal_unit: Callable


func _init() -> void:
	pass


## Set system references.
func set_fog_system(system: FogOfWarSystem) -> void:
	_fog_system = system


func set_vision_system(system: VisionSystem) -> void:
	_vision_system = system


func set_stealth_system(system: StealthSystem) -> void:
	_stealth_system = system


## Set callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_unit_faction(callback: Callable) -> void:
	_get_unit_faction = callback


func set_reveal_unit(callback: Callable) -> void:
	_reveal_unit = callback


## Check if attacker is hidden from target's faction.
func is_hidden_from_target(attacker_id: int, target_id: int) -> bool:
	if not _get_unit_position.is_valid() or not _get_unit_faction.is_valid():
		return false

	var attacker_pos: Vector3 = _get_unit_position.call(attacker_id)
	var target_faction: String = _get_unit_faction.call(target_id)

	# Check if attacker position is visible to target's faction
	var voxel_x := int(floor(attacker_pos.x))
	var voxel_z := int(floor(attacker_pos.z))

	if _fog_system != null:
		return not _fog_system.is_visible_to_faction(target_faction, voxel_x, voxel_z)

	return false


## Process attack and apply ambush bonuses if applicable.
func process_attack(attacker_id: int, target_id: int, base_damage: float, base_accuracy: float, base_crit: float) -> Dictionary:
	var is_ambush := is_hidden_from_target(attacker_id, target_id)

	var result := {
		"is_ambush": is_ambush,
		"damage": base_damage,
		"accuracy": base_accuracy,
		"crit_chance": base_crit,
		"damage_bonus": 0.0,
		"accuracy_bonus": 0.0,
		"crit_bonus": 0.0
	}

	if is_ambush:
		result["damage_bonus"] = base_damage * AMBUSH_DAMAGE_BONUS
		result["accuracy_bonus"] = AMBUSH_ACCURACY_BONUS
		result["crit_bonus"] = AMBUSH_CRIT_BONUS

		result["damage"] = base_damage + result["damage_bonus"]
		result["accuracy"] = minf(base_accuracy + AMBUSH_ACCURACY_BONUS, 1.0)
		result["crit_chance"] = minf(base_crit + AMBUSH_CRIT_BONUS, 1.0)

		var bonuses := {
			"damage_bonus": AMBUSH_DAMAGE_BONUS,
			"accuracy_bonus": AMBUSH_ACCURACY_BONUS,
			"crit_bonus": AMBUSH_CRIT_BONUS
		}
		ambush_attack.emit(attacker_id, target_id, bonuses)

		# Reveal attacker after ambush
		_reveal_attacker(attacker_id)

	return result


## Reveal attacker after ambush.
func _reveal_attacker(attacker_id: int) -> void:
	# Exit stealth if stealthed
	if _stealth_system != null:
		_stealth_system.exit_stealth(attacker_id, "ambush_attack")

	# Reveal in fog of war
	if _reveal_unit.is_valid():
		_reveal_unit.call(attacker_id)

	unit_revealed_by_attack.emit(attacker_id)


## Find best ambush positions near target.
func find_ambush_positions(target_pos: Vector3, search_radius: float, attacker_faction: String, target_faction: String) -> Array[Dictionary]:
	var positions: Array[Dictionary] = []

	if _fog_system == null:
		return positions

	var center_x := int(floor(target_pos.x))
	var center_z := int(floor(target_pos.z))
	var radius := int(ceil(search_radius))

	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var dist_sq := dx * dx + dz * dz
			if dist_sq > radius * radius:
				continue

			var vx := center_x + dx
			var vz := center_z + dz

			# Check if position is hidden from target faction
			var is_hidden := not _fog_system.is_visible_to_faction(target_faction, vx, vz)

			if is_hidden:
				var distance := sqrt(float(dist_sq))
				var score := 1.0 - (distance / search_radius)  ## Closer = better

				# Bonus for being explored (known safe position)
				if _fog_system.is_explored_by_faction(attacker_faction, vx, vz):
					score *= 1.2

				positions.append({
					"position": Vector3(float(vx) + 0.5, target_pos.y, float(vz) + 0.5),
					"score": score,
					"distance": distance
				})

	# Sort by score descending
	positions.sort_custom(func(a, b): return a["score"] > b["score"])

	# Emit for top positions
	for i in mini(3, positions.size()):
		ambush_position_found.emit(positions[i]["position"], positions[i]["score"])

	return positions


## Check if position is good for hiding.
func is_hiding_position(position: Vector3, observer_faction: String) -> bool:
	if _fog_system == null:
		return false

	var vx := int(floor(position.x))
	var vz := int(floor(position.z))

	return not _fog_system.is_visible_to_faction(observer_faction, vx, vz)


## Get ambush bonus constants.
func get_ambush_bonuses() -> Dictionary:
	return {
		"damage_bonus": AMBUSH_DAMAGE_BONUS,
		"accuracy_bonus": AMBUSH_ACCURACY_BONUS,
		"crit_bonus": AMBUSH_CRIT_BONUS
	}


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"damage_bonus": AMBUSH_DAMAGE_BONUS,
		"accuracy_bonus": AMBUSH_ACCURACY_BONUS,
		"crit_bonus": AMBUSH_CRIT_BONUS,
		"has_fog_system": _fog_system != null,
		"has_stealth_system": _stealth_system != null
	}
