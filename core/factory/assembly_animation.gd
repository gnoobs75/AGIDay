class_name AssemblyAnimation
extends RefCounted
## AssemblyAnimation controls smooth part movement and positioning during assembly.

signal animation_started(part_index: int)
signal animation_progress(part_index: int, progress: float)
signal animation_completed(part_index: int)
signal all_animations_complete()

## Animation configuration
const DEFAULT_DURATION := 0.5
const DEFAULT_DELAY := 0.1

## Easing types
enum EaseType {
	LINEAR,
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT,
	BOUNCE,
	ELASTIC
}

## Animation state
var _animations: Dictionary = {}  ## part_index -> AnimationData
var _completed_count: int = 0
var _total_count: int = 0

## Scene tree reference for tweens
var _scene_tree: SceneTree = null

## Animation data class
class AnimationData:
	var part_index: int = -1
	var node: Node3D = null
	var start_position: Vector3 = Vector3.ZERO
	var end_position: Vector3 = Vector3.ZERO
	var start_rotation: Quaternion = Quaternion.IDENTITY
	var end_rotation: Quaternion = Quaternion.IDENTITY
	var start_scale: Vector3 = Vector3.ONE
	var end_scale: Vector3 = Vector3.ONE
	var duration: float = 0.5
	var delay: float = 0.0
	var ease_type: EaseType = EaseType.EASE_OUT
	var tween: Tween = null
	var is_complete: bool = false
	var progress: float = 0.0


func _init() -> void:
	pass


## Set scene tree reference (needed for creating tweens).
func set_scene_tree(tree: SceneTree) -> void:
	_scene_tree = tree


## Add animation for a part.
func add_animation(
	part_index: int,
	node: Node3D,
	start_pos: Vector3,
	end_pos: Vector3,
	start_rot: Quaternion = Quaternion.IDENTITY,
	end_rot: Quaternion = Quaternion.IDENTITY,
	duration: float = DEFAULT_DURATION,
	delay: float = 0.0,
	ease_type: EaseType = EaseType.EASE_OUT
) -> void:
	var anim := AnimationData.new()
	anim.part_index = part_index
	anim.node = node
	anim.start_position = start_pos
	anim.end_position = end_pos
	anim.start_rotation = start_rot
	anim.end_rotation = end_rot
	anim.start_scale = node.scale if node != null else Vector3.ONE
	anim.end_scale = anim.start_scale
	anim.duration = duration
	anim.delay = delay
	anim.ease_type = ease_type

	_animations[part_index] = anim
	_total_count += 1


## Add animation with scale change.
func add_animation_with_scale(
	part_index: int,
	node: Node3D,
	start_pos: Vector3,
	end_pos: Vector3,
	start_scale: Vector3,
	end_scale: Vector3,
	duration: float = DEFAULT_DURATION
) -> void:
	var anim := AnimationData.new()
	anim.part_index = part_index
	anim.node = node
	anim.start_position = start_pos
	anim.end_position = end_pos
	anim.start_scale = start_scale
	anim.end_scale = end_scale
	anim.duration = duration

	_animations[part_index] = anim
	_total_count += 1


## Start a specific animation.
func start_animation(part_index: int) -> bool:
	if not _animations.has(part_index):
		return false

	var anim: AnimationData = _animations[part_index]
	if anim.node == null or not is_instance_valid(anim.node):
		return false

	animation_started.emit(part_index)

	# Set initial state
	anim.node.position = anim.start_position
	anim.node.quaternion = anim.start_rotation
	anim.node.scale = anim.start_scale

	# Create tween
	if anim.node.is_inside_tree():
		anim.tween = anim.node.create_tween()
	elif _scene_tree != null:
		anim.tween = _scene_tree.create_tween()
	else:
		# Fallback: set final state immediately
		anim.node.position = anim.end_position
		anim.node.quaternion = anim.end_rotation
		anim.node.scale = anim.end_scale
		_on_animation_complete(part_index)
		return true

	if anim.tween == null:
		return false

	# Configure easing
	_configure_tween_easing(anim.tween, anim.ease_type)

	# Add delay if specified
	if anim.delay > 0:
		anim.tween.tween_interval(anim.delay)

	# Animate position
	anim.tween.tween_property(anim.node, "position", anim.end_position, anim.duration)

	# Animate rotation in parallel
	anim.tween.parallel().tween_property(anim.node, "quaternion", anim.end_rotation, anim.duration)

	# Animate scale in parallel if changed
	if anim.start_scale != anim.end_scale:
		anim.tween.parallel().tween_property(anim.node, "scale", anim.end_scale, anim.duration)

	# Completion callback
	anim.tween.tween_callback(_on_animation_complete.bind(part_index))

	return true


## Start all animations sequentially with delays.
func start_all_sequential(base_delay: float = DEFAULT_DELAY) -> void:
	var sorted_indices: Array = _animations.keys()
	sorted_indices.sort()

	var accumulated_delay := 0.0
	for part_index in sorted_indices:
		var anim: AnimationData = _animations[part_index]
		anim.delay = accumulated_delay
		start_animation(part_index)
		accumulated_delay += anim.duration + base_delay


## Start all animations simultaneously.
func start_all_parallel() -> void:
	for part_index in _animations:
		start_animation(part_index)


## Configure tween easing based on type.
func _configure_tween_easing(tween: Tween, ease_type: EaseType) -> void:
	match ease_type:
		EaseType.LINEAR:
			tween.set_trans(Tween.TRANS_LINEAR)
			tween.set_ease(Tween.EASE_IN_OUT)
		EaseType.EASE_IN:
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_ease(Tween.EASE_IN)
		EaseType.EASE_OUT:
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_ease(Tween.EASE_OUT)
		EaseType.EASE_IN_OUT:
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_ease(Tween.EASE_IN_OUT)
		EaseType.BOUNCE:
			tween.set_trans(Tween.TRANS_BOUNCE)
			tween.set_ease(Tween.EASE_OUT)
		EaseType.ELASTIC:
			tween.set_trans(Tween.TRANS_ELASTIC)
			tween.set_ease(Tween.EASE_OUT)


## Handle animation completion.
func _on_animation_complete(part_index: int) -> void:
	if _animations.has(part_index):
		var anim: AnimationData = _animations[part_index]
		anim.is_complete = true
		anim.progress = 1.0
		anim.tween = null

	_completed_count += 1
	animation_completed.emit(part_index)

	if _completed_count >= _total_count:
		all_animations_complete.emit()


## Cancel a specific animation.
func cancel_animation(part_index: int) -> void:
	if not _animations.has(part_index):
		return

	var anim: AnimationData = _animations[part_index]
	if anim.tween != null and anim.tween.is_valid():
		anim.tween.kill()
		anim.tween = null


## Cancel all animations.
func cancel_all() -> void:
	for part_index in _animations:
		cancel_animation(part_index)


## Skip to end state for all animations.
func skip_to_end() -> void:
	cancel_all()

	for part_index in _animations:
		var anim: AnimationData = _animations[part_index]
		if anim.node != null and is_instance_valid(anim.node):
			anim.node.position = anim.end_position
			anim.node.quaternion = anim.end_rotation
			anim.node.scale = anim.end_scale
		anim.is_complete = true
		anim.progress = 1.0

	_completed_count = _total_count


## Get animation progress (0.0 to 1.0).
func get_progress() -> float:
	if _total_count == 0:
		return 1.0
	return float(_completed_count) / float(_total_count)


## Check if all animations are complete.
func is_complete() -> bool:
	return _completed_count >= _total_count and _total_count > 0


## Check if any animation is active.
func is_animating() -> bool:
	for part_index in _animations:
		var anim: AnimationData = _animations[part_index]
		if anim.tween != null and anim.tween.is_valid() and anim.tween.is_running():
			return true
	return false


## Get count of active animations.
func get_active_count() -> int:
	var count := 0
	for part_index in _animations:
		var anim: AnimationData = _animations[part_index]
		if anim.tween != null and anim.tween.is_valid() and anim.tween.is_running():
			count += 1
	return count


## Clear all animations.
func clear() -> void:
	cancel_all()
	_animations.clear()
	_completed_count = 0
	_total_count = 0


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"total_count": _total_count,
		"completed_count": _completed_count,
		"active_count": get_active_count(),
		"progress": get_progress(),
		"is_complete": is_complete(),
		"is_animating": is_animating()
	}
