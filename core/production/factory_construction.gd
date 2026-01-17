class_name FactoryConstruction
extends RefCounted
## FactoryConstruction manages the building of new factories by builder units.
## Handles placement validation, construction progress, and completion.

signal construction_started(site_id: int, position: Vector3, faction_id: int)
signal construction_progress(site_id: int, progress: float)
signal construction_completed(site_id: int, factory_id: int)
signal construction_cancelled(site_id: int)

## Construction costs
const FACTORY_REE_COST := 500.0
const FACTORY_POWER_COST := 50.0

## Construction timing
const BASE_CONSTRUCTION_TIME := 30.0  ## 30 seconds base
const BUILDER_SPEED_BONUS := 0.25  ## Each additional builder adds 25% speed

## Placement rules
const MIN_FACTORY_DISTANCE := 100.0  ## Minimum distance between factories
const MAX_FACTORIES_PER_FACTION := 4  ## Maximum factories per faction

## Construction site data
class ConstructionSite:
	var id: int = 0
	var position: Vector3 = Vector3.ZERO
	var faction_id: int = 0
	var progress: float = 0.0  ## 0.0 to 1.0
	var builder_count: int = 0
	var builder_ids: Array[int] = []
	var is_complete: bool = false
	var is_cancelled: bool = false
	var district_id: int = -1
	var visual_node: Node3D = null

	func get_construction_speed() -> float:
		if builder_count <= 0:
			return 0.0
		# First builder = 1.0x, each additional = +0.25x
		return 1.0 + (builder_count - 1) * BUILDER_SPEED_BONUS


## Active construction sites
var _sites: Dictionary = {}  ## site_id -> ConstructionSite
var _next_site_id: int = 1

## Factory positions for distance checking
var _existing_factory_positions: Array[Vector3] = []

## Faction factory counts
var _faction_factory_counts: Dictionary = {}  ## faction_id -> count


func _init() -> void:
	pass


## Register existing factory position (call at game start)
func register_factory(position: Vector3, faction_id: int) -> void:
	_existing_factory_positions.append(position)
	if not _faction_factory_counts.has(faction_id):
		_faction_factory_counts[faction_id] = 0
	_faction_factory_counts[faction_id] += 1


## Check if placement is valid
func is_valid_placement(position: Vector3, faction_id: int, district_owner: int) -> Dictionary:
	var result := {
		"valid": true,
		"reason": ""
	}

	# Check faction owns district
	if district_owner != faction_id:
		result.valid = false
		result.reason = "Must place in owned district"
		return result

	# Check factory count
	var current_count: int = _faction_factory_counts.get(faction_id, 0)
	var construction_count := _count_faction_constructions(faction_id)
	if current_count + construction_count >= MAX_FACTORIES_PER_FACTION:
		result.valid = false
		result.reason = "Maximum factories reached (%d)" % MAX_FACTORIES_PER_FACTION
		return result

	# Check distance from existing factories
	for factory_pos: Vector3 in _existing_factory_positions:
		var dist: float = position.distance_to(factory_pos)
		if dist < MIN_FACTORY_DISTANCE:
			result.valid = false
			result.reason = "Too close to existing factory (%.0f < %.0f)" % [dist, MIN_FACTORY_DISTANCE]
			return result

	# Check distance from construction sites
	for site_id: int in _sites.keys():
		var site: ConstructionSite = _sites[site_id]
		if site.is_complete or site.is_cancelled:
			continue
		var dist: float = position.distance_to(site.position)
		if dist < MIN_FACTORY_DISTANCE:
			result.valid = false
			result.reason = "Too close to construction site"
			return result

	return result


## Count active constructions for faction
func _count_faction_constructions(faction_id: int) -> int:
	var count := 0
	for site_id: int in _sites.keys():
		var site: ConstructionSite = _sites[site_id]
		if site.faction_id == faction_id and not site.is_complete and not site.is_cancelled:
			count += 1
	return count


## Start construction at position
func start_construction(position: Vector3, faction_id: int, district_id: int, builder_id: int) -> int:
	var site := ConstructionSite.new()
	site.id = _next_site_id
	_next_site_id += 1
	site.position = position
	site.faction_id = faction_id
	site.district_id = district_id
	site.builder_ids.append(builder_id)
	site.builder_count = 1

	_sites[site.id] = site
	construction_started.emit(site.id, position, faction_id)

	return site.id


## Add builder to construction site
func add_builder(site_id: int, builder_id: int) -> bool:
	if not _sites.has(site_id):
		return false

	var site: ConstructionSite = _sites[site_id]
	if site.is_complete or site.is_cancelled:
		return false

	if builder_id in site.builder_ids:
		return false  # Already assigned

	site.builder_ids.append(builder_id)
	site.builder_count = site.builder_ids.size()
	return true


## Remove builder from construction site
func remove_builder(site_id: int, builder_id: int) -> void:
	if not _sites.has(site_id):
		return

	var site: ConstructionSite = _sites[site_id]
	site.builder_ids.erase(builder_id)
	site.builder_count = site.builder_ids.size()


## Update construction progress
func update(delta: float) -> Array[int]:
	var completed_sites: Array[int] = []

	for site_id: int in _sites.keys():
		var site: ConstructionSite = _sites[site_id]
		if site.is_complete or site.is_cancelled:
			continue

		# Calculate progress increment
		var speed: float = site.get_construction_speed()
		if speed <= 0:
			continue

		var progress_delta: float = (delta / BASE_CONSTRUCTION_TIME) * speed
		site.progress = minf(site.progress + progress_delta, 1.0)

		construction_progress.emit(site_id, site.progress)

		# Check completion
		if site.progress >= 1.0:
			site.is_complete = true
			completed_sites.append(site_id)

	return completed_sites


## Mark construction as complete (called after factory created)
func finalize_construction(site_id: int, factory_id: int) -> void:
	if not _sites.has(site_id):
		return

	var site: ConstructionSite = _sites[site_id]

	# Add to factory positions
	_existing_factory_positions.append(site.position)

	# Update faction count
	if not _faction_factory_counts.has(site.faction_id):
		_faction_factory_counts[site.faction_id] = 0
	_faction_factory_counts[site.faction_id] += 1

	construction_completed.emit(site_id, factory_id)


## Cancel construction
func cancel_construction(site_id: int) -> void:
	if not _sites.has(site_id):
		return

	var site: ConstructionSite = _sites[site_id]
	site.is_cancelled = true
	construction_cancelled.emit(site_id)


## Get site by ID
func get_site(site_id: int) -> ConstructionSite:
	return _sites.get(site_id)


## Get all active sites
func get_active_sites() -> Array[ConstructionSite]:
	var result: Array[ConstructionSite] = []
	for site_id: int in _sites.keys():
		var site: ConstructionSite = _sites[site_id]
		if not site.is_complete and not site.is_cancelled:
			result.append(site)
	return result


## Get site at position
func get_site_at(position: Vector3, radius: float = 10.0) -> ConstructionSite:
	for site_id: int in _sites.keys():
		var site: ConstructionSite = _sites[site_id]
		if site.is_complete or site.is_cancelled:
			continue
		if position.distance_to(site.position) <= radius:
			return site
	return null


## Get site for faction nearest to position
func get_nearest_site(position: Vector3, faction_id: int) -> ConstructionSite:
	var nearest: ConstructionSite = null
	var nearest_dist := INF

	for site_id: int in _sites.keys():
		var site: ConstructionSite = _sites[site_id]
		if site.faction_id != faction_id:
			continue
		if site.is_complete or site.is_cancelled:
			continue
		var dist: float = position.distance_to(site.position)
		if dist < nearest_dist:
			nearest = site
			nearest_dist = dist

	return nearest


## Clean up completed/cancelled sites
func cleanup_old_sites() -> void:
	var to_remove: Array[int] = []
	for site_id: int in _sites.keys():
		var site: ConstructionSite = _sites[site_id]
		if site.is_complete or site.is_cancelled:
			to_remove.append(site_id)

	for site_id in to_remove:
		_sites.erase(site_id)


## Serialize
func to_dict() -> Dictionary:
	var sites_data: Array = []
	for site_id: int in _sites.keys():
		var site: ConstructionSite = _sites[site_id]
		sites_data.append({
			"id": site.id,
			"position": {"x": site.position.x, "y": site.position.y, "z": site.position.z},
			"faction_id": site.faction_id,
			"progress": site.progress,
			"builder_ids": site.builder_ids.duplicate(),
			"is_complete": site.is_complete,
			"is_cancelled": site.is_cancelled,
			"district_id": site.district_id
		})

	return {
		"sites": sites_data,
		"next_site_id": _next_site_id,
		"existing_factory_positions": _existing_factory_positions.map(func(p): return {"x": p.x, "y": p.y, "z": p.z}),
		"faction_factory_counts": _faction_factory_counts.duplicate()
	}


## Deserialize
func from_dict(data: Dictionary) -> void:
	_sites.clear()
	_next_site_id = data.get("next_site_id", 1)

	_existing_factory_positions.clear()
	for pos_data: Dictionary in data.get("existing_factory_positions", []):
		_existing_factory_positions.append(Vector3(pos_data.get("x", 0), pos_data.get("y", 0), pos_data.get("z", 0)))

	_faction_factory_counts = data.get("faction_factory_counts", {}).duplicate()

	for site_data: Dictionary in data.get("sites", []):
		var site := ConstructionSite.new()
		site.id = site_data.get("id", 0)
		var pos: Dictionary = site_data.get("position", {})
		site.position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		site.faction_id = site_data.get("faction_id", 0)
		site.progress = site_data.get("progress", 0.0)
		site.builder_ids.assign(site_data.get("builder_ids", []))
		site.builder_count = site.builder_ids.size()
		site.is_complete = site_data.get("is_complete", false)
		site.is_cancelled = site_data.get("is_cancelled", false)
		site.district_id = site_data.get("district_id", -1)
		_sites[site.id] = site
