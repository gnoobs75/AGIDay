class_name FactionTactics
extends RefCounted
## FactionTactics provides faction-specific tactical behaviors.

## Faction IDs
const FACTION_AETHER_SWARM := "aether_swarm"
const FACTION_GLACIUS := "glacius"
const FACTION_DYNAPODS := "dynapods"
const FACTION_LOGIBOTS := "logibots"
const FACTION_HUMAN_REMNANT := "human_remnant"

## Tactic implementations
var swarm_tactics: SwarmTactics = null
var tank_tactics: TankTactics = null
var dynapods_tactics: DynapodsTactics = null
var logibots_tactics: LogiBotsTactics = null
var human_tactics: HumanTactics = null


func _init() -> void:
	swarm_tactics = SwarmTactics.new()
	tank_tactics = TankTactics.new()
	dynapods_tactics = DynapodsTactics.new()
	logibots_tactics = LogiBotsTactics.new()
	human_tactics = HumanTactics.new()


## Get tactics for faction.
func get_tactics(faction_id: String) -> RefCounted:
	match faction_id:
		FACTION_AETHER_SWARM:
			return swarm_tactics
		FACTION_GLACIUS:
			return tank_tactics
		FACTION_DYNAPODS:
			return dynapods_tactics
		FACTION_LOGIBOTS:
			return logibots_tactics
		FACTION_HUMAN_REMNANT:
			return human_tactics
	return null


## Execute tactic for unit.
func execute_tactic(unit_id: int, faction_id: String, tactic: String, context: Dictionary) -> Dictionary:
	var tactics := get_tactics(faction_id)
	if tactics == null:
		return {"action": "none"}

	return tactics.execute(unit_id, tactic, context)


## Aether Swarm tactics - swarm, stealth, overwhelming numbers.
class SwarmTactics extends RefCounted:
	## Execute swarm tactic.
	func execute(unit_id: int, tactic: String, context: Dictionary) -> Dictionary:
		match tactic:
			"swarm_attack":
				return _swarm_attack(unit_id, context)
			"stealth_approach":
				return _stealth_approach(unit_id, context)
			"overwhelm":
				return _overwhelm(unit_id, context)
			"scatter":
				return _scatter(unit_id, context)
		return {"action": "none"}

	func _swarm_attack(unit_id: int, context: Dictionary) -> Dictionary:
		var target_id: int = context.get("target_id", -1)
		return {
			"action": "swarm_attack",
			"target_id": target_id,
			"coordination": "join_nearest"
		}

	func _stealth_approach(unit_id: int, context: Dictionary) -> Dictionary:
		var target_pos: Vector3 = context.get("target_position", Vector3.ZERO)
		return {
			"action": "stealth_move",
			"target": target_pos,
			"speed_mult": 0.7,
			"detection_modifier": -0.5
		}

	func _overwhelm(unit_id: int, context: Dictionary) -> Dictionary:
		var target_id: int = context.get("target_id", -1)
		return {
			"action": "coordinated_attack",
			"target_id": target_id,
			"attack_pattern": "all_sides",
			"damage_bonus": 0.5
		}

	func _scatter(unit_id: int, context: Dictionary) -> Dictionary:
		return {
			"action": "scatter",
			"direction": "random",
			"speed_mult": 1.3
		}


## Tank Faction tactics - heavy armor, AoE, siege.
class TankTactics extends RefCounted:
	func execute(unit_id: int, tactic: String, context: Dictionary) -> Dictionary:
		match tactic:
			"hold_position":
				return _hold_position(unit_id, context)
			"aoe_barrage":
				return _aoe_barrage(unit_id, context)
			"siege_mode":
				return _siege_mode(unit_id, context)
			"defensive_line":
				return _defensive_line(unit_id, context)
		return {"action": "none"}

	func _hold_position(unit_id: int, context: Dictionary) -> Dictionary:
		return {
			"action": "hold",
			"position": context.get("position", Vector3.ZERO),
			"defense_bonus": 0.3
		}

	func _aoe_barrage(unit_id: int, context: Dictionary) -> Dictionary:
		var target_pos: Vector3 = context.get("target_position", Vector3.ZERO)
		return {
			"action": "aoe_attack",
			"target": target_pos,
			"radius": 10.0,
			"ability": "artillery_barrage"
		}

	func _siege_mode(unit_id: int, context: Dictionary) -> Dictionary:
		return {
			"action": "enter_siege",
			"setup_time": 2.0,
			"damage_bonus": 0.8,
			"speed_mult": 0.0
		}

	func _defensive_line(unit_id: int, context: Dictionary) -> Dictionary:
		var facing: Vector3 = context.get("facing_direction", Vector3.FORWARD)
		return {
			"action": "formation",
			"type": "defensive_line",
			"facing": facing,
			"armor_share": true
		}


## Dynapods tactics - acrobatic movement, leg attacks.
class DynapodsTactics extends RefCounted:
	func execute(unit_id: int, tactic: String, context: Dictionary) -> Dictionary:
		match tactic:
			"acrobatic_dodge":
				return _acrobatic_dodge(unit_id, context)
			"leg_sweep":
				return _leg_sweep(unit_id, context)
			"momentum_charge":
				return _momentum_charge(unit_id, context)
			"bounce_attack":
				return _bounce_attack(unit_id, context)
		return {"action": "none"}

	func _acrobatic_dodge(unit_id: int, context: Dictionary) -> Dictionary:
		var threat_dir: Vector3 = context.get("threat_direction", Vector3.FORWARD)
		return {
			"action": "acrobatic_dodge",
			"direction": -threat_dir,
			"dodge_bonus": 0.3,
			"i_frames": 0.2
		}

	func _leg_sweep(unit_id: int, context: Dictionary) -> Dictionary:
		return {
			"action": "melee_attack",
			"ability": "leg_sweep",
			"radius": 3.0,
			"knockdown_chance": 0.4
		}

	func _momentum_charge(unit_id: int, context: Dictionary) -> Dictionary:
		var target_pos: Vector3 = context.get("target_position", Vector3.ZERO)
		return {
			"action": "charge",
			"target": target_pos,
			"speed_mult": 2.0,
			"impact_damage": 20.0
		}

	func _bounce_attack(unit_id: int, context: Dictionary) -> Dictionary:
		var targets: Array = context.get("targets", [])
		return {
			"action": "bouncing_attack",
			"targets": targets,
			"max_bounces": 3,
			"damage_falloff": 0.8
		}


## LogiBots tactics - heavy lifting, cargo, siege.
class LogiBotsTactics extends RefCounted:
	func execute(unit_id: int, tactic: String, context: Dictionary) -> Dictionary:
		match tactic:
			"synchronized_strike":
				return _synchronized_strike(unit_id, context)
			"cargo_deploy":
				return _cargo_deploy(unit_id, context)
			"siege_construct":
				return _siege_construct(unit_id, context)
			"heavy_lift":
				return _heavy_lift(unit_id, context)
		return {"action": "none"}

	func _synchronized_strike(unit_id: int, context: Dictionary) -> Dictionary:
		var target_id: int = context.get("target_id", -1)
		return {
			"action": "coordinated_attack",
			"target_id": target_id,
			"sync_delay": 0.1,
			"damage_bonus": 0.5
		}

	func _cargo_deploy(unit_id: int, context: Dictionary) -> Dictionary:
		var deploy_pos: Vector3 = context.get("position", Vector3.ZERO)
		return {
			"action": "deploy_cargo",
			"position": deploy_pos,
			"cargo_type": context.get("cargo_type", "supplies")
		}

	func _siege_construct(unit_id: int, context: Dictionary) -> Dictionary:
		return {
			"action": "construct",
			"structure": "siege_equipment",
			"build_time": 5.0
		}

	func _heavy_lift(unit_id: int, context: Dictionary) -> Dictionary:
		var object_id: int = context.get("object_id", -1)
		return {
			"action": "lift",
			"object_id": object_id,
			"speed_penalty": 0.5
		}


## Human Remnant tactics - military tactics, ambush, coordinated fire.
class HumanTactics extends RefCounted:
	func execute(unit_id: int, tactic: String, context: Dictionary) -> Dictionary:
		match tactic:
			"suppressing_fire":
				return _suppressing_fire(unit_id, context)
			"ambush":
				return _ambush(unit_id, context)
			"tactical_retreat":
				return _tactical_retreat(unit_id, context)
			"coordinated_fire":
				return _coordinated_fire(unit_id, context)
		return {"action": "none"}

	func _suppressing_fire(unit_id: int, context: Dictionary) -> Dictionary:
		var area: Vector3 = context.get("target_area", Vector3.ZERO)
		return {
			"action": "suppressing_fire",
			"target_area": area,
			"radius": 8.0,
			"suppression_value": 0.6
		}

	func _ambush(unit_id: int, context: Dictionary) -> Dictionary:
		return {
			"action": "enter_ambush",
			"stealth_bonus": 0.8,
			"first_strike_bonus": 0.5
		}

	func _tactical_retreat(unit_id: int, context: Dictionary) -> Dictionary:
		var safe_pos: Vector3 = context.get("safe_position", Vector3.ZERO)
		return {
			"action": "tactical_retreat",
			"target": safe_pos,
			"covering_fire": true,
			"speed_mult": 1.2
		}

	func _coordinated_fire(unit_id: int, context: Dictionary) -> Dictionary:
		var target_id: int = context.get("target_id", -1)
		return {
			"action": "coordinated_attack",
			"target_id": target_id,
			"timing": "simultaneous",
			"accuracy_bonus": 0.2
		}
