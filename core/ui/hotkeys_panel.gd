class_name HotkeysPanel
extends RefCounted
## HotkeysPanel displays faction-specific abilities (Q, W, E, R) with status.

signal ability_clicked(ability_key: String)
signal ability_ready(ability_key: String)
signal ability_cooldown_started(ability_key: String, duration: float)

## Ability keys
const ABILITY_KEYS := ["Q", "W", "E", "R"]

## Panel sizing
const PANEL_WIDTH := 320
const PANEL_HEIGHT := 70
const ABILITY_SIZE := 60

## Ability data
var _abilities: Dictionary = {}  ## key -> {name, icon, cooldown, max_cooldown, ready}

## UI components
var _container: PanelContainer = null
var _ability_buttons: Dictionary = {}  ## key -> Button
var _cooldown_labels: Dictionary = {}  ## key -> Label
var _ability_hbox: HBoxContainer = null

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	# Initialize default abilities
	for key in ABILITY_KEYS:
		_abilities[key] = {
			"name": "",
			"icon": null,
			"cooldown": 0.0,
			"max_cooldown": 0.0,
			"ready": true
		}


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "HotkeysPanel"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d", 0.7)
	style.border_color = _faction_color.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_container.add_theme_stylebox_override("panel", style)

	# Ability buttons layout
	_ability_hbox = HBoxContainer.new()
	_ability_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_hbox.add_theme_constant_override("separation", 12)
	_container.add_child(_ability_hbox)

	# Create ability buttons
	for key in ABILITY_KEYS:
		var ability_container := _create_ability_button(key)
		_ability_hbox.add_child(ability_container)

	parent.add_child(_container)
	return _container


## Create a single ability button.
func _create_ability_button(key: String) -> Control:
	var container := VBoxContainer.new()
	container.name = "Ability_" + key
	container.add_theme_constant_override("separation", 2)

	# Button
	var button := Button.new()
	button.name = "Button"
	button.text = key
	button.custom_minimum_size = Vector2(ABILITY_SIZE, ABILITY_SIZE)

	# Button styling
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color("#3d3d3d")
	btn_normal.border_color = _faction_color.darkened(0.3)
	btn_normal.set_border_width_all(2)
	btn_normal.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", btn_normal)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color("#4d4d4d")
	btn_hover.border_color = _faction_color
	btn_hover.set_border_width_all(2)
	btn_hover.set_corner_radius_all(4)
	button.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = Color("#2a2a2a")
	btn_pressed.border_color = _faction_color.lightened(0.2)
	btn_pressed.set_border_width_all(2)
	btn_pressed.set_corner_radius_all(4)
	button.add_theme_stylebox_override("pressed", btn_pressed)

	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = Color("#252525")
	btn_disabled.border_color = Color("#333333")
	btn_disabled.set_border_width_all(2)
	btn_disabled.set_corner_radius_all(4)
	button.add_theme_stylebox_override("disabled", btn_disabled)

	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(func(): _on_ability_pressed(key))

	container.add_child(button)
	_ability_buttons[key] = button

	# Cooldown/status label
	var cooldown_label := Label.new()
	cooldown_label.name = "CooldownLabel"
	cooldown_label.text = ""
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_label.add_theme_font_size_override("font_size", 10)
	cooldown_label.add_theme_color_override("font_color", Color("#888888"))
	container.add_child(cooldown_label)
	_cooldown_labels[key] = cooldown_label

	return container


## Update abilities display.
func update_abilities(abilities: Array[Dictionary]) -> void:
	for i in mini(abilities.size(), ABILITY_KEYS.size()):
		var key: String = ABILITY_KEYS[i]
		var ability_data: Dictionary = abilities[i]

		_abilities[key] = {
			"name": ability_data.get("name", ""),
			"icon": ability_data.get("icon"),
			"cooldown": ability_data.get("cooldown", 0.0),
			"max_cooldown": ability_data.get("max_cooldown", 0.0),
			"ready": ability_data.get("ready", true)
		}

	_update_display()


## Update single ability.
func update_ability(key: String, name: String, cooldown: float, max_cooldown: float, ready: bool) -> void:
	if not _abilities.has(key):
		return

	var was_ready: bool = _abilities[key]["ready"]

	_abilities[key]["name"] = name
	_abilities[key]["cooldown"] = cooldown
	_abilities[key]["max_cooldown"] = max_cooldown
	_abilities[key]["ready"] = ready

	_update_ability_display(key)

	# Emit signals for state changes
	if ready and not was_ready:
		ability_ready.emit(key)
	elif not ready and was_ready and max_cooldown > 0:
		ability_cooldown_started.emit(key, max_cooldown)


## Update display elements.
func _update_display() -> void:
	for key in ABILITY_KEYS:
		_update_ability_display(key)


## Update single ability display.
func _update_ability_display(key: String) -> void:
	if not _ability_buttons.has(key):
		return

	var button: Button = _ability_buttons[key]
	var label: Label = _cooldown_labels[key]
	var data: Dictionary = _abilities[key]

	# Update button state
	button.disabled = not data["ready"]

	# Update button text (key or name abbreviation)
	if data["name"].is_empty():
		button.text = key
	else:
		button.text = key  # Keep key visible, name in tooltip
		button.tooltip_text = data["name"]

	# Update cooldown label
	if data["cooldown"] > 0:
		label.text = "%.1fs" % data["cooldown"]
		label.add_theme_color_override("font_color", Color.ORANGE)
	elif not data["ready"]:
		label.text = "..."
		label.add_theme_color_override("font_color", Color.RED)
	elif not data["name"].is_empty():
		label.text = "Ready"
		label.add_theme_color_override("font_color", Color.GREEN)
	else:
		label.text = ""


## Handle ability button press.
func _on_ability_pressed(key: String) -> void:
	ability_clicked.emit(key)


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _container != null:
		var style := _container.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = _faction_color.darkened(0.3)

	# Update button styles
	for key in _ability_buttons:
		var button: Button = _ability_buttons[key]

		var btn_normal := button.get_theme_stylebox("normal") as StyleBoxFlat
		if btn_normal != null:
			btn_normal.border_color = _faction_color.darkened(0.3)

		var btn_hover := button.get_theme_stylebox("hover") as StyleBoxFlat
		if btn_hover != null:
			btn_hover.border_color = _faction_color


## Get container.
func get_container() -> Control:
	return _container


## Get ability state.
func get_ability_state(key: String) -> Dictionary:
	return _abilities.get(key, {}).duplicate()


## Check if ability is ready.
func is_ability_ready(key: String) -> bool:
	return _abilities.get(key, {}).get("ready", false)


## Cleanup.
func cleanup() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_ability_buttons.clear()
	_cooldown_labels.clear()
	_ability_hbox = null
