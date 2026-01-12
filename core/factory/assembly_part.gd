class_name AssemblyPart
extends RefCounted
## AssemblyPart defines a single part in the unit assembly process.

## Part identity
var part_id: String = ""
var part_name: String = ""

## Visual resources
var mesh: String = ""  ## Path to mesh resource
var material: String = ""  ## Path to material resource

## Positioning
var start_position: Vector3 = Vector3.ZERO
var final_position: Vector3 = Vector3.ZERO
var start_rotation: Quaternion = Quaternion.IDENTITY
var final_rotation: Quaternion = Quaternion.IDENTITY
var scale: Vector3 = Vector3.ONE

## Timing
var assembly_time: float = 1.0  ## Seconds to assemble this part

## Effects
var particle_type: String = ""
var particle_intensity: float = 1.0
var sound_effect: String = ""


func _init() -> void:
	pass


## Initialize part with basic properties.
func initialize(p_id: String, p_name: String, p_assembly_time: float = 1.0) -> void:
	part_id = p_id
	part_name = p_name
	assembly_time = p_assembly_time


## Set position data.
func set_positions(start: Vector3, final: Vector3) -> void:
	start_position = start
	final_position = final


## Set rotation data.
func set_rotations(start: Quaternion, final: Quaternion) -> void:
	start_rotation = start
	final_rotation = final


## Set rotation from euler angles.
func set_rotations_euler(start_euler: Vector3, final_euler: Vector3) -> void:
	start_rotation = Quaternion.from_euler(start_euler)
	final_rotation = Quaternion.from_euler(final_euler)


## Set visual resources.
func set_visuals(p_mesh: String, p_material: String = "") -> void:
	mesh = p_mesh
	material = p_material


## Set effects.
func set_effects(p_particle_type: String, p_intensity: float = 1.0, p_sound: String = "") -> void:
	particle_type = p_particle_type
	particle_intensity = p_intensity
	sound_effect = p_sound


## Get interpolated position at progress (0.0 to 1.0).
func get_position_at(progress: float) -> Vector3:
	return start_position.lerp(final_position, clampf(progress, 0.0, 1.0))


## Get interpolated rotation at progress.
func get_rotation_at(progress: float) -> Quaternion:
	return start_rotation.slerp(final_rotation, clampf(progress, 0.0, 1.0))


## Serialization.
func to_dict() -> Dictionary:
	return {
		"part_id": part_id,
		"part_name": part_name,
		"mesh": mesh,
		"material": material,
		"start_position": _vec3_to_dict(start_position),
		"final_position": _vec3_to_dict(final_position),
		"start_rotation": _quat_to_dict(start_rotation),
		"final_rotation": _quat_to_dict(final_rotation),
		"scale": _vec3_to_dict(scale),
		"assembly_time": assembly_time,
		"particle_type": particle_type,
		"particle_intensity": particle_intensity,
		"sound_effect": sound_effect
	}


func from_dict(data: Dictionary) -> void:
	part_id = data.get("part_id", "")
	part_name = data.get("part_name", "")
	mesh = data.get("mesh", "")
	material = data.get("material", "")
	assembly_time = data.get("assembly_time", 1.0)
	particle_type = data.get("particle_type", "")
	particle_intensity = data.get("particle_intensity", 1.0)
	sound_effect = data.get("sound_effect", "")

	start_position = _dict_to_vec3(data.get("start_position", {}))
	final_position = _dict_to_vec3(data.get("final_position", {}))
	start_rotation = _dict_to_quat(data.get("start_rotation", {}))
	final_rotation = _dict_to_quat(data.get("final_rotation", {}))
	scale = _dict_to_vec3(data.get("scale", {"x": 1, "y": 1, "z": 1}))


## Helper functions.
func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func _dict_to_vec3(d: Dictionary) -> Vector3:
	return Vector3(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0))


func _quat_to_dict(q: Quaternion) -> Dictionary:
	return {"x": q.x, "y": q.y, "z": q.z, "w": q.w}


func _dict_to_quat(d: Dictionary) -> Quaternion:
	if d.is_empty():
		return Quaternion.IDENTITY
	return Quaternion(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0), d.get("w", 1.0))


## Create from JSON data.
static func from_json(data: Dictionary) -> AssemblyPart:
	var part := AssemblyPart.new()

	part.part_id = data.get("part_id", "")
	part.part_name = data.get("part_name", "")
	part.mesh = data.get("mesh", "")
	part.material = data.get("material", "")
	part.assembly_time = data.get("assembly_time", 1.0)
	part.particle_type = data.get("particle_type", "")
	part.particle_intensity = data.get("particle_intensity", 1.0)
	part.sound_effect = data.get("sound_effect", "")

	# Handle position arrays [x, y, z]
	if data.has("start_position"):
		var sp = data["start_position"]
		if sp is Array and sp.size() >= 3:
			part.start_position = Vector3(sp[0], sp[1], sp[2])
		elif sp is Dictionary:
			part.start_position = part._dict_to_vec3(sp)

	if data.has("final_position"):
		var fp = data["final_position"]
		if fp is Array and fp.size() >= 3:
			part.final_position = Vector3(fp[0], fp[1], fp[2])
		elif fp is Dictionary:
			part.final_position = part._dict_to_vec3(fp)

	# Handle rotation arrays [x, y, z, w] or euler [x, y, z]
	if data.has("start_rotation"):
		var sr = data["start_rotation"]
		if sr is Array:
			if sr.size() >= 4:
				part.start_rotation = Quaternion(sr[0], sr[1], sr[2], sr[3])
			elif sr.size() >= 3:
				part.start_rotation = Quaternion.from_euler(Vector3(sr[0], sr[1], sr[2]))
		elif sr is Dictionary:
			part.start_rotation = part._dict_to_quat(sr)

	if data.has("final_rotation"):
		var fr = data["final_rotation"]
		if fr is Array:
			if fr.size() >= 4:
				part.final_rotation = Quaternion(fr[0], fr[1], fr[2], fr[3])
			elif fr.size() >= 3:
				part.final_rotation = Quaternion.from_euler(Vector3(fr[0], fr[1], fr[2]))
		elif fr is Dictionary:
			part.final_rotation = part._dict_to_quat(fr)

	if data.has("scale"):
		var s = data["scale"]
		if s is Array and s.size() >= 3:
			part.scale = Vector3(s[0], s[1], s[2])
		elif s is Dictionary:
			part.scale = part._dict_to_vec3(s)

	return part


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"id": part_id,
		"name": part_name,
		"assembly_time": assembly_time,
		"has_mesh": not mesh.is_empty(),
		"has_effects": not particle_type.is_empty()
	}
