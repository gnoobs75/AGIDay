extends Node
## ECS Framework Comprehensive Test Suite
## Includes unit tests, integration tests, performance benchmarks,
## stress tests, and determinism validation.

var _test_count: int = 0
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("=" .repeat(60))
	print("ECS FRAMEWORK COMPREHENSIVE TEST SUITE")
	print("=" .repeat(60))

	run_all_tests()


func run_all_tests() -> void:
	print("\n[UNIT TESTS]")
	_run_unit_tests()

	print("\n[INTEGRATION TESTS]")
	_run_integration_tests()

	print("\n[PERFORMANCE BENCHMARKS]")
	_run_performance_benchmarks()

	print("\n[STRESS TESTS]")
	_run_stress_tests()

	print("\n[DETERMINISM TESTS]")
	_run_determinism_tests()

	print("\n[ERROR HANDLING TESTS]")
	_run_error_handling_tests()

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


func _assert_eq(actual: Variant, expected: Variant, test_name: String) -> void:
	_assert(actual == expected, "%s (expected: %s, got: %s)" % [test_name, str(expected), str(actual)])


func _assert_ne(actual: Variant, not_expected: Variant, test_name: String) -> void:
	_assert(actual != not_expected, "%s (should not be: %s)" % [test_name, str(not_expected)])


func _assert_lt(actual: float, max_val: float, test_name: String) -> void:
	_assert(actual < max_val, "%s (expected < %.2f, got: %.2f)" % [test_name, max_val, actual])


func _assert_gt(actual: float, min_val: float, test_name: String) -> void:
	_assert(actual > min_val, "%s (expected > %.2f, got: %.2f)" % [test_name, min_val, actual])


func _assert_null(value: Variant, test_name: String) -> void:
	_assert(value == null, "%s (expected null)" % test_name)


func _assert_not_null(value: Variant, test_name: String) -> void:
	_assert(value != null, "%s (expected not null)" % test_name)


# =============================================================================
# UNIT TESTS
# =============================================================================

func _run_unit_tests() -> void:
	print("\n--- Entity Class Tests ---")
	_test_entity_init()
	_test_entity_add_component()
	_test_entity_get_component()
	_test_entity_has_component()
	_test_entity_remove_component()
	_test_entity_has_components()
	_test_entity_get_all_components()
	_test_entity_clear_components()

	print("\n--- Component Class Tests ---")
	_test_component_init()
	_test_component_data_access()
	_test_component_validation()
	_test_component_serialization()

	print("\n--- EntityManager Tests ---")
	_test_em_create_entity()
	_test_em_destroy_entity()
	_test_em_get_entity()
	_test_em_query_by_type()
	_test_em_query_by_component()
	_test_em_query_by_multiple_components()
	_test_em_batch_operations()

	print("\n--- ComponentSchema Tests ---")
	_test_schema_field_definitions()
	_test_schema_validation()
	_test_schema_range_validation()
	_test_schema_defaults()


func _test_entity_init() -> void:
	var entity := Entity.new()
	entity.initialize(123, EntityTypes.Type.UNIT)
	_assert_eq(entity.id, 123, "Entity ID set correctly")
	_assert_eq(entity.entity_type, "Unit", "Entity type set correctly")
	_assert_eq(entity.id_string, "UNIT_123", "Entity ID string formatted")
	_assert(not entity.is_spawned, "Entity not spawned initially")


func _test_entity_add_component() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp := Component.new()
	comp.component_type = "TestComp"
	_assert(entity.add_component(comp), "Component added successfully")
	_assert(not entity.add_component(comp), "Duplicate component rejected")


func _test_entity_get_component() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp := Component.new()
	comp.component_type = "TestComp"
	entity.add_component(comp)
	_assert_eq(entity.get_component("TestComp"), comp, "Get component returns correct instance")
	_assert_null(entity.get_component("NonExistent"), "Get non-existent returns null")


func _test_entity_has_component() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp := Component.new()
	comp.component_type = "TestComp"
	entity.add_component(comp)
	_assert(entity.has_component("TestComp"), "Has component returns true")
	_assert(not entity.has_component("Missing"), "Has missing component returns false")


func _test_entity_remove_component() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp := Component.new()
	comp.component_type = "TestComp"
	entity.add_component(comp)
	var removed := entity.remove_component("TestComp")
	_assert_eq(removed, comp, "Remove returns the component")
	_assert(not entity.has_component("TestComp"), "Component no longer present")
	_assert_null(entity.remove_component("TestComp"), "Remove non-existent returns null")


func _test_entity_has_components() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp1 := Component.new()
	comp1.component_type = "Comp1"
	var comp2 := Component.new()
	comp2.component_type = "Comp2"
	entity.add_component(comp1)
	entity.add_component(comp2)
	_assert(entity.has_components(["Comp1", "Comp2"] as Array[String]), "Has all components")
	_assert(not entity.has_components(["Comp1", "Comp3"] as Array[String]), "Missing one component")


func _test_entity_get_all_components() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp1 := Component.new()
	comp1.component_type = "Comp1"
	var comp2 := Component.new()
	comp2.component_type = "Comp2"
	entity.add_component(comp1)
	entity.add_component(comp2)
	var all := entity.get_all_components()
	_assert_eq(all.size(), 2, "Get all components count")


func _test_entity_clear_components() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp := Component.new()
	comp.component_type = "TestComp"
	entity.add_component(comp)
	entity.clear_components()
	_assert_eq(entity.get_component_count(), 0, "Clear removes all components")


func _test_component_init() -> void:
	var comp := Component.new()
	comp.component_type = "Test"
	comp.version = 2
	_assert_eq(comp.get_component_type(), "Test", "Component type getter")
	_assert_eq(comp.get_version(), 2, "Component version getter")


func _test_component_data_access() -> void:
	var comp := Component.new()
	comp.set_value("health", 100)
	_assert_eq(comp.get_value("health"), 100, "Set and get value")
	_assert(comp.has_value("health"), "Has value returns true")
	_assert(not comp.has_value("missing"), "Has missing value returns false")
	_assert_eq(comp.get_value("missing", 50), 50, "Get with default")
	comp.remove_value("health")
	_assert(not comp.has_value("health"), "Remove value works")


func _test_component_validation() -> void:
	var comp := Component.new()
	comp.data = {"name": "test", "value": 42}
	_assert(comp.validate(), "Valid data passes")
	comp.data = {"nested": {"inner": [1, 2, 3]}}
	_assert(comp.validate(), "Nested data validates")


func _test_component_serialization() -> void:
	var comp := Component.new()
	comp.component_type = "TestType"
	comp.version = 3
	comp.entity_id = 99
	comp.data = {"a": 1, "b": "test"}
	var dict := comp._to_dict()
	_assert_eq(dict["type"], "TestType", "Serialization includes type")
	_assert_eq(dict["version"], 3, "Serialization includes version")
	var comp2 := Component.new()
	comp2._from_dict(dict)
	_assert_eq(comp2.get_component_type(), "TestType", "Deserialization restores type")
	_assert_eq(comp2.get_value("a"), 1, "Deserialization restores data")


func _test_em_create_entity() -> void:
	var em := EntityManager.new(100, 0)
	var e := em.create_entity("Unit")
	_assert_not_null(e, "Create entity returns entity")
	_assert_gt(e.id, 0, "Entity has valid ID")
	_assert_eq(em.get_entity_count(), 1, "Entity count incremented")


func _test_em_destroy_entity() -> void:
	var em := EntityManager.new(100, 0)
	var e := em.create_entity("Unit")
	var id := e.id
	_assert(em.destroy_entity(id), "Destroy returns true")
	_assert_eq(em.get_entity_count(), 0, "Entity count decremented")
	_assert(not em.has_entity(id), "Entity no longer exists")


func _test_em_get_entity() -> void:
	var em := EntityManager.new(100, 0)
	var e := em.create_entity("Unit")
	_assert_eq(em.get_entity(e.id), e, "Get entity returns same instance")
	_assert_null(em.get_entity(99999), "Get invalid ID returns null")


func _test_em_query_by_type() -> void:
	var em := EntityManager.new(100, 0)
	em.create_entity("Unit")
	em.create_entity("Unit")
	em.create_entity("Building")
	var units := em.query_by_type("Unit")
	_assert_eq(units.size(), 2, "Query by type finds correct count")
	var buildings := em.query_by_type("Building")
	_assert_eq(buildings.size(), 1, "Query finds buildings")


func _test_em_query_by_component() -> void:
	var em := EntityManager.new(100, 0)
	var e1 := em.create_entity("Unit")
	var c1 := Component.new()
	c1.component_type = "Health"
	em.add_component(e1.id, c1)
	em.create_entity("Unit")  # No component
	var with_health := em.query_entities(["Health"] as Array[String])
	_assert_eq(with_health.size(), 1, "Query by component finds correct count")


func _test_em_query_by_multiple_components() -> void:
	var em := EntityManager.new(100, 0)
	var e1 := em.create_entity("Unit")
	var h1 := Component.new()
	h1.component_type = "Health"
	var m1 := Component.new()
	m1.component_type = "Movement"
	em.add_component(e1.id, h1)
	em.add_component(e1.id, m1)

	var e2 := em.create_entity("Unit")
	var h2 := Component.new()
	h2.component_type = "Health"
	em.add_component(e2.id, h2)

	var both := em.query_entities(["Health", "Movement"] as Array[String])
	_assert_eq(both.size(), 1, "Query multiple components finds correct count")


func _test_em_batch_operations() -> void:
	var em := EntityManager.new(100, 0)
	var entities := em.batch_create_entities("Unit", 10)
	_assert_eq(entities.size(), 10, "Batch create returns correct count")
	var ids: Array[int] = []
	for e in entities:
		ids.append(e.id)
	var destroyed := em.batch_destroy_entities(ids)
	_assert_eq(destroyed, 10, "Batch destroy returns correct count")


func _test_schema_field_definitions() -> void:
	var schema := ComponentSchema.new("Test")
	schema.int_field("count").set_range(0, 100).set_default(10)
	schema.float_field("rate").set_range(0.0, 1.0)
	schema.string_field("name").set_default("default")
	_assert(schema.has_field("count"), "Schema has int field")
	_assert(schema.has_field("rate"), "Schema has float field")
	_assert(schema.has_field("name"), "Schema has string field")


func _test_schema_validation() -> void:
	var schema := ComponentSchema.new("Test")
	schema.int_field("count").set_required(true)
	schema.string_field("name").set_required(true)
	_assert(schema.validate({"count": 5, "name": "test"}), "Valid data passes")
	_assert(not schema.validate({"count": 5}), "Missing required field fails")


func _test_schema_range_validation() -> void:
	var schema := ComponentSchema.new("Test")
	schema.int_field("count").set_range(0, 100)
	_assert(schema.validate({"count": 50}), "In-range value passes")
	_assert(not schema.validate({"count": 150}), "Out-of-range value fails")
	_assert(not schema.validate({"count": -10}), "Below-range value fails")


func _test_schema_defaults() -> void:
	var schema := ComponentSchema.new("Test")
	schema.int_field("count").set_default(42)
	schema.string_field("name").set_default("default")
	var data := schema.apply_defaults({})
	_assert_eq(data.get("count"), 42, "Int default applied")
	_assert_eq(data.get("name"), "default", "String default applied")


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

func _run_integration_tests() -> void:
	print("\n--- Entity Lifecycle Tests ---")
	_test_complete_entity_lifecycle()
	_test_component_lifecycle_hooks()
	_test_entity_serialization_roundtrip()
	_test_entity_pool_reuse()


func _test_complete_entity_lifecycle() -> void:
	var em := EntityManager.new(100, 0)

	# Create
	var e := em.create_entity("Unit")
	_assert_not_null(e, "Entity created")

	# Add components
	var health := HealthComponent.new()
	var movement := MovementComponent.new()
	em.add_component(e.id, health)
	em.add_component(e.id, movement)
	_assert_eq(e.get_component_count(), 2, "Components added")

	# Spawn
	em.spawn_entity(e.id)
	_assert(e.is_spawned, "Entity spawned")

	# Query
	var found := em.query_entities(["HealthComponent", "MovementComponent"] as Array[String])
	_assert_eq(found.size(), 1, "Entity found in query")

	# Despawn
	em.despawn_entity(e.id)
	_assert(not e.is_spawned, "Entity despawned")

	# Destroy
	em.destroy_entity(e.id)
	_assert(not em.has_entity(e.id), "Entity destroyed")


func _test_component_lifecycle_hooks() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp := Component.new()
	comp.component_type = "Test"

	entity.add_component(comp)
	_assert_eq(comp.entity_id, entity.id, "on_attach sets entity_id")

	entity.remove_component("Test")
	_assert_eq(comp.entity_id, -1, "on_detach clears entity_id")


func _test_entity_serialization_roundtrip() -> void:
	var em := EntityManager.new(100, 0)
	var e := em.create_entity("Building")
	var health := HealthComponent.new()
	health.set_current_health(75.0)
	em.add_component(e.id, health)
	em.spawn_entity(e.id)

	# Serialize
	var data := e.to_dict()
	_assert(data.has("id"), "Serialized has id")
	_assert(data.has("components"), "Serialized has components")

	# Deserialize
	var e2 := Entity.from_dict(data)
	_assert_eq(e2.id, e.id, "Deserialized ID matches")
	_assert_eq(e2.entity_type, e.entity_type, "Deserialized type matches")


func _test_entity_pool_reuse() -> void:
	var em := EntityManager.new(50, 0)
	var initial_pool := em.get_pool_size()

	# Create entities (uses pool)
	var entities: Array[Entity] = []
	for i in range(10):
		entities.append(em.create_entity("Unit"))

	# Destroy entities (returns to pool)
	for e in entities:
		em.destroy_entity(e.id)

	_assert(em.get_pool_size() >= initial_pool, "Pool replenished after destruction")


# =============================================================================
# PERFORMANCE BENCHMARKS
# =============================================================================

func _run_performance_benchmarks() -> void:
	print("\n--- Performance Benchmarks ---")
	_benchmark_entity_creation()
	_benchmark_entity_destruction()
	_benchmark_component_operations()
	_benchmark_query_performance()
	_benchmark_5000_entity_update()


func _benchmark_entity_creation() -> void:
	var em := EntityManager.new(2000, 0)
	var count := 1000

	var start := Time.get_ticks_usec()
	for i in range(count):
		em.create_entity("Unit")
	var elapsed := Time.get_ticks_usec() - start

	var per_entity_us := float(elapsed) / count
	print("  Entity creation: %.2f us/entity (%.2f ms total for %d)" % [per_entity_us, elapsed / 1000.0, count])
	_assert_lt(per_entity_us, 1000.0, "Entity creation < 1ms per entity")


func _benchmark_entity_destruction() -> void:
	var em := EntityManager.new(2000, 0)
	var count := 1000
	var ids: Array[int] = []

	for i in range(count):
		var e := em.create_entity("Unit")
		ids.append(e.id)

	var start := Time.get_ticks_usec()
	for id in ids:
		em.destroy_entity(id)
	var elapsed := Time.get_ticks_usec() - start

	var per_entity_us := float(elapsed) / count
	print("  Entity destruction: %.2f us/entity (%.2f ms total for %d)" % [per_entity_us, elapsed / 1000.0, count])
	_assert_lt(per_entity_us, 1000.0, "Entity destruction < 1ms per entity")


func _benchmark_component_operations() -> void:
	var em := EntityManager.new(500, 0)
	var count := 500
	var ids: Array[int] = []

	for i in range(count):
		var e := em.create_entity("Unit")
		ids.append(e.id)

	# Benchmark add
	var start := Time.get_ticks_usec()
	for id in ids:
		var c := Component.new()
		c.component_type = "TestComp"
		em.add_component(id, c)
	var add_elapsed := Time.get_ticks_usec() - start

	# Benchmark remove
	start = Time.get_ticks_usec()
	for id in ids:
		em.remove_component(id, "TestComp")
	var remove_elapsed := Time.get_ticks_usec() - start

	var add_per := float(add_elapsed) / count
	var remove_per := float(remove_elapsed) / count
	print("  Component add: %.2f us/op | remove: %.2f us/op" % [add_per, remove_per])
	_assert_lt(add_per, 100.0, "Component attachment < 0.1ms")
	_assert_lt(remove_per, 100.0, "Component removal < 0.1ms")


func _benchmark_query_performance() -> void:
	var em := EntityManager.new(6000, 0)

	# Create 5000 entities with components
	for i in range(5000):
		var e := em.create_entity("Unit")
		var h := Component.new()
		h.component_type = "Health"
		em.add_component(e.id, h)
		if i % 2 == 0:
			var m := Component.new()
			m.component_type = "Movement"
			em.add_component(e.id, m)

	var iterations := 100
	var start := Time.get_ticks_usec()
	for i in range(iterations):
		em.query_entities(["Health"] as Array[String])
	var elapsed := Time.get_ticks_usec() - start

	var per_query_us := float(elapsed) / iterations
	print("  Query 5000 entities: %.2f us/query (%.2f ms)" % [per_query_us, per_query_us / 1000.0])
	_assert_lt(per_query_us, 500.0, "Query < 0.5ms with 5000 entities")


func _benchmark_5000_entity_update() -> void:
	var em := EntityManager.new(6000, 0)

	# Create and spawn 5000 entities
	for i in range(5000):
		var e := em.create_entity("Unit")
		var h := HealthComponent.new()
		em.add_component(e.id, h)
		em.spawn_entity(e.id)

	# Simulate frame update
	var iterations := 10
	var total_time := 0

	for i in range(iterations):
		var start := Time.get_ticks_usec()
		var entities := em.get_spawned_entities()
		for entity in entities:
			entity.notify_components_update(0.016)  # ~60fps delta
		var elapsed := Time.get_ticks_usec() - start
		total_time += elapsed

	var avg_frame_us := float(total_time) / iterations
	print("  5000 entity update: %.2f ms/frame" % (avg_frame_us / 1000.0))
	_assert_lt(avg_frame_us / 1000.0, 3.0, "5000 entity update < 3ms per frame")


# =============================================================================
# STRESS TESTS
# =============================================================================

func _run_stress_tests() -> void:
	print("\n--- Stress Tests ---")
	_stress_test_10000_entities()
	_stress_test_rapid_queries()
	_stress_test_pool_exhaustion()


func _stress_test_10000_entities() -> void:
	var em := EntityManager.new(12000, 0)

	var start := Time.get_ticks_usec()
	var entities := em.batch_create_entities("Unit", 10000)
	var create_time := Time.get_ticks_usec() - start

	_assert_eq(entities.size(), 10000, "Created 10000 entities")
	print("  Created 10000 entities in %.2f ms" % (create_time / 1000.0))

	# Add components to all
	var ids: Array[int] = []
	for e in entities:
		ids.append(e.id)
		var h := Component.new()
		h.component_type = "Health"
		em.add_component(e.id, h)

	_assert_eq(em.get_entity_count(), 10000, "10000 entities active")

	# Query all
	start = Time.get_ticks_usec()
	var result := em.query_entities(["Health"] as Array[String])
	var query_time := Time.get_ticks_usec() - start

	_assert_eq(result.size(), 10000, "Query finds all 10000")
	print("  Queried 10000 entities in %.2f ms" % (query_time / 1000.0))


func _stress_test_rapid_queries() -> void:
	var em := EntityManager.new(5500, 0)

	for i in range(5000):
		var e := em.create_entity("Unit")
		var h := Component.new()
		h.component_type = "Health"
		em.add_component(e.id, h)

	var query_count := 1000
	var start := Time.get_ticks_usec()
	for i in range(query_count):
		em.query_entities(["Health"] as Array[String])
	var elapsed := Time.get_ticks_usec() - start

	var qps := float(query_count) / (elapsed / 1000000.0)
	print("  Rapid queries: %.0f queries/second" % qps)
	_assert_gt(qps, 1000.0, "Sustained 1000+ queries/second")


func _stress_test_pool_exhaustion() -> void:
	var em := EntityManager.new(100, 0)  # Small pool

	# Exhaust pool
	var entities: Array[Entity] = []
	for i in range(150):
		var e := em.create_entity("Unit")
		if e != null:
			entities.append(e)

	_assert_gt(entities.size(), 100, "Created more entities than initial pool")
	print("  Pool exhaustion: Created %d entities with pool size 100" % entities.size())

	# Return to pool
	for e in entities:
		em.destroy_entity(e.id)

	_assert(em.get_pool_size() > 100, "Pool grew after exhaustion")


# =============================================================================
# DETERMINISM TESTS
# =============================================================================

func _run_determinism_tests() -> void:
	print("\n--- Determinism Tests ---")
	_test_deterministic_entity_ids()
	_test_deterministic_queries()
	_test_serialization_determinism()


func _test_deterministic_entity_ids() -> void:
	# Same seed should produce same IDs
	var em1 := EntityManager.new(10, 12345)
	var ids1: Array[int] = []
	for i in range(5):
		ids1.append(em1.create_entity("Unit").id)

	var em2 := EntityManager.new(10, 12345)
	var ids2: Array[int] = []
	for i in range(5):
		ids2.append(em2.create_entity("Unit").id)

	var ids_match := true
	for i in range(5):
		if ids1[i] != ids2[i]:
			ids_match = false
			break

	_assert(ids_match, "Same seed produces identical entity IDs")


func _test_deterministic_queries() -> void:
	var em := EntityManager.new(100, 0)
	for i in range(10):
		var e := em.create_entity("Unit")
		var c := Component.new()
		c.component_type = "Health"
		em.add_component(e.id, c)

	var result1 := em.query_entities(["Health"] as Array[String])
	var result2 := em.query_entities(["Health"] as Array[String])

	var ids1: Array[int] = []
	var ids2: Array[int] = []
	for e in result1:
		ids1.append(e.id)
	for e in result2:
		ids2.append(e.id)

	_assert_eq(ids1, ids2, "Query results are deterministic")


func _test_serialization_determinism() -> void:
	var entity := Entity.new()
	entity.initialize(42, EntityTypes.Type.UNIT)
	var comp := Component.new()
	comp.component_type = "Test"
	comp.data = {"a": 1, "b": 2}
	entity.add_component(comp)

	var dict1 := entity.to_dict()
	var dict2 := entity.to_dict()

	_assert_eq(str(dict1), str(dict2), "Serialization is deterministic")


# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

func _run_error_handling_tests() -> void:
	print("\n--- Error Handling Tests ---")
	_test_invalid_entity_access()
	_test_duplicate_component()
	_test_invalid_component_removal()


func _test_invalid_entity_access() -> void:
	var em := EntityManager.new(10, 0)
	_assert_null(em.get_entity(99999), "Get invalid entity returns null")
	_assert(not em.destroy_entity(99999), "Destroy invalid entity returns false")
	_assert(not em.add_component(99999, Component.new()), "Add component to invalid entity fails")


func _test_duplicate_component() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	var comp1 := Component.new()
	comp1.component_type = "Test"
	var comp2 := Component.new()
	comp2.component_type = "Test"

	entity.add_component(comp1)
	_assert(not entity.add_component(comp2), "Duplicate component type rejected")


func _test_invalid_component_removal() -> void:
	var entity := Entity.new()
	entity.initialize(1, EntityTypes.Type.UNIT)
	_assert_null(entity.remove_component("NonExistent"), "Remove non-existent returns null")
