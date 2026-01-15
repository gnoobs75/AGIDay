extends SceneTree
## Phase 6 Systems Test Suite
## Tests the victory, replay, progression, and resource systems.

var _test_count: int = 0
var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	print("=" .repeat(60))
	print("PHASE 6 SYSTEMS TEST SUITE")
	print("=" .repeat(60))

	run_all_tests()
	quit()


func run_all_tests() -> void:
	print("\n[END GAME MANAGER TESTS]")
	_test_end_game_manager()

	print("\n[VICTORY CONDITION SYSTEM TESTS]")
	_test_victory_condition_system()

	print("\n[REPLAY RECORDER TESTS]")
	_test_replay_recorder()

	print("\n[REPLAY VERIFIER TESTS]")
	_test_replay_verifier()

	print("\n[AETHER SWARM PROGRESSION TESTS]")
	_test_aether_progression()

	print("\n[RESOURCE INTEGRATION TESTS]")
	_test_resource_integration()

	print("\n[TERRAIN FLATTENING TESTS]")
	_test_terrain_flattening()

	print("\n[PRODUCTION COST VALIDATOR TESTS]")
	_test_production_cost_validator()

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


# =============================================================================
# END GAME MANAGER TESTS
# =============================================================================

func _test_end_game_manager() -> void:
	var manager := EndGameManager.new()

	# Test initialization
	var factions: Array[int] = [1, 2, 3, 4]
	manager.initialize(1, factions)
	_assert_eq(manager.get_current_state(), EndGameManager.GameState.PLAYING, "Initial state is PLAYING")
	_assert(manager.is_faction_alive(1), "Player faction is alive")
	_assert(manager.is_faction_alive(2), "Enemy faction is alive")

	# Test victory handling
	manager.handle_victory(1)
	_assert(manager.is_faction_victorious(1), "Player marked victorious")
	_assert_eq(manager.get_current_state(), EndGameManager.GameState.VICTORY_SCREEN, "State changed to VICTORY_SCREEN")

	# Test serialization
	var data := manager.to_dict()
	_assert(data.has("current_state"), "Serialization includes state")
	_assert(data.has("faction_status"), "Serialization includes faction status")

	var manager2 := EndGameManager.new()
	manager2.from_dict(data)
	_assert_eq(manager2.get_current_state(), EndGameManager.GameState.VICTORY_SCREEN, "Deserialized state matches")


# =============================================================================
# VICTORY CONDITION SYSTEM TESTS
# =============================================================================

func _test_victory_condition_system() -> void:
	var system := VictoryConditionSystem.new()

	# Test initialization
	var factions: Array[int] = [1, 2, 3]
	system.initialize(1, factions, 64)
	_assert(not system.is_victory_achieved(), "No victory initially")
	_assert_eq(system.get_district_count(1), 0, "Initial district count is 0")

	# Test district updates
	system.update_faction_districts(1, 32)
	_assert_eq(system.get_domination_progress(1), 0.5, "Domination progress is 50%")

	# Test factory elimination
	system.update_faction_factories(2, 0)
	system.update_faction_units(2, 0)
	var result := system.check_now()
	_assert(system.is_faction_eliminated(2), "Faction 2 eliminated after losing factories")

	# Test serialization
	var data := system.to_dict()
	_assert(data.has("faction_districts"), "Serialization includes districts")

	var system2 := VictoryConditionSystem.new()
	system2.from_dict(data)
	_assert_eq(system2.get_district_count(1), 32, "Deserialized district count matches")


# =============================================================================
# REPLAY RECORDER TESTS
# =============================================================================

func _test_replay_recorder() -> void:
	var recorder := ReplayRecorder.new()

	# Test initialization
	var factions: Array[String] = ["faction_1", "faction_2"]
	recorder.start_recording(12345, 67890, factions, "faction_1", 1)
	_assert(recorder.is_recording(), "Recording started")
	_assert_ne(recorder.get_replay_id(), "", "Replay ID generated")

	# Test critical events
	recorder.record_unit_spawn(1, "drone", "faction_1", Vector3(10, 0, 20))
	recorder.record_unit_death(1, 5, Vector3(10, 0, 20))
	var stats := recorder.get_statistics()
	_assert_eq(stats["critical_events"], 2, "Critical events recorded")

	# Test victory recording
	recorder.record_victory("faction_1", "DISTRICT_DOMINATION", 300.0, 10)
	stats = recorder.get_statistics()
	_assert_eq(stats["victory_faction"], "faction_1", "Victory faction recorded")

	# Test stop recording
	var result := recorder.stop_recording()
	_assert(not recorder.is_recording(), "Recording stopped")


# =============================================================================
# REPLAY VERIFIER TESTS
# =============================================================================

func _test_replay_verifier() -> void:
	var verifier := ReplayVerifier.new()

	# Test loading from dict
	var replay_data := {
		"version": 1,
		"replay_id": "test_replay",
		"game_seed": 12345,
		"map_seed": 67890,
		"factions": ["faction_1", "faction_2"],
		"player_faction": "faction_1",
		"base_snapshot": {},
		"start_frame": 0,
		"end_frame": 1000,
		"duration_frames": 1000,
		"victory_faction": "faction_1",
		"victory_type": "DISTRICT_DOMINATION",
		"critical_events": []
	}

	_assert(verifier.load_from_dict(replay_data), "Loaded replay from dict")

	# Test metadata extraction
	var metadata := verifier.get_replay_metadata()
	_assert_eq(metadata["replay_id"], "test_replay", "Metadata replay_id correct")
	_assert_eq(metadata["victory_faction"], "faction_1", "Metadata victory_faction correct")

	# Test verification
	var result := verifier.verify()
	_assert(result.is_valid, "Basic replay passes verification")


# =============================================================================
# AETHER SWARM PROGRESSION TESTS
# =============================================================================

func _test_aether_progression() -> void:
	var progression := AetherSwarmProgression.new()

	# Test initial state
	_assert_eq(progression.get_tier(AetherSwarmProgression.XPPool.COMBAT), 0, "Initial combat tier is 0")
	_assert_eq(progression.get_xp(AetherSwarmProgression.XPPool.COMBAT), 0.0, "Initial combat XP is 0")

	# Test XP addition and tier unlock
	progression.add_combat_xp(1500.0)
	_assert_eq(progression.get_tier(AetherSwarmProgression.XPPool.COMBAT), 1, "Combat tier 1 unlocked at 1000+ XP")
	_assert(progression.is_buff_unlocked("combat_tier_1"), "Combat tier 1 buff unlocked")

	# Test buff effects
	var effects := progression.get_combined_effects()
	_assert_eq(effects["damage_multiplier"], 1.1, "Damage multiplier is 1.1x at tier 1")

	# Test economy progression
	progression.add_economy_xp(600.0)
	_assert_eq(progression.get_tier(AetherSwarmProgression.XPPool.ECONOMY), 1, "Economy tier 1 unlocked")
	_assert_eq(progression.get_ree_multiplier(), 1.1, "REE multiplier is 1.1x")

	# Test serialization
	var data := progression.to_dict()
	_assert(data.has("combat_xp"), "Serialization includes combat_xp")

	var prog2 := AetherSwarmProgression.new()
	prog2.from_dict(data)
	_assert_eq(prog2.get_tier(AetherSwarmProgression.XPPool.COMBAT), 1, "Deserialized tier matches")


# =============================================================================
# RESOURCE INTEGRATION TESTS
# =============================================================================

func _test_resource_integration() -> void:
	var integration := ResourceIntegration.new()

	# Test faction initialization
	integration.initialize_faction(1)
	_assert_eq(integration.get_district_count(1), 0, "Initial district count is 0")
	_assert_eq(integration.get_income_rate(1), 0.0, "Initial income rate is 0")

	# Test district capture
	integration.on_district_captured(1, 1)
	integration.on_district_captured(1, 2)
	_assert_eq(integration.get_district_count(1), 2, "District count updated")

	# Test production validation
	var can_produce := integration.validate_production(1, "drone")
	_assert(can_produce, "Can validate production (no manager = always true)")

	# Test unit cost lookup
	var cost := integration.get_unit_cost("tank")
	_assert(cost > 0, "Tank has production cost")

	# Test serialization
	var data := integration.to_dict()
	_assert(data.has("faction_district_counts"), "Serialization includes district counts")


# =============================================================================
# TERRAIN FLATTENING TESTS
# =============================================================================

func _test_terrain_flattening() -> void:
	var system := TerrainFlatteningSystem.new()

	# Test initialization
	system.initialize(100)
	_assert_eq(system.get_destruction_percentage(), 0.0, "Initial destruction is 0%")
	_assert_eq(system.get_map_stage(), TerrainFlatteningSystem.MapStage.EARLY_GAME, "Initial stage is EARLY_GAME")

	# Test building disassembly
	var building_data := {
		"type": "industrial",
		"size": "medium",
		"damage_state": "intact",
		"position": Vector3(100, 0, 100),
		"bounds": AABB(Vector3(95, 0, 95), Vector3(10, 20, 10))
	}

	_assert(system.start_building_disassembly(1, building_data), "Disassembly started")
	_assert(system.is_disassembling(1), "Building is being disassembled")

	# Test wreck harvesting
	var wreck_data := {
		"type": "debris",
		"size": 5,
		"position": Vector3(200, 0, 200),
		"original_building_type": "residential"
	}

	_assert(system.start_wreck_harvesting(1, wreck_data), "Harvesting started")
	_assert(system.is_harvesting(1), "Wreck is being harvested")

	# Test serialization
	var data := system.to_dict()
	_assert(data.has("total_buildings"), "Serialization includes total_buildings")


# =============================================================================
# PRODUCTION COST VALIDATOR TESTS
# =============================================================================

func _test_production_cost_validator() -> void:
	var validator := ProductionCostValidator.new()

	# Test unit cost retrieval
	var drone_cost := validator.get_ree_cost("drone")
	_assert_eq(drone_cost, 50.0, "Drone costs 50 REE")

	var tank_cost := validator.get_ree_cost("tank")
	_assert_eq(tank_cost, 200.0, "Tank costs 200 REE")

	# Test custom cost setting
	validator.set_unit_cost("custom_unit", 999.0, 10.0, 5.0)
	_assert_eq(validator.get_ree_cost("custom_unit"), 999.0, "Custom unit cost set")

	# Test faction modifiers
	validator.set_faction_modifier(1, 0.9)  # 10% discount
	var effective_cost := validator.get_effective_cost(1, "drone")
	_assert_eq(effective_cost, 45.0, "Faction modifier applied (90% of 50)")

	# Test validation (without resource manager, should pass)
	var can_afford := validator.can_afford(1, "drone")
	_assert(can_afford, "Can afford without resource manager")

	# Test analytics
	var analytics := validator.get_analytics(1)
	_assert(analytics is Dictionary, "Analytics returns dictionary")

	# Test serialization
	var data := validator.to_dict()
	_assert(data.has("unit_costs"), "Serialization includes unit_costs")
