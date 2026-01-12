class_name TestNetworkIntegration
extends RefCounted
## Integration tests for the networking system.
## Tests state synchronization, deterministic RNG, and network simulation.

signal test_completed(test_name: String, passed: bool, message: String)
signal all_tests_completed(passed: int, failed: int)

var _passed := 0
var _failed := 0
var _results: Array[Dictionary] = []


func _init() -> void:
	pass


## Run all network integration tests.
func run_all_tests() -> Dictionary:
	_passed = 0
	_failed = 0
	_results.clear()

	# Run tests
	_test_state_snapshot_delta_compression()
	_test_state_snapshot_full_sync()
	_test_deterministic_rng_consistency()
	_test_deterministic_rng_distribution()
	_test_client_prediction_interpolation()
	_test_rpc_validator_rate_limiting()
	_test_rpc_validator_schema()
	_test_network_simulation_latency()
	_test_network_simulation_packet_loss()
	_test_network_manager_mode_transitions()

	all_tests_completed.emit(_passed, _failed)

	return {
		"passed": _passed,
		"failed": _failed,
		"total": _passed + _failed,
		"results": _results
	}


## Record test result.
func _record_result(test_name: String, passed: bool, message: String = "") -> void:
	if passed:
		_passed += 1
	else:
		_failed += 1

	_results.append({
		"name": test_name,
		"passed": passed,
		"message": message
	})

	test_completed.emit(test_name, passed, message)


## Test: State snapshot delta compression.
func _test_state_snapshot_delta_compression() -> void:
	var snapshot := StateSnapshot.new()

	# Register entities
	snapshot.register_entity(1, {"position": Vector3(0, 0, 0), "health": 100, "faction_id": "test"})
	snapshot.register_entity(2, {"position": Vector3(10, 0, 0), "health": 100, "faction_id": "test"})

	# Create initial snapshot
	var initial := snapshot.create_snapshot()

	# Update only entity 1
	snapshot.update_entity_state(1, {"position": Vector3(5, 0, 0), "health": 100, "faction_id": "test"})

	# Create delta snapshot
	var delta := snapshot.create_snapshot()

	# Verify only changed entity is in delta
	var changes: Dictionary = delta.get("changes", {})
	var has_only_entity1 := changes.has(1) and not changes.has(2)
	var position_changed := false
	if changes.has(1):
		position_changed = changes[1].has("position")

	_record_result("state_snapshot_delta_compression",
		has_only_entity1 and position_changed,
		"Delta should only contain changed entity with changed fields")


## Test: State snapshot full synchronization.
func _test_state_snapshot_full_sync() -> void:
	var snapshot := StateSnapshot.new()

	# Register entities
	for i in 100:
		snapshot.register_entity(i, {"position": Vector3(i, 0, 0), "health": 100})

	# Create full snapshot
	var full := snapshot.create_full_snapshot()

	# Decompress and verify
	var decompressed := snapshot.decompress_snapshot(full)
	var entities: Dictionary = decompressed.get("entities", {})

	_record_result("state_snapshot_full_sync",
		entities.size() == 100,
		"Full snapshot should contain all 100 entities, got: %d" % entities.size())


## Test: Deterministic RNG produces consistent results.
func _test_deterministic_rng_consistency() -> void:
	var seed_value := 12345

	# Create two RNGs with same seed
	var rng1 := DeterministicRNG.new()
	var rng2 := DeterministicRNG.new()
	rng1.initialize(seed_value)
	rng2.initialize(seed_value)

	# Generate sequences
	var sequence1: Array[float] = []
	var sequence2: Array[float] = []
	for i in 1000:
		sequence1.append(rng1.randf())
		sequence2.append(rng2.randf())

	# Compare
	var matches := true
	for i in sequence1.size():
		if not is_equal_approx(sequence1[i], sequence2[i]):
			matches = false
			break

	_record_result("deterministic_rng_consistency",
		matches,
		"Two RNGs with same seed should produce identical sequences")


## Test: Deterministic RNG has good distribution.
func _test_deterministic_rng_distribution() -> void:
	var rng := DeterministicRNG.new()
	rng.initialize(54321)

	# Generate samples
	var buckets := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for i in 10000:
		var val := rng.randf()
		var bucket := mini(int(val * 10), 9)
		buckets[bucket] += 1

	# Check distribution (each bucket should have ~1000 samples)
	var min_bucket := buckets.min()
	var max_bucket := buckets.max()
	var good_distribution := min_bucket > 800 and max_bucket < 1200

	_record_result("deterministic_rng_distribution",
		good_distribution,
		"Distribution should be uniform, got min=%d max=%d" % [min_bucket, max_bucket])


## Test: Client prediction interpolation.
func _test_client_prediction_interpolation() -> void:
	var prediction := ClientPrediction.new()

	# Create two snapshots
	var snapshot1 := {
		"timestamp": 0,
		"entities": {
			"1": {"position": Vector3(0, 0, 0)}
		}
	}
	var snapshot2 := {
		"timestamp": 100,
		"entities": {
			"1": {"position": Vector3(10, 0, 0)}
		}
	}

	prediction.receive_snapshot(snapshot1)
	prediction.receive_snapshot(snapshot2)

	# Simulate time passing
	for i in 20:
		prediction.update(0.01)

	# Check interpolated position (should be between 0 and 10)
	var display := prediction.get_display_state(1)
	var pos: Vector3 = display.get("position", Vector3.ZERO)
	var in_range := pos.x >= 0 and pos.x <= 10

	_record_result("client_prediction_interpolation",
		in_range,
		"Interpolated position should be between start and end, got: %s" % str(pos))


## Test: RPC validator rate limiting.
func _test_rpc_validator_rate_limiting() -> void:
	var validator := RPCValidator.new()

	# Send RPCs rapidly
	var passed := 0
	var blocked := 0
	for i in 100:
		if validator.check_rate_limit(1):
			passed += 1
		else:
			blocked += 1

	# Should hit rate limit
	_record_result("rpc_validator_rate_limiting",
		blocked > 0,
		"Rate limiting should block some rapid RPCs, passed=%d blocked=%d" % [passed, blocked])


## Test: RPC validator schema validation.
func _test_rpc_validator_schema() -> void:
	var validator := RPCValidator.new()

	# Valid RPC
	var valid := validator.validate_outgoing("rpc_move_unit", [1, Vector3(0, 0, 0)])

	# Invalid method name
	var invalid_name := validator.validate_outgoing("move_unit", [1, Vector3(0, 0, 0)])

	# Invalid argument count
	var invalid_args := validator.validate_outgoing("rpc_move_unit", [1])

	_record_result("rpc_validator_schema",
		valid and not invalid_name and not invalid_args,
		"Schema validation should accept valid RPCs and reject invalid ones")


## Test: Network simulation latency.
func _test_network_simulation_latency() -> void:
	var sim := NetworkSimulation.new()
	sim.enable()
	sim.set_latency(100, 100)  ## Fixed 100ms
	sim.set_packet_loss(0.0)  ## No packet loss

	# Queue packets
	for i in 10:
		sim.queue_outgoing_rpc("rpc_test", [i], 1)

	# Check nothing delivered immediately
	var immediate := sim.get_ready_outgoing()

	# Wait for simulated time (need to simulate passage of time)
	# In a real test, we'd use await or scene tree timers
	# For this unit test, we check the queue exists

	var stats := sim.get_stats()
	var has_latency := stats["min_latency_ms"] == 100 and stats["max_latency_ms"] == 100

	_record_result("network_simulation_latency",
		immediate.size() == 0 and has_latency,
		"Packets should be delayed, not delivered immediately")


## Test: Network simulation packet loss.
func _test_network_simulation_packet_loss() -> void:
	var sim := NetworkSimulation.new()
	sim.enable()
	sim.set_latency(0, 0)  ## No latency
	sim.set_packet_loss(0.5)  ## 50% packet loss

	# Queue many packets
	for i in 1000:
		sim.queue_outgoing_rpc("rpc_test", [i], 1)

	var stats := sim.get_stats()
	var drop_rate := stats["actual_drop_rate"]

	# Should be approximately 50% (40-60% acceptable)
	var reasonable_drop := drop_rate > 0.4 and drop_rate < 0.6

	_record_result("network_simulation_packet_loss",
		reasonable_drop,
		"Packet loss should be approximately 50%%, got: %.1f%%" % (drop_rate * 100))


## Test: Network manager mode transitions.
func _test_network_manager_mode_transitions() -> void:
	var manager := NetworkManager.new()

	# Start offline
	manager.start_offline()
	var offline := manager.get_mode() == NetworkManager.NetworkMode.OFFLINE
	var is_server := manager.is_server()

	# Disconnect
	manager.disconnect_network()
	var disconnected := manager.get_mode() == NetworkManager.NetworkMode.OFFLINE

	_record_result("network_manager_mode_transitions",
		offline and is_server and disconnected,
		"Manager should handle mode transitions correctly")


## Run bandwidth benchmark.
func run_bandwidth_benchmark(entity_count: int = 5000) -> Dictionary:
	var snapshot := StateSnapshot.new()

	# Register many entities
	for i in entity_count:
		snapshot.register_entity(i, {
			"position": Vector3(i * 0.1, 0, 0),
			"rotation": 0.0,
			"health": 100,
			"faction_id": "test",
			"state": "idle"
		})

	# Measure full snapshot size
	var start_time := Time.get_ticks_usec()
	var full := snapshot.create_full_snapshot()
	var full_time := (Time.get_ticks_usec() - start_time) / 1000.0

	# Update some entities (10%)
	for i in entity_count / 10:
		snapshot.update_entity_state(i * 10, {
			"position": Vector3(i * 0.1 + 0.01, 0, 0),
			"rotation": 0.1,
			"health": 100,
			"faction_id": "test",
			"state": "idle"
		})

	# Measure delta snapshot size
	start_time = Time.get_ticks_usec()
	var delta := snapshot.create_snapshot()
	var delta_time := (Time.get_ticks_usec() - start_time) / 1000.0
	var compressed := snapshot.compress_delta(delta)

	return {
		"entity_count": entity_count,
		"full_snapshot_size": full.size(),
		"full_snapshot_time_ms": full_time,
		"delta_snapshot_size": compressed.size(),
		"delta_snapshot_time_ms": delta_time,
		"compression_ratio": float(full.size()) / compressed.size() if compressed.size() > 0 else 0,
		"meets_bandwidth_target": compressed.size() < 100000  ## <100KB
	}


## Run latency stress test.
func run_latency_stress_test(iterations: int = 1000) -> Dictionary:
	var prediction := ClientPrediction.new()

	# Simulate high-latency conditions
	var latencies: Array[float] = []
	var corrections := 0

	prediction.prediction_corrected.connect(func(_e, _c): corrections += 1)

	for i in iterations:
		# Create snapshot with some jitter
		var time_offset := randf_range(-50, 50)
		var snapshot := {
			"timestamp": i * 16 + int(time_offset),
			"entities": {
				"1": {"position": Vector3(i * 0.1, 0, 0)}
			}
		}
		prediction.receive_snapshot(snapshot)
		prediction.update(0.016)

	return {
		"iterations": iterations,
		"corrections": corrections,
		"correction_rate": float(corrections) / iterations
	}
