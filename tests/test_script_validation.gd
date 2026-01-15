extends SceneTree
## Script Validation Test
## Validates all GDScript files for syntax and type errors.
## Run with: godot --headless --path "c:\Claude\AGIDay" --script tests/test_script_validation.gd
##
## NOTE: For comprehensive type checking, also run:
##   godot --headless --path "c:\Claude\AGIDay" --check-only
## This will catch type inference errors that load() misses.

var _test_count: int = 0
var _pass_count: int = 0
var _fail_count: int = 0
var _errors: Array = []


func _init() -> void:
	print("=" .repeat(60))
	print("SCRIPT VALIDATION TEST")
	print("=" .repeat(60))

	run_validation()
	quit()


func run_validation() -> void:
	print("\n[SCANNING SCRIPTS]")

	# Get all GDScript files
	var scripts := _find_all_scripts("res://")
	print("Found %d GDScript files to validate\n" % scripts.size())

	print("[VALIDATING SCRIPTS]")
	for script_path in scripts:
		_validate_script(script_path)

	# Run instantiation tests to catch runtime type errors
	_test_ability_instantiation()

	_print_results()


func _find_all_scripts(path: String) -> Array:
	var scripts: Array = []
	var dir := DirAccess.open(path)

	if dir == null:
		return scripts

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != ".." and file_name != ".godot":
				var subdir_path := path.path_join(file_name)
				scripts.append_array(_find_all_scripts(subdir_path))
		elif file_name.ends_with(".gd"):
			scripts.append(path.path_join(file_name))
		file_name = dir.get_next()

	dir.list_dir_end()
	return scripts


func _validate_script(script_path: String) -> void:
	_test_count += 1

	# Try to load the script - this will catch syntax and type errors
	var script := load(script_path)

	if script == null:
		_fail_count += 1
		var error_msg := "Failed to load: %s" % script_path
		_errors.append(error_msg)
		print("  [FAIL] %s" % script_path.get_file())
		return

	# Check if script is valid GDScript
	if not script is GDScript:
		_fail_count += 1
		var error_msg := "Not a valid GDScript: %s" % script_path
		_errors.append(error_msg)
		print("  [FAIL] %s (not GDScript)" % script_path.get_file())
		return

	# Try to get script methods to verify it parses correctly
	var gds: GDScript = script
	var methods := gds.get_script_method_list()

	# Script loaded and parsed successfully
	_pass_count += 1
	# Only print failures to keep output clean
	# print("  [PASS] %s" % script_path.get_file())


func _print_results() -> void:
	print("\n" + "=" .repeat(60))
	print("VALIDATION RESULTS")
	print("=" .repeat(60))
	print("Total: %d | Passed: %d | Failed: %d" % [_test_count, _pass_count, _fail_count])

	if _fail_count > 0:
		print("\nFailed scripts:")
		for error in _errors:
			print("  - %s" % error)
		print("\nSTATUS: %d SCRIPTS FAILED VALIDATION" % _fail_count)
	else:
		print("\nSTATUS: ALL SCRIPTS VALID")


# =============================================================================
# ABILITY CLASS INSTANTIATION TESTS
# These tests catch type errors that only appear when methods are called
# =============================================================================

func _test_ability_instantiation() -> void:
	print("\n[ABILITY INSTANTIATION TESTS]")

	# Test PhaseShiftAbility
	_test_class_instantiation("PhaseShiftAbility", func():
		var ability := PhaseShiftAbility.new()
		ability.can_activate()
		ability.get_phased_count()
		ability.update(0.1)
		ability.to_dict()
		return true
	)

	# Test OverclockUnitAbility
	_test_class_instantiation("OverclockUnitAbility", func():
		var ability := OverclockUnitAbility.new()
		ability.can_activate()
		ability.get_overclocked_count()
		ability.update(0.1)
		ability.to_dict()
		return true
	)

	# Test SiegeFormationAbility
	_test_class_instantiation("SiegeFormationAbility", func():
		var ability := SiegeFormationAbility.new()
		ability.can_activate()
		ability.get_deployed_count()
		ability.update(0.1)
		ability.to_dict()
		return true
	)

	# Test NanoReplicationAbility
	_test_class_instantiation("NanoReplicationAbility", func():
		var ability := NanoReplicationAbility.new()
		ability.register_unit(1)
		ability.get_heal_rate(1)
		ability.update(0.1, {1: Vector3.ZERO})
		ability.to_dict()
		return true
	)

	# Test EtherCloakAbility
	_test_class_instantiation("EtherCloakAbility", func():
		var ability := EtherCloakAbility.new()
		ability.can_activate()
		ability.get_cloaked_count()
		ability.update(0.1)
		ability.to_dict()
		return true
	)

	# Test TerrainMasteryAbility
	_test_class_instantiation("TerrainMasteryAbility", func():
		var ability := TerrainMasteryAbility.new()
		ability.register_unit(1)
		ability.set_terrain(Vector3.ZERO, "rubble")
		ability.get_speed_multiplier(1, Vector3.ZERO)
		ability.to_dict()
		return true
	)

	# Test CoordinatedBarrageAbility
	_test_class_instantiation("CoordinatedBarrageAbility", func():
		var ability := CoordinatedBarrageAbility.new()
		ability.can_activate()
		ability.register_unit(1)
		ability.get_damage_multiplier(1, 100)
		ability.update(0.1)
		ability.to_dict()
		return true
	)

	# Test FactionMechanicsSystem
	_test_class_instantiation("FactionMechanicsSystem", func():
		var system := FactionMechanicsSystem.new()
		system.register_unit(1, "aether_swarm", 0.0)
		system.update_positions({1: Vector3.ZERO})
		system.update(0.1)
		system.to_dict()
		return true
	)


func _test_class_instantiation(class_name_str: String, test_func: Callable) -> void:
	_test_count += 1
	var success := false
	var error_msg := ""

	# Try to run the test
	success = test_func.call()

	if success:
		_pass_count += 1
		print("  [PASS] %s instantiation and methods" % class_name_str)
	else:
		_fail_count += 1
		_errors.append("Failed to instantiate %s" % class_name_str)
		print("  [FAIL] %s instantiation failed" % class_name_str)
