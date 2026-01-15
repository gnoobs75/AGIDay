class_name ResearchTreePanel
extends RefCounted
## ResearchTreePanel displays technology tree with nodes and prerequisite connections.

signal technology_selected(tech_id: String)
signal technology_queued(tech_id: String)
signal panel_closed()

## Panel sizing
const PANEL_WIDTH := 800
const PANEL_HEIGHT := 600
const NODE_WIDTH := 140
const NODE_HEIGHT := 80
const NODE_SPACING_H := 40
const NODE_SPACING_V := 30

## Technology states
enum TechState {
	LOCKED,       ## Prerequisites not met
	AVAILABLE,    ## Can be researched
	RESEARCHING,  ## Currently researching
	COMPLETED     ## Already researched
}

## State colors
const STATE_COLORS := {
	TechState.LOCKED: Color.RED.darkened(0.3),
	TechState.AVAILABLE: Color.YELLOW,
	TechState.RESEARCHING: Color.CYAN,
	TechState.COMPLETED: Color.GREEN
}

## Technology data
var _technologies: Dictionary = {}  ## tech_id -> {name, description, state, prereqs, tier, position}
var _connections: Array[Dictionary] = []  ## [{from, to}]

## UI components
var _container: PanelContainer = null
var _tree_scroll: ScrollContainer = null
var _tree_container: Control = null
var _node_container: Control = null
var _connection_lines: Control = null
var _detail_panel: PanelContainer = null
var _nodes: Dictionary = {}  ## tech_id -> ResearchNode

## Selected technology
var _selected_tech := ""

## Faction accent color
var _faction_color := Color("#808080")


func _init() -> void:
	pass


## Create UI components.
func create_ui(parent: Control, faction_id: String = "neutral") -> Control:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	# Main container
	_container = PanelContainer.new()
	_container.name = "ResearchTreePanel"
	_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a", 0.95)
	style.border_color = _faction_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_container.add_theme_stylebox_override("panel", style)

	# Main layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_container.add_child(vbox)

	# Header with close button
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "Technology Tree"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(func(): panel_closed.emit())
	header.add_child(close_btn)

	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	# Split view: tree and details
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Tree scroll area
	_tree_scroll = ScrollContainer.new()
	_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tree_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_scroll.custom_minimum_size.x = 500

	_tree_container = Control.new()
	_tree_container.custom_minimum_size = Vector2(1200, 800)

	# Connection lines (drawn behind nodes)
	_connection_lines = Control.new()
	_connection_lines.name = "ConnectionLines"
	_connection_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connection_lines.draw.connect(_draw_connections)
	_tree_container.add_child(_connection_lines)

	# Node container
	_node_container = Control.new()
	_node_container.name = "NodeContainer"
	_node_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tree_container.add_child(_node_container)

	_tree_scroll.add_child(_tree_container)
	split.add_child(_tree_scroll)

	# Details panel
	_detail_panel = _create_detail_panel()
	split.add_child(_detail_panel)

	vbox.add_child(split)

	# Legend
	var legend := _create_legend()
	vbox.add_child(legend)

	parent.add_child(_container)
	return _container


## Create detail panel.
func _create_detail_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "DetailPanel"
	panel.custom_minimum_size.x = 250

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d2d2d")
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header := Label.new()
	header.name = "TechName"
	header.text = "Select a Technology"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color.WHITE)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(header)

	var desc := Label.new()
	desc.name = "TechDescription"
	desc.text = "Click on a technology node to view details."
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color("#aaaaaa"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	var prereq_header := Label.new()
	prereq_header.text = "Prerequisites:"
	prereq_header.add_theme_font_size_override("font_size", 12)
	prereq_header.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(prereq_header)

	var prereq_list := VBoxContainer.new()
	prereq_list.name = "PrereqList"
	vbox.add_child(prereq_list)

	vbox.add_child(HSeparator.new())

	var unlocks_header := Label.new()
	unlocks_header.text = "Unlocks:"
	unlocks_header.add_theme_font_size_override("font_size", 12)
	unlocks_header.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(unlocks_header)

	var unlocks_list := VBoxContainer.new()
	unlocks_list.name = "UnlocksList"
	vbox.add_child(unlocks_list)

	# Research button
	var research_btn := Button.new()
	research_btn.name = "ResearchButton"
	research_btn.text = "Research"
	research_btn.custom_minimum_size.y = 40
	research_btn.visible = false
	research_btn.pressed.connect(_on_research_pressed)
	vbox.add_child(research_btn)

	return panel


## Create legend.
func _create_legend() -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	for state in STATE_COLORS:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)

		var color_box := ColorRect.new()
		color_box.color = STATE_COLORS[state]
		color_box.custom_minimum_size = Vector2(16, 16)
		item.add_child(color_box)

		var label := Label.new()
		match state:
			TechState.LOCKED: label.text = "Locked"
			TechState.AVAILABLE: label.text = "Available"
			TechState.RESEARCHING: label.text = "Researching"
			TechState.COMPLETED: label.text = "Completed"
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color("#888888"))
		item.add_child(label)

		hbox.add_child(item)

	return hbox


## Draw connection lines between nodes.
func _draw_connections() -> void:
	if _connection_lines == null:
		return

	for conn in _connections:
		var from_tech: String = conn["from"]
		var to_tech: String = conn["to"]

		if not _technologies.has(from_tech) or not _technologies.has(to_tech):
			continue

		var from_pos: Vector2 = _technologies[from_tech].get("position", Vector2.ZERO)
		var to_pos: Vector2 = _technologies[to_tech].get("position", Vector2.ZERO)

		# Adjust to center of nodes
		var from_center := from_pos + Vector2(NODE_WIDTH, NODE_HEIGHT / 2)
		var to_center := to_pos + Vector2(0, NODE_HEIGHT / 2)

		# Get line color based on target state
		var target_state: int = _technologies[to_tech].get("state", TechState.LOCKED)
		var line_color: Color = STATE_COLORS[target_state].darkened(0.3)

		_connection_lines.draw_line(from_center, to_center, line_color, 2.0, true)


## Set technology tree data.
func set_technologies(techs: Array[Dictionary]) -> void:
	_technologies.clear()
	_connections.clear()

	# Clear existing nodes
	for node in _nodes.values():
		if node != null and is_instance_valid(node.get_container()):
			node.get_container().queue_free()
	_nodes.clear()

	# Process technologies
	for tech in techs:
		var tech_id: String = tech.get("id", "")
		if tech_id.is_empty():
			continue

		_technologies[tech_id] = tech

		# Calculate position based on tier
		var tier: int = tech.get("tier", 0)
		var index: int = _count_techs_in_tier(tier)
		var pos := Vector2(
			20 + tier * (NODE_WIDTH + NODE_SPACING_H),
			20 + index * (NODE_HEIGHT + NODE_SPACING_V)
		)
		_technologies[tech_id]["position"] = pos

		# Create connections from prerequisites
		var prereqs: Array = tech.get("prereqs", [])
		for prereq in prereqs:
			_connections.append({"from": prereq, "to": tech_id})

		# Create node
		var node := _create_tech_node(tech_id, tech)
		_nodes[tech_id] = node

	# Update container size
	_update_container_size()
	_connection_lines.queue_redraw()


## Count technologies in a tier.
func _count_techs_in_tier(tier: int) -> int:
	var count := 0
	for tech in _technologies.values():
		if tech.get("tier", 0) == tier and tech.has("position"):
			count += 1
	return count


## Create a technology node.
func _create_tech_node(tech_id: String, data: Dictionary) -> ResearchNode:
	var node := ResearchNode.new()
	node.create_ui(_node_container, tech_id, data, _faction_color)
	node.node_clicked.connect(_on_node_clicked)
	node.node_double_clicked.connect(_on_node_double_clicked)

	var pos: Vector2 = data.get("position", Vector2.ZERO)
	node.set_position(pos)

	return node


## Update container size based on nodes.
func _update_container_size() -> void:
	var max_x := 0.0
	var max_y := 0.0

	for tech in _technologies.values():
		var pos: Vector2 = tech.get("position", Vector2.ZERO)
		max_x = maxf(max_x, pos.x + NODE_WIDTH + 40)
		max_y = maxf(max_y, pos.y + NODE_HEIGHT + 40)

	_tree_container.custom_minimum_size = Vector2(max_x, max_y)


## Update technology state.
func update_technology_state(tech_id: String, state: int, progress: float = 0.0) -> void:
	if _technologies.has(tech_id):
		_technologies[tech_id]["state"] = state
		_technologies[tech_id]["progress"] = progress

	if _nodes.has(tech_id):
		_nodes[tech_id].update_state(state, progress)

	_connection_lines.queue_redraw()


## Handle node clicked.
func _on_node_clicked(tech_id: String) -> void:
	_selected_tech = tech_id
	_update_detail_panel(tech_id)
	technology_selected.emit(tech_id)


## Handle node double-clicked.
func _on_node_double_clicked(tech_id: String) -> void:
	var tech: Dictionary = _technologies.get(tech_id, {})
	var state: int = tech.get("state", TechState.LOCKED)

	if state == TechState.AVAILABLE:
		technology_queued.emit(tech_id)


## Update detail panel.
func _update_detail_panel(tech_id: String) -> void:
	if _detail_panel == null:
		return

	var tech: Dictionary = _technologies.get(tech_id, {})

	var name_label := _detail_panel.get_node_or_null("VBoxContainer/TechName") as Label
	if name_label != null:
		name_label.text = tech.get("name", "Unknown")

	var desc_label := _detail_panel.get_node_or_null("VBoxContainer/TechDescription") as Label
	if desc_label != null:
		desc_label.text = tech.get("description", "No description available.")

	# Update research button visibility
	var research_btn := _detail_panel.get_node_or_null("VBoxContainer/ResearchButton") as Button
	if research_btn != null:
		var state: int = tech.get("state", TechState.LOCKED)
		research_btn.visible = state == TechState.AVAILABLE


## Handle research button pressed.
func _on_research_pressed() -> void:
	if not _selected_tech.is_empty():
		technology_queued.emit(_selected_tech)


## Apply faction theme.
func apply_faction_theme(faction_id: String) -> void:
	_faction_color = UITheme.FACTION_COLORS.get(faction_id, UITheme.FACTION_COLORS["neutral"])

	if _container != null:
		var style := _container.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = _faction_color

	for node in _nodes.values():
		node.apply_faction_theme(faction_id)


## Get container.
func get_container() -> Control:
	return _container


## Set visibility.
func set_visible(visible: bool) -> void:
	if _container != null:
		_container.visible = visible


## Cleanup.
func cleanup() -> void:
	for node in _nodes.values():
		node.cleanup()
	_nodes.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
