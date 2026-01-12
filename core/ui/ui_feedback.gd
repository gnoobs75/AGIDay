class_name UIFeedback
extends RefCounted
## UIFeedback provides visual feedback for button interactions and UI states.

signal feedback_triggered(control: Control, feedback_type: String)

## Animation timing
const BUTTON_TRANSITION := 0.1       ## Button state transition time
const TOOLTIP_TRANSITION := 0.2      ## Tooltip fade time
const PANEL_TRANSITION := 0.3        ## Panel show/hide time
const PERF_TRANSITION := 0.0         ## Performance mode (instant)

## Hover effects
const HOVER_GLOW_INTENSITY := 0.15   ## Glow strength on hover
const HOVER_SCALE := 1.02            ## Scale factor on hover

## Pressed effects
const PRESSED_SCALE := 0.98          ## Scale factor when pressed
const PRESSED_DARKEN := 0.1          ## Darken amount when pressed

## Disabled styling
const DISABLED_OPACITY := 0.5        ## Opacity for disabled controls
const DISABLED_SATURATION := 0.3     ## Saturation for disabled controls

## State
var _performance_mode := false
var _registered_controls: Dictionary = {}  ## control_id -> {tweens, original_values}
var _faction_color := Color.CYAN


func _init() -> void:
	pass


## Register a button for feedback.
func register_button(button: Button) -> void:
	if button == null:
		return

	var control_id := button.get_instance_id()
	_registered_controls[control_id] = {
		"original_scale": button.scale,
		"original_modulate": button.modulate,
		"active_tweens": []
	}

	# Connect signals
	button.mouse_entered.connect(func(): _on_button_hover_start(button))
	button.mouse_exited.connect(func(): _on_button_hover_end(button))
	button.button_down.connect(func(): _on_button_pressed(button))
	button.button_up.connect(func(): _on_button_released(button))


## Unregister a button.
func unregister_button(button: Button) -> void:
	if button == null:
		return

	var control_id := button.get_instance_id()
	if _registered_controls.has(control_id):
		_cancel_tweens(control_id)
		_registered_controls.erase(control_id)


## Handle button hover start.
func _on_button_hover_start(button: Button) -> void:
	if button.disabled:
		return

	var control_id := button.get_instance_id()
	_cancel_tweens(control_id)

	var transition := PERF_TRANSITION if _performance_mode else BUTTON_TRANSITION

	if transition > 0:
		var tween := button.create_tween()
		tween.set_parallel(true)

		# Scale up slightly
		tween.tween_property(button, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), transition)

		# Add glow effect (brighten)
		var glow_color := Color(1.0 + HOVER_GLOW_INTENSITY, 1.0 + HOVER_GLOW_INTENSITY, 1.0 + HOVER_GLOW_INTENSITY)
		tween.tween_property(button, "modulate", glow_color, transition)

		_track_tween(control_id, tween)
	else:
		button.scale = Vector2(HOVER_SCALE, HOVER_SCALE)
		button.modulate = Color(1.0 + HOVER_GLOW_INTENSITY, 1.0 + HOVER_GLOW_INTENSITY, 1.0 + HOVER_GLOW_INTENSITY)

	feedback_triggered.emit(button, "hover_start")


## Handle button hover end.
func _on_button_hover_end(button: Button) -> void:
	var control_id := button.get_instance_id()
	if not _registered_controls.has(control_id):
		return

	_cancel_tweens(control_id)

	var original := _registered_controls[control_id]
	var transition := PERF_TRANSITION if _performance_mode else BUTTON_TRANSITION

	if transition > 0:
		var tween := button.create_tween()
		tween.set_parallel(true)
		tween.tween_property(button, "scale", original["original_scale"], transition)
		tween.tween_property(button, "modulate", original["original_modulate"], transition)
		_track_tween(control_id, tween)
	else:
		button.scale = original["original_scale"]
		button.modulate = original["original_modulate"]

	feedback_triggered.emit(button, "hover_end")


## Handle button pressed.
func _on_button_pressed(button: Button) -> void:
	if button.disabled:
		return

	var control_id := button.get_instance_id()
	_cancel_tweens(control_id)

	var transition := PERF_TRANSITION if _performance_mode else BUTTON_TRANSITION / 2

	if transition > 0:
		var tween := button.create_tween()
		tween.set_parallel(true)

		# Scale down (depression effect)
		tween.tween_property(button, "scale", Vector2(PRESSED_SCALE, PRESSED_SCALE), transition)

		# Darken slightly
		var dark_color := Color(1.0 - PRESSED_DARKEN, 1.0 - PRESSED_DARKEN, 1.0 - PRESSED_DARKEN)
		tween.tween_property(button, "modulate", dark_color, transition)

		_track_tween(control_id, tween)
	else:
		button.scale = Vector2(PRESSED_SCALE, PRESSED_SCALE)
		button.modulate = Color(1.0 - PRESSED_DARKEN, 1.0 - PRESSED_DARKEN, 1.0 - PRESSED_DARKEN)

	feedback_triggered.emit(button, "pressed")


## Handle button released.
func _on_button_released(button: Button) -> void:
	var control_id := button.get_instance_id()
	if not _registered_controls.has(control_id):
		return

	_cancel_tweens(control_id)

	# Return to hover state if still hovering, otherwise to original
	var target_scale := Vector2(HOVER_SCALE, HOVER_SCALE) if button.is_hovered() else _registered_controls[control_id]["original_scale"]
	var target_modulate := Color(1.0 + HOVER_GLOW_INTENSITY, 1.0 + HOVER_GLOW_INTENSITY, 1.0 + HOVER_GLOW_INTENSITY) if button.is_hovered() else _registered_controls[control_id]["original_modulate"]

	var transition := PERF_TRANSITION if _performance_mode else BUTTON_TRANSITION

	if transition > 0:
		var tween := button.create_tween()
		tween.set_parallel(true)
		tween.tween_property(button, "scale", target_scale, transition)
		tween.tween_property(button, "modulate", target_modulate, transition)
		_track_tween(control_id, tween)
	else:
		button.scale = target_scale
		button.modulate = target_modulate

	feedback_triggered.emit(button, "released")


## Apply disabled styling to a control.
func apply_disabled_style(control: Control, disabled: bool) -> void:
	var transition := PERF_TRANSITION if _performance_mode else BUTTON_TRANSITION

	if disabled:
		var disabled_color := Color(DISABLED_SATURATION, DISABLED_SATURATION, DISABLED_SATURATION, DISABLED_OPACITY)
		if transition > 0:
			var tween := control.create_tween()
			tween.tween_property(control, "modulate", disabled_color, transition)
		else:
			control.modulate = disabled_color
	else:
		if transition > 0:
			var tween := control.create_tween()
			tween.tween_property(control, "modulate", Color.WHITE, transition)
		else:
			control.modulate = Color.WHITE


## Apply click feedback (for any control).
func apply_click_feedback(control: Control) -> void:
	var transition := PERF_TRANSITION if _performance_mode else BUTTON_TRANSITION

	if transition > 0:
		var tween := control.create_tween()
		tween.tween_property(control, "scale", Vector2(0.95, 0.95), transition / 2)
		tween.tween_property(control, "scale", Vector2(1.0, 1.0), transition)
	else:
		# Instant flash
		control.modulate = Color(1.3, 1.3, 1.3)
		await control.get_tree().process_frame
		control.modulate = Color.WHITE


## Apply success feedback.
func apply_success_feedback(control: Control) -> void:
	var transition := BUTTON_TRANSITION * 2

	var tween := control.create_tween()
	tween.tween_property(control, "modulate", Color.GREEN, transition / 2)
	tween.tween_property(control, "modulate", Color.WHITE, transition)


## Apply error feedback.
func apply_error_feedback(control: Control) -> void:
	var transition := BUTTON_TRANSITION * 2

	var tween := control.create_tween()
	# Shake effect
	var original_pos := control.position
	tween.tween_property(control, "position", original_pos + Vector2(5, 0), 0.05)
	tween.tween_property(control, "position", original_pos - Vector2(5, 0), 0.05)
	tween.tween_property(control, "position", original_pos + Vector2(3, 0), 0.05)
	tween.tween_property(control, "position", original_pos, 0.05)

	# Red flash
	tween.parallel().tween_property(control, "modulate", Color.RED, transition / 2)
	tween.tween_property(control, "modulate", Color.WHITE, transition)


## Apply panel show animation.
func show_panel(panel: Control, from_direction: String = "fade") -> void:
	var transition := PERF_TRANSITION if _performance_mode else PANEL_TRANSITION

	panel.visible = true

	if transition <= 0:
		panel.modulate.a = 1.0
		panel.scale = Vector2.ONE
		return

	var tween := panel.create_tween()

	match from_direction:
		"fade":
			panel.modulate.a = 0.0
			tween.tween_property(panel, "modulate:a", 1.0, transition)
		"scale":
			panel.modulate.a = 0.0
			panel.scale = Vector2(0.8, 0.8)
			tween.set_parallel(true)
			tween.tween_property(panel, "modulate:a", 1.0, transition)
			tween.tween_property(panel, "scale", Vector2.ONE, transition).set_trans(Tween.TRANS_BACK)
		"slide_down":
			var target_pos := panel.position
			panel.position.y -= 50
			panel.modulate.a = 0.0
			tween.set_parallel(true)
			tween.tween_property(panel, "position:y", target_pos.y, transition)
			tween.tween_property(panel, "modulate:a", 1.0, transition)
		"slide_up":
			var target_pos := panel.position
			panel.position.y += 50
			panel.modulate.a = 0.0
			tween.set_parallel(true)
			tween.tween_property(panel, "position:y", target_pos.y, transition)
			tween.tween_property(panel, "modulate:a", 1.0, transition)


## Apply panel hide animation.
func hide_panel(panel: Control, to_direction: String = "fade") -> void:
	var transition := PERF_TRANSITION if _performance_mode else PANEL_TRANSITION

	if transition <= 0:
		panel.visible = false
		return

	var tween := panel.create_tween()

	match to_direction:
		"fade":
			tween.tween_property(panel, "modulate:a", 0.0, transition)
		"scale":
			tween.set_parallel(true)
			tween.tween_property(panel, "modulate:a", 0.0, transition)
			tween.tween_property(panel, "scale", Vector2(0.8, 0.8), transition)
		_:
			tween.tween_property(panel, "modulate:a", 0.0, transition)

	tween.tween_callback(func(): panel.visible = false)


## Track a tween for later cancellation.
func _track_tween(control_id: int, tween: Tween) -> void:
	if _registered_controls.has(control_id):
		_registered_controls[control_id]["active_tweens"].append(tween)


## Cancel all active tweens for a control.
func _cancel_tweens(control_id: int) -> void:
	if not _registered_controls.has(control_id):
		return

	var data: Dictionary = _registered_controls[control_id]
	for tween in data["active_tweens"]:
		if tween != null and tween.is_valid():
			tween.kill()
	data["active_tweens"].clear()


## Set performance mode.
func set_performance_mode(enabled: bool) -> void:
	_performance_mode = enabled


## Set faction color for themed effects.
func set_faction_color(color: Color) -> void:
	_faction_color = color


## Cleanup.
func cleanup() -> void:
	for control_id in _registered_controls:
		_cancel_tweens(control_id)
	_registered_controls.clear()
