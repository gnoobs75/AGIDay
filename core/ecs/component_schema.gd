class_name ComponentSchema
extends RefCounted
## ComponentSchema defines the field structure and validation rules for a component type.
## Supports type checking, range validation, enum validation, and custom validators.

## Field definition structure
class FieldDef:
	var name: String
	var type: int  # Variant.Type
	var required: bool = true
	var default_value: Variant = null
	var min_value: Variant = null
	var max_value: Variant = null
	var enum_values: Array = []
	var custom_validator: Callable = Callable()
	var description: String = ""

	func _init(field_name: String, field_type: int) -> void:
		name = field_name
		type = field_type

	func set_required(is_required: bool) -> FieldDef:
		required = is_required
		return self

	func set_default(value: Variant) -> FieldDef:
		default_value = value
		required = false
		return self

	func set_range(min_val: Variant, max_val: Variant) -> FieldDef:
		min_value = min_val
		max_value = max_val
		return self

	func set_enum(values: Array) -> FieldDef:
		enum_values = values
		return self

	func set_validator(validator: Callable) -> FieldDef:
		custom_validator = validator
		return self

	func set_description(desc: String) -> FieldDef:
		description = desc
		return self


## Schema name (matches component type)
var schema_name: String = ""

## Field definitions indexed by name
var _fields: Dictionary = {}

## Field names in definition order
var _field_order: Array[String] = []

## Validation errors from last validate call
var _last_errors: Array[String] = []


func _init(name: String = "") -> void:
	schema_name = name


## Define a new field in the schema.
## Returns the FieldDef for chaining configuration.
func define_field(field_name: String, field_type: int) -> FieldDef:
	var field := FieldDef.new(field_name, field_type)
	_fields[field_name] = field
	_field_order.append(field_name)
	return field


## Define a boolean field.
func bool_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_BOOL)


## Define an integer field.
func int_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_INT)


## Define a float field.
func float_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_FLOAT)


## Define a string field.
func string_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_STRING)


## Define a Vector2 field.
func vector2_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_VECTOR2)


## Define a Vector3 field.
func vector3_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_VECTOR3)


## Define a Color field.
func color_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_COLOR)


## Define a dictionary field.
func dict_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_DICTIONARY)


## Define an array field.
func array_field(field_name: String) -> FieldDef:
	return define_field(field_name, TYPE_ARRAY)


## Get a field definition by name.
func get_field(field_name: String) -> FieldDef:
	return _fields.get(field_name)


## Get all field names.
func get_field_names() -> Array[String]:
	return _field_order.duplicate()


## Check if a field exists.
func has_field(field_name: String) -> bool:
	return _fields.has(field_name)


## Validate data against this schema.
## Returns true if valid, false otherwise.
## Call get_errors() to retrieve validation errors.
func validate(data: Dictionary) -> bool:
	_last_errors.clear()

	# Check required fields
	for field_name in _field_order:
		var field: FieldDef = _fields[field_name]

		if not data.has(field_name):
			if field.required:
				_last_errors.append("Missing required field: %s" % field_name)
			continue

		var value = data[field_name]

		# Type check
		if not _validate_type(value, field):
			_last_errors.append("Field '%s' has wrong type: expected %s, got %s" % [
				field_name,
				_type_name(field.type),
				_type_name(typeof(value))
			])
			continue

		# Range check
		if not _validate_range(value, field):
			_last_errors.append("Field '%s' value %s out of range [%s, %s]" % [
				field_name, str(value), str(field.min_value), str(field.max_value)
			])

		# Enum check
		if not _validate_enum(value, field):
			_last_errors.append("Field '%s' value '%s' not in allowed values: %s" % [
				field_name, str(value), str(field.enum_values)
			])

		# Custom validation
		if field.custom_validator.is_valid():
			var result = field.custom_validator.call(value)
			if result is String and not result.is_empty():
				_last_errors.append("Field '%s': %s" % [field_name, result])
			elif result is bool and not result:
				_last_errors.append("Field '%s' failed custom validation" % field_name)

	return _last_errors.is_empty()


## Validate field type.
func _validate_type(value: Variant, field: FieldDef) -> bool:
	var value_type := typeof(value)

	# Allow null for optional fields
	if value_type == TYPE_NIL:
		return not field.required

	# Exact type match
	if value_type == field.type:
		return true

	# Allow int -> float conversion
	if field.type == TYPE_FLOAT and value_type == TYPE_INT:
		return true

	return false


## Validate value range.
func _validate_range(value: Variant, field: FieldDef) -> bool:
	if field.min_value == null and field.max_value == null:
		return true

	var value_type := typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return true  # Range only applies to numbers

	if field.min_value != null and value < field.min_value:
		return false

	if field.max_value != null and value > field.max_value:
		return false

	return true


## Validate enum values.
func _validate_enum(value: Variant, field: FieldDef) -> bool:
	if field.enum_values.is_empty():
		return true

	return value in field.enum_values


## Get type name for error messages.
func _type_name(type: int) -> String:
	match type:
		TYPE_NIL: return "null"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_COLOR: return "Color"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_: return "unknown"


## Get validation errors from last validate call.
func get_errors() -> Array[String]:
	return _last_errors.duplicate()


## Apply defaults to data dictionary.
## Returns a new dictionary with defaults applied.
func apply_defaults(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)

	for field_name in _field_order:
		var field: FieldDef = _fields[field_name]
		if not result.has(field_name) and field.default_value != null:
			result[field_name] = field.default_value

	return result


## Serialize schema to dictionary (for debugging/documentation).
func to_dict() -> Dictionary:
	var fields_data: Array = []
	for field_name in _field_order:
		var field: FieldDef = _fields[field_name]
		fields_data.append({
			"name": field.name,
			"type": _type_name(field.type),
			"required": field.required,
			"has_default": field.default_value != null,
			"has_range": field.min_value != null or field.max_value != null,
			"has_enum": not field.enum_values.is_empty(),
			"description": field.description
		})

	return {
		"name": schema_name,
		"fields": fields_data
	}
