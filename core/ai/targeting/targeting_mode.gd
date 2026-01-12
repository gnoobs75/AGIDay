class_name TargetingMode
extends RefCounted
## TargetingMode defines targeting behavior evolution based on XP.

## Targeting modes
enum Mode {
	NEAREST,       ## 0-1,000 XP: Simple closest enemy
	THREAT_BASED,  ## 1,000-5,000 XP: Considers threat level
	PRIORITY       ## 5,000+ XP: Strategic priority targeting
}

## XP thresholds
const XP_NEAREST_MAX := 1000.0
const XP_THREAT_MIN := 1000.0
const XP_THREAT_MAX := 5000.0
const XP_PRIORITY_MIN := 5000.0

## Current mode
var mode: int = Mode.NEAREST

## Blend progress (0.0 to 1.0)
var blend_progress: float = 0.0

## Previous mode for blending
var previous_mode: int = Mode.NEAREST

## Mode weights for blending
var nearest_weight: float = 1.0
var threat_weight: float = 0.0
var priority_weight: float = 0.0


func _init() -> void:
	pass


## Update targeting mode based on faction XP.
func update_from_xp(faction_xp: float) -> void:
	var old_mode := mode

	if faction_xp < XP_NEAREST_MAX:
		# Pure nearest mode
		mode = Mode.NEAREST
		blend_progress = 0.0
		nearest_weight = 1.0
		threat_weight = 0.0
		priority_weight = 0.0

	elif faction_xp < XP_THREAT_MIN:
		# Transition to threat mode
		mode = Mode.NEAREST
		blend_progress = faction_xp / XP_THREAT_MIN
		nearest_weight = 1.0 - blend_progress * 0.5
		threat_weight = blend_progress * 0.5
		priority_weight = 0.0

	elif faction_xp < XP_THREAT_MAX:
		# Threat-based mode with progression
		mode = Mode.THREAT_BASED
		blend_progress = (faction_xp - XP_THREAT_MIN) / (XP_THREAT_MAX - XP_THREAT_MIN)
		nearest_weight = 0.5 - blend_progress * 0.3
		threat_weight = 0.5 + blend_progress * 0.2
		priority_weight = blend_progress * 0.1

	elif faction_xp < XP_PRIORITY_MIN:
		# Transition to priority
		mode = Mode.THREAT_BASED
		blend_progress = faction_xp / XP_PRIORITY_MIN
		nearest_weight = 0.2 - blend_progress * 0.1
		threat_weight = 0.7
		priority_weight = 0.1 + blend_progress * 0.1

	else:
		# Full priority mode
		mode = Mode.PRIORITY
		var extra_xp := faction_xp - XP_PRIORITY_MIN
		blend_progress = clampf(extra_xp / 5000.0, 0.0, 1.0)
		nearest_weight = 0.1
		threat_weight = 0.5 - blend_progress * 0.1
		priority_weight = 0.4 + blend_progress * 0.1

	if old_mode != mode:
		previous_mode = old_mode


## Get weight for specific mode.
func get_mode_weight(target_mode: int) -> float:
	match target_mode:
		Mode.NEAREST:
			return nearest_weight
		Mode.THREAT_BASED:
			return threat_weight
		Mode.PRIORITY:
			return priority_weight
	return 0.0


## Check if using pure nearest mode.
func is_pure_nearest() -> bool:
	return mode == Mode.NEAREST and blend_progress < 0.1


## Check if using advanced targeting.
func is_advanced() -> bool:
	return mode == Mode.PRIORITY or (mode == Mode.THREAT_BASED and blend_progress > 0.5)


## Get mode name.
func get_mode_name() -> String:
	return Mode.keys()[mode]


## Serialize to dictionary.
func to_dict() -> Dictionary:
	return {
		"mode": mode,
		"blend_progress": blend_progress,
		"previous_mode": previous_mode,
		"nearest_weight": nearest_weight,
		"threat_weight": threat_weight,
		"priority_weight": priority_weight
	}


## Deserialize from dictionary.
func from_dict(data: Dictionary) -> void:
	mode = data.get("mode", Mode.NEAREST)
	blend_progress = data.get("blend_progress", 0.0)
	previous_mode = data.get("previous_mode", Mode.NEAREST)
	nearest_weight = data.get("nearest_weight", 1.0)
	threat_weight = data.get("threat_weight", 0.0)
	priority_weight = data.get("priority_weight", 0.0)


## Get summary for debugging.
func get_summary() -> Dictionary:
	return {
		"mode": get_mode_name(),
		"blend": "%.0f%%" % (blend_progress * 100),
		"weights": "N:%.2f T:%.2f P:%.2f" % [nearest_weight, threat_weight, priority_weight]
	}
