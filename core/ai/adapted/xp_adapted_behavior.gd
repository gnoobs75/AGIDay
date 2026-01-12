class_name XPAdaptedBehavior
extends RefCounted
## XPAdaptedBehavior modifies behavior trees based on faction experience buffs.
## Integrates with faction progression to unlock advanced tactics.

signal behavior_modified(unit_id: int, modification: String)
signal advanced_tactic_unlocked(faction_id: String, tactic: String)

## Buff thresholds for behavior unlocks
const DODGE_THRESHOLD := 500.0  ## Combat XP for dodge behaviors
const FLANK_THRESHOLD := 1500.0  ## Combat XP for flanking tactics
const COORDINATED_THRESHOLD := 3000.0  ## Combat XP for coordinated assault

## Buff types
enum Buff {
	DODGE_CHANCE,
	FLANKING_TACTICS,
	COORDINATED_ASSAULT
}

## Reference to faction progression
var _faction_learning: FactionLearning = null

## Cached behavior modifiers per faction (faction_id -> modifications)
var _faction_modifiers: Dictionary = {}

## Units with modified behaviors (unit_id -> modifications applied)
var _modified_units: Dictionary = {}


func _init() -> void:
	pass


## Set faction learning reference.
func set_faction_learning(learning: FactionLearning) -> void:
	_faction_learning = learning


## Get behavior tree for unit with XP adaptations.
func get_behavior_tree_for_unit(unit_id: int, faction_id: String, base_tree: LimboAIWrapper.BTNode) -> LimboAIWrapper.BTNode:
	# Get or update faction modifiers
	var modifiers := _get_faction_modifiers(faction_id)

	if modifiers.is_empty():
		return base_tree

	# Clone base tree and add modifications
	var adapted_tree := _clone_and_adapt(base_tree, modifiers)

	_modified_units[unit_id] = modifiers.duplicate()

	return adapted_tree


## Get faction modifiers based on XP.
func _get_faction_modifiers(faction_id: String) -> Dictionary:
	if not _faction_learning:
		return {}

	var combat_xp := _faction_learning.get_category_xp(faction_id, FactionLearning.Category.COMBAT)

	var modifiers: Dictionary = {}

	if combat_xp >= DODGE_THRESHOLD:
		modifiers[Buff.DODGE_CHANCE] = true

	if combat_xp >= FLANK_THRESHOLD:
		modifiers[Buff.FLANKING_TACTICS] = true

	if combat_xp >= COORDINATED_THRESHOLD:
		modifiers[Buff.COORDINATED_ASSAULT] = true

	# Check for newly unlocked tactics
	if not _faction_modifiers.has(faction_id):
		_faction_modifiers[faction_id] = {}

	var old_mods: Dictionary = _faction_modifiers[faction_id]

	for buff in modifiers:
		if not old_mods.has(buff):
			var tactic_name := _get_tactic_name(buff)
			advanced_tactic_unlocked.emit(faction_id, tactic_name)

	_faction_modifiers[faction_id] = modifiers

	return modifiers


## Clone and adapt behavior tree.
func _clone_and_adapt(base_tree: LimboAIWrapper.BTNode, modifiers: Dictionary) -> LimboAIWrapper.BTNode:
	# For now, return base tree with modifications noted
	# In full implementation, would clone tree structure and insert new nodes

	if modifiers.has(Buff.DODGE_CHANCE):
		add_dodge_behavior(base_tree)

	if modifiers.has(Buff.FLANKING_TACTICS):
		add_flanking_behavior(base_tree)

	if modifiers.has(Buff.COORDINATED_ASSAULT):
		add_coordinated_assault_behavior(base_tree)

	return base_tree


## Add dodge behavior nodes to tree.
func add_dodge_behavior(tree: LimboAIWrapper.BTNode) -> void:
	# Create dodge sequence
	var dodge_sequence := LimboAIWrapper.create_sequence("xp_dodge")
	dodge_sequence.add_child(LimboAIWrapper.create_condition("incoming_attack", _check_incoming_attack))
	dodge_sequence.add_child(LimboAIWrapper.create_action("execute_dodge", _action_execute_dodge))

	# Insert at high priority (would need tree structure access)
	# For now, behavior is tracked but actual insertion depends on tree structure


## Add flanking behavior nodes to tree.
func add_flanking_behavior(tree: LimboAIWrapper.BTNode) -> void:
	var flank_sequence := LimboAIWrapper.create_sequence("xp_flank")
	flank_sequence.add_child(LimboAIWrapper.create_condition("can_flank", _check_can_flank))
	flank_sequence.add_child(LimboAIWrapper.create_action("execute_flank", _action_execute_flank))


## Add coordinated assault behavior nodes to tree.
func add_coordinated_assault_behavior(tree: LimboAIWrapper.BTNode) -> void:
	var coord_sequence := LimboAIWrapper.create_sequence("xp_coordinated")
	coord_sequence.add_child(LimboAIWrapper.create_condition("allies_ready", _check_allies_ready))
	coord_sequence.add_child(LimboAIWrapper.create_action("coordinated_attack", _action_coordinated_attack))


## Get tactic name for buff.
func _get_tactic_name(buff: int) -> String:
	match buff:
		Buff.DODGE_CHANCE:
			return "dodge"
		Buff.FLANKING_TACTICS:
			return "flanking"
		Buff.COORDINATED_ASSAULT:
			return "coordinated_assault"
	return "unknown"


## Check if unit has behavior modification.
func has_modification(unit_id: int, buff: int) -> bool:
	if not _modified_units.has(unit_id):
		return false
	return _modified_units[unit_id].has(buff)


## Remove unit modifications.
func remove_unit(unit_id: int) -> void:
	_modified_units.erase(unit_id)


## Condition: Check for incoming attack.
func _check_incoming_attack(blackboard: Dictionary) -> bool:
	# Would check for projectiles or attacks targeting this unit
	return blackboard.get("incoming_threat", false)


## Condition: Check if flanking is possible.
func _check_can_flank(blackboard: Dictionary) -> bool:
	var target_id: int = blackboard.get("target_id", -1)
	if target_id == -1:
		return false

	# Check if allies are engaging from other directions
	var allies_attacking: Array = blackboard.get("allies_attacking_target", [])
	return allies_attacking.size() >= 1


## Condition: Check if allies ready for coordinated assault.
func _check_allies_ready(blackboard: Dictionary) -> bool:
	var coordinated_allies: Array = blackboard.get("coordinated_allies", [])
	return coordinated_allies.size() >= 2


## Action: Execute dodge.
func _action_execute_dodge(blackboard: Dictionary) -> int:
	blackboard["last_action"] = "xp_dodge"
	return LimboAIWrapper.BTStatus.SUCCESS


## Action: Execute flank.
func _action_execute_flank(blackboard: Dictionary) -> int:
	blackboard["last_action"] = "xp_flank"
	return LimboAIWrapper.BTStatus.SUCCESS


## Action: Coordinated attack.
func _action_coordinated_attack(blackboard: Dictionary) -> int:
	blackboard["last_action"] = "xp_coordinated_attack"
	return LimboAIWrapper.BTStatus.SUCCESS


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_stats: Dictionary = {}

	for faction_id in _faction_modifiers:
		var mods: Dictionary = _faction_modifiers[faction_id]
		faction_stats[faction_id] = {
			"has_dodge": mods.has(Buff.DODGE_CHANCE),
			"has_flanking": mods.has(Buff.FLANKING_TACTICS),
			"has_coordinated": mods.has(Buff.COORDINATED_ASSAULT)
		}

	return {
		"factions_tracked": _faction_modifiers.size(),
		"units_modified": _modified_units.size(),
		"faction_modifiers": faction_stats
	}
