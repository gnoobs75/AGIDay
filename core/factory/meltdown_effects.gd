class_name MeltdownEffects
extends RefCounted
## MeltdownEffects manages visual and audio effects for factory meltdowns.

signal effects_started(factory_id: int)
signal effects_ended(factory_id: int)

## Meltdown timing
const MELTDOWN_DURATION := 30.0  ## Seconds

## Light settings
const LIGHT_COLOR := Color.RED
const LIGHT_INITIAL_ENERGY := 2.0
const LIGHT_FINAL_ENERGY := 0.5
const LIGHT_RANGE := 20.0

## Particle settings
const PARTICLE_AMOUNT_RATIO := 1.0
const PARTICLE_LIFETIME := 2.0

## Audio
const MELTDOWN_AUDIO_PATH := "res://assets/audio/sfx/factory_meltdown.ogg"

## Active meltdowns
var _active_meltdowns: Dictionary = {}  ## factory_id -> MeltdownData


func _init() -> void:
	pass


## Trigger meltdown effects for a factory.
func trigger_meltdown(factory_id: int, factory_node: Node3D) -> void:
	if factory_node == null:
		return

	if _active_meltdowns.has(factory_id):
		return  # Already melting down

	var data := MeltdownData.new()
	data.factory_id = factory_id
	data.factory_node = factory_node
	data.start_time = Time.get_ticks_msec() / 1000.0
	data.duration = MELTDOWN_DURATION

	# Create effects
	data.light = _create_meltdown_light(factory_node)
	data.particles = _create_meltdown_particles(factory_node)
	data.audio = _create_meltdown_audio(factory_node)

	# Start light energy tween
	if data.light != null:
		data.light_tween = data.light.create_tween()
		data.light_tween.tween_property(data.light, "light_energy", LIGHT_FINAL_ENERGY, MELTDOWN_DURATION)

	_active_meltdowns[factory_id] = data
	effects_started.emit(factory_id)


## Create meltdown light effect.
func _create_meltdown_light(parent: Node3D) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "MeltdownLight"
	light.light_color = LIGHT_COLOR
	light.light_energy = LIGHT_INITIAL_ENERGY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false  # Performance optimization
	light.position = Vector3(0, 2, 0)  # Slightly above factory

	parent.add_child(light)
	return light


## Create meltdown particle effect.
func _create_meltdown_particles(parent: Node3D) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "MeltdownParticles"
	particles.amount = 100
	particles.lifetime = PARTICLE_LIFETIME
	particles.emitting = true
	particles.one_shot = false
	particles.amount_ratio = PARTICLE_AMOUNT_RATIO
	particles.position = Vector3(0, 1, 0)

	# Create process material
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3(0, -2, 0)
	material.scale_min = 0.1
	material.scale_max = 0.3
	material.color = LIGHT_COLOR

	# Add some orange/yellow variation
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color.YELLOW)
	color_ramp.set_color(1, Color.RED)
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = color_ramp
	material.color_ramp = color_texture

	particles.process_material = material

	# Create simple mesh for particles
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh

	parent.add_child(particles)
	return particles


## Create meltdown audio effect.
func _create_meltdown_audio(parent: Node3D) -> AudioStreamPlayer3D:
	var audio := AudioStreamPlayer3D.new()
	audio.name = "MeltdownAudio"
	audio.max_distance = 50.0
	audio.unit_size = 10.0

	# Load audio stream
	if ResourceLoader.exists(MELTDOWN_AUDIO_PATH):
		audio.stream = load(MELTDOWN_AUDIO_PATH)
		audio.play()
	else:
		# Fallback: create placeholder effect info
		push_warning("MeltdownEffects: Audio file not found: " + MELTDOWN_AUDIO_PATH)

	parent.add_child(audio)
	return audio


## Update effects each frame.
func update(delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	var completed: Array[int] = []

	for factory_id in _active_meltdowns:
		var data: MeltdownData = _active_meltdowns[factory_id]
		var elapsed := current_time - data.start_time

		if elapsed >= data.duration:
			completed.append(factory_id)
		else:
			# Update particle intensity based on progress
			var progress := elapsed / data.duration
			if data.particles != null:
				# Particles get more intense near the end
				data.particles.amount_ratio = lerpf(0.5, 1.0, progress)

	# Clean up completed meltdowns
	for factory_id in completed:
		_end_meltdown(factory_id)


## End meltdown effects.
func _end_meltdown(factory_id: int) -> void:
	if not _active_meltdowns.has(factory_id):
		return

	var data: MeltdownData = _active_meltdowns[factory_id]

	# Stop and cleanup effects
	if data.light_tween != null and data.light_tween.is_valid():
		data.light_tween.kill()

	if data.light != null and is_instance_valid(data.light):
		data.light.queue_free()

	if data.particles != null and is_instance_valid(data.particles):
		data.particles.emitting = false
		# Delay removal to let particles fade
		var tree := data.particles.get_tree()
		if tree != null:
			await tree.create_timer(PARTICLE_LIFETIME).timeout
		if is_instance_valid(data.particles):
			data.particles.queue_free()

	if data.audio != null and is_instance_valid(data.audio):
		data.audio.stop()
		data.audio.queue_free()

	_active_meltdowns.erase(factory_id)
	effects_ended.emit(factory_id)


## Cancel meltdown effects (for recovery).
func cancel_meltdown(factory_id: int) -> void:
	if not _active_meltdowns.has(factory_id):
		return

	var data: MeltdownData = _active_meltdowns[factory_id]

	# Quick fade out
	if data.light != null and is_instance_valid(data.light):
		if data.light_tween != null and data.light_tween.is_valid():
			data.light_tween.kill()
		var fade_tween := data.light.create_tween()
		fade_tween.tween_property(data.light, "light_energy", 0.0, 1.0)
		fade_tween.tween_callback(data.light.queue_free)

	if data.particles != null and is_instance_valid(data.particles):
		data.particles.emitting = false
		# Delay removal
		var timer := data.particles.get_tree().create_timer(PARTICLE_LIFETIME)
		timer.timeout.connect(func():
			if is_instance_valid(data.particles):
				data.particles.queue_free()
		)

	if data.audio != null and is_instance_valid(data.audio):
		var audio_tween := data.audio.create_tween()
		audio_tween.tween_property(data.audio, "volume_db", -40.0, 1.0)
		audio_tween.tween_callback(func():
			data.audio.stop()
			data.audio.queue_free()
		)

	_active_meltdowns.erase(factory_id)


## Is factory currently melting down.
func is_melting_down(factory_id: int) -> bool:
	return _active_meltdowns.has(factory_id)


## Get active meltdown count.
func get_active_count() -> int:
	return _active_meltdowns.size()


## Get meltdown progress (0.0 to 1.0).
func get_meltdown_progress(factory_id: int) -> float:
	if not _active_meltdowns.has(factory_id):
		return 0.0

	var data: MeltdownData = _active_meltdowns[factory_id]
	var current_time := Time.get_ticks_msec() / 1000.0
	var elapsed := current_time - data.start_time
	return clampf(elapsed / data.duration, 0.0, 1.0)


## Cleanup all effects.
func cleanup() -> void:
	for factory_id in _active_meltdowns.keys():
		cancel_meltdown(factory_id)
	_active_meltdowns.clear()


## MeltdownData helper class.
class MeltdownData:
	var factory_id: int
	var factory_node: Node3D
	var start_time: float
	var duration: float
	var light: OmniLight3D
	var light_tween: Tween
	var particles: GPUParticles3D
	var audio: AudioStreamPlayer3D
