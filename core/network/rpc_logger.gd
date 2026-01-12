class_name RPCLogger
extends RefCounted
## RPCLogger captures all RPC calls for debugging and analysis.
## Provides detailed logs with timestamps, peer info, and performance metrics.

signal log_entry_added(entry: Dictionary)
signal log_cleared()

## Configuration
const MAX_LOG_ENTRIES := 10000
const LOG_FILE_PATH := "user://rpc_log.txt"

## Log levels
enum LogLevel {
	DEBUG,
	INFO,
	WARNING,
	ERROR
}

## Log entries
var _log_entries: Array[Dictionary] = []
var _enabled := true
var _log_to_file := false
var _min_log_level := LogLevel.DEBUG
var _file: FileAccess = null

## Statistics
var _rpc_counts: Dictionary = {}     ## method_name -> count
var _rpc_timing: Dictionary = {}     ## method_name -> {total_time, count, min, max}
var _peer_stats: Dictionary = {}     ## peer_id -> {sent, received, errors}

## Filtering
var _method_filter: Array[String] = []  ## Empty = log all
var _peer_filter: Array[int] = []       ## Empty = log all peers


func _init() -> void:
	pass


## Enable/disable logging.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled


## Set minimum log level.
func set_log_level(level: LogLevel) -> void:
	_min_log_level = level


## Enable file logging.
func enable_file_logging(path: String = LOG_FILE_PATH) -> bool:
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file != null:
		_log_to_file = true
		_write_file_header()
		return true
	push_error("RPCLogger: Failed to open log file: " + path)
	return false


## Disable file logging.
func disable_file_logging() -> void:
	if _file != null:
		_file.close()
		_file = null
	_log_to_file = false


## Log an outgoing RPC call.
func log_outgoing(method: String, args: Array, target_peer: int) -> void:
	if not _should_log(method, target_peer):
		return

	var entry := _create_entry(method, args, target_peer, 0, "outgoing", LogLevel.DEBUG)
	_add_entry(entry)
	_update_stats(method, target_peer, "sent")


## Log an incoming RPC call.
func log_incoming(method: String, args: Array, source_peer: int) -> void:
	if not _should_log(method, source_peer):
		return

	var entry := _create_entry(method, args, 0, source_peer, "incoming", LogLevel.DEBUG)
	_add_entry(entry)
	_update_stats(method, source_peer, "received")


## Log an RPC error.
func log_error(method: String, error_message: String, peer_id: int) -> void:
	var entry := _create_entry(method, [], peer_id, peer_id, "error", LogLevel.ERROR)
	entry["error"] = error_message
	_add_entry(entry)
	_update_peer_stat(peer_id, "errors")


## Log an RPC with timing information.
func log_with_timing(method: String, args: Array, peer_id: int, duration_ms: float, direction: String) -> void:
	if not _should_log(method, peer_id):
		return

	var entry := _create_entry(method, args, peer_id if direction == "outgoing" else 0,
							   peer_id if direction == "incoming" else 0, direction, LogLevel.DEBUG)
	entry["duration_ms"] = duration_ms
	_add_entry(entry)
	_update_timing(method, duration_ms)


## Log a custom message.
func log_message(message: String, level: LogLevel = LogLevel.INFO) -> void:
	if level < _min_log_level:
		return

	var entry := {
		"timestamp": Time.get_ticks_msec(),
		"datetime": Time.get_datetime_string_from_system(),
		"type": "message",
		"level": level,
		"message": message
	}
	_add_entry(entry)


## Create a log entry.
func _create_entry(method: String, args: Array, target_peer: int, source_peer: int,
				   direction: String, level: LogLevel) -> Dictionary:
	return {
		"timestamp": Time.get_ticks_msec(),
		"datetime": Time.get_datetime_string_from_system(),
		"type": "rpc",
		"level": level,
		"method": method,
		"args_count": args.size(),
		"args_types": _get_arg_types(args),
		"target_peer": target_peer,
		"source_peer": source_peer,
		"direction": direction
	}


## Get argument types for logging.
func _get_arg_types(args: Array) -> Array[String]:
	var types: Array[String] = []
	for arg in args:
		types.append(_type_name(typeof(arg)))
	return types


## Get type name.
func _type_name(type_id: int) -> String:
	match type_id:
		TYPE_NIL: return "null"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "string"
		TYPE_VECTOR2: return "vector2"
		TYPE_VECTOR3: return "vector3"
		TYPE_DICTIONARY: return "dict"
		TYPE_ARRAY: return "array"
		_: return "other"


## Add entry to log.
func _add_entry(entry: Dictionary) -> void:
	_log_entries.append(entry)

	# Limit log size
	while _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_front()

	# Write to file
	if _log_to_file and _file != null:
		_write_entry_to_file(entry)

	log_entry_added.emit(entry)


## Check if should log this RPC.
func _should_log(method: String, peer_id: int) -> bool:
	if not _enabled:
		return false

	# Check method filter
	if not _method_filter.is_empty() and method not in _method_filter:
		return false

	# Check peer filter
	if not _peer_filter.is_empty() and peer_id not in _peer_filter:
		return false

	return true


## Update RPC statistics.
func _update_stats(method: String, peer_id: int, stat_type: String) -> void:
	# Method counts
	if not _rpc_counts.has(method):
		_rpc_counts[method] = 0
	_rpc_counts[method] += 1

	# Peer stats
	_update_peer_stat(peer_id, stat_type)


## Update peer statistics.
func _update_peer_stat(peer_id: int, stat_type: String) -> void:
	if not _peer_stats.has(peer_id):
		_peer_stats[peer_id] = {"sent": 0, "received": 0, "errors": 0}
	_peer_stats[peer_id][stat_type] += 1


## Update timing statistics.
func _update_timing(method: String, duration_ms: float) -> void:
	if not _rpc_timing.has(method):
		_rpc_timing[method] = {"total": 0.0, "count": 0, "min": duration_ms, "max": duration_ms}

	var timing: Dictionary = _rpc_timing[method]
	timing["total"] += duration_ms
	timing["count"] += 1
	timing["min"] = minf(timing["min"], duration_ms)
	timing["max"] = maxf(timing["max"], duration_ms)


## Write file header.
func _write_file_header() -> void:
	if _file == null:
		return
	_file.store_line("=== RPC Log Started: %s ===" % Time.get_datetime_string_from_system())
	_file.store_line("")


## Write entry to file.
func _write_entry_to_file(entry: Dictionary) -> void:
	if _file == null:
		return

	var line := "[%s] " % entry.get("datetime", "")

	if entry.get("type") == "rpc":
		line += "[%s] %s " % [entry.get("direction", ""), entry.get("method", "")]
		line += "(args: %d) " % entry.get("args_count", 0)
		if entry.has("target_peer") and entry["target_peer"] > 0:
			line += "-> peer %d " % entry["target_peer"]
		if entry.has("source_peer") and entry["source_peer"] > 0:
			line += "<- peer %d " % entry["source_peer"]
		if entry.has("duration_ms"):
			line += "[%.2fms]" % entry["duration_ms"]
		if entry.has("error"):
			line += "ERROR: %s" % entry["error"]
	else:
		line += "[%s] %s" % [_level_name(entry.get("level", 0)), entry.get("message", "")]

	_file.store_line(line)


## Get level name.
func _level_name(level: int) -> String:
	match level:
		LogLevel.DEBUG: return "DEBUG"
		LogLevel.INFO: return "INFO"
		LogLevel.WARNING: return "WARN"
		LogLevel.ERROR: return "ERROR"
		_: return "UNKNOWN"


## Set method filter.
func set_method_filter(methods: Array[String]) -> void:
	_method_filter = methods


## Set peer filter.
func set_peer_filter(peers: Array[int]) -> void:
	_peer_filter = peers


## Clear filters.
func clear_filters() -> void:
	_method_filter.clear()
	_peer_filter.clear()


## Get log entries.
func get_entries(count: int = 100, offset: int = 0) -> Array[Dictionary]:
	var start := maxi(0, _log_entries.size() - count - offset)
	var end := mini(_log_entries.size() - offset, start + count)

	var result: Array[Dictionary] = []
	for i in range(start, end):
		result.append(_log_entries[i])
	return result


## Get entries by method.
func get_entries_by_method(method: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _log_entries:
		if entry.get("method") == method:
			result.append(entry)
	return result


## Get entries by peer.
func get_entries_by_peer(peer_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _log_entries:
		if entry.get("target_peer") == peer_id or entry.get("source_peer") == peer_id:
			result.append(entry)
	return result


## Get error entries.
func get_errors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _log_entries:
		if entry.get("level") == LogLevel.ERROR:
			result.append(entry)
	return result


## Get RPC counts.
func get_rpc_counts() -> Dictionary:
	return _rpc_counts.duplicate()


## Get RPC timing statistics.
func get_timing_stats() -> Dictionary:
	var result := {}
	for method in _rpc_timing:
		var timing: Dictionary = _rpc_timing[method]
		var avg := timing["total"] / timing["count"] if timing["count"] > 0 else 0.0
		result[method] = {
			"count": timing["count"],
			"avg_ms": avg,
			"min_ms": timing["min"],
			"max_ms": timing["max"]
		}
	return result


## Get peer statistics.
func get_peer_stats() -> Dictionary:
	return _peer_stats.duplicate(true)


## Get summary statistics.
func get_summary() -> Dictionary:
	var total_sent := 0
	var total_received := 0
	var total_errors := 0

	for peer_id in _peer_stats:
		var stats: Dictionary = _peer_stats[peer_id]
		total_sent += stats["sent"]
		total_received += stats["received"]
		total_errors += stats["errors"]

	return {
		"total_entries": _log_entries.size(),
		"unique_methods": _rpc_counts.size(),
		"total_sent": total_sent,
		"total_received": total_received,
		"total_errors": total_errors,
		"peers_tracked": _peer_stats.size()
	}


## Clear log.
func clear() -> void:
	_log_entries.clear()
	_rpc_counts.clear()
	_rpc_timing.clear()
	_peer_stats.clear()
	log_cleared.emit()


## Export log to file.
func export_to_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_line(JSON.stringify({
		"export_time": Time.get_datetime_string_from_system(),
		"summary": get_summary(),
		"rpc_counts": _rpc_counts,
		"timing_stats": get_timing_stats(),
		"peer_stats": _peer_stats,
		"entries": _log_entries
	}, "\t"))

	file.close()
	return true
