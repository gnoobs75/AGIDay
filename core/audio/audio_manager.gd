class_name AudioManager
extends RefCounted
## AudioManager provides comprehensive audio management with pooling and ECS integration.
## Handles music streaming, SFX pre-loading, and 3D spatial audio.

signal sfx_played(sfx_id: String, position: Vector3)
signal volume_changed(bus: String, volume: float)
signal audio_pool_exhausted(pool_name: String)

## Audio buses
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"
const BUS_AMBIENT := "Ambient"
const BUS_VOICE := "Voice"

## Pool configuration
const MAX_SFX_PLAYERS := 64
const MAX_3D_PLAYERS := 128
const POOL_EXPAND_SIZE := 8

## Frame budget
const FRAME_BUDGET_MS := 1.0  ## 1ms for audio processing

## SFX categories for pre-loading
enum SFXCategory {
	UNIT_COMBAT,
	UNIT_MOVEMENT,
	UNIT_VOICE,
	PROJECTILE,
	EXPLOSION,
	UI,
	ENVIRONMENT,
	CONSTRUCTION
}

## Sub-systems
var _music_manager: DynamicMusicManager = null

## Audio players pool
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var _active_sfx: Dictionary = {}  ## player -> {sfx_id, start_time}
var _active_3d_sfx: Dictionary = {}

## Pre-loaded sounds
var _preloaded_sfx: Dictionary = {}  ## sfx_id -> AudioStream
var _sfx_metadata: Dictionary = {}   ## sfx_id -> {category, volume, pitch_variance}

## Volume settings
var _bus_volumes: Dictionary = {
	BUS_MASTER: 1.0,
	BUS_MUSIC: 0.8,
	BUS_SFX: 1.0,
	BUS_UI: 1.0,
	BUS_AMBIENT: 0.7,
	BUS_VOICE: 1.0
}

## State
var _is_initialized := false
var _scene_tree: SceneTree = null
var _audio_root: Node = null

## Statistics
var _sfx_played_this_frame := 0
var _total_sfx_played := 0
var _pool_misses := 0


func _init() -> void:
	pass


## Initialize audio system.
func initialize(scene_tree: SceneTree) -> void:
	_scene_tree = scene_tree

	# Create audio root node
	_audio_root = Node.new()
	_audio_root.name = "AudioManager"
	scene_tree.root.call_deferred("add_child", _audio_root)

	# Initialize audio buses
	_setup_audio_buses()

	# Create player pools
	_create_sfx_pool()
	_create_3d_pool()

	# Initialize music manager
	_music_manager = DynamicMusicManager.new()
	_music_manager.initialize()

	# Pre-load common SFX
	_preload_common_sfx()

	_is_initialized = true


## Setup audio buses.
func _setup_audio_buses() -> void:
	# Apply saved volumes
	for bus_name in _bus_volumes:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			var volume: float = _bus_volumes[bus_name]
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(volume))


## Create 2D SFX player pool.
func _create_sfx_pool() -> void:
	for i in MAX_SFX_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		_sfx_pool.append(player)
		_audio_root.call_deferred("add_child", player)


## Create 3D SFX player pool.
func _create_3d_pool() -> void:
	for i in MAX_3D_PLAYERS:
		var player := AudioStreamPlayer3D.new()
		player.bus = BUS_SFX
		player.max_distance = 100.0
		player.unit_size = 10.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_sfx_3d_pool.append(player)
		_audio_root.call_deferred("add_child", player)


## Pre-load common sound effects.
func _preload_common_sfx() -> void:
	# Define common SFX to pre-load
	var common_sfx := {
		# Combat
		"laser_fire": {"path": "res://assets/audio/sfx/laser_fire.ogg", "category": SFXCategory.PROJECTILE},
		"bullet_fire": {"path": "res://assets/audio/sfx/bullet_fire.ogg", "category": SFXCategory.PROJECTILE},
		"missile_launch": {"path": "res://assets/audio/sfx/missile_launch.ogg", "category": SFXCategory.PROJECTILE},
		"explosion_small": {"path": "res://assets/audio/sfx/explosion_small.ogg", "category": SFXCategory.EXPLOSION},
		"explosion_medium": {"path": "res://assets/audio/sfx/explosion_medium.ogg", "category": SFXCategory.EXPLOSION},
		"explosion_large": {"path": "res://assets/audio/sfx/explosion_large.ogg", "category": SFXCategory.EXPLOSION},
		"hit_metal": {"path": "res://assets/audio/sfx/hit_metal.ogg", "category": SFXCategory.UNIT_COMBAT},
		"hit_flesh": {"path": "res://assets/audio/sfx/hit_flesh.ogg", "category": SFXCategory.UNIT_COMBAT},

		# Movement
		"footstep_metal": {"path": "res://assets/audio/sfx/footstep_metal.ogg", "category": SFXCategory.UNIT_MOVEMENT},
		"servo_move": {"path": "res://assets/audio/sfx/servo_move.ogg", "category": SFXCategory.UNIT_MOVEMENT},
		"hover_loop": {"path": "res://assets/audio/sfx/hover_loop.ogg", "category": SFXCategory.UNIT_MOVEMENT},

		# UI
		"button_click": {"path": "res://assets/audio/sfx/button_click.ogg", "category": SFXCategory.UI},
		"button_hover": {"path": "res://assets/audio/sfx/button_hover.ogg", "category": SFXCategory.UI},
		"menu_open": {"path": "res://assets/audio/sfx/menu_open.ogg", "category": SFXCategory.UI},
		"menu_close": {"path": "res://assets/audio/sfx/menu_close.ogg", "category": SFXCategory.UI},
		"notification": {"path": "res://assets/audio/sfx/notification.ogg", "category": SFXCategory.UI},
		"error": {"path": "res://assets/audio/sfx/error.ogg", "category": SFXCategory.UI},

		# Construction
		"build_start": {"path": "res://assets/audio/sfx/build_start.ogg", "category": SFXCategory.CONSTRUCTION},
		"build_complete": {"path": "res://assets/audio/sfx/build_complete.ogg", "category": SFXCategory.CONSTRUCTION},
		"factory_produce": {"path": "res://assets/audio/sfx/factory_produce.ogg", "category": SFXCategory.CONSTRUCTION}
	}

	for sfx_id in common_sfx:
		var data: Dictionary = common_sfx[sfx_id]
		_sfx_metadata[sfx_id] = {
			"category": data["category"],
			"volume": data.get("volume", 1.0),
			"pitch_variance": data.get("pitch_variance", 0.1)
		}

		# Try to load if file exists
		if ResourceLoader.exists(data["path"]):
			_preloaded_sfx[sfx_id] = load(data["path"])


## Register custom SFX.
func register_sfx(sfx_id: String, stream: AudioStream, category: SFXCategory,
				  volume: float = 1.0, pitch_variance: float = 0.1) -> void:
	_preloaded_sfx[sfx_id] = stream
	_sfx_metadata[sfx_id] = {
		"category": category,
		"volume": volume,
		"pitch_variance": pitch_variance
	}


## Update (call each frame).
func update(delta: float) -> void:
	var start_time := Time.get_ticks_usec()

	# Update music manager
	if _music_manager != null:
		_music_manager.update(delta)

	# Clean up finished players
	_cleanup_finished_players()

	# Reset frame counter
	_sfx_played_this_frame = 0

	# Check frame budget
	var elapsed_ms := (Time.get_ticks_usec() - start_time) / 1000.0
	if elapsed_ms > FRAME_BUDGET_MS:
		push_warning("AudioManager: Frame budget exceeded (%.2fms)" % elapsed_ms)


## Cleanup finished audio players.
func _cleanup_finished_players() -> void:
	# 2D players
	var finished_2d: Array = []
	for player in _active_sfx:
		if not player.playing:
			finished_2d.append(player)

	for player in finished_2d:
		_active_sfx.erase(player)

	# 3D players
	var finished_3d: Array = []
	for player in _active_3d_sfx:
		if not player.playing:
			finished_3d.append(player)

	for player in finished_3d:
		_active_3d_sfx.erase(player)


## Play 2D sound effect.
func play_sfx(sfx_id: String, volume_scale: float = 1.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	if not _preloaded_sfx.has(sfx_id):
		push_warning("AudioManager: Unknown SFX '%s'" % sfx_id)
		return null

	var player := _get_available_sfx_player()
	if player == null:
		_pool_misses += 1
		audio_pool_exhausted.emit("sfx_2d")
		return null

	var metadata: Dictionary = _sfx_metadata.get(sfx_id, {})
	var base_volume: float = metadata.get("volume", 1.0)
	var pitch_variance: float = metadata.get("pitch_variance", 0.1)

	player.stream = _preloaded_sfx[sfx_id]
	player.volume_db = linear_to_db(base_volume * volume_scale)
	player.pitch_scale = pitch_scale + randf_range(-pitch_variance, pitch_variance)
	player.play()

	_active_sfx[player] = {
		"sfx_id": sfx_id,
		"start_time": Time.get_ticks_msec()
	}

	_sfx_played_this_frame += 1
	_total_sfx_played += 1
	sfx_played.emit(sfx_id, Vector3.ZERO)

	return player


## Play 3D sound effect at position.
func play_sfx_3d(sfx_id: String, position: Vector3, volume_scale: float = 1.0,
				 pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	if not _preloaded_sfx.has(sfx_id):
		push_warning("AudioManager: Unknown SFX '%s'" % sfx_id)
		return null

	var player := _get_available_3d_player()
	if player == null:
		_pool_misses += 1
		audio_pool_exhausted.emit("sfx_3d")
		return null

	var metadata: Dictionary = _sfx_metadata.get(sfx_id, {})
	var base_volume: float = metadata.get("volume", 1.0)
	var pitch_variance: float = metadata.get("pitch_variance", 0.1)

	player.stream = _preloaded_sfx[sfx_id]
	player.global_position = position
	player.volume_db = linear_to_db(base_volume * volume_scale)
	player.pitch_scale = pitch_scale + randf_range(-pitch_variance, pitch_variance)
	player.play()

	_active_3d_sfx[player] = {
		"sfx_id": sfx_id,
		"start_time": Time.get_ticks_msec(),
		"position": position
	}

	_sfx_played_this_frame += 1
	_total_sfx_played += 1
	sfx_played.emit(sfx_id, position)

	return player


## Play UI sound effect (2D, UI bus).
func play_ui_sfx(sfx_id: String, volume_scale: float = 1.0) -> void:
	var player := play_sfx(sfx_id, volume_scale)
	if player != null:
		player.bus = BUS_UI


## Get available 2D player from pool.
func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	return null


## Get available 3D player from pool.
func _get_available_3d_player() -> AudioStreamPlayer3D:
	for player in _sfx_3d_pool:
		if not player.playing:
			return player
	return null


## Set bus volume (0.0 to 1.0).
func set_bus_volume(bus_name: String, volume: float) -> void:
	volume = clampf(volume, 0.0, 1.0)
	_bus_volumes[bus_name] = volume

	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(volume))
		volume_changed.emit(bus_name, volume)


## Get bus volume.
func get_bus_volume(bus_name: String) -> float:
	return _bus_volumes.get(bus_name, 1.0)


## Mute/unmute bus.
func set_bus_muted(bus_name: String, muted: bool) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_mute(bus_idx, muted)


## Set master volume.
func set_master_volume(volume: float) -> void:
	set_bus_volume(BUS_MASTER, volume)


## Set music volume.
func set_music_volume(volume: float) -> void:
	set_bus_volume(BUS_MUSIC, volume)


## Set SFX volume.
func set_sfx_volume(volume: float) -> void:
	set_bus_volume(BUS_SFX, volume)


## Get music manager.
func get_music_manager() -> DynamicMusicManager:
	return _music_manager


## Stop all sounds.
func stop_all() -> void:
	for player in _sfx_pool:
		player.stop()
	for player in _sfx_3d_pool:
		player.stop()
	_active_sfx.clear()
	_active_3d_sfx.clear()


## Pause all sounds.
func pause_all() -> void:
	_scene_tree.paused = true


## Resume all sounds.
func resume_all() -> void:
	_scene_tree.paused = false


## Report event for battle intensity (forwarded to music manager).
func report_battle_intensity(unit_count: int, enemy_count: int, in_combat: bool) -> void:
	if _music_manager == null:
		return

	var intensity := _music_manager.calculate_intensity(unit_count, enemy_count, in_combat)
	_music_manager.set_battle_intensity(intensity)


## Report combat event (forwarded to music manager).
func report_combat_event(severity: float = 1.0) -> void:
	if _music_manager != null:
		_music_manager.report_combat_event(severity)


## Serialize state for save.
func to_dict() -> Dictionary:
	var music_data := {}
	if _music_manager != null:
		music_data = _music_manager.to_dict()

	return {
		"bus_volumes": _bus_volumes.duplicate(),
		"music_state": music_data
	}


## Deserialize state from save.
func from_dict(data: Dictionary) -> void:
	# Restore volumes
	var saved_volumes: Dictionary = data.get("bus_volumes", {})
	for bus_name in saved_volumes:
		set_bus_volume(bus_name, saved_volumes[bus_name])

	# Restore music state
	if _music_manager != null:
		var music_data: Dictionary = data.get("music_state", {})
		if not music_data.is_empty():
			_music_manager.from_dict(music_data)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"total_sfx_played": _total_sfx_played,
		"sfx_played_this_frame": _sfx_played_this_frame,
		"active_2d_players": _active_sfx.size(),
		"active_3d_players": _active_3d_sfx.size(),
		"pool_2d_size": _sfx_pool.size(),
		"pool_3d_size": _sfx_3d_pool.size(),
		"pool_misses": _pool_misses,
		"preloaded_sfx": _preloaded_sfx.size()
	}


## Cleanup.
func cleanup() -> void:
	stop_all()
	_preloaded_sfx.clear()
	_sfx_metadata.clear()
