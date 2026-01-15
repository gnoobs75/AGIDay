class_name AIComponentSystem
extends RefCounted
## AIComponentSystem manages AI components within the ECS framework.
## Bridges AISystem with entity components for unified AI processing.

signal component_added(entity_id: int, component: AIComponentData)
signal component_removed(entity_id: int)
signal batch_processed(count: int, time_ms: float)

## Reference to main AI system
var _ai_system: AISystem = null

## Components (entity_id -> AIComponentData)
var _components: Dictionary = {}

## Processing order (prioritized)
var _processing_order: Array[int] = []

## Performance tracking
var _last_process_time_ms := 0.0


func _init() -> void:
	_ai_system = AISystem.new()


## Get AI system reference.
func get_ai_system() -> AISystem:
	return _ai_system


## Register behavior tree template.
func register_tree_template(tree_name: String, root: LimboAIWrapper.BTNode) -> void:
	_ai_system.register_tree_template(tree_name, root)


## Add AI component to entity.
func add_component(entity_id: int, faction_id: String, unit_type: String, tree_name: String) -> AIComponentData:
	var component := AIComponentData.new()
	component.initialize(entity_id, faction_id, unit_type, tree_name)

	_components[entity_id] = component
	_processing_order.append(entity_id)

	# Register with AI system
	_ai_system.register_unit(entity_id, faction_id, tree_name)

	component_added.emit(entity_id, component)

	return component


## Remove AI component.
func remove_component(entity_id: int) -> void:
	if not _components.has(entity_id):
		return

	_ai_system.unregister_unit(entity_id)
	_components.erase(entity_id)

	var idx := _processing_order.find(entity_id)
	if idx != -1:
		_processing_order.remove_at(idx)

	component_removed.emit(entity_id)


## Get component.
func get_component(entity_id: int) -> AIComponentData:
	return _components.get(entity_id)


## Has component.
func has_component(entity_id: int) -> bool:
	return _components.has(entity_id)


## Update all components - call each frame.
func update(delta: float) -> void:
	var start_time := Time.get_ticks_usec()

	# Update AI system (handles behavior tree execution)
	_ai_system.update(delta)

	# Sync component data from blackboards
	_sync_component_states()

	_last_process_time_ms = float(Time.get_ticks_usec() - start_time) / 1000.0
	batch_processed.emit(_components.size(), _last_process_time_ms)


## Sync component states from behavior tree results.
func _sync_component_states() -> void:
	for entity_id in _components:
		var component: AIComponentData = _components[entity_id]

		# Get latest blackboard values
		var target_id: Variant = _ai_system.distributed_bt.get_blackboard_value(entity_id, "target_id", -1)
		if target_id is int:
			if target_id != component.target_entity_id:
				if target_id == -1:
					component.clear_target()
				else:
					component.set_target(target_id)

		# Update state based on last action
		var last_action: String = _ai_system.distributed_bt.get_blackboard_value(entity_id, "last_action", "")
		if last_action != "":
			_update_state_from_action(component, last_action)

		# Apply faction buffs
		_sync_buffs(component)


## Update component state based on action.
func _update_state_from_action(component: AIComponentData, action: String) -> void:
	match action:
		"patrol", "move_to_patrol":
			component.set_state(AIComponentData.State.PATROLLING)
		"pursue", "chase", "move_to_target":
			component.set_state(AIComponentData.State.PURSUING)
		"attack", "engage", "fire":
			component.set_state(AIComponentData.State.ATTACKING)
		"flee", "retreat", "escape":
			component.set_state(AIComponentData.State.FLEEING)
		"support", "heal", "repair":
			component.set_state(AIComponentData.State.SUPPORTING)
		"build", "construct":
			component.set_state(AIComponentData.State.BUILDING)
		"idle", "wait":
			component.set_state(AIComponentData.State.IDLE)


## Sync buffs from hive mind to component.
func _sync_buffs(component: AIComponentData) -> void:
	for buff_type in HiveMindProgression.BuffType.values():
		var value := _ai_system.get_unit_buff(component.entity_id, buff_type)
		if value > 0:
			component.apply_buff(buff_type, value)


## Update single component's blackboard data.
func update_component_data(entity_id: int, position: Vector3, health_percent: float, allies: Array, enemies: Array) -> void:
	if not _components.has(entity_id):
		return

	var component: AIComponentData = _components[entity_id]

	_ai_system.update_unit_data_batch(entity_id, {
		"position": position,
		"health_percent": health_percent,
		"allies_nearby": allies,
		"enemies_nearby": enemies,
		"in_combat": not enemies.is_empty(),
		"detection_range": component.detection_range,
		"attack_range": component.attack_range,
		"aggression": component.aggression
	})


## Set component perception settings.
func set_perception(entity_id: int, detection_range: float, attack_range: float, aggression: float) -> void:
	if not _components.has(entity_id):
		return

	var component: AIComponentData = _components[entity_id]
	component.detection_range = detection_range
	component.attack_range = attack_range
	component.aggression = aggression


## Add faction XP.
func add_faction_xp(faction_id: String, category: int, amount: float) -> void:
	_ai_system.add_faction_xp(faction_id, category, amount)


## Get all entities with AI component.
func get_all_entities() -> Array[int]:
	var entities: Array[int] = []
	for entity_id in _components:
		entities.append(entity_id)
	return entities


## Get entities by faction.
func get_entities_by_faction(faction_id: String) -> Array[int]:
	var entities: Array[int] = []

	for entity_id in _components:
		if _components[entity_id].faction_id == faction_id:
			entities.append(entity_id)

	return entities


## Get entities by state.
func get_entities_by_state(state: int) -> Array[int]:
	var entities: Array[int] = []

	for entity_id in _components:
		if _components[entity_id].current_state == state:
			entities.append(entity_id)

	return entities


## Serialization.
func to_dict() -> Dictionary:
	var components_data: Dictionary = {}

	for entity_id in _components:
		components_data[str(entity_id)] = _components[entity_id].to_dict()

	return {
		"ai_system": _ai_system.to_dict(),
		"components": components_data,
		"processing_order": _processing_order.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	if data.has("ai_system"):
		_ai_system.from_dict(data["ai_system"])

	_components.clear()
	var components_data: Dictionary = data.get("components", {})

	for entity_id_str in components_data:
		var entity_id := int(entity_id_str)
		var component := AIComponentData.new()
		component.from_dict(components_data[entity_id_str])
		_components[entity_id] = component

	_processing_order.clear()
	for entity_id in data.get("processing_order", []):
		_processing_order.append(entity_id)


## Get summary for debugging.
func get_summary() -> Dictionary:
	var state_counts: Dictionary = {}
	for state in AIComponentData.State.values():
		state_counts[AIComponentData.STATE_NAMES[state]] = 0

	var faction_counts: Dictionary = {}

	for entity_id in _components:
		var component: AIComponentData = _components[entity_id]
		state_counts[component.get_state_name()] += 1
		faction_counts[component.faction_id] = faction_counts.get(component.faction_id, 0) + 1

	return {
		"total_components": _components.size(),
		"last_process_time_ms": _last_process_time_ms,
		"state_distribution": state_counts,
		"faction_distribution": faction_counts,
		"ai_system": _ai_system.get_summary()
	}
