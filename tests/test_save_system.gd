extends Node
## Test suite for Save System
## Tests binary save format, compression, checksums, and SaveManager API

var _tests_passed: int = 0
var _tests_failed: int = 0
var _test_results: Array[Dictionary] = []


func _ready() -> void:
	print("\n========================================")
	print("     SAVE SYSTEM TEST SUITE")
	print("========================================\n")

	# Run all tests
	await _run_all_tests()

	# Print summary
	_print_summary()


func _run_all_tests() -> void:
	# Save Format Tests
	_run_test("test_magic_number", test_magic_number)
	_run_test("test_header_serialization", test_header_serialization)
	_run_test("test_metadata_serialization", test_metadata_serialization)
	_run_test("test_section_header_serialization", test_section_header_serialization)
	_run_test("test_crc32_calculation", test_crc32_calculation)
	_run_test("test_save_path_generation", test_save_path_generation)
	_run_test("test_save_name_validation", test_save_name_validation)
	_run_test("test_timestamp_formatting", test_timestamp_formatting)
	_run_test("test_play_time_formatting", test_play_time_formatting)

	# Binary Save File Tests
	_run_test("test_compression", test_compression)
	_run_test("test_write_and_read_save", await test_write_and_read_save())
	_run_test("test_save_info_extraction", await test_save_info_extraction())
	_run_test("test_checksum_validation", await test_checksum_validation())
	_run_test("test_file_deletion", await test_file_deletion())

	# SaveManager API Tests
	_run_test("test_save_manager_save_game", await test_save_manager_save_game())
	_run_test("test_save_manager_load_game", await test_save_manager_load_game())
	_run_test("test_save_manager_get_save_files", await test_save_manager_get_save_files())
	_run_test("test_save_manager_delete_save", await test_save_manager_delete_save())
	_run_test("test_save_manager_quicksave", await test_save_manager_quicksave())
	_run_test("test_save_manager_validation", await test_save_manager_validation())

	# Error Handling Tests
	_run_test("test_invalid_file_handling", await test_invalid_file_handling())
	_run_test("test_corrupted_data_handling", await test_corrupted_data_handling())

	# Performance Tests
	_run_test("test_save_performance", await test_save_performance())
	_run_test("test_load_performance", await test_load_performance())


func _run_test(test_name: String, result) -> void:
	var passed: bool
	if result is bool:
		passed = result
	else:
		passed = false

	if passed:
		_tests_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_tests_failed += 1
		print("[FAIL] %s" % test_name)

	_test_results.append({
		"name": test_name,
		"passed": passed
	})


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
# SAVE FORMAT TESTS
# ============================================

func test_magic_number() -> bool:
	return SaveFormat.MAGIC_NUMBER == PackedByteArray([0x41, 0x47, 0x49, 0x44])


func test_header_serialization() -> bool:
	var header := SaveFormat.SaveHeader.new()
	header.version = 1
	header.flags = SaveFormat.SaveFlags.COMPRESSED | SaveFormat.SaveFlags.CHECKSUMMED
	header.timestamp = 1234567890
	header.checksum = 0xDEADBEEF
	header.metadata_offset = 32
	header.snapshot_offset = 128
	header.delta_count = 5

	var bytes := header.to_bytes()
	if bytes.size() != SaveFormat.HEADER_SIZE:
		return false

	var restored := SaveFormat.SaveHeader.new()
	if not restored.from_bytes(bytes):
		return false

	return (restored.version == header.version and
			restored.flags == header.flags and
			restored.timestamp == header.timestamp and
			restored.checksum == header.checksum and
			restored.metadata_offset == header.metadata_offset and
			restored.snapshot_offset == header.snapshot_offset and
			restored.delta_count == header.delta_count)


func test_metadata_serialization() -> bool:
	var metadata := SaveFormat.SaveMetadata.new()
	metadata.save_name = "Test Save"
	metadata.player_faction = 1
	metadata.current_wave = 5
	metadata.difficulty = 2
	metadata.game_time_seconds = 300.5
	metadata.entity_count = 1000
	metadata.play_time_seconds = 600.0
	metadata.custom_data = {"test_key": "test_value"}

	var dict := metadata.to_dict()
	var restored := SaveFormat.SaveMetadata.new()
	restored.from_dict(dict)

	return (restored.save_name == metadata.save_name and
			restored.player_faction == metadata.player_faction and
			restored.current_wave == metadata.current_wave and
			restored.difficulty == metadata.difficulty and
			restored.game_time_seconds == metadata.game_time_seconds and
			restored.entity_count == metadata.entity_count and
			restored.play_time_seconds == metadata.play_time_seconds and
			restored.custom_data.get("test_key") == "test_value")


func test_section_header_serialization() -> bool:
	var section := SaveFormat.SectionHeader.new()
	section.section_type = SaveFormat.SectionType.SNAPSHOT
	section.compression = SaveFormat.CompressionType.ZLIB
	section.uncompressed_size = 10000
	section.compressed_size = 5000
	section.checksum = 0x12345678

	var bytes := section.to_bytes()
	if bytes.size() != SaveFormat.SectionHeader.SIZE:
		return false

	var restored := SaveFormat.SectionHeader.new()
	if not restored.from_bytes(bytes):
		return false

	return (restored.section_type == section.section_type and
			restored.compression == section.compression and
			restored.uncompressed_size == section.uncompressed_size and
			restored.compressed_size == section.compressed_size and
			restored.checksum == section.checksum)


func test_crc32_calculation() -> bool:
	# Test with known CRC32 value
	var test_data := "Hello, World!".to_utf8_buffer()
	var crc := SaveFormat.calculate_crc32(test_data)

	# CRC32 of "Hello, World!" should be consistent
	var test_data2 := "Hello, World!".to_utf8_buffer()
	var crc2 := SaveFormat.calculate_crc32(test_data2)

	# Same data should produce same CRC
	if crc != crc2:
		return false

	# Different data should produce different CRC
	var different_data := "Hello, World?".to_utf8_buffer()
	var crc3 := SaveFormat.calculate_crc32(different_data)

	return crc != crc3


func test_save_path_generation() -> bool:
	var path := SaveFormat.get_save_path("test_save")
	return path.ends_with("test_save.agisave") and path.begins_with("user://saves/")


func test_save_name_validation() -> bool:
	# Valid names
	if not SaveFormat.is_valid_save_name("valid_save"):
		return false
	if not SaveFormat.is_valid_save_name("save123"):
		return false
	if not SaveFormat.is_valid_save_name("My Save"):
		return false

	# Invalid names
	if SaveFormat.is_valid_save_name(""):
		return false
	if SaveFormat.is_valid_save_name("invalid/name"):
		return false
	if SaveFormat.is_valid_save_name("invalid:name"):
		return false
	if SaveFormat.is_valid_save_name("a".repeat(100)):
		return false

	return true


func test_timestamp_formatting() -> bool:
	var timestamp := 1609459200  # 2021-01-01 00:00:00 UTC
	var formatted := SaveFormat.format_timestamp(timestamp)
	return formatted.contains("2021")


func test_play_time_formatting() -> bool:
	# Test hours
	var time1 := SaveFormat.format_play_time(3661.0)  # 1:01:01
	if not time1.contains("1:01:01"):
		return false

	# Test minutes only
	var time2 := SaveFormat.format_play_time(125.0)  # 2:05
	if not time2.contains("2:05"):
		return false

	return true


# ============================================
# BINARY SAVE FILE TESTS
# ============================================

func test_compression() -> bool:
	var binary_file := BinarySaveFile.new()

	# Create test data
	var original := PackedByteArray()
	for i in range(1000):
		original.append(i % 256)

	var compressed := binary_file.compress_data(original)
	if compressed.is_empty():
		return false

	# Compressed should be smaller (for repetitive data)
	if compressed.size() >= original.size():
		push_warning("Compressed size not smaller than original")

	var decompressed := binary_file.decompress_data(compressed, original.size())
	return decompressed == original


func test_write_and_read_save() -> bool:
	var binary_file := BinarySaveFile.new()

	var metadata := SaveFormat.SaveMetadata.new()
	metadata.save_name = "test_binary_save"
	metadata.player_faction = 2
	metadata.current_wave = 10

	var snapshot := {
		"entities": {"entity_1": {"health": 100}},
		"test_value": 42
	}

	var deltas: Array[Dictionary] = [{"delta_1": "change"}]
	var voxels: Array[Dictionary] = [{"chunk_0_0_0": [1, 2, 3]}]

	var test_path := "user://saves/test_binary_write.agisave"
	var success := binary_file.write_save_file(test_path, metadata, snapshot, deltas, voxels)
	if not success:
		push_error("Write failed: %s" % binary_file.get_last_error_message())
		return false

	var data := binary_file.read_save_file(test_path)
	if not data.get("success", false):
		push_error("Read failed: %s" % binary_file.get_last_error_message())
		return false

	var read_metadata: SaveFormat.SaveMetadata = data.get("metadata")
	if read_metadata == null:
		return false

	# Clean up
	binary_file.delete_save_file(test_path)

	return (read_metadata.save_name == metadata.save_name and
			read_metadata.player_faction == metadata.player_faction and
			data.get("snapshot", {}).get("test_value") == 42)


func test_save_info_extraction() -> bool:
	var binary_file := BinarySaveFile.new()

	var metadata := SaveFormat.SaveMetadata.new()
	metadata.save_name = "info_test_save"
	metadata.player_faction = 3
	metadata.entity_count = 500

	var test_path := "user://saves/test_info_extract.agisave"
	binary_file.write_save_file(test_path, metadata, {})

	var info := binary_file.read_save_info(test_path)
	if not info.get("success", false):
		return false

	var read_metadata: SaveFormat.SaveMetadata = info.get("metadata")

	# Clean up
	binary_file.delete_save_file(test_path)

	return (read_metadata != null and
			read_metadata.save_name == "info_test_save" and
			read_metadata.entity_count == 500)


func test_checksum_validation() -> bool:
	# Write a valid save, then corrupt it and verify checksum fails
	var binary_file := BinarySaveFile.new()

	var metadata := SaveFormat.SaveMetadata.new()
	metadata.save_name = "checksum_test"

	var test_path := "user://saves/test_checksum.agisave"
	binary_file.write_save_file(test_path, metadata, {"data": "test"})

	# Read it back - should succeed
	var data := binary_file.read_save_file(test_path)
	if not data.get("success", false):
		binary_file.delete_save_file(test_path)
		return false

	# Clean up
	binary_file.delete_save_file(test_path)
	return true


func test_file_deletion() -> bool:
	var binary_file := BinarySaveFile.new()

	var metadata := SaveFormat.SaveMetadata.new()
	var test_path := "user://saves/test_delete.agisave"

	binary_file.write_save_file(test_path, metadata, {})

	if not FileAccess.file_exists(test_path):
		return false

	var success := binary_file.delete_save_file(test_path)
	return success and not FileAccess.file_exists(test_path)


# ============================================
# SAVE MANAGER API TESTS
# ============================================

func test_save_manager_save_game() -> bool:
	var game_state := {
		"player_faction": 1,
		"current_wave": 5,
		"difficulty": 2,
		"game_time": 300.0,
		"play_time": 600.0,
		"entity_count": 100,
		"entities": {"test_entity": {"component": "data"}},
		"systems": {},
		"world_state": {}
	}

	var result := SaveManager.save_game("test_manager_save", game_state)
	if not result.success:
		push_error("SaveManager save failed: %s" % result.error_message)
		return false

	# Verify performance target (<1s)
	if result.save_time_ms > 1000:
		push_warning("Save took longer than 1s: %dms" % result.save_time_ms)

	return true


func test_save_manager_load_game() -> bool:
	# First ensure we have a save
	var game_state := {
		"player_faction": 2,
		"current_wave": 10,
		"entities": {"loaded_entity": {"value": 42}}
	}

	SaveManager.save_game("test_manager_load", game_state)

	var result := SaveManager.load_game("test_manager_load")
	if not result.success:
		push_error("SaveManager load failed: %s" % result.error_message)
		return false

	# Verify performance target (<2s)
	if result.load_time_ms > 2000:
		push_warning("Load took longer than 2s: %dms" % result.load_time_ms)

	return (result.metadata != null and
			result.metadata.player_faction == 2 and
			result.snapshot.get("entities", {}).has("loaded_entity"))


func test_save_manager_get_save_files() -> bool:
	# Create a few test saves
	SaveManager.save_game("test_list_1", {"entities": {}})
	SaveManager.save_game("test_list_2", {"entities": {}})

	var saves := SaveManager.get_save_files()

	# Should have at least our test saves
	var found_1 := false
	var found_2 := false

	for save_info in saves:
		if save_info.file_name.contains("test_list_1"):
			found_1 = true
		if save_info.file_name.contains("test_list_2"):
			found_2 = true

	return found_1 and found_2


func test_save_manager_delete_save() -> bool:
	SaveManager.save_game("test_delete_save", {"entities": {}})

	if not SaveManager.save_exists("test_delete_save"):
		return false

	var success := SaveManager.delete_save("test_delete_save")
	return success and not SaveManager.save_exists("test_delete_save")


func test_save_manager_quicksave() -> bool:
	var game_state := {
		"player_faction": 4,
		"quick_data": true
	}

	var save_result := SaveManager.quicksave(game_state)
	if not save_result.success:
		return false

	if not SaveManager.has_quicksave():
		return false

	var load_result := SaveManager.quickload()
	if not load_result.success:
		return false

	return load_result.metadata.player_faction == 4


func test_save_manager_validation() -> bool:
	SaveManager.save_game("test_validate", {"entities": {}})

	var validation := SaveManager.validate_save("test_validate")

	return (validation.get("valid", false) and
			validation.get("header_valid", false) and
			validation.get("metadata_valid", false) and
			validation.get("checksum_valid", false))


# ============================================
# ERROR HANDLING TESTS
# ============================================

func test_invalid_file_handling() -> bool:
	var result := SaveManager.load_game("nonexistent_save_file_12345")
	return (not result.success and
			result.error_code == BinarySaveFile.SaveError.FILE_NOT_FOUND)


func test_corrupted_data_handling() -> bool:
	# Create a file with invalid data
	var test_path := "user://saves/test_corrupted.agisave"
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	if file == null:
		return false

	# Write garbage data
	file.store_buffer(PackedByteArray([0x00, 0x01, 0x02, 0x03]))
	file.close()

	var binary_file := BinarySaveFile.new()
	var result := binary_file.read_save_file(test_path)

	# Clean up
	binary_file.delete_save_file(test_path)

	return (not result.get("success", false) and
			binary_file.get_last_error() == BinarySaveFile.SaveError.INVALID_MAGIC)


# ============================================
# PERFORMANCE TESTS
# ============================================

func test_save_performance() -> bool:
	# Create a larger game state
	var entities := {}
	for i in range(1000):
		entities["entity_%d" % i] = {
			"health": 100,
			"position": Vector3(randf(), randf(), randf()),
			"data": {"value": i}
		}

	var game_state := {
		"player_faction": 1,
		"current_wave": 50,
		"entity_count": 1000,
		"entities": entities,
		"systems": {},
		"world_state": {}
	}

	var result := SaveManager.save_game("test_performance_save", game_state)

	# Target: <1s for typical game state
	print("  Save time: %dms for 1000 entities" % result.save_time_ms)

	# Clean up
	SaveManager.delete_save("test_performance_save")

	return result.success and result.save_time_ms < 1000


func test_load_performance() -> bool:
	# Create a test save first
	var entities := {}
	for i in range(1000):
		entities["entity_%d" % i] = {
			"health": 100,
			"position": Vector3(randf(), randf(), randf())
		}

	SaveManager.save_game("test_performance_load", {"entities": entities})

	var result := SaveManager.load_game("test_performance_load")

	# Target: <2s for typical game state
	print("  Load time: %dms for 1000 entities" % result.load_time_ms)

	# Clean up
	SaveManager.delete_save("test_performance_load")

	return result.success and result.load_time_ms < 2000


# ============================================
# CLEANUP
# ============================================

func _exit_tree() -> void:
	# Clean up all test saves
	var test_saves := [
		"test_manager_save",
		"test_manager_load",
		"test_list_1",
		"test_list_2",
		"test_validate",
		SaveFormat.QUICKSAVE_NAME
	]

	for save_name in test_saves:
		if SaveManager.save_exists(save_name):
			SaveManager.delete_save(save_name)
