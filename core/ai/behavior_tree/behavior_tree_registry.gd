class_name BehaviorTreeRegistry
extends RefCounted
## BehaviorTreeRegistry manages behavior tree templates by faction and unit type.
## Provides template registration, lookup, and wrapper creation.

signal template_registered(template_id: String)
signal template_removed(template_id: String)
signal wrapper_created(unit_id: int, template_id: String)

## All registered templates (template_id -> BehaviorTreeTemplate)
var _templates: Dictionary = {}

## Templates indexed by faction (faction_id -> Array[template_id])
var _faction_templates: Dictionary = {}

## Templates indexed by unit type (unit_type -> Array[template_id])
var _unit_type_templates: Dictionary = {}

## Default template ID when no match found
var default_template_id: String = "default"


func _init() -> void:
	_register_default_templates()


## Register default templates.
func _register_default_templates() -> void:
	# Default attack-or-idle template
	var default_template := BehaviorTreeTemplate.new()
	default_template.template_id = "default"
	default_template.tree_type = "attack_or_idle"
	default_template.description = "Default behavior for any unit"
	register_template(default_template)

	# Combat template
	register_template(BehaviorTreeTemplate.create_combat_template())

	# Builder template
	register_template(BehaviorTreeTemplate.create_builder_template())

	# Gatherer template
	register_template(BehaviorTreeTemplate.create_gatherer_template())


## Register a behavior tree template.
func register_template(template: BehaviorTreeTemplate) -> void:
	var template_id := template.template_id
	_templates[template_id] = template

	# Index by faction
	var faction_id := template.faction_id
	if not _faction_templates.has(faction_id):
		_faction_templates[faction_id] = []
	if template_id not in _faction_templates[faction_id]:
		_faction_templates[faction_id].append(template_id)

	# Index by unit type
	var unit_type := template.unit_type
	if not unit_type.is_empty():
		if not _unit_type_templates.has(unit_type):
			_unit_type_templates[unit_type] = []
		if template_id not in _unit_type_templates[unit_type]:
			_unit_type_templates[unit_type].append(template_id)

	template_registered.emit(template_id)


## Remove a template.
func remove_template(template_id: String) -> bool:
	if not _templates.has(template_id):
		return false

	var template: BehaviorTreeTemplate = _templates[template_id]

	# Remove from faction index
	var faction_id := template.faction_id
	if _faction_templates.has(faction_id):
		var idx: int = _faction_templates[faction_id].find(template_id)
		if idx >= 0:
			_faction_templates[faction_id].remove_at(idx)

	# Remove from unit type index
	var unit_type := template.unit_type
	if _unit_type_templates.has(unit_type):
		var unit_type_idx: int = _unit_type_templates[unit_type].find(template_id)
		if unit_type_idx >= 0:
			_unit_type_templates[unit_type].remove_at(unit_type_idx)

	_templates.erase(template_id)
	template_removed.emit(template_id)
	return true


## Get a template by ID.
func get_template(template_id: String) -> BehaviorTreeTemplate:
	return _templates.get(template_id)


## Find the best matching template for a faction and unit type.
func find_best_template(faction_id: int, unit_type: String) -> BehaviorTreeTemplate:
	var best_template: BehaviorTreeTemplate = null
	var best_specificity := -1

	for template_id in _templates:
		var template: BehaviorTreeTemplate = _templates[template_id]
		if template.matches(faction_id, unit_type):
			var specificity := template.get_specificity()
			if specificity > best_specificity:
				best_specificity = specificity
				best_template = template

	# Fallback to default
	if best_template == null:
		best_template = _templates.get(default_template_id)

	return best_template


## Get all templates for a faction.
func get_templates_for_faction(faction_id: int) -> Array[BehaviorTreeTemplate]:
	var result: Array[BehaviorTreeTemplate] = []

	# Get faction-specific templates
	if _faction_templates.has(faction_id):
		for template_id in _faction_templates[faction_id]:
			result.append(_templates[template_id])

	# Also include any-faction templates
	if _faction_templates.has(0):
		for template_id in _faction_templates[0]:
			if not result.has(_templates[template_id]):
				result.append(_templates[template_id])

	return result


## Get all templates for a unit type.
func get_templates_for_unit_type(unit_type: String) -> Array[BehaviorTreeTemplate]:
	var result: Array[BehaviorTreeTemplate] = []

	if _unit_type_templates.has(unit_type):
		for template_id in _unit_type_templates[unit_type]:
			result.append(_templates[template_id])

	return result


## Create a behavior tree wrapper for a unit.
func create_wrapper(unit_id: int, faction_id: int, unit_type: String, seed: int = 0) -> BehaviorTreeWrapper:
	var template := find_best_template(faction_id, unit_type)
	var wrapper := BehaviorTreeWrapper.new(unit_id, faction_id, unit_type)

	if template != null:
		wrapper.set_tree_from_template(template)
	else:
		# Fallback to default attack-or-idle
		wrapper.set_tree(UnitBehaviorTree.create_attack_or_idle_tree(unit_id))
		wrapper.template_id = "default"

	if seed != 0:
		wrapper.initialize(seed)

	wrapper_created.emit(unit_id, wrapper.template_id)
	return wrapper


## Create a wrapper with a specific template.
func create_wrapper_with_template(unit_id: int, faction_id: int, unit_type: String, template_id: String, seed: int = 0) -> BehaviorTreeWrapper:
	var template := get_template(template_id)
	var wrapper := BehaviorTreeWrapper.new(unit_id, faction_id, unit_type)

	if template != null:
		wrapper.set_tree_from_template(template)
	else:
		# Fallback to best match
		template = find_best_template(faction_id, unit_type)
		if template != null:
			wrapper.set_tree_from_template(template)
		else:
			wrapper.set_tree(UnitBehaviorTree.create_attack_or_idle_tree(unit_id))
			wrapper.template_id = "default"

	if seed != 0:
		wrapper.initialize(seed)

	wrapper_created.emit(unit_id, wrapper.template_id)
	return wrapper


## Get all registered template IDs.
func get_all_template_ids() -> Array[String]:
	var result: Array[String] = []
	for id in _templates.keys():
		result.append(str(id))
	return result


## Get template count.
func get_template_count() -> int:
	return _templates.size()


## Load templates from a directory.
func load_templates_from_directory(path: String) -> int:
	var loaded := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource := ResourceLoader.load(path.path_join(file_name))
			if resource is BehaviorTreeTemplate:
				register_template(resource)
				loaded += 1
		file_name = dir.get_next()
	dir.list_dir_end()

	return loaded


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"template_count": _templates.size(),
		"faction_count": _faction_templates.size(),
		"unit_type_count": _unit_type_templates.size(),
		"default_template": default_template_id,
		"templates": get_all_template_ids()
	}
