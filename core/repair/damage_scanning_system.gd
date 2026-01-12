class_name DamageScanningSystem
extends RefCounted
## DamageScanningSystem manages damage scanners for multiple builder units.

signal scanner_registered(scanner_id: int)
signal scanner_unregistered(scanner_id: int)
signal scan_completed(scanner_id: int, damaged_count: int)
signal damaged_voxel_detected(scanner_id: int, position: Vector3i, damage_stage: int)

## Maximum simultaneous scanners
const MAX_SCANNERS := 100

## Scan update frequency
const SCAN_INTERVAL := 0.5  ## Seconds between automated scans

## Active scanners
var _scanners: Dictionary = {}  ## scanner_id -> DamageScanner

## Voxel grid callback
var _get_voxel_state_callback: Callable = Callable()

## Update timing
var _time_since_scan: float = 0.0
var _auto_scan_enabled: bool = true

## Scan queue for staggered scanning
var _scan_queue: Array[int] = []
var _scanners_per_frame: int = 5


func _init() -> void:
	pass


## Set voxel state callback.
## Callback signature: func(position: Vector3i) -> int
func set_voxel_state_callback(callback: Callable) -> void:
	_get_voxel_state_callback = callback


## Register a scanner for a builder unit.
func register_scanner(scanner_id: int, faction_id: String = "") -> DamageScanner:
	if _scanners.size() >= MAX_SCANNERS:
		push_warning("Maximum scanners reached")
		return null

	if _scanners.has(scanner_id):
		return _scanners[scanner_id]

	var scanner := DamageScanner.new()
	scanner.initialize(scanner_id, faction_id)

	# Connect signals
	scanner.scan_completed.connect(_on_scan_completed)
	scanner.damaged_voxel_found.connect(_on_damaged_voxel_found.bind(scanner_id))

	_scanners[scanner_id] = scanner
	scanner_registered.emit(scanner_id)

	return scanner


## Unregister a scanner.
func unregister_scanner(scanner_id: int) -> void:
	if not _scanners.has(scanner_id):
		return

	# Remove from queue
	var queue_idx := _scan_queue.find(scanner_id)
	if queue_idx != -1:
		_scan_queue.remove_at(queue_idx)

	_scanners.erase(scanner_id)
	scanner_unregistered.emit(scanner_id)


## Get a scanner.
func get_scanner(scanner_id: int) -> DamageScanner:
	return _scanners.get(scanner_id)


## Update scanner position.
func update_scanner_position(scanner_id: int, position: Vector3) -> void:
	if _scanners.has(scanner_id):
		_scanners[scanner_id].set_scan_position(position)


## Perform scan for a specific scanner.
func perform_scan(scanner_id: int) -> Array:
	if not _scanners.has(scanner_id):
		return []

	if not _get_voxel_state_callback.is_valid():
		push_warning("No voxel state callback set")
		return []

	var scanner: DamageScanner = _scanners[scanner_id]
	return scanner.scan_for_damaged_voxels(_get_voxel_state_callback)


## Update system (call each frame).
func update(delta: float) -> void:
	if not _auto_scan_enabled:
		return

	_time_since_scan += delta

	if _time_since_scan >= SCAN_INTERVAL:
		_time_since_scan = 0.0
		_queue_all_scans()

	# Process scan queue
	_process_scan_queue()


## Queue all scanners for scanning.
func _queue_all_scans() -> void:
	_scan_queue.clear()
	for scanner_id in _scanners:
		_scan_queue.append(scanner_id)


## Process scan queue (staggered scanning).
func _process_scan_queue() -> void:
	if _scan_queue.is_empty():
		return

	if not _get_voxel_state_callback.is_valid():
		return

	var scans_this_frame := mini(_scanners_per_frame, _scan_queue.size())

	for i in scans_this_frame:
		if _scan_queue.is_empty():
			break

		var scanner_id: int = _scan_queue.pop_front()
		if _scanners.has(scanner_id):
			_scanners[scanner_id].scan_for_damaged_voxels(_get_voxel_state_callback)


## Handle scan completed.
func _on_scan_completed(scanner_id: int, damaged_count: int) -> void:
	scan_completed.emit(scanner_id, damaged_count)


## Handle damaged voxel found.
func _on_damaged_voxel_found(position: Vector3i, damage_stage: int, scanner_id: int) -> void:
	damaged_voxel_detected.emit(scanner_id, position, damage_stage)


## Get all damaged voxels found by all scanners.
func get_all_damaged_voxels() -> Array[Vector3i]:
	var all_positions: Array[Vector3i] = []
	var seen: Dictionary = {}

	for scanner_id in _scanners:
		var scanner: DamageScanner = _scanners[scanner_id]
		for pos in scanner.get_damaged_positions():
			var key := "%d,%d,%d" % [pos.x, pos.y, pos.z]
			if not seen.has(key):
				seen[key] = true
				all_positions.append(pos)

	return all_positions


## Get closest damaged voxel to a position.
func get_closest_damaged_to(position: Vector3) -> DamageScanner.DamagedVoxelInfo:
	var closest: DamageScanner.DamagedVoxelInfo = null
	var closest_distance := INF

	for scanner_id in _scanners:
		var scanner: DamageScanner = _scanners[scanner_id]
		for info in scanner.get_last_scan_results():
			var distance := position.distance_to(info.world_position)
			if distance < closest_distance:
				closest_distance = distance
				closest = info

	return closest


## Enable/disable auto scanning.
func set_auto_scan_enabled(enabled: bool) -> void:
	_auto_scan_enabled = enabled


## Set scanners per frame for load balancing.
func set_scanners_per_frame(count: int) -> void:
	_scanners_per_frame = maxi(count, 1)


## Force scan all scanners immediately.
func force_scan_all() -> void:
	if not _get_voxel_state_callback.is_valid():
		return

	for scanner_id in _scanners:
		_scanners[scanner_id].scan_for_damaged_voxels(_get_voxel_state_callback)


## Get scanner count.
func get_scanner_count() -> int:
	return _scanners.size()


## Get all scanner IDs.
func get_all_scanner_ids() -> Array[int]:
	var ids: Array[int] = []
	for scanner_id in _scanners:
		ids.append(scanner_id)
	return ids


## Clear all scanners.
func clear() -> void:
	for scanner_id in _scanners.keys():
		unregister_scanner(scanner_id)
	_scan_queue.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var total_damaged := 0
	for scanner_id in _scanners:
		total_damaged += _scanners[scanner_id].get_damaged_count()

	return {
		"scanner_count": _scanners.size(),
		"queue_size": _scan_queue.size(),
		"total_damaged_found": total_damaged,
		"auto_scan_enabled": _auto_scan_enabled,
		"has_callback": _get_voxel_state_callback.is_valid()
	}
