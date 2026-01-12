class_name BuilderUnit
extends Unit
## BuilderUnit extends Unit with repair functionality.
## Base class for faction-specific builder variants.

signal repair_started(target_id: int)
signal repair_progress(target_id: int, progress: float)
signal repair_completed(target_id: int)
signal repair_cancelled(target_id: int, reason: String)

## Builder states
enum BuilderState {
	IDLE = 0,
	MOVING_TO_TARGET = 1,
	REPAIRING = 2,
	RETURNING = 3
}

## Builder-specific properties
var repair_speed: float = 0.5  ## Voxels per second repair rate
var scan_radius: float = 20.0  ## Detection range for damaged units
var ree_cost_per_voxel: float = 1.0  ## REE cost per voxel repaired
var max_repair_range: float = 5.0  ## Range at which repair can occur

## Current builder state
var builder_state: int = BuilderState.IDLE

## Repair target tracking
var current_repair_target_id: int = -1
var repair_progress_current: float = 0.0
var repair_progress_total: float = 0.0

## Special abilities flags
var can_repair_while_moving: bool = false
var can_repair_while_dodging: bool = false
var simultaneous_repair_count: int = 1
var infrastructure_repair_multiplier: float = 1.0

## Repair queue for multi-target builders
var repair_queue: Array[int] = []

## Resource tracking
var total_voxels_repaired: float = 0.0
var total_ree_consumed: float = 0.0


func _init() -> void:
	super._init()
	unit_type = "builder"


## Initialize builder with faction-specific stats.
func initialize_builder(builder_faction_id: int, builder_type: String, builder_stats: Dictionary) -> void:
	initialize_unit(Unit.generate_unit_id(), builder_faction_id, builder_type)

	# Apply builder-specific stats
	repair_speed = builder_stats.get("repair_speed", 0.5)
	scan_radius = builder_stats.get("scan_radius", 20.0)
	ree_cost_per_voxel = builder_stats.get("ree_cost_per_voxel", 1.0)
	max_repair_range = builder_stats.get("max_repair_range", 5.0)

	# Apply special abilities
	can_repair_while_moving = builder_stats.get("can_repair_while_moving", false)
	can_repair_while_dodging = builder_stats.get("can_repair_while_dodging", false)
	simultaneous_repair_count = builder_stats.get("simultaneous_repair_count", 1)
	infrastructure_repair_multiplier = builder_stats.get("infrastructure_repair_multiplier", 1.0)

	# Apply health stats
	var health := get_health()
	if health != null:
		health.set_max_health(builder_stats.get("max_health", 20.0))
		health.set_current_health(builder_stats.get("max_health", 20.0))

	# Apply movement stats
	var movement := get_movement()
	if movement != null:
		movement.data["max_speed"] = builder_stats.get("max_speed", 5.0)


## Set repair target.
func set_repair_target(target_id: int, total_damage: float) -> bool:
	if current_repair_target_id == target_id:
		return true  # Already targeting

	# Cancel current repair if any
	if current_repair_target_id != -1:
		cancel_repair("new_target")

	current_repair_target_id = target_id
	repair_progress_current = 0.0
	repair_progress_total = total_damage
	builder_state = BuilderState.MOVING_TO_TARGET

	return true


## Start repair process (called when in range).
func start_repair() -> void:
	if current_repair_target_id == -1:
		return

	builder_state = BuilderState.REPAIRING
	repair_started.emit(current_repair_target_id)


## Update repair progress.
## Returns the amount repaired this frame.
func update_repair(delta: float, is_infrastructure: bool = false) -> float:
	if builder_state != BuilderState.REPAIRING:
		return 0.0

	if current_repair_target_id == -1:
		return 0.0

	# Check if we can repair while moving
	if not can_repair_while_moving:
		var movement := get_movement()
		if movement != null and movement.is_moving():
			return 0.0

	# Calculate repair amount
	var repair_rate := repair_speed
	if is_infrastructure:
		repair_rate *= infrastructure_repair_multiplier

	var repair_amount := repair_rate * delta
	repair_progress_current += repair_amount
	total_voxels_repaired += repair_amount
	total_ree_consumed += repair_amount * ree_cost_per_voxel

	# Emit progress
	var progress_percent := 0.0
	if repair_progress_total > 0:
		progress_percent = repair_progress_current / repair_progress_total

	repair_progress.emit(current_repair_target_id, progress_percent)

	# Check if repair complete
	if repair_progress_current >= repair_progress_total:
		complete_repair()

	return repair_amount


## Complete the current repair.
func complete_repair() -> void:
	if current_repair_target_id == -1:
		return

	var completed_target := current_repair_target_id
	repair_completed.emit(completed_target)

	# Reset repair state
	current_repair_target_id = -1
	repair_progress_current = 0.0
	repair_progress_total = 0.0
	builder_state = BuilderState.IDLE

	# Check repair queue for multi-target builders
	if not repair_queue.is_empty():
		var next_target := repair_queue.pop_front()
		set_repair_target(next_target, 1.0)  # Damage amount would be fetched


## Cancel the current repair.
func cancel_repair(reason: String) -> void:
	if current_repair_target_id == -1:
		return

	var cancelled_target := current_repair_target_id
	repair_cancelled.emit(cancelled_target, reason)

	current_repair_target_id = -1
	repair_progress_current = 0.0
	repair_progress_total = 0.0
	builder_state = BuilderState.IDLE


## Add target to repair queue (for multi-target builders).
func queue_repair_target(target_id: int) -> void:
	if target_id not in repair_queue:
		repair_queue.append(target_id)


## Get current repair progress as percentage (0.0 to 1.0).
func get_repair_progress_percent() -> float:
	if repair_progress_total <= 0:
		return 0.0
	return clampf(repair_progress_current / repair_progress_total, 0.0, 1.0)


## Check if builder is currently repairing.
func is_repairing() -> bool:
	return builder_state == BuilderState.REPAIRING


## Check if builder is idle.
func is_idle() -> bool:
	return builder_state == BuilderState.IDLE


## Get builder state name for debugging.
func get_builder_state_name() -> String:
	match builder_state:
		BuilderState.IDLE: return "IDLE"
		BuilderState.MOVING_TO_TARGET: return "MOVING_TO_TARGET"
		BuilderState.REPAIRING: return "REPAIRING"
		BuilderState.RETURNING: return "RETURNING"
		_: return "UNKNOWN"


## Override reset for object pooling.
func reset() -> void:
	super.reset()
	builder_state = BuilderState.IDLE
	current_repair_target_id = -1
	repair_progress_current = 0.0
	repair_progress_total = 0.0
	repair_queue.clear()
	total_voxels_repaired = 0.0
	total_ree_consumed = 0.0


## Override serialization.
func to_dict() -> Dictionary:
	var base := super.to_dict()

	base["builder"] = {
		"repair_speed": repair_speed,
		"scan_radius": scan_radius,
		"ree_cost_per_voxel": ree_cost_per_voxel,
		"max_repair_range": max_repair_range,
		"builder_state": builder_state,
		"current_repair_target_id": current_repair_target_id,
		"repair_progress_current": repair_progress_current,
		"repair_progress_total": repair_progress_total,
		"can_repair_while_moving": can_repair_while_moving,
		"can_repair_while_dodging": can_repair_while_dodging,
		"simultaneous_repair_count": simultaneous_repair_count,
		"infrastructure_repair_multiplier": infrastructure_repair_multiplier,
		"total_voxels_repaired": total_voxels_repaired,
		"total_ree_consumed": total_ree_consumed,
		"repair_queue": repair_queue.duplicate()
	}

	return base


## Override deserialization.
static func from_dict(data: Dictionary) -> BuilderUnit:
	var builder := BuilderUnit.new()

	# Restore Unit properties
	builder.id = data.get("id", -1)
	builder.id_string = data.get("id_string", "")
	builder.entity_type = data.get("entity_type", "Unit")
	builder.type_enum = data.get("type_enum", EntityTypes.Type.UNIT)
	builder.is_active = data.get("is_active", true)
	builder.is_spawned = data.get("is_spawned", false)
	builder.spawn_time = data.get("spawn_time", 0)
	builder.despawn_time = data.get("despawn_time", 0)
	builder.name = builder.id_string

	var unit_data: Dictionary = data.get("unit", {})
	builder.faction_id = unit_data.get("faction_id", 0)
	builder.unit_type = unit_data.get("unit_type", "builder")
	builder.current_state = unit_data.get("current_state", State.IDLE)
	builder.is_alive = unit_data.get("is_alive", true)

	# Restore builder properties
	var builder_data: Dictionary = data.get("builder", {})
	builder.repair_speed = builder_data.get("repair_speed", 0.5)
	builder.scan_radius = builder_data.get("scan_radius", 20.0)
	builder.ree_cost_per_voxel = builder_data.get("ree_cost_per_voxel", 1.0)
	builder.max_repair_range = builder_data.get("max_repair_range", 5.0)
	builder.builder_state = builder_data.get("builder_state", BuilderState.IDLE)
	builder.current_repair_target_id = builder_data.get("current_repair_target_id", -1)
	builder.repair_progress_current = builder_data.get("repair_progress_current", 0.0)
	builder.repair_progress_total = builder_data.get("repair_progress_total", 0.0)
	builder.can_repair_while_moving = builder_data.get("can_repair_while_moving", false)
	builder.can_repair_while_dodging = builder_data.get("can_repair_while_dodging", false)
	builder.simultaneous_repair_count = builder_data.get("simultaneous_repair_count", 1)
	builder.infrastructure_repair_multiplier = builder_data.get("infrastructure_repair_multiplier", 1.0)
	builder.total_voxels_repaired = builder_data.get("total_voxels_repaired", 0.0)
	builder.total_ree_consumed = builder_data.get("total_ree_consumed", 0.0)

	builder.repair_queue.clear()
	for target_id in builder_data.get("repair_queue", []):
		builder.repair_queue.append(int(target_id))

	return builder


## Get builder summary for debugging.
func get_builder_summary() -> Dictionary:
	var summary := get_summary()
	summary["builder_state"] = get_builder_state_name()
	summary["repair_target"] = current_repair_target_id
	summary["repair_progress"] = get_repair_progress_percent()
	summary["repair_speed"] = repair_speed
	summary["total_repaired"] = total_voxels_repaired
	return summary


## Static factory methods for faction-specific builders

## Create Aether Swarm Nano-Welder.
static func create_nano_welder(position: Vector3 = Vector3.ZERO) -> BuilderUnit:
	var builder := BuilderUnit.new()
	builder.initialize_builder(1, "nano_welder", {
		"max_health": 15.0,
		"max_speed": 7.0,
		"repair_speed": 0.5,
		"scan_radius": 25.0,
		"ree_cost_per_voxel": 0.8,
		"max_repair_range": 6.0,
		"can_repair_while_moving": true,
		"can_repair_while_dodging": false,
		"simultaneous_repair_count": 1,
		"infrastructure_repair_multiplier": 1.0
	})
	builder.set_position(position)
	return builder


## Create OptiForge Legion Repair Drone.
static func create_repair_drone(position: Vector3 = Vector3.ZERO) -> BuilderUnit:
	var builder := BuilderUnit.new()
	builder.initialize_builder(2, "repair_drone", {
		"max_health": 25.0,
		"max_speed": 5.0,
		"repair_speed": 0.75,
		"scan_radius": 20.0,
		"ree_cost_per_voxel": 1.0,
		"max_repair_range": 5.0,
		"can_repair_while_moving": false,
		"can_repair_while_dodging": false,
		"simultaneous_repair_count": 1,
		"infrastructure_repair_multiplier": 1.5
	})
	builder.set_position(position)
	return builder


## Create Dynapods Vanguard Swift Fixer.
static func create_swift_fixer(position: Vector3 = Vector3.ZERO) -> BuilderUnit:
	var builder := BuilderUnit.new()
	builder.initialize_builder(3, "swift_fixer", {
		"max_health": 20.0,
		"max_speed": 8.5,
		"repair_speed": 0.6,
		"scan_radius": 22.0,
		"ree_cost_per_voxel": 0.9,
		"max_repair_range": 5.0,
		"can_repair_while_moving": false,
		"can_repair_while_dodging": true,
		"simultaneous_repair_count": 1,
		"infrastructure_repair_multiplier": 1.0
	})
	builder.set_position(position)
	return builder


## Create LogiBots Colossus Heavy Reconstructor.
static func create_heavy_reconstructor(position: Vector3 = Vector3.ZERO) -> BuilderUnit:
	var builder := BuilderUnit.new()
	builder.initialize_builder(4, "heavy_reconstructor", {
		"max_health": 40.0,
		"max_speed": 3.5,
		"repair_speed": 1.0,
		"scan_radius": 18.0,
		"ree_cost_per_voxel": 1.2,
		"max_repair_range": 4.0,
		"can_repair_while_moving": false,
		"can_repair_while_dodging": false,
		"simultaneous_repair_count": 3,
		"infrastructure_repair_multiplier": 1.0
	})
	builder.set_position(position)
	return builder


## Create builder for any faction by faction ID.
static func create_for_faction(faction_id: int, position: Vector3 = Vector3.ZERO) -> BuilderUnit:
	match faction_id:
		1: return create_nano_welder(position)
		2: return create_repair_drone(position)
		3: return create_swift_fixer(position)
		4: return create_heavy_reconstructor(position)
		_: return null
