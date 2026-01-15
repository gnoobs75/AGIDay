class_name StrategicAnalysis
extends RefCounted
## StrategicAnalysis identifies chokepoints, faction advantages, and tactical positions.
## Analyzes resource placement and power grid paths for strategic value.

signal chokepoint_identified(position: Vector3, width: float)
signal faction_advantage_detected(faction: String, zone: Rect2, advantage_type: String)
signal analysis_complete(chokepoints: int, advantages: int)

## Minimum passage width to be considered a chokepoint
const CHOKEPOINT_WIDTH_THRESHOLD := 4.0

## Zone analysis grid size
const ZONE_SIZE := 64


## Chokepoint data.
class Chokepoint:
	var position: Vector3 = Vector3.ZERO
	var width: float = 0.0
	var direction: Vector3 = Vector3.FORWARD  ## Direction of passage
	var connected_districts: Array[int] = []
	var power_line_aligned: bool = false


## Faction advantage data.
class FactionAdvantage:
	var faction: String = ""
	var zone: Rect2 = Rect2()
	var advantage_type: String = ""  ## terrain, resources, cover, proximity
	var strength: float = 0.0


## Identified chokepoints
var _chokepoints: Array[Chokepoint] = []

## Faction advantages by zone
var _faction_advantages: Array[FactionAdvantage] = []

## Zone analysis cache
var _zone_analysis: Dictionary = {}  ## "x,z" -> Dictionary

## RNG
var _rng: RandomNumberGenerator = null

## World size
var _world_size: int = 512


func _init() -> void:
	_rng = RandomNumberGenerator.new()


## Initialize with seed.
func initialize(seed_value: int, world_size: int = 512) -> void:
	_rng.seed = seed_value
	_world_size = world_size


## Identify strategic chokepoints in the map.
func identify_strategic_chokepoints(
	blocked_positions: Array[Vector3i],
	power_line_positions: Array[Vector3] = []
) -> Array[Chokepoint]:
	_chokepoints.clear()

	# Build blocked position lookup
	var blocked_lookup: Dictionary = {}
	for pos in blocked_positions:
		blocked_lookup["%d,%d" % [pos.x, pos.z]] = true

	# Scan map for narrow passages
	var step := 8  # Check every 8 units for efficiency
	for z in range(step, _world_size - step, step):
		for x in range(step, _world_size - step, step):
			var pos := Vector3(x, 0, z)

			# Skip blocked positions
			if blocked_lookup.has("%d,%d" % [x, z]):
				continue

			# Measure passage width in cardinal directions
			var width_x := _measure_passage_width(pos, Vector3.RIGHT, blocked_lookup)
			var width_z := _measure_passage_width(pos, Vector3.FORWARD, blocked_lookup)

			var min_width := minf(width_x, width_z)

			# Check if this is a chokepoint
			if min_width <= CHOKEPOINT_WIDTH_THRESHOLD and min_width > 0:
				var chokepoint := Chokepoint.new()
				chokepoint.position = pos
				chokepoint.width = min_width
				chokepoint.direction = Vector3.RIGHT if width_x < width_z else Vector3.FORWARD

				# Check power line alignment
				chokepoint.power_line_aligned = _is_near_power_line(pos, power_line_positions)

				_chokepoints.append(chokepoint)
				chokepoint_identified.emit(pos, min_width)

	return _chokepoints


## Measure passage width at position in given direction.
func _measure_passage_width(position: Vector3, direction: Vector3, blocked: Dictionary) -> float:
	var perpendicular := Vector3(-direction.z, 0, direction.x)
	var width := 0.0

	# Measure in both perpendicular directions
	for sign_val in [-1, 1]:
		for dist in range(1, 20):
			var check_pos: Vector3 = position + perpendicular * dist * sign_val
			var key := "%d,%d" % [int(check_pos.x), int(check_pos.z)]

			if blocked.has(key):
				break

			if check_pos.x < 0 or check_pos.x >= _world_size:
				break
			if check_pos.z < 0 or check_pos.z >= _world_size:
				break

			width += 1.0

	return width


## Measure passage width externally.
func measure_passage_width(position: Vector3, direction: Vector3, blocked_positions: Array[Vector3i]) -> float:
	var blocked: Dictionary = {}
	for pos in blocked_positions:
		blocked["%d,%d" % [pos.x, pos.z]] = true

	return _measure_passage_width(position, direction, blocked)


## Check if position is near a power line.
func _is_near_power_line(position: Vector3, power_lines: Array[Vector3]) -> bool:
	for line_pos in power_lines:
		if position.distance_to(line_pos) < 16.0:
			return true
	return false


## Analyze faction advantages across the map.
func analyze_faction_advantages(
	faction_spawns: Dictionary,  ## faction_id -> Vector3
	resource_positions: Array[Vector3],
	cover_positions: Array[Vector3] = []
) -> Array[FactionAdvantage]:
	_faction_advantages.clear()

	# Divide map into zones
	var zones_x := _world_size / ZONE_SIZE
	var zones_z := _world_size / ZONE_SIZE

	for zz in zones_z:
		for zx in zones_x:
			var zone := Rect2(
				zx * ZONE_SIZE,
				zz * ZONE_SIZE,
				ZONE_SIZE,
				ZONE_SIZE
			)
			var zone_center := Vector3(
				zone.position.x + zone.size.x / 2,
				0,
				zone.position.y + zone.size.y / 2
			)

			# Count resources in zone
			var zone_resources := _count_in_zone(resource_positions, zone)

			# Count cover positions in zone
			var zone_cover := _count_in_zone(cover_positions, zone)

			# Determine faction proximity advantage
			for faction in faction_spawns:
				var spawn_pos: Vector3 = faction_spawns[faction]
				var dist := zone_center.distance_to(spawn_pos)

				# Proximity advantage
				if dist < _world_size * 0.25:
					var advantage := FactionAdvantage.new()
					advantage.faction = faction
					advantage.zone = zone
					advantage.advantage_type = "proximity"
					advantage.strength = 1.0 - (dist / (_world_size * 0.25))
					_faction_advantages.append(advantage)
					faction_advantage_detected.emit(faction, zone, "proximity")

				# Resource advantage
				if zone_resources > 3 and dist < _world_size * 0.4:
					var advantage := FactionAdvantage.new()
					advantage.faction = faction
					advantage.zone = zone
					advantage.advantage_type = "resources"
					advantage.strength = float(zone_resources) / 10.0
					_faction_advantages.append(advantage)

				# Cover advantage
				if zone_cover > 5 and dist < _world_size * 0.35:
					var advantage := FactionAdvantage.new()
					advantage.faction = faction
					advantage.zone = zone
					advantage.advantage_type = "cover"
					advantage.strength = float(zone_cover) / 15.0
					_faction_advantages.append(advantage)

	analysis_complete.emit(_chokepoints.size(), _faction_advantages.size())
	return _faction_advantages


## Count positions within a zone.
func _count_in_zone(positions: Array[Vector3], zone: Rect2) -> int:
	var count := 0
	for pos in positions:
		if pos.x >= zone.position.x and pos.x < zone.position.x + zone.size.x:
			if pos.z >= zone.position.y and pos.z < zone.position.y + zone.size.y:
				count += 1
	return count


## Get chokepoints near position.
func get_chokepoints_near(position: Vector3, radius: float) -> Array[Chokepoint]:
	var result: Array[Chokepoint] = []
	var radius_sq := radius * radius

	for cp in _chokepoints:
		if position.distance_squared_to(cp.position) <= radius_sq:
			result.append(cp)

	return result


## Get faction advantages in zone.
func get_advantages_in_zone(zone: Rect2) -> Array[FactionAdvantage]:
	var result: Array[FactionAdvantage] = []

	for adv in _faction_advantages:
		if adv.zone.intersects(zone):
			result.append(adv)

	return result


## Get advantages for faction.
func get_faction_advantages(faction_id: String) -> Array[FactionAdvantage]:
	var result: Array[FactionAdvantage] = []

	for adv in _faction_advantages:
		if adv.faction == faction_id:
			result.append(adv)

	return result


## Get all chokepoints.
func get_all_chokepoints() -> Array[Chokepoint]:
	return _chokepoints


## Get power-aligned chokepoints.
func get_power_aligned_chokepoints() -> Array[Chokepoint]:
	var result: Array[Chokepoint] = []
	for cp in _chokepoints:
		if cp.power_line_aligned:
			result.append(cp)
	return result


## Get narrowest chokepoints.
func get_narrowest_chokepoints(count: int) -> Array[Chokepoint]:
	var sorted := _chokepoints.duplicate()
	sorted.sort_custom(func(a, b): return a.width < b.width)
	return sorted.slice(0, mini(count, sorted.size()))


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var chokepoints_data: Array = []
	for cp in _chokepoints:
		chokepoints_data.append({
			"position": [cp.position.x, cp.position.y, cp.position.z],
			"width": cp.width,
			"direction": [cp.direction.x, cp.direction.y, cp.direction.z],
			"power_aligned": cp.power_line_aligned
		})

	var advantages_data: Array = []
	for adv in _faction_advantages:
		advantages_data.append({
			"faction": adv.faction,
			"zone": [adv.zone.position.x, adv.zone.position.y, adv.zone.size.x, adv.zone.size.y],
			"type": adv.advantage_type,
			"strength": adv.strength
		})

	return {
		"chokepoints": chokepoints_data,
		"advantages": advantages_data
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_chokepoints.clear()
	_faction_advantages.clear()

	for cp_data in data.get("chokepoints", []):
		var cp := Chokepoint.new()
		var pos: Array = cp_data["position"]
		cp.position = Vector3(pos[0], pos[1], pos[2])
		cp.width = cp_data["width"]
		var dir: Array = cp_data["direction"]
		cp.direction = Vector3(dir[0], dir[1], dir[2])
		cp.power_line_aligned = cp_data.get("power_aligned", false)
		_chokepoints.append(cp)

	for adv_data in data.get("advantages", []):
		var adv := FactionAdvantage.new()
		adv.faction = adv_data["faction"]
		var zone: Array = adv_data["zone"]
		adv.zone = Rect2(zone[0], zone[1], zone[2], zone[3])
		adv.advantage_type = adv_data["type"]
		adv.strength = adv_data["strength"]
		_faction_advantages.append(adv)


## Get statistics.
func get_statistics() -> Dictionary:
	var power_aligned := 0
	var narrow_count := 0

	for cp in _chokepoints:
		if cp.power_line_aligned:
			power_aligned += 1
		if cp.width < 2.0:
			narrow_count += 1

	var adv_by_type: Dictionary = {}
	for adv in _faction_advantages:
		adv_by_type[adv.advantage_type] = adv_by_type.get(adv.advantage_type, 0) + 1

	return {
		"total_chokepoints": _chokepoints.size(),
		"power_aligned_chokepoints": power_aligned,
		"narrow_chokepoints": narrow_count,
		"total_advantages": _faction_advantages.size(),
		"advantages_by_type": adv_by_type
	}
