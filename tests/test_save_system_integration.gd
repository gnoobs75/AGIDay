extends Node
## Integration tests for the complete Data Persistence & Save System
## Tests the full save/load cycle with all components working together

var _tests_passed: int = 0
var _tests_failed: int = 0
var _test_results: Array[Dictionary] = []


func _ready() -> void:
	print("\n========================================")
	print("  SAVE SYSTEM INTEGRATION TESTS")
	print("========================================\n")

	await _run_all_tests()
	_print_summary()


func _run_all_tests() -> void:
	# Full Cycle Tests
	_run_test("test_full_save_load_cycle", await test_full_save_load_cycle())
	_run_test("test_save_modify_save_cycle", await test_save_modify_save_cycle())
	_run_test("test_snapshot_delta_integration", await test_snapshot_delta_integration())

	# Component Registry Integration
	_run_test("test_component_serialization_roundtrip", test_component_serialization_roundtrip)
	_run_test("test_entity_persistence", await test_entity_persistence())

	# Backup Integration
	_run_test("test_save_creates_backup", await test_save_creates_backup())
	_run_test("test_corruption_recovery_full_cycle", await test_corruption_recovery_full_cycle())

	# Performance Validation
	_run_test("test_save_performance_target", await test_save_performance_target())
	_run_test("test_load_performance_target", await test_load_performance_target())
	_run_test("test_memory_usage_target", await test_memory_usage_target())
	_run_test("test_file_size_target", await test_file_size_target())

	# Data Integrity
	_run_test("test_zero_data_loss", await test_zero_data_loss())
	_run_test("test_checksum_validation", await test_checksum_validation())

	# Stress Tests
	_run_test("test_large_entity_count", await test_large_entity_count())
	_run_test("test_multiple_save_load_cycles", await test_multiple_save_load_cycles())


func _run_test(test_name: String, result) -> void:
	var passed: bool = result if result is bool else false

	if passed:
		_tests_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_tests_failed += 1
		print("[FAIL] %s" % test_name)

	_test_results.append({"name": test_name, "passed": passed})


func _print_summary() -> void:
	print("\n========================================")
	print("           TEST SUMMARY")
	print("========================================")
	print("Total:  %d" % (_tests_passed + _tests_failed))
	print("Passed: %d" % _tests_passed)
	print("Failed: %d" % _tests_failed)

	if _tests_failed > 0:
		print("\nFailed tests:")
		for result in _test_results:
			if not result["passed"]:
				print("  - %s" % result["name"])

	print("========================================\n")


# ============================================
# FULL CYCLE TESTS
# ============================================

func test_full_save_load_cycle() -> bool:
	var save_name := "integration_full_cycle"

	# Create game state with all component types
	var game_state := _create_test_game_state(100)

	# Save
	var save_result := SaveManager.save_game(save_name, game_state)
	if not save_result.success:
		push_error("Save failed: %s" % save_result.error_message)
		return false

	# Load
	var load_result := SaveManager.load_game(save_name)
	if not load_result.success:
		push_error("Load failed: %s" % load_result.error_message)
		SaveManager.delete_save_with_backups(save_name)
		return false

	# Verify data integrity
	var entities_match := _verify_entities(game_state, load_result.snapshot)

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return entities_match


func test_save_modify_save_cycle() -> bool:
	var save_name := "integration_modify_cycle"

	# Initial state
	var state1 := _create_test_game_state(50)
	SaveManager.save_game(save_name, state1)

	# Load, modify, save again
	var load1 := SaveManager.load_game(save_name)
	if not load1.success:
		return false

	# Modify entities
	var modified_state := load1.snapshot.duplicate(true)
	modified_state["entities"]["new_entity_999"] = {"health": 999, "modified": true}
	modified_state["current_wave"] = 10

	# Save modified state
	var save2 := SaveManager.save_game(save_name, modified_state)
	if not save2.success:
		return false

	# Load and verify modifications
	var load2 := SaveManager.load_game(save_name)
	var has_new_entity := load2.snapshot.get("entities", {}).has("new_entity_999")

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return has_new_entity


func test_snapshot_delta_integration() -> bool:
	SnapshotManager.clear()
	SnapshotManager.start_tracking()

	# Create initial snapshot
	var state1 := _create_test_game_state(20)
	SnapshotManager.create_snapshot(state1)

	# Record some changes
	SnapshotManager.record_entity_added("delta_entity_1", {"health": 100})
	SnapshotManager.record_resource_changed("gold", 0.0, 500.0)
	SnapshotManager.finalize_delta()

	# Export and save via SnapshotSystem
	var export_data := SnapshotManager.export_for_save()

	# Verify export has snapshot and deltas
	var has_snapshot := not export_data.get("snapshot", {}).is_empty()
	var has_deltas := not export_data.get("deltas", []).is_empty()

	SnapshotManager.stop_tracking()
	SnapshotManager.clear()

	return has_snapshot and has_deltas


# ============================================
# COMPONENT REGISTRY INTEGRATION
# ============================================

func test_component_serialization_roundtrip() -> bool:
	# Create a health component
	var health := HealthComponent.new()
	health.set_health(75.0, 100.0)

	# Serialize
	var data := health._to_dict()

	# Deserialize into new component
	var restored := HealthComponent.new()
	restored._from_dict(data)

	return (restored.get_current_health() == 75.0 and
			restored.get_max_health() == 100.0)


func test_entity_persistence() -> bool:
	var save_name := "integration_entity_persist"

	# Create game state with specific component data
	var game_state := {
		"player_faction": 2,
		"current_wave": 5,
		"entities": {
			"unit_001": {
				"HealthComponent": {"current_health": 75.0, "max_health": 100.0},
				"MovementComponent": {"position": {"x": 10.0, "y": 0.0, "z": 5.0}},
				"FactionComponent": {"faction_id": 2, "faction_name": "OptiForge Legion"}
			}
		}
	}

	# Save and load
	SaveManager.save_game(save_name, game_state)
	var load_result := SaveManager.load_game(save_name)

	if not load_result.success:
		return false

	# Verify component data preserved
	var entities: Dictionary = load_result.snapshot.get("entities", {})
	var unit_data: Dictionary = entities.get("unit_001", {})
	var health_data: Dictionary = unit_data.get("HealthComponent", {})

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return health_data.get("current_health") == 75.0


# ============================================
# BACKUP INTEGRATION
# ============================================

func test_save_creates_backup() -> bool:
	var save_name := "integration_backup_test"

	# Ensure auto-backup is enabled
	SaveManager.set_auto_backup_enabled(true)

	# Save
	var game_state := _create_test_game_state(10)
	SaveManager.save_game(save_name, game_state)

	# Check backup was created
	var backups := SaveManager.get_backups(save_name)
	var has_backup := backups.size() > 0

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return has_backup


func test_corruption_recovery_full_cycle() -> bool:
	var save_name := "integration_corruption_test"

	# Create save with backup
	var game_state := _create_test_game_state(20)
	game_state["unique_marker"] = "recovery_test_marker"
	SaveManager.save_game(save_name, game_state)

	# Verify backup exists
	var backups := SaveManager.get_backups(save_name)
	if backups.is_empty():
		push_error("No backup created")
		SaveManager.delete_save_with_backups(save_name)
		return false

	# "Corrupt" the main save
	var save_path := SaveFormat.get_save_path(save_name)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_buffer(PackedByteArray([0xFF, 0xFE, 0xFD]))
		file.close()

	# Try to load (should auto-recover from backup)
	var load_result := SaveManager.load_game(save_name)

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return load_result.success


# ============================================
# PERFORMANCE VALIDATION
# ============================================

func test_save_performance_target() -> bool:
	var save_name := "integration_perf_save"

	# Create typical game state (5000 units target)
	var game_state := _create_test_game_state(5000)

	# Measure save time
	var start := Time.get_ticks_msec()
	var result := SaveManager.save_game(save_name, game_state)
	var save_time := Time.get_ticks_msec() - start

	print("  Save time (5000 entities): %dms (target: <1000ms)" % save_time)

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	# Target: <1 second (1000ms)
	return result.success and save_time < 1000


func test_load_performance_target() -> bool:
	var save_name := "integration_perf_load"

	# Create and save state
	var game_state := _create_test_game_state(5000)
	SaveManager.save_game(save_name, game_state)

	# Measure load time
	var start := Time.get_ticks_msec()
	var result := SaveManager.load_game(save_name)
	var load_time := Time.get_ticks_msec() - start

	print("  Load time (5000 entities): %dms (target: <2000ms)" % load_time)

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	# Target: <2 seconds (2000ms)
	return result.success and load_time < 2000


func test_memory_usage_target() -> bool:
	# Create game state and measure memory
	var game_state := _create_test_game_state(5000)

	# Estimate memory usage via serialization size
	var bytes := var_to_bytes(game_state)
	var size_mb := float(bytes.size()) / (1024 * 1024)

	print("  Memory estimate (5000 entities): %.2fMB (target: <500MB)" % size_mb)

	# Target: <500MB
	return size_mb < 500


func test_file_size_target() -> bool:
	var save_name := "integration_perf_size"

	# Create and save state
	var game_state := _create_test_game_state(5000)
	var result := SaveManager.save_game(save_name, game_state)

	var file_size_mb := float(result.file_size) / (1024 * 1024)
	print("  File size (5000 entities): %.2fMB (target: <50MB)" % file_size_mb)

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	# Target: <50MB on disk
	return result.success and file_size_mb < 50


# ============================================
# DATA INTEGRITY TESTS
# ============================================

func test_zero_data_loss() -> bool:
	var save_name := "integration_zero_loss"

	# Create specific test data
	var test_entities := {}
	for i in range(100):
		test_entities["entity_%d" % i] = {
			"health": 100.0 - i,
			"position": Vector3(i, i * 2, i * 3),
			"unique_id": "uid_%d" % i
		}

	var game_state := {
		"entities": test_entities,
		"resources": {"gold": 12345, "metal": 67890},
		"player_faction": 3
	}

	# Save
	SaveManager.save_game(save_name, game_state)

	# Load
	var load_result := SaveManager.load_game(save_name)
	if not load_result.success:
		SaveManager.delete_save_with_backups(save_name)
		return false

	# Verify every entity
	var loaded_entities: Dictionary = load_result.snapshot.get("entities", {})
	var all_match := true

	for entity_id in test_entities:
		if not loaded_entities.has(entity_id):
			push_error("Missing entity: %s" % entity_id)
			all_match = false
			break

		var original = test_entities[entity_id]
		var loaded = loaded_entities[entity_id]

		if original.get("health") != loaded.get("health"):
			all_match = false
			break
		if original.get("unique_id") != loaded.get("unique_id"):
			all_match = false
			break

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return all_match


func test_checksum_validation() -> bool:
	var save_name := "integration_checksum"

	# Save valid data
	var game_state := _create_test_game_state(50)
	SaveManager.save_game(save_name, game_state)

	# Verify save is valid
	var validation := SaveManager.validate_save(save_name)
	var is_valid := validation.get("valid", false)

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return is_valid


# ============================================
# STRESS TESTS
# ============================================

func test_large_entity_count() -> bool:
	var save_name := "integration_large_count"

	# Create 10000 entities (stress test)
	var game_state := _create_test_game_state(10000)

	var save_result := SaveManager.save_game(save_name, game_state)
	if not save_result.success:
		return false

	var load_result := SaveManager.load_game(save_name)

	# Verify count
	var loaded_count := load_result.snapshot.get("entities", {}).size()
	print("  Large entity test: Saved %d, Loaded %d" % [10000, loaded_count])

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return loaded_count == 10000


func test_multiple_save_load_cycles() -> bool:
	var save_name := "integration_cycles"
	var cycles := 5

	for i in range(cycles):
		var game_state := _create_test_game_state(100)
		game_state["cycle"] = i

		var save_result := SaveManager.save_game(save_name, game_state)
		if not save_result.success:
			SaveManager.delete_save_with_backups(save_name)
			return false

		var load_result := SaveManager.load_game(save_name)
		if not load_result.success:
			SaveManager.delete_save_with_backups(save_name)
			return false

	# Cleanup
	SaveManager.delete_save_with_backups(save_name)

	return true


# ============================================
# HELPER FUNCTIONS
# ============================================

func _create_test_game_state(entity_count: int) -> Dictionary:
	var entities := {}

	for i in range(entity_count):
		entities["entity_%d" % i] = {
			"HealthComponent": {
				"current_health": 100.0 - (i % 50),
				"max_health": 100.0
			},
			"MovementComponent": {
				"position": Vector3(randf() * 100, 0, randf() * 100),
				"velocity": Vector3.ZERO,
				"max_speed": 10.0
			},
			"FactionComponent": {
				"faction_id": (i % 5) + 1,
				"faction_name": "Faction %d" % ((i % 5) + 1)
			}
		}

	return {
		"player_faction": 1,
		"current_wave": 5,
		"difficulty": 2,
		"game_time": 300.0,
		"play_time": 600.0,
		"entity_count": entity_count,
		"entities": entities,
		"systems": {},
		"world_state": {
			"resources": {"gold": 1000, "metal": 500},
			"district_control": {"district_1": 1, "district_2": 2}
		}
	}


func _verify_entities(original: Dictionary, loaded: Dictionary) -> bool:
	var original_entities: Dictionary = original.get("entities", {})
	var loaded_entities: Dictionary = loaded.get("entities", {})

	if original_entities.size() != loaded_entities.size():
		push_error("Entity count mismatch: %d vs %d" % [
			original_entities.size(), loaded_entities.size()
		])
		return false

	for entity_id in original_entities:
		if not loaded_entities.has(entity_id):
			push_error("Missing entity: %s" % entity_id)
			return false

	return true
