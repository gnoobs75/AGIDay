class_name RPCValidator
extends RefCounted
## RPCValidator handles RPC input validation, rate limiting, and anti-cheat validation.
## All RPCs must use snake_case with rpc_ prefix.

signal rpc_blocked(peer_id: int, reason: String)
signal rate_limit_exceeded(peer_id: int)
signal cheat_detected(peer_id: int, action_type: String, details: String)

## Rate limiting configuration
const RPC_RATE_LIMIT := 60      ## Max RPCs per second per client
const RPC_BURST_LIMIT := 10     ## Max burst RPCs
const RATE_WINDOW := 1.0        ## Window in seconds for rate calculation

## Validation configuration
const MAX_STRING_LENGTH := 256
const MAX_ARRAY_SIZE := 100
const MAX_DICT_SIZE := 50

## Rate tracking
var _rpc_counts: Dictionary = {}         ## peer_id -> {count: int, window_start: float, burst: int}
var _last_rpc_time: Dictionary = {}      ## peer_id -> float

## Registered RPC schemas
var _rpc_schemas: Dictionary = {}        ## method_name -> {params: Array, types: Array}

## Action validation rules
var _action_validators: Dictionary = {}  ## action_type -> Callable

## Blocked peers
var _blocked_peers: Dictionary = {}      ## peer_id -> unblock_time


func _init() -> void:
	_register_default_schemas()


## Register default RPC schemas.
func _register_default_schemas() -> void:
	# Movement RPC
	register_rpc_schema("rpc_move_unit", [
		{"name": "unit_id", "type": TYPE_INT},
		{"name": "target_position", "type": TYPE_VECTOR3}
	])

	# Attack RPC
	register_rpc_schema("rpc_attack_target", [
		{"name": "attacker_id", "type": TYPE_INT},
		{"name": "target_id", "type": TYPE_INT}
	])

	# Ability RPC
	register_rpc_schema("rpc_use_ability", [
		{"name": "unit_id", "type": TYPE_INT},
		{"name": "ability_id", "type": TYPE_STRING},
		{"name": "target_position", "type": TYPE_VECTOR3, "optional": true}
	])

	# Build RPC
	register_rpc_schema("rpc_build_unit", [
		{"name": "factory_id", "type": TYPE_INT},
		{"name": "unit_type", "type": TYPE_STRING}
	])

	# Input RPC
	register_rpc_schema("rpc_player_input", [
		{"name": "frame", "type": TYPE_INT},
		{"name": "input_data", "type": TYPE_DICTIONARY}
	])


## Register an RPC schema for validation.
func register_rpc_schema(method_name: String, params: Array) -> void:
	_rpc_schemas[method_name] = {"params": params}


## Register an action validator.
func register_action_validator(action_type: String, validator: Callable) -> void:
	_action_validators[action_type] = validator


## Validate outgoing RPC.
func validate_outgoing(method: String, args: Array) -> bool:
	# Check method name format (snake_case with rpc_ prefix)
	if not method.begins_with("rpc_"):
		push_warning("RPCValidator: RPC method must start with 'rpc_': " + method)
		return false

	# Validate against schema if registered
	if _rpc_schemas.has(method):
		return _validate_against_schema(method, args)

	# Basic validation for unregistered RPCs
	return _validate_basic(args)


## Validate incoming RPC.
func validate_incoming(peer_id: int, method: String, args: Array) -> bool:
	# Check if peer is blocked
	if _is_peer_blocked(peer_id):
		rpc_blocked.emit(peer_id, "Peer is temporarily blocked")
		return false

	# Check method name format
	if not method.begins_with("rpc_"):
		_log_suspicious_activity(peer_id, "Invalid RPC method name: " + method)
		return false

	# Validate against schema
	if _rpc_schemas.has(method):
		if not _validate_against_schema(method, args):
			_log_suspicious_activity(peer_id, "Schema validation failed for: " + method)
			return false

	# Basic validation
	if not _validate_basic(args):
		_log_suspicious_activity(peer_id, "Basic validation failed")
		return false

	return true


## Check rate limit for a peer.
func check_rate_limit(peer_id: int) -> bool:
	var current_time := Time.get_ticks_msec() / 1000.0

	# Initialize tracking for new peer
	if not _rpc_counts.has(peer_id):
		_rpc_counts[peer_id] = {
			"count": 0,
			"window_start": current_time,
			"burst": 0
		}

	var tracking: Dictionary = _rpc_counts[peer_id]

	# Reset window if expired
	if current_time - tracking["window_start"] >= RATE_WINDOW:
		tracking["count"] = 0
		tracking["window_start"] = current_time
		tracking["burst"] = 0

	# Check burst limit (rapid consecutive calls)
	var last_time: float = _last_rpc_time.get(peer_id, 0.0)
	if current_time - last_time < 0.016:  ## ~60fps
		tracking["burst"] += 1
		if tracking["burst"] > RPC_BURST_LIMIT:
			rate_limit_exceeded.emit(peer_id)
			return false
	else:
		tracking["burst"] = 0

	# Check rate limit
	tracking["count"] += 1
	_last_rpc_time[peer_id] = current_time

	if tracking["count"] > RPC_RATE_LIMIT:
		rate_limit_exceeded.emit(peer_id)
		return false

	return true


## Validate action on server (anti-cheat).
func validate_action(peer_id: int, action_type: String, action_data: Dictionary) -> bool:
	# Use registered validator if available
	if _action_validators.has(action_type):
		var result: bool = _action_validators[action_type].call(peer_id, action_data)
		if not result:
			cheat_detected.emit(peer_id, action_type, "Validator rejected action")
		return result

	# Default validations
	match action_type:
		"move_unit":
			return _validate_move_action(peer_id, action_data)
		"attack":
			return _validate_attack_action(peer_id, action_data)
		"use_ability":
			return _validate_ability_action(peer_id, action_data)
		"build_unit":
			return _validate_build_action(peer_id, action_data)
		_:
			return true  ## Unknown action types pass by default


## Validate move action.
func _validate_move_action(peer_id: int, data: Dictionary) -> bool:
	# Check required fields
	if not data.has("unit_id") or not data.has("target_position"):
		return false

	# Validate position is within map bounds (example: 1000x1000 map)
	var target: Vector3 = data.get("target_position", Vector3.ZERO)
	if target.x < -1000 or target.x > 1000 or target.z < -1000 or target.z > 1000:
		cheat_detected.emit(peer_id, "move_unit", "Position out of bounds: " + str(target))
		return false

	return true


## Validate attack action.
func _validate_attack_action(peer_id: int, data: Dictionary) -> bool:
	if not data.has("attacker_id") or not data.has("target_id"):
		return false

	# Validate IDs are positive
	if data["attacker_id"] <= 0 or data["target_id"] <= 0:
		return false

	return true


## Validate ability action.
func _validate_ability_action(peer_id: int, data: Dictionary) -> bool:
	if not data.has("unit_id") or not data.has("ability_id"):
		return false

	# Validate ability ID format
	var ability_id: String = data.get("ability_id", "")
	if ability_id.is_empty() or ability_id.length() > 64:
		return false

	return true


## Validate build action.
func _validate_build_action(peer_id: int, data: Dictionary) -> bool:
	if not data.has("factory_id") or not data.has("unit_type"):
		return false

	# Validate unit type
	var unit_type: String = data.get("unit_type", "")
	if unit_type.is_empty() or unit_type.length() > 64:
		return false

	return true


## Validate arguments against schema.
func _validate_against_schema(method: String, args: Array) -> bool:
	var schema: Dictionary = _rpc_schemas[method]
	var params: Array = schema["params"]

	var required_count := 0
	for param in params:
		if not param.get("optional", false):
			required_count += 1

	if args.size() < required_count or args.size() > params.size():
		return false

	for i in args.size():
		var param: Dictionary = params[i]
		var expected_type: int = param["type"]
		var actual_type := typeof(args[i])

		if actual_type != expected_type:
			# Allow null for optional params
			if param.get("optional", false) and args[i] == null:
				continue
			return false

	return true


## Basic validation for unregistered RPCs.
func _validate_basic(args: Array) -> bool:
	for arg in args:
		if not _validate_value(arg):
			return false
	return true


## Validate a single value.
func _validate_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_STRING:
			return value.length() <= MAX_STRING_LENGTH
		TYPE_ARRAY:
			if value.size() > MAX_ARRAY_SIZE:
				return false
			for item in value:
				if not _validate_value(item):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > MAX_DICT_SIZE:
				return false
			for key in value:
				if not _validate_value(key) or not _validate_value(value[key]):
					return false
			return true
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR:
			return true
		TYPE_NIL:
			return true
		_:
			return false  ## Unknown types rejected


## Log suspicious activity.
func _log_suspicious_activity(peer_id: int, details: String) -> void:
	push_warning("RPCValidator: Suspicious activity from peer %d: %s" % [peer_id, details])


## Block a peer temporarily.
func block_peer(peer_id: int, duration: float = 60.0) -> void:
	var unblock_time := Time.get_ticks_msec() / 1000.0 + duration
	_blocked_peers[peer_id] = unblock_time
	rpc_blocked.emit(peer_id, "Peer blocked for %d seconds" % int(duration))


## Check if peer is blocked.
func _is_peer_blocked(peer_id: int) -> bool:
	if not _blocked_peers.has(peer_id):
		return false

	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time >= _blocked_peers[peer_id]:
		_blocked_peers.erase(peer_id)
		return false

	return true


## Unblock a peer.
func unblock_peer(peer_id: int) -> void:
	_blocked_peers.erase(peer_id)


## Reset rate limit tracking for a peer.
func reset_rate_limit(peer_id: int) -> void:
	_rpc_counts.erase(peer_id)
	_last_rpc_time.erase(peer_id)


## Get rate limit stats for a peer.
func get_rate_stats(peer_id: int) -> Dictionary:
	if not _rpc_counts.has(peer_id):
		return {"count": 0, "burst": 0}

	var tracking: Dictionary = _rpc_counts[peer_id]
	return {
		"count": tracking["count"],
		"burst": tracking["burst"],
		"window_remaining": RATE_WINDOW - (Time.get_ticks_msec() / 1000.0 - tracking["window_start"])
	}


## Clear all tracking data.
func clear() -> void:
	_rpc_counts.clear()
	_last_rpc_time.clear()
	_blocked_peers.clear()
