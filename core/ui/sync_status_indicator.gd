class_name SyncStatusIndicator
extends RefCounted
## SyncStatusIndicator displays cloud sync status in the UI.
## Shows online/offline state, sync progress, and error notifications.

signal status_clicked()

## Icons (placeholder paths)
const ICON_ONLINE := "res://assets/ui/icons/cloud_online.png"
const ICON_OFFLINE := "res://assets/ui/icons/cloud_offline.png"
const ICON_SYNCING := "res://assets/ui/icons/cloud_syncing.png"
const ICON_ERROR := "res://assets/ui/icons/cloud_error.png"
const ICON_CONFLICT := "res://assets/ui/icons/cloud_conflict.png"

## Colors
const COLOR_ONLINE := Color(0.2, 0.8, 0.2)      ## Green
const COLOR_OFFLINE := Color(0.5, 0.5, 0.5)     ## Gray
const COLOR_SYNCING := Color(0.2, 0.6, 1.0)     ## Blue
const COLOR_ERROR := Color(1.0, 0.3, 0.3)       ## Red
const COLOR_CONFLICT := Color(1.0, 0.8, 0.2)    ## Yellow

## Animation
const SPIN_SPEED := 2.0
const PULSE_SPEED := 1.5

## UI components
var _container: Control = null
var _icon: TextureRect = null
var _status_label: Label = null
var _progress_bar: ProgressBar = null
var _tooltip_label: Label = null

## State
var _current_status := "offline"
var _spin_angle := 0.0
var _pulse_alpha := 1.0
var _pulse_direction := -1.0


func _init() -> void:
	pass


## Create the indicator UI.
func create_ui(parent: Control) -> Control:
	_container = Control.new()
	_container.custom_minimum_size = Vector2(150, 32)
	_container.mouse_filter = Control.MOUSE_FILTER_STOP

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.3)
	_container.add_child(bg)

	# Icon
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(24, 24)
	_icon.position = Vector2(4, 4)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_container.add_child(_icon)

	# Status label
	_status_label = Label.new()
	_status_label.position = Vector2(32, 4)
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	_container.add_child(_status_label)

	# Progress bar (hidden by default)
	_progress_bar = ProgressBar.new()
	_progress_bar.position = Vector2(32, 20)
	_progress_bar.custom_minimum_size = Vector2(110, 8)
	_progress_bar.visible = false
	_progress_bar.show_percentage = false

	var progress_style := StyleBoxFlat.new()
	progress_style.bg_color = Color(0.2, 0.2, 0.2)
	_progress_bar.add_theme_stylebox_override("background", progress_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COLOR_SYNCING
	_progress_bar.add_theme_stylebox_override("fill", fill_style)

	_container.add_child(_progress_bar)

	# Click handler
	_container.gui_input.connect(_on_gui_input)

	parent.add_child(_container)
	return _container


## Update indicator (call each frame).
func update(delta: float, sync_status: Dictionary) -> void:
	var is_online: bool = sync_status.get("online", false)
	var is_syncing: bool = sync_status.get("syncing", false)
	var has_conflicts: bool = sync_status.get("has_conflicts", false)
	var last_success: bool = sync_status.get("last_sync_success", true)

	# Determine status
	var new_status := "offline"
	if has_conflicts:
		new_status = "conflict"
	elif is_syncing:
		new_status = "syncing"
	elif not last_success:
		new_status = "error"
	elif is_online:
		new_status = "online"

	_current_status = new_status
	_update_visuals(delta, sync_status)


## Update visual elements.
func _update_visuals(delta: float, sync_status: Dictionary) -> void:
	match _current_status:
		"online":
			_status_label.text = "Cloud: Online"
			_icon.modulate = COLOR_ONLINE
			_progress_bar.visible = false

		"offline":
			_status_label.text = "Cloud: Offline"
			_icon.modulate = COLOR_OFFLINE
			_progress_bar.visible = false

		"syncing":
			_status_label.text = "Syncing..."
			_icon.modulate = COLOR_SYNCING
			_progress_bar.visible = true

			# Animate spin
			_spin_angle += delta * SPIN_SPEED * TAU
			if _spin_angle > TAU:
				_spin_angle -= TAU
			_icon.rotation = _spin_angle

			# Update progress if available
			var progress: float = sync_status.get("sync_progress", 0.5)
			_progress_bar.value = progress * 100

		"error":
			_status_label.text = "Sync Error"
			_icon.modulate = COLOR_ERROR
			_progress_bar.visible = false

			# Pulse effect
			_pulse_alpha += _pulse_direction * delta * PULSE_SPEED
			if _pulse_alpha <= 0.5:
				_pulse_direction = 1.0
			elif _pulse_alpha >= 1.0:
				_pulse_direction = -1.0
			_icon.modulate.a = _pulse_alpha

		"conflict":
			_status_label.text = "Conflict!"
			_icon.modulate = COLOR_CONFLICT
			_progress_bar.visible = false

			# Pulse effect
			_pulse_alpha += _pulse_direction * delta * PULSE_SPEED * 2
			if _pulse_alpha <= 0.3:
				_pulse_direction = 1.0
			elif _pulse_alpha >= 1.0:
				_pulse_direction = -1.0
			_icon.modulate.a = _pulse_alpha

	# Reset rotation for non-syncing states
	if _current_status != "syncing":
		_icon.rotation = 0


## Handle click.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			status_clicked.emit()


## Show tooltip with detailed status.
func show_detailed_status(sync_status: Dictionary) -> String:
	var lines: Array[String] = []

	lines.append("Cloud Sync Status")
	lines.append("─────────────────")

	if sync_status.get("online", false):
		lines.append("● Connected to cloud")
	else:
		lines.append("○ Offline mode")

	if sync_status.get("syncing", false):
		lines.append("↻ Sync in progress...")
	else:
		var time_until: float = sync_status.get("time_until_sync", 0)
		if time_until > 0:
			lines.append("Next sync: %d:%02d" % [int(time_until) / 60, int(time_until) % 60])

	var pending: int = sync_status.get("pending_operations", 0)
	if pending > 0:
		lines.append("Pending: %d operations" % pending)

	if sync_status.get("has_conflicts", false):
		lines.append("⚠ Conflicts require resolution")

	if not sync_status.get("last_sync_success", true):
		lines.append("✗ Last sync failed")

	return "\n".join(lines)


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Get current status.
func get_status() -> String:
	return _current_status


## Is showing error or conflict.
func needs_attention() -> bool:
	return _current_status == "error" or _current_status == "conflict"


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
