class_name NarrativeSequence
extends RefCounted
## NarrativeSequence defines a single cinematic sequence with slides and metadata.

## Sequence identification
var id: String = ""
var type: int = 0  ## CinematicManager.CinematicType

## Display settings
var title: String = ""
var subtitle: String = ""

## Slide data - Array of Dictionaries with:
## - text: String - Narrative text to display
## - image: String - Optional image resource path
## - audio: String - Optional audio resource path
## - duration: float - How long to show this slide (default 5.0)
## - effect: String - Optional transition effect name
var slides: Array[Dictionary] = []

## Audio settings
var background_music: String = ""
var ambient_sound: String = ""

## Playback options
var can_skip: bool = true
var auto_advance: bool = true
var loop: bool = false

## Metadata
var faction_id: String = ""  ## For faction-specific sequences
var unlock_condition: String = ""  ## Condition to unlock this sequence


func _init() -> void:
	pass


## Create from dictionary data.
static func from_dict(data: Dictionary) -> NarrativeSequence:
	var sequence := NarrativeSequence.new()

	sequence.id = data.get("id", "")
	sequence.type = data.get("type", 0)
	sequence.title = data.get("title", "")
	sequence.subtitle = data.get("subtitle", "")

	# Parse slides
	var slides_data: Array = data.get("slides", [])
	for slide_data in slides_data:
		if slide_data is Dictionary:
			sequence.slides.append(slide_data)

	sequence.background_music = data.get("background_music", "")
	sequence.ambient_sound = data.get("ambient_sound", "")
	sequence.can_skip = data.get("can_skip", true)
	sequence.auto_advance = data.get("auto_advance", true)
	sequence.loop = data.get("loop", false)
	sequence.faction_id = data.get("faction_id", "")
	sequence.unlock_condition = data.get("unlock_condition", "")

	return sequence


## Convert to dictionary for serialization.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"title": title,
		"subtitle": subtitle,
		"slides": slides,
		"background_music": background_music,
		"ambient_sound": ambient_sound,
		"can_skip": can_skip,
		"auto_advance": auto_advance,
		"loop": loop,
		"faction_id": faction_id,
		"unlock_condition": unlock_condition
	}


## Add a text-only slide.
func add_text_slide(text: String, duration: float = 5.0) -> NarrativeSequence:
	slides.append({
		"text": text,
		"duration": duration
	})
	return self


## Add a slide with image.
func add_image_slide(text: String, image_path: String, duration: float = 5.0) -> NarrativeSequence:
	slides.append({
		"text": text,
		"image": image_path,
		"duration": duration
	})
	return self


## Add a slide with audio.
func add_audio_slide(text: String, audio_path: String, duration: float = 5.0) -> NarrativeSequence:
	slides.append({
		"text": text,
		"audio": audio_path,
		"duration": duration
	})
	return self


## Add a full slide with all options.
func add_slide(text: String, image_path: String = "", audio_path: String = "",
			   duration: float = 5.0, effect: String = "") -> NarrativeSequence:
	var slide := {"text": text, "duration": duration}
	if not image_path.is_empty():
		slide["image"] = image_path
	if not audio_path.is_empty():
		slide["audio"] = audio_path
	if not effect.is_empty():
		slide["effect"] = effect
	slides.append(slide)
	return self


## Get slide count.
func get_slide_count() -> int:
	return slides.size()


## Get total duration.
func get_total_duration() -> float:
	var total := 0.0
	for slide in slides:
		total += slide.get("duration", 5.0)
	return total


## Get slide at index.
func get_slide(index: int) -> Dictionary:
	if index < 0 or index >= slides.size():
		return {}
	return slides[index]


## Validate sequence data.
func is_valid() -> bool:
	if id.is_empty():
		return false
	if slides.is_empty():
		return false
	return true
