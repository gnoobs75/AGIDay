class_name UITheme
extends RefCounted
## UITheme manages the visual theming system with faction-specific colors.
## Provides dark theme as default with typography and component styling.

signal theme_changed(faction_id: String)
signal color_scheme_changed(scheme_name: String)

## Base dark theme colors
const BACKGROUND_COLOR := Color("#1a1a1a")
const PANEL_COLOR := Color("#2d2d2d")
const PANEL_BORDER_COLOR := Color("#404040")
const TEXT_COLOR := Color("#e0e0e0")
const TEXT_MUTED_COLOR := Color("#888888")
const TEXT_DISABLED_COLOR := Color("#555555")

## Faction accent colors
const FACTION_COLORS := {
	"aether_swarm": Color("#00d9ff"),      ## Cyan - stealth/energy
	"optiforge": Color("#ff6b35"),          ## Orange - industrial
	"dynapods": Color("#c0c0c0"),           ## Silver - mechanical
	"logibots": Color("#d4af37"),           ## Gold - heavy industry
	"human_remnant": Color("#556b2f"),      ## Olive - military
	"neutral": Color("#808080")             ## Gray - default
}

## Faction secondary colors (lighter variants)
const FACTION_SECONDARY_COLORS := {
	"aether_swarm": Color("#66e6ff"),
	"optiforge": Color("#ff9966"),
	"dynapods": Color("#d9d9d9"),
	"logibots": Color("#e6c766"),
	"human_remnant": Color("#7a9a4a"),
	"neutral": Color("#a0a0a0")
}

## Typography sizes (in pixels)
const FONT_SIZE_BODY := 12
const FONT_SIZE_LABEL := 14
const FONT_SIZE_HEADER := 16
const FONT_SIZE_TITLE := 24
const FONT_SIZE_LARGE_TITLE := 32

## Component styling
const CORNER_RADIUS := 4
const BORDER_WIDTH := 1
const PANEL_TRANSPARENCY := 0.85
const BUTTON_TRANSITION_TIME := 0.1

## Button state colors
const BUTTON_DEFAULT_BG := Color("#3d3d3d")
const BUTTON_HOVER_BG := Color("#4d4d4d")
const BUTTON_PRESSED_BG := Color("#2a2a2a")
const BUTTON_DISABLED_BG := Color("#252525")

## Current theme state
var _current_faction: String = "neutral"
var _base_theme: Theme = null
var _faction_themes: Dictionary = {}  ## faction_id -> Theme
var _text_scale: float = 1.0


func _init() -> void:
	_create_base_theme()
	_create_faction_themes()


## Create the base dark theme.
func _create_base_theme() -> void:
	_base_theme = Theme.new()

	# Set default font sizes
	_base_theme.set_default_font_size(FONT_SIZE_BODY)

	# Panel styling
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.bg_color.a = PANEL_TRANSPARENCY
	panel_style.border_color = PANEL_BORDER_COLOR
	panel_style.set_border_width_all(BORDER_WIDTH)
	panel_style.set_corner_radius_all(CORNER_RADIUS)
	panel_style.set_content_margin_all(8)
	_base_theme.set_stylebox("panel", "Panel", panel_style)
	_base_theme.set_stylebox("panel", "PanelContainer", panel_style)

	# Button styling
	_create_button_styles(_base_theme, FACTION_COLORS["neutral"])

	# Label styling
	_base_theme.set_color("font_color", "Label", TEXT_COLOR)
	_base_theme.set_font_size("font_size", "Label", FONT_SIZE_LABEL)

	# ProgressBar styling
	var progress_bg := StyleBoxFlat.new()
	progress_bg.bg_color = Color("#1f1f1f")
	progress_bg.set_corner_radius_all(2)
	_base_theme.set_stylebox("background", "ProgressBar", progress_bg)

	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = FACTION_COLORS["neutral"]
	progress_fill.set_corner_radius_all(2)
	_base_theme.set_stylebox("fill", "ProgressBar", progress_fill)

	# LineEdit styling
	var line_edit_style := StyleBoxFlat.new()
	line_edit_style.bg_color = Color("#252525")
	line_edit_style.border_color = PANEL_BORDER_COLOR
	line_edit_style.set_border_width_all(1)
	line_edit_style.set_corner_radius_all(CORNER_RADIUS)
	line_edit_style.set_content_margin_all(4)
	_base_theme.set_stylebox("normal", "LineEdit", line_edit_style)
	_base_theme.set_color("font_color", "LineEdit", TEXT_COLOR)

	# Separator styling
	var separator_style := StyleBoxFlat.new()
	separator_style.bg_color = PANEL_BORDER_COLOR
	_base_theme.set_stylebox("separator", "HSeparator", separator_style)
	_base_theme.set_stylebox("separator", "VSeparator", separator_style)


## Create button styles with accent color.
func _create_button_styles(theme: Theme, accent_color: Color) -> void:
	# Normal state
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = BUTTON_DEFAULT_BG
	btn_normal.border_color = accent_color.darkened(0.3)
	btn_normal.set_border_width_all(BORDER_WIDTH)
	btn_normal.set_corner_radius_all(CORNER_RADIUS)
	btn_normal.set_content_margin_all(8)
	theme.set_stylebox("normal", "Button", btn_normal)

	# Hover state
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = BUTTON_HOVER_BG
	btn_hover.border_color = accent_color
	btn_hover.set_border_width_all(BORDER_WIDTH)
	btn_hover.set_corner_radius_all(CORNER_RADIUS)
	btn_hover.set_content_margin_all(8)
	theme.set_stylebox("hover", "Button", btn_hover)

	# Pressed state
	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = BUTTON_PRESSED_BG
	btn_pressed.border_color = accent_color.lightened(0.2)
	btn_pressed.set_border_width_all(BORDER_WIDTH + 1)
	btn_pressed.set_corner_radius_all(CORNER_RADIUS)
	btn_pressed.set_content_margin_all(8)
	theme.set_stylebox("pressed", "Button", btn_pressed)

	# Disabled state
	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = BUTTON_DISABLED_BG
	btn_disabled.border_color = Color("#333333")
	btn_disabled.set_border_width_all(BORDER_WIDTH)
	btn_disabled.set_corner_radius_all(CORNER_RADIUS)
	btn_disabled.set_content_margin_all(8)
	theme.set_stylebox("disabled", "Button", btn_disabled)

	# Button text colors
	theme.set_color("font_color", "Button", TEXT_COLOR)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", accent_color)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED_COLOR)


## Create faction-specific themes.
func _create_faction_themes() -> void:
	for faction_id in FACTION_COLORS:
		var faction_theme := _base_theme.duplicate()
		var accent := FACTION_COLORS[faction_id]

		# Update button styles with faction accent
		_create_button_styles(faction_theme, accent)

		# Update panel border to faction color
		var panel_style := faction_theme.get_stylebox("panel", "Panel").duplicate()
		if panel_style is StyleBoxFlat:
			panel_style.border_color = accent.darkened(0.5)
		faction_theme.set_stylebox("panel", "Panel", panel_style)
		faction_theme.set_stylebox("panel", "PanelContainer", panel_style)

		# Update progress bar fill
		var progress_fill := StyleBoxFlat.new()
		progress_fill.bg_color = accent
		progress_fill.set_corner_radius_all(2)
		faction_theme.set_stylebox("fill", "ProgressBar", progress_fill)

		_faction_themes[faction_id] = faction_theme


## Get base theme.
func get_base_theme() -> Theme:
	return _base_theme


## Get faction-specific theme.
func get_faction_theme(faction_id: String) -> Theme:
	if _faction_themes.has(faction_id):
		return _faction_themes[faction_id]
	return _base_theme


## Set current faction theme.
func set_current_faction(faction_id: String) -> void:
	if not FACTION_COLORS.has(faction_id):
		faction_id = "neutral"

	_current_faction = faction_id
	theme_changed.emit(faction_id)


## Get current faction.
func get_current_faction() -> String:
	return _current_faction


## Get current theme.
func get_current_theme() -> Theme:
	return get_faction_theme(_current_faction)


## Get faction primary color.
func get_faction_color(faction_id: String) -> Color:
	return FACTION_COLORS.get(faction_id, FACTION_COLORS["neutral"])


## Get faction secondary color.
func get_faction_secondary_color(faction_id: String) -> Color:
	return FACTION_SECONDARY_COLORS.get(faction_id, FACTION_SECONDARY_COLORS["neutral"])


## Set text scale (for accessibility).
func set_text_scale(scale: float) -> void:
	_text_scale = clampf(scale, 0.8, 1.5)
	_update_font_sizes()


## Get text scale.
func get_text_scale() -> float:
	return _text_scale


## Update font sizes based on scale.
func _update_font_sizes() -> void:
	var scaled_body := int(FONT_SIZE_BODY * _text_scale)
	var scaled_label := int(FONT_SIZE_LABEL * _text_scale)
	var scaled_header := int(FONT_SIZE_HEADER * _text_scale)
	var scaled_title := int(FONT_SIZE_TITLE * _text_scale)

	_base_theme.set_default_font_size(scaled_body)
	_base_theme.set_font_size("font_size", "Label", scaled_label)

	for faction_theme in _faction_themes.values():
		faction_theme.set_default_font_size(scaled_body)
		faction_theme.set_font_size("font_size", "Label", scaled_label)


## Create styled panel StyleBox.
func create_panel_style(faction_id: String = "", transparent: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	if transparent:
		style.bg_color.a = PANEL_TRANSPARENCY

	var accent := get_faction_color(faction_id) if not faction_id.is_empty() else PANEL_BORDER_COLOR
	style.border_color = accent.darkened(0.5) if not faction_id.is_empty() else PANEL_BORDER_COLOR
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.set_content_margin_all(8)

	return style


## Create header style.
func create_header_style(faction_id: String = "") -> StyleBoxFlat:
	var style := create_panel_style(faction_id, false)
	var accent := get_faction_color(faction_id) if not faction_id.is_empty() else FACTION_COLORS["neutral"]
	style.bg_color = accent.darkened(0.7)
	style.border_color = accent.darkened(0.3)
	return style


## Get scaled font size.
func get_scaled_font_size(base_size: int) -> int:
	return int(base_size * _text_scale)


## Get statistics.
func get_statistics() -> Dictionary:
	return {
		"current_faction": _current_faction,
		"faction_themes_count": _faction_themes.size(),
		"text_scale": _text_scale,
		"base_font_size": FONT_SIZE_BODY
	}
