class_name AIComponent
extends Component
## AIComponent manages behavior tree execution and target selection for units.
## Serves as the bridge between behavior tree framework and unit actions.

signal target_acquired(target_id: int)
signal target_lost(old_target_id: int)
signal action_changed(old_action: String, new_action: String)
signal threat_level_changed(old_level: float, new_level: float)

## AI states
enum AIState {
	IDLE = 0,
	PURSUING = 1,
	ATTACKING = 2,
	FLEEING = 3,
	PATROLLING = 4,
	DEFENDING = 5
}

## Behavior tree wrapper for this unit
var behavior_tree: BehaviorTreeWrapper = null

## Current target information
var current_target: TargetInfo = null

## Current AI state
var current_state: int = AIState.IDLE

## Current action from behavior tree
var current_action: String = "idle"

## Threat level (0.0 to 1.0) based on nearby enemies
var threat_level: float = 0.0

## Vision range for target detection
var vision_range: float = 50.0

## Attack range
var attack_range: float = 10.0

## Unit's damage output (for threat calculation by others)
var unit_damage: float = 10.0

## Faction ID (cached for quick access)
var faction_id: int = 0

## Whether AI is enabled
var ai_enabled: bool = true

## Time since last target scan
var _time_since_scan: float = 0.0

## Target scan interval (seconds)
var target_scan_interval: float = 0.2

## Cached potential targets from last scan
var _potential_targets: Array[TargetInfo] = []

## Maximum targets to consider
var max_target_candidates: int = 10


func _init() -> void:
	super._init()
	component_type = "AIComponent"
	current_target = TargetInfo.new()


## Initialize with faction and unit data.
func initialize_ai(p_faction_id: int, unit_type: String, seed: int = 0) -> void:
	faction_id = p_faction_id

	# Create behavior tree wrapper
	behavior_tree = BehaviorTreeWrapper.new(entity_id, faction_id, unit_type)
	if seed != 0:
		behavior_tree.initialize(seed)


## Set behavior tree from template.
func set_behavior_template(template: BehaviorTreeTemplate) -> void:
	if behavior_tree != null:
		behavior_tree.set_tree_from_template(template)


## Set behavior tree from registry.
func set_behavior_from_registry(registry: BehaviorTreeRegistry, unit_type: String) -> void:
	if behavior_tree == null:
		behavior_tree = BehaviorTreeWrapper.new(entity_id, faction_id, unit_type)

	var template := registry.find_best_template(faction_id, unit_type)
	if template != null:
		behavior_tree.set_tree_from_template(template)


## Called every frame to update AI.
func tick(delta: float, unit_position: Vector3, nearby_units: Array) -> String:
	if not ai_enabled or behavior_tree == null:
		return current_action

	# Update target scan timer
	_time_since_scan += delta
	if _time_since_scan >= target_scan_interval:
		_time_since_scan = 0.0
		_scan_for_targets(unit_position, nearby_units)

	# Update blackboard with current state
	_update_blackboard(unit_position)

	# Evaluate behavior tree
	var old_action := current_action
	current_action = behavior_tree.evaluate()

	if current_action != old_action:
		action_changed.emit(old_action, current_action)

	# Update AI state based on action
	_update_ai_state()

	return current_action


## Scan for targets among nearby units.
func _scan_for_targets(unit_position: Vector3, nearby_units: Array) -> void:
	_potential_targets.clear()
	var best_target: TargetInfo = null
	var best_priority := -INF

	for unit_data in nearby_units:
		# Skip if same faction (ally)
		var unit_faction: int = unit_data.get("faction_id", faction_id)
		if unit_faction == faction_id:
			continue

		# Skip if dead
		var is_alive: bool = unit_data.get("is_alive", true)
		if not is_alive:
			continue

		var target_pos: Vector3 = unit_data.get("position", Vector3.ZERO)
		var distance := unit_position.distance_to(target_pos)

		# Skip if out of vision range
		if distance > vision_range:
			continue

		# Create target info
		var target := TargetInfo.new(unit_data.get("id", -1))
		target.faction_id = unit_faction
		target.distance = distance
		target.position = target_pos
		target.health_ratio = unit_data.get("health_ratio", 1.0)
		target.damage = unit_data.get("damage", 10.0)
		target.unit_type = unit_data.get("unit_type", "")
		target.is_attacking_us = unit_data.get("target_id", -1) == entity_id

		# Calculate priority
		target.calculate_threat()
		target.calculate_priority()

		_potential_targets.append(target)

		# Track best target
		if target.priority > best_priority:
			best_priority = target.priority
			best_target = target

		# Limit candidates
		if _potential_targets.size() >= max_target_candidates:
			break

	# Update current target
	_update_current_target(best_target)

	# Update threat level based on nearby enemies
	_update_threat_level()


## Update current target.
func _update_current_target(new_target: TargetInfo) -> void:
	var old_target_id := current_target.target_id

	if new_target == null:
		if current_target.target_id >= 0:
			current_target.clear()
			target_lost.emit(old_target_id)
	else:
		if new_target.target_id != current_target.target_id:
			if current_target.target_id >= 0:
				target_lost.emit(old_target_id)
			current_target = new_target
			target_acquired.emit(new_target.target_id)
		else:
			# Update existing target info
			current_target = new_target


## Update threat level based on nearby enemies.
func _update_threat_level() -> void:
	var old_threat := threat_level

	if _potential_targets.is_empty():
		threat_level = 0.0
	else:
		# Calculate threat as sum of nearby enemy threats, normalized
		var total_threat := 0.0
		for target in _potential_targets:
			# Closer enemies contribute more to threat
			var distance_factor := 1.0 - clampf(target.distance / vision_range, 0.0, 1.0)
			total_threat += target.threat * distance_factor

		# Normalize to 0-1 range (assume 100 is max reasonable threat)
		threat_level = clampf(total_threat / 100.0, 0.0, 1.0)

	if absf(threat_level - old_threat) > 0.1:
		threat_level_changed.emit(old_threat, threat_level)


## Update blackboard with current state.
func _update_blackboard(unit_position: Vector3) -> void:
	if behavior_tree == null:
		return

	behavior_tree.set_blackboard_var("position", unit_position)
	behavior_tree.set_blackboard_var("attack_range", attack_range)
	behavior_tree.set_blackboard_var("vision_range", vision_range)
	behavior_tree.set_blackboard_var("threat_level", threat_level)
	behavior_tree.set_blackboard_var("current_state", current_state)

	if current_target.is_valid():
		behavior_tree.set_target(
			current_target.target_id,
			current_target.position,
			current_target.distance
		)
	else:
		behavior_tree.clear_target()


## Update AI state based on current action.
func _update_ai_state() -> void:
	match current_action:
		"idle", "hold":
			current_state = AIState.IDLE
		"attack":
			current_state = AIState.ATTACKING
		"chase", "move_to_target":
			current_state = AIState.PURSUING
		"flee", "retreat":
			current_state = AIState.FLEEING
		"patrol":
			current_state = AIState.PATROLLING
		"defend", "return_to_post":
			current_state = AIState.DEFENDING


## Get current target ID.
func get_target_id() -> int:
	return current_target.target_id


## Get current target position.
func get_target_position() -> Vector3:
	return current_target.position


## Get current target distance.
func get_target_distance() -> float:
	return current_target.distance


## Check if has valid target.
func has_target() -> bool:
	return current_target.is_valid()


## Check if target is in attack range.
func is_target_in_range() -> bool:
	return current_target.is_valid() and current_target.distance <= attack_range


## Force set target by ID.
func force_target(target_id: int, target_position: Vector3, target_distance: float) -> void:
	var old_target_id := current_target.target_id

	current_target.target_id = target_id
	current_target.position = target_position
	current_target.distance = target_distance

	if target_id != old_target_id:
		if old_target_id >= 0:
			target_lost.emit(old_target_id)
		if target_id >= 0:
			target_acquired.emit(target_id)


## Clear current target.
func clear_target() -> void:
	var old_target_id := current_target.target_id
	current_target.clear()
	if old_target_id >= 0:
		target_lost.emit(old_target_id)


## Enable/disable AI.
func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled


## Pause behavior tree.
func pause() -> void:
	if behavior_tree != null:
		behavior_tree.pause()


## Resume behavior tree.
func resume() -> void:
	if behavior_tree != null:
		behavior_tree.resume()


## Get AI state name.
func get_state_name() -> String:
	match current_state:
		AIState.IDLE: return "IDLE"
		AIState.PURSUING: return "PURSUING"
		AIState.ATTACKING: return "ATTACKING"
		AIState.FLEEING: return "FLEEING"
		AIState.PATROLLING: return "PATROLLING"
		AIState.DEFENDING: return "DEFENDING"
		_: return "UNKNOWN"


## Override component type.
func get_component_type() -> String:
	return "AIComponent"


## Serialize to dictionary.
func _to_dict() -> Dictionary:
	var base := super._to_dict()
	base["ai"] = {
		"faction_id": faction_id,
		"current_state": current_state,
		"current_action": current_action,
		"threat_level": threat_level,
		"vision_range": vision_range,
		"attack_range": attack_range,
		"unit_damage": unit_damage,
		"ai_enabled": ai_enabled,
		"target_scan_interval": target_scan_interval,
		"current_target": current_target.to_dict() if current_target != null else {}
	}
	return base


## Deserialize from dictionary.
func _from_dict(dict_data: Dictionary) -> void:
	super._from_dict(dict_data)
	var ai_data: Dictionary = dict_data.get("ai", {})
	faction_id = ai_data.get("faction_id", 0)
	current_state = ai_data.get("current_state", AIState.IDLE)
	current_action = ai_data.get("current_action", "idle")
	threat_level = ai_data.get("threat_level", 0.0)
	vision_range = ai_data.get("vision_range", 50.0)
	attack_range = ai_data.get("attack_range", 10.0)
	unit_damage = ai_data.get("unit_damage", 10.0)
	ai_enabled = ai_data.get("ai_enabled", true)
	target_scan_interval = ai_data.get("target_scan_interval", 0.2)

	var target_data: Dictionary = ai_data.get("current_target", {})
	if not target_data.is_empty():
		current_target = TargetInfo.from_dict(target_data)
	else:
		current_target = TargetInfo.new()


## Get debug info.
func get_debug_info() -> Dictionary:
	var info := {
		"entity_id": entity_id,
		"faction_id": faction_id,
		"state": get_state_name(),
		"action": current_action,
		"threat_level": threat_level,
		"ai_enabled": ai_enabled,
		"has_target": has_target(),
		"target_id": current_target.target_id,
		"target_distance": current_target.distance,
		"potential_targets": _potential_targets.size()
	}

	if behavior_tree != null:
		info["bt_evaluations"] = behavior_tree.total_evaluations
		info["bt_last_time_ms"] = behavior_tree.last_evaluation_time_ms

	return info
