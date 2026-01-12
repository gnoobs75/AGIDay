class_name CityGenerationSeed
extends RefCounted
## CityGenerationSeed manages deterministic seed derivation for city generation.
## Ensures identical results across platforms from the same master seed.

## Master seed
var master_seed: int = 0

## Derived sub-seeds
var zone_seed: int = 0
var building_seed: int = 0
var resource_seed: int = 0
var power_seed: int = 0
var road_seed: int = 0
var decoration_seed: int = 0

## Seed derivation constants (prime numbers for mixing)
const ZONE_PRIME := 73856093
const BUILDING_PRIME := 19349663
const RESOURCE_PRIME := 83492791
const POWER_PRIME := 47116179
const ROAD_PRIME := 31415927
const DECORATION_PRIME := 14159265

## Hash mixing constant
const HASH_CONST := 0x9E3779B9


func _init(seed: int = 0) -> void:
	if seed != 0:
		initialize(seed)


## Initialize from master seed.
func initialize(seed: int) -> void:
	master_seed = seed
	_derive_sub_seeds()


## Derive all sub-seeds from master.
func _derive_sub_seeds() -> void:
	zone_seed = _derive_seed(master_seed, ZONE_PRIME)
	building_seed = _derive_seed(master_seed, BUILDING_PRIME)
	resource_seed = _derive_seed(master_seed, RESOURCE_PRIME)
	power_seed = _derive_seed(master_seed, POWER_PRIME)
	road_seed = _derive_seed(master_seed, ROAD_PRIME)
	decoration_seed = _derive_seed(master_seed, DECORATION_PRIME)


## Derive a sub-seed using consistent cross-platform hash.
func _derive_seed(base_seed: int, multiplier: int) -> int:
	return cross_platform_hash(base_seed ^ multiplier)


## Cross-platform consistent hash function.
## Uses 32-bit operations to ensure identical results on all platforms.
static func cross_platform_hash(value: int) -> int:
	# Ensure 32-bit range
	var h := value & 0xFFFFFFFF

	# MurmurHash3 finalizer (32-bit)
	h = h ^ (h >> 16)
	h = (h * 0x85EBCA6B) & 0xFFFFFFFF
	h = h ^ (h >> 13)
	h = (h * 0xC2B2AE35) & 0xFFFFFFFF
	h = h ^ (h >> 16)

	return h


## Get seed for specific zone position.
func get_zone_position_seed(x: int, y: int) -> int:
	return cross_platform_hash(zone_seed ^ (x * ZONE_PRIME + y * BUILDING_PRIME))


## Get seed for specific building position.
func get_building_position_seed(x: int, y: int) -> int:
	return cross_platform_hash(building_seed ^ (x * BUILDING_PRIME + y * RESOURCE_PRIME))


## Get seed for resource at position.
func get_resource_position_seed(x: int, y: int) -> int:
	return cross_platform_hash(resource_seed ^ (x * RESOURCE_PRIME + y * POWER_PRIME))


## Get seed for wave number.
func get_wave_seed(wave_number: int) -> int:
	return cross_platform_hash(master_seed ^ (wave_number * ROAD_PRIME))


## Get seed for specific generation phase.
func get_phase_seed(phase_name: String) -> int:
	var phase_hash := string_hash(phase_name)
	return cross_platform_hash(master_seed ^ phase_hash)


## Cross-platform string hash.
static func string_hash(s: String) -> int:
	var h := 0
	for c in s:
		h = ((h << 5) - h + c.unicode_at(0)) & 0xFFFFFFFF
	return h


## Create seeded RNG for zone generation.
func create_zone_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = zone_seed
	return rng


## Create seeded RNG for building generation.
func create_building_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = building_seed
	return rng


## Create seeded RNG for resource generation.
func create_resource_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = resource_seed
	return rng


## Create seeded RNG for power grid generation.
func create_power_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = power_seed
	return rng


## Create seeded RNG for road generation.
func create_road_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = road_seed
	return rng


## Create seeded RNG for custom phase.
func create_phase_rng(phase_name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = get_phase_seed(phase_name)
	return rng


## Verify seed consistency (for testing).
static func verify_consistency(seed: int) -> bool:
	var gen1 := CityGenerationSeed.new(seed)
	var gen2 := CityGenerationSeed.new(seed)

	if gen1.zone_seed != gen2.zone_seed:
		return false
	if gen1.building_seed != gen2.building_seed:
		return false
	if gen1.resource_seed != gen2.resource_seed:
		return false

	return true


## Generate random master seed.
static func generate_random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"master_seed": master_seed,
		"zone_seed": zone_seed,
		"building_seed": building_seed,
		"resource_seed": resource_seed,
		"power_seed": power_seed,
		"road_seed": road_seed,
		"decoration_seed": decoration_seed
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> CityGenerationSeed:
	var seed_mgr := CityGenerationSeed.new()
	seed_mgr.master_seed = data.get("master_seed", 0)
	seed_mgr.zone_seed = data.get("zone_seed", 0)
	seed_mgr.building_seed = data.get("building_seed", 0)
	seed_mgr.resource_seed = data.get("resource_seed", 0)
	seed_mgr.power_seed = data.get("power_seed", 0)
	seed_mgr.road_seed = data.get("road_seed", 0)
	seed_mgr.decoration_seed = data.get("decoration_seed", 0)
	return seed_mgr


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"master": master_seed,
		"zone": zone_seed,
		"building": building_seed,
		"resource": resource_seed,
		"power": power_seed
	}
