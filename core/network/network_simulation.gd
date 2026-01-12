class_name NetworkSimulation
extends RefCounted
## NetworkSimulation provides latency and packet loss simulation for development testing.
## Supports 100-300ms latency and 1-5% packet loss as specified.

signal packet_delayed(method: String, delay_ms: float)
signal packet_dropped(method: String)
signal latency_changed(min_ms: float, max_ms: float)

## Configuration
const DEFAULT_MIN_LATENCY := 100.0  ## ms
const DEFAULT_MAX_LATENCY := 300.0  ## ms
const DEFAULT_PACKET_LOSS := 0.02   ## 2%
const DEFAULT_JITTER := 0.3         ## 30% of latency as jitter

## Simulation parameters
var _enabled := false
var _min_latency_ms := DEFAULT_MIN_LATENCY
var _max_latency_ms := DEFAULT_MAX_LATENCY
var _packet_loss_rate := DEFAULT_PACKET_LOSS
var _jitter_factor := DEFAULT_JITTER

## Packet queues
var _outgoing_queue: Array[QueuedPacket] = []
var _incoming_queue: Array[QueuedPacket] = []

## Statistics
var _packets_sent := 0
var _packets_dropped := 0
var _total_latency := 0.0
var _latency_samples := 0

## Random generator for simulation
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Enable simulation.
func enable() -> void:
	_enabled = true


## Disable simulation.
func disable() -> void:
	_enabled = false
	_flush_queues()


## Check if simulation is enabled.
func is_enabled() -> bool:
	return _enabled


## Set latency range (in milliseconds).
func set_latency(min_ms: float, max_ms: float) -> void:
	_min_latency_ms = maxf(0, min_ms)
	_max_latency_ms = maxf(_min_latency_ms, max_ms)
	latency_changed.emit(_min_latency_ms, _max_latency_ms)


## Set packet loss rate (0.0 to 1.0).
func set_packet_loss(rate: float) -> void:
	_packet_loss_rate = clampf(rate, 0.0, 1.0)


## Set jitter factor (0.0 to 1.0).
func set_jitter(factor: float) -> void:
	_jitter_factor = clampf(factor, 0.0, 1.0)


## Apply common network presets.
func apply_preset(preset: String) -> void:
	match preset:
		"local":
			set_latency(0, 5)
			set_packet_loss(0.0)
		"good":
			set_latency(20, 50)
			set_packet_loss(0.01)
		"average":
			set_latency(50, 100)
			set_packet_loss(0.02)
		"poor":
			set_latency(100, 200)
			set_packet_loss(0.03)
		"bad":
			set_latency(200, 400)
			set_packet_loss(0.05)
		"test":
			set_latency(DEFAULT_MIN_LATENCY, DEFAULT_MAX_LATENCY)
			set_packet_loss(DEFAULT_PACKET_LOSS)


## Queue outgoing RPC with simulated delay.
func queue_outgoing_rpc(method: String, args: Array, target_peer: int) -> bool:
	if not _enabled:
		return false

	# Check for packet loss
	if _should_drop_packet():
		_packets_dropped += 1
		packet_dropped.emit(method)
		return true  ## Packet "sent" but dropped

	# Calculate delay
	var delay := _calculate_delay()
	var delivery_time := Time.get_ticks_msec() + int(delay)

	var packet := QueuedPacket.new()
	packet.method = method
	packet.args = args
	packet.target_peer = target_peer
	packet.delivery_time = delivery_time
	packet.queued_time = Time.get_ticks_msec()

	_outgoing_queue.append(packet)
	_packets_sent += 1
	_total_latency += delay
	_latency_samples += 1

	packet_delayed.emit(method, delay)
	return true


## Queue incoming packet with simulated delay.
func queue_incoming_packet(data: PackedByteArray, source_peer: int) -> void:
	if not _enabled:
		return

	# Check for packet loss
	if _should_drop_packet():
		_packets_dropped += 1
		return

	var delay := _calculate_delay()
	var delivery_time := Time.get_ticks_msec() + int(delay)

	var packet := QueuedPacket.new()
	packet.raw_data = data
	packet.source_peer = source_peer
	packet.delivery_time = delivery_time
	packet.queued_time = Time.get_ticks_msec()

	_incoming_queue.append(packet)


## Update simulation (call each frame).
func update(delta: float) -> void:
	if not _enabled:
		return

	var current_time := Time.get_ticks_msec()

	# Process outgoing queue
	_process_outgoing_queue(current_time)

	# Process incoming queue
	_process_incoming_queue(current_time)


## Process outgoing packet queue.
func _process_outgoing_queue(current_time: int) -> Array[QueuedPacket]:
	var ready_packets: Array[QueuedPacket] = []

	var i := 0
	while i < _outgoing_queue.size():
		var packet := _outgoing_queue[i]
		if packet.delivery_time <= current_time:
			ready_packets.append(packet)
			_outgoing_queue.remove_at(i)
		else:
			i += 1

	return ready_packets


## Process incoming packet queue.
func _process_incoming_queue(current_time: int) -> Array[QueuedPacket]:
	var ready_packets: Array[QueuedPacket] = []

	var i := 0
	while i < _incoming_queue.size():
		var packet := _incoming_queue[i]
		if packet.delivery_time <= current_time:
			ready_packets.append(packet)
			_incoming_queue.remove_at(i)
		else:
			i += 1

	return ready_packets


## Get ready outgoing packets.
func get_ready_outgoing() -> Array[QueuedPacket]:
	return _process_outgoing_queue(Time.get_ticks_msec())


## Get ready incoming packets.
func get_ready_incoming() -> Array[QueuedPacket]:
	return _process_incoming_queue(Time.get_ticks_msec())


## Check if packet should be dropped.
func _should_drop_packet() -> bool:
	return _rng.randf() < _packet_loss_rate


## Calculate delay for a packet.
func _calculate_delay() -> float:
	# Base latency with uniform distribution
	var base_latency := _rng.randf_range(_min_latency_ms, _max_latency_ms)

	# Add jitter
	var jitter_range := base_latency * _jitter_factor
	var jitter := _rng.randf_range(-jitter_range, jitter_range)

	return maxf(0, base_latency + jitter)


## Flush all queues (immediate delivery).
func _flush_queues() -> void:
	_outgoing_queue.clear()
	_incoming_queue.clear()


## Get statistics.
func get_stats() -> Dictionary:
	var avg_latency := 0.0
	if _latency_samples > 0:
		avg_latency = _total_latency / _latency_samples

	var drop_rate := 0.0
	if _packets_sent > 0:
		drop_rate = float(_packets_dropped) / float(_packets_sent + _packets_dropped)

	return {
		"enabled": _enabled,
		"min_latency_ms": _min_latency_ms,
		"max_latency_ms": _max_latency_ms,
		"packet_loss_rate": _packet_loss_rate,
		"jitter_factor": _jitter_factor,
		"packets_sent": _packets_sent,
		"packets_dropped": _packets_dropped,
		"actual_drop_rate": drop_rate,
		"avg_latency_ms": avg_latency,
		"outgoing_queue_size": _outgoing_queue.size(),
		"incoming_queue_size": _incoming_queue.size()
	}


## Reset statistics.
func reset_stats() -> void:
	_packets_sent = 0
	_packets_dropped = 0
	_total_latency = 0.0
	_latency_samples = 0


## Get current configuration.
func get_config() -> Dictionary:
	return {
		"min_latency_ms": _min_latency_ms,
		"max_latency_ms": _max_latency_ms,
		"packet_loss_rate": _packet_loss_rate,
		"jitter_factor": _jitter_factor
	}


## Set configuration from dictionary.
func set_config(config: Dictionary) -> void:
	if config.has("min_latency_ms") and config.has("max_latency_ms"):
		set_latency(config["min_latency_ms"], config["max_latency_ms"])
	if config.has("packet_loss_rate"):
		set_packet_loss(config["packet_loss_rate"])
	if config.has("jitter_factor"):
		set_jitter(config["jitter_factor"])


## QueuedPacket helper class.
class QueuedPacket:
	var method: String = ""
	var args: Array = []
	var target_peer: int = 0
	var source_peer: int = 0
	var raw_data: PackedByteArray = PackedByteArray()
	var delivery_time: int = 0
	var queued_time: int = 0

	func get_actual_delay() -> int:
		return delivery_time - queued_time
