class_name BehaviorTreeTemplate
extends Resource
## BehaviorTreeTemplate stores behavior tree structure with faction and unit type metadata.
## Can be saved as .tres resource and loaded at runtime.

## Template identifier
@export var template_id: String = ""

## Faction this template is for (0 = any faction)
@export var faction_id: int = 0

## Unit type this template is for (empty = any unit type)
@export var unit_type: String = ""

## Human-readable description
@export_multiline var description: String = ""

## Tree structure type (determines which factory method to use)
@export_enum("custom", "attack_or_idle", "chase_attack", "patrol", "defend", "gather", "build") var tree_type: String = "attack_or_idle"

## Custom tree definition (for tree_type = "custom")
## Format: Array of node definitions
@export var tree_definition: Array = []

## Default blackboard variables to initialize
@export var default_blackboard_vars: Dictionary = {}

## Priority (higher priority templates override lower)
@export var priority: int = 0


func _init() -> void:
	pass


## Check if this template matches the given faction and unit type.
func matches(p_faction_id: int, p_unit_type: String) -> bool:
	# Faction must match or be 0 (any faction)
	var faction_match := (faction_id == 0) or (faction_id == p_faction_id)

	# Unit type must match or be empty (any unit type)
	var unit_match := unit_type.is_empty() or (unit_type == p_unit_type)

	return faction_match and unit_match


## Get specificity score (more specific = higher score).
func get_specificity() -> int:
	var score := 0
	if faction_id != 0:
		score += 10
	if not unit_type.is_empty():
		score += 5
	score += priority
	return score


## Create a behavior tree instance from this template.
func create_tree(unit_id: int) -> UnitBehaviorTree:
	var tree: UnitBehaviorTree

	match tree_type:
		"attack_or_idle":
			tree = UnitBehaviorTree.create_attack_or_idle_tree(unit_id)
		"chase_attack":
			tree = UnitBehaviorTree.create_chase_attack_tree(unit_id)
		"patrol":
			tree = _create_patrol_tree(unit_id)
		"defend":
			tree = _create_defend_tree(unit_id)
		"gather":
			tree = _create_gather_tree(unit_id)
		"build":
			tree = _create_build_tree(unit_id)
		"custom":
			tree = _create_custom_tree(unit_id)
		_:
			tree = UnitBehaviorTree.create_attack_or_idle_tree(unit_id)

	# Initialize with default blackboard vars
	for key in default_blackboard_vars:
		tree.set_context_value(key, default_blackboard_vars[key])

	return tree


## Create patrol behavior tree.
func _create_patrol_tree(unit_id: int) -> UnitBehaviorTree:
	var tree := UnitBehaviorTree.new(unit_id)
	var root := BTSelector.new("Patrol")

	# Attack if enemy nearby
	var attack_sequence := BTSequence.new("AttackEnemy")
	attack_sequence.add_child(BTCondition.new("HasEnemy", func(ctx: Dictionary) -> bool:
		return ctx.get("enemy_nearby", false)
	))
	attack_sequence.add_child(BTAction.new("Attack", func(ctx: Dictionary) -> int:
		ctx["action"] = "attack"
		return BTStatus.Status.SUCCESS
	))

	# Continue patrol
	var patrol_action := BTAction.new("Patrol", func(ctx: Dictionary) -> int:
		ctx["action"] = "patrol"
		return BTStatus.Status.RUNNING
	)

	root.add_child(attack_sequence)
	root.add_child(patrol_action)
	tree.set_root(root)
	return tree


## Create defend behavior tree.
func _create_defend_tree(unit_id: int) -> UnitBehaviorTree:
	var tree := UnitBehaviorTree.new(unit_id)
	var root := BTSelector.new("Defend")

	# Attack if enemy in defense range
	var attack_sequence := BTSequence.new("AttackInRange")
	attack_sequence.add_child(BTCondition.new("EnemyInDefenseRange", func(ctx: Dictionary) -> bool:
		var dist: float = ctx.get("nearest_enemy_distance", INF)
		var range: float = ctx.get("defense_range", 50.0)
		return dist <= range
	))
	attack_sequence.add_child(BTAction.new("Attack", func(ctx: Dictionary) -> int:
		ctx["action"] = "attack"
		return BTStatus.Status.SUCCESS
	))

	# Return to defense position
	var return_sequence := BTSequence.new("ReturnToPost")
	return_sequence.add_child(BTCondition.new("NotAtPost", func(ctx: Dictionary) -> bool:
		var dist: float = ctx.get("distance_to_post", 0.0)
		return dist > 5.0
	))
	return_sequence.add_child(BTAction.new("ReturnToPost", func(ctx: Dictionary) -> int:
		ctx["action"] = "return_to_post"
		return BTStatus.Status.RUNNING
	))

	# Hold position
	var hold_action := BTAction.new("Hold", func(ctx: Dictionary) -> int:
		ctx["action"] = "hold"
		return BTStatus.Status.SUCCESS
	)

	root.add_child(attack_sequence)
	root.add_child(return_sequence)
	root.add_child(hold_action)
	tree.set_root(root)
	return tree


## Create gather behavior tree (for resource gathering).
func _create_gather_tree(unit_id: int) -> UnitBehaviorTree:
	var tree := UnitBehaviorTree.new(unit_id)
	var root := BTSelector.new("Gather")

	# Return cargo if full
	var return_sequence := BTSequence.new("ReturnCargo")
	return_sequence.add_child(BTCondition.new("CargoFull", func(ctx: Dictionary) -> bool:
		return ctx.get("cargo_full", false)
	))
	return_sequence.add_child(BTAction.new("ReturnCargo", func(ctx: Dictionary) -> int:
		ctx["action"] = "return_cargo"
		return BTStatus.Status.RUNNING
	))

	# Gather from resource
	var gather_sequence := BTSequence.new("GatherResource")
	gather_sequence.add_child(BTCondition.new("HasResourceTarget", func(ctx: Dictionary) -> bool:
		return ctx.get("resource_target_id", -1) >= 0
	))
	gather_sequence.add_child(BTCondition.new("AtResource", func(ctx: Dictionary) -> bool:
		return ctx.get("at_resource", false)
	))
	gather_sequence.add_child(BTAction.new("Gather", func(ctx: Dictionary) -> int:
		ctx["action"] = "gather"
		return BTStatus.Status.RUNNING
	))

	# Move to resource
	var move_sequence := BTSequence.new("MoveToResource")
	move_sequence.add_child(BTCondition.new("HasResourceTarget", func(ctx: Dictionary) -> bool:
		return ctx.get("resource_target_id", -1) >= 0
	))
	move_sequence.add_child(BTAction.new("MoveToResource", func(ctx: Dictionary) -> int:
		ctx["action"] = "move_to_resource"
		return BTStatus.Status.RUNNING
	))

	# Find resource
	var find_action := BTAction.new("FindResource", func(ctx: Dictionary) -> int:
		ctx["action"] = "find_resource"
		return BTStatus.Status.SUCCESS
	)

	root.add_child(return_sequence)
	root.add_child(gather_sequence)
	root.add_child(move_sequence)
	root.add_child(find_action)
	tree.set_root(root)
	return tree


## Create build behavior tree (for builder units).
func _create_build_tree(unit_id: int) -> UnitBehaviorTree:
	var tree := UnitBehaviorTree.new(unit_id)
	var root := BTSelector.new("Build")

	# Build if at construction site
	var build_sequence := BTSequence.new("BuildStructure")
	build_sequence.add_child(BTCondition.new("HasBuildTarget", func(ctx: Dictionary) -> bool:
		return ctx.get("build_target_id", -1) >= 0
	))
	build_sequence.add_child(BTCondition.new("AtBuildSite", func(ctx: Dictionary) -> bool:
		return ctx.get("at_build_site", false)
	))
	build_sequence.add_child(BTAction.new("Build", func(ctx: Dictionary) -> int:
		ctx["action"] = "build"
		return BTStatus.Status.RUNNING
	))

	# Move to construction site
	var move_sequence := BTSequence.new("MoveToBuildSite")
	move_sequence.add_child(BTCondition.new("HasBuildTarget", func(ctx: Dictionary) -> bool:
		return ctx.get("build_target_id", -1) >= 0
	))
	move_sequence.add_child(BTAction.new("MoveToBuildSite", func(ctx: Dictionary) -> int:
		ctx["action"] = "move_to_build_site"
		return BTStatus.Status.RUNNING
	))

	# Repair if has repair target
	var repair_sequence := BTSequence.new("RepairStructure")
	repair_sequence.add_child(BTCondition.new("HasRepairTarget", func(ctx: Dictionary) -> bool:
		return ctx.get("repair_target_id", -1) >= 0
	))
	repair_sequence.add_child(BTAction.new("Repair", func(ctx: Dictionary) -> int:
		ctx["action"] = "repair"
		return BTStatus.Status.RUNNING
	))

	# Idle
	var idle_action := BTAction.new("Idle", func(ctx: Dictionary) -> int:
		ctx["action"] = "idle"
		return BTStatus.Status.SUCCESS
	)

	root.add_child(build_sequence)
	root.add_child(move_sequence)
	root.add_child(repair_sequence)
	root.add_child(idle_action)
	tree.set_root(root)
	return tree


## Create custom behavior tree from definition.
func _create_custom_tree(unit_id: int) -> UnitBehaviorTree:
	var tree := UnitBehaviorTree.new(unit_id)

	if tree_definition.is_empty():
		# Fallback to attack_or_idle
		return UnitBehaviorTree.create_attack_or_idle_tree(unit_id)

	var root := _parse_node_definition(tree_definition[0])
	tree.set_root(root)
	return tree


## Parse a node definition into a BTNode.
func _parse_node_definition(def: Dictionary) -> BTNode:
	var node_type: String = def.get("type", "action")
	var node_name: String = def.get("name", "Node")
	var children: Array = def.get("children", [])

	var node: BTNode

	match node_type:
		"selector":
			var selector := BTSelector.new(node_name)
			for child_def in children:
				selector.add_child(_parse_node_definition(child_def))
			node = selector
		"sequence":
			var sequence := BTSequence.new(node_name)
			for child_def in children:
				sequence.add_child(_parse_node_definition(child_def))
			node = sequence
		"action":
			var action_name: String = def.get("action", "idle")
			node = BTAction.new(node_name, func(ctx: Dictionary) -> int:
				ctx["action"] = action_name
				return BTStatus.Status.SUCCESS
			)
		"condition":
			var var_name: String = def.get("variable", "")
			var expected_value: Variant = def.get("value", true)
			node = BTCondition.new(node_name, func(ctx: Dictionary) -> bool:
				return ctx.get(var_name) == expected_value
			)
		"inverter":
			var inverter := BTInverter.new(node_name)
			if not children.is_empty():
				inverter.set_child(_parse_node_definition(children[0]))
			node = inverter
		_:
			node = BTAction.new(node_name)

	return node


## Create a default template for combat units.
static func create_combat_template(faction_id: int = 0) -> BehaviorTreeTemplate:
	var template := BehaviorTreeTemplate.new()
	template.template_id = "combat_default"
	template.faction_id = faction_id
	template.tree_type = "chase_attack"
	template.description = "Default combat behavior for attack units"
	template.default_blackboard_vars = {
		"attack_range": 10.0,
		"chase_range": 50.0
	}
	return template


## Create a default template for builder units.
static func create_builder_template(faction_id: int = 0) -> BehaviorTreeTemplate:
	var template := BehaviorTreeTemplate.new()
	template.template_id = "builder_default"
	template.faction_id = faction_id
	template.unit_type = "builder"
	template.tree_type = "build"
	template.description = "Default behavior for builder units"
	template.default_blackboard_vars = {
		"build_range": 5.0
	}
	return template


## Create a default template for gatherer units.
static func create_gatherer_template(faction_id: int = 0) -> BehaviorTreeTemplate:
	var template := BehaviorTreeTemplate.new()
	template.template_id = "gatherer_default"
	template.faction_id = faction_id
	template.unit_type = "gatherer"
	template.tree_type = "gather"
	template.description = "Default behavior for resource gathering units"
	template.default_blackboard_vars = {
		"gather_range": 3.0,
		"cargo_capacity": 50.0
	}
	return template
