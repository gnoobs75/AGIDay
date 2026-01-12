class_name BehaviorTreeFactory
extends RefCounted
## BehaviorTreeFactory creates and caches faction-specific behavior trees.

## Cached behavior trees per faction (faction_id -> tree)
var _faction_trees: Dictionary = {}

## Cached behavior trees per unit type (faction_id:unit_type -> tree)
var _unit_type_trees: Dictionary = {}

## Callbacks (shared across all trees)
var _get_unit_position: Callable
var _get_nearby_allies: Callable
var _get_ally_target: Callable
var _set_attack_target: Callable
var _request_movement: Callable
var _get_enemies_in_range: Callable
var _get_unit_health_percent: Callable
var _get_strategic_points: Callable
var _is_position_held: Callable


func _init() -> void:
	pass


## Set shared callbacks.
func set_get_unit_position(callback: Callable) -> void:
	_get_unit_position = callback


func set_get_nearby_allies(callback: Callable) -> void:
	_get_nearby_allies = callback


func set_get_ally_target(callback: Callable) -> void:
	_get_ally_target = callback


func set_attack_target(callback: Callable) -> void:
	_set_attack_target = callback


func set_request_movement(callback: Callable) -> void:
	_request_movement = callback


func set_get_enemies_in_range(callback: Callable) -> void:
	_get_enemies_in_range = callback


func set_get_unit_health_percent(callback: Callable) -> void:
	_get_unit_health_percent = callback


func set_get_strategic_points(callback: Callable) -> void:
	_get_strategic_points = callback


func set_is_position_held(callback: Callable) -> void:
	_is_position_held = callback


## Get behavior tree for unit.
func get_behavior_tree_for_unit(faction_id: String, unit_type: String = "") -> RefCounted:
	# Check unit type specific tree first
	if not unit_type.is_empty():
		var type_key := "%s:%s" % [faction_id, unit_type]
		if _unit_type_trees.has(type_key):
			return _unit_type_trees[type_key]

	# Fall back to faction tree
	if _faction_trees.has(faction_id):
		return _faction_trees[faction_id]

	# Create new tree
	var tree := _create_faction_tree(faction_id)
	if tree:
		_faction_trees[faction_id] = tree

	return tree


## Create behavior tree for faction.
func _create_faction_tree(faction_id: String) -> RefCounted:
	var tree: RefCounted = null

	match faction_id:
		"aether_swarm":
			tree = _create_aether_swarm_tree()
		"glacius":
			tree = _create_tank_faction_tree()
		_:
			# Default to basic tree
			tree = _create_basic_tree(faction_id)

	return tree


## Create Aether Swarm behavior tree.
func _create_aether_swarm_tree() -> AetherSwarmBehaviorTree:
	var tree := AetherSwarmBehaviorTree.new()

	tree.set_get_unit_position(_get_unit_position)
	tree.set_get_nearby_allies(_get_nearby_allies)
	tree.set_get_ally_target(_get_ally_target)
	tree.set_attack_target(_set_attack_target)
	tree.set_request_movement(_request_movement)
	tree.set_get_enemies_in_range(_get_enemies_in_range)
	tree.set_get_unit_health_percent(_get_unit_health_percent)

	return tree


## Create Tank Faction behavior tree.
func _create_tank_faction_tree() -> TankFactionBehaviorTree:
	var tree := TankFactionBehaviorTree.new()

	tree.set_get_unit_position(_get_unit_position)
	tree.set_get_nearby_allies(_get_nearby_allies)
	tree.set_get_ally_target(_get_ally_target)
	tree.set_attack_target(_set_attack_target)
	tree.set_request_movement(_request_movement)
	tree.set_get_enemies_in_range(_get_enemies_in_range)
	tree.set_get_unit_health_percent(_get_unit_health_percent)
	tree.set_get_strategic_points(_get_strategic_points)
	tree.set_is_position_held(_is_position_held)

	return tree


## Create basic behavior tree for other factions.
func _create_basic_tree(faction_id: String) -> RefCounted:
	# Use Aether Swarm as base for now
	return _create_aether_swarm_tree()


## Register custom tree for unit type.
func register_unit_type_tree(faction_id: String, unit_type: String, tree: RefCounted) -> void:
	var type_key := "%s:%s" % [faction_id, unit_type]
	_unit_type_trees[type_key] = tree


## Clear cached trees.
func clear_cache() -> void:
	_faction_trees.clear()
	_unit_type_trees.clear()


## Get all cached faction trees.
func get_cached_factions() -> Array[String]:
	var factions: Array[String] = []
	for faction_id in _faction_trees:
		factions.append(faction_id)
	return factions


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_list: Array[String] = []
	for faction_id in _faction_trees:
		faction_list.append(faction_id)

	var unit_types: Array[String] = []
	for type_key in _unit_type_trees:
		unit_types.append(type_key)

	return {
		"cached_faction_trees": _faction_trees.size(),
		"cached_unit_type_trees": _unit_type_trees.size(),
		"factions": faction_list,
		"unit_types": unit_types
	}
