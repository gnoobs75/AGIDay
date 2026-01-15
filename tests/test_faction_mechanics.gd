extends SceneTree
## Faction Mechanics Test Suite
## Tests all faction ability subsystems and their integration.
## Run with: godot --headless --path "c:\Claude\AGIDay" --script tests/test_faction_mechanics.gd

var _test_count: int = 0
var _pass_count: int = 0
var _fail_count: int = 0
var _output_log: Array = []  # Capture output for verification


func _init() -> void:
	print("=" .repeat(60))
	print("FACTION MECHANICS TEST SUITE")
	print("=" .repeat(60))

	run_all_tests()
	quit()


func run_all_tests() -> void:
	print("\n[SWARM SYNERGY TESTS]")
	_test_swarm_synergy()

	print("\n[ARMOR STACKING TESTS]")
	_test_armor_stacking()

	print("\n[EVASION STACKING TESTS]")
	_test_evasion_stacking()

	print("\n[SYNCHRONIZED STRIKES TESTS]")
	_test_synchronized_strikes()

	print("\n[ADAPTIVE EVOLUTION TESTS]")
	_test_adaptive_evolution()

	print("\n[FACTION MECHANICS SYSTEM INTEGRATION TESTS]")
	_test_faction_mechanics_integration()

	print("\n[OUTPUT VERIFICATION TESTS]")
	_test_output_verification()

	print("\n[PHASE SHIFT ABILITY TESTS]")
	_test_phase_shift_ability()

	print("\n[COMBAT FLOW SIMULATION TESTS]")
	_test_combat_flow_simulation()

	print("\n[OVERCLOCK UNIT ABILITY TESTS]")
	_test_overclock_unit_ability()

	print("\n[SIEGE FORMATION ABILITY TESTS]")
	_test_siege_formation_ability()

	print("\n[NANO REPLICATION ABILITY TESTS]")
	_test_nano_replication_ability()

	print("\n[ETHER CLOAK ABILITY TESTS]")
	_test_ether_cloak_ability()

	print("\n[TERRAIN MASTERY ABILITY TESTS]")
	_test_terrain_mastery_ability()

	print("\n[COORDINATED BARRAGE ABILITY TESTS]")
	_test_coordinated_barrage_ability()

	print("\n[FRACTAL MOVEMENT ABILITY TESTS]")
	_test_fractal_movement_ability()

	print("\n[MASS PRODUCTION ABILITY TESTS]")
	_test_mass_production_ability()

	print("\n[ACROBATIC STRIKE ABILITY TESTS]")
	_test_acrobatic_strike_ability()

	_print_results()


func _print_results() -> void:
	print("\n" + "=" .repeat(60))
	print("TEST RESULTS")
	print("=" .repeat(60))
	print("Total: %d | Passed: %d | Failed: %d" % [_test_count, _pass_count, _fail_count])

	if _fail_count == 0:
		print("STATUS: ALL TESTS PASSED")
	else:
		print("STATUS: %d TESTS FAILED" % _fail_count)


# =============================================================================
# Test Helpers
# =============================================================================

func _assert(condition: bool, test_name: String) -> void:
	_test_count += 1
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % test_name)
	else:
		_fail_count += 1
		print("  [FAIL] %s" % test_name)


func _assert_eq(actual, expected, test_name: String) -> void:
	_assert(actual == expected, "%s (expected: %s, got: %s)" % [test_name, str(expected), str(actual)])


func _assert_ne(actual, not_expected, test_name: String) -> void:
	_assert(actual != not_expected, "%s (should not be: %s)" % [test_name, str(not_expected)])


func _assert_approx(actual: float, expected: float, tolerance: float, test_name: String) -> void:
	var diff := absf(actual - expected)
	_assert(diff <= tolerance, "%s (expected: %.4f, got: %.4f, tolerance: %.4f)" % [test_name, expected, actual, tolerance])


func _assert_gt(actual: float, threshold: float, test_name: String) -> void:
	_assert(actual > threshold, "%s (expected > %.4f, got: %.4f)" % [test_name, threshold, actual])


func _assert_lt(actual: float, threshold: float, test_name: String) -> void:
	_assert(actual < threshold, "%s (expected < %.4f, got: %.4f)" % [test_name, threshold, actual])


func _log_output(message: String) -> void:
	_output_log.append(message)
	print("    [LOG] %s" % message)


func _clear_output_log() -> void:
	_output_log.clear()


func _output_contains(substring: String) -> bool:
	for entry in _output_log:
		if substring in entry:
			return true
	return false


# =============================================================================
# SWARM SYNERGY TESTS
# =============================================================================

func _test_swarm_synergy() -> void:
	var synergy := SwarmSynergy.new()

	# Test registration
	synergy.register_unit(1)
	synergy.register_unit(2)
	synergy.register_unit(3)
	_assert_eq(synergy.get_synergy_bonus(1), 0.0, "Initial synergy bonus is 0")
	_assert_eq(synergy.get_nearby_count(1), 0, "Initial nearby count is 0")

	# Test synergy calculation with nearby units
	var positions := {
		1: Vector3(0, 0, 0),
		2: Vector3(5, 0, 0),   # Within 10m radius
		3: Vector3(8, 0, 0),   # Within 10m radius
	}
	synergy.update(positions)

	_assert_eq(synergy.get_nearby_count(1), 2, "Unit 1 has 2 nearby allies")
	_assert_approx(synergy.get_synergy_bonus(1), 0.02, 0.001, "Synergy bonus is 2% (1% per ally)")

	# Test damage application
	var base_damage := 100.0
	var modified_damage := synergy.apply_to_damage(1, base_damage)
	_assert_approx(modified_damage, 102.0, 0.1, "Damage increased by 2%")

	# Test max bonus cap (50 allies = 50% max)
	for i in range(4, 60):
		synergy.register_unit(i)
		positions[i] = Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))

	synergy.update(positions)
	var max_bonus := synergy.get_synergy_bonus(1)
	_assert_lt(max_bonus, 0.51, "Synergy bonus capped at 50%")

	# Test unregistration
	synergy.unregister_unit(1)
	_assert_eq(synergy.get_synergy_bonus(1), 0.0, "Bonus is 0 after unregistration")

	# Test serialization
	var data := synergy.to_dict()
	_assert(data.has("unit_synergy"), "Serialization includes unit_synergy")

	var synergy2 := SwarmSynergy.new()
	synergy2.from_dict(data)
	_assert_eq(synergy2.get_nearby_count(2), synergy.get_nearby_count(2), "Deserialized nearby count matches")


# =============================================================================
# ARMOR STACKING TESTS
# =============================================================================

func _test_armor_stacking() -> void:
	var armor := ArmorStacking.new()

	# Test registration with base armor
	armor.register_unit(1, 0.2)  # 20% base armor
	armor.register_unit(2, 0.15)
	armor.register_unit(3, 0.1)

	_assert_approx(armor.get_effective_armor(1), 0.2, 0.01, "Initial effective armor equals base armor")

	# Test armor stacking with nearby allies
	var positions := {
		1: Vector3(0, 0, 0),
		2: Vector3(3, 0, 0),   # Close enough for stacking
		3: Vector3(4, 0, 0),
	}
	armor.update(positions)

	var effective := armor.get_effective_armor(1)
	_assert_gt(effective, 0.2, "Effective armor increased with nearby allies")

	# Test damage distribution
	var result := armor.process_damage(1, 100.0)
	_assert(result.has("primary_damage"), "Result includes primary_damage")
	_assert(result.has("distributed"), "Result includes distributed damage")
	_assert_lt(result["primary_damage"], 100.0, "Primary damage reduced")

	# Test serialization
	var data := armor.to_dict()
	_assert(data.has("unit_armor"), "Serialization includes unit_armor")

	var armor2 := ArmorStacking.new()
	armor2.from_dict(data)
	_assert_approx(armor2.get_effective_armor(1), armor.get_effective_armor(1), 0.01, "Deserialized armor matches")


# =============================================================================
# EVASION STACKING TESTS
# =============================================================================

func _test_evasion_stacking() -> void:
	var evasion := EvasionStacking.new()

	# Test registration
	evasion.register_unit(1)
	evasion.register_unit(2)
	evasion.register_unit(3)
	evasion.register_unit(4)
	evasion.register_unit(5)

	_assert_approx(evasion.get_evasion_chance(1), 0.0, 0.01, "Initial evasion chance is 0 (no nearby allies)")

	# Position units close together to build evasion (2% per nearby ally)
	var positions := {
		1: Vector3(0, 0, 0),
		2: Vector3(3, 0, 0),   # Within 7m radius (3m away)
		3: Vector3(0, 0, 4),   # Within 7m radius (4m away)
		4: Vector3(4, 0, 4),   # Within 7m radius (~5.6m away)
		5: Vector3(50, 0, 50), # Far away, not counted
	}
	evasion.update(positions)

	var evasion_chance := evasion.get_evasion_chance(1)
	_assert_approx(evasion_chance, 0.06, 0.01, "Evasion chance is 6% with 3 nearby allies (2% each)")

	# Test dodge roll
	var dodge_result := evasion.roll_dodge(1, 100.0)
	_assert(dodge_result.has("damage"), "Dodge result includes damage")
	_assert(dodge_result.has("dodged"), "Dodge result includes dodged flag")

	# Test dodge stats
	var stats := evasion.get_dodge_stats(1)
	_assert(stats.has("dodges"), "Stats include dodges")
	_assert(stats.has("hits"), "Stats include hits")
	_assert(stats.has("rate"), "Stats include rate")

	# Test max evasion cap (40% at 20 allies)
	for i in range(6, 30):
		evasion.register_unit(i)
		positions[i] = Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	evasion.update(positions)

	var max_evasion := evasion.get_evasion_chance(1)
	_assert_lt(max_evasion, 0.41, "Evasion capped at 40%")

	# Test serialization
	var data := evasion.to_dict()
	_assert(data.has("unit_evasion"), "Serialization includes unit_evasion")


# =============================================================================
# SYNCHRONIZED STRIKES TESTS
# =============================================================================

func _test_synchronized_strikes() -> void:
	var sync := SynchronizedStrikes.new()

	# Test registration
	sync.register_unit(1)
	sync.register_unit(2)
	sync.register_unit(3)

	_assert_eq(sync.get_sync_bonus(1), 0.0, "Initial sync bonus is 0")

	# Test target assignment
	sync.set_attack_target(1, 100)  # All targeting enemy 100
	sync.set_attack_target(2, 100)
	sync.set_attack_target(3, 100)

	var positions := {
		1: Vector3(0, 0, 0),
		2: Vector3(5, 0, 0),
		3: Vector3(3, 0, 3),
	}
	sync.update(positions)

	var synced_count := sync.get_synced_count(1)
	_assert_gt(synced_count, 0, "Synced count > 0 when multiple units target same enemy")

	var bonus := sync.get_sync_bonus(1)
	_assert_gt(bonus, 0.0, "Sync bonus > 0 when synchronized")

	# Test damage application
	var base_damage := 100.0
	var modified := sync.apply_to_damage(1, base_damage)
	_assert_gt(modified, base_damage, "Damage increased with sync bonus")

	# Test target clearing
	sync.clear_attack_target(1)
	sync.update(positions)
	_assert_eq(sync.get_synced_count(1), 0, "Synced count is 0 after clearing target")

	# Test serialization
	var data := sync.to_dict()
	_assert(data.has("unit_sync"), "Serialization includes unit_sync")


# =============================================================================
# ADAPTIVE EVOLUTION TESTS
# =============================================================================

func _test_adaptive_evolution() -> void:
	var evolution := AdaptiveEvolution.new()

	# Test registration
	evolution.register_unit(1)
	evolution.register_unit(2)

	_assert_eq(evolution.get_resistance("aether_swarm"), 0.0, "Initial resistance is 0")
	_assert_eq(evolution.get_total_deaths(), 0, "Initial death count is 0")

	# Test learning from deaths
	evolution.record_death("aether_swarm")
	_assert_eq(evolution.get_death_count("aether_swarm"), 1, "Death count incremented")
	_assert_approx(evolution.get_resistance("aether_swarm"), 0.02, 0.001, "Resistance is 2% after 1 death")

	# Test resistance accumulation
	for i in range(9):  # 10 more deaths
		evolution.record_death("aether_swarm")

	_assert_approx(evolution.get_resistance("aether_swarm"), 0.20, 0.001, "Resistance is 20% after 10 deaths")

	# Test max resistance cap (30% per faction)
	for i in range(10):
		evolution.record_death("aether_swarm")

	_assert_lt(evolution.get_resistance("aether_swarm"), 0.31, "Resistance capped at 30%")

	# Test damage reduction application
	var base_damage := 100.0
	var reduced := evolution.apply_to_incoming_damage(1, "aether_swarm", base_damage)
	_assert_lt(reduced, base_damage, "Damage reduced against learned threat")
	_log_output("AdaptiveEvolution: %.1f damage reduced to %.1f (%.1f%% resistance)" % [
		base_damage, reduced, evolution.get_resistance("aether_swarm") * 100
	])

	# Test multiple faction learning
	evolution.record_death("dynapods")
	evolution.record_death("dynapods")
	_assert_approx(evolution.get_resistance("dynapods"), 0.04, 0.001, "Learned resistance against second faction")

	# Test total resistance cap (50%)
	var all_resistances := evolution.get_all_resistances()
	var total := 0.0
	for faction in all_resistances:
		total += all_resistances[faction]
	_assert_lt(total, 0.51, "Total resistance capped at 50%")

	# Test serialization
	var data := evolution.to_dict()
	_assert(data.has("learned_resistances"), "Serialization includes learned_resistances")
	_assert(data.has("death_counts"), "Serialization includes death_counts")

	var evolution2 := AdaptiveEvolution.new()
	evolution2.from_dict(data)
	_assert_approx(evolution2.get_resistance("aether_swarm"), evolution.get_resistance("aether_swarm"), 0.001, "Deserialized resistance matches")

	# Test summary
	var summary := evolution.get_summary()
	_assert(summary.has("total_deaths"), "Summary includes total_deaths")
	_assert(summary.has("top_threat"), "Summary includes top_threat")
	_log_output("AdaptiveEvolution Summary: %s" % str(summary))


# =============================================================================
# FACTION MECHANICS SYSTEM INTEGRATION TESTS
# =============================================================================

func _test_faction_mechanics_integration() -> void:
	var system := FactionMechanicsSystem.new()

	# Test registering units from different factions
	# Need 4+ aether_swarm units for SwarmSynergy (requires 3+ nearby allies)
	system.register_unit(1, "aether_swarm", 0.0)
	system.register_unit(2, "aether_swarm", 0.0)
	system.register_unit(100, "aether_swarm", 0.0)  # Extra for synergy
	system.register_unit(101, "aether_swarm", 0.0)  # Extra for synergy
	system.register_unit(3, "glacius", 0.2)
	system.register_unit(4, "glacius", 0.15)
	system.register_unit(5, "dynapods", 0.0)
	system.register_unit(6, "logibots", 0.0)
	system.register_unit(7, "logibots", 0.0)

	_assert_eq(system.get_unit_faction(1), "aether_swarm", "Unit 1 faction is aether_swarm")
	_assert_eq(system.get_unit_faction(3), "glacius", "Unit 3 faction is glacius")

	# Test position updates - cluster aether_swarm units within 10m radius
	var positions := {
		1: Vector3(0, 0, 0),
		2: Vector3(3, 0, 0),
		100: Vector3(0, 0, 3),
		101: Vector3(3, 0, 3),
		3: Vector3(20, 0, 0),
		4: Vector3(23, 0, 0),
		5: Vector3(40, 0, 0),
		6: Vector3(60, 0, 0),
		7: Vector3(63, 0, 0),
	}
	system.update_positions(positions)
	system.update(0.034)  # Slightly more than 1/30 to ensure update triggers

	# Test outgoing damage (SwarmSynergy for aether_swarm)
	var aether_damage := system.calculate_outgoing_damage(1, 100.0)
	_assert_gt(aether_damage, 100.0, "Aether Swarm gets damage bonus from SwarmSynergy")
	_log_output("Aether Swarm outgoing damage: 100.0 -> %.1f" % aether_damage)

	# Test outgoing damage (SynchronizedStrikes for logibots)
	system.set_attack_target(6, 100)  # Both logibots target same enemy
	system.set_attack_target(7, 100)
	system.update(0.034)
	var logi_damage := system.calculate_outgoing_damage(6, 100.0)
	_assert_gt(logi_damage, 100.0, "LogiBots get damage bonus from SynchronizedStrikes")
	_log_output("LogiBots outgoing damage: 100.0 -> %.1f" % logi_damage)

	# Test incoming damage (ArmorStacking for glacius)
	var glacius_result := system.calculate_incoming_damage(3, 100.0, "aether_swarm")
	_assert_lt(glacius_result["damage"], 100.0, "Glacius takes reduced damage from ArmorStacking")
	_log_output("Glacius incoming damage: 100.0 -> %.1f" % glacius_result["damage"])

	# Test incoming damage (EvasionStacking for dynapods)
	# Add another dynapods unit nearby for evasion bonus
	system.register_unit(8, "dynapods", 0.0)
	positions[8] = Vector3(43, 0, 0)  # Near unit 5
	system.update_positions(positions)
	system.update(0.034)

	var dynapods_result := system.calculate_incoming_damage(5, 100.0)
	_assert(dynapods_result.has("dodged"), "Dynapods result includes dodge check")
	_log_output("Dynapods incoming damage: 100.0 -> %.1f (dodged: %s)" % [
		dynapods_result["damage"], str(dynapods_result["dodged"])
	])

	# Test death recording for AdaptiveEvolution
	system.record_death(3, "aether_swarm")  # Glacius unit dies to Aether Swarm
	system.record_death(4, "aether_swarm")

	# Check that glacius now has resistance
	var glacius_result2 := system.calculate_incoming_damage(3, 100.0, "aether_swarm")
	_assert(glacius_result2.has("evolution_reduction"), "Result includes evolution_reduction")
	_log_output("Glacius evolved resistance reduction: %.1f" % glacius_result2.get("evolution_reduction", 0.0))

	# Test unregistration
	system.unregister_unit(1)
	_assert_eq(system.get_unit_faction(1), "", "Unregistered unit has no faction")

	# Test serialization
	var data := system.to_dict()
	_assert(data.has("unit_factions"), "Serialization includes unit_factions")
	_assert(data.has("swarm_synergy"), "Serialization includes swarm_synergy")
	_assert(data.has("adaptive_evolution"), "Serialization includes adaptive_evolution")

	var system2 := FactionMechanicsSystem.new()
	system2.from_dict(data)
	_assert_eq(system2.get_unit_faction(3), "glacius", "Deserialized faction matches")

	# Test summary
	var summary := system.get_summary()
	_assert(summary.has("total_units"), "Summary includes total_units")
	_assert(summary.has("faction_counts"), "Summary includes faction_counts")
	_log_output("System Summary: %d units tracked" % summary["total_units"])


# =============================================================================
# OUTPUT VERIFICATION TESTS
# =============================================================================

func _test_output_verification() -> void:
	_clear_output_log()

	var system := FactionMechanicsSystem.new()

	# Connect to signals for output verification
	system.damage_modified.connect(_on_damage_modified)
	system.damage_received_modified.connect(_on_damage_received_modified)

	# Setup test units
	system.register_unit(1, "aether_swarm", 0.0)
	system.register_unit(2, "aether_swarm", 0.0)
	system.register_unit(3, "glacius", 0.2)

	var positions := {
		1: Vector3(0, 0, 0),
		2: Vector3(3, 0, 0),
		3: Vector3(20, 0, 0),
	}
	system.update_positions(positions)
	system.update(0.034)  # Slightly more than 1/30 to ensure update triggers

	# Trigger damage modification (should emit signal)
	var damage := system.calculate_outgoing_damage(1, 100.0)
	_assert(_output_contains("damage_modified"), "Signal emitted for damage modification")

	# Trigger incoming damage modification
	var result := system.calculate_incoming_damage(3, 100.0)
	_assert(_output_contains("damage_received"), "Signal emitted for incoming damage modification")

	# Verify output format
	_assert(_output_contains("unit_id"), "Output includes unit_id")
	_assert(_output_contains("base"), "Output includes base damage")


func _on_damage_modified(unit_id: int, base_damage: float, modified_damage: float, faction: String) -> void:
	_log_output("damage_modified: unit_id=%d, base=%.1f, modified=%.1f, faction=%s" % [
		unit_id, base_damage, modified_damage, faction
	])


func _on_damage_received_modified(unit_id: int, incoming: float, actual: float, faction: String) -> void:
	_log_output("damage_received_modified: unit_id=%d, incoming=%.1f, actual=%.1f, faction=%s" % [
		unit_id, incoming, actual, faction
	])


# =============================================================================
# PHASE SHIFT ABILITY TESTS
# =============================================================================

func _test_phase_shift_ability() -> void:
	var phase := PhaseShiftAbility.new()

	# Test initial state
	_assert_eq(phase.get_phased_count(), 0, "Initial phased count is 0")
	_assert(not phase.is_on_cooldown(), "Not on cooldown initially")

	# Test activation validation
	var validation := phase.can_activate()
	_assert(validation["can_activate"], "Can activate initially")

	# Test activation with specific units
	var unit_ids: Array[int] = [1, 2, 3, 4, 5]
	var activated := phase.activate_for_units(unit_ids)
	_assert(activated, "Activation succeeded")
	_assert_eq(phase.get_phased_count(), 5, "5 units phased")
	_assert(phase.is_on_cooldown(), "On cooldown after activation")

	# Test phased state
	_assert(phase.is_phased(1), "Unit 1 is phased")
	_assert(phase.is_phased(5), "Unit 5 is phased")
	_assert(not phase.is_phased(100), "Non-phased unit returns false")

	# Test damage reduction
	var reduction := phase.get_damage_reduction(1)
	_assert_approx(reduction, 0.90, 0.01, "Damage reduction is 90%")

	var original_damage := 100.0
	var reduced_damage := phase.apply_to_damage(1, original_damage)
	_assert_approx(reduced_damage, 10.0, 0.1, "100 damage reduced to 10 (90% reduction)")
	_log_output("PhaseShift: %.1f damage -> %.1f (%.0f%% reduction)" % [
		original_damage, reduced_damage, reduction * 100
	])

	# Test non-phased unit gets no reduction
	var normal_damage := phase.apply_to_damage(100, 100.0)
	_assert_eq(normal_damage, 100.0, "Non-phased unit takes full damage")

	# Test cooldown blocking
	validation = phase.can_activate()
	_assert(not validation["can_activate"], "Cannot activate while on cooldown")
	_assert("cooldown" in validation["reason"].to_lower(), "Reason mentions cooldown")

	# Test phase expiration via update
	phase.update(4.0)  # Phase duration is 3s, this exceeds it
	_assert_eq(phase.get_phased_count(), 0, "All phases expired after duration")
	_assert(not phase.is_phased(1), "Unit 1 no longer phased")

	# Test cooldown decay
	phase.update(5.0)  # Cooldown is 8s, total 9s elapsed
	_assert(not phase.is_on_cooldown(), "Cooldown expired")

	# Test serialization
	phase.activate_for_units([10, 11])
	var data := phase.to_dict()
	_assert(data.has("phased_units"), "Serialization includes phased_units")
	_assert(data.has("total_damage_phased"), "Serialization includes stats")

	var phase2 := PhaseShiftAbility.new()
	phase2.from_dict(data)
	_assert_eq(phase2.get_phased_count(), 2, "Deserialized phased count matches")

	# Test stats
	var stats := phase.get_stats()
	_assert(stats.has("total_activations"), "Stats include activations")
	_assert_gt(stats["total_damage_phased"], 0.0, "Stats track damage phased")
	_log_output("PhaseShift Stats: %s" % str(stats))


# =============================================================================
# COMBAT FLOW SIMULATION TESTS
# =============================================================================

func _test_combat_flow_simulation() -> void:
	_clear_output_log()

	var system := FactionMechanicsSystem.new()

	# Simulate a mini-battle between factions
	_log_output("=== COMBAT SIMULATION START ===")

	# Register units for each faction
	var aether_units := [1, 2, 3, 4, 5]  # Aether Swarm (swarm synergy)
	var glacius_units := [10, 11, 12]     # OptiForge/Glacius (armor + evolution)
	var dynapods_units := [20, 21]        # Dynapods (evasion)
	var logibots_units := [30, 31, 32]    # LogiBots (synchronized strikes)

	for id in aether_units:
		system.register_unit(id, "aether_swarm", 0.0)
	for id in glacius_units:
		system.register_unit(id, "glacius", 0.15)
	for id in dynapods_units:
		system.register_unit(id, "dynapods", 0.0)
	for id in logibots_units:
		system.register_unit(id, "logibots", 0.1)

	# Position units in clusters
	var positions := {}
	for i in range(aether_units.size()):
		positions[aether_units[i]] = Vector3(i * 3, 0, 0)
	for i in range(glacius_units.size()):
		positions[glacius_units[i]] = Vector3(50 + i * 3, 0, 0)
	for i in range(dynapods_units.size()):
		positions[dynapods_units[i]] = Vector3(0, 0, 50 + i * 5)
	for i in range(logibots_units.size()):
		positions[logibots_units[i]] = Vector3(50, 0, 50 + i * 3)

	system.update_positions(positions)

	# Simulate 10 combat ticks
	for tick in range(10):
		system.update(0.1)

		# Aether attacks Glacius
		var aether_damage := system.calculate_outgoing_damage(1, 50.0)
		var glacius_result := system.calculate_incoming_damage(10, aether_damage, "aether_swarm")

		# LogiBots focus fire on Aether (synchronized)
		system.set_attack_target(30, 1)
		system.set_attack_target(31, 1)
		system.set_attack_target(32, 1)
		var logi_damage := system.calculate_outgoing_damage(30, 40.0)

		if tick == 0:
			_log_output("Tick %d: Aether deals %.1f (base 50), Glacius receives %.1f" % [
				tick, aether_damage, glacius_result["damage"]
			])
			_log_output("Tick %d: LogiBots synchronized damage: %.1f (base 40)" % [tick, logi_damage])

		# Simulate some Glacius deaths to trigger evolution
		if tick == 3:
			system.record_death(11, "aether_swarm")
			_log_output("Tick %d: Glacius unit 11 killed by Aether Swarm" % tick)
		if tick == 5:
			system.record_death(12, "aether_swarm")
			_log_output("Tick %d: Glacius unit 12 killed by Aether Swarm" % tick)

		# Move Dynapods to build evasion
		positions[20] = positions[20] + Vector3(5, 0, 0)
		positions[21] = positions[21] + Vector3(3, 0, 2)
		system.update_positions(positions)

	# Final state verification
	_log_output("=== COMBAT SIMULATION END ===")

	# Verify SwarmSynergy is working
	var final_aether_damage := system.calculate_outgoing_damage(1, 100.0)
	_assert_gt(final_aether_damage, 100.0, "SwarmSynergy bonus active at end")
	_log_output("Final Aether damage bonus: %.1f%%" % ((final_aether_damage / 100.0 - 1.0) * 100))

	# Verify AdaptiveEvolution learned from deaths
	var evolved_result := system.calculate_incoming_damage(10, 100.0, "aether_swarm")
	_assert_gt(evolved_result.get("evolution_reduction", 0.0), 0.0, "Glacius evolved resistance after deaths")
	_log_output("Glacius evolution resistance: %.1f%%" % (evolved_result.get("evolution_reduction", 0.0)))

	# Verify LogiBots synchronized
	var final_logi_damage := system.calculate_outgoing_damage(30, 100.0)
	_assert_gt(final_logi_damage, 100.0, "SynchronizedStrikes bonus active")
	_log_output("Final LogiBots sync bonus: %.1f%%" % ((final_logi_damage / 100.0 - 1.0) * 100))

	# Get final summary
	var summary := system.get_summary()
	_log_output("Final system state: %d units, update time: %s" % [
		summary["total_units"], summary["last_update_ms"]
	])

	# Verify faction counts
	var faction_counts: Dictionary = summary["faction_counts"]
	_assert_eq(faction_counts.get("aether_swarm", 0), 5, "Correct Aether Swarm count")
	_assert_eq(faction_counts.get("logibots", 0), 3, "Correct LogiBots count")


# =============================================================================
# OVERCLOCK UNIT ABILITY TESTS
# =============================================================================

func _test_overclock_unit_ability() -> void:
	var overclock := OverclockUnitAbility.new()

	# Set up self-damage tracking callback BEFORE activation
	# Use Dictionary to capture by reference (primitives are captured by value)
	var damage_tracker := {"accumulated": 0.0}
	var test_self_damage_callback := func(unit_id: int, damage: float) -> void:
		damage_tracker["accumulated"] += damage
	overclock.set_apply_self_damage(test_self_damage_callback)

	# Test initial state
	_assert_eq(overclock.get_overclocked_count(), 0, "Initial overclocked count is 0")
	_assert(not overclock.is_on_cooldown(), "Not on cooldown initially")

	# Test activation validation
	var validation := overclock.can_activate()
	_assert(validation["can_activate"], "Can activate initially")

	# Test activation with specific units
	var unit_ids: Array[int] = [1, 2, 3]
	var activated := overclock.activate_for_units(unit_ids)
	_assert(activated, "Activation succeeded")
	_assert_eq(overclock.get_overclocked_count(), 3, "3 units overclocked")
	_assert(overclock.is_on_cooldown(), "On cooldown after activation")

	# Test overclocked state
	_assert(overclock.is_overclocked(1), "Unit 1 is overclocked")
	_assert(overclock.is_overclocked(3), "Unit 3 is overclocked")
	_assert(not overclock.is_overclocked(100), "Non-overclocked unit returns false")

	# Test damage multiplier (50% boost)
	var multiplier := overclock.get_damage_multiplier(1)
	_assert_approx(multiplier, 1.50, 0.01, "Damage multiplier is 1.5 (50% boost)")

	var base_damage := 100.0
	var boosted_damage := overclock.apply_to_damage(1, base_damage)
	_assert_approx(boosted_damage, 150.0, 0.1, "100 damage boosted to 150 (50% increase)")
	_log_output("Overclock: %.1f damage -> %.1f (+%.0f%% boost)" % [
		base_damage, boosted_damage, (multiplier - 1.0) * 100
	])

	# Test speed multiplier (30% boost)
	var speed_mult := overclock.get_speed_multiplier(1)
	_assert_approx(speed_mult, 1.30, 0.01, "Speed multiplier is 1.3 (30% boost)")

	# Test non-overclocked unit gets no boost
	var normal_damage := overclock.apply_to_damage(100, 100.0)
	_assert_eq(normal_damage, 100.0, "Non-overclocked unit gets no boost")
	var normal_speed := overclock.get_speed_multiplier(100)
	_assert_eq(normal_speed, 1.0, "Non-overclocked unit has normal speed")

	# Test cooldown blocking
	validation = overclock.can_activate()
	_assert(not validation["can_activate"], "Cannot activate while on cooldown")
	_assert("cooldown" in validation["reason"].to_lower(), "Reason mentions cooldown")

	# Test self-damage during update (5 DPS * 1s = 5 damage per unit * 3 units)
	# Note: Callback was set up earlier in the test before activation
	overclock.update(1.0)
	_assert_gt(damage_tracker["accumulated"], 0.0, "Self-damage applied during overclock")
	_log_output("Self-damage after 1s: %.1f (3 units at 5 DPS = expected 15)" % damage_tracker["accumulated"])

	# Test overclock expiration via update
	overclock.update(5.0)  # Duration is 5s, total 6s elapsed
	_assert_eq(overclock.get_overclocked_count(), 0, "All overclocks expired after duration")
	_assert(not overclock.is_overclocked(1), "Unit 1 no longer overclocked")

	# Test cooldown decay
	overclock.update(7.0)  # Cooldown is 12s, total 13s elapsed
	_assert(not overclock.is_on_cooldown(), "Cooldown expired")

	# Test serialization
	overclock.activate_for_units([10, 11])
	var data := overclock.to_dict()
	_assert(data.has("overclocked_units"), "Serialization includes overclocked_units")
	_assert(data.has("total_overclocks"), "Serialization includes stats")
	_assert(data.has("total_bonus_damage_dealt"), "Serialization includes bonus damage stats")

	var overclock2 := OverclockUnitAbility.new()
	overclock2.from_dict(data)
	_assert_eq(overclock2.get_overclocked_count(), 2, "Deserialized overclocked count matches")

	# Test stats
	var stats := overclock.get_stats()
	_assert(stats.has("total_overclocks"), "Stats include total overclocks")
	_assert(stats.has("total_bonus_damage_dealt"), "Stats include bonus damage")
	_assert(stats.has("total_self_damage_taken"), "Stats include self damage")
	_log_output("Overclock Stats: %s" % str(stats))

	# Test configuration
	var config := overclock.get_config()
	_assert_eq(config["hotkey"], "Q", "Hotkey is Q")
	_assert_approx(config["damage_boost"], 0.50, 0.01, "Damage boost is 50%")
	_assert_approx(config["speed_boost"], 0.30, 0.01, "Speed boost is 30%")
	_assert_approx(config["self_damage_per_second"], 5.0, 0.01, "Self damage is 5 DPS")


# =============================================================================
# SIEGE FORMATION ABILITY TESTS
# =============================================================================

func _test_siege_formation_ability() -> void:
	var siege := SiegeFormationAbility.new()

	# Test initial state
	_assert_eq(siege.get_deployed_count(), 0, "Initial deployed count is 0")
	_assert(not siege.is_on_cooldown(), "Not on cooldown initially")

	# Test activation validation
	var validation := siege.can_activate()
	_assert(validation["can_activate"], "Can activate initially")

	# Setup position callback for position tracking
	var unit_positions: Dictionary = {
		1: Vector3(0, 0, 0),
		2: Vector3(10, 0, 0),
		3: Vector3(20, 0, 0)
	}
	var get_pos_callback := func(unit_id: int) -> Vector3:
		return unit_positions.get(unit_id, Vector3.ZERO)
	siege.set_get_unit_position(get_pos_callback)

	# Test activation with specific units
	var unit_ids: Array[int] = [1, 2, 3]
	var activated := siege.activate_for_units(unit_ids)
	_assert(activated, "Activation succeeded")
	_assert_eq(siege.get_deployed_count(), 3, "3 units deployed")
	_assert(siege.is_on_cooldown(), "On cooldown after activation")

	# Test deployed state
	_assert(siege.is_deployed(1), "Unit 1 is deployed")
	_assert(siege.is_deployed(3), "Unit 3 is deployed")
	_assert(not siege.is_deployed(100), "Non-deployed unit returns false")

	# Test deploying state (not fully deployed yet)
	_assert(not siege.is_fully_deployed(1), "Unit 1 is not fully deployed immediately")

	# Test range multiplier during deploy (should be 1.0)
	var multiplier := siege.get_range_multiplier(1)
	_assert_approx(multiplier, 1.0, 0.01, "No range boost while deploying")

	# Simulate deploy time passing
	siege.update(1.5)  # Deploy time is 1s
	_assert(siege.is_fully_deployed(1), "Unit 1 fully deployed after deploy time")

	# Test range multiplier after deploy (50% boost)
	multiplier = siege.get_range_multiplier(1)
	_assert_approx(multiplier, 1.50, 0.01, "Range multiplier is 1.5 (50% boost)")

	var base_range := 15.0
	var boosted_range := siege.apply_to_range(1, base_range)
	_assert_approx(boosted_range, 22.5, 0.1, "15 range boosted to 22.5 (50% increase)")
	_log_output("Siege Formation: %.1f range -> %.1f (+%.0f%% boost)" % [
		base_range, boosted_range, (multiplier - 1.0) * 100
	])

	# Test non-deployed unit gets no boost
	var normal_range := siege.apply_to_range(100, 15.0)
	_assert_eq(normal_range, 15.0, "Non-deployed unit gets no boost")

	# Test cooldown blocking
	validation = siege.can_activate()
	_assert(not validation["can_activate"], "Cannot activate while on cooldown")
	_assert("cooldown" in validation["reason"].to_lower(), "Reason mentions cooldown")

	# Test movement detection (unit moves, siege cancelled)
	unit_positions[1] = Vector3(100, 0, 0)  # Move unit 1 far away
	siege.update(0.1)
	_assert(not siege.is_deployed(1), "Unit 1 mobilized after moving")
	_assert_eq(siege.get_deployed_count(), 2, "Only 2 units still deployed")

	# Test manual mobilization via cancel
	siege.cancel_all()
	_assert_eq(siege.get_deployed_count(), 0, "All units mobilized after cancel")

	# Test cooldown decay
	siege.update(16.0)  # Cooldown is 15s
	_assert(not siege.is_on_cooldown(), "Cooldown expired")

	# Test serialization
	unit_positions[10] = Vector3(50, 0, 50)
	unit_positions[11] = Vector3(60, 0, 50)
	siege.activate_for_units([10, 11])
	siege.update(1.5)  # Fully deploy

	var data := siege.to_dict()
	_assert(data.has("deployed_units"), "Serialization includes deployed_units")
	_assert(data.has("total_deployments"), "Serialization includes stats")

	var siege2 := SiegeFormationAbility.new()
	siege2.from_dict(data)
	_assert_eq(siege2.get_deployed_count(), 2, "Deserialized deployed count matches")

	# Test stats
	var stats := siege.get_stats()
	_assert(stats.has("total_deployments"), "Stats include total deployments")
	_assert(stats.has("total_shots_while_deployed"), "Stats include shots fired")
	_log_output("Siege Formation Stats: %s" % str(stats))

	# Test configuration
	var config := siege.get_config()
	_assert_eq(config["hotkey"], "F", "Hotkey is F")
	_assert_approx(config["range_boost"], 0.50, 0.01, "Range boost is 50%")
	_assert_approx(config["deploy_time"], 1.0, 0.01, "Deploy time is 1s")

	# Test toggle functionality
	siege2.set_get_unit_position(get_pos_callback)
	_assert(siege2.is_deployed(10), "Unit 10 still deployed after deserialization")
	siege2.toggle("logibots")  # Should undeploy since some are deployed
	_assert_eq(siege2.get_deployed_count(), 0, "Toggle undeploys when units are deployed")


# =============================================================================
# NANO REPLICATION ABILITY TESTS
# =============================================================================

func _test_nano_replication_ability() -> void:
	var nano := NanoReplicationAbility.new()

	# Set up callbacks
	var unit_health: Dictionary = {1: 50.0, 2: 80.0, 3: 100.0}
	var unit_max_health: Dictionary = {1: 100.0, 2: 100.0, 3: 100.0}
	var healing_applied: Dictionary = {}

	nano.set_get_unit_health(func(uid: int) -> float: return unit_health.get(uid, 0.0))
	nano.set_get_unit_max_health(func(uid: int) -> float: return unit_max_health.get(uid, 100.0))
	nano.set_apply_healing(func(uid: int, amount: float) -> void:
		healing_applied[uid] = healing_applied.get(uid, 0.0) + amount
		unit_health[uid] = minf(unit_health.get(uid, 0.0) + amount, unit_max_health.get(uid, 100.0))
	)

	# Test registration
	nano.register_unit(1)
	nano.register_unit(2)
	nano.register_unit(3)

	_assert_eq(nano.get_heal_rate(1), 0.0, "Initial heal rate is 0")
	_assert_eq(nano.get_nearby_count(1), 0, "Initial nearby count is 0")

	# Test healing with nearby allies (need at least 1 ally nearby)
	var positions := {
		1: Vector3(0, 0, 0),
		2: Vector3(3, 0, 0),   # Within 8m radius
		3: Vector3(5, 0, 0),   # Within 8m radius
	}
	nano.update(1.0, positions)  # 1 second of healing

	_assert_gt(nano.get_nearby_count(1), 0, "Unit 1 has nearby allies")
	_assert_gt(nano.get_heal_rate(1), 0.0, "Heal rate > 0 with nearby allies")

	# Unit 1 was at 50 HP, should have healed some
	_assert_gt(unit_health[1], 50.0, "Unit 1 healed (was at 50 HP)")
	_log_output("NanoReplication: Unit 1 healed to %.1f HP (from 50)" % unit_health[1])

	# Unit 3 was at full health, should not have healed
	_assert_eq(unit_health[3], 100.0, "Unit 3 at full health didn't heal")

	# Test heal rate calculation (base 2.0 + 0.5 per ally, capped at 15)
	var rate := nano.get_heal_rate(1)
	_assert_gt(rate, 2.0, "Heal rate > base rate with allies")
	_assert_lt(rate, 15.1, "Heal rate capped at 15")
	_log_output("NanoReplication: Heal rate = %.1f HP/s" % rate)

	# Test unregistration
	nano.unregister_unit(1)
	_assert_eq(nano.get_heal_rate(1), 0.0, "Heal rate 0 after unregistration")

	# Test serialization
	var data := nano.to_dict()
	_assert(data.has("unit_data"), "Serialization includes unit_data")
	_assert(data.has("total_healing_done"), "Serialization includes stats")

	var nano2 := NanoReplicationAbility.new()
	nano2.from_dict(data)
	_assert_eq(nano2.get_stats()["tracked_units"], 2, "Deserialized tracked units matches")

	# Test stats
	var stats := nano.get_stats()
	_assert(stats.has("total_healing_done"), "Stats include total healing")
	_assert(stats.has("units_fully_healed"), "Stats include fully healed count")
	_log_output("NanoReplication Stats: %s" % str(stats))


# =============================================================================
# ETHER CLOAK ABILITY TESTS
# =============================================================================

func _test_ether_cloak_ability() -> void:
	var cloak := EtherCloakAbility.new()

	# Set up callbacks
	var unit_targetable: Dictionary = {}
	var unit_cloaked_visual: Dictionary = {}

	cloak.set_get_faction_units(func(faction_id: String) -> Array:
		return [1, 2, 3, 4, 5]
	)
	cloak.set_unit_targetable(func(uid: int, targetable: bool) -> void:
		unit_targetable[uid] = targetable
	)
	cloak.set_unit_visual_cloak(func(uid: int, cloaked: bool, alpha: float) -> void:
		unit_cloaked_visual[uid] = {"cloaked": cloaked, "alpha": alpha}
	)

	# Test initial state
	_assert_eq(cloak.get_cloaked_count(), 0, "Initial cloaked count is 0")
	_assert(not cloak.is_on_cooldown(), "Not on cooldown initially")

	# Test activation validation
	var validation := cloak.can_activate()
	_assert(validation["can_activate"], "Can activate initially")

	# Test activation for faction
	var activated := cloak.activate("aether_swarm")
	_assert(activated, "Activation succeeded")
	_assert_eq(cloak.get_cloaked_count(), 5, "5 units cloaked")
	_assert(cloak.is_on_cooldown(), "On cooldown after activation")

	# Test cloaked state
	_assert(cloak.is_cloaked(1), "Unit 1 is cloaked")
	_assert(cloak.is_cloaked(5), "Unit 5 is cloaked")
	_assert(not cloak.is_cloaked(100), "Non-cloaked unit returns false")

	# Test targetability callbacks
	_assert_eq(unit_targetable.get(1, true), false, "Unit 1 untargetable while cloaked")
	_assert(unit_cloaked_visual.get(1, {}).get("cloaked", false), "Unit 1 has cloak visual")
	_assert_approx(unit_cloaked_visual.get(1, {}).get("alpha", 1.0), 0.15, 0.01, "Cloak alpha is 0.15")

	# Test cloak duration tracking
	var remaining := cloak.get_cloak_remaining(1)
	_assert_approx(remaining, 4.0, 0.1, "Cloak remaining is ~4s")

	# Test cooldown blocking
	validation = cloak.can_activate()
	_assert(not validation["can_activate"], "Cannot activate while on cooldown")
	_assert("cooldown" in validation["reason"].to_lower(), "Reason mentions cooldown")

	# Test attack recording
	cloak.record_attack(1)
	cloak.record_attack(1)
	cloak.record_attack(2)
	# Stats will be tracked when cloak ends

	# Test cloak expiration via update
	cloak.update(5.0)  # Cloak duration is 4s
	_assert_eq(cloak.get_cloaked_count(), 0, "All cloaks expired after duration")
	_assert(not cloak.is_cloaked(1), "Unit 1 no longer cloaked")

	# Check targetability restored
	_assert_eq(unit_targetable.get(1, false), true, "Unit 1 targetable again after cloak ends")

	# Test cooldown decay
	cloak.update(16.0)  # Cooldown is 20s, total 21s elapsed
	_assert(not cloak.is_on_cooldown(), "Cooldown expired")

	# Test serialization
	cloak.activate_for_units([10, 11] as Array[int])
	var data := cloak.to_dict()
	_assert(data.has("cloaked_units"), "Serialization includes cloaked_units")
	_assert(data.has("total_cloaks"), "Serialization includes stats")

	var cloak2 := EtherCloakAbility.new()
	cloak2.from_dict(data)
	_assert_eq(cloak2.get_cloaked_count(), 2, "Deserialized cloaked count matches")

	# Test stats
	var stats := cloak.get_stats()
	_assert(stats.has("total_cloaks"), "Stats include total cloaks")
	_assert(stats.has("total_attacks_while_cloaked"), "Stats include attacks while cloaked")
	_log_output("EtherCloak Stats: %s" % str(stats))

	# Test configuration
	var config := cloak.get_config()
	_assert_eq(config["hotkey"], "C", "Hotkey is C")
	_assert_approx(config["duration"], 4.0, 0.01, "Duration is 4s")
	_assert_approx(config["cooldown"], 20.0, 0.01, "Cooldown is 20s")


# =============================================================================
# TERRAIN MASTERY ABILITY TESTS
# =============================================================================

func _test_terrain_mastery_ability() -> void:
	var terrain := TerrainMasteryAbility.new()

	# Test registration
	terrain.register_unit(1)  # Has mastery
	terrain.register_unit(2)  # Has mastery

	_assert(terrain.has_mastery(1), "Unit 1 has terrain mastery")
	_assert(not terrain.has_mastery(100), "Unit 100 doesn't have mastery")

	# Test terrain setting
	terrain.set_terrain(Vector3(10, 0, 10), "rubble")
	terrain.set_terrain(Vector3(20, 0, 20), "mud")
	terrain.set_terrain_area(Vector3(50, 0, 50), 10.0, "water")

	_assert_eq(terrain.get_terrain_at(Vector3(10, 0, 10)), "rubble", "Terrain at (10,0,10) is rubble")
	_assert_eq(terrain.get_terrain_at(Vector3(50, 0, 50)), "water", "Terrain at (50,0,50) is water")
	_assert_eq(terrain.get_terrain_at(Vector3(0, 0, 0)), "normal", "Terrain at origin is normal")

	# Test speed multiplier for mastery unit (always 1.0)
	var multiplier := terrain.get_speed_multiplier(1, Vector3(10, 0, 10))
	_assert_approx(multiplier, 1.0, 0.01, "Mastery unit has full speed on rubble")

	# Test speed multiplier for non-mastery unit (gets penalty)
	var penalty_mult := terrain.get_speed_multiplier(100, Vector3(10, 0, 10))
	_assert_approx(penalty_mult, 0.5, 0.01, "Non-mastery unit has 50% speed on rubble")

	var mud_penalty := terrain.get_speed_multiplier(100, Vector3(20, 0, 20))
	_assert_approx(mud_penalty, 0.4, 0.01, "Non-mastery unit has 40% speed in mud")
	_log_output("TerrainMastery: Rubble penalty %.0f%%, Mud penalty %.0f%%" % [
		(1.0 - penalty_mult) * 100, (1.0 - mud_penalty) * 100
	])

	# Test update tracking
	var positions := {
		1: Vector3(10, 0, 10),  # On rubble
		2: Vector3(20, 0, 20),  # On mud
	}
	terrain.update(1.0, positions)

	_assert_eq(terrain.get_unit_terrain(1), "rubble", "Unit 1 on rubble")
	_assert_eq(terrain.get_unit_terrain(2), "mud", "Unit 2 on mud")

	# Test unregistration
	terrain.unregister_unit(1)
	_assert(not terrain.has_mastery(1), "Unit 1 no longer has mastery after unregistration")

	# Test serialization
	var data := terrain.to_dict()
	_assert(data.has("terrain_grid"), "Serialization includes terrain_grid")
	_assert(data.has("terrain_crossings"), "Serialization includes stats")

	var terrain2 := TerrainMasteryAbility.new()
	terrain2.from_dict(data)
	_assert_eq(terrain2.get_terrain_at(Vector3(10, 0, 10)), "rubble", "Deserialized terrain matches")

	# Test stats
	var stats := terrain.get_stats()
	_assert(stats.has("terrain_crossings"), "Stats include terrain crossings")
	_assert(stats.has("total_distance_bonus"), "Stats include distance bonus")
	_log_output("TerrainMastery Stats: %s" % str(stats))

	# Test configuration
	var config := terrain.get_config()
	_assert(config.has("terrain_types"), "Config includes terrain types")
	_assert(config.has("default_penalties"), "Config includes default penalties")


# =============================================================================
# COORDINATED BARRAGE ABILITY TESTS
# =============================================================================

func _test_coordinated_barrage_ability() -> void:
	var barrage := CoordinatedBarrageAbility.new()

	# Set up callbacks
	var unit_positions: Dictionary = {
		1: Vector3(0, 0, 0),
		2: Vector3(10, 0, 0),
		3: Vector3(20, 0, 0),
	}
	var unit_targets: Dictionary = {}
	var target_alive: Dictionary = {100: true, 101: true}

	barrage.set_get_unit_position(func(uid: int) -> Vector3: return unit_positions.get(uid, Vector3.ZERO))
	barrage.set_unit_target(func(uid: int, tid: int) -> void: unit_targets[uid] = tid)
	barrage.set_is_target_alive(func(tid: int) -> bool: return target_alive.get(tid, false))

	# Test registration
	barrage.register_unit(1)
	barrage.register_unit(2)
	barrage.register_unit(3)

	# Test initial state
	_assert_eq(barrage.get_marked_target(), -1, "Initial marked target is -1")
	_assert(not barrage.is_on_cooldown(), "Not on cooldown initially")
	_assert(not barrage.is_barrage_active(), "No barrage active initially")

	# Test activation validation
	var validation := barrage.can_activate()
	_assert(validation["can_activate"], "Can activate initially")

	# Test activation
	var activated := barrage.activate(100, Vector3(15, 0, 0))
	_assert(activated, "Activation succeeded")
	_assert_eq(barrage.get_marked_target(), 100, "Target 100 is marked")
	_assert(barrage.is_on_cooldown(), "On cooldown after activation")
	_assert(barrage.is_barrage_active(), "Barrage is active")

	# Test target marking
	_assert(barrage.is_target_marked(100), "Target 100 is marked")
	_assert(not barrage.is_target_marked(101), "Target 101 is not marked")

	# Test units redirected to target (units within 30m radius)
	_assert_eq(unit_targets.get(1, -1), 100, "Unit 1 redirected to target 100")
	_assert_eq(unit_targets.get(2, -1), 100, "Unit 2 redirected to target 100")

	# Test damage multiplier (75% bonus)
	var multiplier := barrage.get_damage_multiplier(1, 100)
	_assert_approx(multiplier, 1.75, 0.01, "Damage multiplier is 1.75 (75% bonus)")

	var no_bonus := barrage.get_damage_multiplier(1, 101)
	_assert_eq(no_bonus, 1.0, "No bonus for unmarked target")

	# Test bonus damage calculation
	var bonus := barrage.calculate_bonus_damage(1, 100, 100.0)
	_assert_approx(bonus, 75.0, 0.1, "Bonus damage is 75 for 100 base damage")
	_log_output("CoordinatedBarrage: 100 base damage + %.1f bonus = %.1f total" % [
		bonus, 100.0 + bonus
	])

	# Test cooldown blocking
	validation = barrage.can_activate()
	_assert(not validation["can_activate"], "Cannot activate while on cooldown")
	_assert("cooldown" in validation["reason"].to_lower(), "Reason mentions cooldown")

	# Test barrage duration tracking
	var remaining := barrage.get_barrage_remaining()
	_assert_approx(remaining, 8.0, 0.1, "Barrage remaining is ~8s")

	# Test barrage expiration via update
	barrage.update(9.0)  # Duration is 8s
	_assert(not barrage.is_barrage_active(), "Barrage expired after duration")
	_assert_eq(barrage.get_marked_target(), -1, "No marked target after expiration")

	# Test cooldown decay
	barrage.update(17.0)  # Cooldown is 25s, total 26s elapsed
	_assert(not barrage.is_on_cooldown(), "Cooldown expired")

	# Test target death ends barrage early
	barrage.activate(101, Vector3(0, 0, 0))
	target_alive[101] = false  # Kill target
	barrage.update(0.1)
	_assert(not barrage.is_barrage_active(), "Barrage ended when target died")

	# Test serialization
	target_alive[102] = true
	barrage.update(26.0)  # Clear cooldown
	barrage.activate(102, Vector3(0, 0, 0))
	var data := barrage.to_dict()
	_assert(data.has("marked_target_id"), "Serialization includes marked_target_id")
	_assert(data.has("total_barrages"), "Serialization includes stats")

	var barrage2 := CoordinatedBarrageAbility.new()
	barrage2.from_dict(data)
	_assert_eq(barrage2.get_marked_target(), 102, "Deserialized marked target matches")

	# Test stats
	var stats := barrage.get_stats()
	_assert(stats.has("total_barrages"), "Stats include total barrages")
	_assert(stats.has("total_bonus_damage"), "Stats include bonus damage")
	_assert(stats.has("targets_killed_while_marked"), "Stats include kills")
	_log_output("CoordinatedBarrage Stats: %s" % str(stats))

	# Test configuration
	var config := barrage.get_config()
	_assert_eq(config["hotkey"], "V", "Hotkey is V")
	_assert_approx(config["damage_bonus"], 0.75, 0.01, "Damage bonus is 75%")
	_assert_approx(config["duration"], 8.0, 0.01, "Duration is 8s")


# =============================================================================
# FRACTAL MOVEMENT ABILITY TESTS
# =============================================================================

func _test_fractal_movement_ability() -> void:
	var fractal := FractalMovementAbility.new()

	# Test registration
	fractal.register_unit(1)
	fractal.register_unit(2)

	_assert(fractal.has_fractal_movement(1), "Unit 1 has fractal movement")
	_assert_eq(fractal.get_evasion_chance(1), 0.0, "Initial evasion is 0")

	# Test movement tracking - simulate moving unit
	var positions := {1: Vector3(0, 0, 0), 2: Vector3(10, 0, 0)}
	fractal.update(0.1, positions)

	# Move unit in one direction
	positions[1] = Vector3(5, 0, 0)
	fractal.update(0.1, positions)

	# Change direction sharply
	positions[1] = Vector3(5, 0, 5)
	fractal.update(0.1, positions)

	# Change direction again
	positions[1] = Vector3(0, 0, 5)
	fractal.update(0.1, positions)

	# Evasion should have built up from direction changes
	var evasion := fractal.get_evasion_chance(1)
	_assert_gt(evasion, 0.0, "Evasion > 0 after direction changes")
	_log_output("FractalMovement: Evasion after direction changes = %.1f%%" % (evasion * 100))

	# Test evasion roll
	var result := fractal.roll_evasion(1, 100.0)
	_assert(result.has("evaded"), "Roll result has evaded flag")
	_assert(result.has("damage"), "Roll result has damage")

	# Test evasion stats
	var stats := fractal.get_evasion_stats(1)
	_assert(stats.has("evades"), "Stats include evades")
	_assert(stats.has("hits"), "Stats include hits")
	_assert(stats.has("rate"), "Stats include rate")

	# Test max evasion cap (35%)
	_assert_lt(evasion, 0.36, "Evasion capped at 35%")

	# Test unregistration
	fractal.unregister_unit(1)
	_assert(not fractal.has_fractal_movement(1), "Unit 1 no longer has fractal movement")

	# Test serialization
	fractal.register_unit(10)
	positions[10] = Vector3(0, 0, 0)
	fractal.update(0.1, positions)
	positions[10] = Vector3(5, 0, 0)
	fractal.update(0.1, positions)

	var data := fractal.to_dict()
	_assert(data.has("unit_data"), "Serialization includes unit_data")
	_assert(data.has("total_evades"), "Serialization includes stats")

	var fractal2 := FractalMovementAbility.new()
	fractal2.from_dict(data)
	_assert(fractal2.has_fractal_movement(10), "Deserialized unit has fractal movement")

	# Test configuration
	var config := fractal.get_config()
	_assert_approx(config["base_evasion"], 0.05, 0.01, "Base evasion is 5%")
	_assert_approx(config["max_evasion"], 0.35, 0.01, "Max evasion is 35%")


# =============================================================================
# MASS PRODUCTION ABILITY TESTS
# =============================================================================

func _test_mass_production_ability() -> void:
	var mass := MassProductionAbility.new()

	# Test registration - single factory (no bonus)
	mass.register_factory(1)
	_assert_eq(mass.get_controlled_factories(), 1, "1 factory controlled")
	_assert(not mass.is_bonus_active(), "Bonus not active with 1 factory")
	_assert_approx(mass.get_production_speed_multiplier(), 1.0, 0.01, "Speed multiplier is 1.0x")

	# Test with multiple factories (bonus active)
	mass.register_factory(2)
	_assert_eq(mass.get_controlled_factories(), 2, "2 factories controlled")
	_assert(mass.is_bonus_active(), "Bonus active with 2 factories")
	_assert_gt(mass.get_production_speed_multiplier(), 1.0, "Speed multiplier > 1.0x")
	_log_output("MassProduction: 2 factories = %.2fx speed" % mass.get_production_speed_multiplier())

	# Test with more factories
	mass.register_factory(3)
	mass.register_factory(4)
	var speed := mass.get_production_speed_multiplier()
	_assert_gt(speed, 1.3, "Speed multiplier > 1.3x with 4 factories")
	_log_output("MassProduction: 4 factories = %.2fx speed" % speed)

	# Test max speed cap (2.5x)
	for i in range(5, 20):
		mass.register_factory(i)
	_assert_lt(mass.get_production_speed_multiplier(), 2.51, "Speed capped at 2.5x")

	# Test production time calculation
	var base_time := 10.0
	var actual_time := mass.calculate_production_time(base_time)
	_assert_lt(actual_time, base_time, "Production time reduced")
	_log_output("MassProduction: %.1fs base -> %.1fs actual" % [base_time, actual_time])

	# Test factory deactivation
	mass.set_factory_active(1, false)
	var speed_after := mass.get_production_speed_multiplier()
	_assert_lt(speed_after, speed, "Speed reduced after factory deactivated")

	# Test production recording
	mass.record_production(2, 10.0)
	var stats := mass.get_stats()
	_assert_eq(stats["units_produced"], 1, "1 unit produced recorded")
	_assert_gt(stats["total_time_saved"], 0.0, "Time saved recorded")

	# Test serialization
	var data := mass.to_dict()
	_assert(data.has("factory_data"), "Serialization includes factory_data")
	_assert(data.has("current_multiplier"), "Serialization includes multiplier")

	var mass2 := MassProductionAbility.new()
	mass2.from_dict(data)
	_assert_approx(mass2.get_production_speed_multiplier(), mass.get_production_speed_multiplier(), 0.01, "Deserialized multiplier matches")

	# Test configuration
	var config := mass.get_config()
	_assert_approx(config["speed_per_factory"], 0.15, 0.01, "Speed per factory is 15%")
	_assert_approx(config["max_speed_multiplier"], 2.5, 0.01, "Max multiplier is 2.5x")


# =============================================================================
# ACROBATIC STRIKE ABILITY TESTS
# =============================================================================

func _test_acrobatic_strike_ability() -> void:
	var acro := AcrobaticStrikeAbility.new()

	# Set up callbacks
	var enemies_hit: Array = []
	var unit_positions: Dictionary = {1: Vector3(0, 0, 0), 2: Vector3(50, 0, 0)}

	acro.set_get_enemies_in_radius(func(pos: Vector3, radius: float) -> Array:
		var result: Array = []
		# Simulate an enemy at the landing zone
		result.append({"id": 100, "position": pos + Vector3(1, 0, 0)})
		return result
	)
	acro.set_apply_damage(func(target_id: int, damage: float) -> void:
		enemies_hit.append({"id": target_id, "damage": damage})
	)
	acro.set_unit_position(func(unit_id: int, pos: Vector3) -> void:
		unit_positions[unit_id] = pos
	)

	# Test registration
	acro.register_unit(1)
	acro.register_unit(2)

	# Test initial state
	_assert(not acro.is_on_cooldown(), "Not on cooldown initially")
	_assert_eq(acro.get_leaping_count(), 0, "No units leaping initially")

	# Test activation validation
	var validation := acro.can_activate()
	_assert(validation["can_activate"], "Can activate initially")

	# Test leap activation
	var activated := acro.activate_leap(1, Vector3(0, 0, 0), Vector3(15, 0, 0))
	_assert(activated, "Leap activation succeeded")
	_assert(acro.is_leaping(1), "Unit 1 is leaping")
	_assert(acro.is_on_cooldown(), "On cooldown after activation")

	# Test leap progress
	var progress := acro.get_leap_progress(1)
	_assert_approx(progress, 0.0, 0.1, "Initial progress is ~0")

	# Update leap partway
	acro.update(0.4)  # Half of leap duration (0.8s)
	progress = acro.get_leap_progress(1)
	_assert_gt(progress, 0.4, "Progress increased after update")
	_assert_lt(progress, 0.6, "Progress is mid-leap")

	# Check unit position during leap (should be elevated)
	var mid_pos: Vector3 = unit_positions[1]
	_assert_gt(mid_pos.y, 0.0, "Unit elevated during leap")
	_log_output("AcrobaticStrike: Mid-leap height = %.1f" % mid_pos.y)

	# Complete the leap
	acro.update(0.5)  # Finish the leap
	_assert(not acro.is_leaping(1), "Unit 1 finished leaping")
	_assert_gt(enemies_hit.size(), 0, "Enemies were hit on landing")
	_log_output("AcrobaticStrike: Hit %d enemies on landing" % enemies_hit.size())

	# Test cooldown blocking
	validation = acro.can_activate()
	_assert(not validation["can_activate"], "Cannot activate while on cooldown")

	# Test cooldown decay
	acro.update(16.0)  # Cooldown is 15s
	_assert(not acro.is_on_cooldown(), "Cooldown expired")

	# Test range clamping (leap range is 20)
	acro.activate_leap(2, Vector3(50, 0, 0), Vector3(100, 0, 0))  # Try to leap 50 units
	acro.update(1.0)  # Complete leap
	var final_pos: Vector3 = unit_positions[2]
	_assert_lt(final_pos.x, 75.0, "Leap range was clamped")

	# Test serialization
	acro.update(16.0)  # Clear cooldown
	acro.activate_leap(1, Vector3(0, 0, 0), Vector3(10, 0, 0))
	var data := acro.to_dict()
	_assert(data.has("leaping_units"), "Serialization includes leaping_units")
	_assert(data.has("total_leaps"), "Serialization includes stats")

	var acro2 := AcrobaticStrikeAbility.new()
	acro2.from_dict(data)
	_assert(acro2.is_leaping(1), "Deserialized unit is still leaping")

	# Test stats
	var stats := acro.get_stats()
	_assert(stats.has("total_leaps"), "Stats include total leaps")
	_assert(stats.has("total_damage_dealt"), "Stats include damage dealt")
	_log_output("AcrobaticStrike Stats: %s" % str(stats))

	# Test configuration
	var config := acro.get_config()
	_assert_eq(config["hotkey"], "B", "Hotkey is B")
	_assert_approx(config["landing_damage"], 75.0, 0.1, "Landing damage is 75")
	_assert_approx(config["leap_range"], 20.0, 0.1, "Leap range is 20")
