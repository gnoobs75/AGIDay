class_name FactionMinimapIcons
extends RefCounted
## FactionMinimapIcons manages faction-specific unit icons on the minimap.

## Icon sizes by unit class
const ICON_SIZES := {
	"small": Vector2(4, 4),
	"medium": Vector2(6, 6),
	"large": Vector2(8, 8),
	"building": Vector2(12, 12),
	"factory": Vector2(16, 16)
}

## Unit type to icon class mapping
const UNIT_ICON_CLASS := {
	# Human Resistance
	"soldier": "small",
	"sniper": "small",
	"heavy_gunner": "medium",
	"commander": "medium",
	# Aether Swarm
	"micro_drone": "small",
	"stealth_drone": "small",
	"phase_unit": "medium",
	# OptiForge Legion
	"worker_bot": "small",
	"combat_bot": "medium",
	"heavy_bot": "large",
	# Dynapods Vanguard
	"quad_runner": "medium",
	"acrobat": "small",
	"behemoth": "large",
	# LogiBots Colossus
	"siege_titan": "large",
	"industrial_unit": "medium",
	"support_unit": "small"
}

## Faction colors (matches UITheme)
const FACTION_COLORS := {
	"aether_swarm": Color.CYAN,
	"optiforge_legion": Color.ORANGE,
	"dynapods_vanguard": Color("#c0c0c0"),  # Silver
	"logibots_colossus": Color.GOLD,
	"human_remnant": Color.DARK_GREEN,
	"neutral": Color.GRAY
}

## Icon container
var _container: Control = null
var _icons: Dictionary = {}  ## unit_id -> IconData
var _faction_layers: Dictionary = {}  ## faction_id -> Control


func _init() -> void:
	pass


## Create icon container.
func create_container(parent: Control) -> Control:
	_container = Control.new()
	_container.name = "FactionMinimapIcons"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_container)

	# Create layer for each faction
	for faction_id in FACTION_COLORS:
		var layer := Control.new()
		layer.name = "Layer_" + faction_id
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.add_child(layer)
		_faction_layers[faction_id] = layer

	return _container


## Add unit icon.
func add_unit_icon(unit_id: int, faction_id: String, unit_type: String, position: Vector2) -> void:
	if _icons.has(unit_id):
		return  # Already exists

	var layer: Control = _faction_layers.get(faction_id)
	if layer == null:
		layer = _faction_layers.get("neutral")

	var icon_class: String = UNIT_ICON_CLASS.get(unit_type, "small")
	var size: Vector2 = ICON_SIZES.get(icon_class, ICON_SIZES["small"])
	var color: Color = FACTION_COLORS.get(faction_id, FACTION_COLORS["neutral"])

	var icon := ColorRect.new()
	icon.name = "Icon_%d" % unit_id
	icon.color = color
	icon.custom_minimum_size = size
	icon.position = position - size / 2
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	layer.add_child(icon)

	_icons[unit_id] = {
		"node": icon,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"size": size
	}


## Update unit position.
func update_unit_position(unit_id: int, position: Vector2) -> void:
	if not _icons.has(unit_id):
		return

	var data: Dictionary = _icons[unit_id]
	var icon: ColorRect = data["node"]
	var size: Vector2 = data["size"]

	if is_instance_valid(icon):
		icon.position = position - size / 2


## Remove unit icon.
func remove_unit_icon(unit_id: int) -> void:
	if not _icons.has(unit_id):
		return

	var data: Dictionary = _icons[unit_id]
	if is_instance_valid(data["node"]):
		data["node"].queue_free()

	_icons.erase(unit_id)


## Add building icon.
func add_building_icon(building_id: int, faction_id: String, position: Vector2, is_factory: bool = false) -> void:
	if _icons.has(building_id):
		return

	var layer: Control = _faction_layers.get(faction_id)
	if layer == null:
		layer = _faction_layers.get("neutral")

	var icon_class: String = "factory" if is_factory else "building"
	var size: Vector2 = ICON_SIZES[icon_class]
	var color: Color = FACTION_COLORS.get(faction_id, FACTION_COLORS["neutral"])

	var icon := ColorRect.new()
	icon.name = "Building_%d" % building_id
	icon.color = color
	icon.custom_minimum_size = size
	icon.position = position - size / 2
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Add border for buildings
	var border := ReferenceRect.new()
	border.border_color = color.lightened(0.3)
	border.border_width = 1.0
	border.custom_minimum_size = size
	icon.add_child(border)

	layer.add_child(icon)

	_icons[building_id] = {
		"node": icon,
		"faction_id": faction_id,
		"unit_type": "building",
		"size": size
	}


## Set unit visibility.
func set_unit_visible(unit_id: int, visible: bool) -> void:
	if not _icons.has(unit_id):
		return

	var data: Dictionary = _icons[unit_id]
	if is_instance_valid(data["node"]):
		data["node"].visible = visible


## Highlight unit.
func highlight_unit(unit_id: int, highlighted: bool) -> void:
	if not _icons.has(unit_id):
		return

	var data: Dictionary = _icons[unit_id]
	if is_instance_valid(data["node"]):
		if highlighted:
			data["node"].modulate = Color(1.5, 1.5, 1.5)
		else:
			data["node"].modulate = Color.WHITE


## Batch update positions.
func batch_update_positions(updates: Array[Dictionary]) -> void:
	for update in updates:
		var unit_id: int = update.get("id", 0)
		var position: Vector2 = update.get("position", Vector2.ZERO)
		update_unit_position(unit_id, position)


## Get units at position.
func get_units_at_position(position: Vector2, radius: float = 10.0) -> Array[int]:
	var result: Array[int] = []

	for unit_id in _icons:
		var data: Dictionary = _icons[unit_id]
		if not is_instance_valid(data["node"]):
			continue

		var icon_pos: Vector2 = data["node"].position + data["size"] / 2
		if icon_pos.distance_to(position) <= radius:
			result.append(unit_id)

	return result


## Clear all icons for faction.
func clear_faction(faction_id: String) -> void:
	var to_remove: Array[int] = []

	for unit_id in _icons:
		if _icons[unit_id]["faction_id"] == faction_id:
			to_remove.append(unit_id)

	for unit_id in to_remove:
		remove_unit_icon(unit_id)


## Clear all icons.
func clear_all() -> void:
	for unit_id in _icons:
		var data: Dictionary = _icons[unit_id]
		if is_instance_valid(data["node"]):
			data["node"].queue_free()

	_icons.clear()


## Get icon count.
func get_icon_count() -> int:
	return _icons.size()


## Get container.
func get_container() -> Control:
	return _container


## Cleanup.
func cleanup() -> void:
	clear_all()
	_faction_layers.clear()

	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
