class_name UnitBehaviorPatterns
extends RefCounted
## UnitBehaviorPatterns provides factory methods for creating common behavior patterns.
## These patterns can be combined and reused across different unit types.


## Create idle behavior pattern.
## Pattern: find target → move to target, fallback to patrol
static func create_idle_pattern() -> BTSelector:
	var root := BTSelector.new("IdleBehavior")

	# Try to find and pursue a target
	var pursue_sequence := BTSequence.new("PursueTarget")
	pursue_sequence.add_child(BTFindTarget.new())
	pursue_sequence.add_child(BTMoveToTarget.new())
	root.add_child(pursue_sequence)

	# Fallback to patrol
	root.add_child(BTPatrol.new())

	return root


## Create combat behavior pattern.
## Pattern: find target → (dodge if needed OR attack if in range OR move to target)
static func create_combat_pattern() -> BTSelector:
	var root := BTSelector.new("CombatBehavior")

	# First, ensure we have a target
	var combat_sequence := BTSequence.new("CombatSequence")
	combat_sequence.add_child(BTFindTarget.new())

	# Combat choices
	var combat_choices := BTSelector.new("CombatChoices")

	# Option 1: Dodge if needed
	var dodge_sequence := BTSequence.new("DodgeSequence")
	dodge_sequence.add_child(BTShouldDodge.new())
	dodge_sequence.add_child(BTDodge.new())
	combat_choices.add_child(dodge_sequence)

	# Option 2: Attack if in range
	var attack_sequence := BTSequence.new("AttackSequence")
	attack_sequence.add_child(BTInAttackRange.new())
	attack_sequence.add_child(BTAttack.new())
	combat_choices.add_child(attack_sequence)

	# Option 3: Move to target
	combat_choices.add_child(BTMoveToTarget.new())

	combat_sequence.add_child(combat_choices)
	root.add_child(combat_sequence)

	# Fallback to idle if no target
	root.add_child(BTAction.new("Idle", func(ctx: Dictionary) -> int:
		ctx["action"] = "idle"
		return BTStatus.Status.SUCCESS
	))

	return root


## Create flee behavior pattern.
## Pattern: if health critical → find nearest ally → move to ally, otherwise continue combat
static func create_flee_pattern() -> BTSelector:
	var root := BTSelector.new("FleeBehavior")

	# Flee sequence: health critical → find ally → move to ally
	var flee_sequence := BTSequence.new("FleeSequence")
	flee_sequence.add_child(BTHealthCritical.new())
	flee_sequence.add_child(BTFindAlly.new())
	flee_sequence.add_child(BTMoveToAlly.new())
	root.add_child(flee_sequence)

	# Alternative flee: health critical but no ally → flee from threat
	var emergency_flee := BTSequence.new("EmergencyFlee")
	emergency_flee.add_child(BTHealthCritical.new())
	emergency_flee.add_child(BTFlee.new())
	root.add_child(emergency_flee)

	# Otherwise continue combat
	root.add_child(create_combat_pattern())

	return root


## Create full unit behavior combining flee, combat, and idle.
## This is the main behavior tree for standard combat units.
static func create_standard_unit_behavior() -> BTSelector:
	var root := BTSelector.new("StandardUnitBehavior")

	# Priority 1: Flee if health critical
	var flee_check := BTSequence.new("FleeCheck")
	flee_check.add_child(BTHealthCritical.new())

	var flee_choices := BTSelector.new("FleeChoices")
	# Try to flee to ally
	var flee_to_ally := BTSequence.new("FleeToAlly")
	flee_to_ally.add_child(BTFindAlly.new())
	flee_to_ally.add_child(BTMoveToAlly.new())
	flee_choices.add_child(flee_to_ally)
	# Fallback: flee from threat
	flee_choices.add_child(BTFlee.new())

	flee_check.add_child(flee_choices)
	root.add_child(flee_check)

	# Priority 2: Combat if enemy nearby
	var combat_check := BTSequence.new("CombatCheck")
	combat_check.add_child(BTEnemyNearby.new())
	combat_check.add_child(create_combat_pattern())
	root.add_child(combat_check)

	# Priority 3: Idle behavior (patrol or pursue distant targets)
	root.add_child(create_idle_pattern())

	return root


## Create aggressive unit behavior (never flees).
static func create_aggressive_behavior() -> BTSelector:
	var root := BTSelector.new("AggressiveBehavior")

	# Combat if enemy nearby
	var combat_check := BTSequence.new("CombatCheck")
	combat_check.add_child(BTEnemyNearby.new())
	combat_check.add_child(create_combat_pattern())
	root.add_child(combat_check)

	# Idle/patrol otherwise
	root.add_child(create_idle_pattern())

	return root


## Create defensive unit behavior (prioritizes holding position).
static func create_defensive_behavior() -> BTSelector:
	var root := BTSelector.new("DefensiveBehavior")

	# Priority 1: Flee if health critical
	var flee_check := BTSequence.new("FleeCheck")
	flee_check.add_child(BTHealthCritical.new())
	flee_check.add_child(BTFlee.new())
	root.add_child(flee_check)

	# Priority 2: Attack enemies in range (don't pursue)
	var defend_sequence := BTSequence.new("DefendSequence")
	defend_sequence.add_child(BTHasTarget.new())
	defend_sequence.add_child(BTInAttackRange.new())

	var defend_choices := BTSelector.new("DefendChoices")
	# Dodge if needed
	var dodge_seq := BTSequence.new("DodgeSeq")
	dodge_seq.add_child(BTShouldDodge.new())
	dodge_seq.add_child(BTDodge.new())
	defend_choices.add_child(dodge_seq)
	# Attack
	defend_choices.add_child(BTAttack.new())

	defend_sequence.add_child(defend_choices)
	root.add_child(defend_sequence)

	# Priority 3: Hold position (don't patrol)
	root.add_child(BTAction.new("Hold", func(ctx: Dictionary) -> int:
		ctx["action"] = "hold"
		return BTStatus.Status.SUCCESS
	))

	return root


## Create support unit behavior (stays near allies, avoids combat).
static func create_support_behavior() -> BTSelector:
	var root := BTSelector.new("SupportBehavior")

	# Priority 1: Flee if any enemy nearby
	var flee_check := BTSequence.new("FleeFromEnemy")
	flee_check.add_child(BTEnemyNearby.new())
	var flee_choices := BTSelector.new("FleeChoices")
	var flee_to_ally := BTSequence.new("FleeToAlly")
	flee_to_ally.add_child(BTFindAlly.new())
	flee_to_ally.add_child(BTMoveToAlly.new())
	flee_choices.add_child(flee_to_ally)
	flee_choices.add_child(BTFlee.new())
	flee_check.add_child(flee_choices)
	root.add_child(flee_check)

	# Priority 2: Stay near allies
	var stay_near_ally := BTSequence.new("StayNearAlly")
	stay_near_ally.add_child(BTFindAlly.new())
	stay_near_ally.add_child(BTMoveToAlly.new())
	root.add_child(stay_near_ally)

	# Fallback: idle
	root.add_child(BTAction.new("Idle", func(ctx: Dictionary) -> int:
		ctx["action"] = "idle"
		return BTStatus.Status.SUCCESS
	))

	return root


## Create a UnitBehaviorTree from a behavior pattern.
static func create_tree_from_pattern(unit_id: int, pattern: BTNode) -> UnitBehaviorTree:
	var tree := UnitBehaviorTree.new(unit_id)
	tree.set_root(pattern)
	return tree


## Create standard unit tree.
static func create_standard_tree(unit_id: int) -> UnitBehaviorTree:
	return create_tree_from_pattern(unit_id, create_standard_unit_behavior())


## Create aggressive unit tree.
static func create_aggressive_tree(unit_id: int) -> UnitBehaviorTree:
	return create_tree_from_pattern(unit_id, create_aggressive_behavior())


## Create defensive unit tree.
static func create_defensive_tree(unit_id: int) -> UnitBehaviorTree:
	return create_tree_from_pattern(unit_id, create_defensive_behavior())


## Create support unit tree.
static func create_support_tree(unit_id: int) -> UnitBehaviorTree:
	return create_tree_from_pattern(unit_id, create_support_behavior())
