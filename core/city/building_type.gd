class_name BuildingType
extends RefCounted
## BuildingType defines all building types for city generation.

## Building type enumeration
enum Type {
	SMALL_RESIDENTIAL = 0,   ## Small houses (1x1)
	MEDIUM_RESIDENTIAL = 1,  ## Apartment blocks (2x2)
	LARGE_RESIDENTIAL = 2,   ## High-rise apartments (3x3)
	SMALL_COMMERCIAL = 3,    ## Shops (1x1)
	MEDIUM_COMMERCIAL = 4,   ## Offices (2x2)
	LARGE_COMMERCIAL = 5,    ## Skyscrapers (3x3)
	SMALL_INDUSTRIAL = 6,    ## Workshops (1x1)
	MEDIUM_INDUSTRIAL = 7,   ## Factories (2x2)
	LARGE_INDUSTRIAL = 8,    ## Heavy industry (3x3)
	POWER_STATION = 9,       ## Power generation (2x2)
	POWER_SUBSTATION = 10,   ## Power distribution (1x1)
	REE_EXTRACTOR = 11,      ## REE mining (2x2)
	WAREHOUSE = 12,          ## Storage (2x2)
	ROAD = 13,               ## Road tile (1x1)
	ALLEY = 14,              ## Narrow passage (1x1)
	BOULEVARD = 15,          ## Wide road (2x1)
	PLAZA = 16,              ## Open area (2x2)
	PARK = 17,               ## Green space (2x2)
	EMPTY = 18               ## Empty lot
}

## Get display name.
static func get_name(type: int) -> String:
	match type:
		Type.SMALL_RESIDENTIAL: return "Small Residential"
		Type.MEDIUM_RESIDENTIAL: return "Medium Residential"
		Type.LARGE_RESIDENTIAL: return "Large Residential"
		Type.SMALL_COMMERCIAL: return "Small Commercial"
		Type.MEDIUM_COMMERCIAL: return "Medium Commercial"
		Type.LARGE_COMMERCIAL: return "Large Commercial"
		Type.SMALL_INDUSTRIAL: return "Small Industrial"
		Type.MEDIUM_INDUSTRIAL: return "Medium Industrial"
		Type.LARGE_INDUSTRIAL: return "Large Industrial"
		Type.POWER_STATION: return "Power Station"
		Type.POWER_SUBSTATION: return "Power Substation"
		Type.REE_EXTRACTOR: return "REE Extractor"
		Type.WAREHOUSE: return "Warehouse"
		Type.ROAD: return "Road"
		Type.ALLEY: return "Alley"
		Type.BOULEVARD: return "Boulevard"
		Type.PLAZA: return "Plaza"
		Type.PARK: return "Park"
		Type.EMPTY: return "Empty"
	return "Unknown"


## Get default dimensions.
static func get_dimensions(type: int) -> Vector2i:
	match type:
		Type.SMALL_RESIDENTIAL, Type.SMALL_COMMERCIAL, Type.SMALL_INDUSTRIAL:
			return Vector2i(1, 1)
		Type.MEDIUM_RESIDENTIAL, Type.MEDIUM_COMMERCIAL, Type.MEDIUM_INDUSTRIAL:
			return Vector2i(2, 2)
		Type.LARGE_RESIDENTIAL, Type.LARGE_COMMERCIAL, Type.LARGE_INDUSTRIAL:
			return Vector2i(3, 3)
		Type.POWER_STATION, Type.REE_EXTRACTOR, Type.WAREHOUSE, Type.PLAZA, Type.PARK:
			return Vector2i(2, 2)
		Type.POWER_SUBSTATION, Type.ROAD, Type.ALLEY, Type.EMPTY:
			return Vector2i(1, 1)
		Type.BOULEVARD:
			return Vector2i(2, 1)
	return Vector2i(1, 1)


## Get height in floors.
static func get_height(type: int) -> int:
	match type:
		Type.SMALL_RESIDENTIAL: return 2
		Type.MEDIUM_RESIDENTIAL: return 4
		Type.LARGE_RESIDENTIAL: return 12
		Type.SMALL_COMMERCIAL: return 1
		Type.MEDIUM_COMMERCIAL: return 6
		Type.LARGE_COMMERCIAL: return 20
		Type.SMALL_INDUSTRIAL: return 1
		Type.MEDIUM_INDUSTRIAL: return 2
		Type.LARGE_INDUSTRIAL: return 3
		Type.POWER_STATION: return 2
		Type.POWER_SUBSTATION: return 1
		Type.REE_EXTRACTOR: return 1
		Type.WAREHOUSE: return 2
	return 0


## Get power consumption.
static func get_power_consumption(type: int) -> float:
	match type:
		Type.SMALL_RESIDENTIAL: return 1.0
		Type.MEDIUM_RESIDENTIAL: return 4.0
		Type.LARGE_RESIDENTIAL: return 15.0
		Type.SMALL_COMMERCIAL: return 2.0
		Type.MEDIUM_COMMERCIAL: return 8.0
		Type.LARGE_COMMERCIAL: return 25.0
		Type.SMALL_INDUSTRIAL: return 3.0
		Type.MEDIUM_INDUSTRIAL: return 12.0
		Type.LARGE_INDUSTRIAL: return 40.0
		Type.REE_EXTRACTOR: return 10.0
		Type.WAREHOUSE: return 2.0
	return 0.0


## Get power production.
static func get_power_production(type: int) -> float:
	match type:
		Type.POWER_STATION: return 100.0
		Type.POWER_SUBSTATION: return 0.0  # Distributes, doesn't produce
	return 0.0


## Get REE production.
static func get_ree_production(type: int) -> float:
	match type:
		Type.REE_EXTRACTOR: return 5.0
	return 0.0


## Get compatible zone types.
static func get_compatible_zones(type: int) -> Array[int]:
	match type:
		Type.SMALL_RESIDENTIAL, Type.MEDIUM_RESIDENTIAL, Type.LARGE_RESIDENTIAL:
			return [ZoneType.Type.RESIDENTIAL, ZoneType.Type.MIXED_ZONE]
		Type.SMALL_COMMERCIAL, Type.MEDIUM_COMMERCIAL, Type.LARGE_COMMERCIAL:
			return [ZoneType.Type.COMMERCIAL, ZoneType.Type.MIXED_ZONE]
		Type.SMALL_INDUSTRIAL, Type.MEDIUM_INDUSTRIAL, Type.LARGE_INDUSTRIAL:
			return [ZoneType.Type.INDUSTRIAL]
		Type.POWER_STATION, Type.POWER_SUBSTATION:
			return [ZoneType.Type.POWER_HUB, ZoneType.Type.INDUSTRIAL]
		Type.REE_EXTRACTOR:
			return [ZoneType.Type.INDUSTRIAL]
		Type.WAREHOUSE:
			return [ZoneType.Type.INDUSTRIAL, ZoneType.Type.COMMERCIAL]
		Type.ROAD:
			return ZoneType.get_all_types()
		Type.ALLEY:
			return [ZoneType.Type.ZERG_ALLEY, ZoneType.Type.RESIDENTIAL]
		Type.BOULEVARD:
			return [ZoneType.Type.TANK_BOULEVARD, ZoneType.Type.COMMERCIAL]
		Type.PLAZA, Type.PARK:
			return [ZoneType.Type.MIXED_ZONE, ZoneType.Type.COMMERCIAL, ZoneType.Type.RESIDENTIAL]
		Type.EMPTY:
			return ZoneType.get_all_types()
	return []


## Check if is walkable.
static func is_walkable(type: int) -> bool:
	match type:
		Type.ROAD, Type.ALLEY, Type.BOULEVARD, Type.PLAZA, Type.PARK, Type.EMPTY:
			return true
	return false


## Check if is building.
static func is_building(type: int) -> bool:
	return type <= Type.WAREHOUSE and type != Type.EMPTY


## Get all building types.
static func get_all_types() -> Array[int]:
	var result: Array[int] = []
	for i in range(Type.EMPTY + 1):
		result.append(i)
	return result
