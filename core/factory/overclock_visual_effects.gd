class_name OverclockVisualEffects
extends RefCounted
## OverclockVisualEffects manages visual feedback for factory overclock state.
## Shows heat glow and warning effects as heat rises.

signal heat_warning_started(factory_id: int)
signal heat_warning_ended(factory_id: int)

## Heat thresholds for visual feedback
const HEAT_LOW := 0.3		## Yellow-orange glow starts
const HEAT_MEDIUM := 0.6	## Orange glow, warning sparks
const HEAT_HIGH := 0.85		## Red glow, heavy sparks, pulsing

## Active factory effects
var _factory_effects: Dictionary = {}  ## factory_id -> EffectData


## Initialize effects for a factory.
func register_factory(factory_id: int, factory_node: Node3D) -> void:
	if factory_node == null:
		return

	if _factory_effects.has(factory_id):
		return

	var data := EffectData.new()
	data.factory_id = factory_id
	data.factory_node = factory_node
	data.heat_level = 0.0

	# Create heat glow light (starts invisible)
	data.glow_light = _create_heat_glow_light(factory_node)

	# Create spark particles (starts not emitting)
	data.spark_particles = _create_spark_particles(factory_node)

	_factory_effects[factory_id] = data


## Unregister factory effects.
func unregister_factory(factory_id: int) -> void:
	if not _factory_effects.has(factory_id):
		return

	var data: EffectData = _factory_effects[factory_id]
	_cleanup_effects(data)
	_factory_effects.erase(factory_id)


## Update heat level for a factory.
func update_heat(factory_id: int, heat_level: float) -> void:
	if not _factory_effects.has(factory_id):
		return

	var data: EffectData = _factory_effects[factory_id]
	var old_heat := data.heat_level
	data.heat_level = clampf(heat_level, 0.0, 1.0)

	_update_glow_effects(data)
	_update_spark_effects(data)

	# Check for warning state changes
	if old_heat < HEAT_HIGH and data.heat_level >= HEAT_HIGH:
		heat_warning_started.emit(factory_id)
	elif old_heat >= HEAT_HIGH and data.heat_level < HEAT_HIGH:
		heat_warning_ended.emit(factory_id)


## Update each frame.
func update(delta: float) -> void:
	for factory_id in _factory_effects:
		var data: EffectData = _factory_effects[factory_id]

		# Pulse effect for high heat
		if data.heat_level >= HEAT_HIGH:
			_update_pulse_effect(data, delta)


## Create heat glow light.
func _create_heat_glow_light(parent: Node3D) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "OverclockHeatGlow"
	light.light_color = Color(1.0, 0.6, 0.2)  # Orange
	light.light_energy = 0.0  # Start invisible
	light.omni_range = 15.0
	light.shadow_enabled = false  # Performance
	light.position = Vector3(0, 3, 0)

	parent.add_child(light)
	return light


## Create spark particle system.
func _create_spark_particles(parent: Node3D) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "OverclockSparks"
	particles.amount = 30
	particles.lifetime = 1.0
	particles.emitting = false
	particles.one_shot = false
	particles.position = Vector3(0, 2, 0)

	# Process material
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 60.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 8.0
	material.gravity = Vector3(0, -5, 0)
	material.scale_min = 0.05
	material.scale_max = 0.15
	material.color = Color(1.0, 0.7, 0.3)

	# Color gradient (yellow -> orange -> red)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 0.3))  # Yellow
	gradient.set_color(1, Color(1.0, 0.3, 0.1))  # Red
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material

	# Spark mesh (small sphere)
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	particles.draw_pass_1 = mesh

	parent.add_child(particles)
	return particles


## Update glow light based on heat.
func _update_glow_effects(data: EffectData) -> void:
	if data.glow_light == null or not is_instance_valid(data.glow_light):
		return

	if data.heat_level < HEAT_LOW:
		# No glow at low heat
		data.glow_light.light_energy = 0.0
	elif data.heat_level < HEAT_MEDIUM:
		# Low glow (yellow-orange)
		var t := (data.heat_level - HEAT_LOW) / (HEAT_MEDIUM - HEAT_LOW)
		data.glow_light.light_energy = lerpf(0.0, 1.0, t)
		data.glow_light.light_color = Color(1.0, 0.7, 0.3)  # Yellow-orange
	elif data.heat_level < HEAT_HIGH:
		# Medium glow (orange)
		var t := (data.heat_level - HEAT_MEDIUM) / (HEAT_HIGH - HEAT_MEDIUM)
		data.glow_light.light_energy = lerpf(1.0, 2.0, t)
		data.glow_light.light_color = Color(1.0, 0.5, 0.2)  # Orange
	else:
		# High glow (red-orange, pulsing handled separately)
		data.glow_light.light_energy = 2.5
		data.glow_light.light_color = Color(1.0, 0.3, 0.1)  # Red-orange


## Update spark particles based on heat.
func _update_spark_effects(data: EffectData) -> void:
	if data.spark_particles == null or not is_instance_valid(data.spark_particles):
		return

	if data.heat_level < HEAT_MEDIUM:
		# No sparks below medium heat
		data.spark_particles.emitting = false
	elif data.heat_level < HEAT_HIGH:
		# Occasional sparks
		data.spark_particles.emitting = true
		data.spark_particles.amount = 15
		data.spark_particles.amount_ratio = 0.5
	else:
		# Heavy sparks
		data.spark_particles.emitting = true
		data.spark_particles.amount = 30
		data.spark_particles.amount_ratio = 1.0


## Update pulse effect for high heat warning.
func _update_pulse_effect(data: EffectData, delta: float) -> void:
	if data.glow_light == null or not is_instance_valid(data.glow_light):
		return

	# Pulse the light energy
	data.pulse_timer += delta * 4.0  # Fast pulse
	var pulse := 0.5 + 0.5 * sin(data.pulse_timer)
	data.glow_light.light_energy = lerpf(2.0, 3.5, pulse)


## Clean up effects for a factory.
func _cleanup_effects(data: EffectData) -> void:
	if data.glow_light != null and is_instance_valid(data.glow_light):
		data.glow_light.queue_free()

	if data.spark_particles != null and is_instance_valid(data.spark_particles):
		data.spark_particles.emitting = false
		data.spark_particles.queue_free()


## Cleanup all effects.
func cleanup() -> void:
	for factory_id in _factory_effects.keys():
		unregister_factory(factory_id)
	_factory_effects.clear()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var factories: Array = []
	for factory_id in _factory_effects:
		var data: EffectData = _factory_effects[factory_id]
		factories.append({
			"factory_id": factory_id,
			"heat_level": data.heat_level,
			"is_warning": data.heat_level >= HEAT_HIGH
		})

	return {
		"factory_count": _factory_effects.size(),
		"factories": factories
	}


## Effect data for a factory.
class EffectData:
	var factory_id: int = -1
	var factory_node: Node3D = null
	var heat_level: float = 0.0
	var glow_light: OmniLight3D = null
	var spark_particles: GPUParticles3D = null
	var pulse_timer: float = 0.0
