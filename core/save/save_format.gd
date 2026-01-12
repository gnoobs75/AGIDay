class_name SaveFormat
extends RefCounted
## SaveFormat defines constants and structures for the binary save file format.
## File Structure:
##   [Header Section]       - Magic number, version, flags, checksum
##   [Metadata Section]     - Game state metadata (faction, wave, etc.)
##   [Snapshot Section]     - Latest complete game state snapshot
##   [Delta Sections]       - Incremental changes since snapshot
##   [Voxel Chunks Section] - Compressed voxel world data

## Magic number identifying AGI Day save files
const MAGIC_NUMBER: PackedByteArray = [0x41, 0x47, 0x49, 0x44]  # "AGID"

## Current save format version
const FORMAT_VERSION: int = 1

## Section type identifiers
enum SectionType {
	HEADER = 0x01,
	METADATA = 0x02,
	SNAPSHOT = 0x03,
	DELTA = 0x04,
	VOXEL_CHUNK = 0x05,
	ENTITY_DATA = 0x06,
	COMPONENT_DATA = 0x07,
	END_OF_FILE = 0xFF
}

## Compression type flags
enum CompressionType {
	NONE = 0x00,
	ZLIB = 0x01,
	GZIP = 0x02
}

## Save file flags (bitfield)
enum SaveFlags {
	NONE = 0x00,
	COMPRESSED = 0x01,
	HAS_SNAPSHOT = 0x02,
	HAS_DELTAS = 0x04,
	HAS_VOXELS = 0x08,
	CHECKSUMMED = 0x10
}

## Header structure size in bytes (fixed)
const HEADER_SIZE: int = 32

## Maximum section size (500MB uncompressed)
const MAX_SECTION_SIZE: int = 500 * 1024 * 1024

## Maximum save file size on disk (50MB compressed)
const MAX_FILE_SIZE: int = 50 * 1024 * 1024

## Default compression level for zlib (1-9, higher = better compression)
const DEFAULT_COMPRESSION_LEVEL: int = 6

## Save file extension
const FILE_EXTENSION: String = ".agisave"

## Autosave file prefix
const AUTOSAVE_PREFIX: String = "autosave_"

## Quicksave file name
const QUICKSAVE_NAME: String = "quicksave"


## Header structure for save files
class SaveHeader:
	var magic: PackedByteArray = MAGIC_NUMBER.duplicate()
	var version: int = FORMAT_VERSION
	var flags: int = SaveFlags.NONE
	var timestamp: int = 0
	var checksum: int = 0
	var metadata_offset: int = 0
	var snapshot_offset: int = 0
	var delta_count: int = 0
	var reserved: PackedByteArray = PackedByteArray()

	func _init() -> void:
		timestamp = int(Time.get_unix_time_from_system())
		reserved.resize(8)  # Reserved bytes for future use


	func to_bytes() -> PackedByteArray:
		var buffer := PackedByteArray()
		buffer.append_array(magic)                              # 4 bytes
		buffer.encode_u16(4, version)                           # 2 bytes
		buffer.resize(6)
		buffer.encode_u16(6, flags)                             # 2 bytes
		buffer.resize(8)
		buffer.encode_s64(8, timestamp)                         # 8 bytes
		buffer.resize(16)
		buffer.encode_u32(16, checksum)                         # 4 bytes
		buffer.resize(20)
		buffer.encode_u32(20, metadata_offset)                  # 4 bytes
		buffer.resize(24)
		buffer.encode_u32(24, snapshot_offset)                  # 4 bytes
		buffer.resize(28)
		buffer.encode_u16(28, delta_count)                      # 2 bytes
		buffer.resize(30)
		buffer.append_array(reserved)                           # 8 bytes (padding to 32)
		buffer.resize(HEADER_SIZE)
		return buffer


	func from_bytes(buffer: PackedByteArray) -> bool:
		if buffer.size() < HEADER_SIZE:
			return false

		magic = buffer.slice(0, 4)
		if magic != MAGIC_NUMBER:
			return false

		version = buffer.decode_u16(4)
		flags = buffer.decode_u16(6)
		timestamp = buffer.decode_s64(8)
		checksum = buffer.decode_u32(16)
		metadata_offset = buffer.decode_u32(20)
		snapshot_offset = buffer.decode_u32(24)
		delta_count = buffer.decode_u16(28)
		reserved = buffer.slice(30, 38)

		return true


	func has_flag(flag: int) -> bool:
		return (flags & flag) != 0


	func set_flag(flag: int, value: bool) -> void:
		if value:
			flags |= flag
		else:
			flags &= ~flag


## Metadata structure for game state
class SaveMetadata:
	var save_name: String = ""
	var player_faction: int = 0
	var current_wave: int = 0
	var difficulty: int = 0
	var game_time_seconds: float = 0.0
	var entity_count: int = 0
	var play_time_seconds: float = 0.0
	var created_timestamp: int = 0
	var modified_timestamp: int = 0
	var custom_data: Dictionary = {}

	func _init() -> void:
		var now := int(Time.get_unix_time_from_system())
		created_timestamp = now
		modified_timestamp = now


	func to_dict() -> Dictionary:
		return {
			"save_name": save_name,
			"player_faction": player_faction,
			"current_wave": current_wave,
			"difficulty": difficulty,
			"game_time_seconds": game_time_seconds,
			"entity_count": entity_count,
			"play_time_seconds": play_time_seconds,
			"created_timestamp": created_timestamp,
			"modified_timestamp": modified_timestamp,
			"custom_data": custom_data
		}


	func from_dict(data: Dictionary) -> void:
		save_name = data.get("save_name", "")
		player_faction = data.get("player_faction", 0)
		current_wave = data.get("current_wave", 0)
		difficulty = data.get("difficulty", 0)
		game_time_seconds = data.get("game_time_seconds", 0.0)
		entity_count = data.get("entity_count", 0)
		play_time_seconds = data.get("play_time_seconds", 0.0)
		created_timestamp = data.get("created_timestamp", 0)
		modified_timestamp = data.get("modified_timestamp", int(Time.get_unix_time_from_system()))
		custom_data = data.get("custom_data", {})


## Section header for variable-length sections
class SectionHeader:
	var section_type: int = SectionType.END_OF_FILE
	var compression: int = CompressionType.ZLIB
	var uncompressed_size: int = 0
	var compressed_size: int = 0
	var checksum: int = 0

	const SIZE: int = 16  # Section header is 16 bytes

	func to_bytes() -> PackedByteArray:
		var buffer := PackedByteArray()
		buffer.resize(SIZE)
		buffer.encode_u8(0, section_type)
		buffer.encode_u8(1, compression)
		buffer.encode_u32(4, uncompressed_size)
		buffer.encode_u32(8, compressed_size)
		buffer.encode_u32(12, checksum)
		return buffer


	func from_bytes(buffer: PackedByteArray) -> bool:
		if buffer.size() < SIZE:
			return false

		section_type = buffer.decode_u8(0)
		compression = buffer.decode_u8(1)
		uncompressed_size = buffer.decode_u32(4)
		compressed_size = buffer.decode_u32(8)
		checksum = buffer.decode_u32(12)
		return true


## Voxel chunk header for voxel data sections
class VoxelChunkHeader:
	var chunk_x: int = 0
	var chunk_y: int = 0
	var chunk_z: int = 0
	var data_size: int = 0
	var is_empty: bool = false

	const SIZE: int = 16

	func to_bytes() -> PackedByteArray:
		var buffer := PackedByteArray()
		buffer.resize(SIZE)
		buffer.encode_s32(0, chunk_x)
		buffer.encode_s32(4, chunk_y)
		buffer.encode_s32(8, chunk_z)
		buffer.encode_u32(12, data_size)
		buffer.encode_u8(15, 1 if is_empty else 0)
		return buffer


	func from_bytes(buffer: PackedByteArray) -> bool:
		if buffer.size() < SIZE:
			return false

		chunk_x = buffer.decode_s32(0)
		chunk_y = buffer.decode_s32(4)
		chunk_z = buffer.decode_s32(8)
		data_size = buffer.decode_u32(12)
		is_empty = buffer.decode_u8(15) != 0
		return true


## Calculate CRC32 checksum for data
static func calculate_crc32(data: PackedByteArray) -> int:
	# CRC32 polynomial table
	var table: Array[int] = []
	for i in range(256):
		var crc := i
		for _j in range(8):
			if crc & 1:
				crc = (crc >> 1) ^ 0xEDB88320
			else:
				crc >>= 1
		table.append(crc)

	var crc: int = 0xFFFFFFFF
	for byte in data:
		crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8)

	return crc ^ 0xFFFFFFFF


## Get save directory path
static func get_save_directory() -> String:
	return "user://saves/"


## Get full path for a save file
static func get_save_path(save_name: String) -> String:
	var dir := get_save_directory()
	if not save_name.ends_with(FILE_EXTENSION):
		save_name += FILE_EXTENSION
	return dir + save_name


## Validate a save file name
static func is_valid_save_name(name: String) -> bool:
	if name.is_empty():
		return false

	# Check for invalid characters
	var invalid_chars := ['/', '\\', ':', '*', '?', '"', '<', '>', '|']
	for c in invalid_chars:
		if name.contains(str(c)):
			return false

	# Check length
	if name.length() > 64:
		return false

	return true


## Format timestamp as readable string
static func format_timestamp(timestamp: int) -> String:
	var datetime := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year,
		datetime.month,
		datetime.day,
		datetime.hour,
		datetime.minute,
		datetime.second
	]


## Format play time as readable string
static func format_play_time(seconds: float) -> String:
	var hours := int(seconds / 3600)
	var minutes := int(fmod(seconds, 3600) / 60)
	var secs := int(fmod(seconds, 60))

	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	else:
		return "%d:%02d" % [minutes, secs]
