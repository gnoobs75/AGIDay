class_name SettingsManager
extends RefCounted
## SettingsManager handles persistent storage of user settings.
## Uses Godot's ConfigFile for cross-platform settings persistence.

signal settings_loaded()
signal settings_saved()
signal setting_changed(section: String, key: String, value: Variant)

## Settings file path
const SETTINGS_FILE := "user://settings.cfg"
const SETTINGS_VERSION := 1

## Default settings
const DEFAULT_AUDIO := {
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"ui_volume": 1.0,
	"ambient_volume": 0.7,
	"voice_volume": 1.0,
	"mute_on_focus_loss": false
}

const DEFAULT_CONTROLS := {
	"camera_pan_speed": 15.0,
	"camera_zoom_speed": 2.0,
	"edge_pan_enabled": true,
	"edge_pan_margin": 20,
	"mouse_sensitivity": 1.0,
	"invert_zoom": false,
	"double_click_select_all": true
}

const DEFAULT_GAMEPLAY := {
	"game_speed": 1.0,
	"auto_pause_on_focus_loss": true,
	"show_health_bars": true,
	"show_damage_numbers": true,
	"show_minimap": true,
	"show_tutorial_hints": true,
	"human_remnant_enabled": true
}

const DEFAULT_GRAPHICS := {
	"fullscreen": false,
	"vsync": true,
	"max_fps": 60,
	"particle_quality": 2,  # 0=low, 1=medium, 2=high
	"shadow_quality": 2,
	"show_fps": false
}

const DEFAULT_ACCESSIBILITY := {
	"colorblind_mode": 0,  # 0=off, 1=protanopia, 2=deuteranopia, 3=tritanopia
	"screen_shake": true,
	"flash_effects": true,
	"font_size_multiplier": 1.0
}

## Active settings
var _audio: Dictionary = {}
var _controls: Dictionary = {}
var _gameplay: Dictionary = {}
var _graphics: Dictionary = {}
var _accessibility: Dictionary = {}

## Config file
var _config: ConfigFile = null
var _is_loaded := false


func _init() -> void:
	_config = ConfigFile.new()
	_reset_to_defaults()


## Reset all settings to defaults.
func _reset_to_defaults() -> void:
	_audio = DEFAULT_AUDIO.duplicate()
	_controls = DEFAULT_CONTROLS.duplicate()
	_gameplay = DEFAULT_GAMEPLAY.duplicate()
	_graphics = DEFAULT_GRAPHICS.duplicate()
	_accessibility = DEFAULT_ACCESSIBILITY.duplicate()


## Load settings from file.
func load_settings() -> bool:
	var err := _config.load(SETTINGS_FILE)

	if err == ERR_FILE_NOT_FOUND:
		# First run, use defaults and save them
		print("Settings file not found, using defaults")
		_reset_to_defaults()
		save_settings()
		_is_loaded = true
		settings_loaded.emit()
		return true
	elif err != OK:
		push_warning("Failed to load settings: %s" % error_string(err))
		_reset_to_defaults()
		_is_loaded = true
		settings_loaded.emit()
		return false

	# Load audio settings
	for key in DEFAULT_AUDIO:
		_audio[key] = _config.get_value("audio", key, DEFAULT_AUDIO[key])

	# Load control settings
	for key in DEFAULT_CONTROLS:
		_controls[key] = _config.get_value("controls", key, DEFAULT_CONTROLS[key])

	# Load gameplay settings
	for key in DEFAULT_GAMEPLAY:
		_gameplay[key] = _config.get_value("gameplay", key, DEFAULT_GAMEPLAY[key])

	# Load graphics settings
	for key in DEFAULT_GRAPHICS:
		_graphics[key] = _config.get_value("graphics", key, DEFAULT_GRAPHICS[key])

	# Load accessibility settings
	for key in DEFAULT_ACCESSIBILITY:
		_accessibility[key] = _config.get_value("accessibility", key, DEFAULT_ACCESSIBILITY[key])

	print("Settings loaded from %s" % SETTINGS_FILE)
	_is_loaded = true
	settings_loaded.emit()
	return true


## Save settings to file.
func save_settings() -> bool:
	# Save version
	_config.set_value("meta", "version", SETTINGS_VERSION)

	# Save audio settings
	for key in _audio:
		_config.set_value("audio", key, _audio[key])

	# Save control settings
	for key in _controls:
		_config.set_value("controls", key, _controls[key])

	# Save gameplay settings
	for key in _gameplay:
		_config.set_value("gameplay", key, _gameplay[key])

	# Save graphics settings
	for key in _graphics:
		_config.set_value("graphics", key, _graphics[key])

	# Save accessibility settings
	for key in _accessibility:
		_config.set_value("accessibility", key, _accessibility[key])

	var err := _config.save(SETTINGS_FILE)
	if err != OK:
		push_error("Failed to save settings: %s" % error_string(err))
		return false

	print("Settings saved to %s" % SETTINGS_FILE)
	settings_saved.emit()
	return true


# =============================================================================
# AUDIO SETTINGS
# =============================================================================

## Get master volume (0.0 to 1.0).
func get_master_volume() -> float:
	return _audio.get("master_volume", 1.0)


## Set master volume.
func set_master_volume(value: float) -> void:
	_audio["master_volume"] = clampf(value, 0.0, 1.0)
	setting_changed.emit("audio", "master_volume", _audio["master_volume"])


## Get music volume.
func get_music_volume() -> float:
	return _audio.get("music_volume", 0.8)


## Set music volume.
func set_music_volume(value: float) -> void:
	_audio["music_volume"] = clampf(value, 0.0, 1.0)
	setting_changed.emit("audio", "music_volume", _audio["music_volume"])


## Get SFX volume.
func get_sfx_volume() -> float:
	return _audio.get("sfx_volume", 1.0)


## Set SFX volume.
func set_sfx_volume(value: float) -> void:
	_audio["sfx_volume"] = clampf(value, 0.0, 1.0)
	setting_changed.emit("audio", "sfx_volume", _audio["sfx_volume"])


## Get UI volume.
func get_ui_volume() -> float:
	return _audio.get("ui_volume", 1.0)


## Set UI volume.
func set_ui_volume(value: float) -> void:
	_audio["ui_volume"] = clampf(value, 0.0, 1.0)
	setting_changed.emit("audio", "ui_volume", _audio["ui_volume"])


## Get ambient volume.
func get_ambient_volume() -> float:
	return _audio.get("ambient_volume", 0.7)


## Set ambient volume.
func set_ambient_volume(value: float) -> void:
	_audio["ambient_volume"] = clampf(value, 0.0, 1.0)
	setting_changed.emit("audio", "ambient_volume", _audio["ambient_volume"])


## Get voice volume.
func get_voice_volume() -> float:
	return _audio.get("voice_volume", 1.0)


## Set voice volume.
func set_voice_volume(value: float) -> void:
	_audio["voice_volume"] = clampf(value, 0.0, 1.0)
	setting_changed.emit("audio", "voice_volume", _audio["voice_volume"])


## Get mute on focus loss setting.
func get_mute_on_focus_loss() -> bool:
	return _audio.get("mute_on_focus_loss", false)


## Set mute on focus loss.
func set_mute_on_focus_loss(value: bool) -> void:
	_audio["mute_on_focus_loss"] = value
	setting_changed.emit("audio", "mute_on_focus_loss", value)


# =============================================================================
# CONTROL SETTINGS
# =============================================================================

## Get camera pan speed.
func get_camera_pan_speed() -> float:
	return _controls.get("camera_pan_speed", 15.0)


## Set camera pan speed.
func set_camera_pan_speed(value: float) -> void:
	_controls["camera_pan_speed"] = clampf(value, 1.0, 50.0)
	setting_changed.emit("controls", "camera_pan_speed", _controls["camera_pan_speed"])


## Get camera zoom speed.
func get_camera_zoom_speed() -> float:
	return _controls.get("camera_zoom_speed", 2.0)


## Set camera zoom speed.
func set_camera_zoom_speed(value: float) -> void:
	_controls["camera_zoom_speed"] = clampf(value, 0.5, 10.0)
	setting_changed.emit("controls", "camera_zoom_speed", _controls["camera_zoom_speed"])


## Get edge pan enabled.
func get_edge_pan_enabled() -> bool:
	return _controls.get("edge_pan_enabled", true)


## Set edge pan enabled.
func set_edge_pan_enabled(value: bool) -> void:
	_controls["edge_pan_enabled"] = value
	setting_changed.emit("controls", "edge_pan_enabled", value)


## Get edge pan margin.
func get_edge_pan_margin() -> int:
	return _controls.get("edge_pan_margin", 20)


## Set edge pan margin.
func set_edge_pan_margin(value: int) -> void:
	_controls["edge_pan_margin"] = clampi(value, 5, 100)
	setting_changed.emit("controls", "edge_pan_margin", _controls["edge_pan_margin"])


## Get mouse sensitivity.
func get_mouse_sensitivity() -> float:
	return _controls.get("mouse_sensitivity", 1.0)


## Set mouse sensitivity.
func set_mouse_sensitivity(value: float) -> void:
	_controls["mouse_sensitivity"] = clampf(value, 0.1, 5.0)
	setting_changed.emit("controls", "mouse_sensitivity", _controls["mouse_sensitivity"])


## Get invert zoom setting.
func get_invert_zoom() -> bool:
	return _controls.get("invert_zoom", false)


## Set invert zoom.
func set_invert_zoom(value: bool) -> void:
	_controls["invert_zoom"] = value
	setting_changed.emit("controls", "invert_zoom", value)


# =============================================================================
# GAMEPLAY SETTINGS
# =============================================================================

## Get game speed.
func get_game_speed() -> float:
	return _gameplay.get("game_speed", 1.0)


## Set game speed.
func set_game_speed(value: float) -> void:
	_gameplay["game_speed"] = clampf(value, 0.5, 3.0)
	setting_changed.emit("gameplay", "game_speed", _gameplay["game_speed"])


## Get auto pause on focus loss.
func get_auto_pause_on_focus_loss() -> bool:
	return _gameplay.get("auto_pause_on_focus_loss", true)


## Set auto pause on focus loss.
func set_auto_pause_on_focus_loss(value: bool) -> void:
	_gameplay["auto_pause_on_focus_loss"] = value
	setting_changed.emit("gameplay", "auto_pause_on_focus_loss", value)


## Get show health bars.
func get_show_health_bars() -> bool:
	return _gameplay.get("show_health_bars", true)


## Set show health bars.
func set_show_health_bars(value: bool) -> void:
	_gameplay["show_health_bars"] = value
	setting_changed.emit("gameplay", "show_health_bars", value)


## Get show damage numbers.
func get_show_damage_numbers() -> bool:
	return _gameplay.get("show_damage_numbers", true)


## Set show damage numbers.
func set_show_damage_numbers(value: bool) -> void:
	_gameplay["show_damage_numbers"] = value
	setting_changed.emit("gameplay", "show_damage_numbers", value)


## Get Human Remnant enabled.
func get_human_remnant_enabled() -> bool:
	return _gameplay.get("human_remnant_enabled", true)


## Set Human Remnant enabled.
func set_human_remnant_enabled(value: bool) -> void:
	_gameplay["human_remnant_enabled"] = value
	setting_changed.emit("gameplay", "human_remnant_enabled", value)


# =============================================================================
# GRAPHICS SETTINGS
# =============================================================================

## Get fullscreen mode.
func get_fullscreen() -> bool:
	return _graphics.get("fullscreen", false)


## Set fullscreen mode.
func set_fullscreen(value: bool) -> void:
	_graphics["fullscreen"] = value
	setting_changed.emit("graphics", "fullscreen", value)


## Get vsync.
func get_vsync() -> bool:
	return _graphics.get("vsync", true)


## Set vsync.
func set_vsync(value: bool) -> void:
	_graphics["vsync"] = value
	setting_changed.emit("graphics", "vsync", value)


## Get max FPS.
func get_max_fps() -> int:
	return _graphics.get("max_fps", 60)


## Set max FPS.
func set_max_fps(value: int) -> void:
	_graphics["max_fps"] = clampi(value, 30, 240)
	setting_changed.emit("graphics", "max_fps", _graphics["max_fps"])


## Get show FPS.
func get_show_fps() -> bool:
	return _graphics.get("show_fps", false)


## Set show FPS.
func set_show_fps(value: bool) -> void:
	_graphics["show_fps"] = value
	setting_changed.emit("graphics", "show_fps", value)


# =============================================================================
# ACCESSIBILITY SETTINGS
# =============================================================================

## Get colorblind mode.
func get_colorblind_mode() -> int:
	return _accessibility.get("colorblind_mode", 0)


## Set colorblind mode.
func set_colorblind_mode(value: int) -> void:
	_accessibility["colorblind_mode"] = clampi(value, 0, 3)
	setting_changed.emit("accessibility", "colorblind_mode", _accessibility["colorblind_mode"])


## Get screen shake enabled.
func get_screen_shake() -> bool:
	return _accessibility.get("screen_shake", true)


## Set screen shake.
func set_screen_shake(value: bool) -> void:
	_accessibility["screen_shake"] = value
	setting_changed.emit("accessibility", "screen_shake", value)


## Get flash effects enabled.
func get_flash_effects() -> bool:
	return _accessibility.get("flash_effects", true)


## Set flash effects.
func set_flash_effects(value: bool) -> void:
	_accessibility["flash_effects"] = value
	setting_changed.emit("accessibility", "flash_effects", value)


# =============================================================================
# UTILITY
# =============================================================================

## Get all audio settings.
func get_audio_settings() -> Dictionary:
	return _audio.duplicate()


## Get all control settings.
func get_control_settings() -> Dictionary:
	return _controls.duplicate()


## Get all gameplay settings.
func get_gameplay_settings() -> Dictionary:
	return _gameplay.duplicate()


## Get all graphics settings.
func get_graphics_settings() -> Dictionary:
	return _graphics.duplicate()


## Get all accessibility settings.
func get_accessibility_settings() -> Dictionary:
	return _accessibility.duplicate()


## Check if settings are loaded.
func is_loaded() -> bool:
	return _is_loaded


## Reset a section to defaults.
func reset_section(section: String) -> void:
	match section:
		"audio":
			_audio = DEFAULT_AUDIO.duplicate()
		"controls":
			_controls = DEFAULT_CONTROLS.duplicate()
		"gameplay":
			_gameplay = DEFAULT_GAMEPLAY.duplicate()
		"graphics":
			_graphics = DEFAULT_GRAPHICS.duplicate()
		"accessibility":
			_accessibility = DEFAULT_ACCESSIBILITY.duplicate()
	setting_changed.emit(section, "", null)


## Reset all settings to defaults.
func reset_all() -> void:
	_reset_to_defaults()
	setting_changed.emit("all", "", null)


## Serialize to dictionary (for debugging).
func to_dict() -> Dictionary:
	return {
		"version": SETTINGS_VERSION,
		"audio": _audio.duplicate(),
		"controls": _controls.duplicate(),
		"gameplay": _gameplay.duplicate(),
		"graphics": _graphics.duplicate(),
		"accessibility": _accessibility.duplicate()
	}
