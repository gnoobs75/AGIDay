class_name ClientPrediction
extends RefCounted
## ClientPrediction provides client-side prediction and interpolation for smooth visuals.
## Predicts local player actions and interpolates between server snapshots.

signal prediction_corrected(entity_id: int, correction_amount: float)
signal snapshot_interpolated(progress: float)

## Configuration
const INTERPOLATION_DELAY := 0.1    ## Seconds behind server time for interpolation
const MAX_PREDICTION_FRAMES := 30   ## Max frames to predict ahead
const CORRECTION_THRESHOLD := 0.5   ## Distance threshold for immediate snap vs smooth correction
const CORRECTION_SPEED := 10.0      ## Speed of smooth corrections

## Snapshot buffer for interpolation
var _snapshot_buffer: Array[Dictionary] = []
const MAX_SNAPSHOT_BUFFER := 32

## Prediction state
var _predicted_inputs: Array[Dictionary] = []
var _last_processed_input := 0
var _prediction_error := Vector3.ZERO

## Interpolation state
var _interpolation_time := 0.0
var _render_time := 0.0

## Entity states
var _predicted_states: Dictionary = {}   ## entity_id -> predicted state
var _display_states: Dictionary = {}     ## entity_id -> interpolated display state
var _server_states: Dictionary = {}      ## entity_id -> last confirmed server state


func _init() -> void:
	pass


## Update prediction and interpolation (call each frame).
func update(delta: float) -> void:
	_interpolation_time += delta
	_render_time = _interpolation_time - INTERPOLATION_DELAY

	# Update interpolation for all entities
	_update_interpolation()

	# Apply smooth corrections to predicted entities
	_apply_corrections(delta)


## Add input for prediction.
func add_input(input_frame: int, input_data: Dictionary) -> void:
	_predicted_inputs.append({
		"frame": input_frame,
		"data": input_data,
		"timestamp": Time.get_ticks_msec()
	})

	# Limit prediction buffer size
	while _predicted_inputs.size() > MAX_PREDICTION_FRAMES:
		_predicted_inputs.pop_front()


## Predict entity state based on input.
func predict_entity(entity_id: int, base_state: Dictionary, input_data: Dictionary) -> Dictionary:
	var predicted := base_state.duplicate(true)

	# Apply movement prediction
	if input_data.has("move_direction"):
		var move_dir: Vector3 = input_data["move_direction"]
		var speed: float = base_state.get("speed", 5.0)
		var delta: float = input_data.get("delta", 1.0 / 60.0)

		if predicted.has("position"):
			predicted["position"] = predicted["position"] + move_dir * speed * delta

	# Apply rotation prediction
	if input_data.has("rotation"):
		predicted["rotation"] = input_data["rotation"]

	_predicted_states[entity_id] = predicted
	return predicted


## Receive server snapshot for interpolation.
func receive_snapshot(snapshot: Dictionary) -> void:
	var server_time: float = snapshot.get("timestamp", 0) / 1000.0

	_snapshot_buffer.append({
		"time": server_time,
		"data": snapshot
	})

	# Sort by time
	_snapshot_buffer.sort_custom(func(a, b): return a["time"] < b["time"])

	# Limit buffer size
	while _snapshot_buffer.size() > MAX_SNAPSHOT_BUFFER:
		_snapshot_buffer.pop_front()

	# Update server states
	var entities: Dictionary = snapshot.get("entities", snapshot.get("changes", {}))
	for entity_id_str in entities:
		var entity_id := int(entity_id_str)
		_server_states[entity_id] = entities[entity_id_str]

	# Check prediction accuracy
	_reconcile_predictions(snapshot)


## Reconcile predictions with server state.
func _reconcile_predictions(snapshot: Dictionary) -> void:
	var server_frame: int = snapshot.get("id", 0)

	# Remove processed inputs
	var inputs_to_remove: Array[int] = []
	for i in _predicted_inputs.size():
		if _predicted_inputs[i]["frame"] <= server_frame:
			inputs_to_remove.append(i)

	for i in range(inputs_to_remove.size() - 1, -1, -1):
		_predicted_inputs.remove_at(inputs_to_remove[i])

	_last_processed_input = server_frame

	# Check for prediction errors
	var entities: Dictionary = snapshot.get("entities", snapshot.get("changes", {}))
	for entity_id_str in entities:
		var entity_id := int(entity_id_str)
		if not _predicted_states.has(entity_id):
			continue

		var server_state: Dictionary = entities[entity_id_str]
		var predicted_state: Dictionary = _predicted_states[entity_id]

		# Calculate position error
		if server_state.has("position") and predicted_state.has("position"):
			var server_pos: Vector3 = server_state["position"]
			var predicted_pos: Vector3 = predicted_state["position"]
			var error := server_pos.distance_to(predicted_pos)

			if error > 0.01:
				_schedule_correction(entity_id, server_pos, error)


## Schedule a correction for an entity.
func _schedule_correction(entity_id: int, target_pos: Vector3, error: float) -> void:
	if error > CORRECTION_THRESHOLD:
		# Large error: snap immediately
		if _predicted_states.has(entity_id):
			_predicted_states[entity_id]["position"] = target_pos
		prediction_corrected.emit(entity_id, error)
	else:
		# Small error: smooth correction
		_prediction_error = target_pos - _predicted_states.get(entity_id, {}).get("position", target_pos)


## Apply smooth corrections.
func _apply_corrections(delta: float) -> void:
	if _prediction_error.length() < 0.001:
		return

	var correction := _prediction_error * CORRECTION_SPEED * delta
	if correction.length() > _prediction_error.length():
		correction = _prediction_error

	# Apply correction to all predicted entities
	for entity_id in _predicted_states:
		if _predicted_states[entity_id].has("position"):
			_predicted_states[entity_id]["position"] += correction

	_prediction_error -= correction


## Update interpolation between snapshots.
func _update_interpolation() -> void:
	if _snapshot_buffer.size() < 2:
		# Not enough snapshots, use latest
		if _snapshot_buffer.size() == 1:
			_apply_snapshot_to_display(_snapshot_buffer[0]["data"])
		return

	# Find two snapshots to interpolate between
	var from_snapshot: Dictionary = {}
	var to_snapshot: Dictionary = {}
	var found := false

	for i in range(_snapshot_buffer.size() - 1):
		var current := _snapshot_buffer[i]
		var next := _snapshot_buffer[i + 1]

		if current["time"] <= _render_time and next["time"] >= _render_time:
			from_snapshot = current
			to_snapshot = next
			found = true
			break

	if not found:
		# Render time is beyond buffer, use latest
		_apply_snapshot_to_display(_snapshot_buffer[-1]["data"])
		return

	# Calculate interpolation factor
	var time_range := to_snapshot["time"] - from_snapshot["time"]
	var t := 0.0
	if time_range > 0:
		t = (_render_time - from_snapshot["time"]) / time_range
	t = clampf(t, 0.0, 1.0)

	# Interpolate between snapshots
	_interpolate_snapshots(from_snapshot["data"], to_snapshot["data"], t)
	snapshot_interpolated.emit(t)


## Interpolate between two snapshots.
func _interpolate_snapshots(from_data: Dictionary, to_data: Dictionary, t: float) -> void:
	var from_entities: Dictionary = from_data.get("entities", from_data.get("changes", {}))
	var to_entities: Dictionary = to_data.get("entities", to_data.get("changes", {}))

	# Get all entity IDs
	var all_ids: Dictionary = {}
	for id in from_entities:
		all_ids[id] = true
	for id in to_entities:
		all_ids[id] = true

	# Interpolate each entity
	for entity_id_str in all_ids:
		var entity_id := int(entity_id_str)
		var from_state: Dictionary = from_entities.get(entity_id_str, {})
		var to_state: Dictionary = to_entities.get(entity_id_str, {})

		if from_state.is_empty():
			_display_states[entity_id] = to_state.duplicate(true)
		elif to_state.is_empty():
			_display_states[entity_id] = from_state.duplicate(true)
		else:
			_display_states[entity_id] = _interpolate_entity_state(from_state, to_state, t)


## Interpolate a single entity's state.
func _interpolate_entity_state(from_state: Dictionary, to_state: Dictionary, t: float) -> Dictionary:
	var result := from_state.duplicate(true)

	# Interpolate position
	if from_state.has("position") and to_state.has("position"):
		var from_pos: Vector3 = from_state["position"]
		var to_pos: Vector3 = to_state["position"]
		result["position"] = from_pos.lerp(to_pos, t)

	# Interpolate rotation
	if from_state.has("rotation") and to_state.has("rotation"):
		var from_rot = from_state["rotation"]
		var to_rot = to_state["rotation"]
		if from_rot is float and to_rot is float:
			result["rotation"] = lerpf(from_rot, to_rot, t)
		elif from_rot is Vector3 and to_rot is Vector3:
			result["rotation"] = from_rot.lerp(to_rot, t)

	# Interpolate scale
	if from_state.has("scale") and to_state.has("scale"):
		var from_scale: Vector3 = from_state["scale"]
		var to_scale: Vector3 = to_state["scale"]
		result["scale"] = from_scale.lerp(to_scale, t)

	# Don't interpolate discrete values (health, ammo, etc.)
	# Just use the latest value
	for key in to_state:
		if key not in ["position", "rotation", "scale"]:
			result[key] = to_state[key]

	return result


## Apply snapshot directly to display (no interpolation).
func _apply_snapshot_to_display(snapshot: Dictionary) -> void:
	var entities: Dictionary = snapshot.get("entities", snapshot.get("changes", {}))
	for entity_id_str in entities:
		var entity_id := int(entity_id_str)
		_display_states[entity_id] = entities[entity_id_str].duplicate(true)


## Get predicted state for an entity.
func get_predicted_state(entity_id: int) -> Dictionary:
	return _predicted_states.get(entity_id, {})


## Get display state (interpolated) for an entity.
func get_display_state(entity_id: int) -> Dictionary:
	return _display_states.get(entity_id, {})


## Get server-confirmed state for an entity.
func get_server_state(entity_id: int) -> Dictionary:
	return _server_states.get(entity_id, {})


## Check if entity has predicted state.
func has_predicted_state(entity_id: int) -> bool:
	return _predicted_states.has(entity_id)


## Clear predicted state for an entity.
func clear_entity_prediction(entity_id: int) -> void:
	_predicted_states.erase(entity_id)
	_display_states.erase(entity_id)


## Get current render time.
func get_render_time() -> float:
	return _render_time


## Get prediction statistics.
func get_stats() -> Dictionary:
	return {
		"snapshot_buffer_size": _snapshot_buffer.size(),
		"predicted_inputs": _predicted_inputs.size(),
		"predicted_entities": _predicted_states.size(),
		"interpolation_time": _interpolation_time,
		"render_time": _render_time,
		"prediction_error": _prediction_error.length()
	}


## Clear all state.
func clear() -> void:
	_snapshot_buffer.clear()
	_predicted_inputs.clear()
	_predicted_states.clear()
	_display_states.clear()
	_server_states.clear()
	_interpolation_time = 0.0
	_render_time = 0.0
	_prediction_error = Vector3.ZERO
