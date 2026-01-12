class_name DistrictManager
extends RefCounted
## DistrictManager manages all 64 districts in the 8x8 grid.
## Provides efficient queries by position, owner, or type.

signal district_captured(district_id: int, old_owner: String, new_owner: String)
signal district_contested(district_id: int, factions: Array)
signal resources_generated(faction_id: String, power: float, ree: float, research: float)

## All districts indexed by ID (0-63)
var _districts: Array[District] = []

## Districts indexed by owner (faction_id -> Array[district_id])
var _districts_by_owner: Dictionary = {}

## Districts indexed by type (type -> Array[district_id])
var _districts_by_type: Dictionary = {}

## Neutral districts
var _neutral_districts: Array[int] = []

## Type configurations
var _type_configs: Dictionary = {}

## Performance tracking
var _last_update_time_us: int = 0


func _init() -> void:
	_type_configs = DistrictTypeConfig.create_all_configs()
	_initialize_districts()


## Initialize all 64 districts.
func _initialize_districts() -> void:
	_districts.clear()
	_neutral_districts.clear()

	# Initialize type index
	for type in [DistrictType.Type.POWER_HUB, DistrictType.Type.INDUSTRIAL,
				 DistrictType.Type.RESEARCH, DistrictType.Type.RESIDENTIAL,
				 DistrictType.Type.MIXED]:
		_districts_by_type[type] = []

	# Create all districts
	for i in District.TOTAL_DISTRICTS:
		var district := District.new(i)
		# Default to MIXED type, can be set later
		district.district_type = DistrictType.Type.MIXED
		district.type_config = _type_configs[DistrictType.Type.MIXED]

		# Connect signals
		district.ownership_changed.connect(_on_district_ownership_changed.bind(i))

		_districts.append(district)
		_neutral_districts.append(i)
		_districts_by_type[DistrictType.Type.MIXED].append(i)


## Handle district ownership change.
func _on_district_ownership_changed(old_owner: String, new_owner: String, district_id: int) -> void:
	# Update owner index
	if not old_owner.is_empty():
		if _districts_by_owner.has(old_owner):
			var idx := _districts_by_owner[old_owner].find(district_id)
			if idx >= 0:
				_districts_by_owner[old_owner].remove_at(idx)

	if new_owner.is_empty():
		if district_id not in _neutral_districts:
			_neutral_districts.append(district_id)
	else:
		var idx := _neutral_districts.find(district_id)
		if idx >= 0:
			_neutral_districts.remove_at(idx)

		if not _districts_by_owner.has(new_owner):
			_districts_by_owner[new_owner] = []
		if district_id not in _districts_by_owner[new_owner]:
			_districts_by_owner[new_owner].append(district_id)

	district_captured.emit(district_id, old_owner, new_owner)


## Get district by ID.
func get_district(id: int) -> District:
	if id >= 0 and id < _districts.size():
		return _districts[id]
	return null


## Get district at grid position.
func get_district_at_grid(grid_x: int, grid_y: int) -> District:
	if grid_x < 0 or grid_x >= District.GRID_SIZE:
		return null
	if grid_y < 0 or grid_y >= District.GRID_SIZE:
		return null
	var id := grid_y * District.GRID_SIZE + grid_x
	return get_district(id)


## Get district containing world position.
func get_district_at_position(pos: Vector3) -> District:
	var grid_x := int(pos.x / District.DISTRICT_SIZE)
	var grid_y := int(pos.z / District.DISTRICT_SIZE)
	return get_district_at_grid(grid_x, grid_y)


## Get district ID from world position.
func get_district_id_at_position(pos: Vector3) -> int:
	var grid_x := int(pos.x / District.DISTRICT_SIZE)
	var grid_y := int(pos.z / District.DISTRICT_SIZE)
	if grid_x < 0 or grid_x >= District.GRID_SIZE:
		return -1
	if grid_y < 0 or grid_y >= District.GRID_SIZE:
		return -1
	return grid_y * District.GRID_SIZE + grid_x


## Get all districts owned by a faction.
func get_districts_by_owner(faction_id: String) -> Array[District]:
	var result: Array[District] = []
	if faction_id.is_empty():
		for id in _neutral_districts:
			result.append(_districts[id])
	elif _districts_by_owner.has(faction_id):
		for id in _districts_by_owner[faction_id]:
			result.append(_districts[id])
	return result


## Get district IDs owned by a faction.
func get_district_ids_by_owner(faction_id: String) -> Array[int]:
	if faction_id.is_empty():
		return _neutral_districts.duplicate()
	return _districts_by_owner.get(faction_id, []).duplicate()


## Get all districts of a type.
func get_districts_by_type(type: int) -> Array[District]:
	var result: Array[District] = []
	if _districts_by_type.has(type):
		for id in _districts_by_type[type]:
			result.append(_districts[id])
	return result


## Get all neutral districts.
func get_neutral_districts() -> Array[District]:
	return get_districts_by_owner("")


## Get all contested districts.
func get_contested_districts() -> Array[District]:
	var result: Array[District] = []
	for district in _districts:
		if district.is_contested:
			result.append(district)
	return result


## Set district type.
func set_district_type(district_id: int, type: int) -> void:
	var district := get_district(district_id)
	if district == null:
		return

	# Update type index
	var old_type := district.district_type
	if _districts_by_type.has(old_type):
		var idx := _districts_by_type[old_type].find(district_id)
		if idx >= 0:
			_districts_by_type[old_type].remove_at(idx)

	district.district_type = type
	district.type_config = _type_configs.get(type, _type_configs[DistrictType.Type.MIXED])

	if not _districts_by_type.has(type):
		_districts_by_type[type] = []
	_districts_by_type[type].append(district_id)


## Set district owner.
func set_district_owner(district_id: int, faction_id: String) -> void:
	var district := get_district(district_id)
	if district != null:
		district.set_owner(faction_id)


## Update unit presence in district.
func update_unit_in_district(unit_position: Vector3, faction_id: String, delta: int = 1) -> void:
	var district := get_district_at_position(unit_position)
	if district != null:
		var current := district.get_unit_count(faction_id)
		district.update_unit_presence(faction_id, current + delta)


## Process all districts for a time delta.
## Returns total resources generated per faction.
func process(delta: float, faction_modifiers: Dictionary = {}) -> Dictionary:
	var start_time := Time.get_ticks_usec()
	var faction_resources: Dictionary = {}

	for district in _districts:
		if district.is_neutral():
			continue

		var modifier: float = faction_modifiers.get(district.owner_faction, 1.0)
		var resources := district.generate_resources(delta, modifier)

		if not faction_resources.has(district.owner_faction):
			faction_resources[district.owner_faction] = {"power": 0.0, "ree": 0.0, "research": 0.0}

		faction_resources[district.owner_faction]["power"] += resources["power"]
		faction_resources[district.owner_faction]["ree"] += resources["ree"]
		faction_resources[district.owner_faction]["research"] += resources["research"]

	# Emit resource events
	for faction_id in faction_resources:
		var res: Dictionary = faction_resources[faction_id]
		resources_generated.emit(faction_id, res["power"], res["ree"], res["research"])

	_last_update_time_us = Time.get_ticks_usec() - start_time
	return faction_resources


## Get count of districts owned by faction.
func get_district_count_by_owner(faction_id: String) -> int:
	if faction_id.is_empty():
		return _neutral_districts.size()
	return _districts_by_owner.get(faction_id, []).size()


## Get total district count.
func get_total_district_count() -> int:
	return _districts.size()


## Get neighbors of a district.
func get_district_neighbors(district_id: int) -> Array[District]:
	var result: Array[District] = []
	var district := get_district(district_id)
	if district == null:
		return result

	for neighbor_id in district.get_neighbor_ids():
		var neighbor := get_district(neighbor_id)
		if neighbor != null:
			result.append(neighbor)

	return result


## Check if faction controls adjacent district.
func has_adjacent_control(district_id: int, faction_id: String) -> bool:
	var district := get_district(district_id)
	if district == null:
		return false

	for neighbor_id in district.get_neighbor_ids():
		var neighbor := get_district(neighbor_id)
		if neighbor != null and neighbor.is_owned_by(faction_id):
			return true

	return false


## Serialize all districts.
func to_dict() -> Dictionary:
	var districts_data: Array = []
	for district in _districts:
		districts_data.append(district.to_dict())

	return {
		"districts": districts_data,
		"last_update_time_us": _last_update_time_us
	}


## Deserialize all districts.
func from_dict(data: Dictionary) -> void:
	var districts_data: Array = data.get("districts", [])

	# Clear indexes
	_districts_by_owner.clear()
	_neutral_districts.clear()
	for type in _districts_by_type:
		_districts_by_type[type].clear()

	# Restore districts
	for i in districts_data.size():
		if i < _districts.size():
			var district_data: Dictionary = districts_data[i]
			var district := District.from_dict(district_data)
			_districts[i] = district

			# Reconnect signals
			district.ownership_changed.connect(_on_district_ownership_changed.bind(i))

			# Update indexes
			if district.is_neutral():
				_neutral_districts.append(i)
			else:
				if not _districts_by_owner.has(district.owner_faction):
					_districts_by_owner[district.owner_faction] = []
				_districts_by_owner[district.owner_faction].append(i)

			if not _districts_by_type.has(district.district_type):
				_districts_by_type[district.district_type] = []
			_districts_by_type[district.district_type].append(i)


## Get performance stats.
func get_performance_stats() -> Dictionary:
	return {
		"last_update_us": _last_update_time_us,
		"district_count": _districts.size(),
		"neutral_count": _neutral_districts.size(),
		"factions_with_districts": _districts_by_owner.size()
	}


## Get summary for debugging.
func get_summary() -> Dictionary:
	var owner_counts := {}
	for faction_id in _districts_by_owner:
		owner_counts[faction_id] = _districts_by_owner[faction_id].size()

	var type_counts := {}
	for type in _districts_by_type:
		type_counts[DistrictType.get_type_name(type)] = _districts_by_type[type].size()

	return {
		"total_districts": _districts.size(),
		"neutral_districts": _neutral_districts.size(),
		"ownership": owner_counts,
		"types": type_counts,
		"contested": get_contested_districts().size()
	}
