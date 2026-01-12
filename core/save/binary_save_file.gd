class_name BinarySaveFile
extends RefCounted
## BinarySaveFile handles reading and writing binary save files with compression.
## Provides low-level file I/O operations for the save system.

signal write_progress(bytes_written: int, total_bytes: int)
signal read_progress(bytes_read: int, total_bytes: int)

## Error codes for save operations
enum SaveError {
	OK = 0,
	FILE_NOT_FOUND = 1,
	INVALID_MAGIC = 2,
	VERSION_MISMATCH = 3,
	CHECKSUM_FAILED = 4,
	DECOMPRESSION_FAILED = 5,
	COMPRESSION_FAILED = 6,
	FILE_TOO_LARGE = 7,
	DISK_FULL = 8,
	PERMISSION_DENIED = 9,
	CORRUPTED_DATA = 10,
	UNKNOWN_ERROR = 99
}

var _last_error: int = SaveError.OK
var _last_error_message: String = ""


## Get the last error code
func get_last_error() -> int:
	return _last_error


## Get the last error message
func get_last_error_message() -> String:
	return _last_error_message


## Set error state
func _set_error(code: int, message: String = "") -> void:
	_last_error = code
	_last_error_message = message
	if code != SaveError.OK:
		push_error("BinarySaveFile: %s (code %d)" % [message, code])


## Clear error state
func _clear_error() -> void:
	_last_error = SaveError.OK
	_last_error_message = ""


## Ensure save directory exists
func _ensure_save_directory() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		_set_error(SaveError.PERMISSION_DENIED, "Cannot access user directory")
		return false

	if not dir.dir_exists("saves"):
		var err := dir.make_dir("saves")
		if err != OK:
			_set_error(SaveError.PERMISSION_DENIED, "Cannot create saves directory")
			return false

	return true


## Compress data using zlib
func compress_data(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()

	var compressed := data.compress(FileAccess.COMPRESSION_DEFLATE)
	if compressed.is_empty() and not data.is_empty():
		_set_error(SaveError.COMPRESSION_FAILED, "Failed to compress data")
		return PackedByteArray()

	return compressed


## Decompress data using zlib
func decompress_data(data: PackedByteArray, expected_size: int) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()

	var decompressed := data.decompress(expected_size, FileAccess.COMPRESSION_DEFLATE)
	if decompressed.is_empty() and expected_size > 0:
		_set_error(SaveError.DECOMPRESSION_FAILED, "Failed to decompress data")
		return PackedByteArray()

	return decompressed


## Write complete save file
func write_save_file(
	path: String,
	metadata: SaveFormat.SaveMetadata,
	snapshot_data: Dictionary,
	delta_data: Array[Dictionary] = [],
	voxel_chunks: Array[Dictionary] = []
) -> bool:
	_clear_error()

	if not _ensure_save_directory():
		return false

	# Serialize all data first to calculate sizes
	var metadata_bytes := _serialize_dictionary(metadata.to_dict())
	var snapshot_bytes := _serialize_dictionary(snapshot_data)

	var delta_bytes_list: Array[PackedByteArray] = []
	for delta in delta_data:
		delta_bytes_list.append(_serialize_dictionary(delta))

	var voxel_bytes_list: Array[PackedByteArray] = []
	for chunk in voxel_chunks:
		voxel_bytes_list.append(_serialize_dictionary(chunk))

	# Calculate total uncompressed size
	var total_size := metadata_bytes.size() + snapshot_bytes.size()
	for d in delta_bytes_list:
		total_size += d.size()
	for v in voxel_bytes_list:
		total_size += v.size()

	if total_size > SaveFormat.MAX_SECTION_SIZE:
		_set_error(SaveError.FILE_TOO_LARGE, "Save data exceeds maximum size")
		return false

	# Compress sections
	var compressed_metadata := compress_data(metadata_bytes)
	var compressed_snapshot := compress_data(snapshot_bytes)

	var compressed_deltas: Array[PackedByteArray] = []
	for d in delta_bytes_list:
		compressed_deltas.append(compress_data(d))

	var compressed_voxels: Array[PackedByteArray] = []
	for v in voxel_bytes_list:
		compressed_voxels.append(compress_data(v))

	if _last_error != SaveError.OK:
		return false

	# Build header
	var header := SaveFormat.SaveHeader.new()
	header.set_flag(SaveFormat.SaveFlags.COMPRESSED, true)
	header.set_flag(SaveFormat.SaveFlags.CHECKSUMMED, true)
	header.set_flag(SaveFormat.SaveFlags.HAS_SNAPSHOT, not snapshot_data.is_empty())
	header.set_flag(SaveFormat.SaveFlags.HAS_DELTAS, not delta_data.is_empty())
	header.set_flag(SaveFormat.SaveFlags.HAS_VOXELS, not voxel_chunks.is_empty())
	header.delta_count = delta_data.size()
	header.metadata_offset = SaveFormat.HEADER_SIZE
	header.snapshot_offset = header.metadata_offset + SaveFormat.SectionHeader.SIZE + compressed_metadata.size()

	# Calculate checksum of all data
	var all_data := PackedByteArray()
	all_data.append_array(compressed_metadata)
	all_data.append_array(compressed_snapshot)
	for d in compressed_deltas:
		all_data.append_array(d)
	for v in compressed_voxels:
		all_data.append_array(v)
	header.checksum = SaveFormat.calculate_crc32(all_data)

	# Open file for writing
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		if err == ERR_FILE_NO_PERMISSION:
			_set_error(SaveError.PERMISSION_DENIED, "No permission to write file")
		else:
			_set_error(SaveError.UNKNOWN_ERROR, "Cannot open file for writing: %d" % err)
		return false

	var bytes_written := 0
	var total_bytes := SaveFormat.HEADER_SIZE + all_data.size() + (2 + delta_data.size() + voxel_chunks.size()) * SaveFormat.SectionHeader.SIZE

	# Write header
	file.store_buffer(header.to_bytes())
	bytes_written += SaveFormat.HEADER_SIZE
	write_progress.emit(bytes_written, total_bytes)

	# Write metadata section
	if not _write_section(file, SaveFormat.SectionType.METADATA, metadata_bytes, compressed_metadata):
		file.close()
		return false
	bytes_written += SaveFormat.SectionHeader.SIZE + compressed_metadata.size()
	write_progress.emit(bytes_written, total_bytes)

	# Write snapshot section
	if not _write_section(file, SaveFormat.SectionType.SNAPSHOT, snapshot_bytes, compressed_snapshot):
		file.close()
		return false
	bytes_written += SaveFormat.SectionHeader.SIZE + compressed_snapshot.size()
	write_progress.emit(bytes_written, total_bytes)

	# Write delta sections
	for i in range(delta_bytes_list.size()):
		if not _write_section(file, SaveFormat.SectionType.DELTA, delta_bytes_list[i], compressed_deltas[i]):
			file.close()
			return false
		bytes_written += SaveFormat.SectionHeader.SIZE + compressed_deltas[i].size()
		write_progress.emit(bytes_written, total_bytes)

	# Write voxel chunk sections
	for i in range(voxel_bytes_list.size()):
		if not _write_section(file, SaveFormat.SectionType.VOXEL_CHUNK, voxel_bytes_list[i], compressed_voxels[i]):
			file.close()
			return false
		bytes_written += SaveFormat.SectionHeader.SIZE + compressed_voxels[i].size()
		write_progress.emit(bytes_written, total_bytes)

	# Write end of file marker
	var eof_header := SaveFormat.SectionHeader.new()
	eof_header.section_type = SaveFormat.SectionType.END_OF_FILE
	file.store_buffer(eof_header.to_bytes())

	file.close()

	# Verify file size
	var file_size := FileAccess.open(path, FileAccess.READ).get_length() if FileAccess.file_exists(path) else 0
	if file_size > SaveFormat.MAX_FILE_SIZE:
		push_warning("BinarySaveFile: Save file exceeds recommended size (%d > %d)" % [file_size, SaveFormat.MAX_FILE_SIZE])

	return true


## Write a section to file
func _write_section(file: FileAccess, section_type: int, uncompressed: PackedByteArray, compressed: PackedByteArray) -> bool:
	var section_header := SaveFormat.SectionHeader.new()
	section_header.section_type = section_type
	section_header.compression = SaveFormat.CompressionType.ZLIB
	section_header.uncompressed_size = uncompressed.size()
	section_header.compressed_size = compressed.size()
	section_header.checksum = SaveFormat.calculate_crc32(uncompressed)

	file.store_buffer(section_header.to_bytes())
	file.store_buffer(compressed)

	return true


## Read complete save file
func read_save_file(path: String) -> Dictionary:
	_clear_error()

	var result := {
		"success": false,
		"header": null,
		"metadata": null,
		"snapshot": {},
		"deltas": [],
		"voxel_chunks": []
	}

	if not FileAccess.file_exists(path):
		_set_error(SaveError.FILE_NOT_FOUND, "Save file not found: %s" % path)
		return result

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_error(SaveError.PERMISSION_DENIED, "Cannot open file for reading")
		return result

	var file_size := file.get_length()
	var bytes_read := 0

	# Read header
	var header_bytes := file.get_buffer(SaveFormat.HEADER_SIZE)
	if header_bytes.size() < SaveFormat.HEADER_SIZE:
		_set_error(SaveError.CORRUPTED_DATA, "File too small for header")
		file.close()
		return result

	var header := SaveFormat.SaveHeader.new()
	if not header.from_bytes(header_bytes):
		_set_error(SaveError.INVALID_MAGIC, "Invalid save file magic number")
		file.close()
		return result

	if header.version > SaveFormat.FORMAT_VERSION:
		_set_error(SaveError.VERSION_MISMATCH, "Save file version %d is newer than supported %d" % [header.version, SaveFormat.FORMAT_VERSION])
		file.close()
		return result

	result["header"] = header
	bytes_read += SaveFormat.HEADER_SIZE
	read_progress.emit(bytes_read, file_size)

	# Read sections until EOF
	var all_compressed_data := PackedByteArray()

	while file.get_position() < file_size:
		var section_header_bytes := file.get_buffer(SaveFormat.SectionHeader.SIZE)
		if section_header_bytes.size() < SaveFormat.SectionHeader.SIZE:
			break

		var section_header := SaveFormat.SectionHeader.new()
		if not section_header.from_bytes(section_header_bytes):
			_set_error(SaveError.CORRUPTED_DATA, "Invalid section header")
			file.close()
			return result

		if section_header.section_type == SaveFormat.SectionType.END_OF_FILE:
			break

		# Read section data
		var compressed_data := file.get_buffer(section_header.compressed_size)
		if compressed_data.size() != section_header.compressed_size:
			_set_error(SaveError.CORRUPTED_DATA, "Incomplete section data")
			file.close()
			return result

		all_compressed_data.append_array(compressed_data)

		# Decompress data
		var decompressed := decompress_data(compressed_data, section_header.uncompressed_size)
		if decompressed.is_empty() and section_header.uncompressed_size > 0:
			file.close()
			return result

		# Verify section checksum
		var actual_checksum := SaveFormat.calculate_crc32(decompressed)
		if actual_checksum != section_header.checksum:
			_set_error(SaveError.CHECKSUM_FAILED, "Section checksum mismatch")
			file.close()
			return result

		# Deserialize based on section type
		var section_data := _deserialize_dictionary(decompressed)

		match section_header.section_type:
			SaveFormat.SectionType.METADATA:
				var metadata := SaveFormat.SaveMetadata.new()
				metadata.from_dict(section_data)
				result["metadata"] = metadata
			SaveFormat.SectionType.SNAPSHOT:
				result["snapshot"] = section_data
			SaveFormat.SectionType.DELTA:
				result["deltas"].append(section_data)
			SaveFormat.SectionType.VOXEL_CHUNK:
				result["voxel_chunks"].append(section_data)

		bytes_read += SaveFormat.SectionHeader.SIZE + compressed_data.size()
		read_progress.emit(bytes_read, file_size)

	file.close()

	# Verify overall checksum if checksummed flag is set
	if header.has_flag(SaveFormat.SaveFlags.CHECKSUMMED):
		var calculated_checksum := SaveFormat.calculate_crc32(all_compressed_data)
		if calculated_checksum != header.checksum:
			_set_error(SaveError.CHECKSUM_FAILED, "File checksum mismatch")
			return result

	result["success"] = true
	return result


## Read only header and metadata (fast operation for listings)
func read_save_info(path: String) -> Dictionary:
	_clear_error()

	var result := {
		"success": false,
		"header": null,
		"metadata": null
	}

	if not FileAccess.file_exists(path):
		_set_error(SaveError.FILE_NOT_FOUND, "Save file not found")
		return result

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_error(SaveError.PERMISSION_DENIED, "Cannot open file for reading")
		return result

	# Read header
	var header_bytes := file.get_buffer(SaveFormat.HEADER_SIZE)
	if header_bytes.size() < SaveFormat.HEADER_SIZE:
		_set_error(SaveError.CORRUPTED_DATA, "File too small for header")
		file.close()
		return result

	var header := SaveFormat.SaveHeader.new()
	if not header.from_bytes(header_bytes):
		_set_error(SaveError.INVALID_MAGIC, "Invalid save file magic number")
		file.close()
		return result

	result["header"] = header

	# Read metadata section
	var section_header_bytes := file.get_buffer(SaveFormat.SectionHeader.SIZE)
	if section_header_bytes.size() < SaveFormat.SectionHeader.SIZE:
		_set_error(SaveError.CORRUPTED_DATA, "No metadata section")
		file.close()
		return result

	var section_header := SaveFormat.SectionHeader.new()
	if not section_header.from_bytes(section_header_bytes):
		_set_error(SaveError.CORRUPTED_DATA, "Invalid section header")
		file.close()
		return result

	if section_header.section_type != SaveFormat.SectionType.METADATA:
		_set_error(SaveError.CORRUPTED_DATA, "First section is not metadata")
		file.close()
		return result

	var compressed_data := file.get_buffer(section_header.compressed_size)
	file.close()

	var decompressed := decompress_data(compressed_data, section_header.uncompressed_size)
	if decompressed.is_empty() and section_header.uncompressed_size > 0:
		return result

	var section_data := _deserialize_dictionary(decompressed)
	var metadata := SaveFormat.SaveMetadata.new()
	metadata.from_dict(section_data)

	result["metadata"] = metadata
	result["success"] = true

	return result


## Serialize dictionary to bytes using Godot's var_to_bytes
func _serialize_dictionary(data: Dictionary) -> PackedByteArray:
	return var_to_bytes(data)


## Deserialize bytes to dictionary using Godot's bytes_to_var
func _deserialize_dictionary(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}

	var result = bytes_to_var(data)
	if result is Dictionary:
		return result

	_set_error(SaveError.CORRUPTED_DATA, "Failed to deserialize dictionary")
	return {}


## Delete a save file
func delete_save_file(path: String) -> bool:
	_clear_error()

	if not FileAccess.file_exists(path):
		_set_error(SaveError.FILE_NOT_FOUND, "Save file not found")
		return false

	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		_set_error(SaveError.PERMISSION_DENIED, "Cannot access directory")
		return false

	var err := dir.remove(path.get_file())
	if err != OK:
		_set_error(SaveError.PERMISSION_DENIED, "Cannot delete file")
		return false

	return true


## Get file size in bytes
func get_file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1

	var size := file.get_length()
	file.close()
	return size
