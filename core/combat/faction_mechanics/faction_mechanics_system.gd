class_name FactionMechanicsSystem
extends RefCounted
## FactionMechanicsSystem integrates all faction-specific combat mechanics.
## Supports 5000+ units at 30Hz with <2ms frame budget.

signal damage_modified(unit_id: int, base_damage: float, modified_damage: float, faction: String)
signal damage_received_modified(unit_id: int, incoming: float, actual: float, faction: String)

## Performance settings
const UPDATE_FREQUENCY := 30.0  ## Hz
const MAX_UPDATE_TIME_MS := 2.0

## Faction IDs
const FACTION_AETHER_SWARM := "aether_swarm"
const FACTION_GLACIUS := "glacius"
const FACTION_DYNAPODS := "dynapods"
const FACTION_LOGIBOTS := "logibots"

## Sub-systems
var swarm_synergy: SwarmSynergy = null
var armor_stacking: ArmorStacking = null
var evasion_stacking: EvasionStacking = null
var synchronized_strikes: SynchronizedStrikes = null
var adaptive_evolution: AdaptiveEvolution = null

## Unit registrations (unit_id -> faction_id)
var _unit_factions: Dictionary = {}

## Unit positions cache
var _positions_cache: Dictionary = {}

## Update timing
var _update_accumulator: float = 0.0
var _update_interval: float = 1.0 / UPDATE_FREQUENCY

## Last frame time
var _last_update_ms: float = 0.0


func _init() -> void:
	swarm_synergy = SwarmSynergy.new()
	armor_stacking = ArmorStacking.new()
	evasion_stacking = EvasionStacking.new()
	synchronized_strikes = SynchronizedStrikes.new()
	adaptive_evolution = AdaptiveEvolution.new()


## Register unit with faction.
func register_unit(unit_id: int, faction_id: String, base_armor: float = 0.0) -> void:
	_unit_factions[unit_id] = faction_id

	match faction_id:
		FACTION_AETHER_SWARM:
			swarm_synergy.register_unit(unit_id)
		FACTION_GLACIUS:
			armor_stacking.register_unit(unit_id, base_armor)
			adaptive_evolution.register_unit(unit_id)  # OptiForge learns from deaths
		FACTION_DYNAPODS:
			evasion_stacking.register_unit(unit_id)
		FACTION_LOGIBOTS:
			synchronized_strikes.register_unit(unit_id)


## Unregister unit.
func unregister_unit(unit_id: int) -> void:
	var faction_id: String = _unit_factions.get(unit_id, "")
	_unit_factions.erase(unit_id)
	_positions_cache.erase(unit_id)

	match faction_id:
		FACTION_AETHER_SWARM:
			swarm_synergy.unregister_unit(unit_id)
		FACTION_GLACIUS:
			armor_stacking.unregister_unit(unit_id)
			adaptive_evolution.unregister_unit(unit_id)
		FACTION_DYNAPODS:
			evasion_stacking.unregister_unit(unit_id)
		FACTION_LOGIBOTS:
			synchronized_strikes.unregister_unit(unit_id)


## Record a unit death for adaptive evolution learning.
## Call this when an OptiForge (glacius) unit is killed.
func record_death(unit_id: int, attacker_faction: String) -> void:
	var faction_id: String = _unit_factions.get(unit_id, "")
	if faction_id == FACTION_GLACIUS:
		adaptive_evolution.record_death(attacker_faction)


## Update unit position.
func update_position(unit_id: int, position: Vector3) -> void:
	_positions_cache[unit_id] = position


## Update all positions at once.
func update_positions(positions: Dictionary) -> void:
	for unit_id in positions:
		_positions_cache[unit_id] = positions[unit_id]


## Set attack target for unit.
func set_attack_target(unit_id: int, target_id: int) -> void:
	var faction_id: String = _unit_factions.get(unit_id, "")
	if faction_id == FACTION_LOGIBOTS:
		synchronized_strikes.set_attack_target(unit_id, target_id)


## Clear attack target for unit.
func clear_attack_target(unit_id: int) -> void:
	var faction_id: String = _unit_factions.get(unit_id, "")
	if faction_id == FACTION_LOGIBOTS:
		synchronized_strikes.clear_attack_target(unit_id)


## Update system (called each frame).
func update(delta: float) -> void:
	_update_accumulator += delta

	if _update_accumulator >= _update_interval:
		_update_accumulator -= _update_interval
		_process_update()


## Process faction mechanics update.
func _process_update() -> void:
	var start_time := Time.get_ticks_usec()

	# Group positions by faction
	var aether_positions: Dictionary = {}
	var glacius_positions: Dictionary = {}
	var dynapods_positions: Dictionary = {}
	var logibots_positions: Dictionary = {}

	for unit_id in _unit_factions:
		if not _positions_cache.has(unit_id):
			continue

		var faction_id: String = _unit_factions[unit_id]
		var pos: Vector3 = _positions_cache[unit_id]

		match faction_id:
			FACTION_AETHER_SWARM:
				aether_positions[unit_id] = pos
			FACTION_GLACIUS:
				glacius_positions[unit_id] = pos
			FACTION_DYNAPODS:
				dynapods_positions[unit_id] = pos
			FACTION_LOGIBOTS:
				logibots_positions[unit_id] = pos

	# Update each system
	swarm_synergy.update(aether_positions)

	var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
	if elapsed < MAX_UPDATE_TIME_MS:
		armor_stacking.update(glacius_positions)

	elapsed = (Time.get_ticks_usec() - start_time) / 1000.0
	if elapsed < MAX_UPDATE_TIME_MS:
		evasion_stacking.update(dynapods_positions)

	elapsed = (Time.get_ticks_usec() - start_time) / 1000.0
	if elapsed < MAX_UPDATE_TIME_MS:
		synchronized_strikes.update(logibots_positions)

	_last_update_ms = (Time.get_ticks_usec() - start_time) / 1000.0


## Calculate outgoing damage with faction bonuses.
func calculate_outgoing_damage(unit_id: int, base_damage: float) -> float:
	var faction_id: String = _unit_factions.get(unit_id, "")
	var modified := base_damage

	match faction_id:
		FACTION_AETHER_SWARM:
			modified = swarm_synergy.apply_to_damage(unit_id, base_damage)
		FACTION_LOGIBOTS:
			modified = synchronized_strikes.apply_to_damage(unit_id, base_damage)

	if absf(modified - base_damage) > 0.01:
		damage_modified.emit(unit_id, base_damage, modified, faction_id)

	return modified


## Calculate incoming damage with faction mechanics.
## attacker_faction is optional, used for adaptive evolution learning.
func calculate_incoming_damage(unit_id: int, incoming_damage: float, attacker_faction: String = "") -> Dictionary:
	var faction_id: String = _unit_factions.get(unit_id, "")
	var result: Dictionary = {
		"damage": incoming_damage,
		"dodged": false,
		"distributed": {},
		"evolution_reduction": 0.0
	}

	match faction_id:
		FACTION_GLACIUS:
			# Apply adaptive evolution resistance first (learned from past deaths)
			var evolved_damage := incoming_damage
			if not attacker_faction.is_empty():
				evolved_damage = adaptive_evolution.apply_to_incoming_damage(unit_id, attacker_faction, incoming_damage)
				result["evolution_reduction"] = incoming_damage - evolved_damage

			# Then apply armor stacking
			var armor_result := armor_stacking.process_damage(unit_id, evolved_damage)
			result["damage"] = armor_result["primary_damage"]
			result["distributed"] = armor_result["distributed"]

		FACTION_DYNAPODS:
			var dodge_result := evasion_stacking.roll_dodge(unit_id, incoming_damage)
			result["damage"] = dodge_result["damage"]
			result["dodged"] = dodge_result["dodged"]

	if result["damage"] != incoming_damage:
		damage_received_modified.emit(unit_id, incoming_damage, result["damage"], faction_id)

	return result


## Get faction bonus info for unit.
func get_bonus_info(unit_id: int) -> Dictionary:
	var faction_id: String = _unit_factions.get(unit_id, "")
	var info: Dictionary = {
		"faction": faction_id,
		"bonus_type": "",
		"bonus_value": 0.0,
		"extra": {}
	}

	match faction_id:
		FACTION_AETHER_SWARM:
			info["bonus_type"] = "swarm_synergy"
			info["bonus_value"] = swarm_synergy.get_synergy_bonus(unit_id)
			info["extra"]["nearby_count"] = swarm_synergy.get_nearby_count(unit_id)

		FACTION_GLACIUS:
			info["bonus_type"] = "armor_stacking"
			info["bonus_value"] = armor_stacking.get_effective_armor(unit_id)

		FACTION_DYNAPODS:
			info["bonus_type"] = "evasion_stacking"
			info["bonus_value"] = evasion_stacking.get_evasion_chance(unit_id)
			info["extra"] = evasion_stacking.get_dodge_stats(unit_id)

		FACTION_LOGIBOTS:
			info["bonus_type"] = "synchronized_strikes"
			info["bonus_value"] = synchronized_strikes.get_sync_bonus(unit_id)
			info["extra"]["synced_count"] = synchronized_strikes.get_synced_count(unit_id)

	return info


## Get unit faction.
func get_unit_faction(unit_id: int) -> String:
	return _unit_factions.get(unit_id, "")


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var factions_data: Dictionary = {}
	for unit_id in _unit_factions:
		factions_data[str(unit_id)] = _unit_factions[unit_id]

	return {
		"unit_factions": factions_data,
		"swarm_synergy": swarm_synergy.to_dict(),
		"armor_stacking": armor_stacking.to_dict(),
		"evasion_stacking": evasion_stacking.to_dict(),
		"synchronized_strikes": synchronized_strikes.to_dict(),
		"adaptive_evolution": adaptive_evolution.to_dict()
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	_unit_factions.clear()
	for unit_id_str in data.get("unit_factions", {}):
		_unit_factions[int(unit_id_str)] = data["unit_factions"][unit_id_str]

	swarm_synergy.from_dict(data.get("swarm_synergy", {}))
	armor_stacking.from_dict(data.get("armor_stacking", {}))
	evasion_stacking.from_dict(data.get("evasion_stacking", {}))
	synchronized_strikes.from_dict(data.get("synchronized_strikes", {}))
	adaptive_evolution.from_dict(data.get("adaptive_evolution", {}))


## Get summary for debugging.
func get_summary() -> Dictionary:
	var faction_counts: Dictionary = {}
	for unit_id in _unit_factions:
		var faction: String = _unit_factions[unit_id]
		faction_counts[faction] = faction_counts.get(faction, 0) + 1

	return {
		"total_units": _unit_factions.size(),
		"faction_counts": faction_counts,
		"last_update_ms": "%.2fms" % _last_update_ms,
		"swarm_synergy": swarm_synergy.get_summary(),
		"armor_stacking": armor_stacking.get_summary(),
		"evasion_stacking": evasion_stacking.get_summary(),
		"synchronized_strikes": synchronized_strikes.get_summary(),
		"adaptive_evolution": adaptive_evolution.get_summary()
	}
