class_name UnitEjectionAnimation
extends RefCounted
## UnitEjectionAnimation handles the visual animation of units emerging from factories.
## Provides faction-specific ejection styles with particles and sound cues.

signal ejection_started(ejection_id: int, factory_id: int)
signal ejection_progress(ejection_id: int, progress: float)
signal ejection_completed(ejection_id: int, unit_node: Node3D)

## Ejection style per faction
enum EjectionStyle {
	SWARM_BURST,       ## Aether Swarm: Quick burst with particle cloud
	FORGE_STAMP,       ## OptiForge: Industrial stamp-down motion
	QUAD_LEAP,         ## Dynapods: Leaping out with acrobatic flair
	SIEGE_DEPLOY,      ## LogiBots: Heavy mechanical deployment
	GUERRILLA_DROP     ## Human Remnant: Rappelling/drop-in effect
}

## Ejection configuration
const DEFAULT_DURATION := 0.8
const GATE_OPEN_DURATION := 0.3
const GATE_CLOSE_DURATION := 0.2

## Active ejections
var _active_ejections: Dictionary = {}  ## ejection_id -> EjectionData
var _next_ejection_id: int = 1

## Particle pool (EjectionParticles instance)
var _ejection_particles: RefCounted = null

## Scene tree for tweens
var _scene_tree: SceneTree = null


func _init() -> void:
	# Load EjectionParticles dynamically to avoid circular dependency
	var ejection_particles_script := load("res://core/factory/ejection_particles.gd")
	if ejection_particles_script != null:
		_ejection_particles = ejection_particles_script.new()


## Initialize with scene tree.
func initialize(scene_tree: SceneTree) -> void:
	_scene_tree = scene_tree


## Start ejection animation for a unit.
func start_ejection(
	unit_node: Node3D,
	factory_position: Vector3,
	target_position: Vector3,
	faction_id: int,
	factory_node: Node3D = null
) -> int:
	if unit_node == null:
		return -1

	var ejection_id := _next_ejection_id
	_next_ejection_id += 1

	var data := EjectionData.new()
	data.ejection_id = ejection_id
	data.unit_node = unit_node
	data.factory_position = factory_position
	data.target_position = target_position
	data.faction_id = faction_id
	data.factory_node = factory_node
	data.style = _get_faction_style(faction_id)
	data.duration = _get_style_duration(data.style)

	# Store original transform
	data.original_scale = unit_node.scale

	# Initialize unit at factory exit position
	var exit_position := _get_exit_position(factory_position, target_position, data.style)
	data.exit_position = exit_position

	# Set initial state based on style
	_setup_initial_state(data)

	_active_ejections[ejection_id] = data

	# Set up particles
	if factory_node != null:
		_ejection_particles.set_parent(factory_node)

	# Start the ejection animation
	_start_ejection_animation(data)

	ejection_started.emit(ejection_id, faction_id)

	return ejection_id


## Get faction-specific ejection style.
func _get_faction_style(faction_id: int) -> EjectionStyle:
	match faction_id:
		1: return EjectionStyle.SWARM_BURST      # Aether Swarm
		2: return EjectionStyle.FORGE_STAMP      # OptiForge Legion
		3: return EjectionStyle.QUAD_LEAP        # Dynapods Vanguard
		4: return EjectionStyle.SIEGE_DEPLOY     # LogiBots Colossus
		5: return EjectionStyle.GUERRILLA_DROP   # Human Remnant
		_: return EjectionStyle.FORGE_STAMP      # Default


## Get duration based on style.
func _get_style_duration(style: EjectionStyle) -> float:
	match style:
		EjectionStyle.SWARM_BURST: return 0.5    # Quick burst
		EjectionStyle.FORGE_STAMP: return 0.7    # Industrial timing
		EjectionStyle.QUAD_LEAP: return 0.9      # Acrobatic leap
		EjectionStyle.SIEGE_DEPLOY: return 1.2   # Heavy deployment
		EjectionStyle.GUERRILLA_DROP: return 0.6 # Fast drop
		_: return DEFAULT_DURATION


## Calculate exit position based on factory and target.
func _get_exit_position(factory_pos: Vector3, target_pos: Vector3, style: EjectionStyle) -> Vector3:
	var direction := (target_pos - factory_pos).normalized()
	if direction.length_squared() < 0.01:
		direction = Vector3.FORWARD

	var exit_offset := 3.0  # Distance from factory center to exit
	match style:
		EjectionStyle.SIEGE_DEPLOY:
			exit_offset = 5.0  # Larger units need more space
		EjectionStyle.SWARM_BURST:
			exit_offset = 2.0  # Smaller units exit closer

	return factory_pos + direction * exit_offset


## Set up initial state for the unit before animation.
func _setup_initial_state(data: EjectionData) -> void:
	if data.unit_node == null:
		return

	match data.style:
		EjectionStyle.SWARM_BURST:
			# Start small and at factory center
			data.unit_node.scale = data.original_scale * 0.1
			data.unit_node.position = data.factory_position + Vector3(0, 1, 0)
			data.unit_node.visible = true

		EjectionStyle.FORGE_STAMP:
			# Start above, will stamp down
			data.unit_node.position = data.factory_position + Vector3(0, 8, 0)
			data.unit_node.scale = data.original_scale
			data.unit_node.visible = true

		EjectionStyle.QUAD_LEAP:
			# Start crouched at exit
			data.unit_node.position = data.exit_position
			data.unit_node.scale = data.original_scale * Vector3(1.2, 0.5, 1.2)  # Compressed
			data.unit_node.visible = true

		EjectionStyle.SIEGE_DEPLOY:
			# Start underground, will rise up
			data.unit_node.position = data.exit_position + Vector3(0, -3, 0)
			data.unit_node.scale = data.original_scale
			data.unit_node.visible = true

		EjectionStyle.GUERRILLA_DROP:
			# Start high above, will drop
			data.unit_node.position = data.target_position + Vector3(0, 15, 0)
			data.unit_node.scale = data.original_scale
			data.unit_node.visible = true


## Start the ejection animation using tweens.
func _start_ejection_animation(data: EjectionData) -> void:
	if data.unit_node == null or not is_instance_valid(data.unit_node):
		return

	# Create tween
	var tween: Tween = null
	if data.unit_node.is_inside_tree():
		tween = data.unit_node.create_tween()
	elif _scene_tree != null:
		tween = _scene_tree.create_tween()
	else:
		# No tween available, skip to end
		_complete_ejection(data)
		return

	if tween == null:
		_complete_ejection(data)
		return

	data.tween = tween

	# Configure based on style
	match data.style:
		EjectionStyle.SWARM_BURST:
			_animate_swarm_burst(data, tween)
		EjectionStyle.FORGE_STAMP:
			_animate_forge_stamp(data, tween)
		EjectionStyle.QUAD_LEAP:
			_animate_quad_leap(data, tween)
		EjectionStyle.SIEGE_DEPLOY:
			_animate_siege_deploy(data, tween)
		EjectionStyle.GUERRILLA_DROP:
			_animate_guerrilla_drop(data, tween)

	# Completion callback
	tween.tween_callback(_on_ejection_complete.bind(data.ejection_id))


## Animate Aether Swarm burst ejection.
func _animate_swarm_burst(data: EjectionData, tween: Tween) -> void:
	var duration := data.duration

	# Spawn particle burst at start
	_ejection_particles.spawn_swarm_burst(data.factory_position + Vector3(0, 1, 0))

	# Scale up while moving outward
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	# Move in an arc
	var mid_point := data.factory_position.lerp(data.target_position, 0.5) + Vector3(0, 3, 0)

	tween.tween_property(data.unit_node, "position", mid_point, duration * 0.4)
	tween.parallel().tween_property(data.unit_node, "scale", data.original_scale * 0.7, duration * 0.4)

	tween.tween_property(data.unit_node, "position", data.target_position, duration * 0.6)
	tween.parallel().tween_property(data.unit_node, "scale", data.original_scale, duration * 0.6)

	# Trail particles during movement
	tween.parallel().tween_callback(_ejection_particles.spawn_swarm_trail.bind(data.unit_node))


## Animate OptiForge stamp ejection.
func _animate_forge_stamp(data: EjectionData, tween: Tween) -> void:
	var duration := data.duration
	var start_pos := data.factory_position + Vector3(0, 8, 0)
	var land_pos := data.exit_position
	var final_pos := data.target_position

	# Hover briefly
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_interval(duration * 0.1)

	# Stamp down fast
	tween.set_trans(Tween.TRANS_EXPO)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(data.unit_node, "position", land_pos, duration * 0.3)

	# Impact callback
	tween.tween_callback(_spawn_impact_effect.bind(land_pos, data.faction_id))

	# Brief compression on landing
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(data.unit_node, "scale", data.original_scale * Vector3(1.2, 0.8, 1.2), duration * 0.15)

	# Recover and walk to position
	tween.tween_property(data.unit_node, "scale", data.original_scale, duration * 0.15)

	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(data.unit_node, "position", final_pos, duration * 0.3)


## Animate Dynapods leap ejection.
func _animate_quad_leap(data: EjectionData, tween: Tween) -> void:
	var duration := data.duration
	var start_pos := data.exit_position
	var apex_pos := start_pos.lerp(data.target_position, 0.5) + Vector3(0, 6, 0)  # High arc
	var final_pos := data.target_position

	# Coil up (scale compression animation)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(data.unit_node, "scale", data.original_scale * Vector3(1.3, 0.4, 1.3), duration * 0.15)

	# Launch particles
	tween.tween_callback(_ejection_particles.spawn_leap_launch.bind(start_pos))

	# Leap to apex
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(data.unit_node, "position", apex_pos, duration * 0.35)
	tween.parallel().tween_property(data.unit_node, "scale", data.original_scale * Vector3(0.9, 1.2, 0.9), duration * 0.35)

	# Add spin during apex
	var spin_rotation := data.unit_node.rotation + Vector3(0, TAU * 1.5, 0)  # 1.5 full rotations
	tween.parallel().tween_property(data.unit_node, "rotation", spin_rotation, duration * 0.7)

	# Descend to landing
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(data.unit_node, "position", final_pos, duration * 0.35)
	tween.parallel().tween_property(data.unit_node, "scale", data.original_scale, duration * 0.35)

	# Landing impact
	tween.tween_callback(_spawn_landing_dust.bind(final_pos, data.faction_id))

	# Ground settle
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(data.unit_node, "scale", data.original_scale * Vector3(1.1, 0.95, 1.1), duration * 0.1)
	tween.tween_property(data.unit_node, "scale", data.original_scale, duration * 0.05)


## Animate LogiBots siege deployment.
func _animate_siege_deploy(data: EjectionData, tween: Tween) -> void:
	var duration := data.duration
	var underground_pos := data.exit_position + Vector3(0, -3, 0)
	var surface_pos := data.exit_position
	var final_pos := data.target_position

	# Ground shake/rumble effect
	tween.tween_callback(_ejection_particles.spawn_ground_crack.bind(surface_pos))

	# Rise from underground slowly
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(data.unit_node, "position", surface_pos, duration * 0.5)

	# Steam/smoke vents as it emerges
	tween.parallel().tween_callback(_ejection_particles.spawn_steam_vent.bind(surface_pos))

	# Brief pause at surface
	tween.tween_interval(duration * 0.1)

	# Heavy footsteps to final position
	var mid_pos := surface_pos.lerp(final_pos, 0.5)

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(data.unit_node, "position", mid_pos, duration * 0.2)
	tween.tween_callback(_spawn_footstep_dust.bind(mid_pos))

	tween.tween_property(data.unit_node, "position", final_pos, duration * 0.2)
	tween.tween_callback(_spawn_footstep_dust.bind(final_pos))


## Animate Human Remnant guerrilla drop.
func _animate_guerrilla_drop(data: EjectionData, tween: Tween) -> void:
	var duration := data.duration
	var sky_pos := data.target_position + Vector3(0, 15, 0)
	var rappel_pos := data.target_position + Vector3(0, 5, 0)
	var final_pos := data.target_position

	# Fast drop from sky
	tween.set_trans(Tween.TRANS_EXPO)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(data.unit_node, "position", rappel_pos, duration * 0.4)

	# Spawn rappel/parachute trail
	tween.parallel().tween_callback(_ejection_particles.spawn_rappel_line.bind(sky_pos, rappel_pos))

	# Controlled descent
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(data.unit_node, "position", final_pos, duration * 0.4)

	# Landing crouch
	tween.tween_property(data.unit_node, "scale", data.original_scale * Vector3(1.1, 0.85, 1.1), duration * 0.1)
	tween.tween_callback(_spawn_landing_dust.bind(final_pos, data.faction_id))

	# Stand up
	tween.tween_property(data.unit_node, "scale", data.original_scale, duration * 0.1)


## Spawn impact effect.
func _spawn_impact_effect(position: Vector3, faction_id: int) -> void:
	_ejection_particles.spawn_impact(position, faction_id)


## Spawn landing dust.
func _spawn_landing_dust(position: Vector3, faction_id: int) -> void:
	_ejection_particles.spawn_dust_cloud(position, faction_id)


## Spawn footstep dust for heavy units.
func _spawn_footstep_dust(position: Vector3) -> void:
	_ejection_particles.spawn_footstep(position)


## Handle ejection completion.
func _on_ejection_complete(ejection_id: int) -> void:
	if not _active_ejections.has(ejection_id):
		return

	var data: EjectionData = _active_ejections[ejection_id]
	_complete_ejection(data)


## Complete an ejection.
func _complete_ejection(data: EjectionData) -> void:
	# Ensure final state
	if data.unit_node != null and is_instance_valid(data.unit_node):
		data.unit_node.position = data.target_position
		data.unit_node.scale = data.original_scale

	data.is_complete = true

	ejection_completed.emit(data.ejection_id, data.unit_node)

	# Cleanup
	_active_ejections.erase(data.ejection_id)


## Cancel an active ejection.
func cancel_ejection(ejection_id: int) -> void:
	if not _active_ejections.has(ejection_id):
		return

	var data: EjectionData = _active_ejections[ejection_id]

	if data.tween != null and data.tween.is_valid():
		data.tween.kill()

	# Reset to target position
	if data.unit_node != null and is_instance_valid(data.unit_node):
		data.unit_node.position = data.target_position
		data.unit_node.scale = data.original_scale

	_active_ejections.erase(ejection_id)


## Update each frame.
func update(delta: float) -> void:
	_ejection_particles.update(delta)

	# Update progress for active ejections
	for ejection_id in _active_ejections:
		var data: EjectionData = _active_ejections[ejection_id]
		data.elapsed_time += delta
		var progress := minf(data.elapsed_time / data.duration, 1.0)
		ejection_progress.emit(ejection_id, progress)


## Check if any ejections are active.
func has_active_ejections() -> bool:
	return not _active_ejections.is_empty()


## Get active ejection count.
func get_active_count() -> int:
	return _active_ejections.size()


## Cleanup all ejections.
func cleanup() -> void:
	for ejection_id in _active_ejections.keys():
		cancel_ejection(ejection_id)

	_ejection_particles.cleanup()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var active_styles: Dictionary = {}
	for ejection_id in _active_ejections:
		var data: EjectionData = _active_ejections[ejection_id]
		var style_name: String = EjectionStyle.keys()[data.style]
		active_styles[style_name] = active_styles.get(style_name, 0) + 1

	var particles_summary: Dictionary = {}
	if _ejection_particles != null:
		particles_summary = _ejection_particles.get_summary()

	return {
		"active_count": _active_ejections.size(),
		"styles": active_styles,
		"particles": particles_summary
	}


## Ejection data class.
class EjectionData:
	var ejection_id: int = -1
	var unit_node: Node3D = null
	var factory_node: Node3D = null
	var factory_position: Vector3 = Vector3.ZERO
	var exit_position: Vector3 = Vector3.ZERO
	var target_position: Vector3 = Vector3.ZERO
	var faction_id: int = 0
	var style: EjectionStyle = EjectionStyle.FORGE_STAMP
	var duration: float = 0.8
	var elapsed_time: float = 0.0
	var original_scale: Vector3 = Vector3.ONE
	var tween: Tween = null
	var is_complete: bool = false
