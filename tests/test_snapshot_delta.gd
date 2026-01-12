extends Node
## Test suite for Snapshot, Delta, and Backup systems

var _tests_passed: int = 0
var _tests_failed: int = 0
var _test_results: Array[Dictionary] = []


func _ready() -> void:
	print("\n========================================")
	print("   SNAPSHOT/DELTA TEST SUITE")
	print("========================================\n")

	await _run_all_tests()
	_print_summary()


func _run_all_tests() -> void:
	# Snapshot Tests
	_run_test("test_snapshot_creation", test_snapshot_creation)
	_run_test("test_snapshot_serialization", test_snapshot_serialization)
	_run_test("test_snapshot_memory_estimation", test_snapshot_memory_estimation)

	# Delta Tests
	_run_test("test_delta_creation", test_delta_creation)
	_run_test("test_delta_changes", test_delta_changes)
	_run_test("test_delta_serialization", test_delta_serialization)
	_run_test("test_delta_apply", test_delta_apply)
	_run_test("test_delta_revert", test_delta_revert)
	_run_test("test_delta_comparison", test_delta_comparison)

	# SnapshotManager Tests
	_run_test("test_manager_snapshot_lifecycle", await test_manager_snapshot_lifecycle())
	_run_test("test_manager_delta_tracking", await test_manager_delta_tracking())
	_run_test("test_manager_snapshot_cleanup", await test_manager_snapshot_cleanup())
	_run_test("test_manager_state_reconstruction", await test_manager_state_reconstruction())
	_run_test("test_manager_export_import", await test_manager_export_import())

	# Backup Tests
	_run_test("test_backup_creation", await test_backup_creation())
	_run_test("test_backup_rotation", await test_backup_rotation())
	_run_test("test_backup_restoration", await test_backup_restoration())
	_run_test("test_backup_validation", await test_backup_validation())
	_run_test("test_corruption_recovery", await test_corruption_recovery())

	# Performance Tests
	_run_test("test_snapshot_performance", test_snapshot_performance)
	_run_test("test_delta_performance", test_delta_performance)


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
# SNAPSHOT TESTS
# ============================================

func test_snapshot_creation() -> bool:
	var game_state := {
		"entities": {"entity_1": {"health": 100}},
		"resources": {"gold": 500},
		"district_control": {"district_1": 1}
	}

	var snapshot := Snapshot.create_from_state(game_state, 100, 5, 60.0, Snapshot.TriggerType.WAVE_COMPLETE)

	return (snapshot.frame_number == 100 and
			snapshot.wave_number == 5 and
			snapshot.game_time == 60.0 and
			snapshot.trigger == Snapshot.TriggerType.WAVE_COMPLETE and
			snapshot.entities.has("entity_1") and
			snapshot.resources.get("gold") == 500)


func test_snapshot_serialization() -> bool:
	var game_state := {
		"entities": {"test": {"value": 42}},
		"resources": {"metal": 100}
	}

	var original := Snapshot.create_from_state(game_state, 50, 3, 30.0)
	original.snapshot_id = 123

	var data := original.to_dict()
	var restored := Snapshot.from_dict(data)

	return (restored.snapshot_id == original.snapshot_id and
			restored.frame_number == original.frame_number and
			restored.wave_number == original.wave_number and
			restored.entities.get("test", {}).get("value") == 42)


func test_snapshot_memory_estimation() -> bool:
	var game_state := {
		"entities": {},
		"resources": {}
	}

	# Add many entities
	for i in range(100):
		game_state["entities"]["entity_%d" % i] = {
			"health": 100,
			"position": Vector3(i, 0, 0)
		}

	var snapshot := Snapshot.create_from_state(game_state, 0, 0, 0.0)
	var size := snapshot.get_memory_size()

	# Should be a reasonable size estimate
	return size > 0 and size < 1024 * 1024  # Less than 1MB for 100 entities


# ============================================
# DELTA TESTS
# ============================================

func test_delta_creation() -> bool:
	var delta := Delta.new()
	delta.delta_id = 1
	delta.frame_number = 100
	delta.base_snapshot_id = 5

	return delta.delta_id == 1 and delta.frame_number == 100 and delta.is_empty()


func test_delta_changes() -> bool:
	var delta := Delta.new()

	delta.record_entity_added("entity_1", {"health": 100})
	delta.record_entity_removed("entity_2", {"health": 50})
	delta.record_component_changed("entity_3", "HealthComponent", "current_health", 100.0, 80.0)
	delta.record_resource_changed("gold", 500.0, 600.0)
	delta.record_district_changed("district_1", 1, 2)

	return delta.get_change_count() == 5 and not delta.is_empty()


func test_delta_serialization() -> bool:
	var delta := Delta.new()
	delta.delta_id = 42
	delta.frame_number = 200
	delta.record_entity_added("test_entity", {"data": "value"})
	delta.record_resource_changed("metal", 0.0, 100.0)

	var data := delta.to_dict()
	var restored := Delta.from_dict(data)

	return (restored.delta_id == 42 and
			restored.frame_number == 200 and
			restored.get_change_count() == 2)


func test_delta_apply() -> bool:
	# Create base snapshot
	var game_state := {
		"entities": {"entity_1": {"health": 100}},
		"resources": {"gold": 500}
	}
	var snapshot := Snapshot.create_from_state(game_state, 0, 0, 0.0)

	# Create delta with changes
	var delta := Delta.new()
	delta.add_change(Delta.ChangeType.MODIFY, "resource", "gold", "amount", 500, 600)
	delta.add_change(Delta.ChangeType.ADD, "entity", "entity_2", "", null, {"health": 50})

	# Apply delta
	var new_snapshot := delta.apply_to_snapshot(snapshot)

	return (new_snapshot.resources.get("gold") == 600 and
			new_snapshot.entities.has("entity_2"))


func test_delta_revert() -> bool:
	# Create snapshot with entity
	var game_state := {
		"entities": {"entity_1": {"health": 100}, "entity_2": {"health": 50}},
		"resources": {"gold": 600}
	}
	var snapshot := Snapshot.create_from_state(game_state, 10, 0, 0.0)

	# Create delta that was applied to reach this state
	var delta := Delta.new()
	delta.add_change(Delta.ChangeType.MODIFY, "resource", "gold", "amount", 500, 600)
	delta.add_change(Delta.ChangeType.ADD, "entity", "entity_2", "", null, {"health": 50})

	# Revert delta
	var reverted := delta.revert_from_snapshot(snapshot)

	return (reverted.resources.get("gold") == 500 and
			not reverted.entities.has("entity_2"))


func test_delta_comparison() -> bool:
	# Create two snapshots
	var old_state := {
		"entities": {"entity_1": {"health": 100}},
		"resources": {"gold": 500},
		"district_control": {"d1": 1}
	}
	var old_snapshot := Snapshot.create_from_state(old_state, 0, 0, 0.0)
	old_snapshot.snapshot_id = 1

	var new_state := {
		"entities": {"entity_1": {"health": 80}, "entity_2": {"health": 50}},
		"resources": {"gold": 600},
		"district_control": {"d1": 2}
	}
	var new_snapshot := Snapshot.create_from_state(new_state, 10, 0, 0.0)

	# Create delta from comparison
	var delta := Delta.create_from_snapshots(old_snapshot, new_snapshot)

	# Should detect: entity_1 modified, entity_2 added, gold changed, district changed
	return delta.get_change_count() >= 4


# ============================================
# SNAPSHOT MANAGER TESTS
# ============================================

func test_manager_snapshot_lifecycle() -> bool:
	SnapshotManager.clear()
	SnapshotManager.start_tracking()

	var game_state := {
		"entities": {"test": {"value": 1}},
		"resources": {}
	}

	var snapshot := SnapshotManager.create_snapshot(game_state, Snapshot.TriggerType.MANUAL)

	var is_valid := (snapshot != null and
			SnapshotManager.get_snapshot_count() == 1 and
			SnapshotManager.get_latest_snapshot() == snapshot)

	SnapshotManager.stop_tracking()
	SnapshotManager.clear()

	return is_valid


func test_manager_delta_tracking() -> bool:
	SnapshotManager.clear()
	SnapshotManager.start_tracking()

	# Create initial snapshot
	SnapshotManager.create_snapshot({"entities": {}})

	# Record some changes
	SnapshotManager.record_entity_added("new_entity", {"health": 100})
	SnapshotManager.record_resource_changed("gold", 0.0, 100.0)
	SnapshotManager.finalize_delta()

	var deltas := SnapshotManager.get_deltas_since_snapshot()
	var has_delta := deltas.size() > 0

	SnapshotManager.stop_tracking()
	SnapshotManager.clear()

	return has_delta


func test_manager_snapshot_cleanup() -> bool:
	SnapshotManager.clear()

	# Create more than MAX_SNAPSHOTS
	for i in range(12):
		SnapshotManager.create_snapshot({
			"entities": {"entity_%d" % i: {"value": i}}
		})

	# Should only keep MAX_SNAPSHOTS (10)
	var count := SnapshotManager.get_snapshot_count()
	SnapshotManager.clear()

	return count <= SnapshotManagerClass.MAX_SNAPSHOTS


func test_manager_state_reconstruction() -> bool:
	SnapshotManager.clear()
	SnapshotManager.start_tracking()

	# Create snapshot at frame 0
	SnapshotManager.create_snapshot({
		"entities": {"entity_1": {"health": 100}},
		"resources": {"gold": 500}
	})

	# Simulate some frames with deltas
	for i in range(5):
		SnapshotManager._frame_number = i + 1
		SnapshotManager.record_resource_changed("gold", 500.0 + i * 10, 500.0 + (i + 1) * 10)
		SnapshotManager.finalize_delta()

	# Try to get state at frame 3
	var state := SnapshotManager.get_state_at_frame(3)

	SnapshotManager.stop_tracking()
	SnapshotManager.clear()

	return not state.is_empty()


func test_manager_export_import() -> bool:
	SnapshotManager.clear()

	# Create some state
	SnapshotManager.create_snapshot({
		"entities": {"test": {"value": 42}}
	})

	# Export
	var exported := SnapshotManager.export_for_save()

	# Clear and reimport
	SnapshotManager.clear()

	var snapshot_data: Dictionary = exported.get("snapshot", {})
	var delta_list: Array[Dictionary] = []
	for d in exported.get("deltas", []):
		if d is Dictionary:
			delta_list.append(d)

	SnapshotManager.load_from_save_data(snapshot_data, delta_list)

	var has_snapshot := SnapshotManager.get_latest_snapshot() != null
	SnapshotManager.clear()

	return has_snapshot


# ============================================
# BACKUP TESTS
# ============================================

func test_backup_creation() -> bool:
	var backup_manager := BackupManagerClass.new()

	# Create a test save first
	SaveManager.save_game("test_backup_create", {"entities": {}})

	# Create backup
	var success := backup_manager.create_backup("test_backup_create")
	var has_backup := backup_manager.has_backup("test_backup_create", 1)

	# Cleanup
	SaveManager.delete_save("test_backup_create")
	backup_manager.delete_all_backups("test_backup_create")

	return success and has_backup


func test_backup_rotation() -> bool:
	var backup_manager := BackupManagerClass.new()

	# Create a test save
	SaveManager.save_game("test_backup_rotate", {"entities": {}})

	# Create multiple backups
	for i in range(4):
		backup_manager.create_backup("test_backup_rotate")

	# Should have exactly MAX_BACKUPS
	var available := backup_manager.get_available_backups("test_backup_rotate")

	# Cleanup
	SaveManager.delete_save("test_backup_rotate")
	backup_manager.delete_all_backups("test_backup_rotate")

	return available.size() == BackupManagerClass.MAX_BACKUPS


func test_backup_restoration() -> bool:
	var backup_manager := BackupManagerClass.new()

	# Create and save game state
	var original_state := {"entities": {"unique_entity": {"value": 12345}}}
	SaveManager.save_game("test_backup_restore", original_state)

	# Create backup
	backup_manager.create_backup("test_backup_restore")

	# Modify the save
	SaveManager.save_game("test_backup_restore", {"entities": {"different": {}}})

	# Restore from backup
	var restored := backup_manager.restore_backup("test_backup_restore", 1)

	# Load and verify
	var loaded := SaveManager.load_game("test_backup_restore")
	var has_original := loaded.snapshot.get("entities", {}).has("unique_entity")

	# Cleanup
	SaveManager.delete_save("test_backup_restore")
	backup_manager.delete_all_backups("test_backup_restore")

	return restored and has_original


func test_backup_validation() -> bool:
	var backup_manager := BackupManagerClass.new()

	# Create valid save and backup
	SaveManager.save_game("test_backup_valid", {"entities": {}})
	backup_manager.create_backup("test_backup_valid")

	var is_valid := backup_manager.validate_backup("test_backup_valid", 1)

	# Cleanup
	SaveManager.delete_save("test_backup_valid")
	backup_manager.delete_all_backups("test_backup_valid")

	return is_valid


func test_corruption_recovery() -> bool:
	var backup_manager := BackupManagerClass.new()

	# Create save with backup
	SaveManager.save_game("test_corruption", {"entities": {"good": {}}})
	backup_manager.create_backup("test_corruption")

	# "Corrupt" the main save by writing garbage
	var save_path := SaveFormat.get_save_path("test_corruption")
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_buffer(PackedByteArray([0x00, 0x01, 0x02]))
		file.close()

	# Attempt recovery
	var result := backup_manager.validate_and_recover("test_corruption")

	# Cleanup
	SaveManager.delete_save("test_corruption")
	backup_manager.delete_all_backups("test_corruption")

	return result.get("recovered", false)


# ============================================
# PERFORMANCE TESTS
# ============================================

func test_snapshot_performance() -> bool:
	# Test with 5000 entities (typical game state)
	var entities := {}
	for i in range(5000):
		entities["entity_%d" % i] = {
			"health": 100,
			"position": Vector3(randf(), randf(), randf()),
			"faction": i % 5
		}

	var game_state := {
		"entities": entities,
		"resources": {"gold": 1000, "metal": 500},
		"district_control": {}
	}

	var start := Time.get_ticks_msec()
	var snapshot := Snapshot.create_from_state(game_state, 0, 0, 0.0)
	var creation_time := Time.get_ticks_msec() - start

	start = Time.get_ticks_msec()
	var data := snapshot.to_dict()
	var _restored := Snapshot.from_dict(data)
	var serialization_time := Time.get_ticks_msec() - start

	print("  Snapshot creation (5000 entities): %dms" % creation_time)
	print("  Snapshot serialization: %dms" % serialization_time)

	return creation_time < 100 and serialization_time < 200


func test_delta_performance() -> bool:
	# Create base snapshot
	var entities := {}
	for i in range(1000):
		entities["entity_%d" % i] = {"health": 100}

	var old_snapshot := Snapshot.create_from_state({"entities": entities}, 0, 0, 0.0)
	old_snapshot.snapshot_id = 1

	# Modify some entities
	var new_entities := entities.duplicate(true)
	for i in range(100):
		new_entities["entity_%d" % i]["health"] = 80

	var new_snapshot := Snapshot.create_from_state({"entities": new_entities}, 10, 0, 0.0)

	var start := Time.get_ticks_msec()
	var delta := Delta.create_from_snapshots(old_snapshot, new_snapshot)
	var comparison_time := Time.get_ticks_msec() - start

	start = Time.get_ticks_msec()
	var _applied := delta.apply_to_snapshot(old_snapshot)
	var apply_time := Time.get_ticks_msec() - start

	print("  Delta comparison (1000 entities, 100 changes): %dms" % comparison_time)
	print("  Delta application: %dms" % apply_time)

	return comparison_time < 100 and apply_time < 50
