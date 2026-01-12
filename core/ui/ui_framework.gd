class_name UIFramework
extends RefCounted
## UIFramework is the main facade for the UI system.
## Integrates theming, scaling, accessibility, and component creation.

signal framework_initialized()
signal faction_changed(faction_id: String)
signal settings_changed()

## Subsystems
var theme: UITheme = null
var scaling: UIScaling = null
var accessibility: UIAccessibility = null
var components: UIComponents = null

## Current state
var _current_faction: String = "neutral"
var _is_initialized := false
var _performance_mode := false

## UI layer references
var _ui_root: CanvasLayer = null
var _hud_layer: Control = null
var _menu_layer: Control = null
var _popup_layer: Control = null
var _tooltip_layer: Control = null

## Active panels for culling
var _registered_panels: Dictionary = {}  ## panel_id -> WeakRef

## Panel visibility callbacks
var _visibility_callbacks: Array[Callable] = []


func _init() -> void:
	# Create subsystems
	theme = UITheme.new()
	scaling = UIScaling.new()
	accessibility = UIAccessibility.new()
	components = UIComponents.new()


## Initialize the framework.
func initialize(viewport_size: Vector2i) -> void:
	if _is_initialized:
		return

	# Initialize subsystems
	scaling.initialize(viewport_size)
	components.initialize(theme, scaling, accessibility)

	# Connect signals
	theme.theme_changed.connect(_on_theme_changed)
	scaling.scale_factor_changed.connect(_on_scale_changed)
	accessibility.accessibility_updated.connect(_on_accessibility_updated)

	_is_initialized = true
	framework_initialized.emit()


## Set up UI layers (call from scene tree).
func setup_layers(root: CanvasLayer) -> void:
	_ui_root = root

	# Create layer containers
	_hud_layer = Control.new()
	_hud_layer.name = "HUDLayer"
	_hud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud_layer)

	_menu_layer = Control.new()
	_menu_layer.name = "MenuLayer"
	_menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_layer.visible = false
	root.add_child(_menu_layer)

	_popup_layer = Control.new()
	_popup_layer.name = "PopupLayer"
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popup_layer)

	_tooltip_layer = Control.new()
	_tooltip_layer.name = "TooltipLayer"
	_tooltip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tooltip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tooltip_layer)


## Get HUD layer.
func get_hud_layer() -> Control:
	return _hud_layer


## Get menu layer.
func get_menu_layer() -> Control:
	return _menu_layer


## Get popup layer.
func get_popup_layer() -> Control:
	return _popup_layer


## Get tooltip layer.
func get_tooltip_layer() -> Control:
	return _tooltip_layer


## Set current faction (updates theming).
func set_faction(faction_id: String) -> void:
	if not UITheme.FACTION_COLORS.has(faction_id):
		faction_id = "neutral"

	_current_faction = faction_id
	theme.set_current_faction(faction_id)
	faction_changed.emit(faction_id)


## Get current faction.
func get_faction() -> String:
	return _current_faction


## Get faction color.
func get_faction_color(faction_id: String = "") -> Color:
	if faction_id.is_empty():
		faction_id = _current_faction
	return theme.get_faction_color(faction_id)


## Set performance mode.
func set_performance_mode(enabled: bool) -> void:
	_performance_mode = enabled
	components.set_performance_mode(enabled)
	settings_changed.emit()


## Is performance mode enabled.
func is_performance_mode() -> bool:
	return _performance_mode


## Handle resolution change.
func on_resolution_changed(new_size: Vector2i) -> void:
	scaling.set_resolution(new_size)


## Create a panel (convenience wrapper).
func create_panel(faction_id: String = "") -> PanelContainer:
	if faction_id.is_empty():
		faction_id = _current_faction
	return components.create_panel(faction_id)


## Create a button (convenience wrapper).
func create_button(text: String, faction_id: String = "") -> Button:
	if faction_id.is_empty():
		faction_id = _current_faction
	return components.create_button(text, faction_id)


## Create a label (convenience wrapper).
func create_label(text: String, size: String = "body") -> Label:
	return components.create_label(text, size)


## Create a progress bar (convenience wrapper).
func create_progress_bar(faction_id: String = "") -> ProgressBar:
	if faction_id.is_empty():
		faction_id = _current_faction
	return components.create_progress_bar(faction_id)


## Register a panel for visibility management.
func register_panel(panel_id: String, panel: Control) -> void:
	_registered_panels[panel_id] = weakref(panel)


## Unregister a panel.
func unregister_panel(panel_id: String) -> void:
	_registered_panels.erase(panel_id)


## Get registered panel.
func get_panel(panel_id: String) -> Control:
	if _registered_panels.has(panel_id):
		var ref: WeakRef = _registered_panels[panel_id]
		return ref.get_ref() as Control
	return null


## Show a registered panel.
func show_panel(panel_id: String, animate: bool = true) -> void:
	var panel := get_panel(panel_id)
	if panel == null:
		return

	if animate and not _performance_mode:
		components.fade_in(panel)
	else:
		panel.visible = true
		panel.modulate.a = 1.0


## Hide a registered panel.
func hide_panel(panel_id: String, animate: bool = true) -> void:
	var panel := get_panel(panel_id)
	if panel == null:
		return

	if animate and not _performance_mode:
		components.fade_out(panel, 0.2, true)
	else:
		panel.visible = false


## Toggle a registered panel.
func toggle_panel(panel_id: String, animate: bool = true) -> void:
	var panel := get_panel(panel_id)
	if panel == null:
		return

	if panel.visible:
		hide_panel(panel_id, animate)
	else:
		show_panel(panel_id, animate)


## Show menu layer (pauses HUD interaction).
func show_menu() -> void:
	_menu_layer.visible = true
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Hide menu layer.
func hide_menu() -> void:
	_menu_layer.visible = false
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Is menu visible.
func is_menu_visible() -> bool:
	return _menu_layer != null and _menu_layer.visible


## Update panel visibility based on screen position (culling).
func update_panel_culling(viewport_rect: Rect2) -> void:
	for panel_id in _registered_panels:
		var ref: WeakRef = _registered_panels[panel_id]
		var panel := ref.get_ref() as Control
		if panel == null:
			continue

		# Get panel rect in screen space
		var panel_rect := panel.get_global_rect()

		# Check if visible
		var should_be_visible := viewport_rect.intersects(panel_rect)

		# Only update if changed (avoid unnecessary property sets)
		if panel.visible != should_be_visible:
			panel.visible = should_be_visible


## Apply current theme to a control tree.
func apply_theme_to_tree(root: Control) -> void:
	root.theme = theme.get_current_theme()

	for child in root.get_children():
		if child is Control:
			apply_theme_to_tree(child)


## Apply accessibility settings to a control tree.
func apply_accessibility_to_tree(root: Control) -> void:
	if root is Label:
		accessibility.apply_to_label(root)
	elif root is Button:
		accessibility.apply_to_button(root)

	for child in root.get_children():
		if child is Control:
			apply_accessibility_to_tree(child)


## Get accessibility-safe color.
func get_safe_color(semantic_type: String, fallback: Color = Color.WHITE) -> Color:
	return accessibility.get_accessible_color(semantic_type, fallback)


## Signal handlers
func _on_theme_changed(faction_id: String) -> void:
	# Re-apply theme to registered panels
	for panel_id in _registered_panels:
		var panel := get_panel(panel_id)
		if panel != null:
			apply_theme_to_tree(panel)

	settings_changed.emit()


func _on_scale_changed(_factor: float) -> void:
	settings_changed.emit()


func _on_accessibility_updated() -> void:
	# Re-apply accessibility to registered panels
	for panel_id in _registered_panels:
		var panel := get_panel(panel_id)
		if panel != null:
			apply_accessibility_to_tree(panel)

	settings_changed.emit()


## Serialize settings to dictionary.
func save_settings() -> Dictionary:
	return {
		"scaling": scaling.to_dict(),
		"accessibility": accessibility.to_dict(),
		"faction": _current_faction,
		"performance_mode": _performance_mode
	}


## Load settings from dictionary.
func load_settings(data: Dictionary) -> void:
	if data.has("scaling"):
		scaling.from_dict(data["scaling"])

	if data.has("accessibility"):
		accessibility.from_dict(data["accessibility"])

	if data.has("faction"):
		set_faction(data["faction"])

	if data.has("performance_mode"):
		set_performance_mode(data["performance_mode"])


## Get statistics.
func get_statistics() -> Dictionary:
	# Clean up dead panel references
	var dead_panels: Array[String] = []
	for panel_id in _registered_panels:
		var ref: WeakRef = _registered_panels[panel_id]
		if ref.get_ref() == null:
			dead_panels.append(panel_id)

	for panel_id in dead_panels:
		_registered_panels.erase(panel_id)

	return {
		"initialized": _is_initialized,
		"current_faction": _current_faction,
		"performance_mode": _performance_mode,
		"registered_panels": _registered_panels.size(),
		"has_ui_root": _ui_root != null,
		"menu_visible": is_menu_visible(),
		"theme": theme.get_statistics(),
		"scaling": scaling.get_statistics(),
		"accessibility": accessibility.get_statistics(),
		"components": components.get_statistics()
	}


## Cleanup.
func cleanup() -> void:
	_registered_panels.clear()
	_visibility_callbacks.clear()

	if _hud_layer != null:
		_hud_layer.queue_free()
	if _menu_layer != null:
		_menu_layer.queue_free()
	if _popup_layer != null:
		_popup_layer.queue_free()
	if _tooltip_layer != null:
		_tooltip_layer.queue_free()

	_hud_layer = null
	_menu_layer = null
	_popup_layer = null
	_tooltip_layer = null
	_ui_root = null
