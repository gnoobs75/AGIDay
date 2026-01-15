class_name DynamicMusicManager
extends RefCounted
## DynamicMusicManager wraps Dynamusic for battle-intensity-based music adaptation.
## Provides smooth transitions and integration with game events.

signal music_layer_changed(layer_name: String, active: bool)
signal intensity_changed(intensity: float)
signal music_state_changed(state: String)
signal transition_started(from_state: String, to_state: String)
signal transition_completed(to_state: String)

## Music states
enum MusicState {
	SILENCE,
	AMBIENT,        ## Calm exploration
	LOW_TENSION,    ## Minor threats nearby
	MEDIUM_TENSION, ## Active combat, moderate units
	HIGH_TENSION,   ## Intense battle, many units
	BOSS,           ## Boss encounter or critical moment
	VICTORY,        ## Victory fanfare
	DEFEAT          ## Defeat stinger
}

## Configuration
const INTENSITY_SMOOTH_SPEED := 2.0       ## Smoothing factor for intensity changes
const TRANSITION_DURATION := 2.0           ## Default transition time in seconds
const INTENSITY_UPDATE_INTERVAL := 0.1    ## Update intensity every 100ms
const LAYER_FADE_TIME := 1.0              ## Fade time for layer changes

## State
var _current_state := MusicState.SILENCE
var _target_state := MusicState.SILENCE
var _current_intensity := 0.0
var _target_intensity := 0.0
var _is_transitioning := false
var _transition_timer := 0.0

## Audio players
var _music_bus := "Music"
var _base_volume := 1.0
var _is_muted := false

## Layer tracking
var _active_layers: Dictionary = {}  ## layer_name -> is_active
var _layer_volumes: Dictionary = {}  ## layer_name -> current_volume

## Battle intensity inputs
var _unit_count := 0
var _enemy_count := 0
var _combat_events := 0
var _combat_event_decay := 5.0  ## Events decay over 5 seconds

## Dynamusic integration (if available)
var _dynamusic_node: Node = null
var _has_dynamusic := false

## Audio streams
var _ambient_stream: AudioStream = null
var _combat_streams: Array[AudioStream] = []
var _boss_stream: AudioStream = null
var _victory_stream: AudioStream = null
var _defeat_stream: AudioStream = null

## Frame budget
const FRAME_BUDGET_MS := 0.5  ## 0.5ms budget for audio processing


func _init() -> void:
	_initialize_layers()


## Initialize music layers.
func _initialize_layers() -> void:
	_active_layers = {
		"base": true,
		"percussion": false,
		"melody": false,
		"strings": false,
		"brass": false,
		"choir": false
	}

	for layer in _active_layers:
		_layer_volumes[layer] = 0.0 if not _active_layers[layer] else 1.0


## Initialize with Dynamusic node if available.
func initialize(dynamusic_node: Node = null) -> void:
	_dynamusic_node = dynamusic_node
	_has_dynamusic = _dynamusic_node != null

	if _has_dynamusic:
		_setup_dynamusic()


## Setup Dynamusic integration.
func _setup_dynamusic() -> void:
	# Dynamusic setup would go here
	# Connect to Dynamusic signals, configure layers, etc.
	pass


## Update (call each frame).
func update(delta: float) -> void:
	var start_time := Time.get_ticks_usec()

	# Update intensity smoothing
	_update_intensity(delta)

	# Update state transitions
	if _is_transitioning:
		_update_transition(delta)

	# Update layer volumes
	_update_layer_volumes(delta)

	# Decay combat events
	_combat_events = maxf(0, _combat_events - delta * _combat_event_decay)

	# Check frame budget
	var elapsed_ms := (Time.get_ticks_usec() - start_time) / 1000.0
	if elapsed_ms > FRAME_BUDGET_MS:
		push_warning("DynamicMusicManager: Frame budget exceeded (%.2fms)" % elapsed_ms)


## Update intensity smoothing.
func _update_intensity(delta: float) -> void:
	if absf(_current_intensity - _target_intensity) > 0.01:
		_current_intensity = lerpf(_current_intensity, _target_intensity, delta * INTENSITY_SMOOTH_SPEED)
		intensity_changed.emit(_current_intensity)

		# Auto-adjust state based on intensity
		_auto_adjust_state()


## Auto-adjust music state based on intensity.
func _auto_adjust_state() -> void:
	var new_state := _target_state

	if _current_state == MusicState.BOSS or _current_state == MusicState.VICTORY or _current_state == MusicState.DEFEAT:
		return  ## Don't auto-transition from these states

	if _current_intensity < 0.1:
		new_state = MusicState.AMBIENT
	elif _current_intensity < 0.3:
		new_state = MusicState.LOW_TENSION
	elif _current_intensity < 0.6:
		new_state = MusicState.MEDIUM_TENSION
	elif _current_intensity < 0.9:
		new_state = MusicState.HIGH_TENSION

	if new_state != _current_state and not _is_transitioning:
		transition_to_state(new_state)


## Update state transition.
func _update_transition(delta: float) -> void:
	_transition_timer += delta

	if _transition_timer >= TRANSITION_DURATION:
		_complete_transition()


## Complete state transition.
func _complete_transition() -> void:
	_current_state = _target_state
	_is_transitioning = false
	_transition_timer = 0.0

	transition_completed.emit(_get_state_name(_current_state))
	music_state_changed.emit(_get_state_name(_current_state))


## Update layer volumes for smooth fades.
func _update_layer_volumes(delta: float) -> void:
	for layer in _active_layers:
		var target_vol := 1.0 if _active_layers[layer] else 0.0
		var current_vol: float = _layer_volumes[layer]

		if absf(current_vol - target_vol) > 0.01:
			_layer_volumes[layer] = lerpf(current_vol, target_vol, delta / LAYER_FADE_TIME)

			if _has_dynamusic:
				_apply_layer_volume(layer, _layer_volumes[layer])


## Apply layer volume to Dynamusic.
func _apply_layer_volume(layer: String, volume: float) -> void:
	if _dynamusic_node == null:
		return

	# Dynamusic-specific API call would go here
	pass


## Transition to a new music state.
func transition_to_state(new_state: MusicState, duration: float = TRANSITION_DURATION) -> void:
	if new_state == _current_state and not _is_transitioning:
		return

	var from_state := _get_state_name(_current_state)
	_target_state = new_state
	_is_transitioning = true
	_transition_timer = 0.0

	transition_started.emit(from_state, _get_state_name(new_state))

	# Update layers for new state
	_update_layers_for_state(new_state)


## Update layers based on music state.
func _update_layers_for_state(state: MusicState) -> void:
	match state:
		MusicState.SILENCE:
			_set_all_layers_inactive()
		MusicState.AMBIENT:
			_set_layers(["base"], true)
			_set_layers(["percussion", "melody", "strings", "brass", "choir"], false)
		MusicState.LOW_TENSION:
			_set_layers(["base", "strings"], true)
			_set_layers(["percussion", "melody", "brass", "choir"], false)
		MusicState.MEDIUM_TENSION:
			_set_layers(["base", "percussion", "strings", "melody"], true)
			_set_layers(["brass", "choir"], false)
		MusicState.HIGH_TENSION:
			_set_layers(["base", "percussion", "strings", "melody", "brass"], true)
			_set_layers(["choir"], false)
		MusicState.BOSS:
			_set_layers(["base", "percussion", "strings", "melody", "brass", "choir"], true)
		MusicState.VICTORY, MusicState.DEFEAT:
			_set_all_layers_inactive()
			_set_layers(["base", "melody"], true)


## Set layers active/inactive.
func _set_layers(layers: Array, active: bool) -> void:
	for layer in layers:
		if _active_layers.has(layer):
			var was_active: bool = _active_layers[layer]
			_active_layers[layer] = active
			if was_active != active:
				music_layer_changed.emit(layer, active)


## Set all layers inactive.
func _set_all_layers_inactive() -> void:
	for layer in _active_layers:
		_active_layers[layer] = false
		music_layer_changed.emit(layer, false)


## Set battle intensity from game state.
func set_battle_intensity(intensity: float) -> void:
	_target_intensity = clampf(intensity, 0.0, 1.0)


## Calculate battle intensity from game metrics.
func calculate_intensity(unit_count: int, enemy_count: int, in_combat: bool) -> float:
	_unit_count = unit_count
	_enemy_count = enemy_count

	var base_intensity := 0.0

	# Unit count contribution
	if unit_count > 0:
		base_intensity += minf(unit_count / 100.0, 0.3)  ## Max 0.3 from units

	# Enemy presence contribution
	if enemy_count > 0:
		base_intensity += minf(enemy_count / 50.0, 0.3)  ## Max 0.3 from enemies

	# Combat event contribution
	if in_combat:
		base_intensity += 0.2
	base_intensity += minf(_combat_events / 10.0, 0.2)  ## Max 0.2 from events

	return clampf(base_intensity, 0.0, 1.0)


## Report a combat event (increases intensity briefly).
func report_combat_event(severity: float = 1.0) -> void:
	_combat_events += severity


## Trigger boss music.
func trigger_boss_music() -> void:
	transition_to_state(MusicState.BOSS, 1.0)


## Trigger victory music.
func trigger_victory() -> void:
	transition_to_state(MusicState.VICTORY, 0.5)


## Trigger defeat music.
func trigger_defeat() -> void:
	transition_to_state(MusicState.DEFEAT, 0.5)


## Stop all music.
func stop_music(fade_time: float = 1.0) -> void:
	transition_to_state(MusicState.SILENCE, fade_time)


## Resume ambient music.
func resume_ambient() -> void:
	transition_to_state(MusicState.AMBIENT, 2.0)


## Set master volume.
func set_volume(volume: float) -> void:
	_base_volume = clampf(volume, 0.0, 1.0)

	if _has_dynamusic:
		# Apply to Dynamusic
		pass

	var bus_idx := AudioServer.get_bus_index(_music_bus)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(_base_volume))


## Mute/unmute music.
func set_muted(muted: bool) -> void:
	_is_muted = muted

	var bus_idx := AudioServer.get_bus_index(_music_bus)
	if bus_idx >= 0:
		AudioServer.set_bus_mute(bus_idx, muted)


## Get current state.
func get_current_state() -> MusicState:
	return _current_state


## Get current intensity.
func get_intensity() -> float:
	return _current_intensity


## Get state name string.
func _get_state_name(state: MusicState) -> String:
	match state:
		MusicState.SILENCE: return "silence"
		MusicState.AMBIENT: return "ambient"
		MusicState.LOW_TENSION: return "low_tension"
		MusicState.MEDIUM_TENSION: return "medium_tension"
		MusicState.HIGH_TENSION: return "high_tension"
		MusicState.BOSS: return "boss"
		MusicState.VICTORY: return "victory"
		MusicState.DEFEAT: return "defeat"
	return "unknown"


## Get layer status.
func get_layer_status() -> Dictionary:
	return _active_layers.duplicate()


## Serialize state for save.
func to_dict() -> Dictionary:
	return {
		"current_state": _current_state,
		"current_intensity": _current_intensity,
		"active_layers": _active_layers.duplicate(),
		"base_volume": _base_volume,
		"is_muted": _is_muted
	}


## Deserialize state from save.
func from_dict(data: Dictionary) -> void:
	var saved_state: int = data.get("current_state", MusicState.AMBIENT)
	_current_state = saved_state
	_target_state = saved_state
	_current_intensity = data.get("current_intensity", 0.0)
	_target_intensity = _current_intensity
	_active_layers = data.get("active_layers", {})
	_base_volume = data.get("base_volume", 1.0)
	_is_muted = data.get("is_muted", false)

	# Apply state
	set_volume(_base_volume)
	set_muted(_is_muted)
	_update_layers_for_state(_current_state)


## Get status.
func get_status() -> Dictionary:
	return {
		"state": _get_state_name(_current_state),
		"intensity": _current_intensity,
		"is_transitioning": _is_transitioning,
		"volume": _base_volume,
		"is_muted": _is_muted,
		"active_layers": _active_layers.keys().filter(func(l): return _active_layers[l])
	}
