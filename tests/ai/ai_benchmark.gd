class_name AIBenchmark
extends RefCounted
## AIBenchmark tests AI system performance with large unit counts.
## Verifies <3ms behavior tree evaluation for 5,000 units.

signal benchmark_complete(results: Dictionary)

## Benchmark configuration
const TARGET_UNITS := 5000
const TARGET_TIME_MS := 3.0
const WARMUP_FRAMES := 10
const BENCHMARK_FRAMES := 100

## Test results
var _results: Dictionary = {}

## Test systems
var _ai_system: AISystem = null
var _test_tree: LimboAIWrapper.BTNode = null


func _init() -> void:
	_ai_system = AISystem.new()
	_create_test_tree()


## Create a representative test behavior tree.
func _create_test_tree() -> void:
	var root := LimboAIWrapper.create_selector("test_root")

	# Combat branch
	var combat := LimboAIWrapper.create_sequence("combat")
	combat.add_child(LimboAIWrapper.create_condition("has_target", _condition_has_target))
	combat.add_child(LimboAIWrapper.create_condition("in_range", _condition_in_range))
	combat.add_child(LimboAIWrapper.create_action("attack", _action_attack))
	root.add_child(combat)

	# Movement branch
	var movement := LimboAIWrapper.create_sequence("movement")
	movement.add_child(LimboAIWrapper.create_condition("has_destination", _condition_has_destination))
	movement.add_child(LimboAIWrapper.create_action("move", _action_move))
	root.add_child(movement)

	# Idle action
	root.add_child(LimboAIWrapper.create_action("idle", _action_idle))

	_test_tree = root
	_ai_system.register_tree_template("test_tree", root)


## Run full benchmark.
func run_benchmark() -> Dictionary:
	_results.clear()

	# Register test units
	var register_start := Time.get_ticks_usec()
	_register_test_units(TARGET_UNITS)
	var register_time := float(Time.get_ticks_usec() - register_start) / 1000.0

	_results["unit_count"] = TARGET_UNITS
	_results["registration_time_ms"] = register_time

	# Warmup
	for i in WARMUP_FRAMES:
		_ai_system.update(0.016)

	# Benchmark
	var frame_times: Array[float] = []
	var total_start := Time.get_ticks_usec()

	for i in BENCHMARK_FRAMES:
		var frame_start := Time.get_ticks_usec()
		_ai_system.update(0.016)
		var frame_time := float(Time.get_ticks_usec() - frame_start) / 1000.0
		frame_times.append(frame_time)

	var total_time := float(Time.get_ticks_usec() - total_start) / 1000.0

	# Calculate stats
	var min_time := INF
	var max_time := 0.0
	var sum := 0.0

	for time in frame_times:
		min_time = min(min_time, time)
		max_time = max(max_time, time)
		sum += time

	var avg_time := sum / float(frame_times.size())

	# Calculate standard deviation
	var variance := 0.0
	for time in frame_times:
		variance += (time - avg_time) * (time - avg_time)
	variance /= float(frame_times.size())
	var std_dev := sqrt(variance)

	# Calculate percentiles
	frame_times.sort()
	var p50 := frame_times[frame_times.size() / 2]
	var p95 := frame_times[int(frame_times.size() * 0.95)]
	var p99 := frame_times[int(frame_times.size() * 0.99)]

	_results["frames_benchmarked"] = BENCHMARK_FRAMES
	_results["total_time_ms"] = total_time
	_results["avg_frame_time_ms"] = avg_time
	_results["min_frame_time_ms"] = min_time
	_results["max_frame_time_ms"] = max_time
	_results["std_dev_ms"] = std_dev
	_results["p50_ms"] = p50
	_results["p95_ms"] = p95
	_results["p99_ms"] = p99
	_results["target_time_ms"] = TARGET_TIME_MS
	_results["meets_target"] = avg_time <= TARGET_TIME_MS
	_results["p95_meets_target"] = p95 <= TARGET_TIME_MS

	benchmark_complete.emit(_results)

	return _results


## Register test units with various factions.
func _register_test_units(count: int) -> void:
	var factions := ["AETHER_SWARM", "GLACIUS", "DYNAPODS", "LOGIBOTS", "HUMAN_REMNANT"]

	for i in count:
		var faction := factions[i % factions.size()]
		_ai_system.register_unit(i, faction, "test_tree")

		# Set initial blackboard data
		_ai_system.update_unit_data_batch(i, {
			"position": Vector3(randf() * 100, 0, randf() * 100),
			"target_id": (i + 1) % count if randf() > 0.5 else -1,
			"target_position": Vector3(randf() * 100, 0, randf() * 100),
			"health_percent": randf(),
			"in_combat": randf() > 0.7,
			"has_destination": randf() > 0.5
		})


## Test determinism.
func test_determinism(seed_value: int, iterations: int = 10) -> Dictionary:
	var results: Array[int] = []

	for i in iterations:
		# Reset and register one unit
		var test_system := AISystem.new()
		test_system.register_tree_template("test_tree", _test_tree)
		test_system.register_unit(0, "AETHER_SWARM", "test_tree")

		# Set consistent blackboard
		test_system.update_unit_data_batch(0, {
			"position": Vector3(10, 0, 10),
			"target_id": 1,
			"target_position": Vector3(15, 0, 15),
			"health_percent": 0.8,
			"in_combat": true,
			"has_destination": true
		})

		# Execute
		var status := test_system.update_unit_immediate(0)
		results.append(status)

	# Check all results match
	var first := results[0]
	var all_match := true
	for result in results:
		if result != first:
			all_match = false
			break

	return {
		"seed": seed_value,
		"iterations": iterations,
		"all_match": all_match,
		"results": results
	}


## Print results to console.
func print_results() -> void:
	print("=== AI Benchmark Results ===")
	print("Units: %d" % _results.get("unit_count", 0))
	print("Frames: %d" % _results.get("frames_benchmarked", 0))
	print("")
	print("Frame Time Statistics:")
	print("  Average: %.3f ms" % _results.get("avg_frame_time_ms", 0))
	print("  Min: %.3f ms" % _results.get("min_frame_time_ms", 0))
	print("  Max: %.3f ms" % _results.get("max_frame_time_ms", 0))
	print("  Std Dev: %.3f ms" % _results.get("std_dev_ms", 0))
	print("")
	print("Percentiles:")
	print("  P50: %.3f ms" % _results.get("p50_ms", 0))
	print("  P95: %.3f ms" % _results.get("p95_ms", 0))
	print("  P99: %.3f ms" % _results.get("p99_ms", 0))
	print("")
	print("Target: %.1f ms" % _results.get("target_time_ms", 0))
	print("Meets Target: %s" % str(_results.get("meets_target", false)))
	print("P95 Meets Target: %s" % str(_results.get("p95_meets_target", false)))


## Condition functions for test tree.
func _condition_has_target(blackboard: Dictionary) -> bool:
	return blackboard.get("target_id", -1) != -1


func _condition_in_range(blackboard: Dictionary) -> bool:
	var pos: Vector3 = blackboard.get("position", Vector3.ZERO)
	var target_pos: Vector3 = blackboard.get("target_position", Vector3.INF)

	if target_pos == Vector3.INF:
		return false

	return pos.distance_to(target_pos) <= 15.0


func _condition_has_destination(blackboard: Dictionary) -> bool:
	return blackboard.get("has_destination", false)


func _action_attack(blackboard: Dictionary) -> int:
	blackboard["last_action"] = "attack"
	return LimboAIWrapper.BTStatus.SUCCESS


func _action_move(blackboard: Dictionary) -> int:
	blackboard["last_action"] = "move"
	return LimboAIWrapper.BTStatus.RUNNING


func _action_idle(blackboard: Dictionary) -> int:
	blackboard["last_action"] = "idle"
	return LimboAIWrapper.BTStatus.SUCCESS
