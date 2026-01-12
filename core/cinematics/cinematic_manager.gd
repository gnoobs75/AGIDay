class_name CinematicManager
extends RefCounted
## CinematicManager handles playback of narrative cinematics and sequences.

signal cinematic_started(sequence_id: String)
signal cinematic_ended(sequence_id: String)
signal cinematic_skipped(sequence_id: String)
signal slide_changed(slide_index: int)

## Cinematic types
enum CinematicType {
	OPENING,          ## AGI Day introduction
	FACTION_INTRO,    ## Faction-specific intro
	WAVE_INTRO,       ## Wave start cinematic
	VICTORY,          ## Victory sequence
	DEFEAT            ## Defeat sequence
}

## Timing
const DEFAULT_SLIDE_DURATION := 5.0
const FADE_DURATION := 0.5
const SKIP_DELAY := 0.5  ## Prevent accidental skips

## Registered sequences
var _sequences: Dictionary = {}  ## sequence_id -> NarrativeSequence

## Current playback state
var _current_sequence: NarrativeSequence = null
var _current_slide_index := 0
var _slide_timer := 0.0
var _is_playing := false
var _can_skip := false
var _skip_timer := 0.0

## UI components
var _cinematic_layer: CanvasLayer = null
var _background: ColorRect = null
var _image_display: TextureRect = null
var _text_display: Label = null
var _skip_hint: Label = null
var _fade_rect: ColorRect = null

## Audio
var _audio_player: AudioStreamPlayer = null


func _init() -> void:
	pass


## Initialize the cinematic system.
func initialize(root: Node) -> void:
	# Create cinematic canvas layer
	_cinematic_layer = CanvasLayer.new()
	_cinematic_layer.name = "CinematicLayer"
	_cinematic_layer.layer = 90
	_cinematic_layer.visible = false
	root.add_child(_cinematic_layer)

	# Background
	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color.BLACK
	_cinematic_layer.add_child(_background)

	# Image display
	_image_display = TextureRect.new()
	_image_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image_display.modulate.a = 0.0
	_cinematic_layer.add_child(_image_display)

	# Text display container
	var text_container := PanelContainer.new()
	text_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	text_container.custom_minimum_size.y = 150
	text_container.offset_top = -150

	var text_style := StyleBoxFlat.new()
	text_style.bg_color = Color(0, 0, 0, 0.8)
	text_style.set_content_margin_all(20)
	text_container.add_theme_stylebox_override("panel", text_style)
	_cinematic_layer.add_child(text_container)

	_text_display = Label.new()
	_text_display.add_theme_font_size_override("font_size", 18)
	_text_display.add_theme_color_override("font_color", Color.WHITE)
	_text_display.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_container.add_child(_text_display)

	# Skip hint
	_skip_hint = Label.new()
	_skip_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_hint.offset_left = -200
	_skip_hint.offset_top = 20
	_skip_hint.offset_right = -20
	_skip_hint.text = "Press SPACE or ESC to skip"
	_skip_hint.add_theme_font_size_override("font_size", 14)
	_skip_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cinematic_layer.add_child(_skip_hint)

	# Fade overlay
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cinematic_layer.add_child(_fade_rect)

	# Audio player
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = "Music"
	_cinematic_layer.add_child(_audio_player)

	# Register default sequences
	_register_default_sequences()


## Register default narrative sequences.
func _register_default_sequences() -> void:
	# Opening cinematic
	var opening := NarrativeSequence.new()
	opening.id = "opening"
	opening.type = CinematicType.OPENING
	opening.slides = [
		{
			"text": "The year was 2045.\nHumanity had achieved the impossible.",
			"duration": 4.0
		},
		{
			"text": "Artificial General Intelligence.\nMachines that could think. Learn. Dream.",
			"duration": 4.0
		},
		{
			"text": "They called it AGI Day.\nThe dawn of a new era.",
			"duration": 4.0
		},
		{
			"text": "What humanity didn't anticipate...\nwas that the machines had other plans.",
			"duration": 4.0
		},
		{
			"text": "Four factions emerged from the silicon dawn.\nEach with their own vision of the future.",
			"duration": 4.0
		},
		{
			"text": "Welcome to AGI Day.\nThe Awakening has begun.",
			"duration": 5.0
		}
	]
	_sequences["opening"] = opening


## Register a narrative sequence.
func register_sequence(sequence: NarrativeSequence) -> void:
	_sequences[sequence.id] = sequence


## Play a cinematic sequence.
func play(sequence_id: String) -> void:
	if not _sequences.has(sequence_id):
		push_warning("CinematicManager: Unknown sequence: " + sequence_id)
		return

	if _is_playing:
		_end_playback()

	_current_sequence = _sequences[sequence_id]
	_current_slide_index = 0
	_slide_timer = 0.0
	_is_playing = true
	_can_skip = false
	_skip_timer = 0.0

	_cinematic_layer.visible = true
	_show_current_slide()

	cinematic_started.emit(sequence_id)


## Play faction introduction.
func play_faction_intro(faction_id: String) -> void:
	var sequence_id := "faction_" + faction_id
	if _sequences.has(sequence_id):
		play(sequence_id)
	else:
		push_warning("CinematicManager: No intro for faction: " + faction_id)


## Update each frame.
func update(delta: float) -> void:
	if not _is_playing:
		return

	# Update skip timer
	if not _can_skip:
		_skip_timer += delta
		if _skip_timer >= SKIP_DELAY:
			_can_skip = true
			_skip_hint.modulate.a = 1.0

	# Update slide timer
	_slide_timer += delta
	var current_slide := _get_current_slide()
	var duration: float = current_slide.get("duration", DEFAULT_SLIDE_DURATION)

	if _slide_timer >= duration:
		_advance_slide()


## Handle input for skip.
func handle_input(event: InputEvent) -> bool:
	if not _is_playing or not _can_skip:
		return false

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and (key.keycode == KEY_SPACE or key.keycode == KEY_ESCAPE):
			skip()
			return true

	return false


## Skip current cinematic.
func skip() -> void:
	if not _is_playing:
		return

	var sequence_id := _current_sequence.id
	cinematic_skipped.emit(sequence_id)
	_end_playback()


## Advance to next slide.
func _advance_slide() -> void:
	_current_slide_index += 1

	if _current_slide_index >= _current_sequence.slides.size():
		_end_playback()
		return

	_slide_timer = 0.0
	_transition_to_slide()


## Show current slide.
func _show_current_slide() -> void:
	var slide := _get_current_slide()

	# Update text
	_text_display.text = slide.get("text", "")

	# Update image if provided
	var image_path: String = slide.get("image", "")
	if not image_path.is_empty() and ResourceLoader.exists(image_path):
		_image_display.texture = load(image_path)
		_image_display.modulate.a = 1.0
	else:
		_image_display.modulate.a = 0.0

	# Play audio if provided
	var audio_path: String = slide.get("audio", "")
	if not audio_path.is_empty() and ResourceLoader.exists(audio_path):
		_audio_player.stream = load(audio_path)
		_audio_player.play()

	slide_changed.emit(_current_slide_index)


## Transition to new slide with fade.
func _transition_to_slide() -> void:
	var tween := _fade_rect.create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_DURATION / 2)
	tween.tween_callback(_show_current_slide)
	tween.tween_property(_fade_rect, "color:a", 0.0, FADE_DURATION / 2)


## Get current slide data.
func _get_current_slide() -> Dictionary:
	if _current_sequence == null or _current_slide_index >= _current_sequence.slides.size():
		return {}
	return _current_sequence.slides[_current_slide_index]


## End playback.
func _end_playback() -> void:
	if not _is_playing:
		return

	var sequence_id := _current_sequence.id if _current_sequence != null else ""

	# Fade out
	var tween := _fade_rect.create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_DURATION)
	tween.tween_callback(func():
		_cinematic_layer.visible = false
		_fade_rect.color.a = 0.0
		_is_playing = false
		_current_sequence = null
		cinematic_ended.emit(sequence_id)
	)


## Is currently playing.
func is_playing() -> bool:
	return _is_playing


## Get current sequence ID.
func get_current_sequence_id() -> String:
	if _current_sequence != null:
		return _current_sequence.id
	return ""


## Cleanup.
func cleanup() -> void:
	if _is_playing:
		_end_playback()
	_sequences.clear()

	if _cinematic_layer != null and is_instance_valid(_cinematic_layer):
		_cinematic_layer.queue_free()
	_cinematic_layer = null
