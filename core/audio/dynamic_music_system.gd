class_name DynamicMusicSystem
extends RefCounted
## DynamicMusicSystem provides adaptive music that responds to battle intensity.

signal intensity_changed(level: float)
signal layer_activated(layer_name: String)
signal layer_deactivated(layer_name: String)
signal transition_started(from_state: String, to_state: String)
signal transition_completed()

## Intensity thresholds
const INTENSITY_CALM := 0.0
const INTENSITY_LIGHT := 0.25
const INTENSITY_MEDIUM := 0.5
const INTENSITY_HEAVY := 0.75
const INTENSITY_EXTREME := 1.0

## Transition timing
const LAYER_FADE_TIME := 2.0          ## Time to fade layers in/out
const INTENSITY_SMOOTHING := 0.1      ## Smoothing factor for intensity changes
const STATE_CHANGE_DELAY := 1.0       ## Delay before state transitions

## Audio bus
const MUSIC_BUS := "Music"

## Music state
enum MusicState {
	CALM,       ## No combat, exploration
	TENSION,    ## Combat imminent
	COMBAT,     ## Active combat
	INTENSE,    ## Large-scale battle
	VICTORY,    ## Battle won
	DEFEAT      ## Battle lost
}

## Current state
var _current_state := MusicState.CALM
var _target_intensity := 0.0
var _current_intensity := 0.0
var _state_timer := 0.0

## Layers
var _layers: Dictionary = {}  ## layer_name -> MusicLayer
var _active_layers: Array[String] = []

## Audio players
var _audio_root: Node = null

## Battle metrics for intensity calculation
var _unit_count := 0
var _enemy_count := 0
var _combat_events := 0
var _recent_deaths := 0

## Metric decay
const COMBAT_EVENT_DECAY := 0.5  ## Per second
const DEATH_DECAY := 0.2


func _init() -> void:
	pass


## Initialize the music system.
func initialize(audio_root: Node) -> void:
	_audio_root = audio_root


## Register a music layer.
func register_layer(layer_name: String, stream: AudioStream, base_volume: float = 0.0,
					intensity_min: float = 0.0, intensity_max: float = 1.0) -> void:
	var layer := MusicLayer.new()
	layer.stream = stream
	layer.base_volume = base_volume
	layer.intensity_min = intensity_min
	layer.intensity_max = intensity_max
	layer.current_volume = -80.0  ## Start silent
	layer.target_volume = -80.0

	# Create audio player
	if _audio_root != null:
		var player := AudioStreamPlayer.new()
		player.name = "MusicLayer_" + layer_name
		player.stream = stream
		player.bus = MUSIC_BUS
		player.volume_db = -80.0
		player.autoplay = true
		_audio_root.add_child(player)
		layer.player = player

	_layers[layer_name] = layer


## Update the music system (call each frame).
func update(delta: float) -> void:
	# Decay combat metrics
	_combat_events = maxf(_combat_events - COMBAT_EVENT_DECAY * delta, 0.0)
	_recent_deaths = maxf(_recent_deaths - DEATH_DECAY * delta, 0.0)

	# Calculate target intensity
	_calculate_intensity()

	# Smooth intensity transition
	_current_intensity = lerpf(_current_intensity, _target_intensity, INTENSITY_SMOOTHING)

	# Update state based on intensity
	_update_state(delta)

	# Update layer volumes
	_update_layers(delta)


## Calculate battle intensity.
func _calculate_intensity() -> void:
	var intensity := 0.0

	# Factor in unit counts
	var total_units := _unit_count + _enemy_count
	if total_units > 100:
		intensity += 0.4
	elif total_units > 50:
		intensity += 0.25
	elif total_units > 20:
		intensity += 0.1

	# Factor in combat events
	intensity += minf(_combat_events * 0.1, 0.3)

	# Factor in recent deaths
	intensity += minf(_recent_deaths * 0.05, 0.2)

	# Factor in enemy presence
	if _enemy_count > 0:
		intensity += 0.1

	_target_intensity = clampf(intensity, 0.0, 1.0)


## Update music state based on intensity.
func _update_state(delta: float) -> void:
	_state_timer += delta

	var new_state := _current_state

	if _target_intensity >= INTENSITY_EXTREME:
		new_state = MusicState.INTENSE
	elif _target_intensity >= INTENSITY_MEDIUM:
		new_state = MusicState.COMBAT
	elif _target_intensity >= INTENSITY_LIGHT:
		new_state = MusicState.TENSION
	else:
		new_state = MusicState.CALM

	if new_state != _current_state and _state_timer >= STATE_CHANGE_DELAY:
		var old_state := _current_state
		_current_state = new_state
		_state_timer = 0.0
		transition_started.emit(_state_to_string(old_state), _state_to_string(new_state))


## Update layer volumes.
func _update_layers(delta: float) -> void:
	for layer_name in _layers:
		var layer: MusicLayer = _layers[layer_name]

		# Determine if layer should be active
		var should_play := _current_intensity >= layer.intensity_min and _current_intensity <= layer.intensity_max

		if should_play:
			# Calculate volume based on intensity within range
			var range_size := layer.intensity_max - layer.intensity_min
			var t := 0.0
			if range_size > 0:
				t = (_current_intensity - layer.intensity_min) / range_size
			layer.target_volume = layer.base_volume

			if layer_name not in _active_layers:
				_active_layers.append(layer_name)
				layer_activated.emit(layer_name)
		else:
			layer.target_volume = -80.0

			if layer_name in _active_layers:
				_active_layers.erase(layer_name)
				layer_deactivated.emit(layer_name)

		# Smooth volume transition
		var volume_delta := (layer.target_volume - layer.current_volume) * delta / LAYER_FADE_TIME
		layer.current_volume += volume_delta
		layer.current_volume = clampf(layer.current_volume, -80.0, layer.base_volume)

		# Apply to player
		if layer.player != null:
			layer.player.volume_db = layer.current_volume


## Report combat event.
func report_combat_event() -> void:
	_combat_events += 1.0


## Report unit death.
func report_death() -> void:
	_recent_deaths += 1.0


## Update unit counts.
func update_unit_counts(friendly: int, enemy: int) -> void:
	_unit_count = friendly
	_enemy_count = enemy


## Set state directly (for victory/defeat).
func set_state(state: MusicState) -> void:
	if state != _current_state:
		var old_state := _current_state
		_current_state = state
		transition_started.emit(_state_to_string(old_state), _state_to_string(state))


## Play victory music.
func play_victory() -> void:
	set_state(MusicState.VICTORY)


## Play defeat music.
func play_defeat() -> void:
	set_state(MusicState.DEFEAT)


## Fade out all music.
func fade_out_all(duration: float = 2.0) -> void:
	for layer_name in _layers:
		var layer: MusicLayer = _layers[layer_name]
		layer.target_volume = -80.0

		if layer.player != null:
			var tween := layer.player.create_tween()
			tween.tween_property(layer.player, "volume_db", -80.0, duration)


## Get current intensity.
func get_intensity() -> float:
	return _current_intensity


## Get current state.
func get_state() -> MusicState:
	return _current_state


## Get state name.
func _state_to_string(state: MusicState) -> String:
	match state:
		MusicState.CALM: return "calm"
		MusicState.TENSION: return "tension"
		MusicState.COMBAT: return "combat"
		MusicState.INTENSE: return "intense"
		MusicState.VICTORY: return "victory"
		MusicState.DEFEAT: return "defeat"
		_: return "unknown"


## Cleanup.
func cleanup() -> void:
	for layer_name in _layers:
		var layer: MusicLayer = _layers[layer_name]
		if layer.player != null and is_instance_valid(layer.player):
			layer.player.queue_free()
	_layers.clear()
	_active_layers.clear()


## MusicLayer data class.
class MusicLayer:
	var stream: AudioStream
	var player: AudioStreamPlayer
	var base_volume: float = 0.0
	var current_volume: float = -80.0
	var target_volume: float = -80.0
	var intensity_min: float = 0.0
	var intensity_max: float = 1.0
